"""Rutas para gestión y consulta de sorteos de rifa (§3.3 y §7.8 de DEFINICION.md)."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from .. import cripto
from ..db import sesion
from ..esquemas import PremioSorteoEntrada, RegistrarSorteoEntrada, SorteoSalida
from ..modelos import Campana, Comprador, Historial, Numero, Sorteo, Usuario, Venta
from ..seguridad import Contexto, contexto_activo, contexto_admin

ruteador = APIRouter(tags=["sorteos"])


@ruteador.post(
    "/campanas/{campana_id}/sorteo",
    response_model=list[SorteoSalida],
    status_code=status.HTTP_201_CREATED,
)
async def registrar_sorteo(
    datos: RegistrarSorteoEntrada,
    ctx: Contexto = Depends(contexto_admin),
    s: AsyncSession = Depends(sesion),
) -> list[SorteoSalida]:
    """Registra el sorteo oficial de una rifa con uno o múltiples premios y determina los ganadores (§3.3 de DEFINICION.md)."""
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

    items: list[PremioSorteoEntrada] = []
    if datos.items:
        items = sorted(datos.items, key=lambda x: x.orden)
    elif datos.numero_sorteado is not None:
        p_def = datos.premio or (config.get("premios", ["Primer Premio"])[0] if config.get("premios") else "Primer Premio")
        items = [PremioSorteoEntrada(orden=1, numero_sorteado=datos.numero_sorteado, premio=p_def)]
    else:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "debe ingresar al menos un número sorteado",
        )

    for it in items:
        if it.numero_sorteado < desde or it.numero_sorteado > hasta:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                f"el número sorteado ({it.numero_sorteado}) para «{it.premio}» está fuera del rango ({desde} al {hasta})",
            )

    regla_no_vendido = datos.regla_no_vendido or config.get("si_no_se_vendio", config.get("regla_no_vendido", "desierto"))

    async def _cargar_datos_ganador(venta_obj_id: uuid.UUID):
        v = (
            await s.execute(
                select(Venta)
                .options(selectinload(Venta.comprador), selectinload(Venta.vendedor))
                .where(Venta.id == venta_obj_id)
            )
        ).scalar_one_or_none()
        if not v:
            return None, None, None, None, None, None
        gn = cripto.descifrar(v.comprador.nombre_cifrado) if v.comprador else None
        gt = cripto.descifrar(v.comprador.telefono_cifrado) if v.comprador else None
        vn = v.vendedor.nombre if v.vendedor else None
        return gn, gt, v.vendedor_id, vn, v.id, v.codigo_corto

    # Eliminar sorteos previos registrados para esta campaña
    await s.execute(delete(Sorteo).where(Sorteo.campana_id == ctx.campana.id))

    numeros_ya_ganadores: set[int] = set()
    resultados: list[Sorteo] = []
    ahora = datetime.now(UTC)

    for it in items:
        estado_resultado = "vacante_desierto"
        numero_ganador: int | None = None
        ganador_nombre: str | None = None
        ganador_telefono: str | None = None
        vendedor_id: uuid.UUID | None = None
        vendedor_nombre: str | None = None
        venta_id: uuid.UUID | None = None
        codigo_corto: str | None = None

        num_sorteado = await s.get(Numero, (ctx.campana.id, it.numero_sorteado))

        # Verificar si el número sorteado fue vendido y no ganó un premio previo
        if (
            num_sorteado
            and num_sorteado.estado == "vendido"
            and num_sorteado.venta_id
            and num_sorteado.numero not in numeros_ya_ganadores
        ):
            estado_resultado = "ganador_encontrado"
            numero_ganador = num_sorteado.numero
            (
                ganador_nombre,
                ganador_telefono,
                vendedor_id,
                vendedor_nombre,
                venta_id,
                codigo_corto,
            ) = await _cargar_datos_ganador(num_sorteado.venta_id)
        else:
            # Número no vendido o ya premiado: aplicar regla de desempate / no vendido (§3.3)
            if regla_no_vendido in ("siguiente", "siguiente_vendido"):
                filtros_base = [
                    Numero.campana_id == ctx.campana.id,
                    Numero.estado == "vendido",
                ]
                if numeros_ya_ganadores:
                    filtros_base.append(Numero.numero.notin_(numeros_ya_ganadores))

                # Buscar siguiente vendido mayor
                siguiente = (
                    await s.execute(
                        select(Numero)
                        .where(*filtros_base, Numero.numero > it.numero_sorteado)
                        .order_by(Numero.numero.asc())
                    )
                ).scalars().first()

                if siguiente and siguiente.venta_id:
                    estado_resultado = "siguiente_vendido"
                    numero_ganador = siguiente.numero
                    (
                        ganador_nombre,
                        ganador_telefono,
                        vendedor_id,
                        vendedor_nombre,
                        venta_id,
                        codigo_corto,
                    ) = await _cargar_datos_ganador(siguiente.venta_id)
                else:
                    # Circular (wrap-around): buscar primer vendido disponible desde el inicio
                    primero = (
                        await s.execute(
                            select(Numero)
                            .where(*filtros_base)
                            .order_by(Numero.numero.asc())
                        )
                    ).scalars().first()
                    if primero and primero.venta_id:
                        estado_resultado = "siguiente_vendido"
                        numero_ganador = primero.numero
                        (
                            ganador_nombre,
                            ganador_telefono,
                            vendedor_id,
                            vendedor_nombre,
                            venta_id,
                            codigo_corto,
                        ) = await _cargar_datos_ganador(primero.venta_id)
                    else:
                        estado_resultado = "vacante_desierto"
                        numero_ganador = None
            elif regla_no_vendido == "sortear_de_nuevo":
                estado_resultado = "vacante_resortear"
                numero_ganador = None
            else:
                estado_resultado = "vacante_desierto"
                numero_ganador = None

        if numero_ganador is not None:
            numeros_ya_ganadores.add(numero_ganador)

        sorteo = Sorteo(
            campana_id=ctx.campana.id,
            orden=it.orden,
            numero_sorteado=it.numero_sorteado,
            numero_ganador=numero_ganador,
            premio=it.premio,
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
        resultados.append(sorteo)

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
                "cantidad_premios": len(resultados),
                "resultados": [
                    {
                        "orden": r.orden,
                        "premio": r.premio,
                        "numero_sorteado": r.numero_sorteado,
                        "numero_ganador": r.numero_ganador,
                        "estado_resultado": r.estado_resultado,
                    }
                    for r in resultados
                ],
            },
        )
    )
    await s.commit()

    return [SorteoSalida.model_validate(r) for r in resultados]


@ruteador.get("/campanas/{campana_id}/sorteo", response_model=list[SorteoSalida])
async def obtener_sorteo(
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> list[SorteoSalida]:
    """Devuelve los resultados oficiales de los sorteos registrados para la campaña."""
    sorteos = (
        await s.execute(
            select(Sorteo)
            .where(Sorteo.campana_id == ctx.campana.id)
            .order_by(Sorteo.orden.asc())
        )
    ).scalars().all()
    if not sorteos:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "esta campaña todavía no tiene un sorteo registrado")

    return [SorteoSalida.model_validate(s_) for s_ in sorteos]

