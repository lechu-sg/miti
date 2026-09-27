"""Carga la rifa de Deluxe Femme en el servidor, para mostrar la app con datos reales.

Crea las diez participantes, la campaña de 200 números, las ventas con la plata
donde realmente está, un par de gastos, y cierra con la liquidación.

    python api/pruebas/cargar_demo_deluxe.py

Los mails inventados van en `demo.miti.sole.ar`, un dominio al que la API no le
manda correo. El de la administradora es real: le llega el código para entrar.
"""

import json
import os
import random
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://miti.sole.ar"
SSH = ["ssh", "-i", os.path.expanduser("~/.ssh/oracle_ollama"), "-o", "BatchMode=yes",
       "ubuntu@129.146.57.10"]

PRECIO = 500_000          # $5.000 por número, en centavos
DESDE, HASTA = 1, 200
ALIAS = "deluxe.femme.mp"

random.seed(7)  # para que dos corridas generen los mismos compradores

PARTICIPANTES = {
    "Euge":   ("Eugenia Ávila",      "eugenia.avila@live.com.ar"),
    "Agus":   ("Agustina Ferrari",   "agustina.ferrari@demo.miti.sole.ar"),
    "Aleska": ("Aleska Duarte",      "aleska.duarte@demo.miti.sole.ar"),
    "Anto":   ("Antonella Paz",      "antonella.paz@demo.miti.sole.ar"),
    "Cisne":  ("Cisne Molina",       "cisne.molina@demo.miti.sole.ar"),
    "Iri":    ("Irina Bravo",        "irina.bravo@demo.miti.sole.ar"),
    "Ivana":  ("Ivana Sosa",         "ivana.sosa@demo.miti.sole.ar"),
    "Jaque":  ("Jaqueline Ortiz",    "jaqueline.ortiz@demo.miti.sole.ar"),
    "Mara":   ("Mara Benítez",       "mara.benitez@demo.miti.sole.ar"),
    "Romi":   ("Romina Villalba",    "romina.villalba@demo.miti.sole.ar"),
}

VENDIDOS = {
    "Agus": [7, 30, 40, 88, 92, 107, 116, 145, 166, 181, 184],
    "Aleska": [10, 20, 21, 24, 38, 45, 64, 68, 72, 75, 82, 85, 94, 129, 147, 180, 183, 185, 190],
    "Anto": [23, 50, 69, 115, 127, 135, 137, 142],
    "Cisne": [31, 33, 55, 70, 73, 95, 100, 101, 105, 120, 126, 133, 155, 161, 171, 193],
    "Euge": [5, 11, 13, 26, 28, 29, 32, 34, 36, 39, 42, 43, 49, 51, 53, 57, 59, 60, 63, 65, 67,
             74, 77, 90, 93, 98, 99, 103, 113, 114, 117, 121, 123, 124, 125, 132, 138, 139, 143,
             144, 152, 157, 169, 172, 174, 182, 191, 192, 194, 195, 198, 199],
    "Iri": [2, 4, 18, 35, 66, 79, 83, 86, 134, 175],
    "Ivana": [3, 6, 15, 17, 19, 27, 41, 44, 48, 52, 58, 61, 78, 81, 84, 130, 196, 197],
    "Jaque": [9, 22, 37, 71, 76, 80, 91, 177, 178, 179, 187, 189],
    "Mara": [1, 14, 46, 54, 56, 62, 118, 122, 128, 158],
    "Romi": [8, 12, 16, 25, 47, 87, 106, 111, 112, 200],
}

