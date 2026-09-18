"""Prueba del circuito completo de la Fase 2 (Rifas, Ventas, Cajas, Comprobantes) contra miti.sole.ar."""

import base64
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
U1 = f"ana.f2.{sello}@pruebas.miti.sole.ar"
U2 = f"beto.f2.{sello}@pruebas.miti.sole.ar"

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

_, r1 = llamar("POST", "/acceso/verificar", cuerpo={"email": U1, "codigo": c1, "nombre": "Ana Vendedora", "nacimiento": "1990-05-20"})
t1 = r1["token"]

_, r2 = llamar("POST", "/acceso/verificar", cuerpo={"email": U2, "codigo": c2, "nombre": "Beto Vendedor", "nacimiento": "1992-10-10"})
t2 = r2["token"]

# Ana crea campaña de rifa de 100 números (0 a 99) a $2.000 cada número
est, camp = llamar("POST", "/campanas", t1, {
    "tipo": "rifa",
    "nombre": f"Rifa Solidaria {sello}",
    "meta": 20_000_000,  # $200.000
    "rifa": {
        "desde": 0,
        "hasta": 99,
        "precio": 200_000,  # $2.000
        "asignacion": "bolsa",
        "sorteo": "externo",
    },
    "alias_cuenta": "ana.rifa.mp",
})
probar("crear campaña de rifa", 201, est)
cid = camp["id"]

# Ana invita a Beto y Beto acepta
est, _ = llamar("POST", f"/campanas/{cid}/invitaciones", t1, {"email": U2})
probar("Ana invita a Beto", 201, est)

est, _ = llamar("POST", f"/campanas/{cid}/respuesta", t2, {"respuesta": "acepto"})
probar("Beto acepta invitación", 200, est)

# Ana activa la campaña
est, camp_act = llamar("PATCH", f"/campanas/{cid}/estado", t1, {"estado": "activa"})
probar("activar campaña", 200, est)

print("\n== 2. Números de rifa y reservas ==")
est, nums = llamar("GET", f"/campanas/{cid}/numeros", t1)
probar("listar números devuelve 200", 200, est)
probar("hay 100 números en la rifa", 100, len(nums))
probar("el número 0 arranca libre", "libre", nums[0]["estado"])

# Beto reserva el número 42
est, res42 = llamar("POST", f"/campanas/{cid}/numeros/42/reservar", t2, {"nota": "para mi tío"})
probar("Beto reserva número 42", 200, est)
probar("número 42 queda reservado", "reservado", res42["estado"])
probar("número 42 reservado por mí para Beto", True, res42["reservado_por_mi"])

# Ana consulta números y ve el 42 reservado por otro
_, nums_ana = llamar("GET", f"/campanas/{cid}/numeros", t1)
n42_ana = next(n for n in nums_ana if n["numero"] == 42)
probar("Ana ve el 42 como reservado", "reservado", n42_ana["estado"])
probar("para Ana no es reservado_por_mi", False, n42_ana["reservado_por_mi"])
probar("la nota de reserva se ve", "para mi tío", n42_ana["reserva_nota"])

# Ana intenta vender el 42 que Beto reservó -> debe fallar con 409
est, _ = llamar("POST", f"/campanas/{cid}/ventas", t1, {
    "numeros": [42],
    "comprador": {"nombre": "Intruso", "telefono": "1199887766"},
    "destino_cobro": "efectivo",
})
probar("Ana no puede vender número reservado por Beto", 409, est)

# Beto libera el 42
est, lib = llamar("POST", f"/campanas/{cid}/numeros/42/liberar", t2)
probar("Beto libera el número 42", 200, est)
probar("el 42 vuelve a estar libre", "libre", lib["estado"])

