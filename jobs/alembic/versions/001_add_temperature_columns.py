"""Add temperature columns to precipitation table

Revision ID: 001
Revises:
Create Date: 2025-12-08

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = '001'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Check if columns exist before adding (MySQL doesn't have IF NOT EXISTS for ADD COLUMN)
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    columns = [col['name'] for col in inspector.get_columns('ods_precipitation')]

    if 'temperature_max_c' not in columns:
        op.add_column('ods_precipitation', sa.Column('temperature_max_c', sa.DECIMAL(4, 1), nullable=True))

    if 'temperature_min_c' not in columns:
        op.add_column('ods_precipitation', sa.Column('temperature_min_c', sa.DECIMAL(4, 1), nullable=True))


def downgrade() -> None:
    op.drop_column('ods_precipitation', 'temperature_min_c')
    op.drop_column('ods_precipitation', 'temperature_max_c')
