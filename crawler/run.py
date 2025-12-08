# run.py
import os
from dotenv import load_dotenv
from crawler import MountainProjectCrawler

load_dotenv()

if __name__ == "__main__":
    start_url = "https://www.mountainproject.com/route-guide"

    crawler = MountainProjectCrawler(
        db_url=os.getenv("DATABASE_URL"),
        headless=True,
        max_depth=5,
        batch_size=5
        )
    crawler.crawl(start_url)
    crawler.shutdown()

    print(f"\n✅ Finished. Crawled {len(crawler.results)} areas.\n")
    for node in crawler.results:
        print(node)