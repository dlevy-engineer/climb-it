from pydantic import BaseModel, Field
from typing import Optional
from enum import Enum
from datetime import date


class SafetyStatusEnum(str, Enum):
    SAFE = "SAFE"
    CAUTION = "CAUTION"
    UNSAFE = "UNSAFE"


class PrecipitationData(BaseModel):
    last_7_days_mm: float = Field(default=0.0, description="Total precipitation in last 7 days (mm)")
    last_rain_date: Optional[date] = Field(default=None, description="Date of last recorded rain")
    days_since_rain: Optional[int] = Field(default=None, description="Days since last rain")


class CragResponse(BaseModel):
    id: str
    name: str
    location: str = Field(description="Formatted location string from hierarchy")
    latitude: float
    longitude: float
    safety_status: SafetyStatusEnum
    google_maps_url: Optional[str] = None
    mountain_project_url: Optional[str] = None

    model_config = {"from_attributes": True}


class CragDetailResponse(CragResponse):
    precipitation: Optional[PrecipitationData] = None
    location_hierarchy: Optional[dict] = None


class CragListResponse(BaseModel):
    crags: list[CragResponse]
    total: int
    page: int
    per_page: int
