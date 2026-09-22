"""Da de alta (o de baja) a un administrador del panel.

    python -m miti_api.admin.alta email@dominio          → alta
    python -m miti_api.admin.alta email@dominio --baja   → baja
    python -m miti_api.admin.alta email@dominio --reenrolar  → borra el TOTP (celular perdido)

La persona tiene que tener cuenta en la app. El segundo factor se enrola la
primera vez que entra al panel.
"""

import argparse
import asyncio

from sqlalchemy import select

from .. import cripto
from ..db import Sesion
from ..modelos import Administrador, Usuario


async def principal(email: str, baja: bool, reenrolar: bool) -> None:
    async with Sesion() as s:
        usuario = (
            await s.execute(
                select(Usuario).where(Usuario.email_huella == cripto.huella(cripto.normalizar_email(email)))
            )
        ).scalar_one_or_none()
        if usuario is None or usuario.baja:
            raise SystemExit(f"No hay una cuenta activa con {email}: primero tiene que entrar a la app.")
        admin = await s.get(Administrador, usuario.id)
        if baja:
            if admin:
                await s.delete(admin)
            print(f"{usuario.nombre} ya no es administrador.")
        elif reenrolar:
            if not admin:
                raise SystemExit("No es administrador.")
            admin.totp_cifrado = None
            print(f"Segundo factor borrado: {usuario.nombre} lo vuelve a activar al entrar.")
        else:
            if admin is None:
                s.add(Administrador(usuario_id=usuario.id))
            print(f"{usuario.nombre} es administrador. Que entre en /admin para activar el segundo factor.")
        await s.commit()


def main() -> None:
    p = argparse.ArgumentParser(description="Administradores del panel de Miti")
    p.add_argument("email")
    p.add_argument("--baja", action="store_true")
    p.add_argument("--reenrolar", action="store_true")
    a = p.parse_args()
    asyncio.run(principal(a.email, a.baja, a.reenrolar))


if __name__ == "__main__":
    main()
