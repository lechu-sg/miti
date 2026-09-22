"""Planes y límites, compras con MercadoPago, bloqueos y panel de administración (§11)

Revision ID: 0011
Revises: 0010
Create Date: 2026-09-22
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import JSONB

revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    planes = op.create_table(
        "planes",
        sa.Column("codigo", sa.String(20), primary_key=True),
        sa.Column("nombre", sa.Text(), nullable=False),
        sa.Column("orden", sa.Integer(), nullable=False),
        sa.Column("precio", sa.BigInteger(), nullable=False, server_default="0"),
        sa.Column("limite_integrantes", sa.Integer()),
        sa.Column("limite_numeros", sa.Integer()),
        sa.Column("limite_ventas", sa.Integer()),
        sa.Column("limite_campanas_activas", sa.Integer()),
        sa.Column("publicidad", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("actualizado", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    # Valores de §11. Precios en centavos: Campaña $15.000 y Campaña Grande $25.000.
    op.bulk_insert(
        planes,
        [
            {"codigo": "gratis", "nombre": "Gratis", "orden": 0, "precio": 0,
             "limite_integrantes": 5, "limite_numeros": 100, "limite_ventas": 20,
             "limite_campanas_activas": 1, "publicidad": True},
            {"codigo": "campana", "nombre": "Campaña", "orden": 1, "precio": 1_500_000,
             "limite_integrantes": 15, "limite_numeros": 1_000, "limite_ventas": 300,
             "limite_campanas_activas": None, "publicidad": False},
            {"codigo": "grande", "nombre": "Campaña Grande", "orden": 2, "precio": 2_500_000,
             "limite_integrantes": 50, "limite_numeros": 10_000, "limite_ventas": None,
             "limite_campanas_activas": None, "publicidad": False},
        ],
    )
    op.create_foreign_key("campanas_plan", "campanas", "planes", ["plan"], ["codigo"])

    op.create_table(
        "compras_campana",
        sa.Column("id", sa.UUID(as_uuid=True), primary_key=True),
        sa.Column("campana_id", sa.UUID(as_uuid=True),
                  sa.ForeignKey("campanas.id", ondelete="CASCADE"), nullable=False),
        sa.Column("usuario_id", sa.UUID(as_uuid=True), sa.ForeignKey("usuarios.id"), nullable=False),
        sa.Column("plan_desde", sa.String(20), nullable=False),
        sa.Column("plan_hasta", sa.String(20), nullable=False),
        sa.Column("importe", sa.BigInteger(), nullable=False),
        sa.Column("estado", sa.String(20), nullable=False, server_default="pendiente"),
        sa.Column("preferencia_id", sa.String(80)),
        sa.Column("pago_id", sa.String(40), unique=True),
        sa.Column("detalle_estado", sa.Text()),
        sa.Column("creada", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("acreditada", sa.DateTime(timezone=True)),
        sa.CheckConstraint(
            "estado in ('pendiente','aprobada','rechazada','cancelada','reintegrada')",
            name="compras_estado",
        ),
    )
    op.create_index("ix_compras_campana", "compras_campana", ["campana_id", "creada"])

    op.add_column("usuarios", sa.Column("bloqueado", sa.DateTime(timezone=True)))
    op.add_column("usuarios", sa.Column("motivo_bloqueo", sa.Text()))
    op.add_column("campanas", sa.Column("suspendida", sa.DateTime(timezone=True)))
    op.add_column("campanas", sa.Column("motivo_suspension", sa.Text()))

    op.create_table(
        "administradores",
        sa.Column("usuario_id", sa.UUID(as_uuid=True), sa.ForeignKey("usuarios.id"), primary_key=True),
        sa.Column("totp_cifrado", sa.LargeBinary()),
        sa.Column("creado", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_table(
        "admin_accesos",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column("usuario_id", sa.UUID(as_uuid=True), sa.ForeignKey("usuarios.id")),
        sa.Column("accion", sa.String(40), nullable=False),
        sa.Column("detalle", JSONB(), nullable=False, server_default=sa.text("'{}'::jsonb")),
        sa.Column("ip", sa.String(64)),
        sa.Column("cuando", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_admin_accesos_cuando", "admin_accesos", ["cuando"])


def downgrade() -> None:
    op.drop_index("ix_admin_accesos_cuando", table_name="admin_accesos")
    op.drop_table("admin_accesos")
    op.drop_table("administradores")
    op.drop_column("campanas", "motivo_suspension")
    op.drop_column("campanas", "suspendida")
    op.drop_column("usuarios", "motivo_bloqueo")
    op.drop_column("usuarios", "bloqueado")
    op.drop_index("ix_compras_campana", table_name="compras_campana")
    op.drop_table("compras_campana")
    op.drop_constraint("campanas_plan", "campanas", type_="foreignkey")
    op.drop_table("planes")
