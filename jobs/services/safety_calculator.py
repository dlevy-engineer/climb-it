"""Service for calculating crag safety status based on precipitation."""
import structlog
from datetime import datetime, date, timedelta

from config import get_settings
from db import get_session, Crag, Precipitation, SafetyStatus

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
        """Calculate and update safety status for all crags."""
        log.info("safety_calculation_starting")

        session = get_session()

        try:
            crags = session.query(Crag).all()
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
            crag = session.query(Crag).filter(Crag.id == crag_id).first()
            if not crag:
                raise ValueError(f"Crag not found: {crag_id}")

            status = self._calculate_for_crag(session, crag)
            if status:
                crag.safety_status = status
                session.commit()

            return status

        finally:
            session.close()

    def _calculate_for_crag(self, session, crag: Crag) -> SafetyStatus | None:
        """
        Calculate safety status based on precipitation records.

        Returns None if no precipitation data available.
        """
        # Get precipitation data for last 14 days (accounting for API delay)
        cutoff = datetime.utcnow() - timedelta(days=19)

        records = (
            session.query(Precipitation)
            .filter(Precipitation.crag_id == crag.id)
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
            crag = session.query(Crag).filter(Crag.id == crag_id).first()
            if not crag:
                return {"error": "Crag not found"}

            cutoff = datetime.utcnow() - timedelta(days=19)

            records = (
                session.query(Precipitation)
                .filter(Precipitation.crag_id == crag_id)
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
