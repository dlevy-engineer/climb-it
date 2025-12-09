from sqlalchemy import Column, String, DECIMAL, JSON, Enum, TIMESTAMP, ForeignKey
from sqlalchemy.dialects.mysql import CHAR
from sqlalchemy.orm import relationship
from .database import Base
import enum


class SafetyStatus(enum.Enum):
    SAFE = "SAFE"
    CAUTION = "CAUTION"
    UNSAFE = "UNSAFE"
    UNKNOWN = "UNKNOWN"


class ODSCrag(Base):
    __tablename__ = "ods_crags"

    id = Column(CHAR(36), primary_key=True)
    url = Column(String(255), nullable=False)
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

    precipitation_records = relationship(
        "ODSCragPrecipitation",
        back_populates="crag",
        lazy="dynamic"
    )


class ODSCragPrecipitation(Base):
    __tablename__ = "ods_precipitation"

    crag_id = Column(CHAR(36), ForeignKey("ods_crags.id"), primary_key=True)
    recorded_at = Column(TIMESTAMP, primary_key=True)
    precipitation_mm = Column(DECIMAL(5, 2), nullable=False)

    crag = relationship("ODSCrag", back_populates="precipitation_records")
