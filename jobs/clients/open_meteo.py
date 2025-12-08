"""Open-Meteo weather API client.

API Documentation: https://open-meteo.com/en/docs/historical-weather-api

Open-Meteo is free for non-commercial use, no API key required.
Rate limit: 10,000 requests/day for free tier.
"""
import httpx
import structlog
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Optional
from tenacity import retry, stop_after_attempt, wait_exponential

from config import get_settings

log = structlog.get_logger()


@dataclass
class DailyWeather:
    """Daily weather data for a location."""
    date: date
    precipitation_mm: float
    temperature_max_c: Optional[float] = None
    temperature_min_c: Optional[float] = None
    precipitation_hours: Optional[float] = None


class OpenMeteoClient:
    """Client for Open-Meteo Historical Weather API."""

    def __init__(self):
        settings = get_settings()
        self.base_url = settings.weather_api_base_url
        self.client = httpx.Client(timeout=30.0)

    def close(self):
        self.client.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
    def get_historical_weather(
        self,
        latitude: float,
        longitude: float,
        start_date: date,
        end_date: date,
    ) -> list[DailyWeather]:
        """
        Get historical daily weather data for a location.

        Args:
            latitude: Location latitude
            longitude: Location longitude
            start_date: Start date (inclusive)
            end_date: End date (inclusive)

        Returns:
            List of DailyWeather objects
        """
        params = {
            "latitude": latitude,
            "longitude": longitude,
            "start_date": start_date.isoformat(),
            "end_date": end_date.isoformat(),
            "daily": "precipitation_sum,temperature_2m_max,temperature_2m_min,precipitation_hours",
            "timezone": "auto",
        }

        log.debug("weather_api_request", lat=latitude, lon=longitude, start=start_date, end=end_date)

        response = self.client.get(self.base_url, params=params)
        response.raise_for_status()

        data = response.json()
        daily = data.get("daily", {})

        dates = daily.get("time", [])
        precip = daily.get("precipitation_sum", [])
        temp_max = daily.get("temperature_2m_max", [])
        temp_min = daily.get("temperature_2m_min", [])
        precip_hours = daily.get("precipitation_hours", [])

        results = []
        for i, date_str in enumerate(dates):
            results.append(DailyWeather(
                date=datetime.fromisoformat(date_str).date(),
                precipitation_mm=precip[i] if i < len(precip) and precip[i] is not None else 0.0,
                temperature_max_c=temp_max[i] if i < len(temp_max) else None,
                temperature_min_c=temp_min[i] if i < len(temp_min) else None,
                precipitation_hours=precip_hours[i] if i < len(precip_hours) else None,
            ))

        log.info("weather_fetched", lat=latitude, lon=longitude, days=len(results))
        return results

    def get_last_n_days(
        self,
        latitude: float,
        longitude: float,
        days: int = 7,
    ) -> list[DailyWeather]:
        """
        Convenience method to get weather for the last N days.

        Note: Open-Meteo historical API has a ~5 day delay,
        so "last 7 days" is really 5-12 days ago.
        """
        # Historical API has delay, so we go back further
        end_date = date.today() - timedelta(days=5)
        start_date = end_date - timedelta(days=days)

        return self.get_historical_weather(latitude, longitude, start_date, end_date)

    def get_recent_precipitation(
        self,
        latitude: float,
        longitude: float,
        days: int = 7,
    ) -> tuple[float, Optional[date], Optional[int]]:
        """
        Get precipitation summary for recent days.

        Returns:
            Tuple of (total_mm, last_rain_date, days_since_rain)
        """
        weather = self.get_last_n_days(latitude, longitude, days)

        total_mm = sum(w.precipitation_mm for w in weather)
        last_rain_date = None
        days_since_rain = None

        # Find most recent day with precipitation
        for w in sorted(weather, key=lambda x: x.date, reverse=True):
            if w.precipitation_mm > 0.1:  # > 0.1mm counts as rain
                last_rain_date = w.date
                days_since_rain = (date.today() - w.date).days
                break

        return total_mm, last_rain_date, days_since_rain