NOMBRES = [
    "Carla Giménez", "Noelia Ferreyra", "Mariano Acosta", "Vanina Toledo", "Sergio Pereyra",
    "Lucía Maidana", "Daiana Rojas", "Brenda Cáceres", "Marisa Luna", "Gustavo Ibarra",
    "Natalia Quiroga", "Silvina Romero", "Fabián Ojeda", "Yamila Correa", "Rocío Medina",
    "Débora Farías", "Emanuel Vera", "Paola Gauna", "Sabrina Ledesma", "Claudia Rivero",
    "Micaela Suárez", "Jorgelina Ruiz", "Matías Godoy", "Elsa Barrios", "Karina Peralta",
    "Vanesa Ponce", "Julieta Cabrera", "Nadia Escobar", "Marcelo Aguirre", "Tamara Ojeda",
    "Susana Delgado", "Cintia Valdez", "Leandro Miranda", "Gabriela Ávalos", "Patricia Núñez",
    "Camila Sandoval", "Verónica Ramos", "Melina Olivera", "Adriana Cardozo", "Lorena Chávez",
    "Soledad Vargas", "Mónica Bustos", "Andrea Figueroa", "Ariel Domínguez", "Analía Salas",
    "Belén Herrera", "Cecilia Paredes", "Diego Maldonado", "Estefanía Ayala", "Flavia Coronel",
]


def telefono() -> str:
    return f"11{random.randint(2000, 6999)}{random.randint(1000, 9999)}"


def llamar(metodo, ruta, token=None, cuerpo=None, espera=60):
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


def ssh(comando):
    return subprocess.run(SSH + [comando], capture_output=True, text=True,
                          encoding="utf-8", errors="replace").stdout


def paso(texto):
    print(f"\n== {texto}")


def crear_cuentas() -> dict:
    paso("Cuentas de las participantes")
    for _, email in PARTICIPANTES.values():
        st, r = llamar("POST", "/acceso/codigo", cuerpo={"email": email})
        if st != 204:
            sys.exit(f"no se pudo pedir el código para {email}: {st} {r}")
    time.sleep(3)
    log = ssh("cd /srv/miti/app/infra && sudo docker compose logs --since 10m api")
    tokens = {}
    for apodo, (nombre, email) in PARTICIPANTES.items():
        hallados = re.findall(rf"CÓDIGO DE ACCESO para {re.escape(email)}: (\d{{6}})", log)
        if not hallados:
            sys.exit(f"no apareció el código de {email} en el registro")
        st, r = llamar("POST", "/acceso/verificar", cuerpo={
            "email": email, "codigo": hallados[-1], "nombre": nombre,
            "nacimiento": "1990-06-15"})
        if st != 200:
            sys.exit(f"no se pudo entrar como {nombre}: {st} {r}")
        tokens[apodo] = r["token"]
        print(f"   {nombre} ({apodo})")
    return tokens


def repartir_faltantes() -> dict:
    """Los números que no estaban en la lista se reparten entre las chicas."""
    vendidos = {n for nums in VENDIDOS.values() for n in nums}
    faltan = [n for n in range(DESDE, HASTA + 1) if n not in vendidos]
    apodos = list(VENDIDOS)
    reparto = {a: list(nums) for a, nums in VENDIDOS.items()}
    for i, numero in enumerate(faltan):
        reparto[apodos[i % len(apodos)]].append(numero)
    print(f"   faltaban {len(faltan)} números sin vender: se reparten entre las {len(apodos)}")
    return {a: sorted(nums) for a, nums in reparto.items()}


def plan_de_plata(reparto: dict) -> dict:
    """Dónde quedó la plata de cada número.

    - El 80% del total, en la cuenta principal (la de Euge, que es la titular).
    - 3 números en efectivo de Anto y 2 de Aleska.
    - El resto se lo quedó **cada una** en su billetera, en proporción a lo que vendió.
    """
    total = sum(len(v) for v in reparto.values())
    objetivo_principal = round(total * 0.80)
    destinos = {}

    efectivo = {"Anto": reparto["Anto"][:3], "Aleska": reparto["Aleska"][:2]}
    for apodo, numeros in efectivo.items():
        for n in numeros:
            destinos[(apodo, n)] = "efectivo"
    en_efectivo = sum(len(v) for v in efectivo.values())

    # Lo de Euge entra entero a la cuenta principal.
    de_euge = len(reparto["Euge"])
    for n in reparto["Euge"]:
        destinos[("Euge", n)] = "cuenta_principal"

    # Lo que las demás se quedan en la billetera, repartido en proporción.
    otras = {a: len(v) for a, v in reparto.items() if a != "Euge"}
    para_billetera = total - objetivo_principal - en_efectivo
    vendido_por_otras = sum(otras.values())
    queda = {a: round(para_billetera * n / vendido_por_otras) for a, n in otras.items()}
    # El redondeo puede sobrar o faltar: se ajusta sobre las que más vendieron.
    orden = sorted(otras, key=lambda a: -otras[a])
    i = 0
    while sum(queda.values()) != para_billetera:
        apodo = orden[i % len(orden)]
        queda[apodo] += 1 if sum(queda.values()) < para_billetera else -1
        i += 1

    for apodo, numeros in reparto.items():
        if apodo == "Euge":
            continue
        propios = queda[apodo]
        for n in numeros:
            if (apodo, n) in destinos:   # ya es efectivo
                continue
            if propios > 0:
                destinos[(apodo, n)] = "billetera"
                propios -= 1
            else:
                destinos[(apodo, n)] = "cuenta_principal"

    en_principal = sum(1 for d in destinos.values() if d == "cuenta_principal")
    print(f"   destino de la plata: {en_principal} números a la cuenta principal "
          f"({en_principal * 100 // total}%), {en_efectivo} en efectivo, "
          f"{total - en_principal - en_efectivo} en las billeteras · Euge vendió {de_euge}")
    return destinos


