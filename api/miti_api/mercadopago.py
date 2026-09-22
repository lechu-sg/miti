"""Cliente mínimo de MercadoPago Checkout Pro (§11).

Tres cosas y nada más:
- crear la preferencia de pago (lo que abre el navegador en el celular),
- traer un pago por su id, que es LA verdad: el webhook sólo avisa que algo
  cambió, nunca se le cree el contenido,
- buscar pagos por la referencia externa, para cuando el webhook no llegó.

Las credenciales viven en /srv/miti/secrets/mercadopago.env:
    MP_ACCESS_TOKEN=...      (TEST-... en prueba, APP_USR-... en producción)
    MP_WEBHOOK_SECRET=...    (la "clave secreta" de las notificaciones Webhooks)
"""

import hashlib
import hmac
import logging

import httpx

from .config import ajustes

API = "https://api.mercadopago.com"
registro = logging.getLogger("miti.mercadopago")


class SinCredenciales(Exception):
    """Todavía no se cargó el token de MercadoPago en el servidor."""


def _token() -> str:
    token = ajustes().mercadopago.get("MP_ACCESS_TOKEN", "")
    if not token:
        raise SinCredenciales("MercadoPago todavía no está configurado en el servidor")
    return token


def es_prueba() -> bool:
    return _token().startswith("TEST-")


async def _pedir(metodo: str, ruta: str, **kwargs) -> dict:
    async with httpx.AsyncClient(base_url=API, timeout=20) as cliente:
        r = await cliente.request(
            metodo, ruta, headers={"Authorization": f"Bearer {_token()}", **kwargs.pop("headers", {})},
            **kwargs,
        )
    if r.status_code >= 400:
        # El cuerpo de error de MP no trae datos sensibles: sirve para diagnosticar.
        registro.warning("MercadoPago %s %s → %s %s", metodo, ruta, r.status_code, r.text[:500])
        r.raise_for_status()
    return r.json()


async def crear_preferencia(
    *, compra_id: str, titulo: str, importe_centavos: int, email: str | None
) -> dict:
    base = ajustes().url_publica
    cuerpo = {
        "items": [
            {
                "id": compra_id,
                "title": titulo,
                "quantity": 1,
                "currency_id": "ARS",
                "unit_price": round(importe_centavos / 100, 2),
            }
        ],
        "external_reference": compra_id,
        "notification_url": f"{base}/pagos/mercadopago/webhook",
        "back_urls": {
            "success": f"{base}/pagos/vuelta?compra={compra_id}",
            "pending": f"{base}/pagos/vuelta?compra={compra_id}",
            "failure": f"{base}/pagos/vuelta?compra={compra_id}",
        },
        "auto_return": "approved",
        "statement_descriptor": "MITI",
        # Nada de cuotas con interés para un pago de este tamaño.
        "payment_methods": {"installments": 1},
    }
    if email:
        cuerpo["payer"] = {"email": email}
    return await _pedir(
        "POST", "/checkout/preferences", json=cuerpo, headers={"X-Idempotency-Key": compra_id}
    )


async def traer_pago(pago_id: str) -> dict:
    return await _pedir("GET", f"/v1/payments/{pago_id}")


async def buscar_pagos(referencia: str) -> list[dict]:
    datos = await _pedir(
        "GET", "/v1/payments/search",
        params={"external_reference": referencia, "sort": "date_created", "criteria": "desc"},
    )
    return datos.get("results", [])


def firma_valida(x_signature: str | None, x_request_id: str | None, data_id: str | None) -> bool:
    """Valida la cabecera x-signature de un webhook.

    Si no hay secreto configurado se acepta igual: el contenido del aviso nunca
    se usa, siempre se va a buscar el pago a la API con nuestro token.
    """
    secreto = ajustes().mercadopago.get("MP_WEBHOOK_SECRET", "")
    if not secreto:
        return True
    if not x_signature or not data_id:
        return False
    partes = dict(p.strip().split("=", 1) for p in x_signature.split(",") if "=" in p)
    ts, v1 = partes.get("ts"), partes.get("v1")
    if not ts or not v1:
        return False
    # Formato de MercadoPago: los campos que faltan se omiten del manifiesto.
    manifiesto = f"id:{data_id.lower()};"
    if x_request_id:
        manifiesto += f"request-id:{x_request_id};"
    manifiesto += f"ts:{ts};"
    calculada = hmac.new(secreto.encode(), manifiesto.encode(), hashlib.sha256).hexdigest()
    return hmac.compare_digest(calculada, v1)
