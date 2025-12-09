from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, or_
from typing import Optional
from datetime import datetime, timedelta

from db import get_db, ODSCrag, ODSCragPrecipitation
from models import CragResponse, CragDetailResponse, PrecipitationData, CragListResponse

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