def vender(tokens, cid, reparto, destinos):
    paso("Ventas")
    nombre_i = 0
    ventas = 0
    for apodo, numeros in reparto.items():
        # Se agrupan los números consecutivos del mismo destino en una sola venta,
        # como pasa de verdad: alguien compra dos o tres números juntos.
        pendientes = list(numeros)
        while pendientes:
            destino = destinos[(apodo, pendientes[0])]
            grupo = []
            while pendientes and len(grupo) < random.choice([1, 1, 2, 2, 3]):
                if destinos[(apodo, pendientes[0])] != destino:
                    break
                grupo.append(pendientes.pop(0))
            comprador = NOMBRES[nombre_i % len(NOMBRES)]
            nombre_i += 1
            st, r = llamar("POST", f"/campanas/{cid}/ventas", tokens[apodo], {
                "numeros": grupo,
                "comprador": {"nombre": comprador, "telefono": telefono()},
                "destino_cobro": destino,
            })
            if st != 201:
                sys.exit(f"falló la venta de {grupo} por {apodo}: {st} {r}")
            ventas += 1
    print(f"   {ventas} ventas cargadas, {sum(len(v) for v in reparto.values())} números")


def confirmar_cobros(tokens, cid):
    paso("Euge confirma los cobros que entraron a su cuenta")
    st, movs = llamar("GET", f"/campanas/{cid}/movimientos?estado=pendiente", tokens["Euge"])
    confirmados = 0
    for m in movs or []:
        st, _ = llamar("POST", f"/campanas/{cid}/movimientos/{m['id']}/confirmar", tokens["Euge"])
        confirmados += st == 200
    print(f"   {confirmados} movimientos confirmados")


def gastos(tokens, cid):
    paso("Gastos")
    st, g1 = llamar("POST", f"/campanas/{cid}/gastos", tokens["Euge"], {
        "descripcion": "Impresión de los talonarios", "importe": 4_500_000, "origen": "bolsillo"})
    st2, g2 = llamar("POST", f"/campanas/{cid}/gastos", tokens["Cisne"], {
        "descripcion": "Flyers y publicidad en redes", "importe": 1_800_000, "origen": "bolsillo"})
    # El gasto de la administradora lo aprueba otra integrante; el de Cisne, Euge.
    st, movs = llamar("GET", f"/campanas/{cid}/movimientos?estado=pendiente", tokens["Aleska"])
    for m in movs or []:
        llamar("POST", f"/campanas/{cid}/movimientos/{m['id']}/confirmar", tokens["Aleska"])
    st, movs = llamar("GET", f"/campanas/{cid}/movimientos?estado=pendiente", tokens["Euge"])
    for m in movs or []:
        llamar("POST", f"/campanas/{cid}/movimientos/{m['id']}/confirmar", tokens["Euge"])
    print("   2 gastos cargados y aprobados ($45.000 y $18.000)")


