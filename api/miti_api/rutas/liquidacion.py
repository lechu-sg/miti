"""Rutas de Cierre y Liquidación de Campaña (§3.9 de DEFINICION.md).

Permite al administrador simular las dos bases de reparto (cobrada y vendida),
validar impedimentos, confirmar la liquidación con algoritmo greedy de transferencias mínimas,
y registrar las transferencias entre participantes.
"""

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..db import sesion
from ..esquemas import (
    ActualizarTransferenciaEntrada,
    ConfirmarLiquidacionEntrada,
    LiquidacionSalida,
    OpcionLiquidacion,
    ParticipanteLiquidacion,
    SimulacionLiquidacionSalida,
    TransferenciaLiquidacionSalida,
    TransferenciaSugerida,
)
from ..modelos import (
    Caja,
    Campana,
    Historial,
    Integrante,
    Liquidacion,
    Movimiento,
    Numero,
    SyncLog,
    TransferenciaLiquidacion,
    Usuario,
    Venta,
)
from ..seguridad import Contexto, contexto_activo, contexto_admin

ruteador = APIRouter(tags=["liquidación"])


def calcular_transferencias_minimas(saldos: list[dict]) -> list[dict]:
    """Algoritmo greedy que empareja al mayor deudor con el mayor acreedor (§3.9)."""
    deudores = sorted(
        [dict(d) for d in saldos if d["saldo"] > 0],
        key=lambda x: x["saldo"],
        reverse=True,
    )
    acreedores = sorted(
        [dict(a) for a in saldos if a["saldo"] < 0],
        key=lambda x: -x["saldo"],
        reverse=True,
    )

    transferencias = []
    i = 0
    j = 0
    while i < len(deudores) and j < len(acreedores):
        d = deudores[i]
        a = acreedores[j]
        monto = min(d["saldo"], -a["saldo"])
        if monto > 0:
            transferencias.append({
                "de_usuario_id": d["usuario_id"],
                "de_nombre": d["nombre"],
                "a_usuario_id": a["usuario_id"],
                "a_nombre": a["nombre"],
                "importe": monto,
            })
            d["saldo"] -= monto
            a["saldo"] += monto
        if d["saldo"] == 0:
            i += 1
        if a["saldo"] == 0:
            j += 1

    return transferencias


