"""SQLAlchemy ORM models."""
from sqlalchemy import Column, String, DECIMAL, Enum, TIMESTAMP, ForeignKey, Index, Boolean
from sqlalchemy.orm import relationship
import enum

from .database import Base


class SafetyStatus(enum.Enum):
    SAFE = "SAFE"
    CAUTION = "CAUTION"
    UNSAFE = "UNSAFE"
    UNKNOWN = "UNKNOWN"


class Area(Base):
    """
    Hierarchical climbing area from Mountain Project.

    Stores the full area tree: States -> Regions -> Sub-regions -> Crags
    Only leaf nodes (crags) have coordinates and safety status.
    """
    __tablename__ = "ods_areas"

    id = Column(String(36), primary_key=True)  # Mountain Project area ID from URL
    name = Column(String(255), nullable=False)
    url = Column(String(500), nullable=False, unique=True)
    parent_id = Column(String(36), ForeignKey("ods_areas.id"), nullable=True)

    # Only populated for leaf nodes (actual crags with coordinates)
    latitude = Column(DECIMAL(9, 6), nullable=True)
    longitude = Column(DECIMAL(9, 6), nullable=True)
    google_maps_url = Column(String(500), nullable=True)
    safety_status = Column(Enum(SafetyStatus), nullable=True)

    # Scraping metadata
    scraped_at = Column(TIMESTAMP, nullable=True)  # NULL = never scraped for details
    scrape_failed = Column(Boolean, nullable=False, default=False)

    # Relationships
    parent = relationship("Area", remote_side=[id], backref="children")
    precipitation_records = relationship(
        "Precipitation",
        back_populates="area",
        cascade="all, delete-orphan"
    )

    __table_args__ = (
        Index("idx_area_parent", "parent_id"),
        Index("idx_area_location", "latitude", "longitude"),
        Index("idx_area_needs_scrape", "scraped_at", "scrape_failed"),
    )

    @property
    def is_crag(self) -> bool:
        """A crag is an area with coordinates."""
        return self.latitude is not None and self.longitude is not None


class Precipitation(Base):
    """Daily precipitation data for a crag (area with coordinates)."""
    __tablename__ = "ods_precipitation"

    area_id = Column(String(36), ForeignKey("ods_areas.id", ondelete="CASCADE"), primary_key=True)
    recorded_at = Column(TIMESTAMP, primary_key=True)
    precipitation_mm = Column(DECIMAL(5, 2), nullable=False)
    temperature_max_c = Column(DECIMAL(4, 1), nullable=True)
    temperature_min_c = Column(DECIMAL(4, 1), nullable=True)

    area = relationship("Area", back_populates="precipitation_records")

    __table_args__ = (
        Index("idx_precip_date", "recorded_at"),
    )
