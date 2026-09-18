"""Prueba del circuito completo de Campañas de Productos contra miti.sole.ar."""

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
U1 = f"ana.prod.{sello}@pruebas.miti.sole.ar"
U2 = f"beto.prod.{sello}@pruebas.miti.sole.ar"

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


print("== 1. Preparar usuarios y campaña de productos ==")
for e in (U1, U2):
    llamar("POST", "/acceso/codigo", cuerpo={"email": e})
c1, c2 = codigo_de(U1), codigo_de(U2)

_, r1 = llamar("POST", "/acceso/verificar", cuerpo={"email": U1, "codigo": c1, "nombre": "Ana Chef", "nacimiento": "1990-05-20"})
t1 = r1["token"]

_, r2 = llamar("POST", "/acceso/verificar", cuerpo={"email": U2, "codigo": c2, "nombre": "Beto Mozo", "nacimiento": "1992-10-10"})
t2 = r2["token"]

# Ana crea campaña de productos
est, camp = llamar("POST", "/campanas", t1, {
    "tipo": "productos",
    "nombre": f"Empanadas y Pizzas {sello}",
    "meta": 50_000_000,
    "alias_cuenta": "ana.comida.mp",
})
probar("crear campaña de productos", 201, est)
cid = camp["id"]

# Ana invita a Beto y Beto acepta
est, _ = llamar("POST", f"/campanas/{cid}/invitaciones", t1, {"email": U2})
probar("Ana invita a Beto", 201, est)

est, _ = llamar("POST", f"/campanas/{cid}/invitacion", t2, {"respuesta": "acepto"})
probar("Beto acepta invitación", 200, est)

# Ana activa la campaña
est, _ = llamar("PATCH", f"/campanas/{cid}/estado", t1, {"estado": "activa"})
probar("activar campaña", 200, est)

print("\n== 2. Catálogo de productos ==")
# Ana crea 3 productos
est, p1 = llamar("POST", f"/campanas/{cid}/productos", t1, {
    "nombre": "Docena de Empanadas",
    "precio": 1_200_000,  # $12.000
})
probar("crear producto 1 (empanadas)", 201, est)
p1_id = p1["id"]

est, p2 = llamar("POST", f"/campanas/{cid}/productos", t1, {
    "nombre": "Pizza Muzza",
    "precio": 800_000,  # $8.000
})
probar("crear producto 2 (pizza)", 201, est)
p2_id = p2["id"]

est, p3 = llamar("POST", f"/campanas/{cid}/productos", t1, {
    "nombre": "Locro Criollo",
    "precio": 1_000_000,  # $10.000
})
probar("crear producto 3 (locro)", 201, est)
p3_id = p3["id"]

# Beto (no admin) intenta crear producto -> 403
est, _ = llamar("POST", f"/campanas/{cid}/productos", t2, {
    "nombre": "Flan Casero",
    "precio": 300_000,
})
probar("no admin no puede crear productos", 403, est)

# Ana desactiva Locro Criollo
est, p3_mod = llamar("PATCH", f"/campanas/{cid}/productos/{p3_id}", t1, {"activo": False})
probar("desactivar producto", 200, est)
probar("locro quedó inactivo", False, p3_mod["activo"])

# Beto lista productos: solo ve 2 activos
est, prods_beto = llamar("GET", f"/campanas/{cid}/productos", t2)
probar("listar productos status 200", 200, est)
probar("integrante solo ve productos activos (2)", 2, len(prods_beto))

# Ana lista productos: ve los 3 (incluyendo inactivos)
est, prods_ana = llamar("GET", f"/campanas/{cid}/productos", t1)
probar("admin ve todos los productos (3)", 3, len(prods_ana))

print("\n== 3. Ventas de productos ==")
# Beto registra venta de 2 docenas de empanadas y 1 pizza en efectivo
# Importe: 2 * $12.000 + 1 * $8.000 = $32.000 (3_200_000 centavos)
est, v1 = llamar("POST", f"/campanas/{cid}/ventas/productos", t2, {
    "items": [
        {"producto_id": p1_id, "cantidad": 2},
        {"producto_id": p2_id, "cantidad": 1},
    ],
    "comprador": {
        "nombre": "Carlos Gómez",
        "telefono": "1155443322",
    },
    "destino_cobro": "efectivo",
    "entrega": "pedido",
})
probar("registrar venta de productos", 201, est)
v1_id = v1["id"]
probar("importe total $32.000", 3_200_000, v1["importe"])
probar("total cobrado $32.000", 3_200_000, v1["total_cobrado"])
probar("saldo adeudado $0", 0, v1["saldo_adeudado"])
probar("estado entrega inicial 'pedido'", "pedido", v1["entrega"])
probar("hay 2 items en la venta", 2, len(v1["items_productos"]))

