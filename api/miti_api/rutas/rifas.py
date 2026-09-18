"""Rifas, números, ventas, cobros y recaudación."""

import random
import string
import uuid
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from .. import cripto
from ..config import ajustes
from ..db import sesion
from ..esquemas import (
    CompradorSalida,
    MovimientoSalida,
    NuevaVenta,
    NuevoCobro,
    NumeroSalida,
    RechazarMovimiento,
    RecaudacionCaja,
    RecaudacionSalida,
    ItemVentaProductoSalida,
    ReservarNumero,
    VentaSalida,
)
from ..modelos import (
    Caja,
    Campana,
    Comprador,
    Historial,
    Movimiento,
    Numero,
    Producto,
    Usuario,
    Venta,
    VentaItem,
)
from ..seguridad import Contexto, contexto_activo

ruteador = APIRouter(tags=["rifas y ventas"])


def _generar_codigo_corto() -> str:
    caracteres = string.ascii_uppercase + string.digits
    caracteres = caracteres.replace("O", "").replace("0", "").replace("I", "").replace("1", "")
    return "".join(random.choices(caracteres, k=6))


async def asegurar_numeros(s: AsyncSession, campana: Campana) -> None:
    """Si la campaña es una rifa y todavía no se crearon sus números, los inicializa."""
    if campana.tipo != "rifa" or not campana.config:
        return
    desde = campana.config.get("desde")
    hasta = campana.config.get("hasta")
    if desde is None or hasta is None:
        return

    conteo = (
        await s.execute(select(func.count()).select_from(Numero).where(Numero.campana_id == campana.id))
    ).scalar_one()

    if conteo == 0:
        for n in range(int(desde), int(hasta) + 1):
            s.add(Numero(campana_id=campana.id, numero=n, estado="libre"))
        await s.flush()


async def limpiar_reservas_vencidas(s: AsyncSession, campana_id: uuid.UUID) -> None:
    """Libera las reservas que pasaron las 48 horas."""
    ahora = datetime.now(UTC)
    vencidos = (
        await s.execute(
            select(Numero).where(
                Numero.campana_id == campana_id,
                Numero.estado == "reservado",
                Numero.reserva_vence < ahora,
            )
        )
    ).scalars().all()

    for n in vencidos:
        n.estado = "libre"
        n.reservado_por = None
        n.reserva_vence = None
        n.reserva_nota = None
    if vencidos:
        await s.flush()


@ruteador.get("/campanas/{campana_id}/numeros", response_model=list[NumeroSalida])
async def listar_numeros(
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> list[NumeroSalida]:
    await asegurar_numeros(s, ctx.campana)
    await limpiar_reservas_vencidas(s, ctx.campana.id)
    await s.commit()

    filas = (
        await s.execute(
            select(Numero, Usuario.nombre)
            .outerjoin(Venta, Numero.venta_id == Venta.id)
            .outerjoin(Usuario, Venta.vendedor_id == Usuario.id)
            .where(Numero.campana_id == ctx.campana.id)
            .order_by(Numero.numero)
        )
    ).all()

    resultado = []
    for num, vendedor_nombre in filas:
        resultado.append(
            NumeroSalida(
                numero=num.numero,
                estado=num.estado,
                reserva_vence=num.reserva_vence,
                reserva_nota=num.reserva_nota,
                reservado_por_mi=(num.reservado_por == ctx.usuario.id),
                vendedor_nombre=vendedor_nombre if num.estado == "vendido" else None,
            )
        )
    return resultado


@ruteador.post("/campanas/{campana_id}/numeros/{numero}/reservar", response_model=NumeroSalida)
async def reservar_numero(
    numero: int,
    datos: ReservarNumero,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> NumeroSalida:
    await asegurar_numeros(s, ctx.campana)
    await limpiar_reservas_vencidas(s, ctx.campana.id)

    num = (
        await s.execute(
            select(Numero)
            .where(Numero.campana_id == ctx.campana.id, Numero.numero == numero)
            .with_for_update()
        )
    ).scalar_one_or_none()

    if num is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "el número no existe en esta rifa")
    if num.estado != "libre":
        raise HTTPException(status.HTTP_409_CONFLICT, f"el número {numero} no está disponible")

    ahora = datetime.now(UTC)
    num.estado = "reservado"
    num.reservado_por = ctx.usuario.id
    num.reserva_vence = ahora + timedelta(hours=48)
    num.reserva_nota = datos.nota.strip() if datos.nota else None

    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="numero_reservado",
            objeto="numero",
            detalle={"numero": numero, "nota": num.reserva_nota},
        )
    )
    await s.commit()

    return NumeroSalida(
        numero=num.numero,
        estado=num.estado,
        reserva_vence=num.reserva_vence,
        reserva_nota=num.reserva_nota,
        reservado_por_mi=True,
    )


