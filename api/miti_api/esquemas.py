"""Lo que entra y sale de la API."""

import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, Field, field_validator



class PedirCodigo(BaseModel):
    email: EmailStr


class Verificar(BaseModel):
    email: EmailStr
    codigo: str = Field(min_length=6, max_length=6)
    # Solo para quien entra por primera vez.
    nombre: str | None = Field(default=None, min_length=2, max_length=80)
    nacimiento: date | None = None
    dispositivo: str | None = Field(default=None, max_length=120)


class Refrescar(BaseModel):
    refresco: str


class Tokens(BaseModel):
    token: str
    vence_en: int
    refresco: str


class Perfil(BaseModel):
    id: uuid.UUID
    email: EmailStr
    nombre: str
    nacimiento: date | None
    creado: datetime


class CambiarPerfil(BaseModel):
    nombre: str = Field(min_length=2, max_length=80)


class ConfigRifa(BaseModel):
    desde: int = Field(ge=0)
    hasta: int = Field(ge=0)
    precio: int = Field(gt=0, description="centavos")
    asignacion: Literal["bolsa", "talonarios"] = "bolsa"
    sorteo: Literal["externo", "interno"] = "externo"
    fecha_sorteo: date | None = None
    si_no_se_vendio: Literal["resortear", "desierto", "siguiente"] = "resortear"

    @field_validator("hasta")
    @classmethod
    def _rango(cls, v: int, info):
        desde = info.data.get("desde")
        if desde is not None and v <= desde:
            raise ValueError("el número final tiene que ser mayor que el inicial")
        if desde is not None and (v - desde + 1) > 100_000:
            raise ValueError("el rango no puede superar los 100.000 números")
        return v


class NuevaCampana(BaseModel):
    id: uuid.UUID | None = None  # la genera el celular para poder crear sin señal
    tipo: Literal["rifa", "productos"]
    nombre: str = Field(min_length=3, max_length=80)
    moneda: str = Field(default="ARS", min_length=3, max_length=3)
    meta: int | None = Field(default=None, gt=0, description="centavos")
    rifa: ConfigRifa | None = None
    alias_cuenta: str | None = Field(default=None, max_length=120)


class CajaSalida(BaseModel):
    id: uuid.UUID
    tipo: str
    titular_id: uuid.UUID
    titular: str
    alias: str | None = None


class IntegranteSalida(BaseModel):
    usuario_id: uuid.UUID
    nombre: str
    rol: str
    estado: str
    cuenta_en_reparto: bool
    alta: datetime | None


class CampanaSalida(BaseModel):
    id: uuid.UUID
    tipo: str
    nombre: str
    moneda: str
    meta: int | None
    estado: str
    plan: str
    creador_id: uuid.UUID
    config: dict
    creada: datetime
    mi_rol: str
    mi_estado: str


class CampanaDetalle(CampanaSalida):
    integrantes: list[IntegranteSalida]
    cajas: list[CajaSalida]


class Invitar(BaseModel):
    email: EmailStr


class CambiarEstado(BaseModel):
    estado: Literal["borrador", "activa", "cerrada", "sorteada", "liquidada", "archivada"]


class RespuestaInvitacion(BaseModel):
    respuesta: Literal["acepto", "rechazo"]


class InvitacionSalida(BaseModel):
    campana_id: uuid.UUID
    campana: str
    tipo: str
    invitado_por: str | None
    invitado: datetime
    estado: str