async def _obtener_datos_liquidacion(
    s: AsyncSession, campana: Campana
) -> tuple[dict, dict, list[str]]:
    """Calcula las opciones para base cobrada y base vendida, y detecta impedimentos."""
    impedimentos = []

    # 1. Validar movimientos pendientes
    movs_pendientes_res = await s.execute(
        select(func.count(Movimiento.id)).where(
            Movimiento.campana_id == campana.id,
            Movimiento.estado == "pendiente",
        )
    )
    cant_pendientes = movs_pendientes_res.scalar_one()
    if cant_pendientes > 0:
        impedimentos.append(
            f"Hay {cant_pendientes} movimiento(s) de cobro o entrega pendiente(s) de aprobación"
        )

    # 2. Si es rifa, validar reservas activas
    if campana.tipo == "rifa":
        res_reservas = await s.execute(
            select(func.count(Numero.numero)).where(
                Numero.campana_id == campana.id,
                Numero.estado == "reservado",
            )
        )
        cant_reservas = res_reservas.scalar_one()
        if cant_reservas > 0:
            impedimentos.append(
                f"Hay {cant_reservas} número(s) con reservas activas que deben liberarse o venderse"
            )

    # 3. Integrantes que cuentan en el reparto (activos y retirados; expulsados no)
    integrantes_db = (
        await s.execute(
            select(Integrante)
            .options(selectinload(Integrante.usuario))
            .where(
                Integrante.campana_id == campana.id,
                Integrante.estado.in_(("activo", "retirado")),
            )
            .order_by(Integrante.alta.asc(), Integrante.usuario_id.asc())
        )
    ).scalars().all()

    if not integrantes_db:
        impedimentos.append("No hay integrantes activos para el reparto")

    # 4. Cargar cajas de la campaña
    cajas_db = (
        await s.execute(select(Caja).where(Caja.campana_id == campana.id))
    ).scalars().all()
    caja_ppal = next((c for c in cajas_db if c.tipo == "principal"), None)

    # 5. Cargar movimientos confirmados
    movs_confirmados = (
        await s.execute(
            select(Movimiento).where(
                Movimiento.campana_id == campana.id,
                Movimiento.estado == "confirmado",
            )
        )
    ).scalars().all()

    # Calcular saldo por cada caja
    saldos_cajas: dict[uuid.UUID, int] = {c.id: 0 for c in cajas_db}
    for m in movs_confirmados:
        if m.caja_destino and m.caja_destino in saldos_cajas:
            saldos_cajas[m.caja_destino] += m.importe
        if m.caja_origen and m.caja_origen in saldos_cajas:
            saldos_cajas[m.caja_origen] -= m.importe

    # Gastos
    gastos_bolsillo_por_usuario: dict[uuid.UUID, int] = {i.usuario_id: 0 for i in integrantes_db}
    gastos_caja_total = 0
    for m in movs_confirmados:
        if m.tipo == "gasto":
            if m.caja_origen:
                gastos_caja_total += m.importe
            else:
                if m.creado_por in gastos_bolsillo_por_usuario:
                    gastos_bolsillo_por_usuario[m.creado_por] += m.importe

    total_gastos_bolsillo = sum(gastos_bolsillo_por_usuario.values())
    total_gastos = gastos_caja_total + total_gastos_bolsillo

    # Mapear cobros confirmados por venta
    cobrado_por_venta: dict[uuid.UUID, int] = {}
    for m in movs_confirmados:
        if m.venta_id:
            cobrado_por_venta[m.venta_id] = cobrado_por_venta.get(m.venta_id, 0) + m.importe

    # Cargar ventas para calcular deuda por vendedor (base vendida)
    ventas_db = (
        await s.execute(
            select(Venta).where(
                Venta.campana_id == campana.id,
                Venta.estado == "confirmada",
            )
        )
    ).scalars().all()

    deuda_por_vendedor: dict[uuid.UUID, int] = {i.usuario_id: 0 for i in integrantes_db}
    for v in ventas_db:
        cobrado_v = cobrado_por_venta.get(v.id, 0)
        saldo_v = v.importe - cobrado_v
        if saldo_v > 0 and v.vendedor_id in deuda_por_vendedor:
            deuda_por_vendedor[v.vendedor_id] += saldo_v

    total_deuda = sum(deuda_por_vendedor.values())

    # Dinero en mano cobrado por integrante
    en_mano_cobrado: dict[uuid.UUID, int] = {}
    for i in integrantes_db:
        cajas_usuario = [c for c in cajas_db if c.titular_id == i.usuario_id and c.tipo != "principal"]
        total_usuario = sum(saldos_cajas.get(c.id, 0) for c in cajas_usuario)
        if caja_ppal and caja_ppal.titular_id == i.usuario_id:
            total_usuario += saldos_cajas.get(caja_ppal.id, 0)
        en_mano_cobrado[i.usuario_id] = total_usuario

    N = len(integrantes_db)

    def _generar_opcion(es_vendida: bool) -> dict:
        part_list = []
        total_en_cajas = sum(en_mano_cobrado.values())
        base_total = total_en_cajas + (total_deuda if es_vendida else 0)
        neto = base_total - total_gastos_bolsillo
        cuota = (neto // N) if N > 0 else 0
        resto = (neto % N) if N > 0 else 0

        saldos_transferencias = []
        for idx, i in enumerate(integrantes_db):
            h_i = en_mano_cobrado[i.usuario_id] + (deuda_por_vendedor[i.usuario_id] if es_vendida else 0)
            r_i = gastos_bolsillo_por_usuario[i.usuario_id]
            # Asignación determinística del resto a los primeros integrantes por orden de alta
            s_i = cuota + (1 if idx < resto else 0)
            b_i = h_i - (s_i + r_i)

            part_list.append({
                "usuario_id": str(i.usuario_id),
                "nombre": i.usuario.nombre,
                "en_mano": h_i,
                "gastos_bolsillo": r_i,
                "parte": s_i,
                "saldo": b_i,
            })
            saldos_transferencias.append({
                "usuario_id": i.usuario_id,
                "nombre": i.usuario.nombre,
                "saldo": b_i,
            })

        transf = calcular_transferencias_minimas(saldos_transferencias)

        return {
            "base": "vendida" if es_vendida else "cobrada",
            "recaudado": base_total + gastos_caja_total,
            "gastos": total_gastos,
            "neto": neto,
            "parte": cuota,
            "participantes": part_list,
            "transferencias": transf,
        }

    opc_cobrada = _generar_opcion(es_vendida=False)
    opc_vendida = _generar_opcion(es_vendida=True)

    return opc_cobrada, opc_vendida, impedimentos


@ruteador.get(
    "/campanas/{campana_id}/liquidacion/simulacion",
    response_model=SimulacionLiquidacionSalida,
)
async def simular_liquidacion(
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> SimulacionLiquidacionSalida:
    """Calcula la simulación de liquidación en base cobrada y base vendida sin modificar la base."""
    cobrada, vendida, impedimentos = await _obtener_datos_liquidacion(s, ctx.campana)

    return SimulacionLiquidacionSalida(
        puede_liquidar=len(impedimentos) == 0,
        impedimentos=impedimentos,
        cobrada=OpcionLiquidacion(**cobrada),
        vendida=OpcionLiquidacion(**vendida),
    )


@ruteador.post(
    "/campanas/{campana_id}/liquidacion",
    response_model=LiquidacionSalida,
    status_code=status.HTTP_201_CREATED,
)
async def confirmar_liquidacion(
    datos: ConfirmarLiquidacionEntrada,
    ctx: Contexto = Depends(contexto_admin),
    s: AsyncSession = Depends(sesion),
) -> LiquidacionSalida:
    """Confirma la liquidación de la campaña, genera las transferencias y bloquea la campaña (§3.9)."""
    if ctx.campana.estado == "liquidada":
        raise HTTPException(
            status.HTTP_409_CONFLICT, "la campaña ya fue liquidada previamente"
        )
    if ctx.campana.estado not in ("activa", "cerrada", "sorteada"):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"no se puede liquidar una campaña con estado «{ctx.campana.estado}»",
        )

    cobrada, vendida, impedimentos = await _obtener_datos_liquidacion(s, ctx.campana)

    if impedimentos:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"No se puede liquidar la campaña: {'; '.join(impedimentos)}",
        )

    opcion = vendida if datos.base == "vendida" else cobrada

    # 1. Crear registro de Liquidación
    liq = Liquidacion(
        campana_id=ctx.campana.id,
        base=datos.base,
        neto=opcion["neto"],
        parte=opcion["parte"],
        recaudado=opcion["recaudado"],
        gastos=opcion["gastos"],
        detalle={"participantes": opcion["participantes"]},
        confirmada_por=ctx.usuario.id,
    )
    s.add(liq)
    await s.flush()

    # 2. Generar transferencias sugeridas en transferencias_liq
    transfs_salida = []
    for t in opcion["transferencias"]:
        t_id = uuid.uuid4()
        t_modelo = TransferenciaLiquidacion(
            id=t_id,
            campana_id=ctx.campana.id,
            de_usuario_id=uuid.UUID(str(t["de_usuario_id"])),
            a_usuario_id=uuid.UUID(str(t["a_usuario_id"])),
            importe=t["importe"],
            estado="pendiente",
        )
        s.add(t_modelo)
        transfs_salida.append(
            TransferenciaSugerida(
                id=t_id,
                de_usuario_id=uuid.UUID(str(t["de_usuario_id"])),
                de_nombre=t["de_nombre"],
                a_usuario_id=uuid.UUID(str(t["a_usuario_id"])),
                a_nombre=t["a_nombre"],
                importe=t["importe"],
                estado="pendiente",
            )
        )

    # 3. Cambiar estado de campaña a liquidada y fijar bloqueada
    estado_anterior = ctx.campana.estado
    ctx.campana.estado = "liquidada"
    ctx.campana.bloqueada = datetime.now()

    # 4. Registrar en historial y sync_log
    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="campana_liquidada",
            objeto="liquidaciones",
            objeto_id=ctx.campana.id,
            detalle={
                "base": datos.base,
                "neto": opcion["neto"],
                "parte": opcion["parte"],
                "de_estado": estado_anterior,
            },
        )
    )

    s.add(
        SyncLog(
            campana_id=ctx.campana.id,
            tabla="liquidaciones",
            fila_id=str(ctx.campana.id),
            op="I",
            datos={
                "base": datos.base,
                "neto": opcion["neto"],
                "parte": opcion["parte"],
                "estado": "liquidada",
            },
        )
    )

    await s.commit()

    return LiquidacionSalida(
        campana_id=ctx.campana.id,
        base=datos.base,
        neto=opcion["neto"],
        parte=opcion["parte"],
        recaudado=opcion["recaudado"],
        gastos=opcion["gastos"],
        detalle={"participantes": opcion["participantes"]},
        confirmada_por=ctx.usuario.id,
        confirmada_por_nombre=ctx.usuario.nombre,
        creada=liq.creada,
        transferencias=transfs_salida,
    )


