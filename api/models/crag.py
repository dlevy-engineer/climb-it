from pydantic import BaseModel, Field
from typing import Optional
from enum import Enum
from datetime import date


class SafetyStatusEnum(str, Enum):
    SAFE = "SAFE"
    CAUTION = "CAUTION"
    UNSAFE = "UNSAFE"
    UNKNOWN = "UNKNOWN"


class PrecipitationData(BaseModel):
    last_7_days_mm: float = Field(default=0.0, description="Total precipitation in last 7 days (mm)")
    last_rain_date: Optional[date] = Field(default=None, description="Date of last recorded rain")
    days_since_rain: Optional[int] = Field(default=None, description="Days since last rain")


# --- Area (Hierarchy) Models ---

class AreaResponse(BaseModel):
    """Response for a single area in the hierarchy."""
    id: str
    name: str
    parent_id: Optional[str] = None
    has_children: bool = Field(description="Whether this area has child areas")
    is_crag: bool = Field(description="Whether this is a crag (has coordinates)")
    # Only present if is_crag is True
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    safety_status: Optional[SafetyStatusEnum] = None
    google_maps_url: Optional[str] = None
    mountain_project_url: Optional[str] = None

    model_config = {"from_attributes": True}


class AreaDetailResponse(AreaResponse):
    """Detailed area response with precipitation data."""
    precipitation: Optional[PrecipitationData] = None
    children: list["AreaResponse"] = Field(default_factory=list)


class AreaSearchResult(AreaResponse):
    """Search result with breadcrumb path for context."""
    breadcrumb: str = Field(description="Full path: California > Eastern Sierra > Bishop")


# --- Legacy Crag Models (for backwards compatibility) ---

class CragResponse(BaseModel):
    """Response for a crag (area with coordinates)."""
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


class DayForecastResponse(BaseModel):
    """Forecast for a single day with predicted safety status."""
    date: date
    predicted_status: SafetyStatusEnum = Field(description="Predicted safety status for this day")
    precipitation_mm: float = Field(description="Expected precipitation in mm")
    temp_high_c: Optional[float] = Field(default=None, description="High temperature in Celsius")
    temp_low_c: Optional[float] = Field(default=None, description="Low temperature in Celsius")
    weather_icon: str = Field(default="sun.max.fill", description="SF Symbol name for weather icon")


class ForecastResponse(BaseModel):
    """7-14 day forecast with predicted safety statuses."""
    crag_id: str
    crag_name: str
    current_status: SafetyStatusEnum
    estimated_safe_date: Optional[date] = Field(default=None, description="First day predicted to be SAFE")
    days: list[DayForecastResponse]
