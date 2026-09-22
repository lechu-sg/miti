"""Planes y mejoras pagadas con MercadoPago Checkout Pro (§11).

El circuito:
1. El administrador pide mejorar la campaña → se crea una compra `pendiente`
   y una preferencia en MercadoPago → la app abre el navegador en `url_pago`.
2. MercadoPago avisa por webhook. Del aviso sólo se toma el id del pago: el
   estado real se trae SIEMPRE de la API de MercadoPago con nuestro token.
3. Si el pago está aprobado y el importe y la moneda cuadran, la campaña pasa
   al plan nuevo.
4. Si el webhook no llegó, la app pregunta por la compra y el servidor busca
   el pago por la referencia externa (`reconciliar`).

Se cobra la diferencia entre planes: pasar de Campaña a Campaña Grande cuesta
lo que falta, no el precio entero.
"""

import logging
import uuid
from datetime import UTC, datetime

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request, status
from fastapi.responses import HTMLResponse
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import mercadopago as mp
from .. import planes
from ..db import sesion
from ..esquemas import (
    CompraSalida,
    EstadoPlanCampana,
    MejoraCreada,
    MejoraPosible,
    PedirMejora,
    PlanSalida,
    UsoPlan,
)
from ..modelos import Campana, CompraCampana, Historial, Integrante, Plan, Usuario, Venta
from ..seguridad import Contexto, contexto_activo, contexto_admin, usuario_actual

registro = logging.getLogger("miti.pagos")
ruteador = APIRouter(tags=["planes y pagos"])

# Estados de MercadoPago → estado de nuestra compra.
_ESTADOS_MP = {
    "approved": "aprobada",
    "rejected": "rechazada",
    "cancelled": "cancelada",
    "refunded": "reintegrada",
    "charged_back": "reintegrada",
}


def _plan_salida(p: Plan) -> PlanSalida:
    return PlanSalida.model_validate(p, from_attributes=True)


async def _planes(s: AsyncSession) -> list[Plan]:
    return list((await s.execute(select(Plan).order_by(Plan.orden))).scalars().all())


@ruteador.get("/planes", response_model=list[PlanSalida])
async def listar_planes(
    _: Usuario = Depends(usuario_actual), s: AsyncSession = Depends(sesion)
) -> list[PlanSalida]:
    return [_plan_salida(p) for p in await _planes(s)]


@ruteador.get("/campanas/{campana_id}/plan", response_model=EstadoPlanCampana)
async def estado_plan(
    ctx: Contexto = Depends(contexto_activo), s: AsyncSession = Depends(sesion)
) -> EstadoPlanCampana:
    campana = ctx.campana
    todos = await _planes(s)
    actual = next(p for p in todos if p.codigo == campana.plan)

    integrantes = (
        await s.execute(
            select(func.count()).select_from(Integrante).where(
                Integrante.campana_id == campana.id,
                Integrante.estado.in_(("activo", "invitado")),
            )
        )
    ).scalar_one()
    ventas = None
    if campana.tipo == "productos":
        ventas = (
            await s.execute(
                select(func.count()).select_from(Venta).where(
                    Venta.campana_id == campana.id, Venta.estado == "confirmada"
                )
            )
        ).scalar_one()

    pendiente = (
        await s.execute(
            select(CompraCampana.id)
            .where(CompraCampana.campana_id == campana.id, CompraCampana.estado == "pendiente")
            .order_by(CompraCampana.creada.desc())
            .limit(1)
        )
    ).scalar_one_or_none()

    try:
        mp._token()
        puede_pagar = True
    except mp.SinCredenciales:
        puede_pagar = False

    return EstadoPlanCampana(
        actual=_plan_salida(actual),
        uso=UsoPlan(
            integrantes=integrantes,
            numeros=planes.tamano_talonario(campana) if campana.tipo == "rifa" else None,
            ventas=ventas,
        ),
        mejoras=[
            MejoraPosible(plan=_plan_salida(p), a_pagar=max(p.precio - actual.precio, 0))
            for p in todos
            if p.orden > actual.orden
        ],
        puede_pagar=puede_pagar,
        compra_pendiente=pendiente,
    )


