"""Configuration settings for jobs."""
import os
from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    # Database
    database_url: str = "mysql+pymysql://root:localpass@localhost:3306/climbit"

    # Open-Meteo API (free, no key needed)
    weather_api_base_url: str = "https://archive-api.open-meteo.com/v1/archive"

    # Safety thresholds (configurable)
    # Days since rain to consider "safe"
    safe_days_threshold: int = 3
    # Days since rain to consider "caution" (between safe and unsafe)
    caution_days_threshold: int = 1
    # Precipitation in last 7 days (mm) to trigger caution
    weekly_precip_caution_mm: float = 10.0
    # Precipitation in last 7 days (mm) to trigger unsafe
    weekly_precip_unsafe_mm: float = 25.0

    # Job settings
    batch_size: int = 100
    request_delay_seconds: float = 0.5  # Be nice to APIs

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"


@lru_cache
def get_settings() -> Settings:
    return Settings()