@ruteador.get(
    "/campanas/{campana_id}/liquidacion",
    response_model=LiquidacionSalida,
)
async def obtener_liquidacion(
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> LiquidacionSalida:
    """Devuelve la liquidación confirmada y sus transferencias (§3.9)."""
    liq = (
        await s.execute(
            select(Liquidacion)
            .options(selectinload(Liquidacion.confirmador))
            .where(Liquidacion.campana_id == ctx.campana.id)
        )
    ).scalar_one_or_none()

    if liq is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, "la campaña todavía no fue liquidada"
        )

    transfs = (
        await s.execute(
            select(TransferenciaLiquidacion)
            .options(
                selectinload(TransferenciaLiquidacion.de_usuario),
                selectinload(TransferenciaLiquidacion.a_usuario),
            )
            .where(TransferenciaLiquidacion.campana_id == ctx.campana.id)
            .order_by(TransferenciaLiquidacion.importe.desc())
        )
    ).scalars().all()

    return LiquidacionSalida(
        campana_id=ctx.campana.id,
        base=liq.base,
        neto=liq.neto,
        parte=liq.parte,
        recaudado=liq.recaudado,
        gastos=liq.gastos,
        detalle=liq.detalle,
        confirmada_por=liq.confirmada_por,
        confirmada_por_nombre=liq.confirmador.nombre,
        creada=liq.creada,
        transferencias=[
            TransferenciaSugerida(
                id=t.id,
                de_usuario_id=t.de_usuario_id,
                de_nombre=t.de_usuario.nombre,
                a_usuario_id=t.a_usuario_id,
                a_nombre=t.a_usuario.nombre,
                importe=t.importe,
                estado=t.estado,
                comprobante_id=t.comprobante_id,
                actualizada=t.actualizada,
            )
            for t in transfs
        ],
    )


