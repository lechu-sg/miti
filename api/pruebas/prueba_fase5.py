"""Prueba integral de Entregas, Anulaciones, Sorteos y Exportación (Módulos finales V1)."""

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
U1 = f"ana.f5.{sello}@pruebas.miti.sole.ar"
U2 = f"beto.f5.{sello}@pruebas.miti.sole.ar"

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
            return r.status, (json.loads(texto) if "json" in content_type else texto)
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


def entrar(email, nombre):
    llamar("POST", "/acceso/codigo", cuerpo={"email": email})
    time.sleep(0.5)
    codigo = codigo_de(email)
    st, res = llamar("POST", "/acceso/verificar", cuerpo={
        "email": email, "codigo": codigo, "nombre": nombre, "nacimiento": "1995-05-10"
    })
    token = res["token"]
    st_yo, yo = llamar("GET", "/yo", token=token)
    return token, yo["id"]


print("\n== 1. Preparar usuarios y campaña ==")
t_ana, id_ana = entrar(U1, "Ana Admin")
t_beto, id_beto = entrar(U2, "Beto Vendedor")

st, c = llamar("POST", "/campanas", token=t_ana, cuerpo={
    "tipo": "rifa",
    "nombre": f"Rifa Sorteo {sello}",
    "moneda": "ARS",
    "rifa": {
        "precio": 500000,  # $5.000 por número
        "desde": 1,
        "hasta": 100,
        "asignacion": "bolsa",
        "sorteo": "externo",
        "si_no_se_vendio": "siguiente",
    },
})
probar("crear campaña", 201, st)
camp_id = c["id"]

# Ana invita a Beto
llamar("POST", f"/campanas/{camp_id}/invitaciones", token=t_ana, cuerpo={"email": U2})
llamar("POST", f"/campanas/{camp_id}/invitacion", token=t_beto, cuerpo={"respuesta": "acepto"})
llamar("PATCH", f"/campanas/{camp_id}/estado", token=t_ana, cuerpo={"estado": "activa"})

# Cajas
st, c_det = llamar("GET", f"/campanas/{camp_id}", token=t_ana)
cajas = c_det["cajas"]
caja_ef_ana = next(c["id"] for c in cajas if c["titular_id"] == id_ana and c["tipo"] == "efectivo")
caja_ef_beto = next(c["id"] for c in cajas if c["titular_id"] == id_beto and c["tipo"] == "efectivo")

print("\n== 2. Ventas iniciales ==")
# Ana vende números 1, 2 en efectivo ($10.000)
st, v_ana = llamar("POST", f"/campanas/{camp_id}/ventas", token=t_ana, cuerpo={
    "comprador": {"nombre": "Comprador Ana", "telefono": "1111111111"},
    "numeros": [1, 2],
    "destino_cobro": "efectivo",
})
probar("venta Ana $10.000", 201, st)

# Beto vende número 50 en efectivo ($5.000)
st, v_beto = llamar("POST", f"/campanas/{camp_id}/ventas", token=t_beto, cuerpo={
    "comprador": {"nombre": "Comprador Beto", "telefono": "2222222222"},
    "numeros": [50],
    "destino_cobro": "efectivo",
})
probar("venta Beto $5.000", 201, st)
v_beto_id = v_beto["id"]

# Beto vende número 77 en efectivo a "Ganador Pepe" ($5.000)
st, v_pepe = llamar("POST", f"/campanas/{camp_id}/ventas", token=t_beto, cuerpo={
    "comprador": {"nombre": "Pepe Ganador", "telefono": "3333333333"},
    "numeros": [77],
    "destino_cobro": "efectivo",
})
probar("venta Pepe número 77", 201, st)

print("\n== 3. Entregas entre cajas (§3.6) ==")
# Ana intenta entregar más de lo que tiene ($15.000 > $10.000) -> 409
st, _ = llamar("POST", f"/campanas/{camp_id}/entregas", token=t_ana, cuerpo={
    "caja_origen_id": caja_ef_ana,
    "caja_destino_id": caja_ef_beto,
    "importe": 1500000,
})
probar("entrega sin fondos da 409", 409, st)

