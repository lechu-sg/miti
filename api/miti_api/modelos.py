"""Tablas de Miti (Fase 1: cuentas, campañas, integrantes y cajas).

Reglas de la casa:
- Los identificadores son UUID y los genera el celular, para poder crear sin señal.
- La plata se guarda SIEMPRE en centavos enteros (bigint), nunca en decimales.
- Las fechas van en UTC.
- Los estados son texto con CHECK: se leen en la base y se amplían sin migrar tipos.
"""

import uuid
from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

TIPOS_CAMPANA = ("rifa", "productos")
ESTADOS_CAMPANA = ("borrador", "activa", "cerrada", "sorteada", "liquidada", "archivada")
ROLES = ("admin", "integrante")
ESTADOS_INTEGRANTE = ("invitado", "activo", "rechazado", "retirado", "expulsado")
TIPOS_CAJA = ("principal", "billetera", "efectivo")
ESTADOS_NUMERO = ("libre", "reservado", "vendido")
ESTADOS_VENTA = ("confirmada", "anulada")
ESTADOS_ENTREGA = ("pedido", "entregado")
TIPOS_MOVIMIENTO = ("cobro", "entrega", "gasto", "reintegro", "liquidacion", "anulacion")
ESTADOS_MOVIMIENTO = ("pendiente", "confirmado", "rechazado")


def _uuid() -> uuid.UUID:
    return uuid.uuid4()


def _en_lista(columna: str, valores: tuple[str, ...]) -> str:
    opciones = ", ".join(f"'{v}'" for v in valores)
    return f"{columna} in ({opciones})"


class Base(DeclarativeBase):
    pass


class Usuario(Base):
    __tablename__ = "usuarios"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    # El email se guarda cifrado; la huella permite buscarlo sin poder leerlo.
    email_cifrado: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    email_huella: Mapped[bytes] = mapped_column(LargeBinary, nullable=False, unique=True)
    nombre: Mapped[str] = mapped_column(Text, nullable=False)
    nacimiento: Mapped[datetime | None] = mapped_column(Date, nullable=True)
    creado: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    ultimo_acceso: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    baja: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class CodigoAcceso(Base):
    """Código de un solo uso que se manda por email para entrar."""

    __tablename__ = "codigos_acceso"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    email_huella: Mapped[bytes] = mapped_column(LargeBinary, nullable=False, index=True)
    codigo_hash: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    creado: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    expira: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    usado: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    intentos: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class Sesion(Base):
    """Token de refresco: rotativo y de un solo uso."""

    __tablename__ = "sesiones"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    usuario_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("usuarios.id", ondelete="CASCADE"), nullable=False, index=True
    )
    refresco_hash: Mapped[bytes] = mapped_column(LargeBinary, nullable=False, unique=True)
    creado: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    expira: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revocada: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    reemplazada_por: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    dispositivo: Mapped[str | None] = mapped_column(String(120))


class Campana(Base):
    __tablename__ = "campanas"
    __table_args__ = (
        CheckConstraint(_en_lista("tipo", TIPOS_CAMPANA), name="campanas_tipo"),
        CheckConstraint(_en_lista("estado", ESTADOS_CAMPANA), name="campanas_estado"),
        CheckConstraint("meta is null or meta > 0", name="campanas_meta"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    tipo: Mapped[str] = mapped_column(String(20), nullable=False)
    nombre: Mapped[str] = mapped_column(Text, nullable=False)
    moneda: Mapped[str] = mapped_column(String(3), nullable=False, default="ARS")
    meta: Mapped[int | None] = mapped_column(BigInteger)
    estado: Mapped[str] = mapped_column(String(20), nullable=False, default="borrador")
    plan: Mapped[str] = mapped_column(String(20), nullable=False, default="gratis")
    creador_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("usuarios.id"), nullable=False)
    config: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    creada: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    bloqueada: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    integrantes: Mapped[list["Integrante"]] = relationship(back_populates="campana", lazy="selectin")
    cajas: Mapped[list["Caja"]] = relationship(back_populates="campana", lazy="selectin")
    productos: Mapped[list["Producto"]] = relationship(back_populates="campana", lazy="selectin")


class Integrante(Base):
    __tablename__ = "integrantes"
    __table_args__ = (
        CheckConstraint(_en_lista("rol", ROLES), name="integrantes_rol"),
        CheckConstraint(_en_lista("estado", ESTADOS_INTEGRANTE), name="integrantes_estado"),
        Index("integrantes_usuario", "usuario_id", "estado"),
    )

    campana_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("campanas.id", ondelete="CASCADE"), primary_key=True
    )
    usuario_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("usuarios.id"), primary_key=True)
    rol: Mapped[str] = mapped_column(String(20), nullable=False, default="integrante")
    estado: Mapped[str] = mapped_column(String(20), nullable=False, default="invitado")
    # Quien se va cobra igual; el expulsado no. Por eso el reparto es un dato propio.
    cuenta_en_reparto: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    invitado_por: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("usuarios.id"))
    invitado: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    alta: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    baja: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    campana: Mapped[Campana] = relationship(back_populates="integrantes")
    usuario: Mapped[Usuario] = relationship(foreign_keys=[usuario_id], lazy="selectin")


