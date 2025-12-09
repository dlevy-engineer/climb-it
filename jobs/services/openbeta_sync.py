"""Service for syncing crags from OpenBeta.

Uses the OpenBeta GraphQL API (properly licensed under CC BY-SA 4.0)
instead of scraping Mountain Project.
"""
import re
import uuid
import structlog
from typing import Optional

from sqlalchemy.dialects.mysql import insert

from config import get_settings
from db import get_session, Crag
from clients import OpenBetaClient

log = structlog.get_logger()


def generate_deterministic_uuid(identifier: str) -> str:
    """Generate a consistent UUID from an identifier using UUIDv5."""
    namespace = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
    return str(uuid.uuid5(namespace, identifier))


def clean_area_name(name: str) -> str:
    """Clean up area names by removing special characters and numbering prefixes."""
    # Remove numbering prefixes like "00. ", "01. ", "1. ", etc.
    name = re.sub(r'^\d+\.\s*', '', name)
    # Remove asterisks
    name = name.replace('*', '')
    # Remove smart quotes and regular quotes
    name = name.replace('"', '').replace('"', '').replace('"', '')
    # Remove leading/trailing whitespace
    name = name.strip()
    return name


def build_location_hierarchy(path: list[str], exclude_last: bool = True) -> dict:
    """Convert path list to nested hierarchy dict.

    Args:
        path: List of location names from root to leaf
        exclude_last: If True, exclude the last element (the crag name itself)

    Returns:
        Nested dict with "name" and "child" keys
    """
    if not path:
        return {}

    # Filter out "USA" from the beginning
    filtered_path = [p for p in path if p.upper() != "USA"]

    # Exclude the last element (crag name) since it's already the crag's name
    if exclude_last and len(filtered_path) > 0:
        filtered_path = filtered_path[:-1]

    if not filtered_path:
        return {}

    # Clean names and build hierarchy
    result = None
    for name in reversed(filtered_path):
        cleaned_name = clean_area_name(name)
        if cleaned_name:  # Skip empty names after cleaning
            result = {"name": cleaned_name, "child": result}

    return result or {}


class OpenBetaSyncService:
    """Service for synchronizing crags from OpenBeta."""

    def __init__(self):
        self.settings = get_settings()
        self.client = OpenBetaClient()
        self.stats = {
            "states_processed": 0,
            "areas_processed": 0,
            "crags_found": 0,
            "crags_upserted": 0,
            "errors": 0,
        }

    def close(self):
        self.client.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def sync_all(self, max_areas: Optional[int] = None) -> dict:
        """
        Full sync of all US areas from OpenBeta.

        Much faster than Mountain Project scraping since it uses a proper API.

        Args:
            max_areas: Optional limit on number of areas to process

        Returns:
            Stats dictionary
        """
        log.info("openbeta_sync_starting")

        # Get all US state UUIDs
        states = self.client.get_all_state_urls()
        log.info("states_to_process", count=len(states))

        total_areas_processed = 0
        batch = []

        # Process each state
        for state_name, state_uuid in states:
            if max_areas and total_areas_processed >= max_areas:
                log.info("max_areas_reached", max=max_areas)
                break

            try:
                # Get areas for this state (with nested children)
                areas = self.client.get_areas_from_listing(state_uuid)
                log.info("state_areas_found", state=state_name, areas=len(areas))

                # Process each area
                for area in areas:
                    if max_areas and total_areas_processed >= max_areas:
                        break

                    # Only include areas with valid coordinates
                    if area.latitude and area.longitude:
                        batch.append(area)
                        self.stats["crags_found"] += 1
                        total_areas_processed += 1

                        # Save batch when it reaches threshold
                        if len(batch) >= self.settings.batch_size:
                            self._upsert_batch(batch)
                            batch = []

                    self.stats["areas_processed"] += 1

                    # For deeper areas, fetch their children too
                    try:
                        sub_areas = self.client.get_areas_from_listing(area.id)
                        for sub_area in sub_areas:
                            if max_areas and total_areas_processed >= max_areas:
                                break
                            if sub_area.latitude and sub_area.longitude:
                                batch.append(sub_area)
                                self.stats["crags_found"] += 1
                                total_areas_processed += 1

                                if len(batch) >= self.settings.batch_size:
                                    self._upsert_batch(batch)
                                    batch = []

                            self.stats["areas_processed"] += 1
                    except Exception as e:
                        log.debug("sub_areas_fetch_failed", area=area.name, error=str(e))

                self.stats["states_processed"] += 1
                log.info("state_complete", state=state_name, **self.stats)

            except Exception as e:
                log.error("state_failed", state=state_name, error=str(e))
                self.stats["errors"] += 1

        # Save remaining batch
        if batch:
            self._upsert_batch(batch)

        log.info("openbeta_sync_complete", **self.stats)
        return self.stats

    def _upsert_batch(self, areas: list) -> int:
        """Upsert a batch of areas to the database."""
        if not areas:
            return 0

        session = get_session()
        count = 0

        try:
            for area in areas:
                # Use OpenBeta UUID directly as our ID
                crag_id = generate_deterministic_uuid(f"openbeta:{area.id}")

                record = {
                    "id": crag_id,
                    "url": area.url,
                    "name": area.name,
                    "latitude": area.latitude,
                    "longitude": area.longitude,
                    "location_hierarchy_json": build_location_hierarchy(area.path or []),
                    "safety_status": "UNKNOWN",  # Default until weather is fetched
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
