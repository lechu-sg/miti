#!/usr/bin/env python3
"""Avisa por mail cuando algo del servidor falla (por ahora, las copias de seguridad).

    avisar.py "asunto" "cuerpo"

Usa el SMTP de sole.ar configurado en /srv/miti/secrets/smtp.env. Si no está
configurado, o falla el envío, lo deja en /srv/miti/backups/logs/avisos.log y
termina sin error: un aviso que no sale no puede romper la copia.
"""

import datetime
import pathlib
import smtplib
import ssl
import sys
from email.message import EmailMessage

CONFIG = pathlib.Path("/srv/miti/secrets/smtp.env")
BITACORA = pathlib.Path("/srv/miti/backups/logs/avisos.log")


def anotar(texto: str) -> None:
    BITACORA.parent.mkdir(parents=True, exist_ok=True)
    marca = datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    with BITACORA.open("a", encoding="utf-8") as f:
        f.write(f"{marca} {texto}\n")


def main() -> int:
    asunto = sys.argv[1] if len(sys.argv) > 1 else "Aviso de Miti"
    cuerpo = sys.argv[2] if len(sys.argv) > 2 else sys.stdin.read()

    if not CONFIG.exists():
        anotar(f"SIN SMTP | {asunto} | {cuerpo}")
        return 0
    cfg = dict(
        l.strip().split("=", 1)
        for l in CONFIG.read_text(encoding="utf-8").splitlines()
        if "=" in l and not l.strip().startswith("#")
    )
    destino = cfg.get("AVISOS_PARA", "")
    if "@" not in destino:
        anotar(f"SIN DESTINATARIO (AVISOS_PARA) | {asunto} | {cuerpo}")
        return 0

    mensaje = EmailMessage()
    mensaje["From"] = cfg.get("SMTP_DESDE", cfg["SMTP_USUARIO"])
    mensaje["To"] = destino
    mensaje["Subject"] = f"[Miti] {asunto}"
    mensaje["Auto-Submitted"] = "auto-generated"
    mensaje.set_content(f"{cuerpo}\n\n-- \nServidor de Miti (miti.sole.ar)\n")

    puerto = int(cfg.get("SMTP_PUERTO", "465"))
    try:
        contexto = ssl.create_default_context()
        if puerto == 465:
            servidor = smtplib.SMTP_SSL(cfg["SMTP_HOST"], puerto, timeout=30, context=contexto)
        else:
            servidor = smtplib.SMTP(cfg["SMTP_HOST"], puerto, timeout=30)
            servidor.starttls(context=contexto)
        with servidor:
            servidor.login(cfg["SMTP_USUARIO"], cfg["SMTP_CLAVE"])
            servidor.send_message(mensaje)
        anotar(f"ENVIADO | {asunto}")
    except Exception as e:  # noqa: BLE001 - un aviso que falla no debe romper nada
        anotar(f"ERROR ({type(e).__name__}: {e}) | {asunto} | {cuerpo}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
