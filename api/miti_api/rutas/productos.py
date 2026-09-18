"""Rutas para campañas de productos: catálogo, toma de pedidos, entrega y cobros."""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from .. import cripto
from ..config import ajustes
from ..db import sesion
from ..esquemas import (
    ActualizarEntrega,
    CompradorSalida,
    ItemVentaProductoSalida,
    NuevaVentaProductos,
    ProductoCrear,
    ProductoModificar,
    ProductoSalida,
    VentaSalida,
)
from ..modelos import Caja, Campana, Comprador, Historial, Movimiento, Producto, Usuario, Venta, VentaItem
from ..seguridad import Contexto, contexto_activo
from .rifas import _generar_codigo_corto

ruteador = APIRouter(tags=["productos"])


@ruteador.get("/campanas/{campana_id}/productos", response_model=list[ProductoSalida])
async def listar_productos(
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> list[ProductoSalida]:
    query = select(Producto).where(Producto.campana_id == ctx.campana.id)
    if not ctx.es_admin:
        query = query.where(Producto.activo.is_(True))
    query = query.order_by(Producto.nombre)

    resultado = await s.execute(query)
    prods = resultado.scalars().all()

    return [
        ProductoSalida(
            id=p.id,
            campana_id=p.campana_id,
            nombre=p.nombre,
            precio=p.precio,
            foto=p.foto,
            activo=p.activo,
            creado=p.creado,
        )
        for p in prods
    ]


@ruteador.post(
    "/campanas/{campana_id}/productos",
    response_model=ProductoSalida,
    status_code=status.HTTP_201_CREATED,
)
async def crear_producto(
    datos: ProductoCrear,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> ProductoSalida:
    if not ctx.es_admin:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "solo el administrador puede agregar productos al catálogo",
        )

    prod = Producto(
        campana_id=ctx.campana.id,
        nombre=datos.nombre.strip(),
        precio=datos.precio,
        foto=datos.foto,
        activo=True,
    )
    s.add(prod)
    await s.flush()

    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="producto_creado",
            objeto="producto",
            objeto_id=prod.id,
            detalle={"nombre": prod.nombre, "precio": prod.precio},
        )
    )
    await s.commit()

    return ProductoSalida(
        id=prod.id,
        campana_id=prod.campana_id,
        nombre=prod.nombre,
        precio=prod.precio,
        foto=prod.foto,
        activo=prod.activo,
        creado=prod.creado,
    )


@ruteador.patch(
    "/campanas/{campana_id}/productos/{producto_id}",
    response_model=ProductoSalida,
)
async def modificar_producto(
    producto_id: uuid.UUID,
    datos: ProductoModificar,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> ProductoSalida:
    if not ctx.es_admin:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "solo el administrador puede modificar productos",
        )

    prod = (
        await s.execute(
            select(Producto).where(Producto.id == producto_id, Producto.campana_id == ctx.campana.id)
        )
    ).scalar_one_or_none()

    if not prod:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "producto no encontrado")

    cambios = {}
    if datos.nombre is not None:
        prod.nombre = datos.nombre.strip()
        cambios["nombre"] = prod.nombre
    if datos.precio is not None:
        prod.precio = datos.precio
        cambios["precio"] = prod.precio
    if datos.activo is not None:
        prod.activo = datos.activo
        cambios["activo"] = prod.activo
    if datos.foto is not None:
        prod.foto = datos.foto
        cambios["foto"] = prod.foto

    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="producto_modificado",
            objeto="producto",
            objeto_id=prod.id,
            detalle=cambios,
        )
    )
    await s.commit()

    return ProductoSalida(
        id=prod.id,
        campana_id=prod.campana_id,
        nombre=prod.nombre,
        precio=prod.precio,
        foto=prod.foto,
        activo=prod.activo,
        creado=prod.creado,
    )


