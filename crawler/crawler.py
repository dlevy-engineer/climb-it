# crawler.py

import time
from bs4 import BeautifulSoup
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait

from db_writer import CragDBWriter
from models import AreaNode
from utils import normalize_url
from page_parser import extract_name, extract_area_links, extract_coordinates, extract_location_breadcrumbs


class MountainProjectCrawler:
    def __init__(self, db_url: str, headless: bool = True, max_depth: int = 10, batch_size: int = 1000):
        """
        Initialize crawler instance.

        Args:
            db_url (str): SQLAlchemy-compatible DB URL.
            headless (bool): Run browser in headless mode.
            max_depth (int): Max recursion depth when crawling.
            batch_size (int): Number of results to hold before writing to DB.
        """
        self.found = set()  # 🧠 Tracks all discovered URLs to avoid duplication
        self.results: list[AreaNode] = []
        self.max_depth = max_depth
        self.batch_size = batch_size
        self.driver = self._init_driver(headless)
        self.writer = CragDBWriter(db_url)

    def _init_driver(self, headless: bool) -> webdriver.Chrome:
        """Initialize Selenium Chrome driver."""
        options = Options()
        if headless:
            options.add_argument("--headless")
        options.add_argument("--disable-gpu")
        options.add_argument("--no-sandbox")
        return webdriver.Chrome(options=options)

    def _render_page(self, url: str) -> BeautifulSoup:
        """
        Load and return a fully rendered BeautifulSoup object for a given URL.
        Scrolls the page to ensure lazy-loaded elements are captured.
        """
        self.driver.get(url)

        try:
            WebDriverWait(self.driver, 10).until(
                lambda d: len(d.find_elements(By.XPATH, "//a[contains(@href, '/area/')]")) > 2
            )
            self.driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
            time.sleep(0.5)
        except Exception as e:
            print(f"⚠️ Timeout or incomplete render on {url}: {e}")

        html = self.driver.page_source
        return BeautifulSoup(html, "html.parser")

    def _flush_batch_to_db(self):
        """
        Flush current batch of AreaNodes to the database and clear local buffer.
        """
        print(f"🚚 Writing {len(self.results)} records to DB...")
        self.writer.upsert_crags(self.results)
        self.results.clear()

    def crawl(self, url: str, parent_url: str | None = None, depth: int = 0):
        """
        Recursively crawl Mountain Project area pages.

        Args:
            url (str): URL to crawl.
            parent_url (str | None): Parent area's URL.
            depth (int): Current recursion depth.
        """
        norm_url = normalize_url(url)

        # ❌ Already found or exceeded max depth
        if norm_url in self.found or depth > self.max_depth:
            return

        # ✅ Mark this URL as discovered early to prevent duplicate traversal
        self.found.add(norm_url)
        print(f"{'  '*depth}↳ Crawling: {norm_url} (parent: {parent_url})")

        try:
            soup = self._render_page(norm_url)
        except Exception as e:
            print(f"❌ Error loading {norm_url}: {e}")
            return

        name = extract_name(soup)
        child_links = extract_area_links(soup)
        location_hierarchy = extract_location_breadcrumbs(soup)

        lat, lon, google_maps_url = extract_coordinates(str(soup))

        self.results.append(AreaNode(
            url=norm_url,
            name=name,
            parent_url=parent_url,
            latitude=lat,
            longitude=lon,
            google_maps_url=google_maps_url,
            location_hierarchy=location_hierarchy
        ))

        print(f"{'  '*depth}🧠 Total areas in memory: {len(self.results)}")

        # 🧹 Flush to DB if batch size is reached
        if len(self.results) >= self.batch_size:
            self._flush_batch_to_db()

        print(f"{'  '*depth}🧭 Found {len(child_links)} child links")

        # 🔁 Recurse into child area links
        for link in child_links:
            norm_link = normalize_url(link)
            if norm_link not in self.found:
                print(f"{'  '*depth}    📎 Recursing into: {norm_link}")
                self.crawl(norm_link, parent_url=norm_url, depth=depth + 1)
            else:
                print(f"{'  '*depth}    🚫 Already discovered: {norm_link}")

    def shutdown(self):
        """Flush any remaining results and cleanly shut down browser."""
        if self.results:
            print("💾 Final DB flush before shutdown...")
            self._flush_batch_to_db()
        self.driver.quit()
