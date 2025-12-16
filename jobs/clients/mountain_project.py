"""Mountain Project web scraper using Playwright.

Uses Playwright with Chromium to bypass Cloudflare bot protection.
Mountain Project uses Cloudflare which blocks simple HTTP requests.

Scraping is done respectfully with:
- Proper rate limiting between requests
- Retry logic with exponential backoff
- Browser recovery on crash
"""
import structlog
import time
import random
import re
from dataclasses import dataclass
from typing import Optional
from playwright.sync_api import sync_playwright, Browser, Page, Error as PlaywrightError

log = structlog.get_logger()


# US States and territories - only scrape these
US_STATES = {
    "alabama", "alaska", "arizona", "arkansas", "california", "colorado",
    "connecticut", "delaware", "florida", "georgia", "hawaii", "idaho",
    "illinois", "indiana", "iowa", "kansas", "kentucky", "louisiana",
    "maine", "maryland", "massachusetts", "michigan", "minnesota",
    "mississippi", "missouri", "montana", "nebraska", "nevada",
    "new-hampshire", "new-jersey", "new-mexico", "new-york",
    "north-carolina", "north-dakota", "ohio", "oklahoma", "oregon",
    "pennsylvania", "rhode-island", "south-carolina", "south-dakota",
    "tennessee", "texas", "utah", "vermont", "virginia", "washington",
    "west-virginia", "wisconsin", "wyoming", "puerto-rico", "us-virgin-islands"
}


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
    Web scraper for Mountain Project using Playwright.

    Uses Playwright + Chromium to render JavaScript and bypass
    Cloudflare's bot protection.
    """

    BASE_URL = "https://www.mountainproject.com"
    AREAS_URL = "https://www.mountainproject.com/route-guide"

    def __init__(self):
        self._playwright = None
        self._browser: Optional[Browser] = None
        self._context = None
        self._request_count = 0
        self._visited_urls: set[str] = set()  # Track visited URLs to avoid duplicates

    def _ensure_browser(self, force_restart: bool = False):
        """Lazily initialize browser on first use, or restart if crashed."""
        if force_restart:
            self._cleanup_browser()

        if self._browser is None:
            log.info("starting_playwright_browser")
            self._playwright = sync_playwright().start()
            self._browser = self._playwright.chromium.launch(
                headless=True,
                args=[
                    "--no-sandbox",
                    "--disable-setuid-sandbox",
                    "--disable-dev-shm-usage",
                ]
            )
            self._create_context()

    def _create_context(self):
        """Create a fresh browser context with stealth settings."""
        if self._context:
            try:
                self._context.close()
            except Exception:
                pass

        self._context = self._browser.new_context(
            user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            viewport={"width": 1920, "height": 1080},
            locale="en-US",
            timezone_id="America/New_York",
            java_script_enabled=True,
        )
        # Remove webdriver property to avoid detection
        self._context.add_init_script("""
            Object.defineProperty(navigator, 'webdriver', {
                get: () => undefined
            });
        """)

    def _cleanup_browser(self):
        """Clean up browser resources."""
        try:
            if self._context:
                self._context.close()
        except Exception:
            pass
        try:
            if self._browser:
                self._browser.close()
        except Exception:
            pass
        try:
            if self._playwright:
                self._playwright.stop()
        except Exception:
            pass
        self._context = None
        self._browser = None
        self._playwright = None

    def close(self):
        self._cleanup_browser()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def _normalize_url(self, url: str) -> str:
        """Normalize URL to prevent duplicates from trailing slashes, etc."""
        url = url.rstrip('/')
        if not url.startswith('http'):
            url = f"{self.BASE_URL}{url}"
        return url

    def was_visited(self, url: str) -> bool:
        """Check if URL was already visited."""
        return self._normalize_url(url) in self._visited_urls

    def mark_visited(self, url: str):
        """Mark URL as visited."""
        self._visited_urls.add(self._normalize_url(url))

    def _is_browser_crash(self, error: Exception) -> bool:
        """Check if an exception indicates a browser crash."""
        error_msg = str(error).lower()
        crash_indicators = [
            "target closed",
            "browser",
            "context",
            "crash",
            "connection closed",
            "protocol error",
            "page closed",
            "session closed",
        ]
        return any(indicator in error_msg for indicator in crash_indicators)

    def fetch_page(self, url: str, retry_count: int = 0) -> str:
        """Fetch a page with Playwright, waiting for content to load.

        Creates a fresh page for each request for stability.
        Handles browser crashes by restarting the entire browser.
        """
        max_retries = 3
        page = None

        try:
            self._ensure_browser()
            log.debug("scraper_fetch", url=url)

            # Random delay between requests (2-4 seconds)
            delay = random.uniform(2.0, 4.0)
            time.sleep(delay)

            # Refresh context every 25 requests to prevent memory bloat
            self._request_count += 1
            if self._request_count % 25 == 0:
                log.info("refreshing_browser_context", request_count=self._request_count)
                self._create_context()

            # Create a fresh page for each request (more stable)
            page = self._context.new_page()
            page.goto(url, wait_until="domcontentloaded", timeout=60000)

            # Additional small delay after page load
            time.sleep(random.uniform(0.3, 0.8))

            content = page.content()
            return content

        except Exception as e:
            # Catch ALL exceptions to handle browser crashes properly
            if retry_count < max_retries and self._is_browser_crash(e):
                log.warning("browser_crashed_restarting", url=url, retry=retry_count + 1, error=str(e))
                # Wait longer before restart (exponential backoff)
                wait_time = 5.0 * (2 ** retry_count) + random.uniform(0, 5.0)
                log.info("waiting_before_restart", seconds=wait_time)
                time.sleep(wait_time)
                # Force full browser restart
                self._ensure_browser(force_restart=True)
                return self.fetch_page(url, retry_count + 1)
            raise
        finally:
            # Always close the page after use
            if page:
                try:
                    page.close()
                except Exception:
                    pass

    def get_all_state_urls(self) -> list[tuple[str, str]]:
        """Get all US state URLs from the route guide (filtered to actual states only)."""
        from bs4 import BeautifulSoup

        html = self.fetch_page(self.AREAS_URL)
        soup = BeautifulSoup(html, "html.parser")

        areas = []
        seen_urls = set()

        # Find all area links, deduplicated and filtered to US states
        for link in soup.select('a[href*="/area/"]'):
            href = link.get("href", "")
            name = link.get_text(strip=True)

            if not href or not name:
                continue

            # Must have area ID in URL
            if not re.search(r'/area/\d+/', href):
                continue

            # Extract slug from URL to check if it's a US state
            # URL format: /area/123456/state-name
            slug_match = re.search(r'/area/\d+/([^/]+)', href)
            if not slug_match:
                continue

            slug = slug_match.group(1).lower()

            # Only include if it's a US state (using the US_STATES set)
            if slug not in US_STATES:
                continue

            # Normalize URL
            full_url = self._normalize_url(href)

            # Skip if already seen (deduplication)
            if full_url in seen_urls:
                continue

            seen_urls.add(full_url)
            areas.append((name, full_url))

        log.info("us_states_found", count=len(areas))
        return areas

    def get_area_with_children(self, area_url: str) -> tuple[Optional[MPArea], list[MPArea]]:
        """
        Fetch an area page and extract BOTH coordinates AND child areas in one request.

        Returns (area_with_coords_or_none, list_of_child_areas)
        """
        from bs4 import BeautifulSoup

        url = self._normalize_url(area_url)

        # Skip if already visited
        if self.was_visited(url):
            log.debug("skipping_visited_url", url=url)
            return None, []

        self.mark_visited(url)

        try:
            html = self.fetch_page(url)
        except Exception as e:
            log.warning("area_fetch_failed", url=url, error=str(e))
            return None, []

        soup = BeautifulSoup(html, "html.parser")

        # Extract name
        h1 = soup.find("h1")
        if h1:
            texts = h1.find_all(string=True, recursive=False)
            name = next((t.strip() for t in texts if t.strip()), None)
            if not name:
                name = h1.get_text(strip=True).split('\n')[0].strip()
        else:
            name = "Unknown"

        # Extract coordinates from GPS table row
        lat, lon = None, None
        for row in soup.find_all("tr"):
            label = row.find("td")
            if label and "GPS" in label.get_text():
                value_td = label.find_next_sibling("td")
                if value_td:
                    gps_text = value_td.get_text(strip=True)
                    coord_match = re.search(r"(-?\d+\.?\d*),\s*(-?\d+\.?\d*)", gps_text)
                    if coord_match:
                        try:
                            lat = float(coord_match.group(1))
                            lon = float(coord_match.group(2))
                        except ValueError:
                            pass

        # Extract area ID
        match = re.search(r"/area/(\d+)/", url)
        area_id = int(match.group(1)) if match else hash(url)

        # Extract location hierarchy from breadcrumbs
        path = []
        breadcrumb = soup.find("div", class_="mb-half small text-warm")
        if breadcrumb:
            for a in breadcrumb.find_all("a"):
                path.append(a.get_text(strip=True))

        # Build area object if we have coordinates
        area = None
        if lat is not None and lon is not None:
            log.info("area_details_found", name=name, lat=lat, lon=lon)
            area = MPArea(
                id=area_id,
                name=name,
                latitude=lat,
                longitude=lon,
                url=url,
                path=path,
            )

        # Extract child areas from the same page (no extra request!)
        children = []
        seen_child_urls = set()

        # Look for child area links in the left nav
        for link in soup.select('.lef-nav-row a[href*="/area/"]'):
            href = link.get("href", "")
            child_name = link.get_text(strip=True)

            if not href or not child_name:
                continue

            child_url = self._normalize_url(href)

            # Skip duplicates and already-visited URLs
            if child_url in seen_child_urls or self.was_visited(child_url):
                continue

            seen_child_urls.add(child_url)

            # Extract child area ID
            child_match = re.search(r"/area/(\d+)/", href)
            child_id = int(child_match.group(1)) if child_match else hash(child_url)

            children.append(MPArea(
                id=child_id,
                name=child_name,
                latitude=0.0,
                longitude=0.0,
                url=child_url,
            ))

        log.debug("area_children_found", url=url, count=len(children))
        return area, children

    # Keep old methods for backwards compatibility but mark as deprecated
    def get_areas_from_listing(self, listing_url: str) -> list[MPArea]:
        """DEPRECATED: Use get_area_with_children instead."""
        _, children = self.get_area_with_children(listing_url)
        return children

    def get_area_details(self, area_url: str) -> Optional[MPArea]:
        """DEPRECATED: Use get_area_with_children instead."""
        area, _ = self.get_area_with_children(area_url)
        return area