@ruteador.post("/campanas/{campana_id}/numeros/{numero}/liberar", response_model=NumeroSalida)
async def liberar_numero(
    numero: int,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> NumeroSalida:
    num = (
        await s.execute(
            select(Numero)
            .where(Numero.campana_id == ctx.campana.id, Numero.numero == numero)
            .with_for_update()
        )
    ).scalar_one_or_none()

    if num is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "el número no existe")
    if num.estado != "reservado":
        raise HTTPException(status.HTTP_409_CONFLICT, f"el número {numero} no está reservado")
    if num.reservado_por != ctx.usuario.id and not ctx.es_admin:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "solo quien reservó el número o el administrador pueden liberarlo",
        )

    num.estado = "libre"
    num.reservado_por = None
    num.reserva_vence = None
    num.reserva_nota = None

    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="numero_liberado",
            objeto="numero",
            detalle={"numero": numero},
        )
    )
    await s.commit()

    return NumeroSalida(
        numero=num.numero,
        estado="libre",
        reserva_vence=None,
        reserva_nota=None,
        reservado_por_mi=False,
    )


@ruteador.post("/campanas/{campana_id}/ventas", response_model=VentaSalida, status_code=status.HTTP_201_CREATED)
async def registrar_venta(
    datos: NuevaVenta,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> VentaSalida:
    if ctx.campana.estado not in ("activa", "cerrada"):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"no se pueden registrar ventas en una campaña con estado «{ctx.campana.estado}»",
        )

    await asegurar_numeros(s, ctx.campana)
    await limpiar_reservas_vencidas(s, ctx.campana.id)

    # Control de límites del plan gratis
    if ctx.campana.plan == "gratis":
        cant_ventas = (
            await s.execute(
                select(func.count()).select_from(Venta).where(
                    Venta.campana_id == ctx.campana.id, Venta.estado == "confirmada"
                )
            )
        ).scalar_one()
        if cant_ventas >= ajustes().limite_gratis_ventas:
            raise HTTPException(
                status.HTTP_402_PAYMENT_REQUIRED,
                f"el plan gratis admite hasta {ajustes().limite_gratis_ventas} ventas",
            )

        cant_vendidos = (
            await s.execute(
                select(func.count()).select_from(Numero).where(
                    Numero.campana_id == ctx.campana.id, Numero.estado == "vendido"
                )
            )
        ).scalar_one()
        if cant_vendidos + len(datos.numeros) > ajustes().limite_gratis_numeros:
            raise HTTPException(
                status.HTTP_402_PAYMENT_REQUIRED,
                f"el plan gratis admite hasta {ajustes().limite_gratis_numeros} números vendidos",
            )

    # Bloquear los números pedidos para validar y evitar ventas simultáneas
    nums_bloqueados = (
        await s.execute(
            select(Numero)
            .where(Numero.campana_id == ctx.campana.id, Numero.numero.in_(datos.numeros))
            .with_for_update()
        )
    ).scalars().all()

    if len(nums_bloqueados) != len(datos.numeros):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "uno o más números no existen en la campaña")

    ahora = datetime.now(UTC)
    for n in nums_bloqueados:
        if n.estado == "vendido":
            raise HTTPException(status.HTTP_409_CONFLICT, f"el número {n.numero} ya está vendido")
        if n.estado == "reservado":
            if n.reserva_vence and n.reserva_vence < ahora:
                # Venció: se puede vender
                pass
            elif n.reservado_por != ctx.usuario.id:
                raise HTTPException(
                    status.HTTP_409_CONFLICT,
                    f"el número {n.numero} está reservado por otro integrante",
                )

    precio_unitario = int(ctx.campana.config.get("precio", 0))
    importe_total = precio_unitario * len(datos.numeros)

    # 1. Comprador
    comprador = Comprador(
        campana_id=ctx.campana.id,
        nombre_cifrado=cripto.cifrar(datos.comprador.nombre.strip()),
        telefono_cifrado=cripto.cifrar(datos.comprador.telefono.strip()),
        creado_por=ctx.usuario.id,
    )
    s.add(comprador)
    await s.flush()

    # 2. Venta
    venta_id = datos.id or uuid.uuid4()
    codigo_corto = _generar_codigo_corto()
    venta = Venta(
        id=venta_id,
        campana_id=ctx.campana.id,
        vendedor_id=ctx.usuario.id,
        comprador_id=comprador.id,
        importe=importe_total,
        estado="confirmada",
        codigo_corto=codigo_corto,
    )
    s.add(venta)
    await s.flush()

    # 3. Items y actualización de números
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

    # 4. Destino de los fondos y movimiento
    cobrado_confirmado = 0
    cobrado_pendiente = 0
    if datos.destino_cobro != "adeudado":
        importe_a_cobrar = (
            datos.importe_cobrado if datos.importe_cobrado is not None else importe_total
        )
        if importe_a_cobrar > 0:
            caja_ppal = (
                await s.execute(
                    select(Caja).where(
                        Caja.campana_id == ctx.campana.id,
                        Caja.tipo == "principal",
                    )
                )
            ).scalar_one()
            es_dueno_cuenta = caja_ppal.titular_id == ctx.usuario.id

            if datos.destino_cobro == "efectivo":
                caja = (
                    await s.execute(
                        select(Caja).where(
                            Caja.campana_id == ctx.campana.id,
                            Caja.tipo == "efectivo",
                            Caja.titular_id == ctx.usuario.id,
                        )
                    )
                ).scalar_one()
                estado_mov = "confirmado"
                requiere = None
                aprobado = ctx.usuario.id
                cobrado_confirmado = importe_a_cobrar
            elif datos.destino_cobro in ("billetera", "cuenta_principal"):
                if es_dueno_cuenta or datos.destino_cobro == "cuenta_principal":
                    caja = caja_ppal
                    if es_dueno_cuenta:
                        estado_mov = "confirmado"
                        requiere = None
                        aprobado = ctx.usuario.id
                        cobrado_confirmado = importe_a_cobrar
                    else:
                        estado_mov = "pendiente"
                        requiere = caja_ppal.titular_id
                        aprobado = None
                        cobrado_pendiente = importe_a_cobrar
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
                    estado_mov = "confirmado"
                    requiere = None
                    aprobado = ctx.usuario.id
                    cobrado_confirmado = importe_a_cobrar
            else:
                raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "destino no válido")

            mov = Movimiento(
                campana_id=ctx.campana.id,
                tipo="cobro",
                caja_destino=caja.id,
                importe=importe_a_cobrar,
                estado=estado_mov,
                requiere_aprobacion_de=requiere,
                aprobado_por=aprobado,
                venta_id=venta.id,
                comprobante_id=datos.comprobante_id,
                creado_por=ctx.usuario.id,
            )
            s.add(mov)

    # 5. Historial
    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="venta_creada",
            objeto="venta",
            objeto_id=venta.id,
            detalle={
                "numeros": datos.numeros,
                "importe": importe_total,
                "destino": datos.destino_cobro,
                "codigo": codigo_corto,
            },
        )
    )

    await s.commit()

    saldo_adeudado = max(0, importe_total - cobrado_confirmado - cobrado_pendiente)

    return VentaSalida(
        id=venta.id,
        campana_id=ctx.campana.id,
        vendedor_id=ctx.usuario.id,
        vendedor_nombre=ctx.usuario.nombre,
        comprador=CompradorSalida(
            id=comprador.id,
            nombre=datos.comprador.nombre.strip(),
            telefono=datos.comprador.telefono.strip(),
        ),
        numeros=datos.numeros,
        importe=importe_total,
        estado=venta.estado,
        codigo_corto=codigo_corto,
        creada=venta.creada,
        total_cobrado=cobrado_confirmado,
        cobro_pendiente=cobrado_pendiente,
        saldo_adeudado=saldo_adeudado,
    )


