"""add UNKNOWN to safety_status enum

Revision ID: 7b8c9d0e1f2a
Revises: 0491aac1cafc
Create Date: 2025-12-08

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = '7b8c9d0e1f2a'
down_revision: Union[str, None] = '0491aac1cafc'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Alter the ENUM to add UNKNOWN
    op.execute(
        "ALTER TABLE ods_crags MODIFY COLUMN safety_status "
        "ENUM('SAFE', 'CAUTION', 'UNSAFE', 'UNKNOWN') NOT NULL"
    )


def downgrade() -> None:
    # Remove UNKNOWN from the ENUM
    # First update any UNKNOWN values to CAUTION
    op.execute("UPDATE ods_crags SET safety_status = 'CAUTION' WHERE safety_status = 'UNKNOWN'")
    op.execute(
        "ALTER TABLE ods_crags MODIFY COLUMN safety_status "
        "ENUM('SAFE', 'CAUTION', 'UNSAFE') NOT NULL"
    )
