"""Panel de administración en /admin (§6 y §9 de DEFINICION.md).

Sólo para el dueño de Miti. Servido por la misma API, sin JavaScript:
formularios comunes y páginas generadas en el servidor.

Entrada en dos pasos, siempre los dos:
1. código de 6 dígitos por email (el mismo circuito que la app),
2. código TOTP de una app autenticadora. La primera vez se enrola.

La sesión es una cookie firmada, HttpOnly, Secure, SameSite=Strict, que vence
a las 2 horas. Cada formulario lleva además un token contra CSRF. Todo ingreso,
intento fallido y acción queda en admin_accesos.

Para dar de alta a un administrador (desde el VPS):
    docker compose run --rm --no-deps -T api python -m miti_api.admin.alta email@dominio
"""

import base64
import hashlib
import hmac
import secrets
import shutil
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path
from urllib.parse import quote

import jwt
import pyotp
from fastapi import APIRouter, Depends, Form, HTTPException, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates
from sqlalchemy import Date, cast, func, or_, select, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from .. import cripto, ia_local
from ..config import ajustes
from ..db import sesion
from ..esquemas import PedirCodigo
from ..modelos import (
    AccesoAdmin,
    Administrador,
    Campana,
    CodigoAcceso,
    CompraCampana,
    EnvioCorreo,
    Integrante,
    Plan,
    Usuario,
    Venta,
)
from ..modelos import Sesion as SesionUsuario
from ..rutas import acceso
from ..seguridad import _clave_jwt

ruteador = APIRouter(prefix="/admin", include_in_schema=False)
plantillas = Jinja2Templates(directory=str(Path(__file__).parent / "plantillas"))

COOKIE = "miti_admin"
COOKIE_PREVIA = "miti_admin_previa"
HORAS_SESION = 2
MINUTOS_PREVIA = 10
FALLOS_TOTP_MAX = 5
CARPETA_ESTADO = Path("/srv/miti/backups/estado")


def _plata(centavos: int | None) -> str:
    if centavos is None:
        return "—"
    pesos = centavos / 100
    return "$ " + f"{pesos:,.0f}".replace(",", ".")


plantillas.env.filters["plata"] = _plata
plantillas.env.filters["fecha"] = (
    lambda d: d.astimezone(UTC).strftime("%d/%m/%Y %H:%M UTC") if d else "—"
)


# ---------------------------------------------------------------- sesión


def _firmar(cuerpo: dict, minutos: int, aud: str) -> str:
    ahora = datetime.now(UTC)
    return jwt.encode(
        {**cuerpo, "aud": aud, "iat": ahora, "exp": ahora + timedelta(minutes=minutos)},
        _clave_jwt(),
        algorithm="HS256",
    )


def _leer(valor: str | None, aud: str) -> dict | None:
    if not valor:
        return None
    try:
        return jwt.decode(valor, _clave_jwt(), algorithms=["HS256"], audience=aud)
    except jwt.PyJWTError:
        return None


def _csrf(pedido: Request) -> str:
    base = pedido.cookies.get(COOKIE, "")
    return hmac.new(_clave_jwt(), f"csrf:{base}".encode(), hashlib.sha256).hexdigest()[:40]


def _cookie(respuesta: Response, nombre: str, valor: str, minutos: int) -> None:
    respuesta.set_cookie(
        nombre, valor, max_age=minutos * 60, httponly=True, secure=True,
        samesite="strict", path="/admin",
    )


def _ip(pedido: Request) -> str | None:
    return pedido.client.host if pedido.client else None


async def _auditar(
    s: AsyncSession, pedido: Request, accion: str, usuario_id: uuid.UUID | None = None, **detalle
) -> None:
    s.add(AccesoAdmin(usuario_id=usuario_id, accion=accion, detalle=detalle, ip=_ip(pedido)))
    await s.commit()


class Sesion:
    def __init__(self, usuario: Usuario, csrf: str):
        self.usuario = usuario
        self.csrf = csrf


