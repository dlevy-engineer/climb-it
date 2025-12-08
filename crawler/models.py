from dataclasses import dataclass
from typing import Optional, TypedDict, Union


class LocationNode(TypedDict, total=False):
    name: str
    url: str
    child: 'LocationNode'


@dataclass
class AreaNode:
    """A structured representation of a single area page."""
    url: str
    name: str
    parent_url: Optional[str]
    latitude: Optional[float]
    longitude: Optional[float]
    google_maps_url: Optional[str]
    location_hierarchy: Optional[LocationNode] = None
    safety_status: Optional[str] = "CAUTION"