# Ana intenta entregar desde la caja de Beto -> 403
st, _ = llamar("POST", f"/campanas/{camp_id}/entregas", token=t_ana, cuerpo={
    "caja_origen_id": caja_ef_beto,
    "caja_destino_id": caja_ef_ana,
    "importe": 200000,
})
probar("entrega de caja ajena da 403", 403, st)

# Ana entrega $4.000 a la caja de Beto
st, ent = llamar("POST", f"/campanas/{camp_id}/entregas", token=t_ana, cuerpo={
    "caja_origen_id": caja_ef_ana,
    "caja_destino_id": caja_ef_beto,
    "importe": 400000,
})
probar("crear entrega 201", 201, st)
probar("entrega estado inicial pendiente", "pendiente", ent["estado"])
ent_id = ent["id"]

# Ana no puede auto-aprobar su entrega (403)
st, _ = llamar("POST", f"/campanas/{camp_id}/movimientos/{ent_id}/confirmar", token=t_ana)
probar("Ana no puede auto-confirmar entrega (403)", 403, st)

# Beto (receptor) confirma la entrega (200)
st, ent_conf = llamar("POST", f"/campanas/{camp_id}/movimientos/{ent_id}/confirmar", token=t_beto)
probar("Beto confirma entrega (200)", 200, st)
probar("entrega confirmada", "confirmado", ent_conf["estado"])

# Verificar recaudación: Ana tenía $10.000, entregó $4.000 -> $6.000.
# Beto tenía $10.000, recibió $4.000 -> $14.000.
st, rec = llamar("GET", f"/campanas/{camp_id}/recaudacion", token=t_ana)
cajas_rec = {c["caja_id"]: c["confirmado"] for c in rec["cajas"]}
probar("caja Ana tiene $6.000", 600000, cajas_rec[caja_ef_ana])
probar("caja Beto tiene $14.000", 1400000, cajas_rec[caja_ef_beto])

print("\n== 4. Anulación de venta con contra-movimiento (§3.8) ==")
# Beto solicita anular la venta del número 50
st, sol_anul = llamar("POST", f"/campanas/{camp_id}/ventas/{v_beto_id}/anular", token=t_beto, cuerpo={
    "motivo": "Comprador se arrepintió antes del sorteo",
})
probar("solicitar anulación 201", 201, st)
probar("anulación estado inicial pendiente", "pendiente", sol_anul["estado"])
anul_id = sol_anul["id"]

# Beto no puede auto-aprobar su anulación (403)
st, _ = llamar("POST", f"/campanas/{camp_id}/movimientos/{anul_id}/confirmar", token=t_beto)
probar("Beto no puede auto-aprobar anulación (403)", 403, st)

# Ana (otro integrante) aprueba la anulación (200)
st, anul_conf = llamar("POST", f"/campanas/{camp_id}/movimientos/{anul_id}/confirmar", token=t_ana)
probar("Ana aprueba anulación de venta (200)", 200, st)

# Verificar que el número 50 volvió a estar LIBRE
st, nums = llamar("GET", f"/campanas/{camp_id}/numeros", token=t_ana)
n50 = next(n for n in nums if n["numero"] == 50)
probar("número 50 volvió a estar libre", "libre", n50["estado"])

# Verificar que la venta figura anulada
st, ventas_list = llamar("GET", f"/campanas/{camp_id}/ventas", token=t_ana)
v50_obj = next(v for v in ventas_list if v["id"] == v_beto_id)
probar("venta figura anulada", "anulada", v50_obj["estado"])

print("\n== 5. Sorteo y Ganador (§3.3 y §7.8) ==")
# Beto (no admin) intenta editar premios -> 403
st, _ = llamar("PUT", f"/campanas/{camp_id}/premios", token=t_beto, cuerpo={"premios": ["Intento"]})
probar("participante no puede editar premios 403", 403, st)

