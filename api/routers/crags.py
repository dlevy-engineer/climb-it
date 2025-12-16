"""
Crags API - Legacy flat list of climbing areas with coordinates.

For backwards compatibility with the iOS app.
New clients should use /areas for hierarchical navigation.
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, or_
from typing import Optional
from datetime import datetime, timedelta, date
import httpx

from db import get_db, ODSArea, ODSAreaPrecipitation
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


def build_location_path_slow(area: ODSArea, db: Session) -> str:
    """Build location string by walking up the parent hierarchy (N+1 queries - slow!)."""
    parts = []
    current = area

    # Walk up the tree to build path
    while current:
        parts.append(current.name)
        if current.parent_id:
            current = db.query(ODSArea).filter(ODSArea.id == current.parent_id).first()
        else:
            current = None

    # Reverse to get root-to-leaf order, skip the crag itself
    parts.reverse()
    if len(parts) > 1:
        return " > ".join(parts[:-1])  # All except the last (crag name)
    return parts[0] if parts else "Unknown"


def build_area_lookup(db: Session) -> dict[str, ODSArea]:
    """Pre-load all areas into a lookup dict to avoid N+1 queries."""
    all_areas = db.query(ODSArea).all()
    return {area.id: area for area in all_areas}


def build_location_path_fast(area: ODSArea, area_lookup: dict[str, ODSArea]) -> str:
    """Build location string using pre-loaded area lookup (fast!)."""
    parts = []
    current = area

    # Walk up the tree using the lookup dict
    while current:
        parts.append(current.name)
        if current.parent_id and current.parent_id in area_lookup:
            current = area_lookup[current.parent_id]
        else:
            current = None

    # Reverse to get root-to-leaf order, skip the crag itself
    parts.reverse()
    if len(parts) > 1:
        return " > ".join(parts[:-1])  # All except the last (crag name)
    return parts[0] if parts else "Unknown"


def crag_to_response(crag: ODSArea, db: Session, area_lookup: dict[str, ODSArea] = None) -> CragResponse:
    """Convert ORM model to Pydantic response."""
    # Use fast path if lookup is provided, otherwise fall back to slow path
    if area_lookup:
        location = build_location_path_fast(crag, area_lookup)
    else:
        location = build_location_path_slow(crag, db)

    return CragResponse(
        id=crag.id,
        name=crag.name,
        location=location,
        latitude=float(crag.latitude),
        longitude=float(crag.longitude),
        safety_status=crag.safety_status.value if crag.safety_status else "UNKNOWN",
        google_maps_url=crag.google_maps_url,
        mountain_project_url=crag.url,
    )


@router.get("", response_model=list[CragResponse])
def list_crags(
    page: int = Query(1, ge=1, description="Page number"),
    per_page: int = Query(100, ge=1, le=1000, description="Items per page"),
    db: Session = Depends(get_db),
):
    """List all crags (areas with coordinates) with pagination."""
    offset = (page - 1) * per_page

    # Pre-load all areas to avoid N+1 queries when building location paths
    area_lookup = build_area_lookup(db)

    # Only return areas that have coordinates (actual crags)
    crags = (
        db.query(ODSArea)
        .filter(ODSArea.latitude.isnot(None))
        .order_by(ODSArea.name)
        .offset(offset)
        .limit(per_page)
        .all()
    )

    return [crag_to_response(c, db, area_lookup) for c in crags]


@router.get("/search", response_model=list[CragResponse])
def search_crags(
    q: str = Query(..., min_length=2, description="Search query"),
    limit: int = Query(20, ge=1, le=50, description="Max results"),
    db: Session = Depends(get_db),
):
    """Search crags by name."""
    search_term = f"%{q}%"

    crags = (
        db.query(ODSArea)
        .filter(
            ODSArea.latitude.isnot(None),  # Only crags with coordinates
            ODSArea.name.ilike(search_term),
        )
        .limit(limit)
        .all()
    )

    return [crag_to_response(c, db) for c in crags]


@router.get("/nearby", response_model=list[CragResponse])
def nearby_crags(
    lat: float = Query(..., ge=-90, le=90, description="Latitude"),
    lon: float = Query(..., ge=-180, le=180, description="Longitude"),
    radius_km: float = Query(50, ge=1, le=500, description="Search radius in km"),
    limit: int = Query(20, ge=1, le=50, description="Max results"),
    db: Session = Depends(get_db),
):
    """Find crags within a radius of given coordinates using Haversine formula."""
    # Haversine formula in SQL (approximate, good enough for nearby search)
    distance_expr = (
        6371
        * func.acos(
            func.cos(func.radians(lat))
            * func.cos(func.radians(ODSArea.latitude))
            * func.cos(func.radians(ODSArea.longitude) - func.radians(lon))
            + func.sin(func.radians(lat)) * func.sin(func.radians(ODSArea.latitude))
        )
    )

    crags = (
        db.query(ODSArea)
        .filter(ODSArea.latitude.isnot(None))  # Only crags
        .filter(distance_expr <= radius_km)
        .order_by(distance_expr)
        .limit(limit)
        .all()
    )

    return [crag_to_response(c, db) for c in crags]


@router.get("/{crag_id}", response_model=CragDetailResponse)
def get_crag(crag_id: str, db: Session = Depends(get_db)):
    """Get detailed crag info including precipitation data."""
    crag = db.query(ODSArea).filter(ODSArea.id == crag_id).first()

    if not crag:
        raise HTTPException(status_code=404, detail="Crag not found")

    if crag.latitude is None:
        raise HTTPException(status_code=400, detail="This area is not a crag (no coordinates)")

    # Calculate precipitation stats
    seven_days_ago = datetime.utcnow() - timedelta(days=7)

    precip_7_days = (
        db.query(func.sum(ODSAreaPrecipitation.precipitation_mm))
        .filter(
            ODSAreaPrecipitation.area_id == crag_id,
            ODSAreaPrecipitation.recorded_at >= seven_days_ago,
        )
        .scalar()
    ) or 0.0

    last_rain = (
        db.query(ODSAreaPrecipitation)
        .filter(
            ODSAreaPrecipitation.area_id == crag_id,
            ODSAreaPrecipitation.precipitation_mm > 0,
        )
        .order_by(ODSAreaPrecipitation.recorded_at.desc())
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
        location=build_location_path(crag, db),
        latitude=float(crag.latitude),
        longitude=float(crag.longitude),
        safety_status=crag.safety_status.value if crag.safety_status else "UNKNOWN",
        google_maps_url=crag.google_maps_url,
        mountain_project_url=crag.url,
        precipitation=precipitation,
        location_hierarchy=None,  # Deprecated
    )


# Safety thresholds (matching jobs/config.py)
SAFE_DAYS_THRESHOLD = 3
CAUTION_DAYS_THRESHOLD = 1
WEEKLY_PRECIP_CAUTION_MM = 10.0
WEEKLY_PRECIP_UNSAFE_MM = 25.0


def calculate_safety_status(total_7_days_mm: float, days_since_rain: Optional[int]) -> SafetyStatusEnum:
    """Apply safety rules to determine status."""
    if total_7_days_mm >= WEEKLY_PRECIP_UNSAFE_MM:
        return SafetyStatusEnum.UNSAFE
    if days_since_rain is not None and days_since_rain <= CAUTION_DAYS_THRESHOLD:
        return SafetyStatusEnum.UNSAFE

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
    crag = db.query(ODSArea).filter(ODSArea.id == crag_id).first()
    if not crag:
        raise HTTPException(status_code=404, detail="Crag not found")

    if crag.latitude is None:
        raise HTTPException(status_code=400, detail="This area is not a crag (no coordinates)")

    # Get historical precipitation for context
    cutoff = datetime.utcnow() - timedelta(days=14)
    precip_records = (
        db.query(ODSAreaPrecipitation)
        .filter(
            ODSAreaPrecipitation.area_id == crag_id,
            ODSAreaPrecipitation.recorded_at >= cutoff,
        )
        .order_by(ODSAreaPrecipitation.recorded_at.desc())
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

        combined_precip.append((forecast_date, precip_mm))

        rolling_sum = 0.0
        days_since_rain = None

        for precip_date, p_mm in sorted(combined_precip, key=lambda x: x[0], reverse=True):
            days_diff = (forecast_date - precip_date).days
            if 0 <= days_diff <= 7:
                rolling_sum += p_mm
            if days_since_rain is None and p_mm > 0.1:
                days_since_rain = days_diff

        status = calculate_safety_status(rolling_sum, days_since_rain)

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