@ruteador.post(
    "/campanas/{campana_id}/mejora", response_model=MejoraCreada, status_code=status.HTTP_201_CREATED
)
async def pedir_mejora(
    datos: PedirMejora,
    ctx: Contexto = Depends(contexto_admin),
    s: AsyncSession = Depends(sesion),
) -> MejoraCreada:
    campana = ctx.campana
    if campana.estado in ("liquidada", "archivada"):
        raise HTTPException(status.HTTP_409_CONFLICT, "la campaña ya terminó: no hace falta mejorarla")

    actual = await s.get(Plan, campana.plan)
    destino = await s.get(Plan, datos.plan)
    if destino is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "ese plan no existe")
    if destino.orden <= actual.orden:
        raise HTTPException(status.HTTP_409_CONFLICT, f"la campaña ya tiene el plan {actual.nombre}")

    importe = destino.precio - actual.precio
    if importe <= 0:
        raise HTTPException(status.HTTP_409_CONFLICT, "ese cambio de plan no tiene costo")

    compra = CompraCampana(
        campana_id=campana.id,
        usuario_id=ctx.usuario.id,
        plan_desde=actual.codigo,
        plan_hasta=destino.codigo,
        importe=importe,
    )
    s.add(compra)
    await s.flush()

    try:
        preferencia = await mp.crear_preferencia(
            compra_id=str(compra.id),
            titulo=f"Miti · plan {destino.nombre} para «{campana.nombre[:60]}»",
            importe_centavos=importe,
            email=None,  # en prueba, un email real rompe el pago contra usuarios de prueba
        )
    except mp.SinCredenciales as e:
        await s.rollback()
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(e)) from None
    except httpx.HTTPError:
        await s.rollback()
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, "MercadoPago no respondió: probá de nuevo en un rato"
        ) from None

    prueba = mp.es_prueba()
    compra.preferencia_id = preferencia.get("id")
    url = preferencia.get("sandbox_init_point") if prueba else preferencia.get("init_point")
    s.add(
        Historial(
            campana_id=campana.id,
            actor_id=ctx.usuario.id,
            accion="mejora_pedida",
            objeto="compra",
            objeto_id=compra.id,
            detalle={"de": actual.codigo, "a": destino.codigo, "importe": importe},
        )
    )
    await s.commit()
    return MejoraCreada(compra_id=compra.id, url_pago=url, importe=importe, prueba=prueba)


async def aplicar_pago(s: AsyncSession, pago: dict) -> CompraCampana | None:
    """Actualiza la compra con lo que dice MercadoPago. Idempotente."""
    referencia = pago.get("external_reference")
    try:
        compra_id = uuid.UUID(str(referencia))
    except ValueError:
        registro.warning("pago %s con referencia ajena: %r", pago.get("id"), referencia)
        return None

    compra = (
        await s.execute(select(CompraCampana).where(CompraCampana.id == compra_id).with_for_update())
    ).scalar_one_or_none()
    if compra is None:
        registro.warning("pago %s para una compra que no existe: %s", pago.get("id"), compra_id)
        return None

    estado_mp = pago.get("status", "")
    nuevo = _ESTADOS_MP.get(estado_mp)
    compra.detalle_estado = f"{estado_mp}/{pago.get('status_detail', '')}"
    if nuevo is None:  # pending, in_process, authorized: seguimos esperando
        await s.commit()
        return compra

    if nuevo == "aprobada":
        cobrado = round(float(pago.get("transaction_amount") or 0) * 100)
        if pago.get("currency_id") != "ARS" or cobrado < compra.importe:
            # Nunca se habilita un plan por un pago que no cuadra.
            registro.error(
                "pago %s no cuadra con la compra %s: %s %s (esperaba %s ARS)",
                pago.get("id"), compra.id, cobrado, pago.get("currency_id"), compra.importe,
            )
            compra.detalle_estado = f"importe no coincide: {cobrado} {pago.get('currency_id')}"
            await s.commit()
            return compra

    anterior = compra.estado
    compra.estado = nuevo
    compra.pago_id = str(pago.get("id"))

    if nuevo == "aprobada" and anterior != "aprobada":
        compra.acreditada = datetime.now(UTC)
        campana = await s.get(Campana, compra.campana_id, with_for_update=True)
        destino = await s.get(Plan, compra.plan_hasta)
        vigente = await s.get(Plan, campana.plan)
        # Sólo sube: si mientras tanto quedó en un plan mayor, no se baja.
        if destino.orden > vigente.orden:
            campana.plan = destino.codigo
        s.add(
            Historial(
                campana_id=campana.id,
                actor_id=compra.usuario_id,
                accion="plan_mejorado",
                objeto="compra",
                objeto_id=compra.id,
                detalle={"de": compra.plan_desde, "a": compra.plan_hasta, "pago": compra.pago_id},
            )
        )
    elif nuevo == "reintegrada" and anterior == "aprobada":
        # El plan no se baja solo: queda en el registro para revisarlo desde el panel.
        registro.warning("compra %s reintegrada: revisar el plan de la campaña", compra.id)

    await s.commit()
    return compra