# Ana vende 1 pizza muzza a cuenta principal, entrega 'entregado'
# Ana (dueña de la cuenta principal) vende 1 pizza muzza a cuenta principal
est, v2 = llamar("POST", f"/campanas/{cid}/ventas/productos", t1, {
    "items": [
        {"producto_id": p2_id, "cantidad": 1},
    ],
    "comprador": {
        "nombre": "Diana López",
        "telefono": "1199887766",
    },
    "destino_cobro": "cuenta_principal",
    "entrega": "entregado",
})
probar("dueña de cuenta vende a cuenta principal", 201, est)
probar("importe $8.000", 800_000, v2["importe"])
probar("queda confirmado al instante (0 pendiente)", 0, v2["cobro_pendiente"])
probar("total cobrado confirmado es $8.000", 800_000, v2["total_cobrado"])
probar("estado entrega 'entregado'", "entregado", v2["entrega"])

# Beto (no dueño de cuenta principal) vende 1 pizza a cuenta principal
est, v3 = llamar("POST", f"/campanas/{cid}/ventas/productos", t2, {
    "items": [
        {"producto_id": p2_id, "cantidad": 1},
    ],
    "comprador": {
        "nombre": "Esteban Quito",
        "telefono": "1122339988",
    },
    "destino_cobro": "cuenta_principal",
    "entrega": "pedido",
})
probar("participante que no es dueño vende a cuenta principal", 201, est)
probar("venta de participante queda pendiente de confirmación", 800_000, v3["cobro_pendiente"])
probar("venta de participante tiene cobrado confirmado 0", 0, v3["total_cobrado"])

# Intentar vender producto inactivo da 409
est, _ = llamar("POST", f"/campanas/{cid}/ventas/productos", t2, {
    "items": [{"producto_id": p3_id, "cantidad": 1}],
    "comprador": {"nombre": "Test", "telefono": "11223344"},
    "destino_cobro": "efectivo",
})
probar("producto inactivo rechaza venta (409)", 409, est)

print("\n== 4. Actualizar estado de entrega ==")
# Beto pasa su pedido de 'pedido' a 'entregado'
est, v1_mod = llamar("PATCH", f"/campanas/{cid}/ventas/{v1_id}/entrega", t2, {"entrega": "entregado"})
probar("actualizar entrega a 'entregado'", 200, est)
probar("entrega ahora es 'entregado'", "entregado", v1_mod["entrega"])

print("\n== 5. Regla de privacidad (§3.2) ==")
est, ventas_beto = llamar("GET", f"/campanas/{cid}/ventas", t2)
probar("listar ventas devuelve 3 ventas", 3, len(ventas_beto))
v1_b = next(v for v in ventas_beto if v["id"] == v1_id)
v2_b = next(v for v in ventas_beto if v["id"] == v2["id"])

probar("Beto ve teléfono de su comprador Carlos", "1155443322", v1_b["comprador"]["telefono"])
probar("Beto NO ve teléfono de compradora de Ana", None, v2_b["comprador"]["telefono"])

print("\n== 6. Recaudación y desglose de productos ==")
est, rec = llamar("GET", f"/campanas/{cid}/recaudacion", t1)
probar("recaudacion status 200", 200, est)
probar("total vendido es $48.000", 4_800_000, rec["vendido"])
probar("cobrado confirmado $40.000", 4_000_000, rec["cobrado"])
probar("falta cobrar $8.000", 800_000, rec["falta_cobrar"])

desglose = {item["nombre"]: item for item in rec.get("productos_desglose", [])}
probar("hay desglose de empanadas", True, "Docena de Empanadas" in desglose)
probar("2 docenas vendidas", 2, desglose["Docena de Empanadas"]["cantidad"])
probar("total empanadas $24.000", 2_400_000, desglose["Docena de Empanadas"]["total"])
probar("hay desglose de pizza", True, "Pizza Muzza" in desglose)
probar("3 pizzas vendidas", 3, desglose["Pizza Muzza"]["cantidad"])
probar("total pizzas $24.000", 2_400_000, desglose["Pizza Muzza"]["total"])

print("\n==========================================")
print(f"Total: {bien} en verde, {fallas} fallas")
print("==========================================")
if fallas > 0:
    exit(1)
