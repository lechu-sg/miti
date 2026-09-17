"""Esqueleto de la API de Miti (Fase 0): solo /salud y /version."""

import os
from pathlib import Path

import asyncpg
from fastapi import FastAPI
from fastapi.responses import JSONResponse

VERSION = "0.0.1"
ENTORNO = os.environ.get("MITI_ENTORNO", "desarrollo")

app = FastAPI(title="Miti", version=VERSION, docs_url=None, redoc_url=None, openapi_url=None)


def _clave_db() -> str:
    return Path(os.environ["MITI_DB_CLAVE_ARCHIVO"]).read_text().strip()


@app.get("/salud")
async def salud():
    try:
        con = await asyncpg.connect(
            host=os.environ["MITI_DB_HOST"],
            database=os.environ["MITI_DB_NOMBRE"],
            user=os.environ["MITI_DB_USUARIO"],
            password=_clave_db(),
            timeout=5,
        )
        try:
            await con.fetchval("select 1")
        finally:
            await con.close()
    except Exception:
        return JSONResponse({"estado": "error", "db": "sin conexion"}, status_code=503)
    return {"estado": "ok", "db": "ok"}


@app.get("/version")
async def version():
    # La app consulta esto al arrancar para saber si tiene que actualizarse.
    return {"api": VERSION, "entorno": ENTORNO, "app_minima": None, "app_ultima": None}
