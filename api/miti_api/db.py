"""Conexión a PostgreSQL."""

from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from .config import ajustes

motor = create_async_engine(
    ajustes().url_db,
    pool_size=5,
    max_overflow=5,
    pool_pre_ping=True,
    echo=False,
)

Sesion = async_sessionmaker(motor, expire_on_commit=False, class_=AsyncSession)


async def sesion() -> AsyncIterator[AsyncSession]:
    async with Sesion() as s:
        yield s
