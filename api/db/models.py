from sqlalchemy import Column, String, DECIMAL, Enum, TIMESTAMP, ForeignKey, Boolean
from sqlalchemy.orm import relationship
from .database import Base
import enum


class SafetyStatus(enum.Enum):
    SAFE = "SAFE"
    CAUTION = "CAUTION"
    UNSAFE = "UNSAFE"
    UNKNOWN = "UNKNOWN"


class ODSArea(Base):
    """Hierarchical climbing area from Mountain Project."""
    __tablename__ = "ods_areas"

    id = Column(String(36), primary_key=True)
    name = Column(String(255), nullable=False)
    url = Column(String(500), nullable=False, unique=True)
    parent_id = Column(String(36), ForeignKey("ods_areas.id"), nullable=True)

    # Only populated for leaf nodes (actual crags with coordinates)
    latitude = Column(DECIMAL(9, 6), nullable=True)
    longitude = Column(DECIMAL(9, 6), nullable=True)
    google_maps_url = Column(String(500), nullable=True)
    safety_status = Column(Enum(SafetyStatus), nullable=True)

    # Scraping metadata
    scraped_at = Column(TIMESTAMP, nullable=True)
    scrape_failed = Column(Boolean, nullable=False, default=False)

    # Relationships
    parent = relationship("ODSArea", remote_side=[id], backref="children")
    precipitation_records = relationship(
        "ODSAreaPrecipitation",
        back_populates="area",
        lazy="dynamic"
    )


class ODSAreaPrecipitation(Base):
    """Daily precipitation data for a crag."""
    __tablename__ = "ods_precipitation"

    area_id = Column(String(36), ForeignKey("ods_areas.id", ondelete="CASCADE"), primary_key=True)
    recorded_at = Column(TIMESTAMP, primary_key=True)
    precipitation_mm = Column(DECIMAL(5, 2), nullable=False)

    area = relationship("ODSArea", back_populates="precipitation_records")
