"""Service for calculating crag safety status based on precipitation."""
import structlog
from dataclasses import dataclass
from datetime import datetime, date, timedelta
from typing import Optional

from config import get_settings
from db import get_session, Area, Precipitation, SafetyStatus
from clients import OpenMeteoClient


@dataclass
class DayForecast:
    """Forecast for a single day."""
    date: date
    predicted_status: str  # SAFE, CAUTION, UNSAFE
    precipitation_mm: float
    temp_high_c: Optional[float] = None
    temp_low_c: Optional[float] = None
    weather_icon: str = "sun.max"  # SF Symbol name

log = structlog.get_logger()


class SafetyCalculator:
    """
    Calculates safety status for crags based on precipitation data.

    Safety Rules (configurable in settings):
    - SAFE: No rain in last N days (default: 3) AND < X mm in last 7 days
    - CAUTION: Rain 1-3 days ago OR moderate precipitation
    - UNSAFE: Rain yesterday OR heavy precipitation in last 7 days
    """

    def __init__(self):
        self.settings = get_settings()
        self.stats = {
            "crags_processed": 0,
            "status_safe": 0,
            "status_caution": 0,
            "status_unsafe": 0,
            "no_data": 0,
        }

    def calculate_all(self) -> dict:
        """Calculate and update safety status for all crags (areas with coordinates)."""
        log.info("safety_calculation_starting")

        session = get_session()

        try:
            # Only query areas with coordinates (actual crags)
            crags = session.query(Area).filter(Area.latitude.isnot(None)).all()
            log.info("crags_to_calculate", count=len(crags))

            for crag in crags:
                status = self._calculate_for_crag(session, crag)
                if status:
                    crag.safety_status = status
                    self.stats[f"status_{status.value.lower()}"] += 1
                else:
                    self.stats["no_data"] += 1

                self.stats["crags_processed"] += 1

            session.commit()

        finally:
            session.close()

        log.info("safety_calculation_complete", **self.stats)
        return self.stats

    def calculate_for_crag(self, crag_id: str) -> SafetyStatus:
        """Calculate safety status for a single crag."""
        session = get_session()

        try:
            crag = session.query(Area).filter(Area.id == crag_id).first()
            if not crag:
                raise ValueError(f"Crag not found: {crag_id}")

            status = self._calculate_for_crag(session, crag)
            if status:
                crag.safety_status = status
                session.commit()

            return status

        finally:
            session.close()

    def _calculate_for_crag(self, session, crag: Area) -> SafetyStatus | None:
        """
        Calculate safety status based on precipitation records.

        Returns None if no precipitation data available.
        """
        # Get precipitation data for last 14 days (accounting for API delay)
        cutoff = datetime.utcnow() - timedelta(days=19)

        records = (
            session.query(Precipitation)
            .filter(Precipitation.area_id == crag.id)
            .filter(Precipitation.recorded_at >= cutoff)
            .order_by(Precipitation.recorded_at.desc())
            .all()
        )

        if not records:
            log.debug("no_precipitation_data", crag_id=crag.id)
            return None

        # Calculate metrics
        total_7_days = 0.0
        days_since_rain = None
        today = date.today()

        for r in records:
            record_date = r.recorded_at.date()
            days_ago = (today - record_date).days

            # Sum last 7 days of data we have
            if days_ago <= 12:  # 7 days + 5 day API delay
                total_7_days += float(r.precipitation_mm)

            # Find most recent rain
            if days_since_rain is None and float(r.precipitation_mm) > 0.1:
                days_since_rain = days_ago

        # Apply rules
        status = self._apply_rules(total_7_days, days_since_rain)

        log.debug(
            "safety_calculated",
            crag_id=crag.id,
            crag_name=crag.name,
            total_7_days_mm=total_7_days,
            days_since_rain=days_since_rain,
            status=status.value,
        )

        return status

    def _apply_rules(self, total_7_days_mm: float, days_since_rain: int | None) -> SafetyStatus:
        """
        Apply safety rules to determine status.

        Rules (from settings):
        - UNSAFE if:
          - Heavy precipitation (>25mm) in last 7 days, OR
          - Rain within last day (days_since_rain <= 1)
        - CAUTION if:
          - Moderate precipitation (>10mm) in last 7 days, OR
          - Rain within last 3 days
        - SAFE otherwise
        """
        # UNSAFE conditions
        if total_7_days_mm >= self.settings.weekly_precip_unsafe_mm:
            return SafetyStatus.UNSAFE

        if days_since_rain is not None and days_since_rain <= self.settings.caution_days_threshold:
            return SafetyStatus.UNSAFE

        # CAUTION conditions
        if total_7_days_mm >= self.settings.weekly_precip_caution_mm:
            return SafetyStatus.CAUTION

        if days_since_rain is not None and days_since_rain <= self.settings.safe_days_threshold:
            return SafetyStatus.CAUTION

        # SAFE
        return SafetyStatus.SAFE

    def explain_status(self, crag_id: str) -> dict:
        """Get detailed explanation of a crag's safety status."""
        session = get_session()

        try:
            crag = session.query(Area).filter(Area.id == crag_id).first()
            if not crag:
                return {"error": "Crag not found"}

            cutoff = datetime.utcnow() - timedelta(days=19)

            records = (
                session.query(Precipitation)
                .filter(Precipitation.area_id == crag_id)
                .filter(Precipitation.recorded_at >= cutoff)
                .order_by(Precipitation.recorded_at.desc())
                .all()
            )

            total_7_days = 0.0
            days_since_rain = None
            last_rain_date = None
            daily_precip = []
            today = date.today()

            for r in records:
                record_date = r.recorded_at.date()
                days_ago = (today - record_date).days
                precip_mm = float(r.precipitation_mm)

                daily_precip.append({
                    "date": record_date.isoformat(),
                    "days_ago": days_ago,
                    "precipitation_mm": precip_mm,
                })

                if days_ago <= 12:
                    total_7_days += precip_mm

                if days_since_rain is None and precip_mm > 0.1:
                    days_since_rain = days_ago
                    last_rain_date = record_date

            status = self._apply_rules(total_7_days, days_since_rain)

            return {
                "crag_id": crag_id,
                "crag_name": crag.name,
                "current_status": crag.safety_status.value if crag.safety_status else None,
                "calculated_status": status.value,
                "metrics": {
                    "total_7_days_mm": round(total_7_days, 1),
                    "days_since_rain": days_since_rain,
                    "last_rain_date": last_rain_date.isoformat() if last_rain_date else None,
                },
                "thresholds": {
                    "safe_days_threshold": self.settings.safe_days_threshold,
                    "caution_days_threshold": self.settings.caution_days_threshold,
                    "weekly_precip_caution_mm": self.settings.weekly_precip_caution_mm,
                    "weekly_precip_unsafe_mm": self.settings.weekly_precip_unsafe_mm,
                },
                "daily_precipitation": daily_precip[:14],  # Last 14 days
            }

        finally:
            session.close()

    def get_forecast(self, crag_id: str, days: int = 7) -> list[DayForecast]:
        """
        Get safety forecast for a crag for the next N days.

        Uses weather forecast data to predict when a crag will become safe.

        Args:
            crag_id: The crag ID
            days: Number of days to forecast (max 14)

        Returns:
            List of DayForecast objects
        """
        session = get_session()

        try:
            crag = session.query(Area).filter(Area.id == crag_id).first()
            if not crag:
                log.warning("crag_not_found", crag_id=crag_id)
                return []

            # Get historical precipitation to calculate initial state
            cutoff = datetime.utcnow() - timedelta(days=14)
            records = (
                session.query(Precipitation)
                .filter(Precipitation.area_id == crag_id)
                .filter(Precipitation.recorded_at >= cutoff)
                .order_by(Precipitation.recorded_at.desc())
                .all()
            )

            # Build recent precipitation history (last 7 days)
            today = date.today()
            recent_precip = []  # List of (date, mm) for last 7 days
            for r in records:
                record_date = r.recorded_at.date()
                days_ago = (today - record_date).days
                if days_ago <= 12:  # Account for API delay
                    recent_precip.append((record_date, float(r.precipitation_mm)))

            # Get forecast
            weather_client = OpenMeteoClient()
            try:
                forecast = weather_client.get_forecast(
                    latitude=float(crag.latitude),
                    longitude=float(crag.longitude),
                    days=min(days, 14)
                )
            finally:
                weather_client.close()

            # Calculate predicted status for each day
            results = []
            # Start with historical data, then extend with forecast
            combined_precip = recent_precip.copy()

            for day_weather in forecast:
                # Add this day's forecast precipitation
                combined_precip.append((day_weather.date, day_weather.precipitation_mm))

                # Calculate 7-day rolling sum ending on this day
                rolling_sum = 0.0
                days_since_rain = None

                for precip_date, precip_mm in sorted(combined_precip, key=lambda x: x[0], reverse=True):
                    days_diff = (day_weather.date - precip_date).days
                    if 0 <= days_diff <= 7:
                        rolling_sum += precip_mm
                    if days_since_rain is None and precip_mm > 0.1:
                        days_since_rain = days_diff

                # Apply safety rules
                status = self._apply_rules(rolling_sum, days_since_rain)

                # Determine weather icon based on precipitation
                if day_weather.precipitation_mm > 5.0:
                    weather_icon = "cloud.rain.fill"
                elif day_weather.precipitation_mm > 1.0:
                    weather_icon = "cloud.drizzle.fill"
                elif day_weather.precipitation_mm > 0.1:
                    weather_icon = "cloud.fill"
                else:
                    weather_icon = "sun.max.fill"

                results.append(DayForecast(
                    date=day_weather.date,
                    predicted_status=status.value,
                    precipitation_mm=day_weather.precipitation_mm,
                    temp_high_c=day_weather.temperature_max_c,
                    temp_low_c=day_weather.temperature_min_c,
                    weather_icon=weather_icon,
                ))

            log.info("forecast_calculated", crag_id=crag_id, crag_name=crag.name, days=len(results))
            return results

        finally:
            session.close()

    def estimate_safe_date(self, crag_id: str) -> Optional[date]:
        """
        Estimate when a CAUTION/UNSAFE crag will become SAFE.

        Returns None if already safe or can't be determined within 14 days.
        """
        forecast = self.get_forecast(crag_id, days=14)

        for day in forecast:
            if day.predicted_status == "SAFE":
                return day.date

        return None  # Won't be safe in the next 14 days
