"""OpenBeta GraphQL API client.

Uses the OpenBeta public API to fetch climbing areas.
This is a properly licensed alternative to scraping Mountain Project.

OpenBeta data is licensed under CC BY-SA 4.0.
https://openbeta.io
"""
import structlog
import time
import requests
from dataclasses import dataclass
from typing import Optional

log = structlog.get_logger()


@dataclass
class OpenBetaArea:
    """OpenBeta climbing area."""
    id: str  # UUID
    name: str
    latitude: float
    longitude: float
    url: str
    parent_id: Optional[str] = None
    path: Optional[list[str]] = None  # Location hierarchy (pathTokens)


class OpenBetaClient:
    """
    Client for the OpenBeta GraphQL API.

    Much faster than scraping - uses proper API calls.
    No browser needed, no Cloudflare to bypass.
    """

    API_URL = "https://api.openbeta.io"
    BASE_WEB_URL = "https://openbeta.io/area"

    # UUID of USA in OpenBeta
    USA_UUID = "1db1e8ba-a40e-587c-88a4-64f5ea814b8e"

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            "Content-Type": "application/json",
            "User-Agent": "ClimbIt/1.0 (https://github.com/dlevy-engineer/climb-it)"
        })
        self._request_count = 0

    def close(self):
        """Close the session."""
        self.session.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def _query(self, query: str, variables: dict = None) -> dict:
        """Execute a GraphQL query."""
        self._request_count += 1

        payload = {"query": query}
        if variables:
            payload["variables"] = variables

        # Gentle rate limiting - 100ms between requests
        time.sleep(0.1)

        response = self.session.post(self.API_URL, json=payload, timeout=30)
        response.raise_for_status()

        data = response.json()

        if "errors" in data:
            log.error("graphql_error", errors=data["errors"])
            raise Exception(f"GraphQL error: {data['errors']}")

        return data.get("data", {})

    def get_all_state_urls(self) -> list[tuple[str, str]]:
        """
        Get all US state areas.

        Returns list of (name, uuid) tuples to match Mountain Project interface.
        """
        query = """
        query GetUSAStates($uuid: ID) {
            area(uuid: $uuid) {
                children {
                    area_name
                    uuid
                }
            }
        }
        """

        data = self._query(query, {"uuid": self.USA_UUID})

        states = []
        if data and "area" in data and data["area"]:
            for child in data["area"].get("children", []):
                name = child.get("area_name", "")
                uuid = child.get("uuid", "")
                if name and uuid:
                    states.append((name, uuid))

        log.info("states_found", count=len(states))
        return states

    def get_areas_from_listing(self, state_uuid: str) -> list[OpenBetaArea]:
        """
        Get all climbing areas within a state.

        Returns areas at the first level of children.
        """
        query = """
        query GetStateAreas($uuid: ID) {
            area(uuid: $uuid) {
                area_name
                children {
                    area_name
                    uuid
                    metadata {
                        lat
                        lng
                    }
                    pathTokens
                }
            }
        }
        """

        data = self._query(query, {"uuid": state_uuid})

        areas = []
        if data and "area" in data and data["area"]:
            for child in data["area"].get("children", []):
                name = child.get("area_name", "")
                uuid = child.get("uuid", "")
                metadata = child.get("metadata", {})
                lat = metadata.get("lat")
                lng = metadata.get("lng")
                path = child.get("pathTokens", [])

                if name and uuid:
                    areas.append(OpenBetaArea(
                        id=uuid,
                        name=name,
                        latitude=lat or 0.0,
                        longitude=lng or 0.0,
                        url=f"{self.BASE_WEB_URL}/{uuid}",
                        path=path,
                    ))

        log.info("areas_from_listing", uuid=state_uuid, count=len(areas))
        return areas

    def get_area_details(self, area_uuid: str) -> Optional[OpenBetaArea]:
        """
        Get detailed information about a specific area.

        Returns area with coordinates if available.
        """
        query = """
        query GetAreaDetails($uuid: ID) {
            area(uuid: $uuid) {
                area_name
                uuid
                metadata {
                    lat
                    lng
                }
                pathTokens
                ancestors
            }
        }
        """

        data = self._query(query, {"uuid": area_uuid})

        if not data or "area" not in data or not data["area"]:
            log.debug("area_not_found", uuid=area_uuid)
            return None

        area = data["area"]
        name = area.get("area_name", "Unknown")
        uuid = area.get("uuid", area_uuid)
        metadata = area.get("metadata", {})
        lat = metadata.get("lat")
        lng = metadata.get("lng")
        path = area.get("pathTokens", [])

        if lat is None or lng is None:
            log.debug("area_no_coordinates", uuid=area_uuid, name=name)
            return None

        log.info("area_details_found", name=name, lat=lat, lon=lng)
        return OpenBetaArea(
            id=uuid,
            name=name,
            latitude=lat,
            longitude=lng,
            url=f"{self.BASE_WEB_URL}/{uuid}",
            path=path,
        )

    def get_all_areas_recursive(self, parent_uuid: str = None, max_depth: int = 3) -> list[OpenBetaArea]:
        """
        Recursively fetch all areas with coordinates.

        This is a more efficient approach that fetches children in a single query.
        """
        if parent_uuid is None:
            parent_uuid = self.USA_UUID

        # Build a deep query based on max_depth
        children_fragment = self._build_children_fragment(max_depth)

        query = f"""
        query GetAreasRecursive($uuid: ID) {{
            area(uuid: $uuid) {{
                area_name
                uuid
                metadata {{ lat lng }}
                pathTokens
                {children_fragment}
            }}
        }}
        """

        data = self._query(query, {"uuid": parent_uuid})

        if not data or "area" not in data:
            return []

        # Flatten the recursive structure
        areas = []
        self._extract_areas_recursive(data["area"], areas)

        log.info("recursive_areas_found", count=len(areas))
        return areas

    def _build_children_fragment(self, depth: int) -> str:
        """Build nested children GraphQL fragment."""
        if depth <= 0:
            return ""

        inner = self._build_children_fragment(depth - 1)
        return f"""
        children {{
            area_name
            uuid
            metadata {{ lat lng }}
            pathTokens
            {inner}
        }}
        """

    def _extract_areas_recursive(self, node: dict, areas: list):
        """Extract areas from nested structure."""
        if not node:
            return

        # Check if this node has valid coordinates
        metadata = node.get("metadata", {})
        lat = metadata.get("lat")
        lng = metadata.get("lng")

        if lat is not None and lng is not None:
            areas.append(OpenBetaArea(
                id=node.get("uuid", ""),
                name=node.get("area_name", "Unknown"),
                latitude=lat,
                longitude=lng,
                url=f"{self.BASE_WEB_URL}/{node.get('uuid', '')}",
                path=node.get("pathTokens", []),
            ))

        # Recurse into children
        for child in node.get("children", []):
            self._extract_areas_recursive(child, areas)