@ruteador.get("/campanas/{campana_id}/ventas", response_model=list[VentaSalida])
async def listar_ventas(
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> list[VentaSalida]:
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

    # Cargar movimientos asociados a las ventas para calcular lo cobrado
    venta_ids = [v.id for v in ventas]
    movimientos_por_venta: dict[uuid.UUID, list[Movimiento]] = {vid: [] for vid in venta_ids}
    if venta_ids:
        movs = (
            await s.execute(select(Movimiento).where(Movimiento.venta_id.in_(venta_ids)))
        ).scalars().all()
        for m in movs:
            if m.venta_id:
                movimientos_por_venta[m.venta_id].append(m)

    resultado = []
    for v in ventas:
        movs = movimientos_por_venta.get(v.id, [])
        confirmado = sum(m.importe for m in movs if m.estado == "confirmado")
        pendiente = sum(m.importe for m in movs if m.estado == "pendiente")
        saldo = max(0, v.importe - confirmado - pendiente)

        # Regla §3.2: Solo quien vendió ve el teléfono del comprador
        telefono = (
            cripto.descifrar(v.comprador.telefono_cifrado)
            if v.vendedor_id == ctx.usuario.id
            else None
        )
        nombre = cripto.descifrar(v.comprador.nombre_cifrado) or ""

        numeros = [item.numero for item in v.items if item.numero is not None]
        prod_items = [
            ItemVentaProductoSalida(
                producto_id=item.producto.id,
                nombre=item.producto.nombre,
                cantidad=item.cantidad,
                precio_unitario=item.precio_unitario,
                subtotal=item.precio_unitario * item.cantidad,
            )
            for item in v.items
            if item.producto is not None
        ]

        resultado.append(
            VentaSalida(
                id=v.id,
                campana_id=v.campana_id,
                vendedor_id=v.vendedor_id,
                vendedor_nombre=v.vendedor.nombre,
                comprador=CompradorSalida(
                    id=v.comprador.id,
                    nombre=nombre,
                    telefono=telefono,
                ),
                numeros=numeros,
                items_productos=prod_items,
                importe=v.importe,
                estado=v.estado,
                entrega=v.entrega,
                codigo_corto=v.codigo_corto,
                creada=v.creada,
                total_cobrado=confirmado,
                cobro_pendiente=pendiente,
                saldo_adeudado=saldo,
            )
        )
    return resultado


@ruteador.get("/campanas/{campana_id}/ventas/{venta_id}", response_model=VentaSalida)
async def detalle_venta(
    venta_id: uuid.UUID,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> VentaSalida:
    venta = (
        await s.execute(
            select(Venta)
            .options(
                selectinload(Venta.items).selectinload(VentaItem.producto),
                selectinload(Venta.comprador),
                selectinload(Venta.vendedor),
            )
            .where(Venta.campana_id == ctx.campana.id, Venta.id == venta_id)
        )
    ).scalar_one_or_none()

    if venta is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "la venta no existe")

    movs = (
        await s.execute(select(Movimiento).where(Movimiento.venta_id == venta.id))
    ).scalars().all()
    confirmado = sum(m.importe for m in movs if m.estado == "confirmado")
    pendiente = sum(m.importe for m in movs if m.estado == "pendiente")
    saldo = max(0, venta.importe - confirmado - pendiente)

    telefono = (
        cripto.descifrar(venta.comprador.telefono_cifrado)
        if venta.vendedor_id == ctx.usuario.id
        else None
    )
    nombre = cripto.descifrar(venta.comprador.nombre_cifrado) or ""

    numeros = [item.numero for item in venta.items if item.numero is not None]
    prod_items = [
        ItemVentaProductoSalida(
            producto_id=item.producto.id,
            nombre=item.producto.nombre,
            cantidad=item.cantidad,
            precio_unitario=item.precio_unitario,
            subtotal=item.precio_unitario * item.cantidad,
        )
        for item in venta.items
        if item.producto is not None
    ]

    return VentaSalida(
        id=venta.id,
        campana_id=venta.campana_id,
        vendedor_id=venta.vendedor_id,
        vendedor_nombre=venta.vendedor.nombre,
        comprador=CompradorSalida(
            id=venta.comprador.id,
            nombre=nombre,
            telefono=telefono,
        ),
        numeros=numeros,
        items_productos=prod_items,
        importe=venta.importe,
        estado=venta.estado,
        entrega=venta.entrega,
        codigo_corto=venta.codigo_corto,
        creada=venta.creada,
        total_cobrado=confirmado,
        cobro_pendiente=pendiente,
        saldo_adeudado=saldo,
    )


@ruteador.post("/campanas/{campana_id}/ventas/{venta_id}/cobros", response_model=MovimientoSalida)
async def registrar_cobro_venta(
    venta_id: uuid.UUID,
    datos: NuevoCobro,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> MovimientoSalida:
    venta = await s.get(Venta, venta_id)
    if venta is None or venta.campana_id != ctx.campana.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "la venta no existe")

    movs = (
        await s.execute(select(Movimiento).where(Movimiento.venta_id == venta.id))
    ).scalars().all()
    confirmado = sum(m.importe for m in movs if m.estado == "confirmado")
    pendiente = sum(m.importe for m in movs if m.estado == "pendiente")
    saldo = max(0, venta.importe - confirmado - pendiente)

    if datos.importe > saldo:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"el importe supera el saldo adeudado de la venta (${saldo / 100:.2f})",
        )

    caja_ppal = (
        await s.execute(
            select(Caja).where(Caja.campana_id == ctx.campana.id, Caja.tipo == "principal")
        )
    ).scalar_one()
    es_dueno_cuenta = caja_ppal.titular_id == ctx.usuario.id

    if datos.caja_tipo == "efectivo":
        caja = (
            await s.execute(
                select(Caja).where(
                    Caja.campana_id == ctx.campana.id,
                    Caja.tipo == "efectivo",
                    Caja.titular_id == ctx.usuario.id,
                )
            )
        ).scalar_one()
        estado_mov = "confirmado"
        requiere = None
        aprobado = ctx.usuario.id
    elif datos.caja_tipo in ("billetera", "cuenta_principal"):
        if es_dueno_cuenta or datos.caja_tipo == "cuenta_principal":
            caja = caja_ppal
            if es_dueno_cuenta:
                estado_mov = "confirmado"
                requiere = None
                aprobado = ctx.usuario.id
            else:
                estado_mov = "pendiente"
                requiere = caja_ppal.titular_id
                aprobado = None
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
            estado_mov = "confirmado"
            requiere = None
            aprobado = ctx.usuario.id
    else:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "tipo de caja inválido")

    mov = Movimiento(
        campana_id=ctx.campana.id,
        tipo="cobro",
        caja_destino=caja.id,
        importe=datos.importe,
        estado=estado_mov,
        requiere_aprobacion_de=requiere,
        aprobado_por=aprobado,
        venta_id=venta.id,
        comprobante_id=datos.comprobante_id,
        creado_por=ctx.usuario.id,
    )
    s.add(mov)
    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="cobro_registrado",
            objeto="venta",
            objeto_id=venta.id,
            detalle={"importe": datos.importe, "caja": datos.caja_tipo, "estado": estado_mov},
        )
    )
    await s.commit()
    await s.refresh(mov)

    return MovimientoSalida(
        id=mov.id,
        campana_id=mov.campana_id,
        tipo=mov.tipo,
        caja_origen=mov.caja_origen,
        caja_destino=mov.caja_destino,
        importe=mov.importe,
        estado=mov.estado,
        requiere_aprobacion_de=mov.requiere_aprobacion_de,
        aprobado_por=mov.aprobado_por,
        motivo=mov.motivo,
        venta_id=mov.venta_id,
        comprobante_id=mov.comprobante_id,
        creado_por=mov.creado_por,
        creado=mov.creado,
    )


