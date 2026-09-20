"""Avisos de campaña y dispositivos FCM (§5.7 y §7.9 de DEFINICION.md)

Revision ID: 0010
Revises: 0009
Create Date: 2026-09-19
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0010"
down_revision: str | None = "0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "avisos",
        sa.Column("id", sa.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "campana_id",
            sa.UUID(as_uuid=True),
            sa.ForeignKey("campanas.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "autor_id",
            sa.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id"),
            nullable=False,
        ),
        sa.Column("mensaje", sa.Text(), nullable=False),
        sa.Column("fijado", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("creado", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_avisos_campana_creado", "avisos", ["campana_id", "creado"])

    op.create_table(
        "dispositivos",
        sa.Column("id", sa.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "usuario_id",
            sa.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("fcm_token", sa.String(255), nullable=False, unique=True),
        sa.Column("plataforma", sa.String(20), nullable=False, server_default="android"),
        sa.Column("version_app", sa.String(20), nullable=True),
        sa.Column("actualizado", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_dispositivos_usuario_id", "dispositivos", ["usuario_id"])


def downgrade() -> None:
    op.drop_index("ix_dispositivos_usuario_id", table_name="dispositivos")
    op.drop_table("dispositivos")
    op.drop_index("ix_avisos_campana_creado", table_name="avisos")
    op.drop_table("avisos")
