"""Despacho de notificaciones push Firebase Cloud Messaging (§5.7 de DEFINICION.md)."""

import asyncio
import logging
import uuid
from datetime import UTC, datetime
from pathlib import Path

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from .modelos import Dispositivo, Integrante

logger = logging.getLogger("miti.push")

_firebase_app = None

# Errores de FCM que significan "ese celular ya no existe": desinstalaron la app,
# borraron los datos o el token caducó.
_ERRORES_TOKEN_MUERTO = ("UNREGISTERED", "INVALID_ARGUMENT", "NOT_FOUND", "SENDER_ID_MISMATCH")


def _token_invalido(error: Exception | None) -> bool:
    if error is None:
        return False
    codigo = getattr(error, "code", "") or ""
    texto = f"{codigo} {error}".upper()
    return any(e in texto for e in _ERRORES_TOKEN_MUERTO)


def _obtener_firebase():
    """Inicializa la app de Firebase Admin de manera perezosa si hay credenciales disponibles."""
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app
    try:
        import firebase_admin
        from firebase_admin import credentials

        from .config import ajustes

        if firebase_admin._apps:
            _firebase_app = firebase_admin.get_app()
            return _firebase_app

        ruta = Path(ajustes().firebase_credenciales)
        if not ruta.exists():
            logger.info("Sin credenciales de Firebase en %s: las push quedan en modo registro.", ruta)
            return None

        _firebase_app = firebase_admin.initialize_app(credentials.Certificate(str(ruta)))
        return _firebase_app
    except Exception as e:
        logger.info("Firebase Admin no configurado o sin credenciales (%s). Operando en modo log.", e)
        return None


async def registrar_token_dispositivo(
    s: AsyncSession,
    usuario_id: uuid.UUID,
    fcm_token: str,
    plataforma: str = "android",
    version_app: str | None = None,
) -> Dispositivo:
    """Registra o actualiza el token FCM de un dispositivo."""
    # Si el token ya existía para otro usuario, se reasigna al usuario actual
    existente = (
        await s.execute(select(Dispositivo).where(Dispositivo.fcm_token == fcm_token))
    ).scalar_one_or_none()

    if existente:
        existente.usuario_id = usuario_id
        existente.plataforma = plataforma
        existente.version_app = version_app
        existente.actualizado = datetime.now(UTC)
        disp = existente
    else:
        disp = Dispositivo(
            usuario_id=usuario_id,
            fcm_token=fcm_token,
            plataforma=plataforma,
            version_app=version_app,
        )
        s.add(disp)

    await s.commit()
    return disp


async def enviar_notificacion_usuarios(
    s: AsyncSession,
    usuario_ids: list[uuid.UUID],
    titulo: str,
    cuerpo: str,
    datos: dict[str, str] | None = None,
) -> int:
    """Envía una notificación push a una lista de usuarios."""
    if not usuario_ids:
        return 0

    tokens = (
        await s.execute(
            select(Dispositivo.fcm_token).where(Dispositivo.usuario_id.in_(usuario_ids))
        )
    ).scalars().all()

    if not tokens:
        logger.debug("No hay dispositivos registrados para los usuarios: %s", usuario_ids)
        return 0

    app = _obtener_firebase()
    if not app:
        logger.info(
            "[PUSH SIMULADA] A %d dispositivos: '%s' - '%s' (datos=%s)",
            len(tokens),
            titulo,
            cuerpo,
            datos,
        )
        return len(tokens)

    try:
        from firebase_admin import messaging

        mensajes = [
            messaging.Message(
                notification=messaging.Notification(title=titulo, body=cuerpo),
                data={str(k): str(v) for k, v in (datos or {}).items()},
                token=t,
            )
            for t in tokens
        ]
        # El SDK de Firebase es sincrónico: va a un hilo aparte para no frenar la API.
        enviar = getattr(messaging, "send_each", None) or messaging.send_all
        respuesta = await asyncio.to_thread(enviar, mensajes)
        logger.info("Notificaciones enviadas con éxito: %d/%d", respuesta.success_count, len(tokens))

        # Los dispositivos que ya no existen se dan de baja: si no, cada envío
        # arrastra tokens muertos para siempre.
        muertos = [
            tokens[i]
            for i, r in enumerate(respuesta.responses)
            if not r.success and _token_invalido(r.exception)
        ]
        if muertos:
            await s.execute(delete(Dispositivo).where(Dispositivo.fcm_token.in_(muertos)))
            await s.commit()
            logger.info("Dispositivos dados de baja por token inválido: %d", len(muertos))

        return respuesta.success_count
    except Exception as e:
        logger.warning("Error enviando push FCM: %s", e)
        return 0


async def enviar_notificacion_campana(
    s: AsyncSession,
    campana_id: uuid.UUID,
    titulo: str,
    cuerpo: str,
    excluir_usuario_id: uuid.UUID | None = None,
    datos: dict[str, str] | None = None,
) -> int:
    """Envía una notificación a todos los integrantes activos de la campaña."""
    consulta = select(Integrante.usuario_id).where(
        Integrante.campana_id == campana_id,
        Integrante.estado == "activo",
    )
    if excluir_usuario_id:
        consulta = consulta.where(Integrante.usuario_id != excluir_usuario_id)

    usuario_ids = (await s.execute(consulta)).scalars().all()
    return await enviar_notificacion_usuarios(
        s,
        list(usuario_ids),
        titulo=titulo,
        cuerpo=cuerpo,
        datos=datos,
    )