@ruteador.post(
    "/campanas/{campana_id}/ventas/productos",
    response_model=VentaSalida,
    status_code=status.HTTP_201_CREATED,
)
async def registrar_venta_productos(
    datos: NuevaVentaProductos,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> VentaSalida:
    if ctx.campana.estado not in ("activa", "cerrada"):
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"no se pueden registrar ventas en una campaña con estado «{ctx.campana.estado}»",
        )

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

    # Buscar productos solicitados
    prod_ids = [it.producto_id for it in datos.items]
    resultado = await s.execute(
        select(Producto).where(Producto.id.in_(prod_ids), Producto.campana_id == ctx.campana.id)
    )
    productos_db = {p.id: p for p in resultado.scalars().all()}

    if len(productos_db) != len(set(prod_ids)):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "uno o más productos no existen en la campaña")

    importe_total = 0
    items_salida = []
    items_a_guardar = []

    for item in datos.items:
        prod = productos_db[item.producto_id]
        if not prod.activo:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                f"el producto «{prod.nombre}» está desactivado",
            )
        subtotal = prod.precio * item.cantidad
        importe_total += subtotal
        items_a_guardar.append(
            VentaItem(
                producto_id=prod.id,
                cantidad=item.cantidad,
                precio_unitario=prod.precio,
            )
        )
        items_salida.append(
            ItemVentaProductoSalida(
                producto_id=prod.id,
                nombre=prod.nombre,
                cantidad=item.cantidad,
                precio_unitario=prod.precio,
                subtotal=subtotal,
            )
        )

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
        entrega=datos.entrega,
        codigo_corto=codigo_corto,
    )
    s.add(venta)
    await s.flush()

    for item_db in items_a_guardar:
        item_db.venta_id = venta.id
        s.add(item_db)

    # 3. Movimiento financiero según destino
    cobrado_confirmado = 0
    cobro_pendiente = 0

    if datos.destino_cobro == "adeudado":
        if datos.importe_cobrado and datos.importe_cobrado > 0:
            cobro_parcial = min(datos.importe_cobrado, importe_total)
            caja_efectivo = (
                await s.execute(
                    select(Caja).where(
                        Caja.campana_id == ctx.campana.id,
                        Caja.tipo == "efectivo",
                        Caja.titular_id == ctx.usuario.id,
                    )
                )
            ).scalar_one()
            mov = Movimiento(
                campana_id=ctx.campana.id,
                tipo="cobro",
                caja_destino=caja_efectivo.id,
                importe=cobro_parcial,
                estado="confirmado",
                venta_id=venta.id,
                comprobante_id=datos.comprobante_id,
                creado_por=ctx.usuario.id,
                motivo="Pago parcial de venta de productos",
            )
            s.add(mov)
            cobrado_confirmado = cobro_parcial
    elif datos.destino_cobro in ("efectivo", "billetera"):
        caja = (
            await s.execute(
                select(Caja).where(
                    Caja.campana_id == ctx.campana.id,
                    Caja.tipo == datos.destino_cobro,
                    Caja.titular_id == ctx.usuario.id,
                )
            )
        ).scalar_one()
        mov = Movimiento(
            campana_id=ctx.campana.id,
            tipo="cobro",
            caja_destino=caja.id,
            importe=importe_total,
            estado="confirmado",
            venta_id=venta.id,
            comprobante_id=datos.comprobante_id,
            creado_por=ctx.usuario.id,
            motivo=f"Cobro en {datos.destino_cobro} de productos",
        )
        s.add(mov)
        cobrado_confirmado = importe_total
    elif datos.destino_cobro == "cuenta_principal":
        caja_ppal = (
            await s.execute(
                select(Caja).where(Caja.campana_id == ctx.campana.id, Caja.tipo == "principal")
            )
        ).scalar_one()
        mov = Movimiento(
            campana_id=ctx.campana.id,
            tipo="cobro",
            caja_destino=caja_ppal.id,
            importe=importe_total,
            estado="pendiente",
            requiere_aprobacion_de=caja_ppal.titular_id,
            venta_id=venta.id,
            comprobante_id=datos.comprobante_id,
            creado_por=ctx.usuario.id,
            motivo="Cobro de productos en cuenta principal de la campaña",
        )
        s.add(mov)
        cobro_pendiente = importe_total

    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="venta_productos_registrada",
            objeto="venta",
            objeto_id=venta.id,
            detalle={
                "importe": importe_total,
                "items": [{"producto_id": str(it.producto_id), "cantidad": it.cantidad} for it in datos.items],
                "destino": datos.destino_cobro,
                "entrega": datos.entrega,
            },
        )
    )
    await s.commit()

    saldo_adeudado = importe_total - cobrado_confirmado - cobro_pendiente

    return VentaSalida(
        id=venta.id,
        campana_id=venta.campana_id,
        vendedor_id=venta.vendedor_id,
        vendedor_nombre=ctx.usuario.nombre,
        comprador=CompradorSalida(
            id=comprador.id,
            nombre=datos.comprador.nombre.strip(),
            telefono=datos.comprador.telefono.strip(),
        ),
        numeros=[],
        items_productos=items_salida,
        importe=venta.importe,
        estado=venta.estado,
        entrega=venta.entrega,
        codigo_corto=venta.codigo_corto,
        creada=venta.creada,
        total_cobrado=cobrado_confirmado,
        cobro_pendiente=cobro_pendiente,
        saldo_adeudado=saldo_adeudado,
    )


