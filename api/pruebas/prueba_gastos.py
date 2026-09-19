"""Prueba integral de Registro y Aprobación de Gastos (§3.7 de DEFINICION.md) contra miti.sole.ar."""

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
U1 = f"ana.gasto.{sello}@pruebas.miti.sole.ar"
U2 = f"beto.gasto.{sello}@pruebas.miti.sole.ar"
U3 = f"carlos.gasto.{sello}@pruebas.miti.sole.ar"

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


def entrar(email, nombre):
    llamar("POST", "/acceso/codigo", cuerpo={"email": email})
    time.sleep(0.5)
    codigo = codigo_de(email)
    st, res = llamar("POST", "/acceso/verificar", cuerpo={
        "email": email, "codigo": codigo, "nombre": nombre, "nacimiento": "1995-05-10"
    })
    return res["token"], res["usuario"]["id"]


print("\n== 1. Preparar usuarios y campaña con 3 integrantes ==")
t_ana, id_ana = entrar(U1, "Ana")
t_beto, id_beto = entrar(U2, "Beto")
t_carlos, id_carlos = entrar(U3, "Carlos")

st, c = llamar("POST", "/campanas", token=t_ana, cuerpo={
    "nombre": f"Rifa Gastos {sello}",
    "tipo": "rifa",
    "moneda": "ARS",
    "config": {"desde": 1, "hasta": 100, "precio": 500000},  # $5.000 cada número
})
probar("crear campaña", 201, st)
camp_id = c["id"]

# Invitar a Beto y Carlos
llamar("POST", f"/campanas/{camp_id}/invitaciones", token=t_ana, cuerpo={"email": U2})
llamar("POST", f"/campanas/{camp_id}/invitaciones", token=t_ana, cuerpo={"email": U3})
llamar("POST", f"/campanas/{camp_id}/invitacion", token=t_beto, cuerpo={"respuesta": "acepto"})
llamar("POST", f"/campanas/{camp_id}/invitacion", token=t_carlos, cuerpo={"respuesta": "acepto"})

# Activar campaña
llamar("PATCH", f"/campanas/{camp_id}/estado", token=t_ana, cuerpo={"estado": "activa"})

# Obtener cajas
st, c_det = llamar("GET", f"/campanas/{camp_id}", token=t_ana)
cajas = c_det["cajas"]
caja_efectivo_ana = next(c["id"] for c in cajas if c["titular_id"] == id_ana and c["tipo"] == "efectivo")
caja_efectivo_beto = next(c["id"] for c in cajas if c["titular_id"] == id_beto and c["tipo"] == "efectivo")

print("\n== 2. Venta inicial para recaudar fondos ==")
# Ana vende 4 números en efectivo ($20.000)
st, v = llamar("POST", f"/campanas/{camp_id}/ventas", token=t_ana, cuerpo={
    "comprador_nombre": "Comprador 1",
    "comprador_telefono": "1111111111",
    "numeros": [1, 2, 3, 4],
    "destino": "efectivo",
})
probar("venta Ana $20.000", 201, st)

print("\n== 3. Registro de Gasto de Bolsillo por Integrante (Beto) ==")
st, g1 = llamar("POST", f"/campanas/{camp_id}/gastos", token=t_beto, cuerpo={
    "descripcion": "Carbón y leña para el asado",
    "importe": 400000,  # $4.000
    "origen": "bolsillo",
})
probar("gasto bolsillo Beto 201", 201, st)
probar("gasto estado inicial pendiente", "pendiente", g1["estado"])
mov1_id = g1["movimiento_id"]

# Beto intenta auto-aprobar su gasto -> 403
st, _ = llamar("POST", f"/campanas/{camp_id}/movimientos/{mov1_id}/confirmar", token=t_beto)
probar("Beto no puede auto-aprobar (403)", 403, st)

