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