@ruteador.patch(
    "/campanas/{campana_id}/ventas/{venta_id}/entrega",
    response_model=VentaSalida,
)
async def actualizar_entrega(
    venta_id: uuid.UUID,
    datos: ActualizarEntrega,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> VentaSalida:
    resultado = await s.execute(
        select(Venta)
        .options(
            selectinload(Venta.items).selectinload(VentaItem.producto),
            selectinload(Venta.comprador),
            selectinload(Venta.vendedor),
        )
        .where(Venta.id == venta_id, Venta.campana_id == ctx.campana.id)
    )
    venta = resultado.scalar_one_or_none()
    if not venta:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "venta no encontrada")

    if venta.vendedor_id != ctx.usuario.id and not ctx.es_admin:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "solo el vendedor o el administrador pueden actualizar la entrega",
        )

    venta.entrega = datos.entrega

    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="entrega_actualizada",
            objeto="venta",
            objeto_id=venta.id,
            detalle={"entrega": datos.entrega},
        )
    )
    await s.commit()

    # Calcular saldos
    movs = (
        await s.execute(
            select(Movimiento).where(Movimiento.venta_id == venta.id, Movimiento.tipo == "cobro")
        )
    ).scalars().all()

    cobrado = sum(m.importe for m in movs if m.estado == "confirmado")
    pendiente = sum(m.importe for m in movs if m.estado == "pendiente")
    saldo_adeudado = max(0, venta.importe - cobrado - pendiente)

    nombre_comprador = cripto.descifrar_texto(venta.comprador.nombre_cifrado)
    tel_comprador = None
    if venta.vendedor_id == ctx.usuario.id:
        tel_comprador = cripto.descifrar_texto(venta.comprador.telefono_cifrado)

    items_salida = []
    numeros = []
    for it in venta.items:
        if it.numero is not None:
            numeros.append(it.numero)
        elif it.producto is not None:
            items_salida.append(
                ItemVentaProductoSalida(
                    producto_id=it.producto.id,
                    nombre=it.producto.nombre,
                    cantidad=it.cantidad,
                    precio_unitario=it.precio_unitario,
                    subtotal=it.precio_unitario * it.cantidad,
                )
            )

    return VentaSalida(
        id=venta.id,
        campana_id=venta.campana_id,
        vendedor_id=venta.vendedor_id,
        vendedor_nombre=venta.vendedor.nombre,
        comprador=CompradorSalida(
            id=venta.comprador.id,
            nombre=nombre_comprador,
            telefono=tel_comprador,
        ),
        numeros=numeros,
        items_productos=items_salida,
        importe=venta.importe,
        estado=venta.estado,
        entrega=venta.entrega,
        codigo_corto=venta.codigo_corto,
        creada=venta.creada,
        total_cobrado=cobrado,
        cobro_pendiente=pendiente,
        saldo_adeudado=saldo_adeudado,
    )