async def admin_actual(pedido: Request, s: AsyncSession = Depends(sesion)) -> Sesion:
    datos = _leer(pedido.cookies.get(COOKIE), "admin")
    if datos is None:
        raise HTTPException(status.HTTP_303_SEE_OTHER, headers={"Location": "/admin/entrar"})
    usuario = await s.get(Usuario, uuid.UUID(datos["sub"]))
    es_admin = usuario is not None and await s.get(Administrador, usuario.id) is not None
    if not es_admin or usuario.baja or usuario.bloqueado:
        raise HTTPException(status.HTTP_303_SEE_OTHER, headers={"Location": "/admin/entrar"})
    return Sesion(usuario, _csrf(pedido))


async def formulario_valido(
    pedido: Request, csrf: str = Form(...), adm: Sesion = Depends(admin_actual)
) -> Sesion:
    if not hmac.compare_digest(csrf, adm.csrf):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "el formulario venció: volvé a cargar la página")
    return adm


def _pagina(pedido: Request, nombre: str, **contexto) -> HTMLResponse:
    r = plantillas.TemplateResponse(pedido, nombre, contexto)
    # Nada de scripts ni de marcos: el panel es HTML y formularios.
    r.headers["Content-Security-Policy"] = (
        "default-src 'self'; script-src 'none'; style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data:; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
    )
    r.headers["Cache-Control"] = "no-store"
    return r


def _volver(ruta: str) -> RedirectResponse:
    return RedirectResponse(ruta, status_code=status.HTTP_303_SEE_OTHER)


# ---------------------------------------------------------------- entrada


async def _admin_por_email(s: AsyncSession, email: str) -> Usuario | None:
    usuario = (
        await s.execute(
            select(Usuario).where(Usuario.email_huella == cripto.huella(cripto.normalizar_email(email)))
        )
    ).scalar_one_or_none()
    if usuario is None or usuario.baja or usuario.bloqueado:
        return None
    return usuario if await s.get(Administrador, usuario.id) else None


@ruteador.get("/entrar", response_class=HTMLResponse)
async def entrar(pedido: Request) -> HTMLResponse:
    return _pagina(pedido, "entrar.html", paso="email")


@ruteador.post("/entrar", response_class=HTMLResponse)
async def pedir_codigo(
    pedido: Request, email: str = Form(...), s: AsyncSession = Depends(sesion)
) -> HTMLResponse:
    email = email.strip()
    usuario = await _admin_por_email(s, email)
    if usuario is not None:
        try:
            await acceso.pedir_codigo(PedirCodigo(email=email), s)
        except HTTPException as e:
            return _pagina(pedido, "entrar.html", paso="email", error=str(e.detail).capitalize())
    await _auditar(s, pedido, "codigo_pedido", usuario.id if usuario else None, conocido=usuario is not None)
    # Mismo mensaje exista o no: el panel no confirma quién es administrador.
    return _pagina(pedido, "entrar.html", paso="codigo", email=email)


async def _codigo_correcto(s: AsyncSession, email: str, codigo: str) -> bool:
    huella = cripto.huella(cripto.normalizar_email(email))
    fila = (
        await s.execute(
            select(CodigoAcceso)
            .where(CodigoAcceso.email_huella == huella, CodigoAcceso.usado.is_(None))
            .order_by(CodigoAcceso.creado.desc())
            .limit(1)
            .with_for_update()
        )
    ).scalar_one_or_none()
    if fila is None or fila.expira < datetime.now(UTC) or fila.intentos >= ajustes().intentos_codigo:
        return False
    if not secrets.compare_digest(fila.codigo_hash, cripto.hash_simple(codigo.strip())):
        fila.intentos += 1
        await s.commit()
        return False
    fila.usado = datetime.now(UTC)
    await s.commit()
    return True