class Caja(Base):
    """Dónde hay plata de la campaña: la cuenta principal, o la billetera y el efectivo de cada uno."""

    __tablename__ = "cajas"
    __table_args__ = (
        CheckConstraint(_en_lista("tipo", TIPOS_CAJA), name="cajas_tipo"),
        UniqueConstraint("campana_id", "tipo", "titular_id", name="cajas_unica"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    campana_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("campanas.id", ondelete="CASCADE"), nullable=False, index=True
    )
    tipo: Mapped[str] = mapped_column(String(20), nullable=False)
    titular_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("usuarios.id"), nullable=False)
    # Alias o CBU de la cuenta principal: dato sensible, va cifrado.
    alias_cifrado: Mapped[bytes | None] = mapped_column(LargeBinary)
    creada: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    cerrada: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    campana: Mapped[Campana] = relationship(back_populates="cajas")
    titular: Mapped["Usuario"] = relationship(foreign_keys=[titular_id], lazy="selectin")


class Historial(Base):
    """Todo lo que pasa queda acá. Solo se inserta."""

    __tablename__ = "historial"
    __table_args__ = (Index("historial_campana", "campana_id", "cuando"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    campana_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("campanas.id", ondelete="CASCADE")
    )
    actor_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("usuarios.id"))
    accion: Mapped[str] = mapped_column(String(60), nullable=False)
    objeto: Mapped[str | None] = mapped_column(String(60))
    objeto_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True))
    detalle: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    cuando: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class EnvioCorreo(Base):
    """Cada mail que sale. Sirve de auditoría y para no pasarnos del límite del hosting."""

    __tablename__ = "envios_correo"
    __table_args__ = (Index("envios_correo_cuando", "cuando"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    # Del destinatario se guarda la huella, no la dirección.
    destino_huella: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    motivo: Mapped[str] = mapped_column(String(40), nullable=False, default="")
    estado: Mapped[str] = mapped_column(String(20), nullable=False)
    detalle: Mapped[str | None] = mapped_column(Text)
    cuando: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Comprador(Base):
    __tablename__ = "compradores"
    __table_args__ = (Index("ix_compradores_campana_id", "campana_id"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    campana_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("campanas.id", ondelete="CASCADE"), nullable=False
    )
    nombre_cifrado: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    telefono_cifrado: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    creado_por: Mapped[uuid.UUID] = mapped_column(ForeignKey("usuarios.id"), nullable=False)
    creado: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Comprobante(Base):
    __tablename__ = "comprobantes"
    __table_args__ = (
        Index("ix_comprobantes_campana_sha256", "campana_id", "sha256"),
        Index("ix_comprobantes_campana_nro_operacion", "campana_id", "nro_operacion"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    campana_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("campanas.id", ondelete="CASCADE"), nullable=False
    )
    ruta_archivo: Mapped[str] = mapped_column(Text, nullable=False)
    sha256: Mapped[str | None] = mapped_column(String(64))
    nro_operacion: Mapped[str | None] = mapped_column(String(60))
    mime: Mapped[str] = mapped_column(String(50), nullable=False)
    tamano: Mapped[int] = mapped_column(BigInteger, nullable=False)
    creado_por: Mapped[uuid.UUID] = mapped_column(ForeignKey("usuarios.id"), nullable=False)
    creado: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Producto(Base):
    __tablename__ = "productos"
    __table_args__ = (Index("ix_productos_campana_activo", "campana_id", "activo"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    campana_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("campanas.id", ondelete="CASCADE"), nullable=False
    )
    nombre: Mapped[str] = mapped_column(String(100), nullable=False)
    precio: Mapped[int] = mapped_column(BigInteger, nullable=False)
    foto: Mapped[str | None] = mapped_column(Text)
    activo: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    creado: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    campana: Mapped["Campana"] = relationship(back_populates="productos")


class Venta(Base):
    __tablename__ = "ventas"
    __table_args__ = (
        CheckConstraint(_en_lista("estado", ESTADOS_VENTA), name="ventas_estado"),
        CheckConstraint(_en_lista("entrega", ESTADOS_ENTREGA), name="ventas_entrega"),
        Index("ix_ventas_campana_creada", "campana_id", "creada"),
        Index("ix_ventas_vendedor", "campana_id", "vendedor_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    campana_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("campanas.id", ondelete="CASCADE"), nullable=False
    )
    vendedor_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("usuarios.id"), nullable=False)
    comprador_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("compradores.id"), nullable=False)
    importe: Mapped[int] = mapped_column(BigInteger, nullable=False)
    estado: Mapped[str] = mapped_column(String(20), nullable=False, default="confirmada")
    entrega: Mapped[str] = mapped_column(String(20), nullable=False, default="pedido")
    codigo_corto: Mapped[str] = mapped_column(String(10), nullable=False)
    creada: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    items: Mapped[list["VentaItem"]] = relationship(back_populates="venta", lazy="selectin")
    comprador: Mapped[Comprador] = relationship(lazy="selectin")
    vendedor: Mapped[Usuario] = relationship(foreign_keys=[vendedor_id], lazy="selectin")


class VentaItem(Base):
    __tablename__ = "venta_items"
    __table_args__ = (
        Index("ix_venta_items_producto_id", "producto_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    venta_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("ventas.id", ondelete="CASCADE"), nullable=False
    )
    numero: Mapped[int | None] = mapped_column(Integer, nullable=True)
    producto_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("productos.id", ondelete="SET NULL"), nullable=True
    )
    cantidad: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    precio_unitario: Mapped[int] = mapped_column(BigInteger, nullable=False)

    venta: Mapped[Venta] = relationship(back_populates="items")
    producto: Mapped[Producto | None] = relationship(lazy="selectin")


class Numero(Base):
    __tablename__ = "numeros"
    __table_args__ = (
        CheckConstraint(_en_lista("estado", ESTADOS_NUMERO), name="numeros_estado"),
        Index("ix_numeros_campana_estado", "campana_id", "estado"),
    )

    campana_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("campanas.id", ondelete="CASCADE"), primary_key=True
    )
    numero: Mapped[int] = mapped_column(Integer, primary_key=True)
    estado: Mapped[str] = mapped_column(String(20), nullable=False, default="libre")
    talonario_de: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("usuarios.id"))
    reserva_vence: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    reservado_por: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("usuarios.id"))
    reserva_nota: Mapped[str | None] = mapped_column(Text)
    venta_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("ventas.id", ondelete="SET NULL"))
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    actualizado: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Movimiento(Base):
    __tablename__ = "movimientos"
    __table_args__ = (
        CheckConstraint(_en_lista("tipo", TIPOS_MOVIMIENTO), name="movimientos_tipo"),
        CheckConstraint(_en_lista("estado", ESTADOS_MOVIMIENTO), name="movimientos_estado"),
        Index("ix_movimientos_campana_tipo_estado", "campana_id", "tipo", "estado"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=_uuid)
    campana_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("campanas.id", ondelete="CASCADE"), nullable=False
    )
    tipo: Mapped[str] = mapped_column(String(20), nullable=False)
    caja_origen: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("cajas.id"))
    caja_destino: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("cajas.id"))
    importe: Mapped[int] = mapped_column(BigInteger, nullable=False)
    estado: Mapped[str] = mapped_column(String(20), nullable=False)
    requiere_aprobacion_de: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("usuarios.id"))
    aprobado_por: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("usuarios.id"))
    motivo: Mapped[str | None] = mapped_column(Text)
    venta_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("ventas.id"))
    anula_a: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("movimientos.id"))
    comprobante_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("comprobantes.id"))
    creado_por: Mapped[uuid.UUID] = mapped_column(ForeignKey("usuarios.id"), nullable=False)
    creado: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class SyncLog(Base):
    __tablename__ = "sync_log"
    __table_args__ = (
        Index("ix_sync_log_campana_secuencia", "campana_id", "secuencia"),
    )

    secuencia: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    campana_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("campanas.id", ondelete="CASCADE"), nullable=False
    )
    tabla: Mapped[str] = mapped_column(String(50), nullable=False)
    fila_id: Mapped[str] = mapped_column(String(64), nullable=False)
    op: Mapped[str] = mapped_column(String(10), nullable=False)
    datos: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict)
    creado: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