@ruteador.get("/campanas/{campana_id}/movimientos", response_model=list[MovimientoSalida])
async def listar_movimientos(
    estado: str | None = None,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> list[MovimientoSalida]:
    q = select(Movimiento).where(Movimiento.campana_id == ctx.campana.id)
    if estado:
        q = q.where(Movimiento.estado == estado)
    q = q.order_by(Movimiento.creado.desc())
    movs = (await s.execute(q)).scalars().all()
    return [
        MovimientoSalida(
            id=m.id,
            campana_id=m.campana_id,
            tipo=m.tipo,
            caja_origen=m.caja_origen,
            caja_destino=m.caja_destino,
            importe=m.importe,
            estado=m.estado,
            requiere_aprobacion_de=m.requiere_aprobacion_de,
            aprobado_por=m.aprobado_por,
            motivo=m.motivo,
            venta_id=m.venta_id,
            comprobante_id=m.comprobante_id,
            creado_por=m.creado_por,
            creado=m.creado,
        )
        for m in movs
    ]


@ruteador.post("/campanas/{campana_id}/movimientos/{movimiento_id}/confirmar", response_model=MovimientoSalida)
async def confirmar_movimiento(
    movimiento_id: uuid.UUID,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> MovimientoSalida:
    mov = await s.get(Movimiento, movimiento_id)
    if mov is None or mov.campana_id != ctx.campana.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "el movimiento no existe")
    if mov.estado != "pendiente":
        raise HTTPException(status.HTTP_409_CONFLICT, f"el movimiento no está pendiente (estado: {mov.estado})")

    if mov.requiere_aprobacion_de != ctx.usuario.id and not ctx.es_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "no tenés permiso para confirmar este movimiento")

    mov.estado = "confirmado"
    mov.aprobado_por = ctx.usuario.id

    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="movimiento_confirmado",
            objeto="movimiento",
            objeto_id=mov.id,
            detalle={"tipo": mov.tipo, "importe": mov.importe},
        )
    )
    await s.commit()
    await s.refresh(mov)

    return MovimientoSalida(
        id=mov.id,
        campana_id=mov.campana_id,
        tipo=mov.tipo,
        caja_origen=mov.caja_origen,
        caja_destino=mov.caja_destino,
        importe=mov.importe,
        estado=mov.estado,
        requiere_aprobacion_de=mov.requiere_aprobacion_de,
        aprobado_por=mov.aprobado_por,
        motivo=mov.motivo,
        venta_id=mov.venta_id,
        comprobante_id=mov.comprobante_id,
        creado_por=mov.creado_por,
        creado=mov.creado,
    )


