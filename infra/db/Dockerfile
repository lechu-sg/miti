# PostgreSQL 18 con pgBackRest (el repositorio PGDG ya viene configurado en la imagen oficial).
FROM postgres:18-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends pgbackrest ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /var/log/pgbackrest /var/spool/pgbackrest \
 && chown postgres:postgres /var/log/pgbackrest /var/spool/pgbackrest
