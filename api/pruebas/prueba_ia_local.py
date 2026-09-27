"""Prueba de la IA local: el recordatorio de deuda redactado por el modelo del VPS.

Corre contra https://miti.sole.ar. Deja a la vista el texto generado, cuánto tardó
y de dónde salió, para usarlo como evidencia.
"""

import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request

API = "https://miti.sole.ar"
SSH = ["ssh", "-i", os.path.expanduser("~/.ssh/oracle_ollama"), "-o", "BatchMode=yes",
       "ubuntu@129.146.57.10"]
sello = int(time.time())
EMAIL = f"ia.{sello}@pruebas.miti.sole.ar"

bien = fallas = 0


def probar(nombre, esperado, obtenido):
    global bien, fallas
    if esperado == obtenido:
        print(f"  OK   {nombre}")
        bien += 1
    else:
        print(f"  MAL  {nombre} -> esperaba {esperado!r} y vino {obtenido!r}")
        fallas += 1


def llamar(metodo, ruta, token=None, cuerpo=None, espera=90):
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    pedido = urllib.request.Request(API + ruta, data=datos, method=metodo)
    pedido.add_header("content-type", "application/json")
    if token:
        pedido.add_header("authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(pedido, timeout=espera) as r:
            texto = r.read().decode("utf-8", errors="replace")
            return r.status, (json.loads(texto) if texto.strip() else None)
    except urllib.error.HTTPError as e:
        texto = e.read().decode("utf-8", errors="replace")
        try:
            return e.code, json.loads(texto)
        except Exception:
            return e.code, texto


def entrar(email, nombre):
    llamar("POST", "/acceso/codigo", cuerpo={"email": email})
    time.sleep(1.5)
    log = subprocess.run(
        SSH + ["cd /srv/miti/app/infra && sudo docker compose logs --since 5m api"],
        capture_output=True, text=True, encoding="utf-8", errors="replace").stdout
    codigo = re.findall(rf"CÓDIGO DE ACCESO para {re.escape(email)}: (\d{{6}})", log)[-1]
    st, r = llamar("POST", "/acceso/verificar", cuerpo={
        "email": email, "codigo": codigo, "nombre": nombre, "nacimiento": "1990-01-01"})
    assert st == 200, (st, r)
    return r["token"]


print("\n--- PRUEBA DE IA LOCAL (Ollama en el VPS) ---")
t = entrar(EMAIL, "Vendedora Prueba")

st, campana = llamar("POST", "/campanas", t, {
    "tipo": "rifa",
    "nombre": f"Viaje de egresados 6 B {sello}",
    "alias_cuenta": "viaje.6b.mp",
    "rifa": {"desde": 0, "hasta": 99, "precio": 600_000, "asignacion": "bolsa",
             "sorteo": "externo", "si_no_se_vendio": "resortear"},
})
cid = campana["id"]
probar("campaña creada", 201, st)
st, _ = llamar("PATCH", f"/campanas/{cid}/estado", t, {"estado": "activa"})
probar("campaña activa", 200, st)

# Venta fiada: el comprador queda debiendo.
st, venta = llamar("POST", f"/campanas/{cid}/ventas", t, {
    "numeros": [7, 8],
    "comprador": {"nombre": "Carlos Gómez", "telefono": "1155443322"},
    "destino_cobro": "adeudado",
})
probar("venta a cuenta (queda debiendo)", 201, st)
probar("debe $12.000", 1_200_000, venta["saldo_adeudado"])
vid = venta["id"]

print("\n== El modelo redacta ==")
for tono in ("amable", "firme"):
    arranque = time.monotonic()
    st, r = llamar("POST", f"/campanas/{cid}/ventas/{vid}/recordatorio", t, {"tono": tono})
    demoro = time.monotonic() - arranque
    probar(f"responde 200 ({tono})", 200, st)
    if st != 200:
        continue
    print(f"\n  --- tono {tono} · origen: {r['origen']} · modelo: {r['modelo']} "
          f"· {r['demoro_ms']} ms (ida y vuelta: {demoro:.1f} s)")
    for linea in r["mensaje"].splitlines():
        print("  | " + linea)
    print()
    probar(f"dice el nombre del comprador ({tono})", True, "Carlos" in r["mensaje"])
    probar(f"dice cuánto debe ({tono})", True, "12.000" in r["mensaje"])
    probar(f"lo redactó la IA local ({tono})", "ia_local", r["origen"])

print("== Controles ==")
st, r = llamar("POST", f"/campanas/{cid}/ventas/{vid}/recordatorio", t, {"tono": "insultante"})
probar("un tono que no existe se rechaza", 422, st)

st, cobro = llamar("POST", f"/campanas/{cid}/ventas/{vid}/cobros", t,
                   {"importe": 1_200_000, "caja_tipo": "efectivo"})
st, r = llamar("POST", f"/campanas/{cid}/ventas/{vid}/recordatorio", t)
probar("a quien ya pagó no se le pide redactar nada (409)", 409, st)

st, r = llamar("POST", f"/campanas/{cid}/ventas/{'0' * 8}-0000-0000-0000-000000000000/recordatorio", t)
probar("una venta que no existe da 404", 404, st)

print(f"\nResultado IA local: {bien} OK, {fallas} fallas.")
if fallas:
    raise SystemExit(1)
print("TODO EN VERDE")