@ruteador.post("/campanas/{campana_id}/movimientos/{movimiento_id}/rechazar", response_model=MovimientoSalida)
async def rechazar_movimiento(
    movimiento_id: uuid.UUID,
    datos: RechazarMovimiento,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> MovimientoSalida:
    mov = await s.get(Movimiento, movimiento_id)
    if mov is None or mov.campana_id != ctx.campana.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "el movimiento no existe")
    if mov.estado != "pendiente":
        raise HTTPException(status.HTTP_409_CONFLICT, f"el movimiento no está pendiente (estado: {mov.estado})")

    if mov.requiere_aprobacion_de != ctx.usuario.id and not ctx.es_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "no tenés permiso para rechazar este movimiento")

    mov.estado = "rechazado"
    mov.aprobado_por = ctx.usuario.id
    mov.motivo = datos.motivo.strip()

    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="movimiento_rechazado",
            objeto="movimiento",
            objeto_id=mov.id,
            detalle={"tipo": mov.tipo, "importe": mov.importe, "motivo": mov.motivo},
        )
    )
    await s.commit()
    await s.refresh(mov)

    return MovimientoSalida(
        id=mov.id,
        campana_id=mov.campana_id,
        tipo=mov.tipo,
        caja_origen=mov.caja_origen,
        caja_destino=mov.caja_destino,
        importe=mov.importe,
        estado=mov.estado,
        requiere_aprobacion_de=mov.requiere_aprobacion_de,
        aprobado_por=mov.aprobado_por,
        motivo=mov.motivo,
        venta_id=mov.venta_id,
        comprobante_id=mov.comprobante_id,
        creado_por=mov.creado_por,
        creado=mov.creado,
    )


