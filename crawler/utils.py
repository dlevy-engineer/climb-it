# utils.py
from urllib.parse import urlparse, urlunparse

def normalize_url(url: str) -> str:
    """Normalize Mountain Project URLs to avoid duplicate crawling."""
    parsed = urlparse(url)
    
    # Remove query string, fragments, and 'classics' path prefix
    clean_path = parsed.path.replace('/classics', '')  # normalize path
    clean_path = clean_path.rstrip('/')  # remove trailing slash

    return urlunparse(('https', 'www.mountainproject.com', clean_path, '', '', ''))