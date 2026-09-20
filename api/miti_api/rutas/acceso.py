"""Entrar a Miti: código de un solo uso por email, token y refresco rotativo."""

import logging
import secrets
from datetime import UTC, date, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import delete, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from .. import correo, cripto
from ..config import ajustes
from ..db import sesion
from ..esquemas import CambiarPerfil, PedirCodigo, Perfil, Refrescar, Tokens, Verificar
from ..modelos import CodigoAcceso, Dispositivo, Historial, Sesion, Usuario
from ..seguridad import crear_refresco, crear_token, usuario_actual

registro = logging.getLogger("miti.acceso")
ruteador = APIRouter(tags=["acceso"])


def _edad(nacimiento: date) -> int:
    hoy = date.today()
    return hoy.year - nacimiento.year - ((hoy.month, hoy.day) < (nacimiento.month, nacimiento.day))


@ruteador.post("/acceso/codigo", status_code=status.HTTP_204_NO_CONTENT)
async def pedir_codigo(datos: PedirCodigo, s: AsyncSession = Depends(sesion)) -> Response:
    """Manda un código de 6 dígitos. Contesta lo mismo exista o no la cuenta."""
    email = cripto.normalizar_email(datos.email)
    huella = cripto.huella(email)
    codigo = f"{secrets.randbelow(1_000_000):06d}"

    # Tope de pedidos por dirección: evita usar Miti para molestar a alguien.
    pedidos = (
        await s.execute(
            select(func.count())
            .select_from(CodigoAcceso)
            .where(
                CodigoAcceso.email_huella == huella,
                CodigoAcceso.creado >= datetime.now(UTC) - timedelta(hours=1),
            )
        )
    ).scalar_one()
    if pedidos >= ajustes().codigos_por_hora:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS, "pediste muchos códigos: probá de nuevo en un rato"
        )

    # Un código nuevo invalida los anteriores de ese email.
    await s.execute(
        update(CodigoAcceso)
        .where(CodigoAcceso.email_huella == huella, CodigoAcceso.usado.is_(None))
        .values(usado=datetime.now(UTC))
    )
    s.add(
        CodigoAcceso(
            email_huella=huella,
            codigo_hash=cripto.hash_simple(codigo),
            expira=datetime.now(UTC) + timedelta(minutes=ajustes().minutos_codigo),
        )
    )
    await s.flush()

    asunto, texto, html = correo.armar_codigo(codigo, ajustes().minutos_codigo)
    try:
        salio = await correo.enviar(s, email, asunto, texto, html, motivo="codigo_acceso")
    except correo.CorreoLleno as e:
        await s.commit()
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, f"{e}: probá en un rato") from None
    await s.commit()

    if not ajustes().es_produccion:
        # En prueba el código también queda en el registro, para poder probar sin casilla.
        registro.warning("CÓDIGO DE ACCESO para %s: %s", email, codigo)
    if not salio and ajustes().es_produccion:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "no pudimos mandar el mail")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@ruteador.post("/acceso/verificar", response_model=Tokens)
async def verificar(datos: Verificar, s: AsyncSession = Depends(sesion)) -> Tokens:
    email = cripto.normalizar_email(datos.email)
    huella = cripto.huella(email)

    fila = (
        await s.execute(
            select(CodigoAcceso)
            .where(CodigoAcceso.email_huella == huella, CodigoAcceso.usado.is_(None))
            .order_by(CodigoAcceso.creado.desc())
            .limit(1)
            .with_for_update()
        )
    ).scalar_one_or_none()

    invalido = HTTPException(status.HTTP_400_BAD_REQUEST, "el código no es válido o venció")
    if fila is None or fila.expira < datetime.now(UTC):
        raise invalido
    if fila.intentos >= ajustes().intentos_codigo:
        fila.usado = datetime.now(UTC)
        await s.commit()
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "demasiados intentos, pedí otro código")
    if not secrets.compare_digest(fila.codigo_hash, cripto.hash_simple(datos.codigo)):
        fila.intentos += 1
        await s.commit()
        raise invalido

    usuario = (
        await s.execute(select(Usuario).where(Usuario.email_huella == huella))
    ).scalar_one_or_none()

    if usuario is None:
        if not datos.nombre or not datos.nacimiento:
            # Cuenta nueva: la app va a volver con los datos y con ESTE MISMO código,
            # así que no se puede quemar acá.
            await s.rollback()
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                "para crear la cuenta hacen falta el nombre y la fecha de nacimiento",
            )
        if _edad(datos.nacimiento) < ajustes().edad_minima:
            fila.usado = datetime.now(UTC)
            await s.commit()
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                f"hay que tener {ajustes().edad_minima} años o más para usar Miti",
            )
        usuario = Usuario(
            email_cifrado=cripto.cifrar(email),
            email_huella=huella,
            nombre=datos.nombre.strip(),
            nacimiento=datos.nacimiento,
        )
        s.add(usuario)
        await s.flush()
        s.add(Historial(actor_id=usuario.id, accion="cuenta_creada", objeto="usuario", objeto_id=usuario.id))
    elif usuario.baja is not None:
        fila.usado = datetime.now(UTC)
        await s.commit()
        raise HTTPException(status.HTTP_403_FORBIDDEN, "la cuenta está dada de baja")

    fila.usado = datetime.now(UTC)
    usuario.ultimo_acceso = datetime.now(UTC)
    token, vence = crear_token(usuario.id)
    refresco = await crear_refresco(s, usuario.id, datos.dispositivo)
    await s.commit()
    return Tokens(token=token, vence_en=vence, refresco=refresco)


