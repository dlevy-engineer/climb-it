from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, or_
from typing import Optional
from datetime import datetime, timedelta, date
import httpx

from db import get_db, ODSCrag, ODSCragPrecipitation
from models import (
    CragResponse,
    CragDetailResponse,
    PrecipitationData,
    CragListResponse,
    ForecastResponse,
    DayForecastResponse,
    SafetyStatusEnum,
)

router = APIRouter(prefix="/crags", tags=["crags"])


def format_location(hierarchy: dict | None) -> str:
    """Convert nested location hierarchy to readable string like 'California > Yosemite'"""
    if not hierarchy:
        return "Unknown"

    parts = []
    current = hierarchy
    while current:
        if "name" in current:
            name = current["name"]
            # Skip "All Locations" prefix
            if name != "All Locations":
                parts.append(name)
        current = current.get("child")

    return " > ".join(parts) if parts else "Unknown"


def crag_to_response(crag: ODSCrag) -> CragResponse:
    """Convert ORM model to Pydantic response"""
    return CragResponse(
        id=crag.id,
        name=crag.name,
        location=format_location(crag.location_hierarchy_json),
        latitude=float(crag.latitude),
        longitude=float(crag.longitude),
        safety_status=crag.safety_status.value if crag.safety_status else "CAUTION",
        google_maps_url=crag.google_maps_url,
        mountain_project_url=crag.url,
    )


@router.get("", response_model=list[CragResponse])
def list_crags(
    page: int = Query(1, ge=1, description="Page number"),
    per_page: int = Query(50, ge=1, le=100, description="Items per page"),
    db: Session = Depends(get_db),
):
    """List all crags with pagination"""
    offset = (page - 1) * per_page

    crags = (
        db.query(ODSCrag)
        .order_by(ODSCrag.name)
        .offset(offset)
        .limit(per_page)
        .all()
    )

    return [crag_to_response(c) for c in crags]


@router.get("/search", response_model=list[CragResponse])
def search_crags(
    q: str = Query(..., min_length=2, description="Search query"),
    limit: int = Query(20, ge=1, le=50, description="Max results"),
    db: Session = Depends(get_db),
):
    """Search crags by name or location"""
    search_term = f"%{q}%"

    crags = (
        db.query(ODSCrag)
        .filter(
            or_(
                ODSCrag.name.ilike(search_term),
                func.json_extract(ODSCrag.location_hierarchy_json, "$.name").like(search_term),
            )
        )
        .limit(limit)
        .all()
    )

    return [crag_to_response(c) for c in crags]


@router.get("/nearby", response_model=list[CragResponse])
def nearby_crags(
    lat: float = Query(..., ge=-90, le=90, description="Latitude"),
    lon: float = Query(..., ge=-180, le=180, description="Longitude"),
    radius_km: float = Query(50, ge=1, le=500, description="Search radius in km"),
    limit: int = Query(20, ge=1, le=50, description="Max results"),
    db: Session = Depends(get_db),
):
    """Find crags within a radius of given coordinates using Haversine formula"""
    # Haversine formula in SQL (approximate, good enough for nearby search)
    # 6371 = Earth's radius in km
    distance_expr = (
        6371
        * func.acos(
            func.cos(func.radians(lat))
            * func.cos(func.radians(ODSCrag.latitude))
            * func.cos(func.radians(ODSCrag.longitude) - func.radians(lon))
            + func.sin(func.radians(lat)) * func.sin(func.radians(ODSCrag.latitude))
        )
    )

    crags = (
        db.query(ODSCrag)
        .filter(distance_expr <= radius_km)
        .order_by(distance_expr)
        .limit(limit)
        .all()
    )

    return [crag_to_response(c) for c in crags]


@router.get("/{crag_id}", response_model=CragDetailResponse)
def get_crag(crag_id: str, db: Session = Depends(get_db)):
    """Get detailed crag info including precipitation data"""
    crag = db.query(ODSCrag).filter(ODSCrag.id == crag_id).first()

    if not crag:
        raise HTTPException(status_code=404, detail="Crag not found")

    # Calculate precipitation stats
    seven_days_ago = datetime.utcnow() - timedelta(days=7)

    precip_7_days = (
        db.query(func.sum(ODSCragPrecipitation.precipitation_mm))
        .filter(
            ODSCragPrecipitation.crag_id == crag_id,
            ODSCragPrecipitation.recorded_at >= seven_days_ago,
        )
        .scalar()
    ) or 0.0

    last_rain = (
        db.query(ODSCragPrecipitation)
        .filter(
            ODSCragPrecipitation.crag_id == crag_id,
            ODSCragPrecipitation.precipitation_mm > 0,
        )
        .order_by(ODSCragPrecipitation.recorded_at.desc())
        .first()
    )

    precipitation = PrecipitationData(
        last_7_days_mm=float(precip_7_days),
        last_rain_date=last_rain.recorded_at.date() if last_rain else None,
        days_since_rain=(
            (datetime.utcnow().date() - last_rain.recorded_at.date()).days
            if last_rain
            else None
        ),
    )

    return CragDetailResponse(
        id=crag.id,
        name=crag.name,
        location=format_location(crag.location_hierarchy_json),
        latitude=float(crag.latitude),
        longitude=float(crag.longitude),
        safety_status=crag.safety_status.value if crag.safety_status else "CAUTION",
        google_maps_url=crag.google_maps_url,
        mountain_project_url=crag.url,
        precipitation=precipitation,
        location_hierarchy=crag.location_hierarchy_json,
    )


