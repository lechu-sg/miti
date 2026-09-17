#!/usr/bin/env bash
# Prueba de restauración de Miti: restaura la última copia de repo1 (con todo el WAL
# archivado) en un contenedor descartable, levanta PostgreSQL y hace consultas de control.
# No toca la base en producción ni escribe en el repositorio (archive_mode=off).
set -euo pipefail

BASE=/srv/miti/backups
mkdir -p "$BASE/logs" "$BASE/estado"
LOG="$BASE/logs/restauracion-$(date -u +%Y%m%dT%H%M%SZ).log"
TMP=/srv/miti/data/prueba-restauracion
NOMBRE=miti-prueba-restauracion

limpiar() {
  docker rm -f "$NOMBRE" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap limpiar EXIT
limpiar
install -d -o 999 -g 999 -m 700 "$TMP"

if docker run --rm --name "$NOMBRE" \
    --network miti_salida_db \
    -u postgres \
    -v /srv/miti/secrets/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf:ro \
    -v "$TMP":/restauracion \
    --entrypoint bash miti-db:18 -c '
set -euo pipefail
D=/restauracion/datos
pgbackrest --stanza=miti --repo=1 --pg1-path=$D --archive-mode=off \
  --log-path=/tmp --spool-path=/tmp --process-max=2 restore
pg_ctl -D $D -l /tmp/pg.log -w -t 600 \
  -o "-c archive_mode=off -c port=5433 -c listen_addresses= -c unix_socket_directories=/tmp" start
for i in $(seq 1 120); do
  [ "$(psql -h /tmp -p 5433 -U miti -d miti -Atc "select pg_is_in_recovery()")" = "f" ] && break
  sleep 5
done
echo "en recuperacion: $(psql -h /tmp -p 5433 -U miti -d miti -Atc "select pg_is_in_recovery()")"
echo "tablas de usuario: $(psql -h /tmp -p 5433 -U miti -d miti -Atc "select count(*) from pg_stat_user_tables")"
echo "ultimo latido: $(psql -h /tmp -p 5433 -U miti -d miti -Atc "select max(ts) from ops.latido" 2>/dev/null || echo sin-tabla)"
echo "tamano: $(psql -h /tmp -p 5433 -U miti -d miti -Atc "select pg_size_pretty(pg_database_size(current_database()))")"
psql -h /tmp -p 5433 -U miti -d miti -Atc "select 1" >/dev/null
pg_ctl -D $D -m fast -w stop
' >"$LOG" 2>&1 && grep -q "en recuperacion: f" "$LOG"; then
  echo "OK $(date -u +%FT%TZ) restauracion" > "$BASE/estado/restauracion.txt"
else
  echo "ERROR $(date -u +%FT%TZ) restauracion (ver $LOG)" > "$BASE/estado/restauracion.txt"
  exit 1
fi
