"""Service for syncing crags from Mountain Project."""
import uuid
import time
import structlog
from datetime import datetime
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

        Args:
            max_areas: Optional limit on number of areas to process

        Returns:
            Stats dictionary
        """
        log.info("crag_sync_starting")

        # Get all state/region URLs
        state_urls = self.scraper.get_all_state_urls()
        log.info("states_to_process", count=len(state_urls))

        areas_to_process = []

        # Gather all area URLs from state pages
        for state_name, state_url in state_urls:
            try:
                areas = self.scraper.get_areas_from_listing(state_url)
                areas_to_process.extend(areas)
                log.info("state_processed", state=state_name, areas=len(areas))
                time.sleep(self.settings.request_delay_seconds)
            except Exception as e:
                log.error("state_failed", state=state_name, error=str(e))
                self.stats["errors"] += 1

        if max_areas:
            areas_to_process = areas_to_process[:max_areas]

        log.info("areas_to_process", total=len(areas_to_process))

        # Process each area - recursively drill into sub-areas if no coords
        batch = []
        for area in areas_to_process:
            try:
                found = self._process_area_recursive(area.url, batch, max_depth=3)
                if found and len(batch) >= self.settings.batch_size:
                    self._upsert_batch(batch)
                    batch = []
            except Exception as e:
                log.error("area_failed", url=area.url, error=str(e))
                self.stats["errors"] += 1

            if self.stats["areas_processed"] % 100 == 0:
                log.info("sync_progress", **self.stats)

        # Final batch
        if batch:
            self._upsert_batch(batch)

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
                    "mp_id": str(area.id) if area.id else None,
                    "safety_status": "CAUTION",  # Default until weather is fetched
                    "last_synced_at": datetime.utcnow(),
                }

                stmt = insert(Crag).values(**record)
                upsert_stmt = stmt.on_duplicate_key_update(
                    name=stmt.inserted.name,
                    latitude=stmt.inserted.latitude,
                    longitude=stmt.inserted.longitude,
                    location_hierarchy_json=stmt.inserted.location_hierarchy_json,
                    last_synced_at=stmt.inserted.last_synced_at,
                )

                session.execute(upsert_stmt)
                count += 1

            session.commit()
            self.stats["crags_upserted"] += count
            log.info("batch_upserted", count=count)

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
                crag.last_synced_at = datetime.utcnow()
            else:
                crag = Crag(
                    id=crag_id,
                    url=area.url,
                    name=area.name,
                    latitude=area.latitude,
                    longitude=area.longitude,
                    location_hierarchy_json=build_location_hierarchy(area.path or []),
                    mp_id=str(area.id) if area.id else None,
                    safety_status="CAUTION",
                    last_synced_at=datetime.utcnow(),
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