@ruteador.patch(
    "/campanas/{campana_id}/liquidacion/transferencias/{transferencia_id}",
    response_model=TransferenciaLiquidacionSalida,
)
async def actualizar_transferencia(
    transferencia_id: uuid.UUID,
    datos: ActualizarTransferenciaEntrada,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> TransferenciaLiquidacionSalida:
    """Permite al deudor marcar como pagada y al acreedor confirmar la transferencia."""
    t = (
        await s.execute(
            select(TransferenciaLiquidacion)
            .options(
                selectinload(TransferenciaLiquidacion.de_usuario),
                selectinload(TransferenciaLiquidacion.a_usuario),
            )
            .where(
                TransferenciaLiquidacion.id == transferencia_id,
                TransferenciaLiquidacion.campana_id == ctx.campana.id,
            )
        )
    ).scalar_one_or_none()

    if t is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "la transferencia no existe")

    es_admin = ctx.integrante.rol == "admin"
    es_deudor = t.de_usuario_id == ctx.usuario.id
    es_acreedor = t.a_usuario_id == ctx.usuario.id

    if datos.accion == "pagar":
        if not (es_deudor or es_admin):
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                "solo quien transfiere o el administrador puede marcarla como pagada",
            )
        if t.estado != "pendiente":
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                f"la transferencia ya está en estado «{t.estado}»",
            )
        t.estado = "pagada"
        if datos.comprobante_id:
            t.comprobante_id = datos.comprobante_id

    elif datos.accion == "confirmar":
        if not (es_acreedor or es_admin):
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                "solo quien recibe o el administrador puede confirmar el cobro",
            )
        t.estado = "confirmada"

    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="transferencia_liquidacion_actualizada",
            objeto="transferencias_liq",
            objeto_id=t.id,
            detalle={"accion": datos.accion, "nuevo_estado": t.estado},
        )
    )

    de_nombre = t.de_usuario.nombre
    a_nombre = t.a_usuario.nombre

    await s.commit()

    return TransferenciaLiquidacionSalida(
        id=t.id,
        de_usuario_id=t.de_usuario_id,
        de_nombre=de_nombre,
        a_usuario_id=t.a_usuario_id,
        a_nombre=a_nombre,
        importe=t.importe,
        estado=t.estado,
        comprobante_id=t.comprobante_id,
        actualizada=t.actualizada,
    )