# Ana (admin) edita los premios de la campaña
st, camp_premios = llamar("PUT", f"/campanas/{camp_id}/premios", token=t_ana, cuerpo={
    "premios": ["Moto 110cc 0km", "Smart TV 50 pulgadas"],
})
probar("editar premios 200", 200, st)
probar("2 premios en config", 2, len(camp_premios["config"]["premios"]))
probar("primer premio config", "Moto 110cc 0km", camp_premios["config"]["premios"][0])
probar("segundo premio config", "Smart TV 50 pulgadas", camp_premios["config"]["premios"][1])

# Ana (admin) registra sorteo oficial:
# Premio 1: sale 77 (vendido a Pepe Ganador) -> ganador directo
# Premio 2: sale 12 (no vendido; siguiente vendido > 12 es 77 pero ya ganó; wrap around -> número 1 de Comprador Ana)
st, sort = llamar("POST", f"/campanas/{camp_id}/sorteo", token=t_ana, cuerpo={
    "items": [
        {"orden": 1, "numero_sorteado": 77, "premio": "Moto 110cc 0km"},
        {"orden": 2, "numero_sorteado": 12, "premio": "Smart TV 50 pulgadas"},
    ],
})
probar("registrar sorteo 201", 201, st)
probar("retorna 2 resultados de sorteo", 2, len(sort))

# Validar 1° premio
p1 = sort[0]
probar("p1 resultado ganador encontrado", "ganador_encontrado", p1["estado_resultado"])
probar("p1 número ganador es 77", 77, p1["numero_ganador"])
probar("p1 ganador es Pepe Ganador", "Pepe Ganador", p1["ganador_nombre"])
probar("p1 vendedor fue Beto Vendedor", "Beto Vendedor", p1["vendedor_nombre"])

# Validar 2° premio (exclusión de 77 que ya ganó -> siguiente disponible es 1)
p2 = sort[1]
probar("p2 resultado siguiente vendido", "siguiente_vendido", p2["estado_resultado"])
probar("p2 número ganador es 1 (no repite 77)", 1, p2["numero_ganador"])
probar("p2 ganador es Comprador Ana", "Comprador Ana", p2["ganador_nombre"])
probar("p2 vendedor fue Ana Administradora", "Ana Administradora", p2["vendedor_nombre"])

# Consultar sorteo registrado (GET devuelve lista)
st, sort_get = llamar("GET", f"/campanas/{camp_id}/sorteo", token=t_beto)
probar("Beto consulta sorteo 200", 200, st)
probar("GET devuelve 2 premios", 2, len(sort_get))
probar("mismo número ganador p1", 77, sort_get[0]["numero_ganador"])
probar("mismo número ganador p2", 1, sort_get[1]["numero_ganador"])

# Campaña pasa a sorteada
st, camp_act = llamar("GET", f"/campanas/{camp_id}", token=t_ana)
probar("campaña pasó a estado sorteada", "sorteada", camp_act["estado"])


print("\n== 6. Exportación a Excel y PDF (§3.10 y §7.5) ==")
# Descargar Excel
req_xls = urllib.request.Request(f"{API}/campanas/{camp_id}/exportar/excel")
req_xls.add_header("authorization", "Bearer " + t_ana)
with urllib.request.urlopen(req_xls, timeout=30) as r:
    probar("exportar excel HTTP 200", 200, r.status)
    probar("content-type excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", r.headers.get("content-type"))
    xls_data = r.read()
    probar("archivo excel tiene contenido (> 5 KB)", True, len(xls_data) > 5000)

# Descargar PDF
req_pdf = urllib.request.Request(f"{API}/campanas/{camp_id}/exportar/pdf")
req_pdf.add_header("authorization", "Bearer " + t_ana)
with urllib.request.urlopen(req_pdf, timeout=30) as r:
    probar("exportar pdf HTTP 200", 200, r.status)
    probar("content-type pdf", "application/pdf", r.headers.get("content-type"))
    pdf_data = r.read()
    probar("archivo pdf tiene cabecera %PDF", True, pdf_data.startswith(b"%PDF"))
    probar("archivo pdf tiene contenido (> 1 KB)", True, len(pdf_data) > 1000)

print(f"\n==========================================")
print(f"Resultado final Fase 5: {bien} OK, {fallas} fallas.")
print(f"==========================================")
if fallas > 0:
    exit(1)
