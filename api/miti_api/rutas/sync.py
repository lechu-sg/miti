"""Rutas de sincronización para modo sin señal (§5 de DEFINICION.md).

Protocolo bidireccional push/pull con claves de idempotencia UUID,
detección de conflictos en ventas simultáneas y registro de secuencia en sync_log.
"""

import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from .. import cripto
from ..config import ajustes
from ..db import sesion
from ..esquemas import (
    CompradorSalida,
    ItemVentaProductoSalida,
    NuevaVenta,
    NuevaVentaProductos,
    SyncOperacionResultado,
    SyncPullSalida,
    SyncPushEntrada,
    SyncPushSalida,
    VentaSalida,
)
from ..modelos import (
    Caja,
    Campana,
    Comprador,
    Historial,
    Integrante,
    Movimiento,
    Numero,
    Producto,
    SyncLog,
    Venta,
    VentaItem,
)
from .acceso import Contexto, contexto_activo
from .rifas import _generar_codigo_corto

ruteador = APIRouter(tags=["sync"])


async def registrar_cambio_sync(
    s: AsyncSession,
    campana_id: uuid.UUID,
    tabla: str,
    fila_id: str,
    op: str,
    datos: dict,
) -> SyncLog:
    """Inserta un asiento de cambio en sync_log para replicación incremental."""
    log = SyncLog(
        campana_id=campana_id,
        tabla=tabla,
        fila_id=str(fila_id),
        op=op,
        datos=datos,
    )
    s.add(log)
    await s.flush()
    return log