def cerrar_y_liquidar(tokens, cid):
    paso("Cierre y liquidación")
    st, r = llamar("PATCH", f"/campanas/{cid}/estado", tokens["Euge"], {"estado": "cerrada"})
    if st != 200:
        sys.exit(f"no se pudo cerrar: {st} {r}")

    st, sim = llamar("GET", f"/campanas/{cid}/liquidacion/simulacion", tokens["Euge"])
    if st != 200:
        sys.exit(f"no se pudo simular: {st} {sim}")
    if sim.get("impedimentos"):
        print("   IMPEDIMENTOS:", sim["impedimentos"])
    for clave in ("cobrada", "vendida"):
        op = sim.get(clave) or {}
        print(f"   base {clave}: recaudado {op.get('recaudado')} · gastos {op.get('gastos')} "
              f"· neto {op.get('neto')} · parte {op.get('parte')}")

    st, liq = llamar("POST", f"/campanas/{cid}/liquidacion", tokens["Euge"], {"base": "cobrada"})
    if st != 201:
        sys.exit(f"no se pudo liquidar: {st} {liq}")
    print(f"   liquidada: neto {liq['neto']} · a cada una {liq['parte']}")
    st, transf = llamar("GET", f"/campanas/{cid}/liquidacion", tokens["Euge"])
    for t in (transf.get("transferencias") or []):
        print(f"   transferencia: {t.get('de_nombre')} → {t.get('a_nombre')} {t.get('importe')}")


def main():
    print("=== Cargando la rifa de Deluxe Femme ===")
    tokens = crear_cuentas()

    paso("Campaña")
    st, campana = llamar("POST", "/campanas", tokens["Euge"], {
        "tipo": "rifa",
        "nombre": "Rifa Deluxe Femme",
        "meta": 100_000_000,
        "alias_cuenta": ALIAS,
        "rifa": {"desde": DESDE, "hasta": HASTA, "precio": PRECIO, "asignacion": "bolsa",
                 "sorteo": "externo", "si_no_se_vendio": "resortear"},
    })
    if st != 201:
        sys.exit(f"no se pudo crear la campaña: {st} {campana}")
    cid = campana["id"]
    print(f"   campaña {cid}")

    # 10 integrantes y 200 números necesitan el plan grande.
    ssh("cd /srv/miti/app/infra && sudo docker compose exec -T db psql -U miti -d miti -c "
        f"\"update campanas set plan='grande' where id='{cid}'\"")
    print("   plan: Campaña Grande")

    paso("Invitaciones")
    for apodo, (nombre, email) in PARTICIPANTES.items():
        if apodo == "Euge":
            continue
        st, r = llamar("POST", f"/campanas/{cid}/invitaciones", tokens["Euge"], {"email": email})
        if st != 201:
            sys.exit(f"no se pudo invitar a {nombre}: {st} {r}")
        st, r = llamar("POST", f"/campanas/{cid}/invitacion", tokens[apodo], {"respuesta": "acepto"})
        if st != 200:
            sys.exit(f"{nombre} no pudo aceptar: {st} {r}")
    print(f"   {len(PARTICIPANTES)} integrantes")

    st, r = llamar("PATCH", f"/campanas/{cid}/estado", tokens["Euge"], {"estado": "activa"})
    if st != 200:
        sys.exit(f"no se pudo activar: {st} {r}")

    reparto = repartir_faltantes()
    vender(tokens, cid, reparto, plan_de_plata(reparto))
    confirmar_cobros(tokens, cid)
    gastos(tokens, cid)

    paso("Recaudación antes de cerrar")
    st, rec = llamar("GET", f"/campanas/{cid}/recaudacion", tokens["Euge"])
    if st == 200:
        print(f"   vendido {rec.get('vendido')} · cobrado {rec.get('cobrado')} "
              f"· falta cobrar {rec.get('falta_cobrar')}")
        for caja in (rec.get("cajas") or []):
            print(f"   caja {caja.get('tipo')} de {caja.get('titular_nombre')}: {caja.get('saldo')}")

    cerrar_y_liquidar(tokens, cid)
    print(f"\nListo. Campaña: {cid}")
    print("Entrá con eugenia.avila@live.com.ar para verla como administradora.")


if __name__ == "__main__":
    main()
