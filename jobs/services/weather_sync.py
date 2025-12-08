"""Service for syncing weather data from Open-Meteo."""
import time
import structlog
from datetime import datetime, date, timedelta

from sqlalchemy.dialects.mysql import insert

from config import get_settings
from db import get_session, Crag, Precipitation
from clients import OpenMeteoClient

log = structlog.get_logger()


class WeatherSyncService:
    """Service for fetching and storing weather data."""

    def __init__(self):
        self.settings = get_settings()
        self.client = OpenMeteoClient()
        self.stats = {
            "crags_processed": 0,
            "weather_records_created": 0,
            "errors": 0,
        }

    def close(self):
        self.client.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def sync_all_crags(self, days: int = 14, limit: int = None) -> dict:
        """
        Fetch weather data for all crags.

        Args:
            days: Number of days of history to fetch
            limit: Optional limit on crags to process

        Returns:
            Stats dictionary
        """
        log.info("weather_sync_starting", days=days)

        session = get_session()

        try:
            query = session.query(Crag)
            if limit:
                query = query.limit(limit)

            crags = query.all()
            log.info("crags_to_process", count=len(crags))

            for crag in crags:
                try:
                    self._sync_crag_weather(session, crag, days)
                    self.stats["crags_processed"] += 1

                    # Rate limiting
                    time.sleep(self.settings.request_delay_seconds)

                except Exception as e:
                    log.error("crag_weather_failed", crag_id=crag.id, error=str(e))
                    self.stats["errors"] += 1

                if self.stats["crags_processed"] % 50 == 0:
                    log.info("weather_sync_progress", **self.stats)
                    session.commit()  # Intermediate commit

            session.commit()

        finally:
            session.close()

        log.info("weather_sync_complete", **self.stats)
        return self.stats

    def sync_crag(self, crag_id: str, days: int = 14) -> dict:
        """Sync weather for a single crag."""
        session = get_session()

        try:
            crag = session.query(Crag).filter(Crag.id == crag_id).first()
            if not crag:
                raise ValueError(f"Crag not found: {crag_id}")

            self._sync_crag_weather(session, crag, days)
            session.commit()

            return {"crag_id": crag_id, "status": "success"}

        finally:
            session.close()

    def _sync_crag_weather(self, session, crag: Crag, days: int):
        """Fetch and store weather for a single crag."""
        # Calculate date range (Open-Meteo has ~5 day delay)
        end_date = date.today() - timedelta(days=5)
        start_date = end_date - timedelta(days=days)

        weather_data = self.client.get_historical_weather(
            latitude=float(crag.latitude),
            longitude=float(crag.longitude),
            start_date=start_date,
            end_date=end_date,
        )

        for w in weather_data:
            record = {
                "crag_id": crag.id,
                "recorded_at": datetime.combine(w.date, datetime.min.time()),
                "precipitation_mm": w.precipitation_mm,
                "temperature_max_c": w.temperature_max_c,
                "temperature_min_c": w.temperature_min_c,
            }

            stmt = insert(Precipitation).values(**record)
            upsert_stmt = stmt.on_duplicate_key_update(
                precipitation_mm=stmt.inserted.precipitation_mm,
                temperature_max_c=stmt.inserted.temperature_max_c,
                temperature_min_c=stmt.inserted.temperature_min_c,
            )

            session.execute(upsert_stmt)
            self.stats["weather_records_created"] += 1

        log.debug("crag_weather_synced", crag_id=crag.id, crag_name=crag.name, records=len(weather_data))

    def get_crag_precipitation_summary(self, crag_id: str, days: int = 7) -> dict:
        """Get precipitation summary for a crag."""
        session = get_session()

        try:
            crag = session.query(Crag).filter(Crag.id == crag_id).first()
            if not crag:
                return {"error": "Crag not found"}

            cutoff = datetime.utcnow() - timedelta(days=days + 5)  # Account for API delay

            records = (
                session.query(Precipitation)
                .filter(Precipitation.crag_id == crag_id)
                .filter(Precipitation.recorded_at >= cutoff)
                .order_by(Precipitation.recorded_at.desc())
                .all()
            )

            total_mm = sum(float(r.precipitation_mm) for r in records)

            last_rain = None
            days_since_rain = None
            for r in records:
                if float(r.precipitation_mm) > 0.1:
                    last_rain = r.recorded_at.date()
                    days_since_rain = (date.today() - last_rain).days
                    break

            return {
                "crag_id": crag_id,
                "crag_name": crag.name,
                "total_precipitation_mm": total_mm,
                "last_rain_date": last_rain.isoformat() if last_rain else None,
                "days_since_rain": days_since_rain,
                "records_count": len(records),
            }

        finally:
            session.close()
