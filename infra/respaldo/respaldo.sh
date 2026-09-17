#!/usr/bin/env bash
# Copia de seguridad de la base de Miti con pgBackRest.
#   respaldo.sh completa    → copia completa en repo1 (semanal)
#   respaldo.sh diferencial → copia diferencial en repo1 (diaria)
#   respaldo.sh mensual     → copia completa en repo2 (se guardan 6)
# Deja el resultado en /srv/miti/backups/estado/<tipo>.txt y el detalle en logs/.
set -euo pipefail

TIPO="${1:?uso: respaldo.sh completa|diferencial|mensual}"
case "$TIPO" in
  completa)    ARGS=(--repo=1 --type=full) ;;
  diferencial) ARGS=(--repo=1 --type=diff) ;;
  mensual)     ARGS=(--repo=2 --type=full) ;;
  *) echo "tipo desconocido: $TIPO" >&2; exit 2 ;;
esac

BASE=/srv/miti/backups
mkdir -p "$BASE/logs" "$BASE/estado"
LOG="$BASE/logs/respaldo-$TIPO-$(date -u +%Y%m%dT%H%M%SZ).log"

cd /srv/miti/app/infra
if docker compose exec -T -u postgres db pgbackrest --stanza=miti "${ARGS[@]}" backup >"$LOG" 2>&1; then
  echo "OK $(date -u +%FT%TZ) $TIPO" > "$BASE/estado/$TIPO.txt"
else
  echo "ERROR $(date -u +%FT%TZ) $TIPO (ver $LOG)" > "$BASE/estado/$TIPO.txt"
  exit 1
fi

# Logs de más de 90 días fuera.
find "$BASE/logs" -name '*.log' -mtime +90 -delete