@ruteador.post("/acceso/refrescar", response_model=Tokens)
async def refrescar(datos: Refrescar, s: AsyncSession = Depends(sesion)) -> Tokens:
    hash_actual = cripto.hash_simple(datos.refresco)
    fila = (
        await s.execute(select(Sesion).where(Sesion.refresco_hash == hash_actual).with_for_update())
    ).scalar_one_or_none()
    if fila is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "el refresco no es válido")

    ahora = datetime.now(UTC)
    if fila.revocada is not None or fila.reemplazada_por is not None:
        # Alguien reusó un refresco ya rotado: se cae toda la cadena de ese usuario.
        await s.execute(
            update(Sesion)
            .where(Sesion.usuario_id == fila.usuario_id, Sesion.revocada.is_(None))
            .values(revocada=ahora)
        )
        s.add(Historial(actor_id=fila.usuario_id, accion="refresco_reusado", objeto="sesion", objeto_id=fila.id))
        await s.commit()
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "sesión cerrada por seguridad")
    if fila.expira < ahora:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "la sesión venció")

    usuario = await s.get(Usuario, fila.usuario_id)
    if usuario is None or usuario.baja is not None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "la cuenta no está activa")

    nuevo = await crear_refresco(s, fila.usuario_id, fila.dispositivo)
    await s.flush()
    fila.revocada = ahora
    fila.reemplazada_por = (
        await s.execute(select(Sesion.id).where(Sesion.refresco_hash == cripto.hash_simple(nuevo)))
    ).scalar_one()
    token, vence = crear_token(fila.usuario_id)
    await s.commit()
    return Tokens(token=token, vence_en=vence, refresco=nuevo)


@ruteador.post("/acceso/salir", status_code=status.HTTP_204_NO_CONTENT)
async def salir(
    datos: Refrescar,
    usuario: Usuario = Depends(usuario_actual),
    s: AsyncSession = Depends(sesion),
) -> Response:
    await s.execute(
        update(Sesion)
        .where(
            Sesion.refresco_hash == cripto.hash_simple(datos.refresco),
            Sesion.usuario_id == usuario.id,
        )
        .values(revocada=datetime.now(UTC))
    )
    await s.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@ruteador.post("/acceso/salir-de-todos", status_code=status.HTTP_204_NO_CONTENT)
async def salir_de_todos(
    usuario: Usuario = Depends(usuario_actual), s: AsyncSession = Depends(sesion)
) -> Response:
    await s.execute(
        update(Sesion)
        .where(Sesion.usuario_id == usuario.id, Sesion.revocada.is_(None))
        .values(revocada=datetime.now(UTC))
    )
    await s.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@ruteador.get("/yo", response_model=Perfil)
async def yo(usuario: Usuario = Depends(usuario_actual)) -> Perfil:
    return Perfil(
        id=usuario.id,
        email=cripto.descifrar(usuario.email_cifrado),
        nombre=usuario.nombre,
        nacimiento=usuario.nacimiento,
        creado=usuario.creado,
    )


@ruteador.patch("/yo", response_model=Perfil)
async def cambiar_perfil(
    datos: CambiarPerfil,
    usuario: Usuario = Depends(usuario_actual),
    s: AsyncSession = Depends(sesion),
) -> Perfil:
    usuario.nombre = datos.nombre.strip()
    await s.merge(usuario)
    await s.commit()
    return await yo(usuario)


@ruteador.delete("/yo", status_code=status.HTTP_204_NO_CONTENT)
async def eliminar_cuenta(
    usuario: Usuario = Depends(usuario_actual),
    s: AsyncSession = Depends(sesion),
) -> Response:
    """Baja de cuenta y derecho al olvido (Ley 25.326).
    
    Anonimiza datos personales, revoca todas las sesiones y da de baja al usuario.
    """
    ahora = datetime.now(UTC)
    usuario.baja = ahora
    usuario.nombre = "Usuario eliminado"

    # Generar un hash y payload aleatorio para disociar el email real
    id_random = secrets.token_hex(16)
    email_tombstone = f"eliminado_{id_random}@miti.invalid"
    usuario.email_cifrado = cripto.cifrar(email_tombstone)
    usuario.email_huella = cripto.huella(email_tombstone)

    # Revocar todas las sesiones
    await s.execute(
        update(Sesion)
        .where(Sesion.usuario_id == usuario.id, Sesion.revocada.is_(None))
        .values(revocada=ahora)
    )

    # Eliminar dispositivos FCM
    await s.execute(
        delete(Dispositivo).where(Dispositivo.usuario_id == usuario.id)
    )

    await s.merge(usuario)
    await s.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)

