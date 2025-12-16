"""Service for syncing areas from Mountain Project with hierarchy."""
import uuid
import structlog
from typing import Optional
from datetime import datetime
from collections import deque

from sqlalchemy.dialects.mysql import insert
from sqlalchemy import text

from config import get_settings
from db import get_session, Area, SafetyStatus
from clients import MountainProjectScraper

log = structlog.get_logger()


def generate_deterministic_uuid(url: str) -> str:
    """Generate a consistent UUID from a URL using UUIDv5."""
    namespace = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
    return str(uuid.uuid5(namespace, url))


class CragSyncService:
    """Service for syncing hierarchical areas from Mountain Project.

    New approach:
    - Store EVERY area in the hierarchy (not just crags with coordinates)
    - Track parent-child relationships via parent_id
    - Only scrape URLs that haven't been scraped or failed previously
    - Rocks don't move, so we only need to scrape each URL once
    """

    def __init__(self):
        self.settings = get_settings()
        self.scraper = MountainProjectScraper()
        self.stats = {
            "states_processed": 0,
            "areas_processed": 0,
            "areas_upserted": 0,
            "crags_found": 0,
            "skipped_already_scraped": 0,
            "errors": 0,
        }

    def close(self):
        self.scraper.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def _get_urls_to_skip(self) -> set[str]:
        """Get URLs that were already successfully scraped."""
        session = get_session()
        try:
            result = session.execute(
                text("SELECT url FROM ods_areas WHERE scraped_at IS NOT NULL AND scrape_failed = FALSE")
            )
            return {row[0] for row in result.fetchall()}
        finally:
            session.close()

    def sync_all(self, max_areas: Optional[int] = None) -> dict:
        """
        Full sync of all US areas from Mountain Project.

        Stores the complete hierarchy: States -> Regions -> Sub-regions -> Crags
        Each area is stored with its parent_id for tree navigation.

        Args:
            max_areas: Optional limit on number of areas to process

        Returns:
            Stats dictionary
        """
        log.info("area_sync_starting")

        # Get URLs to skip (already successfully scraped)
        already_scraped = self._get_urls_to_skip()
        log.info("urls_already_scraped", count=len(already_scraped))

        # Get US state URLs
        state_urls = self.scraper.get_all_state_urls()
        log.info("states_to_process", count=len(state_urls))

        # Process each state
        for state_name, state_url in state_urls:
            if max_areas and self.stats["areas_processed"] >= max_areas:
                log.info("max_areas_reached", max=max_areas)
                break

            try:
                self._process_state(state_name, state_url, already_scraped, max_areas)
                self.stats["states_processed"] += 1
                log.info("state_complete", state=state_name, **self.stats)

            except Exception as e:
                log.error("state_failed", state=state_name, error=str(e))
                self.stats["errors"] += 1

        log.info("area_sync_complete", **self.stats)
        return self.stats

    def _process_state(
        self,
        state_name: str,
        state_url: str,
        already_scraped: set[str],
        max_areas: Optional[int]
    ):
        """Process a single state using breadth-first search.

        Stores ALL areas in the hierarchy, not just crags with coordinates.
        """
        # First, upsert the state as a root area (no parent)
        state_id = generate_deterministic_uuid(state_url)
        self._upsert_area(
            area_id=state_id,
            name=state_name,
            url=state_url,
            parent_id=None,  # States have no parent
            latitude=None,
            longitude=None,
        )

        # Queue holds (url, parent_id, depth) tuples
        queue: deque[tuple[str, str, int]] = deque()
        queue.append((state_url, state_id, 0))

        max_depth = 10  # Allow deep hierarchies

        while queue:
            if max_areas and self.stats["areas_processed"] >= max_areas:
                break

            url, parent_id, depth = queue.popleft()

            # Skip if too deep
            if depth > max_depth:
                continue

            # Skip if already successfully scraped (but still process children)
            normalized_url = self.scraper._normalize_url(url)
            if normalized_url in already_scraped:
                self.stats["skipped_already_scraped"] += 1
                continue

            try:
                # Single request gets BOTH coordinates AND children
                area, children = self.scraper.get_area_with_children(url)
                self.stats["areas_processed"] += 1

                # Extract area info - even if no coordinates, we store the area
                area_id = generate_deterministic_uuid(url)

                if area:
                    # Area has coordinates - it's a crag
                    # Don't allow self-referential parent_id (happens when state URL is re-processed)
                    actual_parent_id = None if area_id == parent_id else parent_id
                    self._upsert_area(
                        area_id=area_id,
                        name=area.name,
                        url=url,
                        parent_id=actual_parent_id,
                        latitude=area.latitude,
                        longitude=area.longitude,
                    )
                    self.stats["crags_found"] += 1

                # Add children to queue
                for child in children:
                    child_url = self.scraper._normalize_url(child.url)
                    if not self.scraper.was_visited(child_url):
                        # Upsert child area first (may not have coordinates yet)
                        child_id = generate_deterministic_uuid(child_url)
                        self._upsert_area(
                            area_id=child_id,
                            name=child.name,
                            url=child_url,
                            parent_id=area_id if area else parent_id,
                            latitude=None,  # Will be updated when we visit
                            longitude=None,
                        )
                        # Pass the PARENT's ID, not the child's own ID
                        queue.append((child_url, area_id if area else parent_id, depth + 1))

            except Exception as e:
                log.warning("area_failed", url=url, error=str(e))
                # Mark as failed
                self._mark_scrape_failed(url)
                self.stats["errors"] += 1

    def _upsert_area(
        self,
        area_id: str,
        name: str,
        url: str,
        parent_id: Optional[str],
        latitude: Optional[float],
        longitude: Optional[float],
    ) -> bool:
        """Upsert a single area (crag or region)."""
        session = get_session()

        try:
            record = {
                "id": area_id,
                "url": url,
                "name": name,
                "parent_id": parent_id,
                "latitude": latitude,
                "longitude": longitude,
                "scraped_at": datetime.utcnow(),
                "scrape_failed": False,
            }

            # Only set safety_status if this is a crag (has coordinates)
            if latitude is not None and longitude is not None:
                record["safety_status"] = SafetyStatus.UNKNOWN

            stmt = insert(Area).values(**record)
            upsert_stmt = stmt.on_duplicate_key_update(
                name=stmt.inserted.name,
                parent_id=stmt.inserted.parent_id,
                latitude=stmt.inserted.latitude,
                longitude=stmt.inserted.longitude,
                scraped_at=stmt.inserted.scraped_at,
                scrape_failed=stmt.inserted.scrape_failed,
            )

            session.execute(upsert_stmt)
            session.commit()
            self.stats["areas_upserted"] += 1

            log.info("area_upserted", name=name, url=url, has_coords=latitude is not None, parent_id=parent_id)
            return True

        except Exception as e:
            session.rollback()
            log.error("area_upsert_failed", url=url, error=str(e), error_type=type(e).__name__)
            return False
        finally:
            session.close()

    def _mark_scrape_failed(self, url: str):
        """Mark an area as failed to scrape (for retry later)."""
        session = get_session()
        try:
            area_id = generate_deterministic_uuid(url)
            session.execute(
                text(f"UPDATE ods_areas SET scrape_failed = TRUE WHERE id = '{area_id}'")
            )
            session.commit()
        except Exception:
            session.rollback()
        finally:
            session.close()

    def sync_failed(self) -> dict:
        """Retry scraping areas that failed previously."""
        log.info("retrying_failed_areas")

        session = get_session()
        try:
            result = session.execute(
                text("SELECT url FROM ods_areas WHERE scrape_failed = TRUE")
            )
            failed_urls = [row[0] for row in result.fetchall()]
        finally:
            session.close()

        log.info("failed_urls_to_retry", count=len(failed_urls))

        for url in failed_urls:
            try:
                area, _ = self.scraper.get_area_with_children(url)
                if area:
                    self._upsert_area(
                        area_id=generate_deterministic_uuid(url),
                        name=area.name,
                        url=url,
                        parent_id=None,  # Keep existing parent
                        latitude=area.latitude,
                        longitude=area.longitude,
                    )
            except Exception as e:
                log.warning("retry_failed", url=url, error=str(e))

        return self.stats
