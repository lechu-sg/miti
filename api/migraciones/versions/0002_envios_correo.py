"""Registro de mails enviados

Revision ID: 0002
Revises: 0001
Create Date: 2026-09-17
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "envios_correo",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("destino_huella", sa.LargeBinary(), nullable=False),
        sa.Column("motivo", sa.String(40), nullable=False, server_default=""),
        sa.Column("estado", sa.String(20), nullable=False),
        sa.Column("detalle", sa.Text()),
        sa.Column("cuando", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("envios_correo_cuando", "envios_correo", ["cuando"])


def downgrade() -> None:
    op.drop_table("envios_correo")