# Safety thresholds (matching jobs/config.py)
SAFE_DAYS_THRESHOLD = 3
CAUTION_DAYS_THRESHOLD = 1
WEEKLY_PRECIP_CAUTION_MM = 10.0
WEEKLY_PRECIP_UNSAFE_MM = 25.0


def calculate_safety_status(total_7_days_mm: float, days_since_rain: Optional[int]) -> SafetyStatusEnum:
    """Apply safety rules to determine status."""
    # UNSAFE conditions
    if total_7_days_mm >= WEEKLY_PRECIP_UNSAFE_MM:
        return SafetyStatusEnum.UNSAFE
    if days_since_rain is not None and days_since_rain <= CAUTION_DAYS_THRESHOLD:
        return SafetyStatusEnum.UNSAFE

    # CAUTION conditions
    if total_7_days_mm >= WEEKLY_PRECIP_CAUTION_MM:
        return SafetyStatusEnum.CAUTION
    if days_since_rain is not None and days_since_rain <= SAFE_DAYS_THRESHOLD:
        return SafetyStatusEnum.CAUTION

    return SafetyStatusEnum.SAFE


def get_weather_icon(precip_mm: float) -> str:
    """Get SF Symbol name based on precipitation amount."""
    if precip_mm > 5.0:
        return "cloud.rain.fill"
    elif precip_mm > 1.0:
        return "cloud.drizzle.fill"
    elif precip_mm > 0.1:
        return "cloud.fill"
    return "sun.max.fill"


@router.get("/{crag_id}/forecast", response_model=ForecastResponse)
async def get_crag_forecast(
    crag_id: str,
    days: int = Query(14, ge=1, le=16, description="Number of forecast days (max 16)"),
    db: Session = Depends(get_db),
):
    """Get safety forecast for a crag with daily predictions."""
    crag = db.query(ODSCrag).filter(ODSCrag.id == crag_id).first()
    if not crag:
        raise HTTPException(status_code=404, detail="Crag not found")

    # Get historical precipitation for context
    cutoff = datetime.utcnow() - timedelta(days=14)
    precip_records = (
        db.query(ODSCragPrecipitation)
        .filter(
            ODSCragPrecipitation.crag_id == crag_id,
            ODSCragPrecipitation.recorded_at >= cutoff,
        )
        .order_by(ODSCragPrecipitation.recorded_at.desc())
        .all()
    )

    # Build historical precipitation list
    today = date.today()
    recent_precip = []
    for r in precip_records:
        record_date = r.recorded_at.date()
        days_ago = (today - record_date).days
        if days_ago <= 12:
            recent_precip.append((record_date, float(r.precipitation_mm)))

    # Fetch forecast from Open-Meteo
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(
            "https://api.open-meteo.com/v1/forecast",
            params={
                "latitude": float(crag.latitude),
                "longitude": float(crag.longitude),
                "daily": "precipitation_sum,temperature_2m_max,temperature_2m_min",
                "timezone": "auto",
                "forecast_days": days,
            },
        )
        response.raise_for_status()
        forecast_data = response.json()

    daily = forecast_data.get("daily", {})
    dates = daily.get("time", [])
    precip = daily.get("precipitation_sum", [])
    temp_max = daily.get("temperature_2m_max", [])
    temp_min = daily.get("temperature_2m_min", [])

    # Calculate predicted status for each day
    day_forecasts = []
    combined_precip = recent_precip.copy()
    estimated_safe_date = None

    for i, date_str in enumerate(dates):
        forecast_date = datetime.fromisoformat(date_str).date()
        precip_mm = precip[i] if i < len(precip) and precip[i] is not None else 0.0

        # Add this day's forecast to combined data
        combined_precip.append((forecast_date, precip_mm))

        # Calculate 7-day rolling sum
        rolling_sum = 0.0
        days_since_rain = None

        for precip_date, p_mm in sorted(combined_precip, key=lambda x: x[0], reverse=True):
            days_diff = (forecast_date - precip_date).days
            if 0 <= days_diff <= 7:
                rolling_sum += p_mm
            if days_since_rain is None and p_mm > 0.1:
                days_since_rain = days_diff

        status = calculate_safety_status(rolling_sum, days_since_rain)

        # Track first safe date
        if estimated_safe_date is None and status == SafetyStatusEnum.SAFE:
            estimated_safe_date = forecast_date

        day_forecasts.append(DayForecastResponse(
            date=forecast_date,
            predicted_status=status,
            precipitation_mm=precip_mm,
            temp_high_c=temp_max[i] if i < len(temp_max) else None,
            temp_low_c=temp_min[i] if i < len(temp_min) else None,
            weather_icon=get_weather_icon(precip_mm),
        ))

    return ForecastResponse(
        crag_id=crag.id,
        crag_name=crag.name,
        current_status=crag.safety_status if crag.safety_status else SafetyStatusEnum.UNKNOWN,
        estimated_safe_date=estimated_safe_date,
        days=day_forecasts,
    )
