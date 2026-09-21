#!/usr/bin/env bash
# Limpieza por retención (§9): borra las campañas liquidadas hace más de 6 meses
# y los rastros de acceso viejos. Corre en el contenedor de la api.
#   limpieza.sh              → borra
#   limpieza.sh --simulacion → solo informa
set -euo pipefail

BASE=/srv/miti/backups
mkdir -p "$BASE/logs" "$BASE/estado"
LOG="$BASE/logs/limpieza-$(date -u +%Y%m%dT%H%M%SZ).log"

cd /srv/miti/app/infra
if docker compose run --rm --no-deps -T api python -m miti_api.limpieza "$@" >"$LOG" 2>&1; then
  echo "OK $(date -u +%FT%TZ) $(tail -1 "$LOG")" > "$BASE/estado/limpieza.txt"
else
  echo "ERROR $(date -u +%FT%TZ) (ver $LOG)" > "$BASE/estado/limpieza.txt"
  /srv/miti/app/infra/respaldo/avisar.py "falló la limpieza por retención" \
    "$(printf 'La limpieza por retención falló el %s.\n\nÚltimas líneas:\n%s' \
       "$(date -u +%FT%TZ)" "$(tail -15 "$LOG")")" || true
  exit 1
fi

find "$BASE/logs" -name 'limpieza-*.log' -mtime +90 -delete
