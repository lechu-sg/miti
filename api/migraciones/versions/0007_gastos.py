"""Gastos de campaña (§3.7 de DEFINICION.md)

Revision ID: 0007
Revises: 0006
Create Date: 2026-09-18
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "gastos",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
        ),
        sa.Column(
            "campana_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("campanas.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "movimiento_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("movimientos.id", ondelete="CASCADE"),
            nullable=False,
            unique=True,
        ),
        sa.Column("descripcion", sa.Text(), nullable=False),
        sa.Column("origen", sa.String(20), nullable=False),
        sa.Column(
            "caja_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("cajas.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "creado",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint("origen in ('caja', 'bolsillo')", name="gastos_origen"),
    )
    op.create_index("ix_gastos_campana_creado", "gastos", ["campana_id", "creado"])


def downgrade() -> None:
    op.drop_index("ix_gastos_campana_creado", table_name="gastos")
    op.drop_table("gastos")
