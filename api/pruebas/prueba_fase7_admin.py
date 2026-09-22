"""Prueba del panel de administración (/admin) contra https://miti.sole.ar.

Crea una cuenta de prueba, la hace administradora por SSH, entra con código +
TOTP (enrolando), recorre las secciones, prueba las acciones y el CSRF, y al
final le saca el rol y devuelve los planes como estaban.

Necesita pyotp:  pip install pyotp
"""

import html
import http.cookiejar
import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

import pyotp

API = "https://miti.sole.ar"
SSH = ["ssh", "-i", os.path.expanduser("~/.ssh/oracle_ollama"), "-o", "BatchMode=yes", "ubuntu@129.146.57.10"]
sello = int(time.time())
EMAIL = f"admin.prueba.{sello}@pruebas.miti.sole.ar"
OTRO = f"no.admin.{sello}@pruebas.miti.sole.ar"

bien = fallas = 0


def probar(nombre, esperado, obtenido):
    global bien, fallas
    if esperado == obtenido:
        print(f"  OK   {nombre}")
        bien += 1
    else:
        print(f"  MAL  {nombre} -> esperaba {esperado!r} y vino {obtenido!r}")
        fallas += 1


class SinRedireccion(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


frasco = http.cookiejar.CookieJar()
navegador = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(frasco), SinRedireccion)


def web(metodo, ruta, datos=None):
    cuerpo = urllib.parse.urlencode(datos).encode() if datos is not None else None
    pedido = urllib.request.Request(API + ruta, data=cuerpo, method=metodo)
    if cuerpo is not None:
        pedido.add_header("content-type", "application/x-www-form-urlencoded")
    try:
        with navegador.open(pedido, timeout=30) as r:
            return r.status, r.read().decode("utf-8", errors="replace"), r.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace"), e.headers


