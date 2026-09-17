"""API de Miti."""

import logging
import os

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from sqlalchemy import text

from .config import ajustes
from .db import Sesion
from .rutas import acceso, campanas

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

VERSION = "0.1.0"

app = FastAPI(
    title="Miti",
    version=VERSION,
    docs_url="/docs" if not ajustes().es_produccion else None,
    redoc_url=None,
    openapi_url="/openapi.json" if not ajustes().es_produccion else None,
)

app.include_router(acceso.ruteador)
app.include_router(campanas.ruteador)


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
