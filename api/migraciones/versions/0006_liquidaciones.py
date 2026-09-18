"""Fase 4: cierre y liquidación de campaña (liquidaciones y transferencias_liq)

Revision ID: 0006
Revises: 0005
Create Date: 2026-09-18
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0006"
down_revision: str | None = "0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "liquidaciones",
        sa.Column(
            "campana_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("campanas.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("base", sa.String(20), nullable=False),
        sa.Column("neto", sa.BigInteger(), nullable=False),
        sa.Column("parte", sa.BigInteger(), nullable=False),
        sa.Column("recaudado", sa.BigInteger(), nullable=False),
        sa.Column("gastos", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("detalle", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column(
            "confirmada_por",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id"),
            nullable=False,
        ),
        sa.Column(
            "creada",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint("base IN ('cobrada', 'vendida')", name="ck_liquidaciones_base"),
    )

    op.create_table(
        "transferencias_liq",
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
            "de_usuario_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id"),
            nullable=False,
        ),
        sa.Column(
            "a_usuario_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id"),
            nullable=False,
        ),
        sa.Column("importe", sa.BigInteger(), nullable=False),
        sa.Column("estado", sa.String(20), nullable=False, server_default="pendiente"),
        sa.Column(
            "comprobante_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("comprobantes.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "actualizada",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            onupdate=sa.func.now(),
            nullable=False,
        ),
        sa.CheckConstraint("estado IN ('pendiente', 'pagada', 'confirmada')", name="ck_transf_liq_estado"),
        sa.CheckConstraint("importe > 0", name="ck_transf_liq_importe"),
    )

    op.create_index(
        "ix_transferencias_liq_campana_estado",
        "transferencias_liq",
        ["campana_id", "estado"],
    )


def downgrade() -> None:
    op.drop_index("ix_transferencias_liq_campana_estado", table_name="transferencias_liq")
    op.drop_table("transferencias_liq")
    op.drop_table("liquidaciones")