def api(metodo, ruta, token=None, cuerpo=None):
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    pedido = urllib.request.Request(API + ruta, data=datos, method=metodo)
    pedido.add_header("content-type", "application/json")
    if token:
        pedido.add_header("authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(pedido, timeout=30) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def ssh(comando):
    return subprocess.run(SSH + [comando], capture_output=True, text=True, encoding="utf-8", errors="replace")


def ultimo_codigo(email):
    log = ssh("cd /srv/miti/app/infra && sudo docker compose logs --since 5m api").stdout
    hallados = re.findall(rf"CÓDIGO DE ACCESO para {re.escape(email)}: (\d{{6}})", log)
    return hallados[-1] if hallados else None


def cuenta(email, nombre):
    api("POST", "/acceso/codigo", cuerpo={"email": email})
    time.sleep(1.5)
    st, r = api("POST", "/acceso/verificar", cuerpo={
        "email": email, "codigo": ultimo_codigo(email), "nombre": nombre, "nacimiento": "1990-01-01"})
    assert st == 200, (st, r)
    return r["token"]


def csrf(pagina):
    m = re.search(r'name="csrf" value="([^"]+)"', pagina)
    return m.group(1) if m else ""


def compose(args):
    return ssh(f"cd /srv/miti/app/infra && sudo docker compose run --rm --no-deps -T api {args}")


print("\n--- PRUEBA FASE 7: PANEL DE ADMINISTRACIÓN ---")
t_admin = cuenta(EMAIL, "Admin Prueba")
t_otro = cuenta(OTRO, "Otro Usuario")

print("\n== 1. Alta del administrador ==")
r = compose(f"python -m miti_api.admin.alta {EMAIL}")
probar("el alta por consola funciona", True, "es administrador" in r.stdout)

print("\n== 2. Sin sesión ==")
st, _, h = web("GET", "/admin")
probar("/admin sin sesión redirige a entrar", (303, "/admin/entrar"), (st, h.get("location")))
st, pag, h = web("GET", "/admin/entrar")
probar("la página de entrada responde", 200, st)
probar("tiene CSP sin scripts", True, "script-src 'none'" in (h.get("content-security-policy") or ""))

print("\n== 3. Un usuario que no es admin no recibe código ==")
st, pag, _ = web("POST", "/admin/entrar", {"email": OTRO})
probar("responde igual que a un admin (no revela nada)", True, "le llegó un código" in pag)
time.sleep(1.5)
st, pag, _ = web("POST", "/admin/codigo", {"email": OTRO, "codigo": ultimo_codigo(OTRO) or "000000"})
probar("con el código de la app no entra al panel", True, "no es válido" in pag)

print("\n== 4. Entrada del admin: código + enrolar TOTP ==")
web("POST", "/admin/entrar", {"email": EMAIL})
time.sleep(1.5)
st, pag, _ = web("POST", "/admin/codigo", {"email": EMAIL, "codigo": "123456"})
probar("un código equivocado se rechaza", True, "no es válido" in pag)
st, _, h = web("POST", "/admin/codigo", {"email": EMAIL, "codigo": ultimo_codigo(EMAIL)})
probar("con el código bueno pasa a enrolar", (303, "/admin/enrolar"), (st, h.get("location")))
st, pag, _ = web("GET", "/admin/enrolar")
secreto = re.search(r"<code[^>]*>([A-Z2-7 ]+)</code>", pag)
secreto = secreto.group(1).replace(" ", "") if secreto else ""
probar("muestra la clave para la app autenticadora", True, len(secreto) >= 16)
st, pag, _ = web("POST", "/admin/enrolar", {"totp": "000000"})
probar("un TOTP equivocado no enrola", True, "no coincide" in pag)
st, _, h = web("POST", "/admin/enrolar", {"totp": pyotp.TOTP(secreto).now()})
probar("con el TOTP bueno entra al panel", (303, "/admin"), (st, h.get("location")))

print("\n== 5. Secciones ==")
for ruta, texto in [("/admin", "Métricas"), ("/admin/usuarios", "Usuarios"), ("/admin/campanas", "Campañas"),
                    ("/admin/planes", "Planes y límites"), ("/admin/salud", "Salud del sistema"),
                    ("/admin/accesos", "Accesos al panel")]:
    st, pag, _ = web("GET", ruta)
    probar(f"{ruta} responde con su título", (200, True), (st, texto in pag))
st, pag, _ = web("GET", "/admin/salud")
probar("salud muestra el estado de las copias", True, "archivos-semanal" in pag or "semanal" in pag)
st, pag, _ = web("GET", f"/admin/usuarios?q={urllib.parse.quote(OTRO)}")
probar("encuentra un usuario por el email exacto", True, "Otro Usuario" in pag)

print("\n== 6. CSRF ==")
st, _, _ = web("POST", "/admin/planes/gratis", {"csrf": "falso", "nombre": "Gratis", "precio": "0"})
probar("un formulario sin el token correcto se rechaza", 403, st)

print("\n== 7. Planes: editar y volver ==")
st, pag, _ = web("GET", "/admin/planes")
token = csrf(pag)
st, _, h = web("POST", "/admin/planes/campana", {
    "csrf": token, "nombre": "Campaña", "precio": "16000", "limite_integrantes": "15",
    "limite_numeros": "1000", "limite_ventas": "300", "limite_campanas_activas": ""})
probar("guardar el plan Campaña", 303, st)
st, planes = api("GET", "/planes", t_admin)
precio = next((p["precio"] for p in planes if p["codigo"] == "campana"), None)
probar("la app ve el precio nuevo al instante ($16.000)", 1_600_000, precio)
web("POST", "/admin/planes/campana", {
    "csrf": token, "nombre": "Campaña", "precio": "15000", "limite_integrantes": "15",
    "limite_numeros": "1000", "limite_ventas": "300", "limite_campanas_activas": ""})
st, planes = api("GET", "/planes", t_admin)
precio = next((p["precio"] for p in planes if p["codigo"] == "campana"), None)
probar("el precio vuelve a $15.000", 1_500_000, precio)

print("\n== 8. Suspender una campaña ==")
st, camp = api("POST", "/campanas", t_otro, {"tipo": "productos", "nombre": f"Para suspender {sello}"})
cid = camp["id"]
web("POST", f"/admin/campanas/{cid}/suspension", {"csrf": token, "accion": "suspender", "motivo": "Prueba automática"})
st, _ = api("POST", f"/campanas/{cid}/productos", t_otro, {"nombre": "Algo", "precio": 1000})
probar("en una campaña suspendida no se puede cargar nada (423)", 423, st)
st, detalle = api("GET", f"/campanas/{cid}", t_otro)
probar("pero se puede mirar, y la app sabe que está suspendida", (200, True), (st, detalle.get("suspendida")))
web("POST", f"/admin/campanas/{cid}/suspension", {"csrf": token, "accion": "reactivar"})
st, _ = api("POST", f"/campanas/{cid}/productos", t_otro, {"nombre": "Algo", "precio": 1000})
probar("reactivada, vuelve a funcionar", 201, st)

print("\n== 9. Cambiar el plan a mano ==")
st, _, _ = web("POST", f"/admin/campanas/{cid}/plan", {"csrf": token, "plan": "grande", "motivo": "Regalo de prueba"})
st, estado = api("GET", f"/campanas/{cid}/plan", t_otro)
probar("la campaña queda en Campaña Grande", "grande", estado.get("actual", {}).get("codigo"))

print("\n== 10. Bloquear un usuario ==")
st, pag, _ = web("GET", f"/admin/usuarios?q={urllib.parse.quote(OTRO)}")
uid = re.search(r"/admin/usuarios/([0-9a-f-]{36})/bloqueo", pag).group(1)
web("POST", f"/admin/usuarios/{uid}/bloqueo", {"csrf": token, "accion": "bloquear", "motivo": "Prueba"})
st, _ = api("GET", "/yo", t_otro)
probar("el usuario bloqueado queda afuera (403)", 403, st)
web("POST", f"/admin/usuarios/{uid}/bloqueo", {"csrf": token, "accion": "desbloquear"})
st, _ = api("GET", "/yo", t_otro)
probar("desbloqueado, vuelve a entrar", 200, st)

print("\n== 11. Auditoría ==")
st, pag, _ = web("GET", "/admin/accesos")
for accion in ["totp_enrolado", "totp_fallido", "plan_editado", "campana_suspender", "plan_manual", "usuario_bloquear"]:
    probar(f"queda registrado: {accion}", True, accion in pag)

print("\n== 12. Salir ==")
st, _, h = web("POST", "/admin/salir", {"csrf": token})
probar("salir vuelve a la entrada", (303, "/admin/entrar"), (st, h.get("location")))
st, _, h = web("GET", "/admin")
probar("y ya no hay sesión", 303, st)

print("\n== 13. Segunda entrada: pide el TOTP, no enrola ==")
web("POST", "/admin/entrar", {"email": EMAIL})
time.sleep(1.5)
st, _, h = web("POST", "/admin/codigo", {"email": EMAIL, "codigo": ultimo_codigo(EMAIL)})
probar("con el código pasa al TOTP", (303, "/admin/totp"), (st, h.get("location")))
st, _, h = web("POST", "/admin/totp", {"totp": pyotp.TOTP(secreto).now()})
probar("con el TOTP entra", (303, "/admin"), (st, h.get("location")))

r = compose(f"python -m miti_api.admin.alta {EMAIL} --baja")
probar("limpieza: el admin de prueba deja de serlo", True, "ya no es administrador" in r.stdout)
st, _, h = web("GET", "/admin")
probar("y su sesión deja de servir", 303, st)

print(f"\nResultado final admin: {bien} OK, {fallas} fallas.")
if fallas:
    raise SystemExit(1)
print("TODO EN VERDE")
