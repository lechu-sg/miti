#!/usr/bin/env bash
# Prueba de restauración de Miti: restaura la última copia del repositorio indicado
# (1 = Oracle diario, por defecto; 3 = Backblaze) con todo el WAL archivado, en un
# contenedor descartable, levanta PostgreSQL y hace consultas de control.
#   prueba-restauracion.sh [repo]
# No toca la base en producción ni escribe en el repositorio (archive_mode=off).
set -euo pipefail

REPO="${1:-1}"
case "$REPO" in 1|2|3) ;; *) echo "repo invalido: $REPO" >&2; exit 2 ;; esac
BASE=/srv/miti/backups
mkdir -p "$BASE/logs" "$BASE/estado"
LOG="$BASE/logs/restauracion-repo$REPO-$(date -u +%Y%m%dT%H%M%SZ).log"
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
    -e REPO="$REPO" \
    -v /srv/miti/secrets/pgbackrest.conf:/etc/pgbackrest/pgbackrest.conf:ro \
    -v "$TMP":/restauracion \
    --entrypoint bash miti-db:18 -c '
set -euo pipefail
D=/restauracion/datos
pgbackrest --stanza=miti --repo=$REPO --pg1-path=$D --archive-mode=off \
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
  echo "OK $(date -u +%FT%TZ) restauracion repo$REPO" > "$BASE/estado/restauracion-repo$REPO.txt"
else
  echo "ERROR $(date -u +%FT%TZ) restauracion repo$REPO (ver $LOG)" > "$BASE/estado/restauracion-repo$REPO.txt"
  exit 1
fi
