"""Prueba de sincronización offline (Push, Pull, Idempotencia y Conflictos) contra miti.sole.ar."""

import json
import os
import re
import subprocess
import time
import urllib.error
import urllib.request
import uuid

API = "https://miti.sole.ar"
SSH = [
    "ssh", "-i", os.path.expanduser("~/.ssh/oracle_ollama"),
    "-o", "BatchMode=yes", "ubuntu@129.146.57.10",
]
sello = int(time.time())
U1 = f"ana.sync.{sello}@pruebas.miti.sole.ar"
U2 = f"beto.sync.{sello}@pruebas.miti.sole.ar"

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


print("== 1. Preparar usuarios y campaña de rifa ==")
for e in (U1, U2):
    llamar("POST", "/acceso/codigo", cuerpo={"email": e})
c1, c2 = codigo_de(U1), codigo_de(U2)

_, r1 = llamar("POST", "/acceso/verificar", cuerpo={"email": U1, "codigo": c1, "nombre": "Ana Sync", "nacimiento": "1991-01-01"})
t1 = r1["token"]

_, r2 = llamar("POST", "/acceso/verificar", cuerpo={"email": U2, "codigo": c2, "nombre": "Beto Sync", "nacimiento": "1993-02-02"})
t2 = r2["token"]

est, camp = llamar("POST", "/campanas", t1, {
    "tipo": "rifa",
    "nombre": f"Rifa Sync {sello}",
    "meta": 10_000_000,
    "rifa": {
        "desde": 0,
        "hasta": 99,
        "precio": 100_000,
        "asignacion": "bolsa",
        "sorteo": "externo",
    },
    "alias_cuenta": "ana.sync.mp",
})
probar("crear campaña de rifa", 201, est)
cid = camp["id"]

est, _ = llamar("POST", f"/campanas/{cid}/invitaciones", t1, {"email": U2})
probar("Ana invita a Beto", 201, est)

est, _ = llamar("POST", f"/campanas/{cid}/invitacion", t2, {"respuesta": "acepto"})
probar("Beto acepta invitación", 200, est)

est, _ = llamar("PATCH", f"/campanas/{cid}/estado", t1, {"estado": "activa"})
probar("activar campaña", 200, est)

print("\n== 2. Pull inicial (snapshot con desde=0) ==")
est, pull0 = llamar("GET", f"/campanas/{cid}/sync/pull?desde=0", t2)
probar("pull desde=0 status", 200, est)
probar("snapshot presente", True, pull0.get("snapshot") is not None)
snap = pull0.get("snapshot", {})
probar("snapshot tiene 100 números", 100, len(snap.get("numeros", [])))
probar("snapshot tiene campana activa", "activa", snap.get("campana", {}).get("estado"))
probar("snapshot tiene 2 integrantes", 2, len(snap.get("integrantes", [])))
cursor_inicial = pull0["cursor"]
print(f"  Cursor inicial: {cursor_inicial}")

print("\n== 3. Push de venta offline por Ana ==")
op_ana_id = str(uuid.uuid4())
push_ana = {
    "operaciones": [
        {
            "id": op_ana_id,
            "op": "vender_rifa",
            "creado_cliente": "2026-09-18T20:00:00Z",
            "payload": {
                "numeros": [42],
                "comprador": {"nombre": "Carlos Comprador", "telefono": "1199887766"},
                "destino_cobro": "efectivo",
            },
        }
    ]
}
est, res_push_ana = llamar("POST", f"/campanas/{cid}/sync/push", t1, push_ana)
probar("push Ana status", 200, est)
resultados_ana = res_push_ana.get("resultados", [])
probar("push Ana 1 resultado", 1, len(resultados_ana))
op1_res = resultados_ana[0] if resultados_ana else {}
probar("push Ana estado ok", "ok", op1_res.get("estado"))
probar("push Ana devolvió codigo_corto", True, "codigo_corto" in op1_res.get("resultado", {}))
sec_ana = op1_res.get("secuencia")
probar("secuencia generada > cursor_inicial", True, sec_ana > cursor_inicial)

print("\n== 4. Idempotencia en Push (reintento del mismo lote) ==")
est, res_reintento = llamar("POST", f"/campanas/{cid}/sync/push", t1, push_ana)
probar("reintento status", 200, est)
res_reintento_item = res_reintento.get("resultados", [{}])[0]
probar("reintento estado ok", "ok", res_reintento_item.get("estado"))
probar("reintento motivo ya_aplicada", "ya_aplicada", res_reintento_item.get("motivo"))

print("\n== 5. Conflicto offline: Beto intentó vender el mismo número 42 ==")
op_beto_conflicto = str(uuid.uuid4())
push_beto_conflicto = {
    "operaciones": [
        {
            "id": op_beto_conflicto,
            "op": "vender_rifa",
            "creado_cliente": "2026-09-18T20:01:00Z",
            "payload": {
                "numeros": [42],
                "comprador": {"nombre": "Diana Conflicto", "telefono": "1122334455"},
                "destino_cobro": "efectivo",
            },
        }
    ]
}
est, res_conflicto = llamar("POST", f"/campanas/{cid}/sync/push", t2, push_beto_conflicto)
probar("push Beto conflicto status", 200, est)
res_conflicto_item = res_conflicto.get("resultados", [{}])[0]
probar("push Beto estado conflicto", "conflicto", res_conflicto_item.get("estado"))
probar("motivo numeros_ocupados", "numeros_ocupados", res_conflicto_item.get("motivo"))
probar("detalle contiene numero 42", [42], res_conflicto_item.get("detalle", {}).get("numeros"))

print("\n== 6. Beto resuelve conflicto cambiando de número al 43 ==")
op_beto_ok = str(uuid.uuid4())
push_beto_ok = {
    "operaciones": [
        {
            "id": op_beto_ok,
            "op": "vender_rifa",
            "creado_cliente": "2026-09-18T20:02:00Z",
            "payload": {
                "numeros": [43],
                "comprador": {"nombre": "Diana Resuelta", "telefono": "1122334455"},
                "destino_cobro": "efectivo",
            },
        }
    ]
}
est, res_beto_ok = llamar("POST", f"/campanas/{cid}/sync/push", t2, push_beto_ok)
probar("push Beto resuelto status", 200, est)
res_beto_ok_item = res_beto_ok.get("resultados", [{}])[0]
probar("push Beto resuelto estado ok", "ok", res_beto_ok_item.get("estado"))

print("\n== 7. Pull incremental de cambios ==")
est, pull_inc = llamar("GET", f"/campanas/{cid}/sync/pull?desde={cursor_inicial}", t2)
probar("pull incremental status", 200, est)
cambios = pull_inc.get("cambios", [])
probar("pull incremental tiene cambios", True, len(cambios) >= 2)
tablas = [c["tabla"] for c in cambios]
probar("todas las operaciones son en ventas", True, all(t == "ventas" for t in tablas))

print(f"\nResultado final: {bien} OK, {fallas} fallas.")
if fallas > 0:
    exit(1)