# Ana (admin) aprueba el gasto de Beto -> 200
st, m1_aprob = llamar("POST", f"/campanas/{camp_id}/movimientos/{mov1_id}/confirmar", token=t_ana)
probar("Ana aprueba gasto de Beto (200)", 200, st)
probar("movimiento 1 confirmado", "confirmado", m1_aprob["estado"])

print("\n== 4. Registro de Gasto por el Administrador (Ana) ==")
# Ana registra gasto de bolsillo
st, g2 = llamar("POST", f"/campanas/{camp_id}/gastos", token=t_ana, cuerpo={
    "descripcion": "Premios para sorteo",
    "importe": 600000,  # $6.000
    "origen": "bolsillo",
})
probar("gasto bolsillo Ana 201", 201, st)
mov2_id = g2["movimiento_id"]

# Ana intenta auto-aprobar su propio gasto -> 403
st, _ = llamar("POST", f"/campanas/{camp_id}/movimientos/{mov2_id}/confirmar", token=t_ana)
probar("Ana admin no puede auto-aprobar su gasto (403)", 403, st)

# Beto (integrante) aprueba el gasto del administrador -> 200
st, m2_aprob = llamar("POST", f"/campanas/{camp_id}/movimientos/{mov2_id}/confirmar", token=t_beto)
probar("Beto aprueba gasto del admin (200)", 200, st)
probar("movimiento 2 confirmado", "confirmado", m2_aprob["estado"])

print("\n== 5. Gasto desde Caja con fondos vs sin fondos ==")
# Beto intenta gastar $50.000 de su caja efectivo vacía -> 409
st, _ = llamar("POST", f"/campanas/{camp_id}/gastos", token=t_beto, cuerpo={
    "descripcion": "Gasto sin fondos",
    "importe": 5000000,
    "origen": "caja",
    "caja_id": caja_efectivo_beto,
})
probar("gasto caja sin fondos da 409", 409, st)

# Beto intenta gastar de la caja de Ana -> 403
st, _ = llamar("POST", f"/campanas/{camp_id}/gastos", token=t_beto, cuerpo={
    "descripcion": "Gasto caja ajena",
    "importe": 100000,
    "origen": "caja",
    "caja_id": caja_efectivo_ana,
})
probar("gasto caja ajena da 403", 403, st)

# Ana gasta $3.000 de su caja efectivo (que tiene $20.000 confirmados)
st, g3 = llamar("POST", f"/campanas/{camp_id}/gastos", token=t_ana, cuerpo={
    "descripcion": "Bolsas y embalaje",
    "importe": 300000,  # $3.000
    "origen": "caja",
    "caja_id": caja_efectivo_ana,
})
probar("Ana gasta de su caja efectivo 201", 201, st)
mov3_id = g3["movimiento_id"]

# Carlos aprueba el gasto de caja de Ana
st, _ = llamar("POST", f"/campanas/{camp_id}/movimientos/{mov3_id}/confirmar", token=t_carlos)
probar("Carlos aprueba gasto de caja de Ana 200", 200, st)

# Verificar saldos en recaudación
st, rec = llamar("GET", f"/campanas/{camp_id}/recaudacion", token=t_ana)
probar("recaudacion status 200", 200, st)
probar("total gastos confirmados $13.000", 1300000, rec["gastos"])
caja_ana_rec = next(c for c in rec["cajas"] if c["caja_id"] == caja_efectivo_ana)
probar("caja efectivo Ana ahora tiene $17.000 ($20.000 - $3.000)", 1700000, caja_ana_rec["confirmado"])

print("\n== 6. Gasto pendiente como impedimento de liquidación ==")
# Carlos registra un gasto de $2.000 que queda pendiente
st, g4 = llamar("POST", f"/campanas/{camp_id}/gastos", token=t_carlos, cuerpo={
    "descripcion": "Gasto observado",
    "importe": 200000,
    "origen": "bolsillo",
})
probar("Carlos registra gasto observado 201", 201, st)
mov4_id = g4["movimiento_id"]

