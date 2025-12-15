"""
Areas API - Hierarchical navigation of climbing areas.

Provides endpoints for browsing the area tree:
- GET /areas - List top-level areas (states)
- GET /areas/{id} - Get area details
- GET /areas/{id}/children - Get child areas
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import Optional

from db import get_db, ODSArea, ODSAreaPrecipitation
from models import AreaResponse, AreaDetailResponse, PrecipitationData, SafetyStatusEnum
from datetime import datetime, timedelta

router = APIRouter(prefix="/areas", tags=["areas"])


def area_to_response(area: ODSArea, db: Session) -> AreaResponse:
    """Convert ORM model to Pydantic response."""
    # Check if this area has children
    has_children = db.query(ODSArea).filter(ODSArea.parent_id == area.id).first() is not None
    is_crag = area.latitude is not None and area.longitude is not None

    return AreaResponse(
        id=area.id,
        name=area.name,
        parent_id=area.parent_id,
        has_children=has_children,
        is_crag=is_crag,
        latitude=float(area.latitude) if area.latitude else None,
        longitude=float(area.longitude) if area.longitude else None,
        safety_status=area.safety_status.value if area.safety_status else None,
        google_maps_url=area.google_maps_url,
        mountain_project_url=area.url,
    )


@router.get("", response_model=list[AreaResponse])
def list_areas(
    parent_id: Optional[str] = Query(None, description="Parent area ID (null for top-level)"),
    db: Session = Depends(get_db),
):
    """
    List areas at a given level of the hierarchy.

    - No parent_id: Returns top-level areas (states)
    - With parent_id: Returns children of that area
    """
    if parent_id:
        areas = db.query(ODSArea).filter(ODSArea.parent_id == parent_id).order_by(ODSArea.name).all()
    else:
        # Top-level areas (states) have no parent
        areas = db.query(ODSArea).filter(ODSArea.parent_id.is_(None)).order_by(ODSArea.name).all()

    return [area_to_response(a, db) for a in areas]


@router.get("/{area_id}", response_model=AreaDetailResponse)
def get_area(area_id: str, db: Session = Depends(get_db)):
    """Get detailed area info including children and precipitation data."""
    area = db.query(ODSArea).filter(ODSArea.id == area_id).first()

    if not area:
        raise HTTPException(status_code=404, detail="Area not found")

    # Get children
    children = db.query(ODSArea).filter(ODSArea.parent_id == area_id).order_by(ODSArea.name).all()
    children_responses = [area_to_response(c, db) for c in children]

    # Get precipitation data if this is a crag
    precipitation = None
    if area.latitude is not None:
        seven_days_ago = datetime.utcnow() - timedelta(days=7)

        precip_7_days = (
            db.query(func.sum(ODSAreaPrecipitation.precipitation_mm))
            .filter(
                ODSAreaPrecipitation.area_id == area_id,
                ODSAreaPrecipitation.recorded_at >= seven_days_ago,
            )
            .scalar()
        ) or 0.0

        last_rain = (
            db.query(ODSAreaPrecipitation)
            .filter(
                ODSAreaPrecipitation.area_id == area_id,
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

    has_children = len(children) > 0
    is_crag = area.latitude is not None and area.longitude is not None

    return AreaDetailResponse(
        id=area.id,
        name=area.name,
        parent_id=area.parent_id,
        has_children=has_children,
        is_crag=is_crag,
        latitude=float(area.latitude) if area.latitude else None,
        longitude=float(area.longitude) if area.longitude else None,
        safety_status=area.safety_status.value if area.safety_status else None,
        google_maps_url=area.google_maps_url,
        mountain_project_url=area.url,
        precipitation=precipitation,
        children=children_responses,
    )


@router.get("/{area_id}/children", response_model=list[AreaResponse])
def get_area_children(area_id: str, db: Session = Depends(get_db)):
    """Get child areas of a given area."""
    # Verify parent exists
    parent = db.query(ODSArea).filter(ODSArea.id == area_id).first()
    if not parent:
        raise HTTPException(status_code=404, detail="Area not found")

    children = db.query(ODSArea).filter(ODSArea.parent_id == area_id).order_by(ODSArea.name).all()
    return [area_to_response(c, db) for c in children]


@router.get("/{area_id}/breadcrumb", response_model=list[AreaResponse])
def get_area_breadcrumb(area_id: str, db: Session = Depends(get_db)):
    """Get the full path from root to this area (for navigation breadcrumbs)."""
    area = db.query(ODSArea).filter(ODSArea.id == area_id).first()
    if not area:
        raise HTTPException(status_code=404, detail="Area not found")

    # Build path from area to root
    path = []
    current = area
    while current:
        path.append(area_to_response(current, db))
        if current.parent_id:
            current = db.query(ODSArea).filter(ODSArea.id == current.parent_id).first()
        else:
            current = None

    # Reverse to get root-to-leaf order
    path.reverse()
    return path