@ruteador.get("/campanas/{campana_id}/recaudacion", response_model=RecaudacionSalida)
async def ver_recaudacion(
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> RecaudacionSalida:
    await asegurar_numeros(s, ctx.campana)
    await limpiar_reservas_vencidas(s, ctx.campana.id)

    # 1. Movimientos
    movs = (
        await s.execute(
            select(Movimiento).where(
                Movimiento.campana_id == ctx.campana.id,
                Movimiento.tipo == "cobro",
            )
        )
    ).scalars().all()

    cobrado = sum(m.importe for m in movs if m.estado == "confirmado")
    pendiente = sum(m.importe for m in movs if m.estado == "pendiente")

    # 2. Ventas
    ventas = (
        await s.execute(
            select(Venta).where(
                Venta.campana_id == ctx.campana.id,
                Venta.estado == "confirmada",
            )
        )
    ).scalars().all()
    vendido = sum(v.importe for v in ventas)
    falta_cobrar = max(0, vendido - cobrado)

    # 3. Números
    numeros = (
        await s.execute(select(Numero.estado).where(Numero.campana_id == ctx.campana.id))
    ).scalars().all()
    totales = len(numeros)
    libres = sum(1 for e in numeros if e == "libre")
    reservados = sum(1 for e in numeros if e == "reservado")
    vendidos = sum(1 for e in numeros if e == "vendido")

    # 4. Desglose de cajas
    cajas_con_usuario = (
        await s.execute(
            select(Caja, Usuario.nombre)
            .join(Usuario, Caja.titular_id == Usuario.id)
            .where(Caja.campana_id == ctx.campana.id)
        )
    ).all()

    cajas_salida = []
    for c, titular_nombre in cajas_con_usuario:
        c_confirmado = sum(
            m.importe for m in movs if m.caja_destino == c.id and m.estado == "confirmado"
        )
        c_pendiente = sum(
            m.importe for m in movs if m.caja_destino == c.id and m.estado == "pendiente"
        )
        cajas_salida.append(
            RecaudacionCaja(
                caja_id=c.id,
                tipo=c.tipo,
                titular_id=c.titular_id,
                titular_nombre=titular_nombre,
                confirmado=c_confirmado,
                pendiente=c_pendiente,
            )
        )
    # 5. Desglose de productos si es campaña de productos
    productos_desglose = []
    if ctx.campana.tipo == "productos":
        prods_vendidos = (
            await s.execute(
                select(
                    Producto.id,
                    Producto.nombre,
                    func.sum(VentaItem.cantidad).label("cantidad_total"),
                    func.sum(VentaItem.cantidad * VentaItem.precio_unitario).label("importe_total"),
                )
                .join(VentaItem, VentaItem.producto_id == Producto.id)
                .join(Venta, Venta.id == VentaItem.venta_id)
                .where(Producto.campana_id == ctx.campana.id, Venta.estado == "confirmada")
                .group_by(Producto.id, Producto.nombre)
            )
        ).all()

        for pid, pnom, cant, imp in prods_vendidos:
            productos_desglose.append(
                {
                    "producto_id": str(pid),
                    "nombre": pnom,
                    "cantidad": int(cant or 0),
                    "total": int(imp or 0),
                }
            )

    return RecaudacionSalida(
        cobrado=cobrado,
        pendiente=pendiente,
        vendido=vendido,
        falta_cobrar=falta_cobrar,
        numeros_totales=totales,
        numeros_libres=libres,
        numeros_reservados=reservados,
        numeros_vendidos=vendidos,
        cajas=cajas_salida,
        productos_desglose=productos_desglose,
    )
