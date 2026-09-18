"""Campañas, invitaciones y cajas."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import cripto
from ..config import ajustes
from ..db import sesion
from ..esquemas import (
    CajaSalida,
    CambiarEstado,
    CampanaDetalle,
    CampanaSalida,
    IntegranteSalida,
    InvitacionSalida,
    Invitar,
    NuevaCampana,
    RespuestaInvitacion,
)
from ..modelos import Caja, Campana, Historial, Integrante, Usuario
from ..seguridad import Contexto, contexto_activo, contexto_admin, contexto_campana, usuario_actual
from .rifas import asegurar_numeros

ruteador = APIRouter(tags=["campañas"])

# Qué estado puede seguir a cuál. La liquidación (Fase 5) es la que cierra.
PASOS = {
    "borrador": {"activa", "archivada"},
    "activa": {"cerrada"},
    "cerrada": {"sorteada", "activa", "liquidada"},
    "sorteada": {"liquidada", "archivada"},
    "liquidada": {"archivada"},
}


def _salida(campana: Campana, integrante: Integrante) -> dict:
    return {
        "id": campana.id,
        "tipo": campana.tipo,
        "nombre": campana.nombre,
        "moneda": campana.moneda,
        "meta": campana.meta,
        "estado": campana.estado,
        "plan": campana.plan,
        "creador_id": campana.creador_id,
        "config": campana.config,
        "creada": campana.creada,
        "mi_rol": integrante.rol,
        "mi_estado": integrante.estado,
    }


async def _cajas_de(s: AsyncSession, campana_id: uuid.UUID, titular_id: uuid.UUID) -> None:
    """Toda persona que entra a una campaña trae sus dos cajas: billetera y efectivo."""
    for tipo in ("billetera", "efectivo"):
        existe = (
            await s.execute(
                select(Caja.id).where(
                    Caja.campana_id == campana_id, Caja.tipo == tipo, Caja.titular_id == titular_id
                )
            )
        ).first()
        if not existe:
            s.add(Caja(campana_id=campana_id, tipo=tipo, titular_id=titular_id))


@ruteador.post("/campanas", response_model=CampanaSalida, status_code=status.HTTP_201_CREATED)
async def crear(
    datos: NuevaCampana,
    usuario: Usuario = Depends(usuario_actual),
    s: AsyncSession = Depends(sesion),
) -> dict:
    if datos.tipo == "rifa" and datos.rifa is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "falta la configuración de la rifa")
    if datos.id is not None and await s.get(Campana, datos.id) is not None:
        # El celular reintentó: devolvemos lo que ya existe en vez de duplicar.
        campana = await s.get(Campana, datos.id)
        if campana.creador_id != usuario.id:
            raise HTTPException(status.HTTP_409_CONFLICT, "ese identificador ya está usado")
        integrante = (
            await s.execute(
                select(Integrante).where(
                    Integrante.campana_id == campana.id, Integrante.usuario_id == usuario.id
                )
            )
        ).scalar_one()
        return _salida(campana, integrante)

    campana = Campana(
        id=datos.id or uuid.uuid4(),
        tipo=datos.tipo,
        nombre=datos.nombre.strip(),
        moneda=datos.moneda.upper(),
        meta=datos.meta,
        creador_id=usuario.id,
        config=datos.rifa.model_dump(mode="json") if datos.rifa else {},
    )
    s.add(campana)
    await s.flush()

    s.add(
        Integrante(
            campana_id=campana.id,
            usuario_id=usuario.id,
            rol="admin",
            estado="activo",
            alta=datetime.now(UTC),
        )
    )
    await _cajas_de(s, campana.id, usuario.id)
    # La cuenta principal arranca a nombre de quien crea; se puede pasar a otro integrante.
    s.add(
        Caja(
            campana_id=campana.id,
            tipo="principal",
            titular_id=usuario.id,
            alias_cifrado=cripto.cifrar(datos.alias_cuenta),
        )
    )
    s.add(
        Historial(
            campana_id=campana.id,
            actor_id=usuario.id,
            accion="campana_creada",
            objeto="campana",
            objeto_id=campana.id,
            detalle={"tipo": campana.tipo, "nombre": campana.nombre},
        )
    )
    await s.commit()
    await s.refresh(campana)
    integrante = (
        await s.execute(
            select(Integrante).where(
                Integrante.campana_id == campana.id, Integrante.usuario_id == usuario.id
            )
        )
    ).scalar_one()
    return _salida(campana, integrante)


@ruteador.get("/campanas", response_model=list[CampanaSalida])
async def mis_campanas(
    usuario: Usuario = Depends(usuario_actual), s: AsyncSession = Depends(sesion)
) -> list[dict]:
    filas = (
        await s.execute(
            select(Campana, Integrante)
            .join(Integrante, Integrante.campana_id == Campana.id)
            .where(
                Integrante.usuario_id == usuario.id,
                Integrante.estado.in_(("activo", "invitado")),
            )
            .order_by(Campana.creada.desc())
        )
    ).all()
    return [_salida(c, i) for c, i in filas]


@ruteador.get("/campanas/{campana_id}", response_model=CampanaDetalle)
async def detalle(ctx: Contexto = Depends(contexto_campana), s: AsyncSession = Depends(sesion)) -> dict:
    integrantes = (
        await s.execute(
            select(Integrante, Usuario)
            .join(Usuario, Usuario.id == Integrante.usuario_id)
            .where(Integrante.campana_id == ctx.campana.id)
            .order_by(Integrante.invitado)
        )
    ).all()
    cajas = (
        await s.execute(
            select(Caja, Usuario)
            .join(Usuario, Usuario.id == Caja.titular_id)
            .where(Caja.campana_id == ctx.campana.id, Caja.cerrada.is_(None))
            .order_by(Caja.tipo)
        )
    ).all()

    datos = _salida(ctx.campana, ctx.integrante)
    datos["integrantes"] = [
        IntegranteSalida(
            usuario_id=i.usuario_id,
            nombre=u.nombre,
            rol=i.rol,
            estado=i.estado,
            cuenta_en_reparto=i.cuenta_en_reparto,
            alta=i.alta,
        )
        for i, u in integrantes
    ]
    datos["cajas"] = [
        CajaSalida(
            id=c.id,
            tipo=c.tipo,
            titular_id=c.titular_id,
            titular=u.nombre,
            # El alias de la cuenta principal lo ven todos: es donde tienen que pagar.
            alias=cripto.descifrar(c.alias_cifrado),
        )
        for c, u in cajas
    ]
    return datos


@ruteador.patch("/campanas/{campana_id}/estado", response_model=CampanaSalida)
async def cambiar_estado(
    datos: CambiarEstado,
    ctx: Contexto = Depends(contexto_admin),
    s: AsyncSession = Depends(sesion),
) -> dict:
    actual = ctx.campana.estado
    if datos.estado not in PASOS.get(actual, set()):
        raise HTTPException(
            status.HTTP_409_CONFLICT, f"no se puede pasar de «{actual}» a «{datos.estado}»"
        )
    if datos.estado == "activa" and ctx.campana.tipo == "rifa":
        if not ctx.campana.config:
            raise HTTPException(status.HTTP_409_CONFLICT, "la rifa no tiene configuración")
        await asegurar_numeros(s, ctx.campana)
    ctx.campana.estado = datos.estado
    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="campana_estado",
            objeto="campana",
            objeto_id=ctx.campana.id,
            detalle={"de": actual, "a": datos.estado},
        )
    )
    await s.commit()
    return _salida(ctx.campana, ctx.integrante)


@ruteador.post(
    "/campanas/{campana_id}/invitaciones",
    response_model=IntegranteSalida,
    status_code=status.HTTP_201_CREATED,
)
async def invitar(
    datos: Invitar,
    ctx: Contexto = Depends(contexto_admin),
    s: AsyncSession = Depends(sesion),
) -> IntegranteSalida:
    """Solo el administrador invita, y solo a quien ya tenga cuenta en Miti."""
    if ctx.campana.estado not in ("borrador", "activa"):
        raise HTTPException(status.HTTP_409_CONFLICT, "la campaña ya no admite integrantes nuevos")

    email = cripto.normalizar_email(datos.email)
    invitado = (
        await s.execute(select(Usuario).where(Usuario.email_huella == cripto.huella(email)))
    ).scalar_one_or_none()
    if invitado is None or invitado.baja is not None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            "esa persona todavía no tiene cuenta en Miti: primero tiene que registrarse",
        )

    existente = (
        await s.execute(
            select(Integrante).where(
                Integrante.campana_id == ctx.campana.id, Integrante.usuario_id == invitado.id
            )
        )
    ).scalar_one_or_none()
    if existente is not None and existente.estado in ("invitado", "activo"):
        raise HTTPException(status.HTTP_409_CONFLICT, "ya está en la campaña")
    if existente is not None and existente.estado == "expulsado":
        raise HTTPException(status.HTTP_409_CONFLICT, "esa persona fue expulsada de la campaña")

    activos = (
        await s.execute(
            select(Integrante).where(
                Integrante.campana_id == ctx.campana.id,
                Integrante.estado.in_(("activo", "invitado")),
            )
        )
    ).scalars().all()
    if ctx.campana.plan == "gratis" and len(activos) >= ajustes().limite_gratis_integrantes:
        raise HTTPException(
            status.HTTP_402_PAYMENT_REQUIRED,
            f"el plan gratis llega hasta {ajustes().limite_gratis_integrantes} integrantes",
        )

    if existente is not None:  # había rechazado o se había ido: vuelve a quedar invitado
        existente.estado = "invitado"
        existente.invitado = datetime.now(UTC)
        existente.invitado_por = ctx.usuario.id
        existente.baja = None
        integrante = existente
    else:
        integrante = Integrante(
            campana_id=ctx.campana.id,
            usuario_id=invitado.id,
            invitado_por=ctx.usuario.id,
        )
        s.add(integrante)

    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="integrante_invitado",
            objeto="integrante",
            objeto_id=invitado.id,
        )
    )
    await s.commit()
    return IntegranteSalida(
        usuario_id=invitado.id,
        nombre=invitado.nombre,
        rol=integrante.rol,
        estado=integrante.estado,
        cuenta_en_reparto=integrante.cuenta_en_reparto,
        alta=integrante.alta,
    )


@ruteador.get("/invitaciones", response_model=list[InvitacionSalida])
async def mis_invitaciones(
    usuario: Usuario = Depends(usuario_actual), s: AsyncSession = Depends(sesion)
) -> list[InvitacionSalida]:
    filas = (
        await s.execute(
            select(Integrante, Campana)
            .join(Campana, Campana.id == Integrante.campana_id)
            .where(Integrante.usuario_id == usuario.id, Integrante.estado == "invitado")
            .order_by(Integrante.invitado.desc())
        )
    ).all()
    salida = []
    for integrante, campana in filas:
        quien = (
            await s.get(Usuario, integrante.invitado_por) if integrante.invitado_por else None
        )
        salida.append(
            InvitacionSalida(
                campana_id=campana.id,
                campana=campana.nombre,
                tipo=campana.tipo,
                invitado_por=quien.nombre if quien else None,
                invitado=integrante.invitado,
                estado=integrante.estado,
            )
        )
    return salida


@ruteador.post("/campanas/{campana_id}/invitacion", response_model=CampanaSalida)
async def responder_invitacion(
    datos: RespuestaInvitacion,
    ctx: Contexto = Depends(contexto_campana),
    s: AsyncSession = Depends(sesion),
) -> dict:
    if ctx.integrante.estado != "invitado":
        raise HTTPException(status.HTTP_409_CONFLICT, "no hay una invitación pendiente")

    if datos.respuesta == "acepto":
        ctx.integrante.estado = "activo"
        ctx.integrante.alta = datetime.now(UTC)
        await _cajas_de(s, ctx.campana.id, ctx.usuario.id)
    else:
        ctx.integrante.estado = "rechazado"
        ctx.integrante.baja = datetime.now(UTC)

    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion=f"invitacion_{datos.respuesta}",
            objeto="integrante",
            objeto_id=ctx.usuario.id,
        )
    )
    await s.commit()
    return _salida(ctx.campana, ctx.integrante)


@ruteador.get("/campanas/{campana_id}/cajas", response_model=list[CajaSalida])
async def cajas(ctx: Contexto = Depends(contexto_activo), s: AsyncSession = Depends(sesion)) -> list[CajaSalida]:
    filas = (
        await s.execute(
            select(Caja, Usuario)
            .join(Usuario, Usuario.id == Caja.titular_id)
            .where(Caja.campana_id == ctx.campana.id, Caja.cerrada.is_(None))
            .order_by(Caja.tipo, Usuario.nombre)
        )
    ).all()
    return [
        CajaSalida(
            id=c.id,
            tipo=c.tipo,
            titular_id=c.titular_id,
            titular=u.nombre,
            alias=cripto.descifrar(c.alias_cifrado),
        )
        for c, u in filas
    ]
