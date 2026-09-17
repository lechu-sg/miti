import asyncio

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine

from miti_api.config import ajustes
from miti_api.modelos import Base

config = context.config
destino = Base.metadata


def offline() -> None:
    context.configure(url=ajustes().url_db, target_metadata=destino, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


def _migrar(conexion) -> None:
    context.configure(connection=conexion, target_metadata=destino, compare_type=True)
    with context.begin_transaction():
        context.run_migrations()


async def online() -> None:
    motor = create_async_engine(ajustes().url_db, pool_pre_ping=True)
    async with motor.connect() as conexion:
        await conexion.run_sync(_migrar)
    await motor.dispose()


if context.is_offline_mode():
    offline()
else:
    asyncio.run(online())
