FROM python:3.13-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /srv/api
COPY pyproject.toml ./
RUN uv sync --no-dev --no-install-project

COPY alembic.ini ./
COPY migraciones ./migraciones
COPY miti_api ./miti_api

RUN useradd --system --uid 10001 miti
USER miti

EXPOSE 8000
CMD ["uvicorn", "miti_api.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
