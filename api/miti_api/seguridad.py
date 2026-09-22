"""Tokens, sesiones y los permisos de cada pantalla."""

import base64
import secrets
import uuid
from datetime import UTC, datetime, timedelta

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from . import cripto
from .config import ajustes
from .db import sesion
from .modelos import Campana, Integrante, Sesion, Usuario

_esquema = HTTPBearer(auto_error=False)


def _clave_jwt() -> bytes:
    return base64.b64decode(ajustes().claves["CLAVE_JWT"])


def crear_token(usuario_id: uuid.UUID) -> tuple[str, int]:
    minutos = ajustes().minutos_token
    ahora = datetime.now(UTC)
    cuerpo = {
        "sub": str(usuario_id),
        "iat": int(ahora.timestamp()),
        "exp": int((ahora + timedelta(minutes=minutos)).timestamp()),
    }
    return jwt.encode(cuerpo, _clave_jwt(), algorithm="HS256"), minutos * 60


async def crear_refresco(
    s: AsyncSession, usuario_id: uuid.UUID, dispositivo: str | None = None
) -> str:
    valor = secrets.token_urlsafe(48)
    s.add(
        Sesion(
            usuario_id=usuario_id,
            refresco_hash=cripto.hash_simple(valor),
            expira=datetime.now(UTC) + timedelta(days=ajustes().dias_refresco),
            dispositivo=dispositivo,
        )
    )
    return valor


async def usuario_actual(
    credencial: HTTPAuthorizationCredentials | None = Depends(_esquema),
    s: AsyncSession = Depends(sesion),
) -> Usuario:
    if credencial is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "falta el token")
    try:
        cuerpo = jwt.decode(credencial.credentials, _clave_jwt(), algorithms=["HS256"])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "el token venció") from None
    except jwt.PyJWTError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "token inválido") from None

    usuario = await s.get(Usuario, uuid.UUID(cuerpo["sub"]))
    if usuario is None or usuario.baja is not None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "la cuenta no está activa")
    if usuario.bloqueado is not None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "tu cuenta está bloqueada: escribinos a miti@sole.ar")
    return usuario


class Contexto:
    """La campaña pedida, y qué es el usuario dentro de ella."""

    def __init__(self, campana: Campana, integrante: Integrante, usuario: Usuario):
        self.campana = campana
        self.integrante = integrante
        self.usuario = usuario

    @property
    def es_admin(self) -> bool:
        return self.integrante.rol == "admin"


async def contexto_campana(
    campana_id: uuid.UUID,
    pedido: Request,
    usuario: Usuario = Depends(usuario_actual),
    s: AsyncSession = Depends(sesion),
) -> Contexto:
    campana = await s.get(Campana, campana_id)
    if campana is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "la campaña no existe")
    integrante = (
        await s.execute(
            select(Integrante).where(
                Integrante.campana_id == campana_id, Integrante.usuario_id == usuario.id
            )
        )
    ).scalar_one_or_none()
    # Un invitado que todavía no aceptó ve la campaña, pero nada de adentro.
    if integrante is None or integrante.estado not in ("activo", "invitado"):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "la campaña no existe")
    # Suspendida desde el panel: se puede mirar y exportar, pero no cambiar nada.
    if campana.suspendida is not None and pedido.method not in ("GET", "HEAD"):
        raise HTTPException(
            status.HTTP_423_LOCKED,
            "la campaña está suspendida"
            + (f": {campana.motivo_suspension}" if campana.motivo_suspension else ""),
        )
    return Contexto(campana, integrante, usuario)


async def contexto_activo(ctx: Contexto = Depends(contexto_campana)) -> Contexto:
    if ctx.integrante.estado != "activo":
        raise HTTPException(status.HTTP_403_FORBIDDEN, "todavía no aceptaste la invitación")
    return ctx


async def contexto_admin(ctx: Contexto = Depends(contexto_activo)) -> Contexto:
    if not ctx.es_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "solo el administrador puede hacer esto")
    return ctx
