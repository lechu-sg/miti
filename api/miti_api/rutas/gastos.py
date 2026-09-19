"""Rutas de Gastos de Campaña (§3.7 de DEFINICION.md).

Permite a cualquier integrante registrar gastos realizados para la campaña,
indicando si el dinero salió de su bolsillo o de una caja recaudada.
Todo gasto requiere aprobación cruzada:
- Si lo carga un integrante, lo aprueba el administrador.
- Si lo carga el administrador, lo aprueba cualquier otro integrante (nadie se auto-aprueba).
"""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from ..db import sesion
from ..esquemas import CrearGastoEntrada, GastoSalida
from ..modelos import Caja, Gasto, Historial, Movimiento, SyncLog, Usuario
from ..seguridad import Contexto, contexto_activo

ruteador = APIRouter(tags=["gastos"])


@ruteador.post(
    "/campanas/{campana_id}/gastos",
    response_model=GastoSalida,
    status_code=status.HTTP_201_CREATED,
)
async def registrar_gasto(
    datos: CrearGastoEntrada,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> GastoSalida:
    """Registra un nuevo gasto de campaña (§3.7)."""
    if ctx.campana.estado in ("liquidada", "archivada") or ctx.campana.bloqueada:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            "la campaña está liquidada o bloqueada para nuevos registros",
        )

    caja = None
    caja_id_final: uuid.UUID | None = None
    caja_nombre: str | None = None

    if datos.origen == "caja":
        if not datos.caja_id:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                "debés especificar de qué caja salió el dinero",
            )
        caja = await s.get(Caja, datos.caja_id)
        if caja is None or caja.campana_id != ctx.campana.id:
            raise HTTPException(
                status.HTTP_404_NOT_FOUND,
                "la caja indicada no pertenece a la campaña",
            )

        # Validación de custodia: solo podés gastar de tu caja o de la cuenta principal si sos titular o admin
        es_titular = caja.titular_id == ctx.usuario.id
        es_ppal = caja.tipo == "principal"
        if not (es_titular or (es_ppal and ctx.es_admin)):
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                "no podés registrar un gasto saliendo de una caja ajena",
            )

        # Verificar saldo confirmado disponible en la caja
        ingresos = (
            await s.execute(
                select(func.coalesce(func.sum(Movimiento.importe), 0)).where(
                    Movimiento.campana_id == ctx.campana.id,
                    Movimiento.caja_destino == caja.id,
                    Movimiento.estado == "confirmado",
                )
            )
        ).scalar() or 0

        egresos = (
            await s.execute(
                select(func.coalesce(func.sum(Movimiento.importe), 0)).where(
                    Movimiento.campana_id == ctx.campana.id,
                    Movimiento.caja_origen == caja.id,
                    Movimiento.estado == "confirmado",
                )
            )
        ).scalar() or 0

        saldo_disponible = int(ingresos - egresos)
        if saldo_disponible < datos.importe:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                f"saldo insuficiente en la caja (disponible: ${saldo_disponible // 100})",
            )

        caja_id_final = caja.id
        caja_nombre = f"{caja.tipo} ({caja.titular.nombre if caja.titular else 'campaña'})"

    # Regla de aprobación cruzada (§3.7):
    # Si lo carga el admin, requiere aprobación de cualquier otro integrante (requiere_aprobacion_de = None).
    # Si lo carga un integrante común, requiere aprobación del admin.
    es_admin_creador = ctx.es_admin or ctx.usuario.id == ctx.campana.creador_id
    requiere_de = None if es_admin_creador else ctx.campana.creador_id

    ahora = datetime.now(UTC)
    mov_id = uuid.uuid4()
    mov = Movimiento(
        id=mov_id,
        campana_id=ctx.campana.id,
        tipo="gasto",
        caja_origen=caja_id_final,
        caja_destino=None,
        importe=datos.importe,
        estado="pendiente",
        requiere_aprobacion_de=requiere_de,
        motivo=datos.descripcion.strip(),
        comprobante_id=datos.comprobante_id,
        creado_por=ctx.usuario.id,
        creado=ahora,
    )
    s.add(mov)

    gasto_id = uuid.uuid4()
    gasto = Gasto(
        id=gasto_id,
        campana_id=ctx.campana.id,
        movimiento_id=mov_id,
        descripcion=datos.descripcion.strip(),
        origen=datos.origen,
        caja_id=caja_id_final,
        creado=ahora,
    )
    s.add(gasto)

    s.add(
        Historial(
            campana_id=ctx.campana.id,
            actor_id=ctx.usuario.id,
            accion="gasto_registrado",
            objeto="gastos",
            objeto_id=gasto_id,
            detalle={
                "descripcion": datos.descripcion.strip(),
                "importe": datos.importe,
                "origen": datos.origen,
                "caja_id": str(caja_id_final) if caja_id_final else None,
            },
        )
    )

    s.add(
        SyncLog(
            campana_id=ctx.campana.id,
            tabla="gastos",
            fila_id=str(gasto_id),
            op="I",
            datos={
                "descripcion": datos.descripcion.strip(),
                "importe": datos.importe,
                "origen": datos.origen,
                "caja_id": str(caja_id_final) if caja_id_final else None,
                "movimiento_id": str(mov_id),
                "estado": "pendiente",
            },
        )
    )

    creador_nombre = ctx.usuario.nombre

    await s.commit()

    return GastoSalida(
        id=gasto_id,
        campana_id=ctx.campana.id,
        movimiento_id=mov_id,
        descripcion=datos.descripcion.strip(),
        importe=datos.importe,
        origen=datos.origen,
        caja_id=caja_id_final,
        caja_nombre=caja_nombre,
        estado="pendiente",
        creado_por=ctx.usuario.id,
        creado_por_nombre=creador_nombre,
        aprobado_por=None,
        aprobado_por_nombre=None,
        motivo_rechazo=None,
        comprobante_id=datos.comprobante_id,
        creado=ahora,
    )


