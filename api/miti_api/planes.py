"""Planes y límites (§11 de DEFINICION.md).

Todos los controles de límites pasan por acá, para que la regla viva en un
solo lugar. Los valores salen de la tabla `planes`, que se edita desde el
panel de administración sin sacar una versión nueva.

Qué mide cada límite:
- integrantes: activos + invitados de la campaña, contando al administrador.
- números: el TAMAÑO del talonario (hasta - desde + 1), no los vendidos. Se
  controla al activar la rifa, así se puede armar en borrador, ver que no
  alcanza y mejorar el plan antes de salir a vender.
- ventas: ventas confirmadas de una campaña de productos.
- campañas activas: por creador, las que están en curso (activa, cerrada o
  sorteada). Sólo el plan gratis lo limita.

Si se pasa un límite se contesta 402: la app lo reconoce y ofrece mejorar el plan.
"""

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from .modelos import Campana, Integrante, Plan, Venta

EN_CURSO = ("activa", "cerrada", "sorteada")


def _numero(n: int) -> str:
    return f"{n:,}".replace(",", ".")


async def plan_de(s: AsyncSession, campana: Campana) -> Plan:
    plan = await s.get(Plan, campana.plan)
    if plan is None:  # no debería pasar: hay una clave foránea
        raise HTTPException(status.HTTP_500_INTERNAL_SERVER_ERROR, f"plan desconocido: {campana.plan}")
    return plan


def _pasado(plan: Plan, que: str) -> HTTPException:
    return HTTPException(
        status.HTTP_402_PAYMENT_REQUIRED,
        f"el plan {plan.nombre} {que}. Mejorá el plan de la campaña para seguir",
    )


def tamano_talonario(campana: Campana) -> int:
    config = campana.config or {}
    desde, hasta = config.get("desde"), config.get("hasta")
    if desde is None or hasta is None:
        return 0
    return int(hasta) - int(desde) + 1


async def verificar_integrantes(s: AsyncSession, campana: Campana, nuevos: int = 1) -> None:
    plan = await plan_de(s, campana)
    if plan.limite_integrantes is None:
        return
    actuales = (
        await s.execute(
            select(func.count()).select_from(Integrante).where(
                Integrante.campana_id == campana.id,
                Integrante.estado.in_(("activo", "invitado")),
            )
        )
    ).scalar_one()
    if actuales + nuevos > plan.limite_integrantes:
        raise _pasado(plan, f"llega hasta {plan.limite_integrantes} integrantes")


async def verificar_talonario(s: AsyncSession, campana: Campana) -> None:
    if campana.tipo != "rifa":
        return
    plan = await plan_de(s, campana)
    if plan.limite_numeros is None:
        return
    tamano = tamano_talonario(campana)
    if tamano > plan.limite_numeros:
        raise _pasado(
            plan,
            f"admite talonarios de hasta {_numero(plan.limite_numeros)} números "
            f"y este tiene {_numero(tamano)}",
        )


async def verificar_ventas(s: AsyncSession, campana: Campana, nuevas: int = 1) -> None:
    """Sólo para productos: en las rifas el tope es el tamaño del talonario."""
    if campana.tipo != "productos":
        return
    plan = await plan_de(s, campana)
    if plan.limite_ventas is None:
        return
    actuales = (
        await s.execute(
            select(func.count()).select_from(Venta).where(
                Venta.campana_id == campana.id, Venta.estado == "confirmada"
            )
        )
    ).scalar_one()
    if actuales + nuevas > plan.limite_ventas:
        raise _pasado(plan, f"admite hasta {_numero(plan.limite_ventas)} ventas")


async def verificar_campanas_en_curso(s: AsyncSession, campana: Campana) -> None:
    """Al activar: el creador no puede tener más campañas en curso que las del plan."""
    plan = await plan_de(s, campana)
    if plan.limite_campanas_activas is None:
        return
    # Sólo cuentan las del mismo plan limitado: una campaña paga no ocupa el
    # lugar de la gratis.
    en_curso = (
        await s.execute(
            select(func.count()).select_from(Campana).where(
                Campana.creador_id == campana.creador_id,
                Campana.plan == plan.codigo,
                Campana.estado.in_(EN_CURSO),
                Campana.id != campana.id,
            )
        )
    ).scalar_one()
    if en_curso >= plan.limite_campanas_activas:
        raise _pasado(
            plan,
            f"permite {plan.limite_campanas_activas} campaña en curso a la vez "
            "y ya tenés otra",
        )


async def verificar_al_activar(s: AsyncSession, campana: Campana) -> None:
    await verificar_talonario(s, campana)
    await verificar_campanas_en_curso(s, campana)
