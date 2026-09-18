"""Subida, verificación de duplicados y descarga de comprobantes."""

import base64
import hashlib
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from ..config import ajustes
from ..db import sesion
from ..esquemas import ComprobanteSalida, SubirComprobante
from ..modelos import Comprobante
from ..seguridad import Contexto, contexto_activo

ruteador = APIRouter(tags=["comprobantes"])

MIME_EXT = {
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "application/pdf": ".pdf",
}


@ruteador.post(
    "/campanas/{campana_id}/comprobantes",
    response_model=ComprobanteSalida,
    status_code=status.HTTP_201_CREATED,
)
async def subir_comprobante(
    datos: SubirComprobante,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> ComprobanteSalida:
    try:
        contenido = base64.b64decode(datos.archivo_base64)
    except Exception:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "archivo base64 inválido")

    tamano = len(contenido)
    if tamano == 0:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "el archivo está vacío")
    if tamano > 15 * 1024 * 1024:  # 15 MB tope
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "el archivo no puede superar los 15 MB")

    mime = datos.mime.lower().strip()
    if mime not in MIME_EXT:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, f"tipo de archivo no admitido: {mime}")

    sha256_hash = hashlib.sha256(contenido).hexdigest()
    nro_op = datos.nro_operacion.strip() if datos.nro_operacion else None

    # Detección de duplicados dentro de la misma campaña (§3.5)
    duplicado_aviso: str | None = None
    condiciones = [Comprobante.sha256 == sha256_hash]
    if nro_op:
        condiciones.append(Comprobante.nro_operacion == nro_op)

    duplicado = (
        await s.execute(
            select(Comprobante)
            .where(Comprobante.campana_id == ctx.campana.id, or_(*condiciones))
        )
    ).first()

    if duplicado:
        duplicado_aviso = "Posible comprobante duplicado: coincide el archivo o el número de operación."

    comprobante_id = uuid.uuid4()
    ext = MIME_EXT.get(mime, ".bin")
    nombre_archivo = f"{comprobante_id}{ext}"

    carpeta = Path(ajustes().carpeta_archivos) / str(ctx.campana.id)
    carpeta.mkdir(parents=True, exist_ok=True)
    ruta_guardado = carpeta / nombre_archivo

    # Guardar en disco
    ruta_guardado.write_bytes(contenido)

    comp = Comprobante(
        id=comprobante_id,
        campana_id=ctx.campana.id,
        ruta_archivo=str(ruta_guardado),
        sha256=sha256_hash,
        nro_operacion=nro_op,
        mime=mime,
        tamano=tamano,
        creado_por=ctx.usuario.id,
    )
    s.add(comp)
    await s.commit()
    await s.refresh(comp)

    return ComprobanteSalida(
        id=comp.id,
        sha256=comp.sha256,
        nro_operacion=comp.nro_operacion,
        mime=comp.mime,
        tamano=comp.tamano,
        creado=comp.creado,
        duplicado_aviso=duplicado_aviso,
    )


@ruteador.get("/campanas/{campana_id}/comprobantes/{comprobante_id}/archivo")
async def descargar_comprobante(
    comprobante_id: uuid.UUID,
    ctx: Contexto = Depends(contexto_activo),
    s: AsyncSession = Depends(sesion),
) -> Response:
    comp = (
        await s.execute(
            select(Comprobante).where(
                Comprobante.campana_id == ctx.campana.id,
                Comprobante.id == comprobante_id,
            )
        )
    ).scalar_one_or_none()

    if comp is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "el comprobante no existe")

    ruta = Path(comp.ruta_archivo)
    if not ruta.exists():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "el archivo físico no se encuentra")

    return Response(
        content=ruta.read_bytes(),
        media_type=comp.mime,
        headers={"Content-Disposition": f'inline; filename="{comprobante_id}{MIME_EXT.get(comp.mime, "")}"'},
    )