@ruteador.post("/codigo", response_class=HTMLResponse)
async def verificar_codigo(
    pedido: Request,
    email: str = Form(...),
    codigo: str = Form(...),
    s: AsyncSession = Depends(sesion),
) -> Response:
    usuario = await _admin_por_email(s, email)
    if usuario is None or not await _codigo_correcto(s, email, codigo):
        await _auditar(s, pedido, "codigo_fallido", usuario.id if usuario else None)
        return _pagina(pedido, "entrar.html", paso="codigo", email=email,
                       error="El código no es válido o venció.")

    admin = await s.get(Administrador, usuario.id)
    await _auditar(s, pedido, "codigo_ok", usuario.id)
    if admin.totp_cifrado is None:
        secreto = pyotp.random_base32()
        previa = _firmar(
            {"sub": str(usuario.id), "enrolar": base64.b64encode(cripto.cifrar(secreto)).decode()},
            MINUTOS_PREVIA, "admin-previa",
        )
        r = _volver("/admin/enrolar")
    else:
        previa = _firmar({"sub": str(usuario.id)}, MINUTOS_PREVIA, "admin-previa")
        r = _volver("/admin/totp")
    _cookie(r, COOKIE_PREVIA, previa, MINUTOS_PREVIA)
    return r


def _previa(pedido: Request) -> dict:
    datos = _leer(pedido.cookies.get(COOKIE_PREVIA), "admin-previa")
    if datos is None:
        raise HTTPException(status.HTTP_303_SEE_OTHER, headers={"Location": "/admin/entrar"})
    return datos


async def _demasiados_fallos(s: AsyncSession, usuario_id: uuid.UUID) -> bool:
    fallos = (
        await s.execute(
            select(func.count()).select_from(AccesoAdmin).where(
                AccesoAdmin.usuario_id == usuario_id,
                AccesoAdmin.accion == "totp_fallido",
                AccesoAdmin.cuando > datetime.now(UTC) - timedelta(minutes=15),
            )
        )
    ).scalar_one()
    return fallos >= FALLOS_TOTP_MAX


def _abrir_sesion(usuario_id: uuid.UUID) -> RedirectResponse:
    r = _volver("/admin")
    _cookie(r, COOKIE, _firmar({"sub": str(usuario_id)}, HORAS_SESION * 60, "admin"), HORAS_SESION * 60)
    r.delete_cookie(COOKIE_PREVIA, path="/admin")
    return r


def _qr_data_uri(uri: str) -> str:
    import reportlab.graphics.barcode.qr as qr
    from reportlab.graphics.shapes import Drawing
    import reportlab.graphics.renderSVG as renderSVG

    w = qr.QrCodeWidget(uri)
    w.barWidth = 180
    w.barHeight = 180
    d = Drawing(180, 180)
    d.add(w)
    svg = renderSVG.drawToString(d)
    b64 = base64.b64encode(svg.encode("utf-8")).decode("ascii")
    return f"data:image/svg+xml;base64,{b64}"


@ruteador.get("/enrolar", response_class=HTMLResponse)
async def ver_enrolar(pedido: Request) -> HTMLResponse:
    datos = _previa(pedido)
    if "enrolar" not in datos:
        return _volver("/admin/totp")
    secreto = cripto.descifrar(base64.b64decode(datos["enrolar"]))
    uri = pyotp.TOTP(secreto).provisioning_uri(name="administrador", issuer_name="Miti")
    agrupado = " ".join(secreto[i:i + 4] for i in range(0, len(secreto), 4))
    qr_uri = _qr_data_uri(uri)
    return _pagina(
        pedido, "entrar.html", paso="enrolar", secreto=agrupado, uri=uri, qr_data_uri=qr_uri
    )


@ruteador.post("/enrolar", response_class=HTMLResponse)
async def confirmar_enrolar(
    pedido: Request, totp: str = Form(...), s: AsyncSession = Depends(sesion)
) -> Response:
    datos = _previa(pedido)
    if "enrolar" not in datos:
        return _volver("/admin/totp")
    usuario_id = uuid.UUID(datos["sub"])
    secreto = cripto.descifrar(base64.b64decode(datos["enrolar"]))
    if not pyotp.TOTP(secreto).verify(totp.strip().replace(" ", ""), valid_window=1):
        await _auditar(s, pedido, "totp_fallido", usuario_id, enrolando=True)
        uri = pyotp.TOTP(secreto).provisioning_uri(name="administrador", issuer_name="Miti")
        agrupado = " ".join(secreto[i:i + 4] for i in range(0, len(secreto), 4))
        qr_uri = _qr_data_uri(uri)
        return _pagina(
            pedido,
            "entrar.html",
            paso="enrolar",
            secreto=agrupado,
            uri=uri,
            qr_data_uri=qr_uri,
            error="Ese código no coincide. Revisá la hora del celular y probá de nuevo.",
        )
    admin = await s.get(Administrador, usuario_id)
    admin.totp_cifrado = cripto.cifrar(secreto)
    await s.commit()
    await _auditar(s, pedido, "totp_enrolado", usuario_id)
    return _abrir_sesion(usuario_id)