@ruteador.post("/campanas/{campana_id}/sync/push", response_model=SyncPushSalida)
async def sync_push(
    datos: SyncPushEntrada,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> SyncPushSalida:
    """Procesa un lote de operaciones generadas offline por el cliente."""
    if ctx.campana.estado not in ("activa", "cerrada"):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"no se pueden sincronizar operaciones en una campaña con estado «{ctx.campana.estado}»",
        )

    resultados: list[SyncOperacionResultado] = []

    # Cargar caja principal de la campaña para resolver destinos de fondos
    caja_ppal = (
        await s.execute(
            select(Caja).where(Caja.campana_id == ctx.campana.id, Caja.tipo == "principal")
        )
    ).scalar_one()
    es_dueno_cuenta = caja_ppal.titular_id == ctx.usuario.id

    for op_item in datos.operaciones:
        op_id = op_item.id
        op_tipo = op_item.op
        payload = op_item.payload

        # 1. Control de Idempotencia: ¿Ya se procesó esta venta/operación?
        venta_existente = (
            await s.execute(
                select(Venta)
                .options(selectinload(Venta.items), selectinload(Venta.comprador))
                .where(Venta.id == op_id, Venta.campana_id == ctx.campana.id)
            )
        ).scalar_one_or_none()

        if venta_existente is not None:
            # Operación ya aplicada previamente; responder OK sin duplicar
            resultados.append(
                SyncOperacionResultado(
                    id=op_id,
                    estado="ok",
                    motivo="ya_aplicada",
                    resultado={
                        "venta_id": str(venta_existente.id),
                        "codigo_corto": venta_existente.codigo_corto,
                        "importe": venta_existente.importe,
                    },
                )
            )
            continue

        try:
            if op_tipo == "vender_rifa":
                # Validar payload de venta de rifa
                nv = NuevaVenta.model_validate({**payload, "id": op_id})
                precio_unitario = (ctx.campana.config or {}).get("precio", 0)
                importe_total = precio_unitario * len(nv.numeros)

                # Bloqueo optimista / pesimista de números
                nums_res = await s.execute(
                    select(Numero)
                    .where(
                        Numero.campana_id == ctx.campana.id,
                        Numero.numero.in_(nv.numeros),
                    )
                    .with_for_update()
                )
                nums_bloqueados = nums_res.scalars().all()

                if len(nums_bloqueados) != len(nv.numeros):
                    resultados.append(
                        SyncOperacionResultado(
                            id=op_id,
                            estado="rechazado",
                            motivo="uno o más números no pertenecen a la campaña",
                        )
                    )
                    continue

                # Detección de conflicto: ¿alguno de los números ya no está libre?
                ocupados = [
                    n.numero
                    for n in nums_bloqueados
                    if n.estado != "libre" and n.reservado_por != ctx.usuario.id
                ]
                if ocupados:
                    resultados.append(
                        SyncOperacionResultado(
                            id=op_id,
                            estado="conflicto",
                            motivo="numeros_ocupados",
                            detalle={"numeros": ocupados},
                        )
                    )
                    continue

                # Crear comprador cifrado
                comprador = Comprador(
                    campana_id=ctx.campana.id,
                    nombre_cifrado=cripto.cifrar(nv.comprador.nombre.strip()),
                    telefono_cifrado=cripto.cifrar(nv.comprador.telefono.strip()),
                    creado_por=ctx.usuario.id,
                )
                s.add(comprador)
                await s.flush()

                codigo_corto = _generar_codigo_corto()
                venta = Venta(
                    id=op_id,
                    campana_id=ctx.campana.id,
                    vendedor_id=ctx.usuario.id,
                    comprador_id=comprador.id,
                    importe=importe_total,
                    estado="confirmada",
                    codigo_corto=codigo_corto,
                )
                s.add(venta)
                await s.flush()

                # Asignar números
                for n in nums_bloqueados:
                    s.add(
                        VentaItem(
                            venta_id=venta.id,
                            numero=n.numero,
                            precio_unitario=precio_unitario,
                        )
                    )
                    n.estado = "vendido"
                    n.venta_id = venta.id
                    n.reservado_por = None
                    n.reserva_vence = None
                    n.reserva_nota = None

                # Movimiento de fondos
                if nv.destino_cobro != "adeudado":
                    if nv.destino_cobro == "efectivo":
                        caja = (
                            await s.execute(
                                select(Caja).where(
                                    Caja.campana_id == ctx.campana.id,
                                    Caja.tipo == "efectivo",
                                    Caja.titular_id == ctx.usuario.id,
                                )
                            )
                        ).scalar_one()
                        est_mov = "confirmado"
                        req_aprob = None
                        apr_por = ctx.usuario.id
                    elif nv.destino_cobro in ("billetera", "cuenta_principal"):
                        if es_dueno_cuenta or nv.destino_cobro == "cuenta_principal":
                            caja = caja_ppal
                            if es_dueno_cuenta:
                                est_mov = "confirmado"
                                req_aprob = None
                                apr_por = ctx.usuario.id
                            else:
                                est_mov = "pendiente"
                                req_aprob = caja_ppal.titular_id
                                apr_por = None
                        else:
                            caja = (
                                await s.execute(
                                    select(Caja).where(
                                        Caja.campana_id == ctx.campana.id,
                                        Caja.tipo == "billetera",
                                        Caja.titular_id == ctx.usuario.id,
                                    )
                                )
                            ).scalar_one()
                            est_mov = "confirmado"
                            req_aprob = None
                            apr_por = ctx.usuario.id

                    mov = Movimiento(
                        campana_id=ctx.campana.id,
                        tipo="cobro",
                        caja_destino=caja.id,
                        importe=importe_total,
                        estado=est_mov,
                        requiere_aprobacion_de=req_aprob,
                        aprobado_por=apr_por,
                        venta_id=venta.id,
                        creado_por=ctx.usuario.id,
                    )
                    s.add(mov)

                # Registrar en sync_log
                sync_entry = await registrar_cambio_sync(
                    s,
                    ctx.campana.id,
                    tabla="ventas",
                    fila_id=str(venta.id),
                    op="I",
                    datos={
                        "id": str(venta.id),
                        "numeros": nv.numeros,
                        "importe": importe_total,
                        "codigo_corto": codigo_corto,
                        "comprador_nombre": nv.comprador.nombre.strip(),
                        "vendedor_id": str(ctx.usuario.id),
                        "vendedor_nombre": ctx.usuario.nombre,
                        "destino_cobro": nv.destino_cobro,
                    },
                )

                resultados.append(
                    SyncOperacionResultado(
                        id=op_id,
                        estado="ok",
                        secuencia=sync_entry.secuencia,
                        resultado={
                            "venta_id": str(venta.id),
                            "codigo_corto": codigo_corto,
                            "importe": importe_total,
                        },
                    )
                )

            elif op_tipo == "vender_productos":
                # Validar payload de venta de productos
                nvp = NuevaVentaProductos.model_validate({**payload, "id": op_id})
                prod_ids = [it.producto_id for it in nvp.items]
                resultado_prods = await s.execute(
                    select(Producto).where(
                        Producto.id.in_(prod_ids), Producto.campana_id == ctx.campana.id
                    )
                )
                prods_db = {p.id: p for p in resultado_prods.scalars().all()}

                if len(prods_db) != len(set(prod_ids)):
                    resultados.append(
                        SyncOperacionResultado(
                            id=op_id,
                            estado="rechazado",
                            motivo="uno o más productos no existen en la campaña",
                        )
                    )
                    continue

                # Validar si alguno está inactivo (conflicto)
                inactivos = [p.nombre for p in prods_db.values() if not p.activo]
                if inactivos:
                    resultados.append(
                        SyncOperacionResultado(
                            id=op_id,
                            estado="conflicto",
                            motivo="producto_inactivo",
                            detalle={"inactivos": inactivos},
                        )
                    )
                    continue

                importe_total = sum(prods_db[it.producto_id].precio * it.cantidad for it in nvp.items)

                comprador = Comprador(
                    campana_id=ctx.campana.id,
                    nombre_cifrado=cripto.cifrar(nvp.comprador.nombre.strip()),
                    telefono_cifrado=cripto.cifrar(nvp.comprador.telefono.strip()),
                    creado_por=ctx.usuario.id,
                )
                s.add(comprador)
                await s.flush()

                codigo_corto = _generar_codigo_corto()
                venta = Venta(
                    id=op_id,
                    campana_id=ctx.campana.id,
                    vendedor_id=ctx.usuario.id,
                    comprador_id=comprador.id,
                    importe=importe_total,
                    estado="confirmada",
                    entrega=nvp.entrega,
                    codigo_corto=codigo_corto,
                )
                s.add(venta)
                await s.flush()

                items_sync = []
                for it in nvp.items:
                    prod = prods_db[it.producto_id]
                    s.add(
                        VentaItem(
                            venta_id=venta.id,
                            producto_id=prod.id,
                            cantidad=it.cantidad,
                            precio_unitario=prod.precio,
                        )
                    )
                    items_sync.append({
                        "producto_id": str(prod.id),
                        "nombre": prod.nombre,
                        "cantidad": it.cantidad,
                        "precio_unitario": prod.precio,
                    })

                # Cobro
                if nvp.destino_cobro != "adeudado":
                    if nvp.destino_cobro == "efectivo":
                        caja = (
                            await s.execute(
                                select(Caja).where(
                                    Caja.campana_id == ctx.campana.id,
                                    Caja.tipo == "efectivo",
                                    Caja.titular_id == ctx.usuario.id,
                                )
                            )
                        ).scalar_one()
                        est_mov = "confirmado"
                        req_aprob = None
                        apr_por = ctx.usuario.id
                    elif nvp.destino_cobro in ("billetera", "cuenta_principal"):
                        if es_dueno_cuenta or nvp.destino_cobro == "cuenta_principal":
                            caja = caja_ppal
                            if es_dueno_cuenta:
                                est_mov = "confirmado"
                                req_aprob = None
                                apr_por = ctx.usuario.id
                            else:
                                est_mov = "pendiente"
                                req_aprob = caja_ppal.titular_id
                                apr_por = None
                        else:
                            caja = (
                                await s.execute(
                                    select(Caja).where(
                                        Caja.campana_id == ctx.campana.id,
                                        Caja.tipo == "billetera",
                                        Caja.titular_id == ctx.usuario.id,
                                    )
                                )
                            ).scalar_one()
                            est_mov = "confirmado"
                            req_aprob = None
                            apr_por = ctx.usuario.id

                    mov = Movimiento(
                        campana_id=ctx.campana.id,
                        tipo="cobro",
                        caja_destino=caja.id,
                        importe=importe_total,
                        estado=est_mov,
                        requiere_aprobacion_de=req_aprob,
                        aprobado_por=apr_por,
                        venta_id=venta.id,
                        creado_por=ctx.usuario.id,
                    )
                    s.add(mov)

                sync_entry = await registrar_cambio_sync(
                    s,
                    ctx.campana.id,
                    tabla="ventas",
                    fila_id=str(venta.id),
                    op="I",
                    datos={
                        "id": str(venta.id),
                        "items_productos": items_sync,
                        "importe": importe_total,
                        "entrega": nvp.entrega,
                        "codigo_corto": codigo_corto,
                        "comprador_nombre": nvp.comprador.nombre.strip(),
                        "vendedor_id": str(ctx.usuario.id),
                        "vendedor_nombre": ctx.usuario.nombre,
                        "destino_cobro": nvp.destino_cobro,
                    },
                )

                resultados.append(
                    SyncOperacionResultado(
                        id=op_id,
                        estado="ok",
                        secuencia=sync_entry.secuencia,
                        resultado={
                            "venta_id": str(venta.id),
                            "codigo_corto": codigo_corto,
                            "importe": importe_total,
                        },
                    )
                )

            elif op_tipo == "actualizar_entrega":
                venta_id = uuid.UUID(str(payload.get("venta_id")))
                nueva_entrega = str(payload.get("entrega"))
                venta_a_act = await s.get(Venta, venta_id)
                if venta_a_act is None or venta_a_act.campana_id != ctx.campana.id:
                    resultados.append(
                        SyncOperacionResultado(
                            id=op_id,
                            estado="rechazado",
                            motivo="la venta no existe",
                        )
                    )
                    continue

                venta_a_act.entrega = nueva_entrega
                sync_entry = await registrar_cambio_sync(
                    s,
                    ctx.campana.id,
                    tabla="ventas",
                    fila_id=str(venta_a_act.id),
                    op="U",
                    datos={"id": str(venta_a_act.id), "entrega": nueva_entrega},
                )

                resultados.append(
                    SyncOperacionResultado(
                        id=op_id,
                        estado="ok",
                        secuencia=sync_entry.secuencia,
                        resultado={"entrega": nueva_entrega},
                    )
                )

            else:
                resultados.append(
                    SyncOperacionResultado(
                        id=op_id,
                        estado="rechazado",
                        motivo=f"operación no soportada: {op_tipo}",
                    )
                )

        except Exception as e:
            resultados.append(
                SyncOperacionResultado(
                    id=op_id,
                    estado="rechazado",
                    motivo=f"error de procesamiento: {str(e)}",
                )
            )

    await s.commit()
    return SyncPushSalida(resultados=resultados)


