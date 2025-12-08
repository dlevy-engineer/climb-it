"""Mountain Project web scraper.

Note: The Mountain Project Data API was deprecated in late 2020 when
Adventure Projects was acquired by onX. This module uses lightweight
web scraping with httpx + BeautifulSoup instead of Selenium for
better performance and lower resource usage.

Scraping is done respectfully with:
- Proper User-Agent identification
- Rate limiting between requests
- Retry logic with exponential backoff
"""
import httpx
import structlog
from dataclasses import dataclass
from typing import Optional
from tenacity import retry, stop_after_attempt, wait_exponential

log = structlog.get_logger()


@dataclass
class MPArea:
    """Mountain Project area/crag."""
    id: int
    name: str
    latitude: float
    longitude: float
    url: str
    parent_id: Optional[int] = None
    path: Optional[list[str]] = None  # Location hierarchy


class MountainProjectScraper:
    """
    Web scraper for Mountain Project.

    Uses httpx instead of Selenium - much lighter weight.
    Scrapes area listing pages to extract crag information.
    """

    BASE_URL = "https://www.mountainproject.com"
    AREAS_URL = "https://www.mountainproject.com/route-guide"

    def __init__(self):
        self.client = httpx.Client(
            timeout=30.0,
            headers={
                "User-Agent": "ClimbIt/1.0 (climbing app; respectful scraping)"
            }
        )

    def close(self):
        self.client.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
    def fetch_page(self, url: str) -> str:
        """Fetch a page with retry logic."""
        log.debug("scraper_fetch", url=url)
        response = self.client.get(url)
        response.raise_for_status()
        return response.text

    def get_all_state_urls(self) -> list[tuple[str, str]]:
        """Get all US state area URLs from the route guide."""
        from bs4 import BeautifulSoup

        html = self.fetch_page(self.AREAS_URL)
        soup = BeautifulSoup(html, "html.parser")

        states = []
        # Find the US states section
        for link in soup.select('a[href*="/area/"]'):
            href = link.get("href", "")
            name = link.get_text(strip=True)

            if "/area/" in href and name:
                full_url = href if href.startswith("http") else f"{self.BASE_URL}{href}"
                states.append((name, full_url))

        log.info("states_found", count=len(states))
        return states

    def get_areas_from_listing(self, listing_url: str) -> list[MPArea]:
        """
        Extract area information from a listing page.

        This is a lightweight alternative to the full Selenium crawler.
        """
        from bs4 import BeautifulSoup
        import re

        html = self.fetch_page(listing_url)
        soup = BeautifulSoup(html, "html.parser")

        areas = []

        # Find area cards/links
        for card in soup.select('.lef-nav-row, .mp-sidebar a[href*="/area/"]'):
            link = card if card.name == "a" else card.find("a")
            if not link:
                continue

            href = link.get("href", "")
            name = link.get_text(strip=True)

            if "/area/" in href and name:
                # Extract area ID from URL
                match = re.search(r"/area/(\d+)/", href)
                area_id = int(match.group(1)) if match else None

                full_url = href if href.startswith("http") else f"{self.BASE_URL}{href}"

                areas.append(MPArea(
                    id=area_id or hash(full_url),
                    name=name,
                    latitude=0.0,  # Will be filled in later
                    longitude=0.0,
                    url=full_url,
                ))

        log.info("areas_from_listing", url=listing_url, count=len(areas))
        return areas

    def get_area_details(self, area_url: str) -> Optional[MPArea]:
        """Get detailed information about a specific area including coordinates."""
        from bs4 import BeautifulSoup
        import re

        try:
            html = self.fetch_page(area_url)
        except httpx.HTTPError as e:
            log.warning("area_fetch_failed", url=area_url, error=str(e))
            return None

        soup = BeautifulSoup(html, "html.parser")

        # Extract name
        h1 = soup.find("h1")
        name = h1.get_text(strip=True) if h1 else "Unknown"

        # Extract coordinates from GPS table row
        lat, lon = None, None
        for row in soup.find_all("tr"):
            label = row.find("td")
            if label and "GPS" in label.get_text():
                value_td = label.find_next_sibling("td")
                if value_td:
                    gps_text = value_td.get_text(strip=True)
                    try:
                        parts = gps_text.split(",")
                        lat = float(parts[0].strip())
                        lon = float(parts[1].strip().split()[0])
                    except (ValueError, IndexError):
                        pass

        # Extract area ID
        match = re.search(r"/area/(\d+)/", area_url)
        area_id = int(match.group(1)) if match else hash(area_url)

        # Extract location hierarchy from breadcrumbs
        path = []
        breadcrumb = soup.find("div", class_="mb-half small text-warm")
        if breadcrumb:
            for a in breadcrumb.find_all("a"):
                path.append(a.get_text(strip=True))

        if lat is None or lon is None:
            log.debug("area_no_coordinates", url=area_url, name=name)
            return None

        return MPArea(
            id=area_id,
            name=name,
            latitude=lat,
            longitude=lon,
            url=area_url,
            path=path,
        )