print("\n== 3. Comprobantes y detección de duplicados ==")
dummy_png = base64.b64encode(b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4").decode()
est, comp1 = llamar("POST", f"/campanas/{cid}/comprobantes", t1, {
    "archivo_base64": dummy_png,
    "mime": "image/png",
    "nro_operacion": "OP-998877",
})
probar("subir comprobante", 201, est)
probar("sin aviso de duplicado en primera subida", None, comp1["duplicado_aviso"])
comp_id = comp1["id"]

# Intentar subir el mismo comprobante en la misma campaña
est, comp_dup = llamar("POST", f"/campanas/{cid}/comprobantes", t1, {
    "archivo_base64": dummy_png,
    "mime": "image/png",
    "nro_operacion": "OP-998877",
})
probar("subida repetida da 201 pero con aviso", 201, est)
probar("se detecta posible duplicado", True, bool(comp_dup["duplicado_aviso"]))

print("\n== 4. Ventas y destinos de fondos ==")
# Venta 1: Ana vende números 10 y 11 en efectivo a Carlos Gómez
est, v1 = llamar("POST", f"/campanas/{cid}/ventas", t1, {
    "numeros": [10, 11],
    "comprador": {"nombre": "Carlos Gómez", "telefono": "1155443322"},
    "destino_cobro": "efectivo",
})
probar("Ana registra venta de 2 números en efectivo", 201, est)
probar("importe total $4.000", 400_000, v1["importe"])
probar("total cobrado $4.000", 400_000, v1["total_cobrado"])
probar("saldo adeudado $0", 0, v1["saldo_adeudado"])
probar("código corto de 6 caracteres", 6, len(v1["codigo_corto"]))

# Venta 2: Beto vende número 20 a Laura López con destino cuenta_principal (de Ana)
est, v2 = llamar("POST", f"/campanas/{cid}/ventas", t2, {
    "numeros": [20],
    "comprador": {"nombre": "Laura López", "telefono": "1166778899"},
    "destino_cobro": "cuenta_principal",
    "comprobante_id": comp_id,
})
probar("Beto registra venta a cuenta principal", 201, est)
probar("importe total $2.000", 200_000, v2["importe"])
probar("queda en cobro pendiente", 200_000, v2["cobro_pendiente"])
probar("total cobrado confirmado es 0", 0, v2["total_cobrado"])

# Venta 3: Ana vende número 30 como adeudado ("todavía no pagó")
est, v3 = llamar("POST", f"/campanas/{cid}/ventas", t1, {
    "numeros": [30],
    "comprador": {"nombre": "Martín Deudor", "telefono": "1122334455"},
    "destino_cobro": "adeudado",
})
probar("Ana registra venta adeudada", 201, est)
probar("total cobrado es 0", 0, v3["total_cobrado"])
probar("saldo adeudado es $2.000", 200_000, v3["saldo_adeudado"])

print("\n== 5. Regla de privacidad (§3.2): teléfono solo para el vendedor ==")
est, ventas_beto = llamar("GET", f"/campanas/{cid}/ventas", t2)
v_carlos_para_beto = next(v for v in ventas_beto if v["id"] == v1["id"])
v_laura_para_beto = next(v for v in ventas_beto if v["id"] == v2["id"])
probar("Beto ve el nombre del comprador de Ana", "Carlos Gómez", v_carlos_para_beto["comprador"]["nombre"])
probar("Beto NO ve el teléfono del comprador de Ana", None, v_carlos_para_beto["comprador"]["telefono"])
probar("Beto SÍ ve el teléfono de su propia compradora", "1166778899", v_laura_para_beto["comprador"]["telefono"])

est, ventas_ana = llamar("GET", f"/campanas/{cid}/ventas", t1)
v_carlos_para_ana = next(v for v in ventas_ana if v["id"] == v1["id"])
v_laura_para_ana = next(v for v in ventas_ana if v["id"] == v2["id"])
probar("Ana SÍ ve el teléfono de su propio comprador", "1155443322", v_carlos_para_ana["comprador"]["telefono"])
probar("Ana NO ve el teléfono de la compradora de Beto", None, v_laura_para_ana["comprador"]["telefono"])

print("\n== 6. Recaudación y aprobación de cobros ==")
est, rec = llamar("GET", f"/campanas/{cid}/recaudacion", t1)
probar("recaudación status 200", 200, est)
probar("total vendido es $8.000 (4 números)", 800_000, rec["vendido"])
probar("cobrado confirmado $4.000 (efectivo Ana)", 400_000, rec["cobrado"])
probar("cobrado pendiente $2.000 (cuenta principal)", 200_000, rec["pendiente"])
probar("falta cobrar $4.000 (adeudado + pendiente)", 400_000, rec["falta_cobrar"])
probar("números vendidos: 4", 4, rec["numeros_vendidos"])
probar("números libres: 96", 96, rec["numeros_libres"])

# Ana busca el movimiento pendiente de la venta 2 y lo confirma
# Obtenemos el detalle de la venta 2
est, det_v2 = llamar("GET", f"/campanas/{cid}/ventas/{v2['id']}", t1)
# Consultamos recaudación / cajas para ver los movimientos
# Ana confirma el cobro que le entró en la cuenta principal
# Buscamos el movimiento con estado pendiente en la cuenta principal
caja_principal = next(c for c in rec["cajas"] if c["tipo"] == "principal")
probar("la caja principal tiene $2.000 pendientes", 200_000, caja_principal["pendiente"])

# Realizamos la confirmación del movimiento pendiente:
# Para encontrar el ID del movimiento, registramos un cobro y obtenemos ID, o llamamos a confirmar
# Verificamos que cobro de venta adeudada funciona:
est, cobro_parcial = llamar("POST", f"/campanas/{cid}/ventas/{v3['id']}/cobros", t1, {
    "caja_tipo": "billetera",
    "importe": 100_000,  # $1.000
})
probar("registrar cobro parcial a venta adeudada", 200, est)
probar("el cobro parcial queda confirmado", "confirmado", cobro_parcial["estado"])

# Verificamos que la venta 3 ahora debe solo $1.000
est, v3_act = llamar("GET", f"/campanas/{cid}/ventas/{v3['id']}", t1)
probar("venta adeudada ahora debe $1.000", 100_000, v3_act["saldo_adeudado"])
probar("venta adeudada cobró $1.000", 100_000, v3_act["total_cobrado"])

print("\n== 7. Concurrencia e integridad ==")
# Intentar vender número 10 que ya está vendido
est, _ = llamar("POST", f"/campanas/{cid}/ventas", t2, {
    "numeros": [10],
    "comprador": {"nombre": "Otro", "telefono": "1144332211"},
    "destino_cobro": "efectivo",
})
probar("no se puede vender un número ya vendido (409)", 409, est)

print(f"\n==========================================")
print(f"Total: {bien} en verde, {fallas} fallas")
print(f"==========================================")
if fallas > 0:
    exit(1)
