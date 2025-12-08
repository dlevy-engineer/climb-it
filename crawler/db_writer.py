# db_writer.py
import uuid
from sqlalchemy import create_engine
from sqlalchemy.dialects.mysql import insert
from sqlalchemy.orm import sessionmaker

from models_ods import ODSCrag, Base
from models import AreaNode

BASE_DOMAIN = "https://www.mountainproject.com"
AREA_PREFIX = "/area/"


def generate_deterministic_uuid(url: str) -> str:
    """
    Generate a consistent UUID using UUIDv5 from a given URL.
    This ensures repeated crawls always get the same UUID.
    """
    namespace = uuid.UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")  # DNS namespace
    return str(uuid.uuid5(namespace, url))


class CragDBWriter:
    def __init__(self, db_url: str):
        """Initialize SQLAlchemy connection and ORM base."""
        self.engine = create_engine(db_url, pool_recycle=3600)
        self.Session = sessionmaker(bind=self.engine)
        Base.metadata.create_all(self.engine)

    def upsert_crags(self, area_nodes: list[AreaNode]):
        """
        Upsert a list of AreaNode objects into the database.
        Skips nodes that are not leaf crags (i.e., no lat/lon).
        """
        session = self.Session()
        count = 0

        try:
            for node in area_nodes:
                # Skip nodes without coordinates (i.e., non-leaf)
                if node.latitude is None or node.longitude is None:
                    continue

                if not node.url.startswith(BASE_DOMAIN + AREA_PREFIX):
                    continue  # Skip malformed or external links

                crag_id = generate_deterministic_uuid(node.url)
                record = {
                    "id": crag_id,
                    "url": node.url,
                    "name": node.name or "UNKNOWN",
                    "location_hierarchy_json": node.location_hierarchy,
                    "latitude": node.latitude,
                    "longitude": node.longitude,
                    "google_maps_url": node.google_maps_url,
                    "safety_status": node.safety_status or "CAUTION"
                }

                stmt = insert(ODSCrag).values(**record)
                upsert_stmt = stmt.on_duplicate_key_update(
                    name=stmt.inserted.name,
                    url=stmt.inserted.url,
                    location_hierarchy_json=stmt.inserted.location_hierarchy_json,
                    latitude=stmt.inserted.latitude,
                    longitude=stmt.inserted.longitude,
                    google_maps_url=stmt.inserted.google_maps_url,
                    safety_status=stmt.inserted.safety_status
                )

                session.execute(upsert_stmt)
                count += 1

            session.commit()
            print(f"✅ Upserted {count} crags")
        except Exception as e:
            session.rollback()
            print(f"❌ Failed to write to database: {e}")
        finally:
            session.close()