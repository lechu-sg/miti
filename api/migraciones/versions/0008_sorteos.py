"""Sorteos de campaña (§3.3 y §7.8 de DEFINICION.md)

Revision ID: 0008
Revises: 0007
Create Date: 2026-09-19
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0008"
down_revision: str | None = "0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "sorteos",
        sa.Column(
            "campana_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("campanas.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("numero_sorteado", sa.Integer(), nullable=False),
        sa.Column("numero_ganador", sa.Integer(), nullable=True),
        sa.Column("premio", sa.String(100), nullable=True),
        sa.Column("estado_resultado", sa.String(30), nullable=False),
        sa.Column("ganador_nombre", sa.String(100), nullable=True),
        sa.Column("ganador_telefono", sa.String(40), nullable=True),
        sa.Column(
            "vendedor_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("vendedor_nombre", sa.String(100), nullable=True),
        sa.Column(
            "venta_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("ventas.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("codigo_corto", sa.String(10), nullable=True),
        sa.Column(
            "creado_por",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id"),
            nullable=False,
        ),
        sa.Column(
            "creado",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_table("sorteos")
