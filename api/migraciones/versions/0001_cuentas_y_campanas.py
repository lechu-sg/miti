"""Fase 1: cuentas, campañas, integrantes, cajas e historial

Revision ID: 0001
Revises:
Create Date: 2026-09-17
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "usuarios",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("email_cifrado", sa.LargeBinary(), nullable=False),
        sa.Column("email_huella", sa.LargeBinary(), nullable=False, unique=True),
        sa.Column("nombre", sa.Text(), nullable=False),
        sa.Column("nacimiento", sa.Date()),
        sa.Column("creado", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("ultimo_acceso", sa.DateTime(timezone=True)),
        sa.Column("baja", sa.DateTime(timezone=True)),
    )

    op.create_table(
        "codigos_acceso",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("email_huella", sa.LargeBinary(), nullable=False),
        sa.Column("codigo_hash", sa.LargeBinary(), nullable=False),
        sa.Column("creado", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("expira", sa.DateTime(timezone=True), nullable=False),
        sa.Column("usado", sa.DateTime(timezone=True)),
        sa.Column("intentos", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_index("ix_codigos_acceso_email_huella", "codigos_acceso", ["email_huella"])

    op.create_table(
        "sesiones",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "usuario_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("refresco_hash", sa.LargeBinary(), nullable=False, unique=True),
        sa.Column("creado", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("expira", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revocada", sa.DateTime(timezone=True)),
        sa.Column("reemplazada_por", postgresql.UUID(as_uuid=True)),
        sa.Column("dispositivo", sa.String(120)),
    )
    op.create_index("ix_sesiones_usuario_id", "sesiones", ["usuario_id"])

    op.create_table(
        "campanas",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("tipo", sa.String(20), nullable=False),
        sa.Column("nombre", sa.Text(), nullable=False),
        sa.Column("moneda", sa.String(3), nullable=False, server_default="ARS"),
        sa.Column("meta", sa.BigInteger()),
        sa.Column("estado", sa.String(20), nullable=False, server_default="borrador"),
        sa.Column("plan", sa.String(20), nullable=False, server_default="gratis"),
        sa.Column(
            "creador_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("usuarios.id"), nullable=False
        ),
        sa.Column("config", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("creada", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("bloqueada", sa.DateTime(timezone=True)),
        sa.CheckConstraint("tipo in ('rifa', 'productos')", name="campanas_tipo"),
        sa.CheckConstraint(
            "estado in ('borrador', 'activa', 'cerrada', 'sorteada', 'liquidada', 'archivada')",
            name="campanas_estado",
        ),
        sa.CheckConstraint("meta is null or meta > 0", name="campanas_meta"),
    )

    op.create_table(
        "integrantes",
        sa.Column(
            "campana_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("campanas.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "usuario_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id"),
            primary_key=True,
        ),
        sa.Column("rol", sa.String(20), nullable=False, server_default="integrante"),
        sa.Column("estado", sa.String(20), nullable=False, server_default="invitado"),
        sa.Column("cuenta_en_reparto", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("invitado_por", postgresql.UUID(as_uuid=True), sa.ForeignKey("usuarios.id")),
        sa.Column("invitado", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("alta", sa.DateTime(timezone=True)),
        sa.Column("baja", sa.DateTime(timezone=True)),
        sa.CheckConstraint("rol in ('admin', 'integrante')", name="integrantes_rol"),
        sa.CheckConstraint(
            "estado in ('invitado', 'activo', 'rechazado', 'retirado', 'expulsado')",
            name="integrantes_estado",
        ),
    )
    op.create_index("integrantes_usuario", "integrantes", ["usuario_id", "estado"])

    op.create_table(
        "cajas",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "campana_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("campanas.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("tipo", sa.String(20), nullable=False),
        sa.Column(
            "titular_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("usuarios.id"), nullable=False
        ),
        sa.Column("alias_cifrado", sa.LargeBinary()),
        sa.Column("creada", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("cerrada", sa.DateTime(timezone=True)),
        sa.CheckConstraint("tipo in ('principal', 'billetera', 'efectivo')", name="cajas_tipo"),
        sa.UniqueConstraint("campana_id", "tipo", "titular_id", name="cajas_unica"),
    )
    op.create_index("ix_cajas_campana_id", "cajas", ["campana_id"])

    op.create_table(
        "historial",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "campana_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("campanas.id", ondelete="CASCADE"),
        ),
        sa.Column("actor_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("usuarios.id")),
        sa.Column("accion", sa.String(60), nullable=False),
        sa.Column("objeto", sa.String(60)),
        sa.Column("objeto_id", postgresql.UUID(as_uuid=True)),
        sa.Column("detalle", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("cuando", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("historial_campana", "historial", ["campana_id", "cuando"])


def downgrade() -> None:
    op.drop_table("historial")
    op.drop_table("cajas")
    op.drop_table("integrantes")
    op.drop_table("campanas")
    op.drop_table("sesiones")
    op.drop_table("codigos_acceso")
    op.drop_table("usuarios")