# Simulación de liquidación detecta el gasto pendiente
st, sim = llamar("GET", f"/campanas/{camp_id}/liquidacion/simulacion", token=t_ana)
probar("simulación detecta impedimento", False, sim["puede_liquidar"])
probar("hay impedimento por movimiento pendiente", True, len(sim["impedimentos"]) > 0)

# Ana rechaza el gasto de Carlos con motivo
st, _ = llamar("POST", f"/campanas/{camp_id}/movimientos/{mov4_id}/rechazar", token=t_ana, cuerpo={
    "motivo": "Comprobante no corresponde a la campaña"
})
probar("Ana rechaza gasto observado 200", 200, st)

# Ahora la simulación permite liquidar
st, sim = llamar("GET", f"/campanas/{camp_id}/liquidacion/simulacion", token=t_ana)
probar("ahora puede liquidar", True, sim["puede_liquidar"])

print("\n== 7. Verificación de cálculo contable y reintegro en liquidación ==")
# Recaudado total: $20.000. Gastos caja: $3.000. Dinero en cajas: $17.000.
# Gastos bolsillo: Beto $4.000, Ana $6.000. Total gastos: $13.000.
# Neto a repartir: $20.000 - $13.000 = $7.000.
# Cuota parte (N=3): $7.000 // 3 = $2.333,33. Resto: 1 centavo asignado a Ana.
#   Ana: S_Ana = $2.333,34. R_Ana = $6.000. H_Ana = $17.000.
#        B_Ana = $17.000 - ($2.333,34 + $6.000) = $8.666,66 (debe transferir).
#   Beto: S_Beto = $2.333,33. R_Beto = $4.000. H_Beto = $0.
#        B_Beto = $0 - ($2.333,33 + $4.000) = -$6.333,33 (debe recibir $6.333,33).
#   Carlos: S_Carlos = $2.333,33. R_Carlos = $0. H_Carlos = $0.
#        B_Carlos = $0 - $2.333,33 = -$2.333,33 (debe recibir $2.333,33).
base_cob = sim["base_cobrada"]
probar("neto en base cobrada es $7.000", 700000, base_cob["neto"])
probar("cuota parte es $2.333,33", 233333, base_cob["parte"])
probar("gastos totales en simulación $13.000", 1300000, base_cob["gastos"])

# Liquidar en base cobrada
# Primero cerramos campaña
llamar("PATCH", f"/campanas/{camp_id}/estado", token=t_ana, cuerpo={"estado": "cerrada"})
st, liq = llamar("POST", f"/campanas/{camp_id}/liquidacion", token=t_ana, cuerpo={"base": "cobrada"})
probar("confirmar liquidación status 201", 201, st)
probar("neto liquidado es $7.000", 700000, liq["neto"])

# Verificar transferencias sugeridas
transfs = liq["transferencias"]
probar("2 transferencias generadas", 2, len(transfs))

t_para_beto = next((t for t in transfs if t["a_usuario_id"] == id_beto), None)
t_para_carlos = next((t for t in transfs if t["a_usuario_id"] == id_carlos), None)

probar("Ana le transfiere a Beto su cuota más reintegro de bolsillo ($6.333,33)", 633333, t_para_beto["importe"] if t_para_beto else 0)
probar("Ana le transfiere a Carlos su cuota ($2.333,33)", 233333, t_para_carlos["importe"] if t_para_carlos else 0)

# Listar gastos de la campaña
st, lista_gastos = llamar("GET", f"/campanas/{camp_id}/gastos", token=t_ana)
probar("listar gastos status 200", 200, st)
probar("hay 4 gastos registrados en la campaña", 4, len(lista_gastos))

print(f"\n==========================================")
print(f"Resultado final gastos: {bien} OK, {fallas} fallas.")
print(f"==========================================")
if fallas > 0:
    exit(1)
