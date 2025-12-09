"""Service for syncing crags from Mountain Project."""
import uuid
import time
import structlog
from typing import Optional

from sqlalchemy.dialects.mysql import insert

from config import get_settings
from db import get_session, Crag
from clients import MountainProjectScraper

log = structlog.get_logger()


def generate_deterministic_uuid(url: str) -> str:
    """Generate a consistent UUID from a URL using UUIDv5."""
    namespace = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
    return str(uuid.uuid5(namespace, url))


def build_location_hierarchy(path: list[str]) -> dict:
    """Convert path list to nested hierarchy dict."""
    if not path:
        return {}

    result = None
    for name in reversed(path):
        result = {"name": name, "child": result}

    return result or {}


class CragSyncService:
    """Service for synchronizing crags from Mountain Project."""

    def __init__(self):
        self.settings = get_settings()
        self.scraper = MountainProjectScraper()
        self.stats = {
            "states_processed": 0,
            "areas_processed": 0,
            "crags_found": 0,
            "crags_upserted": 0,
            "errors": 0,
        }

    def close(self):
        self.scraper.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def sync_all(self, max_areas: Optional[int] = None) -> dict:
        """
        Full sync of all areas from Mountain Project.

        Processes and saves crags as it goes - no waiting for full collection.

        Args:
            max_areas: Optional limit on number of areas to process

        Returns:
            Stats dictionary
        """
        log.info("crag_sync_starting")

        # Get all state/region URLs
        state_urls = self.scraper.get_all_state_urls()
        log.info("states_to_process", count=len(state_urls))

        total_areas_processed = 0

        # Process each state and save crags immediately
        for state_name, state_url in state_urls:
            if max_areas and total_areas_processed >= max_areas:
                log.info("max_areas_reached", max=max_areas)
                break

            try:
                # Get areas for this state
                areas = self.scraper.get_areas_from_listing(state_url)
                log.info("state_areas_found", state=state_name, areas=len(areas))

                # Process this state's areas immediately (stream processing)
                batch = []
                for area in areas:
                    if max_areas and total_areas_processed >= max_areas:
                        break

                    try:
                        found = self._process_area_recursive(area.url, batch, max_depth=3)
                        total_areas_processed += 1

                        # Save batch when it reaches threshold
                        if len(batch) >= self.settings.batch_size:
                            self._upsert_batch(batch)
                            batch = []

                    except Exception as e:
                        log.error("area_failed", url=area.url, error=str(e))
                        self.stats["errors"] += 1

                # Save remaining batch for this state
                if batch:
                    self._upsert_batch(batch)

                self.stats["states_processed"] += 1
                log.info("state_complete", state=state_name, **self.stats)

                time.sleep(self.settings.request_delay_seconds)

            except Exception as e:
                log.error("state_failed", state=state_name, error=str(e))
                self.stats["errors"] += 1

        log.info("crag_sync_complete", **self.stats)
        return self.stats

    def _process_area_recursive(self, url: str, batch: list, max_depth: int = 3) -> bool:
        """
        Process an area, recursively drilling into sub-areas if no coords found.

        Returns True if at least one crag with coords was found.
        """
        if max_depth <= 0:
            return False

        self.stats["areas_processed"] += 1
        time.sleep(self.settings.request_delay_seconds)

        # Try to get details with coordinates
        details = self.scraper.get_area_details(url)
        if details and details.latitude and details.longitude:
            batch.append(details)
            self.stats["crags_found"] += 1
            log.debug("crag_found", url=url, name=details.name)
            return True

        # No coords - drill into sub-areas
        log.debug("drilling_into_subareas", url=url, depth=max_depth)
        sub_areas = self.scraper.get_areas_from_listing(url)

        found_any = False
        for sub in sub_areas[:10]:  # Limit sub-areas to avoid explosion
            try:
                if self._process_area_recursive(sub.url, batch, max_depth - 1):
                    found_any = True

                # Save batch if it gets large (stream saves)
                if len(batch) >= self.settings.batch_size:
                    self._upsert_batch(batch)
                    batch.clear()

            except Exception as e:
                log.warning("sub_area_failed", url=sub.url, error=str(e))
                self.stats["errors"] += 1

        return found_any

    def sync_area(self, area_url: str) -> Optional[Crag]:
        """Sync a single area by URL."""
        details = self.scraper.get_area_details(area_url)

        if not details or not details.latitude or not details.longitude:
            log.warning("area_no_coordinates", url=area_url)
            return None

        return self._upsert_single(details)

    def _upsert_batch(self, areas: list) -> int:
        """Upsert a batch of areas to the database."""
        if not areas:
            return 0

        session = get_session()
        count = 0

        try:
            for area in areas:
                crag_id = generate_deterministic_uuid(area.url)

                record = {
                    "id": crag_id,
                    "url": area.url,
                    "name": area.name,
                    "latitude": area.latitude,
                    "longitude": area.longitude,
                    "location_hierarchy_json": build_location_hierarchy(area.path or []),
                    "safety_status": "CAUTION",  # Default until weather is fetched
                }

                stmt = insert(Crag).values(**record)
                upsert_stmt = stmt.on_duplicate_key_update(
                    name=stmt.inserted.name,
                    latitude=stmt.inserted.latitude,
                    longitude=stmt.inserted.longitude,
                    location_hierarchy_json=stmt.inserted.location_hierarchy_json,
                )

                session.execute(upsert_stmt)
                count += 1

            session.commit()
            self.stats["crags_upserted"] += count
            log.info("batch_upserted", count=count, total=self.stats["crags_upserted"])

        except Exception as e:
            session.rollback()
            log.error("batch_upsert_failed", error=str(e))
            raise
        finally:
            session.close()

        return count

    def _upsert_single(self, area) -> Optional[Crag]:
        """Upsert a single area."""
        session = get_session()

        try:
            crag_id = generate_deterministic_uuid(area.url)

            crag = session.query(Crag).filter(Crag.id == crag_id).first()

            if crag:
                crag.name = area.name
                crag.latitude = area.latitude
                crag.longitude = area.longitude
                crag.location_hierarchy_json = build_location_hierarchy(area.path or [])
            else:
                crag = Crag(
                    id=crag_id,
                    url=area.url,
                    name=area.name,
                    latitude=area.latitude,
                    longitude=area.longitude,
                    location_hierarchy_json=build_location_hierarchy(area.path or []),
                    safety_status="CAUTION",
                )
                session.add(crag)

            session.commit()
            session.refresh(crag)
            return crag

        except Exception as e:
            session.rollback()
            log.error("single_upsert_failed", error=str(e))
            raise
        finally:
            session.close()
