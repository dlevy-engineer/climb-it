"""Service for syncing crags from Mountain Project."""
import uuid
import structlog
from typing import Optional
from collections import deque

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

    # Filter out "All Locations" and empty strings
    filtered = [p for p in path if p and p != "All Locations"]
    if not filtered:
        return {}

    result = None
    for name in reversed(filtered):
        result = {"name": name, "child": result}

    return result or {}


class CragSyncService:
    """Service for synchronizing crags from Mountain Project.

    Uses breadth-first traversal to efficiently scrape crags:
    - One HTTP request per area (extracts coords AND children together)
    - Global URL deduplication prevents redundant requests
    - Immediate upserts when crags are found (no batching delay)
    - US-only filtering to skip international areas
    """

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
        Full sync of all US areas from Mountain Project.

        Uses breadth-first search to traverse the area hierarchy:
        1. Get US states from route guide
        2. For each state, do BFS through child areas
        3. When an area has coordinates, save it immediately
        4. When no coordinates, add children to queue for processing

        Args:
            max_areas: Optional limit on number of areas to process

        Returns:
            Stats dictionary
        """
        log.info("crag_sync_starting")

        # Get US state URLs (filtered, deduplicated)
        state_urls = self.scraper.get_all_state_urls()
        log.info("states_to_process", count=len(state_urls))

        # Process each state
        for state_name, state_url in state_urls:
            if max_areas and self.stats["areas_processed"] >= max_areas:
                log.info("max_areas_reached", max=max_areas)
                break

            try:
                self._process_state(state_name, state_url, max_areas)
                self.stats["states_processed"] += 1
                log.info("state_complete", state=state_name, **self.stats)

            except Exception as e:
                log.error("state_failed", state=state_name, error=str(e))
                self.stats["errors"] += 1

        log.info("crag_sync_complete", **self.stats)
        return self.stats

    def _process_state(self, state_name: str, state_url: str, max_areas: Optional[int]):
        """Process a single state using breadth-first search.

        BFS ensures we process areas level by level, which is more predictable
        and allows early termination when hitting max_areas.
        """
        # Queue holds (url, depth) tuples
        queue: deque[tuple[str, int]] = deque()
        queue.append((state_url, 0))

        max_depth = 4  # Don't go deeper than 4 levels

        while queue:
            if max_areas and self.stats["areas_processed"] >= max_areas:
                break

            url, depth = queue.popleft()

            # Skip if too deep
            if depth > max_depth:
                continue

            try:
                # Single request gets BOTH coordinates AND children
                area, children = self.scraper.get_area_with_children(url)
                self.stats["areas_processed"] += 1

                # If area has coordinates, save it immediately
                if area:
                    self._upsert_crag(area)
                    self.stats["crags_found"] += 1

                # Add children to queue for processing (only if we didn't find coords
                # or if we want to go deeper for sub-crags)
                if not area or depth < 2:  # Always drill down first 2 levels
                    for child in children:
                        if not self.scraper.was_visited(child.url):
                            queue.append((child.url, depth + 1))

            except Exception as e:
                log.warning("area_failed", url=url, error=str(e))
                self.stats["errors"] += 1

    def _upsert_crag(self, area) -> bool:
        """Upsert a single crag immediately (no batching)."""
        session = get_session()

        try:
            crag_id = generate_deterministic_uuid(area.url)

            record = {
                "id": crag_id,
                "url": area.url,
                "name": area.name,
                "latitude": area.latitude,
                "longitude": area.longitude,
                "location_hierarchy_json": build_location_hierarchy(area.path or []),
                "safety_status": "UNKNOWN",
            }

            stmt = insert(Crag).values(**record)
            upsert_stmt = stmt.on_duplicate_key_update(
                name=stmt.inserted.name,
                latitude=stmt.inserted.latitude,
                longitude=stmt.inserted.longitude,
                location_hierarchy_json=stmt.inserted.location_hierarchy_json,
            )

            session.execute(upsert_stmt)
            session.commit()
            self.stats["crags_upserted"] += 1

            log.debug("crag_upserted", name=area.name, url=area.url)
            return True

        except Exception as e:
            session.rollback()
            log.error("crag_upsert_failed", url=area.url, error=str(e))
            return False
        finally:
            session.close()

    def sync_area(self, area_url: str) -> Optional[Crag]:
        """Sync a single area by URL."""
        area, _ = self.scraper.get_area_with_children(area_url)

        if not area:
            log.warning("area_no_coordinates", url=area_url)
            return None

        if self._upsert_crag(area):
            return area
        return None
