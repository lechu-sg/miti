"""Fase 2: rifa, números, compradores, comprobantes, ventas y movimientos

Revision ID: 0003
Revises: 0002
Create Date: 2026-09-18
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # 1. Compradores
    op.create_table(
        "compradores",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "campana_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("campanas.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("nombre_cifrado", sa.LargeBinary(), nullable=False),
        sa.Column("telefono_cifrado", sa.LargeBinary(), nullable=False),
        sa.Column(
            "creado_por",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id"),
            nullable=False,
        ),
        sa.Column("creado", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_compradores_campana_id", "compradores", ["campana_id"])

    # 2. Comprobantes
    op.create_table(
        "comprobantes",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "campana_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("campanas.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("ruta_archivo", sa.Text(), nullable=False),
        sa.Column("sha256", sa.String(64)),
        sa.Column("nro_operacion", sa.String(60)),
        sa.Column("mime", sa.String(50), nullable=False),
        sa.Column("tamano", sa.BigInteger(), nullable=False),
        sa.Column(
            "creado_por",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id"),
            nullable=False,
        ),
        sa.Column("creado", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_comprobantes_campana_sha256", "comprobantes", ["campana_id", "sha256"])
    op.create_index(
        "ix_comprobantes_campana_nro_operacion", "comprobantes", ["campana_id", "nro_operacion"]
    )

    # 3. Ventas
    op.create_table(
        "ventas",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "campana_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("campanas.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "vendedor_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id"),
            nullable=False,
        ),
        sa.Column(
            "comprador_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("compradores.id"),
            nullable=False,
        ),
        sa.Column("importe", sa.BigInteger(), nullable=False),
        sa.Column("estado", sa.String(20), nullable=False, server_default="confirmada"),
        sa.Column("codigo_corto", sa.String(10), nullable=False),
        sa.Column("creada", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint("estado in ('confirmada', 'anulada')", name="ventas_estado"),
    )
    op.create_index("ix_ventas_campana_creada", "ventas", ["campana_id", "creada"])
    op.create_index("ix_ventas_vendedor", "ventas", ["campana_id", "vendedor_id"])

    # 4. Venta items
    op.create_table(
        "venta_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "venta_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("ventas.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("numero", sa.Integer(), nullable=False),
        sa.Column("precio_unitario", sa.BigInteger(), nullable=False),
        sa.UniqueConstraint("venta_id", "numero", name="venta_items_unica"),
    )

    # 5. Números de rifa
    op.create_table(
        "numeros",
        sa.Column(
            "campana_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("campanas.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("numero", sa.Integer(), nullable=False),
        sa.Column("estado", sa.String(20), nullable=False, server_default="libre"),
        sa.Column(
            "talonario_de",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id"),
        ),
        sa.Column("reserva_vence", sa.DateTime(timezone=True)),
        sa.Column(
            "reservado_por",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id"),
        ),
        sa.Column("reserva_nota", sa.Text()),
        sa.Column(
            "venta_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("ventas.id", ondelete="SET NULL"),
        ),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("actualizado", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("campana_id", "numero", name="numeros_pk"),
        sa.CheckConstraint("estado in ('libre', 'reservado', 'vendido')", name="numeros_estado"),
    )
    op.create_index("ix_numeros_campana_estado", "numeros", ["campana_id", "estado"])

    # 6. Movimientos
    op.create_table(
        "movimientos",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "campana_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("campanas.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("tipo", sa.String(20), nullable=False),
        sa.Column(
            "caja_origen",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("cajas.id"),
        ),
        sa.Column(
            "caja_destino",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("cajas.id"),
        ),
        sa.Column("importe", sa.BigInteger(), nullable=False),
        sa.Column("estado", sa.String(20), nullable=False),
        sa.Column(
            "requiere_aprobacion_de",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id"),
        ),
        sa.Column(
            "aprobado_por",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id"),
        ),
        sa.Column("motivo", sa.Text()),
        sa.Column(
            "venta_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("ventas.id"),
        ),
        sa.Column(
            "anula_a",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("movimientos.id"),
        ),
        sa.Column(
            "comprobante_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("comprobantes.id"),
        ),
        sa.Column(
            "creado_por",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("usuarios.id"),
            nullable=False,
        ),
        sa.Column("creado", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.CheckConstraint(
            "tipo in ('cobro', 'entrega', 'gasto', 'reintegro', 'liquidacion', 'anulacion')",
            name="movimientos_tipo",
        ),
        sa.CheckConstraint(
            "estado in ('pendiente', 'confirmado', 'rechazado')",
            name="movimientos_estado",
        ),
    )
    op.create_index(
        "ix_movimientos_campana_tipo_estado", "movimientos", ["campana_id", "tipo", "estado"]
    )


def downgrade() -> None:
    op.drop_table("movimientos")
    op.drop_table("numeros")
    op.drop_table("venta_items")
    op.drop_table("ventas")
    op.drop_table("comprobantes")
    op.drop_table("compradores")