@ruteador.get("/totp", response_class=HTMLResponse)
async def ver_totp(pedido: Request) -> HTMLResponse:
    _previa(pedido)
    return _pagina(pedido, "entrar.html", paso="totp")


@ruteador.post("/totp", response_class=HTMLResponse)
async def verificar_totp(
    pedido: Request, totp: str = Form(...), s: AsyncSession = Depends(sesion)
) -> Response:
    datos = _previa(pedido)
    usuario_id = uuid.UUID(datos["sub"])
    if await _demasiados_fallos(s, usuario_id):
        return _pagina(pedido, "entrar.html", paso="totp",
                       error="Demasiados intentos. Esperá 15 minutos.")
    admin = await s.get(Administrador, usuario_id)
    secreto = cripto.descifrar(admin.totp_cifrado) if admin and admin.totp_cifrado else None
    if not secreto or not pyotp.TOTP(secreto).verify(totp.strip().replace(" ", ""), valid_window=1):
        await _auditar(s, pedido, "totp_fallido", usuario_id)
        return _pagina(pedido, "entrar.html", paso="totp", error="Código incorrecto.")
    await _auditar(s, pedido, "ingreso", usuario_id)
    return _abrir_sesion(usuario_id)


@ruteador.post("/salir")
async def salir(
    pedido: Request, adm: Sesion = Depends(formulario_valido), s: AsyncSession = Depends(sesion)
) -> Response:
    await _auditar(s, pedido, "salida", adm.usuario.id)
    r = _volver("/admin/entrar")
    r.delete_cookie(COOKIE, path="/admin")
    return r


# ---------------------------------------------------------------- métricas


@ruteador.get("", response_class=HTMLResponse)
async def metricas(
    pedido: Request, adm: Sesion = Depends(admin_actual), s: AsyncSession = Depends(sesion)
) -> HTMLResponse:
    ahora = datetime.now(UTC)
    hace = lambda dias: ahora - timedelta(days=dias)  # noqa: E731

    async def contar(consulta):
        return (await s.execute(consulta)).scalar_one()

    vivos = Usuario.baja.is_(None)
    tarjetas = {
        "usuarios": await contar(select(func.count()).select_from(Usuario).where(vivos)),
        "usuarios_7": await contar(select(func.count()).select_from(Usuario).where(vivos, Usuario.creado > hace(7))),
        "activos_30": await contar(select(func.count()).select_from(Usuario).where(vivos, Usuario.ultimo_acceso > hace(30))),
        "en_curso": await contar(
            select(func.count()).select_from(Campana).where(Campana.estado.in_(("activa", "cerrada", "sorteada")))
        ),
        "ventas_30": await contar(
            select(func.count()).select_from(Venta).where(Venta.estado == "confirmada", Venta.creada > hace(30))
        ),
        "recaudado_30": await contar(
            select(func.coalesce(func.sum(Venta.importe), 0)).where(
                Venta.estado == "confirmada", Venta.creada > hace(30)
            )
        ),
        "cobrado_planes": await contar(
            select(func.coalesce(func.sum(CompraCampana.importe), 0)).where(CompraCampana.estado == "aprobada")
        ),
        "cobrado_planes_30": await contar(
            select(func.coalesce(func.sum(CompraCampana.importe), 0)).where(
                CompraCampana.estado == "aprobada", CompraCampana.acreditada > hace(30)
            )
        ),
    }

    por_estado = (
        await s.execute(select(Campana.estado, func.count()).group_by(Campana.estado).order_by(Campana.estado))
    ).all()
    por_plan = (
        await s.execute(
            select(Campana.plan, func.count()).where(Campana.estado.in_(("activa", "cerrada", "sorteada")))
            .group_by(Campana.plan)
        )
    ).all()

    # Últimos 14 días, día por día (en UTC).
    desde = (ahora - timedelta(days=13)).date()
    dias = [desde + timedelta(days=i) for i in range(14)]

    async def por_dia(columna, *filtros, suma=None):
        dia = cast(columna, Date)
        filas = (
            await s.execute(
                select(dia, func.coalesce(func.sum(suma), 0) if suma is not None else func.count())
                .where(dia >= desde, *filtros)
                .group_by(dia)
            )
        ).all()
        return dict(filas)

    altas = await por_dia(Usuario.creado)
    campanas = await por_dia(Campana.creada)
    ventas = await por_dia(Venta.creada, Venta.estado == "confirmada")
    cobros = await por_dia(CompraCampana.acreditada, CompraCampana.estado == "aprobada", suma=CompraCampana.importe)
    serie = [
        {"dia": d, "altas": altas.get(d, 0), "campanas": campanas.get(d, 0),
         "ventas": ventas.get(d, 0), "cobros": cobros.get(d, 0)}
        for d in reversed(dias)
    ]

    return _pagina(pedido, "metricas.html", adm=adm, seccion="metricas", t=tarjetas,
                   por_estado=por_estado, por_plan=por_plan, serie=serie)


