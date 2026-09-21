"""Limpieza por retención (§9 de DEFINICION.md).

Seis meses después de liquidada, una campaña se borra del servidor con todo lo
que cuelga de ella (ventas, números, movimientos, gastos, comprobantes) y se
borran también los archivos de los comprobantes, que no viven en la base.

Se corre desde el cron del VPS:
    docker compose run --rm --no-deps -T api python -m miti_api.limpieza
y con `--simulacion` solo informa qué borraría.
"""

import argparse
import asyncio
import logging
import shutil
from datetime import UTC, datetime, timedelta
from pathlib import Path

from sqlalchemy import delete, func, or_, select

from .config import ajustes
from .db import Sesion
from .modelos import Campana, CodigoAcceso, EnvioCorreo, Liquidacion

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
registro = logging.getLogger("miti.limpieza")

MESES_RETENCION = 6
DIAS_CODIGOS = 30          # códigos de acceso ya usados o vencidos
DIAS_ENVIOS = 90           # registro de envíos de correo (sirve para los topes por hora)


async def campanas_vencidas(s, corte: datetime) -> list[tuple]:
    """Campañas liquidadas o archivadas cuya fecha de cierre pasó el corte."""
    # El cierre es cuando se bloqueó la campaña; si faltara, vale la fecha de
    # la liquidación, y como último recurso la de creación.
    cierre = func.coalesce(Campana.bloqueada, Liquidacion.creada, Campana.creada)
    filas = (
        await s.execute(
            select(Campana.id, Campana.nombre, cierre.label("cierre"))
            .join(Liquidacion, Liquidacion.campana_id == Campana.id, isouter=True)
            .where(Campana.estado.in_(("liquidada", "archivada")), cierre < corte)
            .order_by("cierre")
        )
    ).all()
    return list(filas)


async def limpiar(simulacion: bool = False) -> int:
    ahora = datetime.now(UTC)
    corte = ahora - timedelta(days=MESES_RETENCION * 30)
    carpeta_base = Path(ajustes().carpeta_archivos)
    borradas = 0

    async with Sesion() as s:
        vencidas = await campanas_vencidas(s, corte)
        for campana_id, nombre, cierre in vencidas:
            registro.info(
                "campaña vencida: %s «%s» (cerrada el %s)", campana_id, nombre, cierre.date()
            )
            if simulacion:
                continue
            # Primero el disco: si falla, la fila queda y se reintenta mañana.
            carpeta = carpeta_base / str(campana_id)
            if carpeta.exists():
                shutil.rmtree(carpeta)
            # El resto cuelga de campanas con ON DELETE CASCADE.
            await s.execute(delete(Campana).where(Campana.id == campana_id))
            await s.commit()
            borradas += 1

        if not simulacion:
            # Rastros de acceso que ya no sirven para nada.
            res = await s.execute(
                delete(CodigoAcceso).where(
                    CodigoAcceso.creado < ahora - timedelta(days=DIAS_CODIGOS),
                    or_(CodigoAcceso.usado.is_not(None), CodigoAcceso.expira < ahora),
                )
            )
            codigos = res.rowcount or 0
            res = await s.execute(
                delete(EnvioCorreo).where(EnvioCorreo.cuando < ahora - timedelta(days=DIAS_ENVIOS))
            )
            envios = res.rowcount or 0
            await s.commit()
            registro.info("códigos borrados: %s · envíos de correo borrados: %s", codigos, envios)

        # Carpetas de comprobantes que quedaron sin campaña (por una limpieza a medias).
        if carpeta_base.exists() and not simulacion:
            vivas = {
                str(x) for x in (await s.execute(select(Campana.id))).scalars().all()
            }
            for carpeta in carpeta_base.iterdir():
                if carpeta.is_dir() and carpeta.name not in vivas:
                    registro.info("carpeta huérfana borrada: %s", carpeta.name)
                    shutil.rmtree(carpeta)

    registro.info(
        "%s%s campaña(s) %s por retención de %s meses",
        "SIMULACIÓN: " if simulacion else "",
        len(vencidas) if simulacion else borradas,
        "se borrarían" if simulacion else "borradas",
        MESES_RETENCION,
    )
    return borradas


def main() -> None:
    parser = argparse.ArgumentParser(description="Limpieza por retención de Miti")
    parser.add_argument("--simulacion", action="store_true", help="informa sin borrar nada")
    args = parser.parse_args()
    asyncio.run(limpiar(simulacion=args.simulacion))


if __name__ == "__main__":
    main()
