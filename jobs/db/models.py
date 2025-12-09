"""SQLAlchemy ORM models."""
from sqlalchemy import Column, String, DECIMAL, JSON, Enum, TIMESTAMP, ForeignKey, Index
from sqlalchemy.dialects.mysql import CHAR
from sqlalchemy.orm import relationship
from datetime import datetime
import enum

from .database import Base


class SafetyStatus(enum.Enum):
    SAFE = "SAFE"
    CAUTION = "CAUTION"
    UNSAFE = "UNSAFE"


class Crag(Base):
    """Climbing area/crag from Mountain Project."""
    __tablename__ = "ods_crags"

    id = Column(CHAR(36), primary_key=True)
    url = Column(String(255), nullable=False, unique=True)
    name = Column(String(255), nullable=False)
    location_hierarchy_json = Column(JSON, nullable=True)
    latitude = Column(DECIMAL(9, 6), nullable=False)
    longitude = Column(DECIMAL(9, 6), nullable=False)
    google_maps_url = Column(String(500), nullable=True)
    safety_status = Column(
        Enum(SafetyStatus),
        nullable=False,
        default=SafetyStatus.CAUTION
    )
    last_synced_at = Column(TIMESTAMP, nullable=True)
    created_at = Column(TIMESTAMP, default=datetime.utcnow)
    updated_at = Column(TIMESTAMP, default=datetime.utcnow, onupdate=datetime.utcnow)

    precipitation_records = relationship(
        "Precipitation",
        back_populates="crag",
        cascade="all, delete-orphan"
    )

    __table_args__ = (
        Index("idx_crag_location", "latitude", "longitude"),
    )


class Precipitation(Base):
    """Daily precipitation data for a crag."""
    __tablename__ = "ods_precipitation"

    crag_id = Column(CHAR(36), ForeignKey("ods_crags.id", ondelete="CASCADE"), primary_key=True)
    recorded_at = Column(TIMESTAMP, primary_key=True)
    precipitation_mm = Column(DECIMAL(5, 2), nullable=False)
    temperature_max_c = Column(DECIMAL(4, 1), nullable=True)
    temperature_min_c = Column(DECIMAL(4, 1), nullable=True)

    crag = relationship("Crag", back_populates="precipitation_records")

    __table_args__ = (
        Index("idx_precip_date", "recorded_at"),
    )
