"""Prueba de Cierre y Liquidación de Campaña (§3.9) contra miti.sole.ar."""

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
U1 = f"ana.liq.{sello}@pruebas.miti.sole.ar"
U2 = f"beto.liq.{sello}@pruebas.miti.sole.ar"
U3 = f"carlos.liq.{sello}@pruebas.miti.sole.ar"

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


print("== 1. Preparar usuarios y campaña con 3 integrantes ==")
for e in (U1, U2, U3):
    llamar("POST", "/acceso/codigo", cuerpo={"email": e})
c1, c2, c3 = codigo_de(U1), codigo_de(U2), codigo_de(U3)

_, r1 = llamar("POST", "/acceso/verificar", cuerpo={"email": U1, "codigo": c1, "nombre": "Ana Liq", "nacimiento": "1990-01-01"})
t1 = r1["token"]
uid1 = r1["usuario"]["id"]

_, r2 = llamar("POST", "/acceso/verificar", cuerpo={"email": U2, "codigo": c2, "nombre": "Beto Liq", "nacimiento": "1991-02-02"})
t2 = r2["token"]
uid2 = r2["usuario"]["id"]

_, r3 = llamar("POST", "/acceso/verificar", cuerpo={"email": U3, "codigo": c3, "nombre": "Carlos Liq", "nacimiento": "1992-03-03"})
t3 = r3["token"]
uid3 = r3["usuario"]["id"]

# Ana crea campaña de rifa
est, camp = llamar("POST", "/campanas", t1, {
    "tipo": "rifa",
    "nombre": f"Rifa Liquidacion {sello}",
    "meta": 10_000_000,
    "rifa": {
        "desde": 0,
        "hasta": 99,
        "precio": 100_000,  # $1.000 por número
        "asignacion": "bolsa",
        "sorteo": "externo",
    },
    "alias_cuenta": "ana.liq.mp",
})
probar("crear campaña", 201, est)
cid = camp["id"]

# Invitar a Beto y Carlos
llamar("POST", f"/campanas/{cid}/invitaciones", t1, {"email": U2})
llamar("POST", f"/campanas/{cid}/invitacion", t2, {"respuesta": "acepto"})

llamar("POST", f"/campanas/{cid}/invitaciones", t1, {"email": U3})
llamar("POST", f"/campanas/{cid}/invitacion", t3, {"respuesta": "acepto"})

# Activar campaña
llamar("PATCH", f"/campanas/{cid}/estado", t1, {"estado": "activa"})

print("\n== 2. Registrar ventas: Ana vende en efectivo, Beto vende adeudado ==")
# Ana vende 6 números en efectivo ($6.000)
est, _ = llamar("POST", f"/campanas/{cid}/ventas", t1, {
    "numeros": [1, 2, 3, 4, 5, 6],
    "comprador": {"nombre": "Comprador Ana", "telefono": "11111111"},
    "destino_cobro": "efectivo",
})
probar("venta Ana efectivo $6.000", 201, est)

# Beto vende 3 números adeudados ($3.000)
est, _ = llamar("POST", f"/campanas/{cid}/ventas", t2, {
    "numeros": [10, 11, 12],
    "comprador": {"nombre": "Comprador Beto Deudor", "telefono": "22222222"},
    "destino_cobro": "adeudado",
})
probar("venta Beto adeudado $3.000", 201, est)

print("\n== 3. Simulación de liquidación (ambas bases) ==")
est, sim = llamar("GET", f"/campanas/{cid}/liquidacion/simulacion", t1)
probar("simulacion status 200", 200, est)
probar("puede liquidar sin impedimentos", True, sim.get("puede_liquidar"))
probar("cero impedimentos", 0, len(sim.get("impedimentos", [])))

# Verificar Base Cobrada (se reparte solo lo cobrado: $6.000 entre 3 = $2.000 cada uno)
cob = sim["cobrada"]
probar("base cobrada neto $6.000", 600_000, cob["neto"])
probar("base cobrada parte $2.000", 200_000, cob["parte"])
# Transferencias sugeridas en base cobrada: Ana debe pasarle $2.000 a Beto y $2.000 a Carlos
transf_cob = cob["transferencias"]
probar("base cobrada tiene 2 transferencias", 2, len(transf_cob))
suma_transf_cob = sum(t["importe"] for t in transf_cob)
probar("suma transferencias base cobrada es $4.000", 400_000, suma_transf_cob)