# ---------------------------------------------------------------- usuarios


@ruteador.get("/usuarios", response_class=HTMLResponse)
async def usuarios(
    pedido: Request, q: str = "", adm: Sesion = Depends(admin_actual), s: AsyncSession = Depends(sesion)
) -> HTMLResponse:
    consulta = select(Usuario).order_by(Usuario.creado.desc()).limit(50)
    q = q.strip()
    if q:
        if "@" in q:
            # El email está cifrado: sólo se puede buscar por la dirección exacta.
            consulta = consulta.where(Usuario.email_huella == cripto.huella(cripto.normalizar_email(q)))
        else:
            consulta = consulta.where(Usuario.nombre.ilike(f"%{q}%"))
    filas = (await s.execute(consulta)).scalars().all()
    lista = []
    for u in filas:
        campanas = (
            await s.execute(
                select(func.count()).select_from(Integrante).where(
                    Integrante.usuario_id == u.id, Integrante.estado == "activo"
                )
            )
        ).scalar_one()
        lista.append({"u": u, "email": cripto.descifrar(u.email_cifrado), "campanas": campanas})
    return _pagina(pedido, "usuarios.html", adm=adm, seccion="usuarios", q=q, lista=lista)


@ruteador.post("/usuarios/{usuario_id}/bloqueo")
async def bloquear_usuario(
    usuario_id: uuid.UUID,
    pedido: Request,
    accion: str = Form(...),
    motivo: str = Form(""),
    adm: Sesion = Depends(formulario_valido),
    s: AsyncSession = Depends(sesion),
) -> Response:
    u = await s.get(Usuario, usuario_id)
    if u is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    if u.id == adm.usuario.id:
        raise HTTPException(status.HTTP_409_CONFLICT, "no te podés bloquear a vos mismo")
    if accion == "bloquear":
        if not motivo.strip():
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "hace falta un motivo")
        u.bloqueado = datetime.now(UTC)
        u.motivo_bloqueo = motivo.strip()
        # Afuera ya: se revocan sus sesiones.
        await s.execute(
            update(SesionUsuario)
            .where(SesionUsuario.usuario_id == u.id, SesionUsuario.revocada.is_(None))
            .values(revocada=datetime.now(UTC))
        )
    else:
        u.bloqueado = None
        u.motivo_bloqueo = None
    await s.commit()
    await _auditar(s, pedido, f"usuario_{accion}", adm.usuario.id, usuario=str(u.id), motivo=motivo.strip())
    return _volver(f"/admin/usuarios?q={quote(u.nombre)}")


# ---------------------------------------------------------------- campañas


