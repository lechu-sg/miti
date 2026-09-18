"""Fase 3: registro de sincronización (sync_log)

Revision ID: 0005
Revises: 0004
Create Date: 2026-09-18
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0005"
down_revision: str | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "sync_log",
        sa.Column(
            "secuencia",
            sa.BigInteger(),
            sa.Identity(always=False, start=1),
            primary_key=True,
        ),
        sa.Column(
            "campana_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("campanas.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("tabla", sa.String(50), nullable=False),
        sa.Column("fila_id", sa.String(64), nullable=False),
        sa.Column("op", sa.String(10), nullable=False),
        sa.Column("datos", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column(
            "creado",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_sync_log_campana_secuencia",
        "sync_log",
        ["campana_id", "secuencia"],
    )


def downgrade() -> None:
    op.drop_index("ix_sync_log_campana_secuencia", table_name="sync_log")
    op.drop_table("sync_log")
