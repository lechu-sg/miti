"""Prueba integral de Avisos del Muro, Ranking de Ventas y Tokens FCM (Fase 6)."""

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
U1 = f"admin.f6.{sello}@pruebas.miti.sole.ar"
U2 = f"vendedor.f6.{sello}@pruebas.miti.sole.ar"

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
            content_type = r.headers.get("content-type", "")
            return r.status, (json.loads(texto) if "json" in content_type and texto.strip() else texto)
    except urllib.error.HTTPError as e:
        texto = e.read().decode("utf-8", errors="replace")
        try:
            return e.code, json.loads(texto)
        except Exception:
            return e.code, texto


def codigo_de(email):
    salida = subprocess.run(
        SSH + ["cd /srv/miti/app/infra && sudo docker compose logs --since 5m api"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    ).stdout
    hallazgos = re.findall(rf"CÓDIGO DE ACCESO para {re.escape(email)}: (\d{{6}})", salida)
    return hallazgos[-1] if hallazgos else None


def login(email, nombre):
    llamar("POST", "/acceso/codigo", cuerpo={"email": email})
    time.sleep(0.5)
    cod = codigo_de(email)
    st, resp = llamar("POST", "/acceso/verificar", cuerpo={
        "email": email, "codigo": cod, "nombre": nombre, "nacimiento": "1995-05-15",
    })
    return resp["token"]


print("\n--- INICIO PRUEBA FASE 6 (Avisos, Ranking, Deudores y FCM) ---")

# 1. Login y usuarios
t1 = login(U1, "Administrador Miti")
t2 = login(U2, "Vendedor Estrella")

# 2. Registro de token de dispositivo FCM
st, disp = llamar("POST", "/dispositivos/token", token=t1, cuerpo={
    "fcm_token": f"token_fcm_test_{sello}_abc1234567890",
    "plataforma": "android",
    "version_app": "0.7.0",
})
probar("Registrar token FCM (200)", 200, st)
probar("Token FCM guardado correctamente", f"token_fcm_test_{sello}_abc1234567890", disp.get("fcm_token"))

# 3. Crear campaña
st, camp = llamar("POST", "/campanas", token=t1, cuerpo={
    "tipo": "rifa",
    "nombre": f"Rifa Solidaria {sello}",
    "rifa": {
        "desde": 1,
        "hasta": 100,
        "precio": 100000,
        "premios": ["1° Smart TV 55", "2° Canasta"],
    },
})
cid = camp["id"]
probar("Crear campaña rifa (201)", 201, st)

# Activar campaña
llamar("PATCH", f"/campanas/{cid}/estado", token=t1, cuerpo={"estado": "activa"})

# Invitar a U2 y aceptar
st_inv, _ = llamar("POST", f"/campanas/{cid}/invitaciones", token=t1, cuerpo={"email": U2})
st_acep, _ = llamar("POST", f"/campanas/{cid}/invitacion", token=t2, cuerpo={"respuesta": "acepto"})
probar("Invitar a U2 (201)", 201, st_inv)
probar("U2 acepta invitación (200)", 200, st_acep)

# 4. Muro de avisos: Publicar aviso como admin
st, av1 = llamar("POST", f"/campanas/{cid}/avisos", token=t1, cuerpo={
    "mensaje": "¡Bienvenidos al equipo! El sorteo se realizará por Lotería Nacional.",
    "fijado": True,
})
probar("Admin crea aviso fijado (201)", 201, st)
probar("Aviso fijado es True", True, av1.get("fijado"))
probar("Aviso contiene autor_nombre", "Administrador Miti", av1.get("autor_nombre"))

# Intentar publicar aviso como integrante no-admin (debe dar 403)
st, _ = llamar("POST", f"/campanas/{cid}/avisos", token=t2, cuerpo={
    "mensaje": "Hola soy integrante queriendo publicar",
})
probar("Integrante común no puede publicar aviso (403)", 403, st)

# Publicar segundo aviso (normal, no fijado)
st, av2 = llamar("POST", f"/campanas/{cid}/avisos", token=t1, cuerpo={
    "mensaje": "Recuerden pasar lo cobrado en efectivo antes del viernes.",
    "fijado": False,
})
probar("Admin crea segundo aviso (201)", 201, st)

# Listar avisos
st, lista_avisos = llamar("GET", f"/campanas/{cid}/avisos", token=t2)
probar("Listar avisos de campaña (200)", 200, st)
probar("Hay 2 avisos", 2, len(lista_avisos))
probar("El primer aviso es el fijado", True, lista_avisos[0]["fijado"])

# 5. Ventas: una al contado (U1) y una adeudada (U2)
st, v1 = llamar("POST", f"/campanas/{cid}/ventas", token=t1, cuerpo={
    "numeros": [1, 2, 3],
    "comprador": {"nombre": "Carlos Gómez", "telefono": "+5491100001111"},
    "destino_cobro": "efectivo",
})
probar("Venta 1 al contado por U1 (201)", 201, st)

st, v2 = llamar("POST", f"/campanas/{cid}/ventas", token=t2, cuerpo={
    "numeros": [10, 11],
    "comprador": {"nombre": "Lucía Deudora", "telefono": "+5491122223333"},
    "destino_cobro": "adeudado",
})
probar("Venta 2 adeudada por U2 (201)", 201, st)

# 6. Filtro de ventas adeudadas
st, ventas_adeudadas = llamar("GET", f"/campanas/{cid}/ventas?adeudadas=true", token=t1)
probar("Filtrar ventas adeudadas (200)", 200, st)
probar("Solo hay 1 venta adeudada", 1, len(ventas_adeudadas))
probar("La venta adeudada es de Lucía", "Lucía Deudora", ventas_adeudadas[0]["comprador"]["nombre"])

# 7. Ranking de ventas
st, rank = llamar("GET", f"/campanas/{cid}/ranking", token=t1)
probar("Consultar ranking de ventas (200)", 200, st)
items = rank.get("items", [])
probar("Ranking contiene 2 integrantes", 2, len(items))

# U1 vendió 3 números, U2 vendió 2 números
probar("Puesto 1 es U1 (3 números)", "Administrador Miti", items[0]["nombre"])
probar("Puesto 1 cantidad = 3", 3, items[0]["cantidad"])
probar("Puesto 2 es U2 (2 números)", "Vendedor Estrella", items[1]["nombre"])
probar("Puesto 2 cantidad = 2", 2, items[1]["cantidad"])

# 8. Eliminar aviso
aviso_id = av2["id"]
st, _ = llamar("DELETE", f"/campanas/{cid}/avisos/{aviso_id}", token=t1)
probar("Eliminar aviso (204)", 204, st)

st, avisos_restantes = llamar("GET", f"/campanas/{cid}/avisos", token=t1)
probar("Queda 1 solo aviso", 1, len(avisos_restantes))

print(f"\nResultado final: {bien} pasadas, {fallas} fallas.")
if fallas == 0:
    print("TODO EN VERDE")
else:
    exit(1)
