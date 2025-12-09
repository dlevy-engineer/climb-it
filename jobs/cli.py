#!/usr/bin/env python3
"""
ClimbIt Jobs CLI

Run background jobs for data synchronization.

Usage:
    python -m cli sync-crags [--max-areas N]
    python -m cli sync-weather [--days N] [--limit N]
    python -m cli calculate-safety
    python -m cli run-all
"""
import click
import structlog
from datetime import datetime

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.dev.ConsoleRenderer(colors=True),
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

log = structlog.get_logger()


@click.group()
@click.option("--verbose", "-v", is_flag=True, help="Enable verbose logging")
def cli(verbose):
    """ClimbIt background jobs CLI."""
    import logging
    logging.basicConfig(
        format="%(message)s",
        level=logging.DEBUG if verbose else logging.INFO,
    )


@cli.command()
@click.option("--max-areas", "-m", type=int, default=None, help="Max areas to process")
@click.option("--source", "-s", type=click.Choice(["mountain-project", "openbeta"]), default="openbeta", help="Data source")
def sync_crags(max_areas, source):
    """Sync crags from Mountain Project or OpenBeta."""
    log.info("Starting crag sync", max_areas=max_areas, source=source)
    start = datetime.now()

    if source == "openbeta":
        from services.openbeta_sync import OpenBetaSyncService
        with OpenBetaSyncService() as service:
            stats = service.sync_all(max_areas=max_areas)
    else:
        from services import CragSyncService
        with CragSyncService() as service:
            stats = service.sync_all(max_areas=max_areas)

    elapsed = (datetime.now() - start).total_seconds()
    log.info("Crag sync complete", elapsed_seconds=elapsed, **stats)


@cli.command()
@click.option("--days", "-d", type=int, default=14, help="Days of weather history to fetch")
@click.option("--limit", "-l", type=int, default=None, help="Limit number of crags to process")
def sync_weather(days, limit):
    """Fetch weather data for all crags."""
    from services import WeatherSyncService

    log.info("Starting weather sync", days=days, limit=limit)
    start = datetime.now()

    with WeatherSyncService() as service:
        stats = service.sync_all_crags(days=days, limit=limit)

    elapsed = (datetime.now() - start).total_seconds()
    log.info("Weather sync complete", elapsed_seconds=elapsed, **stats)


@cli.command()
def calculate_safety():
    """Calculate safety status for all crags."""
    from services import SafetyCalculator

    log.info("Starting safety calculation")
    start = datetime.now()

    calculator = SafetyCalculator()
    stats = calculator.calculate_all()

    elapsed = (datetime.now() - start).total_seconds()
    log.info("Safety calculation complete", elapsed_seconds=elapsed, **stats)


@cli.command()
@click.option("--max-areas", "-m", type=int, default=None, help="Max areas to process (crag sync)")
@click.option("--days", "-d", type=int, default=14, help="Days of weather history")
@click.option("--source", "-s", type=click.Choice(["mountain-project", "openbeta"]), default="openbeta", help="Data source for crags")
def run_all(max_areas, days, source):
    """Run full sync: crags -> weather -> safety calculation."""
    from services import WeatherSyncService, SafetyCalculator

    log.info("Starting full sync pipeline", source=source)
    pipeline_start = datetime.now()

    # Step 1: Sync crags
    log.info("Step 1/3: Syncing crags", source=source)
    if source == "openbeta":
        from services.openbeta_sync import OpenBetaSyncService
        with OpenBetaSyncService() as service:
            crag_stats = service.sync_all(max_areas=max_areas)
    else:
        from services import CragSyncService
        with CragSyncService() as service:
            crag_stats = service.sync_all(max_areas=max_areas)
    log.info("Crag sync done", **crag_stats)

    # Step 2: Sync weather
    log.info("Step 2/3: Fetching weather data")
    with WeatherSyncService() as service:
        weather_stats = service.sync_all_crags(days=days)
    log.info("Weather sync done", **weather_stats)

    # Step 3: Calculate safety
    log.info("Step 3/3: Calculating safety status")
    calculator = SafetyCalculator()
    safety_stats = calculator.calculate_all()
    log.info("Safety calculation done", **safety_stats)

    elapsed = (datetime.now() - pipeline_start).total_seconds()
    log.info(
        "Full pipeline complete",
        elapsed_seconds=elapsed,
        crag_stats=crag_stats,
        weather_stats=weather_stats,
        safety_stats=safety_stats,
    )


@cli.command()
@click.argument("crag_id")
def explain(crag_id):
    """Explain safety status for a specific crag."""
    from services import SafetyCalculator
    import json

    calculator = SafetyCalculator()
    explanation = calculator.explain_status(crag_id)

    click.echo(json.dumps(explanation, indent=2, default=str))


@cli.command()
def init_db():
    """Initialize database tables."""
    from db.database import init_db as _init_db

    log.info("Initializing database tables")
    _init_db()
    log.info("Database initialized")


@cli.command()
def clear_crags():
    """Clear all crags and weather data from the database."""
    from db.database import get_session
    from sqlalchemy import text

    log.info("Clearing all crags and weather data")

    session = get_session()
    try:
        # Count existing crags
        count = session.execute(text('SELECT COUNT(*) FROM ods_crags')).scalar()
        log.info("current_crag_count", count=count)

        # Clear the weather data first (foreign key constraint)
        session.execute(text('DELETE FROM ods_weather'))
        log.info("cleared_weather_data")

        # Then clear crags
        session.execute(text('DELETE FROM ods_crags'))
        session.commit()
        log.info("cleared_all_crags")

        # Verify
        count = session.execute(text('SELECT COUNT(*) FROM ods_crags')).scalar()
        log.info("crag_count_after_clear", count=count)
    except Exception as e:
        session.rollback()
        log.error("clear_failed", error=str(e))
        raise
    finally:
        session.close()


@cli.command()
def add_unknown_status():
    """Add UNKNOWN to the safety_status enum."""
    from db.database import get_session
    from sqlalchemy import text

    log.info("Adding UNKNOWN to safety_status enum")

    session = get_session()
    try:
        # Check current enum values
        result = session.execute(text("""
            SELECT COLUMN_TYPE
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = 'ods_crags' AND COLUMN_NAME = 'safety_status'
        """))
        current_type = result.scalar()
        log.info("Current column type", type=current_type)

        if current_type and 'UNKNOWN' in current_type:
            log.info("UNKNOWN already exists in enum")
            return

        # Alter the enum to add UNKNOWN
        session.execute(text("""
            ALTER TABLE ods_crags
            MODIFY COLUMN safety_status ENUM('SAFE', 'CAUTION', 'UNSAFE', 'UNKNOWN') NOT NULL
        """))
        session.commit()
        log.info("Successfully added UNKNOWN to safety_status enum")
    except Exception as e:
        session.rollback()
        log.error("Failed to add UNKNOWN to enum", error=str(e))
        raise
    finally:
        session.close()


@cli.command()
def migrate():
    """Run database migrations (Alembic upgrade head)."""
    from alembic.config import Config
    from alembic import command
    import os

    log.info("Running database migrations")

    # Get the directory where cli.py is located
    base_dir = os.path.dirname(os.path.abspath(__file__))
    alembic_cfg = Config(os.path.join(base_dir, "alembic.ini"))
    alembic_cfg.set_main_option("script_location", os.path.join(base_dir, "alembic"))

    command.upgrade(alembic_cfg, "head")
    log.info("Migrations complete")


if __name__ == "__main__":
    cli()
