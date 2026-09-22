"""Prueba de planes y límites (§11) y de la parte de MercadoPago que no necesita credenciales.

Corre contra https://miti.sole.ar. Lee los códigos de acceso de los logs por SSH.
"""

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
            texto = r.read().decode("utf-8", errors="replace")
            tipo = r.headers.get("content-type", "")
            return r.status, (json.loads(texto) if "json" in tipo and texto.strip() else texto)
    except urllib.error.HTTPError as e:
        texto = e.read().decode("utf-8", errors="replace")
        try:
            return e.code, json.loads(texto)
        except Exception:
            return e.code, texto


def codigos_recientes():
    return subprocess.run(
        SSH + ["cd /srv/miti/app/infra && sudo docker compose logs --since 10m api"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    ).stdout


def entrar_varios(nombres):
    """Crea varias cuentas de una: pide todos los códigos y lee el log una sola vez."""
    emails = {n: f"planes.{n.lower()}.{sello}@pruebas.miti.sole.ar" for n in nombres}
    for e in emails.values():
        st, _ = llamar("POST", "/acceso/codigo", cuerpo={"email": e})
        assert st == 204, f"pedir código {e}: {st}"
    time.sleep(2)
    log = codigos_recientes()
    tokens = {}
    for n, e in emails.items():
        cod = re.findall(rf"CÓDIGO DE ACCESO para {re.escape(e)}: (\d{{6}})", log)[-1]
        st, r = llamar("POST", "/acceso/verificar", cuerpo={
            "email": e, "codigo": cod, "nombre": n, "nacimiento": "1990-01-01"})
        assert st == 200, f"verificar {e}: {st} {r}"
        tokens[n] = r["token"]
    return tokens, emails


def rifa(token, nombre, hasta):
    st, c = llamar("POST", "/campanas", token, {
        "tipo": "rifa", "nombre": f"{nombre} {sello}",
        "rifa": {"desde": 0, "hasta": hasta, "precio": 100_000, "asignacion": "bolsa",
                 "sorteo": "externo", "si_no_se_vendio": "resortear"},
    })
    assert st == 201, (st, c)
    return c["id"]


def detalle(r):
    return r.get("detail", "") if isinstance(r, dict) else str(r)


print("\n--- PRUEBA FASE 7: PLANES Y LÍMITES ---")
t, emails = entrar_varios(["Ana", "Beto", "Caro", "Dani", "Eli", "Fede", "Gabi"])

print("\n== 1. Planes publicados ==")
st, planes = llamar("GET", "/planes", t["Ana"])
probar("GET /planes responde 200", 200, st)
por_codigo = {p["codigo"]: p for p in planes} if st == 200 else {}
probar("hay tres planes", ["gratis", "campana", "grande"], [p["codigo"] for p in planes])
probar("Campaña cuesta $15.000", 1_500_000, por_codigo.get("campana", {}).get("precio"))
probar("Campaña Grande cuesta $25.000", 2_500_000, por_codigo.get("grande", {}).get("precio"))
probar("gratis tiene publicidad", True, por_codigo.get("gratis", {}).get("publicidad"))
probar("Grande no limita las ventas", None, por_codigo.get("grande", {}).get("limite_ventas"))

print("\n== 2. Talonario: se controla al activar ==")
grande = rifa(t["Ana"], "Talonario de 200", 199)
st, r = llamar("PATCH", f"/campanas/{grande}/estado", t["Ana"], {"estado": "activa"})
probar("activar una rifa de 200 números en gratis → 402", 402, st)
probar("el mensaje dice el tamaño", True, "200" in detalle(r))

st, r = llamar("GET", f"/campanas/{grande}/plan", t["Ana"])
probar("GET /campanas/{id}/plan responde 200", 200, st)
probar("uso: talonario de 200", 200, r.get("uso", {}).get("numeros") if st == 200 else None)
probar("ofrece dos mejoras", ["campana", "grande"],
       [m["plan"]["codigo"] for m in r.get("mejoras", [])] if st == 200 else None)
probar("pasar a Grande cuesta $25.000 desde gratis", 2_500_000,
       r["mejoras"][1]["a_pagar"] if st == 200 else None)

chica = rifa(t["Ana"], "Talonario de 100", 99)
st, _ = llamar("PATCH", f"/campanas/{chica}/estado", t["Ana"], {"estado": "activa"})
probar("activar una rifa de 100 números en gratis → 200", 200, st)

print("\n== 3. Una sola campaña gratis en curso por creador ==")
otra = rifa(t["Ana"], "Segunda rifa", 9)
st, r = llamar("PATCH", f"/campanas/{otra}/estado", t["Ana"], {"estado": "activa"})
probar("activar una segunda campaña gratis → 402", 402, st)
probar("el mensaje explica que ya tiene otra", True, "ya tenés otra" in detalle(r))

print("\n== 4. Ventas de una rifa: ya no corta en 20 ==")
st, _ = llamar("POST", f"/campanas/{chica}/ventas", t["Ana"], {
    "numeros": list(range(0, 25)),
    "comprador": {"nombre": "Comprador grande", "telefono": "1100000000"},
    "destino_cobro": "efectivo",
})
probar("vender 25 números de una en gratis → 201", 201, st)
cortadas = 0
for i in range(25, 47):
    st, _ = llamar("POST", f"/campanas/{chica}/ventas", t["Ana"], {
        "numeros": [i],
        "comprador": {"nombre": f"Comprador {i}", "telefono": "1100000000"},
        "destino_cobro": "efectivo",
    })
    cortadas += st != 201
probar("22 ventas más, una por número: ninguna rechazada", 0, cortadas)

print("\n== 5. Integrantes: hasta 5 contando al administrador ==")
for n in ["Beto", "Caro", "Dani", "Eli"]:
    st, _ = llamar("POST", f"/campanas/{chica}/invitaciones", t["Ana"], {"email": emails[n]})
    probar(f"invitar a {n}", 201, st)
st, r = llamar("POST", f"/campanas/{chica}/invitaciones", t["Ana"], {"email": emails["Fede"]})
probar("el sexto integrante → 402", 402, st)
probar("el mensaje dice el tope", True, "5 integrantes" in detalle(r))

print("\n== 6. Productos: hasta 20 ventas ==")
st, c = llamar("POST", "/campanas", t["Gabi"], {"tipo": "productos", "nombre": f"Tortas {sello}"})
prod_camp = c["id"]
llamar("PATCH", f"/campanas/{prod_camp}/estado", t["Gabi"], {"estado": "activa"})
st, p = llamar("POST", f"/campanas/{prod_camp}/productos", t["Gabi"], {"nombre": "Torta", "precio": 500_000})
probar("crear producto", 201, st)
rechazadas = 0
for i in range(20):
    st, _ = llamar("POST", f"/campanas/{prod_camp}/ventas/productos", t["Gabi"], {
        "items": [{"producto_id": p["id"], "cantidad": 1}],
        "comprador": {"nombre": f"Cliente {i}", "telefono": "1100000000"},
        "destino_cobro": "efectivo", "entrega": "pedido",
    })
    rechazadas += st != 201
probar("20 ventas entran", 0, rechazadas)
st, r = llamar("POST", f"/campanas/{prod_camp}/ventas/productos", t["Gabi"], {
    "items": [{"producto_id": p["id"], "cantidad": 1}],
    "comprador": {"nombre": "Cliente 21", "telefono": "1100000000"},
    "destino_cobro": "efectivo", "entrega": "pedido",
})
probar("la venta 21 → 402", 402, st)

print("\n== 7. Mejora de plan ==")
st, r = llamar("POST", f"/campanas/{chica}/mejora", t["Beto"], {"plan": "campana"})
probar("un integrante que no es admin no puede pedir la mejora", 403, st)
st, r = llamar("POST", f"/campanas/{chica}/mejora", t["Ana"], {"plan": "gratis"})
probar("no se puede 'mejorar' al mismo plan", 409, st)
st, r = llamar("POST", f"/campanas/{chica}/mejora", t["Ana"], {"plan": "inexistente"})
probar("un plan que no existe → 404", 404, st)

st, estado = llamar("GET", f"/campanas/{chica}/plan", t["Ana"])
if estado.get("puede_pagar"):
    st, m = llamar("POST", f"/campanas/{chica}/mejora", t["Ana"], {"plan": "campana"})
    probar("con MercadoPago configurado, la mejora crea el pago", 201, st)
    probar("devuelve una URL de MercadoPago", True, "mercadopago" in (m.get("url_pago") or ""))
    probar("cobra $15.000", 1_500_000, m.get("importe"))
    st, compra = llamar("GET", f"/campanas/{chica}/compras/{m['compra_id']}", t["Ana"])
    probar("la compra queda pendiente hasta que se pague", "pendiente", compra.get("estado"))
else:
    st, m = llamar("POST", f"/campanas/{chica}/mejora", t["Ana"], {"plan": "campana"})
    probar("sin credenciales de MercadoPago → 503 con explicación", 503, st)

print("\n== 8. Webhook ==")
st, r = llamar("POST", "/pagos/mercadopago/webhook?type=merchant_order&data.id=1", cuerpo={})
probar("un aviso que no es de pago se ignora con 200", 200, st)
st, r = llamar("GET", "/pagos/vuelta?compra=x")
probar("la página de vuelta responde", 200, st)

print(f"\nResultado final planes: {bien} OK, {fallas} fallas.")
if fallas:
    raise SystemExit(1)
print("TODO EN VERDE")