@ruteador.get("/campanas", response_class=HTMLResponse)
async def campanas(
    pedido: Request, q: str = "", estado: str = "",
    adm: Sesion = Depends(admin_actual), s: AsyncSession = Depends(sesion),
) -> HTMLResponse:
    consulta = select(Campana).order_by(Campana.creada.desc()).limit(50)
    if q.strip():
        consulta = consulta.where(Campana.nombre.ilike(f"%{q.strip()}%"))
    if estado:
        consulta = consulta.where(Campana.estado == estado)
    lista = (await s.execute(consulta)).scalars().all()
    return _pagina(pedido, "campanas.html", adm=adm, seccion="campanas", q=q, estado=estado, lista=lista)


@ruteador.get("/campanas/{campana_id}", response_class=HTMLResponse)
async def campana(
    campana_id: uuid.UUID, pedido: Request,
    adm: Sesion = Depends(admin_actual), s: AsyncSession = Depends(sesion),
) -> HTMLResponse:
    c = await s.get(Campana, campana_id)
    if c is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    creador = await s.get(Usuario, c.creador_id)
    integrantes = [i for i in c.integrantes if i.estado in ("activo", "invitado")]
    ventas = (
        await s.execute(
            select(func.count(), func.coalesce(func.sum(Venta.importe), 0)).where(
                Venta.campana_id == c.id, Venta.estado == "confirmada"
            )
        )
    ).one()
    compras = (
        await s.execute(
            select(CompraCampana).where(CompraCampana.campana_id == c.id).order_by(CompraCampana.creada.desc())
        )
    ).scalars().all()
    planes = (await s.execute(select(Plan).order_by(Plan.orden))).scalars().all()
    nombres = dict(
        (await s.execute(
            select(Usuario.id, Usuario.nombre).where(Usuario.id.in_([i.usuario_id for i in integrantes]))
        )).all()
    )
    return _pagina(pedido, "campana.html", adm=adm, seccion="campanas", c=c, creador=creador,
                   integrantes=integrantes, nombres=nombres, ventas=ventas, compras=compras, planes=planes)


@ruteador.post("/campanas/{campana_id}/suspension")
async def suspender_campana(
    campana_id: uuid.UUID, pedido: Request,
    accion: str = Form(...), motivo: str = Form(""),
    adm: Sesion = Depends(formulario_valido), s: AsyncSession = Depends(sesion),
) -> Response:
    c = await s.get(Campana, campana_id)
    if c is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    if accion == "suspender":
        if not motivo.strip():
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "hace falta un motivo")
        c.suspendida = datetime.now(UTC)
        c.motivo_suspension = motivo.strip()
    else:
        c.suspendida = None
        c.motivo_suspension = None
    await s.commit()
    await _auditar(s, pedido, f"campana_{accion}", adm.usuario.id, campana=str(c.id), motivo=motivo.strip())
    return _volver(f"/admin/campanas/{c.id}")


@ruteador.post("/campanas/{campana_id}/plan")
async def cambiar_plan(
    campana_id: uuid.UUID, pedido: Request,
    plan: str = Form(...), motivo: str = Form(...),
    adm: Sesion = Depends(formulario_valido), s: AsyncSession = Depends(sesion),
) -> Response:
    c = await s.get(Campana, campana_id)
    if c is None or await s.get(Plan, plan) is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    if not motivo.strip():
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "hace falta un motivo")
    anterior = c.plan
    c.plan = plan
    await s.commit()
    await _auditar(s, pedido, "plan_manual", adm.usuario.id, campana=str(c.id),
                   de=anterior, a=plan, motivo=motivo.strip())
    return _volver(f"/admin/campanas/{c.id}")


# ---------------------------------------------------------------- planes


@ruteador.get("/planes", response_class=HTMLResponse)
async def planes(
    pedido: Request, adm: Sesion = Depends(admin_actual), s: AsyncSession = Depends(sesion)
) -> HTMLResponse:
    lista = (await s.execute(select(Plan).order_by(Plan.orden))).scalars().all()
    return _pagina(pedido, "planes.html", adm=adm, seccion="planes", lista=lista,
                   guardado=pedido.query_params.get("guardado"))


