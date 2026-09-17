"""Prueba del circuito completo de la Fase 1 contra miti.sole.ar."""

import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request

API = "https://miti.sole.ar"
SSH = [
    "ssh", "-i", os.path.expanduser("~/.ssh/oracle_ollama"),
    "-o", "BatchMode=yes", "ubuntu@129.146.57.10",
]
sello = int(time.time())
U1 = f"ana.{sello}@pruebas.miti.sole.ar"
U2 = f"beto.{sello}@pruebas.miti.sole.ar"

bien = fallas = 0


def probar(nombre, esperado, obtenido):
    global bien, fallas
    if esperado == obtenido:
        print(f"  OK   {nombre}")
        bien += 1
    else:
        print(f"  MAL  {nombre} -> esperaba {esperado!r} y vino {obtenido!r}")
        fallas += 1


def llamar(metodo, ruta, token=None, cuerpo=None):
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    pedido = urllib.request.Request(API + ruta, data=datos, method=metodo)
    pedido.add_header("content-type", "application/json")
    if token:
        pedido.add_header("authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(pedido, timeout=30) as r:
            texto = r.read().decode()
            return r.status, (json.loads(texto) if texto else None)
    except urllib.error.HTTPError as e:
        texto = e.read().decode()
        try:
            return e.code, json.loads(texto)
        except json.JSONDecodeError:
            return e.code, texto


def codigo_de(email):
    salida = subprocess.run(
        SSH + ["cd /srv/miti/app/infra && sudo docker compose logs --since 5m api"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    ).stdout
    hallazgos = re.findall(rf"CÓDIGO DE ACCESO para {re.escape(email)}: (\d{{6}})", salida)
    return hallazgos[-1] if hallazgos else None


print("== 1. alta de dos cuentas")
for e in (U1, U2):
    probar(f"pedir código ({e.split('@')[0]})", 204, llamar("POST", "/acceso/codigo", cuerpo={"email": e})[0])
c1, c2 = codigo_de(U1), codigo_de(U2)
probar("los códigos llegan al registro", True, bool(c1 and c2))

est, r = llamar("POST", "/acceso/verificar", cuerpo={
    "email": U1, "codigo": c1, "nombre": "Ana Prueba", "nacimiento": "1990-05-20"})
probar("Ana entra", 200, est)
t1, ref1 = r["token"], r["refresco"]

est, r = llamar("POST", "/acceso/verificar", cuerpo={
    "email": U2, "codigo": c2, "nombre": "Beto Prueba", "nacimiento": "2000-01-10"})
probar("Beto entra", 200, est)
t2 = r["token"]

print("== 2. reglas de alta")
probar("el código no se puede reusar", 400,
       llamar("POST", "/acceso/verificar", cuerpo={"email": U1, "codigo": c1})[0])
probar("código equivocado", 400,
       llamar("POST", "/acceso/verificar", cuerpo={"email": U1, "codigo": "000000"})[0])

menor = f"nene.{sello}@pruebas.miti.sole.ar"
llamar("POST", "/acceso/codigo", cuerpo={"email": menor})
cm = codigo_de(menor)
probar("menor de 13 rechazado", 403, llamar("POST", "/acceso/verificar", cuerpo={
    "email": menor, "codigo": cm, "nombre": "Nene Chico", "nacimiento": "2020-03-03"})[0])

sin_datos = f"nuevo.{sello}@pruebas.miti.sole.ar"
llamar("POST", "/acceso/codigo", cuerpo={"email": sin_datos})
probar("cuenta nueva sin nombre ni fecha", 422, llamar("POST", "/acceso/verificar", cuerpo={
    "email": sin_datos, "codigo": codigo_de(sin_datos)})[0])

print("== 3. perfil")
est, r = llamar("GET", "/yo", t1)
probar("el email vuelve descifrado", U1, r["email"])
probar("nombre", "Ana Prueba", r["nombre"])
probar("sin token no se puede", 401, llamar("GET", "/yo")[0])
probar("token inventado", 401, llamar("GET", "/yo", "esto.no.es")[0])

print("== 4. crear campaña (rifa)")
est, camp = llamar("POST", "/campanas", t1, {
    "tipo": "rifa", "nombre": "Viaje de egresados 6 B", "meta": 200_000_000,
    "alias_cuenta": "ana.mp",
    "rifa": {"desde": 0, "hasta": 99, "precio": 2_000_000, "asignacion": "bolsa",
             "sorteo": "externo", "si_no_se_vendio": "resortear"}})
probar("campaña creada", 201, est)
probar("arranca en borrador", "borrador", camp["estado"])
probar("Ana es administradora", "admin", camp["mi_rol"])
cid = camp["id"]

probar("rifa sin configuración", 422,
       llamar("POST", "/campanas", t1, {"tipo": "rifa", "nombre": "Sin config"})[0])
probar("rango al revés", 422, llamar("POST", "/campanas", t1, {
    "tipo": "rifa", "nombre": "Rango malo",
    "rifa": {"desde": 100, "hasta": 10, "precio": 100}})[0])

est, det = llamar("GET", f"/campanas/{cid}", t1)
probar("cajas al crear", 3, len(det["cajas"]))
principal = [c for c in det["cajas"] if c["tipo"] == "principal"][0]
probar("alias de la cuenta principal", "ana.mp", principal["alias"])

print("== 5. invitaciones")
probar("Beto no ve la campaña ajena", 404, llamar("GET", f"/campanas/{cid}", t2)[0])
probar("invitar a alguien sin cuenta", 404, llamar(
    "POST", f"/campanas/{cid}/invitaciones", t1, {"email": f"nadie.{sello}@pruebas.miti.sole.ar"})[0])
probar("invitar a Beto", 201, llamar("POST", f"/campanas/{cid}/invitaciones", t1, {"email": U2})[0])
probar("invitación repetida", 409,
       llamar("POST", f"/campanas/{cid}/invitaciones", t1, {"email": U2})[0])

est, inv = llamar("GET", "/invitaciones", t2)
probar("Beto tiene 1 invitación", 1, len(inv))
probar("dice quién lo invitó", "Ana Prueba", inv[0]["invitado_por"])
probar("el invitado todavía no puede invitar", 403,
       llamar("POST", f"/campanas/{cid}/invitaciones", t2, {"email": U1})[0])

est, r = llamar("POST", f"/campanas/{cid}/invitacion", t2, {"respuesta": "acepto"})
probar("Beto acepta", "activo", r["mi_estado"])
probar("no se puede aceptar dos veces", 409,
       llamar("POST", f"/campanas/{cid}/invitacion", t2, {"respuesta": "acepto"})[0])

est, cajas = llamar("GET", f"/campanas/{cid}/cajas", t2)
probar("cajas después de aceptar", 5, len(cajas))
probar("Beto sigue sin ser administrador", 403,
       llamar("POST", f"/campanas/{cid}/invitaciones", t2, {"email": U1})[0])

print("== 6. estados")
est, r = llamar("PATCH", f"/campanas/{cid}/estado", t1, {"estado": "activa"})
probar("activar la campaña", "activa", r["estado"])
probar("no se puede saltar a liquidada", 409,
       llamar("PATCH", f"/campanas/{cid}/estado", t1, {"estado": "liquidada"})[0])

print("== 7. refresco")
est, r = llamar("POST", "/acceso/refrescar", cuerpo={"refresco": ref1})
probar("el refresco rota", True, est == 200 and r["refresco"] != ref1)
nuevo = r["refresco"]
probar("el refresco viejo ya no sirve", 401,
       llamar("POST", "/acceso/refrescar", cuerpo={"refresco": ref1})[0])
probar("y por reuso se corta toda la cadena", 401,
       llamar("POST", "/acceso/refrescar", cuerpo={"refresco": nuevo})[0])

print("== 8. lo que ve cada uno")
probar("Ana ve 1 campaña", 1, len(llamar("GET", "/campanas", t1)[1]))
probar("Beto ve 1 campaña", 1, len(llamar("GET", "/campanas", t2)[1]))

print(f"\nRESULTADO: {bien} bien, {fallas} mal")
raise SystemExit(1 if fallas else 0)
