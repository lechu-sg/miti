"""Segunda rifa de Deluxe Femme, esta **en curso**, para mostrar la app trabajando.

A diferencia de `cargar_demo_deluxe.py`, esta campaña queda activa: con números
libres (para la imagen de disponibles) y con tres compradores debiendo (para el
recordatorio que redacta la IA local).

    python api/pruebas/cargar_demo_en_curso.py
"""

import random
import sys

from cargar_demo_deluxe import (  # se reutiliza todo lo que ya existe
    DESDE,
    HASTA,
    NOMBRES,
    PARTICIPANTES,
    PRECIO,
    crear_cuentas,
    llamar,
    paso,
    ssh,
    telefono,
)

random.seed(21)

# Quién vende qué en esta: se venden 140 de 200, así quedan 60 libres en la grilla.
VENDIDOS = list(range(1, 90)) + list(range(100, 151))
ADEUDAN = [147, 148, 149]  # estos tres quedan sin pagar, para el recordatorio


def main():
    print("=== Rifa Deluxe Femme EN CURSO ===")
    tokens = crear_cuentas()
    apodos = [a for a in PARTICIPANTES if a != "Euge"]

    paso("Campaña")
    st, campana = llamar("POST", "/campanas", tokens["Euge"], {
        "tipo": "rifa",
        "nombre": "Rifa Deluxe Femme · Nacional",
        "meta": 100_000_000,
        "alias_cuenta": "deluxefemme",
        "rifa": {"desde": DESDE, "hasta": HASTA, "precio": PRECIO, "asignacion": "bolsa",
                 "sorteo": "externo", "si_no_se_vendio": "resortear"},
    })
    if st != 201:
        sys.exit(f"no se pudo crear: {st} {campana}")
    cid = campana["id"]
    ssh("cd /srv/miti/app/infra && sudo docker compose exec -T db psql -U miti -d miti -c "
        f"\"update campanas set plan='grande' where id='{cid}'\"")
    print(f"   campaña {cid} (plan grande)")

    paso("Invitaciones")
    for apodo in apodos:
        _, email = PARTICIPANTES[apodo]
        llamar("POST", f"/campanas/{cid}/invitaciones", tokens["Euge"], {"email": email})
        llamar("POST", f"/campanas/{cid}/invitacion", tokens[apodo], {"respuesta": "acepto"})
    llamar("PATCH", f"/campanas/{cid}/estado", tokens["Euge"], {"estado": "activa"})
    print(f"   {len(PARTICIPANTES)} integrantes · campaña activa")

    paso("Ventas")
    pendientes = list(VENDIDOS)
    nombre_i = 0
    ventas = 0
    turno = 0
    while pendientes:
        grupo = [pendientes.pop(0) for _ in range(min(random.choice([1, 1, 2, 2, 3]), len(pendientes) + 1)) if pendientes or True]
        grupo = [n for n in grupo if n is not None]
        apodo = ([*apodos, "Euge"])[turno % (len(apodos) + 1)]
        turno += 1
        adeuda = any(n in ADEUDAN for n in grupo)
        destino = "adeudado" if adeuda else random.choice(
            ["cuenta_principal", "cuenta_principal", "cuenta_principal", "billetera", "efectivo"])
        st, r = llamar("POST", f"/campanas/{cid}/ventas", tokens[apodo], {
            "numeros": grupo,
            "comprador": {"nombre": NOMBRES[nombre_i % len(NOMBRES)], "telefono": telefono()},
            "destino_cobro": destino,
        })
        nombre_i += 1
        if st != 201:
            sys.exit(f"falló la venta {grupo}: {st} {r}")
        ventas += 1
    print(f"   {ventas} ventas · {len(VENDIDOS)} números vendidos · "
          f"{HASTA - DESDE + 1 - len(VENDIDOS)} libres")

    paso("Euge confirma los cobros de su cuenta")
    st, movs = llamar("GET", f"/campanas/{cid}/movimientos?estado=pendiente", tokens["Euge"])
    for m in movs or []:
        llamar("POST", f"/campanas/{cid}/movimientos/{m['id']}/confirmar", tokens["Euge"])
    print(f"   {len(movs or [])} confirmados")

    st, rec = llamar("GET", f"/campanas/{cid}/recaudacion", tokens["Euge"])
    print(f"\n   cobrado {rec.get('cobrado')} · falta cobrar {rec.get('falta_cobrar')}")
    st, deudoras = llamar("GET", f"/campanas/{cid}/ventas?adeudadas=true", tokens["Euge"])
    for v in deudoras or []:
        print(f"   debe: {v['comprador']['nombre']} · {v['saldo_adeudado']} · números {v['numeros']}")
    print(f"\nListo. Campaña en curso: {cid}")


if __name__ == "__main__":
    main()
