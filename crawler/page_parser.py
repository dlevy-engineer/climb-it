# page_parser.py
import re

from bs4 import BeautifulSoup
from urllib.parse import urljoin

BASE_DOMAIN = "https://www.mountainproject.com"
AREA_PREFIX = "/area/"


def extract_name(soup: BeautifulSoup) -> str:
    """Get the name of the area from the page <h1>."""
    h1 = soup.find("h1")
    return h1.get_text(strip=True) if h1 else "UNKNOWN"


def extract_coordinates(html: str):
    soup = BeautifulSoup(html, 'html.parser')
    gps_text = None
    google_maps_url = None

    rows = soup.find_all('tr')
    for row in rows:
        label = row.find('td')
        if not label or not label.text:
            continue
        label_text = label.text.strip()

        if 'GPS' in label_text:
            gps_value_td = label.find_next_sibling('td')
            if gps_value_td:
                gps_text = gps_value_td.text.strip()
                print(f"🛰 Found GPS text: {gps_text}")

        if 'Google Map' in label_text:
            map_td = row.find_next_sibling('td')
            if map_td:
                a_tag = map_td.find('a')
                if a_tag and a_tag.has_attr('href'):
                    google_maps_url = a_tag['href']
                    print(f"🗺 Found Google Maps URL: {google_maps_url}")

    if not gps_text:
        print("⚠️ No GPS text found.")
        return None, None, google_maps_url

    try:
        # Split on comma, strip each part, and remove extra tokens after longitude
        parts = gps_text.split(',')
        if len(parts) != 2:
            raise ValueError("Invalid GPS format")

        lat_str = parts[0].strip()
        lon_str = parts[1].strip().split()[0]  # take only the first token

        lat = float(lat_str)
        lon = float(lon_str)
        return lat, lon, google_maps_url

    except Exception as e:
        print(f"❌ Failed to parse coordinates: {e}")
        return None, None, google_maps_url


def extract_area_links(soup: BeautifulSoup) -> list[str]:
    links = []
    for tag in soup.find_all("a", href=True):
        href = tag["href"]
        if href.startswith(BASE_DOMAIN + AREA_PREFIX):
            full_url = urljoin(BASE_DOMAIN, href)
            links.append(full_url)

    print(f"📦 extract_area_links() found {len(links)} area links")
    return links


def extract_location_breadcrumbs(soup: BeautifulSoup) -> dict | None:
    """
    Extracts breadcrumbs as a nested dict representing the area hierarchy.

    Returns:
        Nested dictionary like:
        { name: ..., url: ..., child: { name: ..., url: ..., ... } }
    """
    breadcrumb_div = soup.find('div', class_='mb-half small text-warm')
    if not breadcrumb_div:
        return None

    links = breadcrumb_div.find_all('a')
    nested = None
    for a in reversed(links):
        name = a.get_text(strip=True)
        url = a.get('href')
        if not name or not url:
            continue
        full_url = url if url.startswith('http') else f"https://www.mountainproject.com{url}"
        nested = {
            "name": name,
            "url": full_url,
            "child": nested
        }

    return nested
