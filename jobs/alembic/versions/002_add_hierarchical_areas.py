"""Add hierarchical ods_areas table

Revision ID: 002
Revises: 001
Create Date: 2025-12-15

This migration:
1. Creates the new ods_areas table with hierarchical parent_id
2. Drops the old ods_crags table
3. Updates ods_precipitation to reference ods_areas
"""

from alembic import op
import sqlalchemy as sa


# revision identifiers
revision = '002'
down_revision = '001'
branch_labels = None
depends_on = None


def upgrade():
    # Drop old precipitation table (will recreate with new FK)
    op.execute('DROP TABLE IF EXISTS ods_precipitation')

    # Drop old crags table
    op.execute('DROP TABLE IF EXISTS ods_crags')

    # Create new ods_areas table
    op.create_table(
        'ods_areas',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('name', sa.String(255), nullable=False),
        sa.Column('url', sa.String(500), nullable=False, unique=True),
        sa.Column('parent_id', sa.String(36), sa.ForeignKey('ods_areas.id'), nullable=True),
        sa.Column('latitude', sa.Numeric(9, 6), nullable=True),
        sa.Column('longitude', sa.Numeric(9, 6), nullable=True),
        sa.Column('google_maps_url', sa.String(500), nullable=True),
        sa.Column('safety_status', sa.Enum('SAFE', 'CAUTION', 'UNSAFE', 'UNKNOWN', name='safety_status_enum'), nullable=True),
        sa.Column('scraped_at', sa.TIMESTAMP, nullable=True),
        sa.Column('scrape_failed', sa.Boolean, nullable=False, default=False),
    )

    # Create indexes
    op.create_index('idx_areas_parent_id', 'ods_areas', ['parent_id'])
    op.create_index('idx_areas_has_coords', 'ods_areas', ['latitude'], postgresql_where=sa.text('latitude IS NOT NULL'))

    # Create new precipitation table with area_id FK
    op.create_table(
        'ods_precipitation',
        sa.Column('id', sa.Integer, primary_key=True, autoincrement=True),
        sa.Column('area_id', sa.String(36), sa.ForeignKey('ods_areas.id', ondelete='CASCADE'), nullable=False),
        sa.Column('recorded_at', sa.TIMESTAMP, nullable=False),
        sa.Column('precipitation_mm', sa.Numeric(6, 2), nullable=False),
        sa.Column('temperature_max_c', sa.Numeric(4, 1), nullable=True),
        sa.Column('temperature_min_c', sa.Numeric(4, 1), nullable=True),
        sa.UniqueConstraint('area_id', 'recorded_at', name='uq_area_date')
    )

    op.create_index('idx_precip_area_date', 'ods_precipitation', ['area_id', 'recorded_at'])


def downgrade():
    # Drop new tables
    op.drop_table('ods_precipitation')
    op.drop_table('ods_areas')

    # Recreate old structure (simplified, won't restore data)
    op.create_table(
        'ods_crags',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('name', sa.String(255), nullable=False),
        sa.Column('url', sa.String(500), nullable=False, unique=True),
        sa.Column('latitude', sa.Numeric(9, 6), nullable=False),
        sa.Column('longitude', sa.Numeric(9, 6), nullable=False),
        sa.Column('location_hierarchy_json', sa.JSON, nullable=True),
        sa.Column('google_maps_url', sa.String(500), nullable=True),
        sa.Column('safety_status', sa.Enum('SAFE', 'CAUTION', 'UNSAFE', 'UNKNOWN', name='safety_status_enum'), nullable=False),
    )