@ruteador.post("/pagos/mercadopago/webhook")
async def webhook_mercadopago(
    pedido: Request,
    data_id: str | None = Query(default=None, alias="data.id"),
    tipo: str | None = Query(default=None, alias="type"),
    x_signature: str | None = Header(default=None),
    x_request_id: str | None = Header(default=None),
    s: AsyncSession = Depends(sesion),
) -> dict:
    try:
        cuerpo = await pedido.json()
    except Exception:
        cuerpo = {}
    tipo = tipo or cuerpo.get("type") or cuerpo.get("topic")
    data_id = data_id or str((cuerpo.get("data") or {}).get("id") or "") or None

    if not mp.firma_valida(x_signature, x_request_id, data_id):
        registro.warning("webhook con firma inválida (data.id=%s)", data_id)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "firma inválida")

    if tipo != "payment" or not data_id:
        return {"ok": True, "ignorado": tipo}

    try:
        pago = await mp.traer_pago(data_id)
    except (httpx.HTTPError, mp.SinCredenciales):
        # 500 para que MercadoPago reintente más tarde.
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, "no se pudo consultar el pago") from None

    compra = await aplicar_pago(s, pago)
    return {"ok": True, "compra": str(compra.id) if compra else None}


@ruteador.get("/campanas/{campana_id}/compras/{compra_id}", response_model=CompraSalida)
async def ver_compra(
    compra_id: uuid.UUID,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> CompraCampana:
    compra = (
        await s.execute(
            select(CompraCampana).where(
                CompraCampana.id == compra_id, CompraCampana.campana_id == ctx.campana.id
            )
        )
    ).scalar_one_or_none()
    if compra is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "esa compra no existe")

    if compra.estado == "pendiente":
        # Por si el webhook se perdió: se pregunta directo a MercadoPago.
        try:
            for pago in await mp.buscar_pagos(str(compra.id)):
                compra = await aplicar_pago(s, pago) or compra
                if compra.estado != "pendiente":
                    break
        except (httpx.HTTPError, mp.SinCredenciales):
            pass
    return compra


@ruteador.get("/pagos/vuelta", response_class=HTMLResponse, include_in_schema=False)
async def vuelta_de_pago(compra: str | None = None) -> str:
    """Donde cae el navegador después de pagar: sólo pide volver a la app."""
    return """<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Miti</title>
<style>
 body{margin:0;min-height:100vh;display:grid;place-items:center;background:#FBF9F4;color:#1E2A3A;
      font:17px/1.5 system-ui,sans-serif;padding:24px;box-sizing:border-box}
 @media (prefers-color-scheme:dark){body{background:#141A23;color:#F3EDE0}}
 main{max-width:340px;text-align:center}
 h1{font-size:30px;letter-spacing:.04em;margin:0 0 8px}
</style></head><body><main>
<h1>MITI</h1>
<p><strong>Listo.</strong> Volvé a la app: en unos segundos vas a ver el plan nuevo en la campaña.</p>
<p>Si el pago quedó pendiente, se acredita solo cuando MercadoPago lo apruebe.</p>
</main></body></html>"""