def _limite(valor: str) -> int | None:
    valor = valor.strip().replace(".", "")
    return None if valor == "" else max(int(valor), 0)


@ruteador.post("/planes/{codigo}")
async def guardar_plan(
    codigo: str, pedido: Request,
    nombre: str = Form(...), precio: str = Form(...),
    limite_integrantes: str = Form(""), limite_numeros: str = Form(""),
    limite_ventas: str = Form(""), limite_campanas_activas: str = Form(""),
    publicidad: str | None = Form(None),
    adm: Sesion = Depends(formulario_valido), s: AsyncSession = Depends(sesion),
) -> Response:
    p = await s.get(Plan, codigo)
    if p is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND)
    antes = {k: getattr(p, k) for k in ("nombre", "precio", "limite_integrantes", "limite_numeros",
                                         "limite_ventas", "limite_campanas_activas", "publicidad")}
    try:
        p.nombre = nombre.strip() or p.nombre
        p.precio = int(precio.strip().replace(".", "").replace("$", "") or 0) * 100
        p.limite_integrantes = _limite(limite_integrantes)
        p.limite_numeros = _limite(limite_numeros)
        p.limite_ventas = _limite(limite_ventas)
        p.limite_campanas_activas = _limite(limite_campanas_activas)
        p.publicidad = publicidad is not None
    except ValueError:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "los valores tienen que ser números enteros") from None
    await s.commit()
    despues = {k: getattr(p, k) for k in antes}
    await _auditar(s, pedido, "plan_editado", adm.usuario.id, plan=codigo,
                   cambios={k: [antes[k], despues[k]] for k in antes if antes[k] != despues[k]})
    return _volver(f"/admin/planes?guardado={codigo}")


# ---------------------------------------------------------------- salud


@ruteador.get("/salud", response_class=HTMLResponse)
async def salud(
    pedido: Request, adm: Sesion = Depends(admin_actual), s: AsyncSession = Depends(sesion)
) -> HTMLResponse:
    estados = []
    if CARPETA_ESTADO.exists():
        for archivo in sorted(CARPETA_ESTADO.glob("*.txt")):
            linea = archivo.read_text(encoding="utf-8", errors="replace").strip()
            estados.append({"nombre": archivo.stem, "ok": linea.startswith("OK"), "linea": linea})

    correo = (
        await s.execute(
            select(EnvioCorreo.estado, func.count())
            .where(EnvioCorreo.cuando > datetime.now(UTC) - timedelta(hours=24))
            .group_by(EnvioCorreo.estado)
        )
    ).all()
    compras_trabadas = (
        await s.execute(
            select(CompraCampana).where(
                or_(
                    CompraCampana.detalle_estado.ilike("importe no coincide%"),
                    (CompraCampana.estado == "reintegrada"),
                )
            ).order_by(CompraCampana.creada.desc()).limit(20)
        )
    ).scalars().all()
    ia = {"viva": await ia_local.esta_viva(), "modelo": ajustes().modelo_ia}
    tam_db = (await s.execute(text("select pg_size_pretty(pg_database_size(current_database()))"))).scalar_one()
    try:
        uso = shutil.disk_usage(ajustes().carpeta_archivos)
        disco = {"libre": uso.free / 2**30, "total": uso.total / 2**30}
    except OSError:
        disco = None
    return _pagina(pedido, "salud.html", adm=adm, seccion="salud", estados=estados, correo=correo,
                   compras_trabadas=compras_trabadas, tam_db=tam_db, disco=disco, ia=ia)


@ruteador.get("/accesos", response_class=HTMLResponse)
async def accesos(
    pedido: Request, adm: Sesion = Depends(admin_actual), s: AsyncSession = Depends(sesion)
) -> HTMLResponse:
    lista = (
        await s.execute(select(AccesoAdmin).order_by(AccesoAdmin.cuando.desc()).limit(200))
    ).scalars().all()
    return _pagina(pedido, "accesos.html", adm=adm, seccion="accesos", lista=lista)
