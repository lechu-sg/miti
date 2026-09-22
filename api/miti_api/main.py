"""API de Miti."""

import logging
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text

from .config import ajustes
from .db import Sesion
from .admin import rutas as admin_rutas
from .rutas import (
    acceso,
    campanas,
    comprobantes,
    dispositivos,
    exportar,
    gastos,
    liquidacion,
    pagos,
    productos,
    rifas,
    sorteos,
    sync,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

VERSION = "0.7.0"

app = FastAPI(
    title="Miti",
    version=VERSION,
    docs_url="/docs" if not ajustes().es_produccion else None,
    redoc_url=None,
)

if not ajustes().es_produccion:
    # Solo para poder probar la app en el navegador durante el desarrollo.
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
        allow_methods=["*"],
        allow_headers=["*"],
    )

app.include_router(acceso.ruteador)
app.include_router(campanas.ruteador)
app.include_router(rifas.ruteador)
app.include_router(productos.ruteador)
app.include_router(comprobantes.ruteador)
app.include_router(sync.ruteador)
app.include_router(liquidacion.ruteador)
app.include_router(gastos.ruteador)
app.include_router(sorteos.ruteador)
app.include_router(exportar.ruteador)
app.include_router(dispositivos.ruteador)
app.include_router(pagos.ruteador)
app.include_router(admin_rutas.ruteador)


@app.get("/salud", tags=["servicio"])
async def salud():
    try:
        async with Sesion() as s:
            await s.execute(text("select 1"))
    except Exception:
        return JSONResponse({"estado": "error", "db": "sin conexion"}, status_code=503)
    return {"estado": "ok", "db": "ok"}


@app.get("/version", tags=["servicio"])
async def version():
    # La app consulta esto al arrancar para saber si tiene que actualizarse.
    return {
        "api": VERSION,
        "entorno": os.environ.get("MITI_ENTORNO", "desarrollo"),
        "app_minima": None,
        "app_ultima": None,
    }
