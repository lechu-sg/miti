"""Registro de dispositivos y tokens FCM (§5.7 de DEFINICION.md)."""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..db import sesion
from ..esquemas import DispositivoSalida, RegistroDispositivoEntrada
from ..modelos import Usuario
from ..push import registrar_token_dispositivo
from ..seguridad import usuario_actual

ruteador = APIRouter(tags=["dispositivos y notificaciones"])


@ruteador.post("/dispositivos/token", response_model=DispositivoSalida)
async def registrar_dispositivo(
    datos: RegistroDispositivoEntrada,
    usuario: Usuario = Depends(usuario_actual),
    s: AsyncSession = Depends(sesion),
) -> DispositivoSalida:
    """Registra o renueva el token FCM del dispositivo para recibir notificaciones push."""
    disp = await registrar_token_dispositivo(
        s,
        usuario_id=usuario.id,
        fcm_token=datos.fcm_token,
        plataforma=datos.plataforma,
        version_app=datos.version_app,
    )
    return DispositivoSalida(
        id=disp.id,
        usuario_id=disp.usuario_id,
        fcm_token=disp.fcm_token,
        plataforma=disp.plataforma,
        version_app=disp.version_app,
        actualizado=disp.actualizado,
    )