@ruteador.get("/campanas/{campana_id}/sync/pull", response_model=SyncPullSalida)
async def sync_pull(
    desde: int = Query(default=0, ge=0),
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> SyncPullSalida:
    """Descarga los cambios de la campaña desde una secuencia (o snapshot completo si desde=0)."""
    # Si desde == 0: hidratación completa inicial para la base de datos local
    if desde == 0:
        # Cargar números
        nums = (
            await s.execute(
                select(Numero)
                .where(Numero.campana_id == ctx.campana.id)
                .order_by(Numero.numero.asc())
            )
        ).scalars().all()

        # Cargar productos
        prods = (
            await s.execute(
                select(Producto)
                .where(Producto.campana_id == ctx.campana.id)
                .order_by(Producto.nombre.asc())
            )
        ).scalars().all()

        # Cargar ventas con items
        ventas = (
            await s.execute(
                select(Venta)
                .options(
                    selectinload(Venta.items).selectinload(VentaItem.producto),
                    selectinload(Venta.comprador),
                    selectinload(Venta.vendedor),
                )
                .where(Venta.campana_id == ctx.campana.id)
                .order_by(Venta.creada.desc())
            )
        ).scalars().all()

        # Cargar movimientos
        movs = (
            await s.execute(
                select(Movimiento)
                .where(Movimiento.campana_id == ctx.campana.id)
                .order_by(Movimiento.creado.desc())
            )
        ).scalars().all()

        # Cargar cajas e integrantes
        cajas = (
            await s.execute(
                select(Caja).where(Caja.campana_id == ctx.campana.id)
            )
        ).scalars().all()

        integrantes = (
            await s.execute(
                select(Integrante)
                .options(selectinload(Integrante.usuario))
                .where(Integrante.campana_id == ctx.campana.id)
            )
        ).scalars().all()

        # Obtener secuencia máxima actual
        max_sec = (
            await s.execute(
                select(func.coalesce(func.max(SyncLog.secuencia), 0)).where(
                    SyncLog.campana_id == ctx.campana.id
                )
            )
        ).scalar_one()

        snapshot = {
            "campana": {
                "id": str(ctx.campana.id),
                "nombre": ctx.campana.nombre,
                "tipo": ctx.campana.tipo,
                "estado": ctx.campana.estado,
                "meta": ctx.campana.meta,
                "config": ctx.campana.config,
            },
            "numeros": [
                {
                    "numero": n.numero,
                    "estado": n.estado,
                    "reservado_por": str(n.reservado_por) if n.reservado_por else None,
                    "reserva_nota": n.reserva_nota,
                    "venta_id": str(n.venta_id) if n.venta_id else None,
                }
                for n in nums
            ],
            "productos": [
                {
                    "id": str(p.id),
                    "nombre": p.nombre,
                    "precio": p.precio,
                    "activo": p.activo,
                }
                for p in prods
            ],
            "ventas": [
                {
                    "id": str(v.id),
                    "vendedor_id": str(v.vendedor_id),
                    "vendedor_nombre": v.vendedor.nombre,
                    "comprador_nombre": cripto.descifrar(v.comprador.nombre_cifrado) or "",
                    "comprador_telefono": (
                        cripto.descifrar(v.comprador.telefono_cifrado)
                        if v.vendedor_id == ctx.usuario.id
                        else None
                    ),
                    "numeros": [it.numero for it in v.items if it.numero is not None],
                    "items_productos": [
                        {
                            "producto_id": str(it.producto.id),
                            "nombre": it.producto.nombre,
                            "cantidad": it.cantidad,
                            "precio_unitario": it.precio_unitario,
                            "subtotal": it.precio_unitario * it.cantidad,
                        }
                        for it in v.items
                        if it.producto is not None
                    ],
                    "importe": v.importe,
                    "estado": v.estado,
                    "entrega": v.entrega,
                    "codigo_corto": v.codigo_corto,
                    "creada": v.creada.isoformat(),
                }
                for v in ventas
            ],
            "cajas": [
                {
                    "id": str(c.id),
                    "tipo": c.tipo,
                    "titular_id": str(c.titular_id),
                    "titular_nombre": c.titular.nombre,
                }
                for c in cajas
            ],
            "integrantes": [
                {
                    "usuario_id": str(i.usuario_id),
                    "nombre": i.usuario.nombre,
                    "rol": i.rol,
                    "estado": i.estado,
                }
                for i in integrantes
            ],
        }

        return SyncPullSalida(cursor=max_sec, hay_mas=False, cambios=[], snapshot=snapshot)

    # Consulta incremental si desde > 0
    limite = 100
    cambios_db = (
        await s.execute(
            select(SyncLog)
            .where(SyncLog.campana_id == ctx.campana.id, SyncLog.secuencia > desde)
            .order_by(SyncLog.secuencia.asc())
            .limit(limite + 1)
        )
    ).scalars().all()

    hay_mas = len(cambios_db) > limite
    items = cambios_db[:limite]

    nuevo_cursor = items[-1].secuencia if items else desde

    cambios_salida = [
        {
            "secuencia": c.secuencia,
            "tabla": c.tabla,
            "fila_id": c.fila_id,
            "op": c.op,
            "datos": c.datos,
            "creado": c.creado.isoformat(),
        }
        for c in items
    ]

    return SyncPullSalida(
        cursor=nuevo_cursor,
        hay_mas=hay_mas,
        cambios=cambios_salida,
        snapshot=None,
    )
