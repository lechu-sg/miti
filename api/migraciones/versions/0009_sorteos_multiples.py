"""Sorteos con múltiples premios y orden (§3.3 de DEFINICION.md)

Revision ID: 0009
Revises: 0008
Create Date: 2026-09-19
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0009"
down_revision: str | None = "0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("sorteos", sa.Column("orden", sa.Integer(), nullable=False, server_default="1"))
    op.drop_constraint("sorteos_pkey", "sorteos", type_="primary")
    op.create_primary_key("sorteos_pkey", "sorteos", ["campana_id", "orden"])


def downgrade() -> None:
    op.drop_constraint("sorteos_pkey", "sorteos", type_="primary")
    op.create_primary_key("sorteos_pkey", "sorteos", ["campana_id"])
    op.drop_column("sorteos", "orden")
