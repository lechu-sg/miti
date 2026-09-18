"""Fase 2+: productos y entregas

Revision ID: 0004
Revises: 0003
Create Date: 2026-09-18
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # 1. Tabla de productos
    op.create_table(
        "productos",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "campana_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("campanas.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("nombre", sa.String(100), nullable=False),
        sa.Column("precio", sa.BigInteger(), nullable=False),
        sa.Column("foto", sa.Text(), nullable=True),
        sa.Column("activo", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("creado", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_productos_campana_activo", "productos", ["campana_id", "activo"])

    # 2. Agregar entrega en ventas
    op.add_column(
        "ventas",
        sa.Column("entrega", sa.String(20), nullable=False, server_default="pedido"),
    )
    op.create_check_constraint(
        "ventas_entrega",
        "ventas",
        "entrega in ('pedido', 'entregado')",
    )

    # 3. Modificar venta_items para soportar productos y cantidades
    op.alter_column("venta_items", "numero", existing_type=sa.Integer(), nullable=True)
    op.drop_constraint("venta_items_unica", "venta_items", type_="unique")
    op.add_column(
        "venta_items",
        sa.Column(
            "producto_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("productos.id", ondelete="SET NULL"),
            nullable=True,
        ),
    )
    op.add_column(
        "venta_items",
        sa.Column("cantidad", sa.Integer(), nullable=False, server_default="1"),
    )
    op.create_index("ix_venta_items_producto_id", "venta_items", ["producto_id"])
    op.create_check_constraint(
        "venta_items_tipo",
        "venta_items",
        "(numero IS NOT NULL AND producto_id IS NULL) OR (numero IS NULL AND producto_id IS NOT NULL)",
    )


def downgrade() -> None:
    op.drop_constraint("venta_items_tipo", "venta_items", type_="check")
    op.drop_index("ix_venta_items_producto_id", table_name="venta_items")
    op.drop_column("venta_items", "cantidad")
    op.drop_column("venta_items", "producto_id")
    op.create_unique_constraint("venta_items_unica", "venta_items", ["venta_id", "numero"])
    op.alter_column("venta_items", "numero", existing_type=sa.Integer(), nullable=False)

    op.drop_constraint("ventas_entrega", "ventas", type_="check")
    op.drop_column("ventas", "entrega")

    op.drop_index("ix_productos_campana_activo", table_name="productos")
    op.drop_table("productos")
