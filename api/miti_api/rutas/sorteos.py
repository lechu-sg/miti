"""Rutas para gestión y consulta de sorteos de rifa (§3.3 y §7.8 de DEFINICION.md)."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from .. import cripto
from ..db import sesion
from ..esquemas import RegistrarSorteoEntrada, SorteoSalida
from ..modelos import Campana, Comprador, Historial, Numero, Sorteo, Usuario, Venta
from ..seguridad import Contexto, contexto_activo, contexto_admin

ruteador = APIRouter(tags=["sorteos"])


@ruteador.post(
    "/campanas/{campana_id}/sorteo",
    response_model=SorteoSalida,
    status_code=status.HTTP_201_CREATED,
)
async def registrar_sorteo(
    datos: RegistrarSorteoEntrada,
    ctx: Contexto = Depends(contexto_admin),
    s: AsyncSession = Depends(sesion),
) -> SorteoSalida:
    """Registra el sorteo oficial de una rifa y determina el ganador (§3.3 de DEFINICION.md)."""
    if ctx.campana.tipo != "rifa":
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "solo las campañas de tipo rifa tienen sorteos",
        )

    if ctx.campana.estado in ("liquidada", "archivada"):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"no se puede registrar un sorteo en una campaña con estado «{ctx.campana.estado}»",
        )

    config = ctx.campana.config or {}
    desde = config.get("desde", 0)
    hasta = config.get("hasta", 99)

    if datos.numero_sorteado < desde or datos.numero_sorteado > hasta:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"el número sorteado ({datos.numero_sorteado}) está fuera del rango ({desde} al {hasta})",
        )

    # Buscar el número sorteado
    num_sorteado = await s.get(Numero, (ctx.campana.id, datos.numero_sorteado))
    estado_resultado = "vacante_desierto"
    numero_ganador: int | None = None
    ganador_nombre: str | None = None
    ganador_telefono: str | None = None
    vendedor_id: uuid.UUID | None = None
    vendedor_nombre: str | None = None
    venta_id: uuid.UUID | None = None
    codigo_corto: str | None = None

    regla_no_vendido = config.get("si_no_se_vendio", config.get("regla_no_vendido", "desierto"))

    async def _cargar_datos_ganador(venta_obj_id: uuid.UUID):
        nonlocal ganador_nombre, ganador_telefono, vendedor_id, vendedor_nombre, venta_id, codigo_corto
        v = (
            await s.execute(
                select(Venta)
                .options(selectinload(Venta.comprador), selectinload(Venta.vendedor))
                .where(Venta.id == venta_obj_id)
            )
        ).scalar_one_or_none()
        if v:
            venta_id = v.id
            codigo_corto = v.codigo_corto
            vendedor_id = v.vendedor_id
            vendedor_nombre = v.vendedor.nombre
            if v.comprador:
                ganador_nombre = cripto.descifrar_texto(v.comprador.nombre_cifrado)
                ganador_telefono = cripto.descifrar_texto(v.comprador.telefono_cifrado)

    if num_sorteado and num_sorteado.estado == "vendido" and num_sorteado.venta_id:
        estado_resultado = "ganador_encontrado"
        numero_ganador = num_sorteado.numero
        await _cargar_datos_ganador(num_sorteado.venta_id)
    else:
        # Número no vendido: aplicar regla (§3.3)
        if regla_no_vendido in ("siguiente", "siguiente_vendido"):
            # Buscar el siguiente número vendido mayor o igual
            siguientes = (
                await s.execute(
                    select(Numero)
                    .where(
                        Numero.campana_id == ctx.campana.id,
                        Numero.estado == "vendido",
                        Numero.numero > datos.numero_sorteado,
                    )
                    .order_by(Numero.numero.asc())
                )
            ).scalars().first()

            if siguientes and siguientes.venta_id:
                estado_resultado = "siguiente_vendido"
                numero_ganador = siguientes.numero
                await _cargar_datos_ganador(siguientes.venta_id)
            else:
                # Si no hay mayores, buscar el primero vendido desde el inicio
                primero = (
                    await s.execute(
                        select(Numero)
                        .where(
                            Numero.campana_id == ctx.campana.id,
                            Numero.estado == "vendido",
                        )
                        .order_by(Numero.numero.asc())
                    )
                ).scalars().first()
                if primero and primero.venta_id:
                    estado_resultado = "siguiente_vendido"
                    numero_ganador = primero.numero
                    await _cargar_datos_ganador(primero.venta_id)
                else:
                    estado_resultado = "vacante_desierto"
                    numero_ganador = None
        elif regla_no_vendido == "sortear_de_nuevo":
            estado_resultado = "vacante_resortear"
            numero_ganador = None
        else:
            estado_resultado = "vacante_desierto"
            numero_ganador = None

    premio = datos.premio or (config.get("premios", ["Primer Premio"])[0] if config.get("premios") else "Primer Premio")
    ahora = datetime.now(UTC)

    sorteo = await s.get(Sorteo, ctx.campana.id)
    if sorteo:
        sorteo.numero_sorteado = datos.numero_sorteado
        sorteo.numero_ganador = numero_ganador
        sorteo.premio = premio
        sorteo.estado_resultado = estado_resultado
        sorteo.ganador_nombre = ganador_nombre
        sorteo.ganador_telefono = ganador_telefono
        sorteo.vendedor_id = vendedor_id
        sorteo.vendedor_nombre = vendedor_nombre
        sorteo.venta_id = venta_id
        sorteo.codigo_corto = codigo_corto
        sorteo.creado_por = ctx.usuario.id
        sorteo.creado = ahora
    else:
        sorteo = Sorteo(
            campana_id=ctx.campana.id,
            numero_sorteado=datos.numero_sorteado,
            numero_ganador=numero_ganador,
            premio=premio,
            estado_resultado=estado_resultado,
            ganador_nombre=ganador_nombre,
            ganador_telefono=ganador_telefono,
            vendedor_id=vendedor_id,
            vendedor_nombre=vendedor_nombre,
            venta_id=venta_id,
            codigo_corto=codigo_corto,
            creado_por=ctx.usuario.id,
            creado=ahora,
        )
        s.add(sorteo)

    if ctx.campana.estado in ("activa", "cerrada"):
        ctx.campana.estado = "sorteada"

    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="sorteo_registrado",
            objeto="sorteo",
            objeto_id=None,
            detalle={
                "numero_sorteado": datos.numero_sorteado,
                "numero_ganador": numero_ganador,
                "estado_resultado": estado_resultado,
                "premio": premio,
            },
        )
    )
    await s.commit()

    return SorteoSalida(
        campana_id=sorteo.campana_id,
        numero_sorteado=sorteo.numero_sorteado,
        numero_ganador=sorteo.numero_ganador,
        premio=sorteo.premio,
        estado_resultado=sorteo.estado_resultado,
        ganador_nombre=sorteo.ganador_nombre,
        ganador_telefono=sorteo.ganador_telefono,
        vendedor_id=sorteo.vendedor_id,
        vendedor_nombre=sorteo.vendedor_nombre,
        venta_id=sorteo.venta_id,
        codigo_corto=sorteo.codigo_corto,
        creado_por=sorteo.creado_por,
        creado=sorteo.creado,
    )


@ruteador.get("/campanas/{campana_id}/sorteo", response_model=SorteoSalida)
async def obtener_sorteo(
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> SorteoSalida:
    """Devuelve el resultado oficial del sorteo registrado."""
    sorteo = await s.get(Sorteo, ctx.campana.id)
    if sorteo is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "esta campaña todavía no tiene un sorteo registrado")

    return SorteoSalida(
        campana_id=sorteo.campana_id,
        numero_sorteado=sorteo.numero_sorteado,
        numero_ganador=sorteo.numero_ganador,
        premio=sorteo.premio,
        estado_resultado=sorteo.estado_resultado,
        ganador_nombre=sorteo.ganador_nombre,
        ganador_telefono=sorteo.ganador_telefono,
        vendedor_id=sorteo.vendedor_id,
        vendedor_nombre=sorteo.vendedor_nombre,
        venta_id=sorteo.venta_id,
        codigo_corto=sorteo.codigo_corto,
        creado_por=sorteo.creado_por,
        creado=sorteo.creado,
    )
