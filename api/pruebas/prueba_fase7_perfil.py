"""Prueba de Perfil, Cambio de Nombre, Cierre Global y Baja de Cuenta (Fase 7)."""

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
U1 = f"usuario.perfil.{sello}@pruebas.miti.sole.ar"

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


def entrar(email, nombre="Martín"):
    st, _ = llamar("POST", "/acceso/codigo", cuerpo={"email": email})
    if st != 204:
        raise RuntimeError(f"Fallo pedir codigo para {email}: {st}")
    time.sleep(1.5)
    cod = codigo_de(email)
    if not cod:
        raise RuntimeError(f"No se encontro codigo para {email}")
    st, resp = llamar("POST", "/acceso/verificar", cuerpo={
        "email": email, "codigo": cod, "nombre": nombre, "nacimiento": "1995-05-20"
    })
    if st != 200:
        raise RuntimeError(f"Fallo verificar para {email}: {st} {resp}")
    return resp["token"], resp["refresco"]


def main():
    print(f"\n--- INICIO PRUEBA FASE 7 (Perfil, Nombre, Salir de todos y Baja / DELETE /yo) ---")

    # 1. Registrar usuario
    t1, r1 = entrar(U1, "Martín Prueba")
    probar("Registro usuario U1 exitoso", True, bool(t1))

    # 2. Consultar perfil inicial
    st, perfil = llamar("GET", "/yo", token=t1)
    probar("GET /yo responde 200", 200, st)
    probar("Nombre inicial correcto", "Martín Prueba", perfil.get("nombre"))
    probar("Email correcto", U1, perfil.get("email"))

    # 3. Modificar nombre con PATCH /yo
    st, nuevo_perfil = llamar("PATCH", "/yo", token=t1, cuerpo={"nombre": "Martín Fierro Editado"})
    probar("PATCH /yo responde 200", 200, st)
    probar("Nuevo nombre actualizado", "Martín Fierro Editado", nuevo_perfil.get("nombre"))

    # 4. Salir de todos los dispositivos
    st, _ = llamar("POST", "/acceso/salir-de-todos", token=t1)
    probar("POST /acceso/salir-de-todos responde 204", 204, st)

    # 5. El refresh token r1 debería estar revocado
    st, _ = llamar("POST", "/acceso/refrescar", cuerpo={"refresco": r1})
    probar("Refrescar sesión revocada rechaza con 401", 401, st)

    # 6. Volver a entrar para obtener nueva sesión y probar baja
    t2, r2 = entrar(U1, "Martín Fierro Editado")
    probar("Re-ingreso exitoso", True, bool(t2))

    # 7. Con una campaña sin liquidar, la baja se rechaza (§ derecho al olvido
    #    vs. cuentas abiertas con el grupo).
    st, campana = llamar("POST", "/campanas", token=t2, cuerpo={
        "tipo": "rifa",
        "nombre": f"Baja bloqueada {sello}",
        "rifa": {"desde": 0, "hasta": 9, "precio": 100000,
                 "asignacion": "bolsa", "sorteo": "externo", "si_no_se_vendio": "resortear"},
    })
    probar("Campaña de prueba creada", 201, st)
    st, err = llamar("DELETE", "/yo", token=t2)
    probar("DELETE /yo con campaña sin liquidar rechaza con 409", 409, st)
    probar(
        "El mensaje nombra la campaña",
        True,
        "sin liquidar" in str(err.get("detail", "")) if isinstance(err, dict) else False,
    )

    # 7b. Archivada la campaña, la baja se puede hacer.
    st, _ = llamar("PATCH", f"/campanas/{campana['id']}/estado", token=t2,
                   cuerpo={"estado": "archivada"})
    probar("Campaña archivada para liberar la baja", 200, st)

    # 8. Eliminar cuenta con DELETE /yo
    st, _ = llamar("DELETE", "/yo", token=t2)
    probar("DELETE /yo responde 204 No Content", 204, st)

    # 8. Token t2 ahora debe ser rechazado inmediatamente con 401
    st, err = llamar("GET", "/yo", token=t2)
    probar("GET /yo con cuenta dada de baja rechaza con 401", 401, st)

    # 9. Refresh token r2 debe estar revocado
    st, _ = llamar("POST", "/acceso/refrescar", cuerpo={"refresco": r2})
    probar("Refrescar sesión de cuenta eliminada rechaza con 401", 401, st)

    print(f"\nResultado final: {bien} pasadas, {fallas} fallas.")
    if fallas == 0:
        print("TODO EN VERDE")
    else:
        exit(1)


if __name__ == "__main__":
    main()