@ruteador.get(
    "/campanas/{campana_id}/gastos",
    response_model=list[GastoSalida],
)
async def listar_gastos(
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> list[GastoSalida]:
    """Devuelve la lista de gastos registrados en la campaña."""
    gastos = (
        await s.execute(
            select(Gasto)
            .options(
                selectinload(Gasto.movimiento),
                selectinload(Gasto.caja),
            )
            .where(Gasto.campana_id == ctx.campana.id)
            .order_by(Gasto.creado.desc())
        )
    ).scalars().all()

    # Obtener usuarios participantes para resolver nombres
    usuarios_ids = set()
    for g in gastos:
        if g.movimiento:
            usuarios_ids.add(g.movimiento.creado_por)
            if g.movimiento.aprobado_por:
                usuarios_ids.add(g.movimiento.aprobado_por)

    nombres_usuarios: dict[uuid.UUID, str] = {}
    if usuarios_ids:
        us = (
            await s.execute(select(Usuario).where(Usuario.id.in_(usuarios_ids)))
        ).scalars().all()
        nombres_usuarios = {u.id: u.nombre for u in us}

    salida = []
    for g in gastos:
        mov = g.movimiento
        caja_nom = None
        if g.caja:
            caja_nom = f"{g.caja.tipo}"

        salida.append(
            GastoSalida(
                id=g.id,
                campana_id=g.campana_id,
                movimiento_id=g.movimiento_id,
                descripcion=g.descripcion,
                importe=mov.importe if mov else 0,
                origen=g.origen,
                caja_id=g.caja_id,
                caja_nombre=caja_nom,
                estado=mov.estado if mov else "pendiente",
                creado_por=mov.creado_por if mov else ctx.usuario.id,
                creado_por_nombre=nombres_usuarios.get(mov.creado_por, "Integrante") if mov else "",
                aprobado_por=mov.aprobado_por if mov else None,
                aprobado_por_nombre=nombres_usuarios.get(mov.aprobado_por) if mov and mov.aprobado_por else None,
                motivo_rechazo=mov.motivo if mov and mov.estado == "rechazado" else None,
                comprobante_id=mov.comprobante_id if mov else None,
                creado=g.creado,
            )
        )

    return salida