# Verificar Base Vendida (se reparte $6.000 cobrado + $3.000 adeudado = $9.000 entre 3 = $3.000 cada uno)
ven = sim["vendida"]
probar("base vendida neto $9.000", 900_000, ven["neto"])
probar("base vendida parte $3.000", 300_000, ven["parte"])
# Transferencias sugeridas en base vendida: Ana le pasa $3.000 a Carlos; Beto queda en cero
transf_ven = ven["transferencias"]
probar("base vendida tiene 1 transferencia", 1, len(transf_ven))
probar("transferencia de Ana a Carlos por $3.000", 300_000, transf_ven[0]["importe"])

print("\n== 4. Impedimento: reserva activa impide liquidar ==")
# Beto reserva número 50
llamar("POST", f"/campanas/{cid}/numeros/50/reserva", t2, {"nota": "Reserva de prueba"})
est, sim_imp = llamar("GET", f"/campanas/{cid}/liquidacion/simulacion", t1)
probar("con reserva no puede liquidar", False, sim_imp.get("puede_liquidar"))
probar("hay impedimentos", True, len(sim_imp.get("impedimentos", [])) > 0)

# Intento de liquidar con impedimento debe dar 409
est, _ = llamar("POST", f"/campanas/{cid}/liquidacion", t1, {"base": "cobrada"})
probar("confirmar con impedimento da 409", 409, est)

# Liberar reserva
llamar("DELETE", f"/campanas/{cid}/numeros/50/reserva", t2)

print("\n== 5. Confirmar Liquidación (en Base Cobrada) ==")
# Beto (no admin) no puede liquidar
est, _ = llamar("POST", f"/campanas/{cid}/liquidacion", t2, {"base": "cobrada"})
probar("no admin no puede liquidar", 403, est)

# Ana liquida
est, liq = llamar("POST", f"/campanas/{cid}/liquidacion", t1, {"base": "cobrada"})
probar("Ana confirma liquidación status 201", 201, est)
probar("liquidada en base cobrada", "cobrada", liq["base"])
probar("neto liquidado $6.000", 600_000, liq["neto"])
probar("cuota parte $2.000", 200_000, liq["parte"])
transfs = liq["transferencias"]
probar("2 transferencias generadas", 2, len(transfs))

# Campaña queda bloqueada y liquidada
est, c_act = llamar("GET", f"/campanas/{cid}", t1)
probar("estado de campana es liquidada", "liquidada", c_act["estado"])

# Intento de nueva venta en campaña liquidada debe ser rechazado
est, _ = llamar("POST", f"/campanas/{cid}/ventas", t1, {
    "numeros": [99],
    "comprador": {"nombre": "Tardio", "telefono": "999999"},
    "destino_cobro": "efectivo",
})
probar("venta en campaña liquidada rechazada 409", 409, est)

print("\n== 6. Gestión de Transferencias de Liquidación ==")
# Obtener liquidación guardada
est, liq_guardada = llamar("GET", f"/campanas/{cid}/liquidacion", t2)
probar("obtener liquidacion status 200", 200, est)
probar("mismas transferencias registradas", 2, len(liq_guardada["transferencias"]))

t_ana_beto = next(t for t in liq_guardada["transferencias"] if t["a_usuario_id"] == uid2)
tid = t_ana_beto["id"]

# Carlos (tercero) no puede marcar pagada la transferencia entre Ana y Beto
est, _ = llamar("PATCH", f"/campanas/{cid}/liquidacion/transferencias/{tid}", t3, {"accion": "pagar"})
probar("tercero no puede marcar pagada (403)", 403, est)

# Ana (deudora) marca pagada
est, res_pagar = llamar("PATCH", f"/campanas/{cid}/liquidacion/transferencias/{tid}", t1, {"accion": "pagar"})
probar("Ana marca pagada status 200", 200, est)
probar("estado ahora es pagada", "pagada", res_pagar["estado"])

# Beto (acreedor) confirma cobro
est, res_conf = llamar("PATCH", f"/campanas/{cid}/liquidacion/transferencias/{tid}", t2, {"accion": "confirmar"})
probar("Beto confirma cobro status 200", 200, est)
probar("estado ahora es confirmada", "confirmada", res_conf["estado"])

print(f"\nResultado final: {bien} OK, {fallas} fallas.")
if fallas > 0:
    exit(1)
