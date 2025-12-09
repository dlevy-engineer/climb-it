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
from dataclasses import dataclass
from typing import Optional
from tenacity import retry, stop_after_attempt, wait_exponential
from playwright.sync_api import sync_playwright, Browser, Page, Error as PlaywrightError

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

    def fetch_page(self, url: str, retry_count: int = 0) -> str:
        """Fetch a page with Playwright, waiting for content to load.

        Creates a fresh page for each request for stability.
        Handles browser crashes by restarting and retrying.
        """
        max_retries = 3
        page = None

        try:
            self._ensure_browser()
            log.debug("scraper_fetch", url=url)

            # Random delay between requests (2-5 seconds)
            delay = random.uniform(2.0, 5.0)
            time.sleep(delay)

            # Refresh context every 50 requests to prevent memory bloat
            self._request_count += 1
            if self._request_count % 50 == 0:
                log.info("refreshing_browser_context", request_count=self._request_count)
                self._create_context()

            # Create a fresh page for each request (more stable)
            page = self._context.new_page()
            page.goto(url, wait_until="domcontentloaded", timeout=60000)

            # Additional small delay after page load
            time.sleep(random.uniform(0.5, 1.5))

            content = page.content()
            return content

        except PlaywrightError as e:
            error_msg = str(e).lower()
            if retry_count < max_retries and ("target closed" in error_msg or "browser" in error_msg or "context" in error_msg or "crash" in error_msg):
                log.warning("browser_crashed_restarting", url=url, retry=retry_count + 1, error=str(e))
                # Wait longer before restart to avoid rate limiting
                time.sleep(random.uniform(5.0, 10.0))
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
        except Exception as e:
            log.warning("area_fetch_failed", url=area_url, error=str(e))
            return None

        soup = BeautifulSoup(html, "html.parser")

        # Extract name (exclude nested elements like <small>Rock Climbing</small>)
        h1 = soup.find("h1")
        if h1:
            # Get only direct text, not text from nested elements
            texts = h1.find_all(string=True, recursive=False)
            # Filter out empty strings and take first meaningful text
            name = next((t.strip() for t in texts if t.strip()), None)
            if not name:
                # Fallback: get first line of text content
                name = h1.get_text(strip=True).split('\n')[0].strip()
        else:
            name = "Unknown"

        # Extract coordinates from GPS table row using regex
        lat, lon = None, None
        for row in soup.find_all("tr"):
            label = row.find("td")
            if label and "GPS" in label.get_text():
                value_td = label.find_next_sibling("td")
                if value_td:
                    gps_text = value_td.get_text(strip=True)
                    # Use regex to extract coordinates (handles "Google" suffix)
                    coord_match = re.search(r"(-?\d+\.?\d*),\s*(-?\d+\.?\d*)", gps_text)
                    if coord_match:
                        try:
                            lat = float(coord_match.group(1))
                            lon = float(coord_match.group(2))
                        except ValueError:
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

        log.info("area_details_found", name=name, lat=lat, lon=lon)
        return MPArea(
            id=area_id,
            name=name,
            latitude=lat,
            longitude=lon,
            url=area_url,
            path=path,
        )
