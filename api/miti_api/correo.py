"""Envío de mails por el SMTP de sole.ar.

Los mails SALEN por el servidor del hosting, no por el VPS: así valen el SPF y la
firma DKIM del dominio y no caen en spam.

Límites del hosting compartido (y el freno que nos ponemos):
- 200 mails por hora por dominio      → nosotros cortamos en 150
- 120 destinatarios distintos por hora → cortamos en 100
- 20 destinatarios por envío           → mandamos de a uno
"""

import logging
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from email.message import EmailMessage
from email.utils import formatdate, make_msgid, parseaddr
from pathlib import Path

import aiosmtplib
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from . import cripto
from .config import ajustes
from .modelos import EnvioCorreo

registro = logging.getLogger("miti.correo")

TOPE_POR_HORA = 150
TOPE_DESTINATARIOS = 100


class CorreoLleno(Exception):
    """Se llegó al tope de envíos de la hora."""


@dataclass(frozen=True)
class Config:
    host: str
    puerto: int
    usuario: str
    clave: str
    desde: str
    avisos_para: str | None


def config() -> Config | None:
    ruta = ajustes().smtp_archivo
    if not ruta or not Path(ruta).exists():
        return None
    datos: dict[str, str] = {}
    for linea in Path(ruta).read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if linea and not linea.startswith("#") and "=" in linea:
            nombre, valor = linea.split("=", 1)
            datos[nombre.strip()] = valor.strip()
    if not {"SMTP_HOST", "SMTP_USUARIO", "SMTP_CLAVE"} <= datos.keys():
        return None
    return Config(
        host=datos["SMTP_HOST"],
        puerto=int(datos.get("SMTP_PUERTO", "465")),
        usuario=datos["SMTP_USUARIO"],
        clave=datos["SMTP_CLAVE"],
        desde=datos.get("SMTP_DESDE", datos["SMTP_USUARIO"]),
        avisos_para=datos.get("AVISOS_PARA"),
    )


async def _hay_lugar(s: AsyncSession, destino_huella: bytes) -> None:
    desde = datetime.now(UTC) - timedelta(hours=1)
    enviados = (
        await s.execute(
            select(func.count())
            .select_from(EnvioCorreo)
            .where(EnvioCorreo.cuando >= desde, EnvioCorreo.estado == "enviado")
        )
    ).scalar_one()
    if enviados >= TOPE_POR_HORA:
        raise CorreoLleno("se llegó al tope de mails por hora")

    distintos = (
        await s.execute(
            select(func.count(func.distinct(EnvioCorreo.destino_huella))).where(
                EnvioCorreo.cuando >= desde,
                EnvioCorreo.estado == "enviado",
                EnvioCorreo.destino_huella != destino_huella,
            )
        )
    ).scalar_one()
    if distintos >= TOPE_DESTINATARIOS:
        raise CorreoLleno("se llegó al tope de destinatarios por hora")


async def enviar(
    s: AsyncSession, destino: str, asunto: str, texto: str, html: str | None = None, motivo: str = ""
) -> bool:
    """Manda un mail y lo deja registrado. Devuelve si salió."""
    cfg = config()
    huella = cripto.huella(destino)

    sin_envio = [d.strip().lower() for d in ajustes().dominios_sin_envio.split(",") if d.strip()]
    if destino.rsplit("@", 1)[-1].lower() in sin_envio:
        registro.info("dominio de prueba: no se manda «%s»", asunto)
        s.add(EnvioCorreo(destino_huella=huella, motivo=motivo, estado="salteado", detalle="dominio de prueba"))
        return True

    if cfg is None:
        registro.warning("no hay SMTP configurado: no se mandó «%s»", asunto)
        s.add(EnvioCorreo(destino_huella=huella, motivo=motivo, estado="sin_smtp", detalle="falta la configuración"))
        return False

    await _hay_lugar(s, huella)

    mensaje = EmailMessage()
    mensaje["From"] = cfg.desde
    mensaje["To"] = destino
    mensaje["Subject"] = asunto
    # Sin Date ni Message-Id los filtros de spam descuentan puntos (medido: -1,5).
    mensaje["Date"] = formatdate(localtime=False)
    mensaje["Message-Id"] = make_msgid(domain=parseaddr(cfg.desde)[1].split("@")[-1])
    mensaje["Auto-Submitted"] = "auto-generated"
    mensaje.set_content(texto)
    if html:
        mensaje.add_alternative(html, subtype="html")

    try:
        await aiosmtplib.send(
            mensaje,
            hostname=cfg.host,
            port=cfg.puerto,
            username=cfg.usuario,
            password=cfg.clave,
            use_tls=cfg.puerto == 465,
            start_tls=cfg.puerto != 465,
            timeout=25,
        )
    except Exception as e:  # el hosting puede estar caído o rechazar
        registro.error("no se pudo mandar «%s»: %s", asunto, e)
        s.add(EnvioCorreo(destino_huella=huella, motivo=motivo, estado="error", detalle=str(e)[:400]))
        return False

    s.add(EnvioCorreo(destino_huella=huella, motivo=motivo, estado="enviado"))
    return True


def armar_codigo(codigo: str, minutos: int) -> tuple[str, str, str]:
    """Asunto, texto y html del mail con el código de acceso."""
    asunto = f"{codigo} es tu código para entrar a Miti"
    texto = (
        f"Tu código para entrar a Miti es {codigo}\n\n"
        f"Vence en {minutos} minutos y se usa una sola vez.\n"
        "Si no lo pediste vos, ignorá este mensaje: sin el código nadie puede entrar.\n"
    )
    html = f"""<!doctype html>
<html lang="es"><body style="margin:0;background:#FBF9F4;font-family:Helvetica,Arial,sans-serif;color:#1E2A3A">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:32px 16px">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
             style="max-width:420px;background:#FFFFFF;border:2px dashed #1E2A3A;border-radius:6px;padding:28px">
        <tr><td style="font-size:12px;letter-spacing:.14em;text-transform:uppercase;color:#5F5A4E">Miti</td></tr>
        <tr><td style="font-size:26px;font-weight:700;padding-top:6px">Tu código para entrar</td></tr>
        <tr><td align="center" style="padding:24px 0">
          <div style="font-size:44px;font-weight:700;letter-spacing:.18em">{codigo}</div>
        </td></tr>
        <tr><td style="font-size:14px;color:#5F5A4E">
          Vence en {minutos} minutos y se usa una sola vez.<br>
          Si no lo pediste vos, ignorá este mensaje: sin el código nadie puede entrar.
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>"""
    return asunto, texto, html
