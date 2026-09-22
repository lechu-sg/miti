"""Campañas, invitaciones y cajas."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import cripto, planes
from ..db import sesion
from ..esquemas import (
    AvisoSalida,
    CajaSalida,
    CambiarEstado,
    CampanaDetalle,
    CampanaSalida,
    EditarPremiosEntrada,
    IntegranteSalida,
    InvitacionSalida,
    Invitar,
    NuevaCampana,
    NuevoAvisoEntrada,
    RespuestaInvitacion,
)
from ..modelos import Aviso, Caja, Campana, Historial, Integrante, Usuario
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
        "suspendida": campana.suspendida is not None,
        "motivo_suspension": campana.motivo_suspension,
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
    if datos.estado == "activa":
        await planes.verificar_al_activar(s, ctx.campana)
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

    await planes.verificar_integrantes(s, ctx.campana)

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


@ruteador.put("/campanas/{campana_id}/premios", response_model=list[str])
async def editar_premios(
    datos: EditarPremiosEntrada,
    ctx: Contexto = Depends(contexto_admin),
    s: AsyncSession = Depends(sesion),
) -> list[str]:
    """Modifica la lista ordenada y cantidad de premios de una rifa (§3.3)."""
    if ctx.campana.tipo != "rifa":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "la campaña no es una rifa")
    if ctx.campana.estado in ("sorteada", "liquidada", "archivada"):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"no se pueden modificar los premios en estado {ctx.campana.estado}",
        )

    nueva_config = dict(ctx.campana.config) if ctx.campana.config else {}
    nueva_config["premios"] = datos.premios
    ctx.campana.config = nueva_config

    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="editar_premios",
            objeto="campana",
            objeto_id=ctx.campana.id,
            detalle={"cantidad": len(datos.premios), "premios": datos.premios},
        )
    )
    await s.commit()
    return datos.premios


@ruteador.get("/campanas/{campana_id}/avisos", response_model=list[AvisoSalida])
async def listar_avisos(
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> list[AvisoSalida]:
    """Lista todos los avisos del muro de la campaña (§7.9)."""
    filas = (
        await s.execute(
            select(Aviso, Usuario.nombre)
            .join(Usuario, Usuario.id == Aviso.autor_id)
            .where(Aviso.campana_id == ctx.campana.id)
            .order_by(Aviso.fijado.desc(), Aviso.creado.desc())
        )
    ).all()
    return [
        AvisoSalida(
            id=a.id,
            campana_id=a.campana_id,
            autor_id=a.autor_id,
            autor_nombre=nombre,
            mensaje=a.mensaje,
            fijado=a.fijado,
            creado=a.creado,
        )
        for a, nombre in filas
    ]


@ruteador.post(
    "/campanas/{campana_id}/avisos",
    response_model=AvisoSalida,
    status_code=status.HTTP_201_CREATED,
)
async def crear_aviso(
    datos: NuevoAvisoEntrada,
    ctx: Contexto = Depends(contexto_admin),
    s: AsyncSession = Depends(sesion),
) -> AvisoSalida:
    """Publica un nuevo aviso oficial para la campaña (solo admin)."""
    aviso = Aviso(
        campana_id=ctx.campana.id,
        autor_id=ctx.usuario.id,
        mensaje=datos.mensaje.strip(),
        fijado=datos.fijado,
    )
    s.add(aviso)
    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="aviso_creado",
            objeto="aviso",
            objeto_id=aviso.id,
            detalle={"mensaje": aviso.mensaje[:100], "fijado": aviso.fijado},
        )
    )
    await s.commit()

    try:
        from ..push import enviar_notificacion_campana
        await enviar_notificacion_campana(
            s,
            campana_id=ctx.campana.id,
            titulo=f"📢 Aviso en {ctx.campana.nombre}",
            cuerpo=aviso.mensaje,
            excluir_usuario_id=ctx.usuario.id,
            datos={"tipo": "aviso", "campana_id": str(ctx.campana.id), "aviso_id": str(aviso.id)},
        )
    except Exception:
        pass

    return AvisoSalida(
        id=aviso.id,
        campana_id=aviso.campana_id,
        autor_id=aviso.autor_id,
        autor_nombre=ctx.usuario.nombre,
        mensaje=aviso.mensaje,
        fijado=aviso.fijado,
        creado=aviso.creado,
    )


@ruteador.delete(
    "/campanas/{campana_id}/avisos/{aviso_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def eliminar_aviso(
    aviso_id: uuid.UUID,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> None:
    """Elimina un aviso del muro (solo admin de la campaña o el autor del aviso)."""
    aviso = await s.get(Aviso, aviso_id)
    if not aviso or aviso.campana_id != ctx.campana.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "aviso no encontrado")

    es_admin = ctx.integrante.rol == "admin"
    es_autor = aviso.autor_id == ctx.usuario.id
    if not (es_admin or es_autor):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "solo el admin o el autor pueden eliminar el aviso")

    await s.delete(aviso)
    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="aviso_eliminado",
            objeto="aviso",
            objeto_id=aviso_id,
        )
    )
    await s.commit()

