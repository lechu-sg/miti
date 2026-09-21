#!/usr/bin/env bash
# Prueba de restauración de los comprobantes: baja la última cadena completa +
# incrementales del destino indicado, la descifra, la extrae en una carpeta
# temporal y la compara con lo que hay en disco.
#   prueba-restauracion-archivos.sh 1  → Oracle Object Storage
#   prueba-restauracion-archivos.sh 3  → Backblaze B2
set -euo pipefail

REPO="${1:?uso: prueba-restauracion-archivos.sh 1|3}"

ORIGEN=/srv/miti/data/archivos
BASE=/srv/miti/backups
SECRETOS=/srv/miti/secrets

mkdir -p "$BASE/logs" "$BASE/estado"
SELLO=$(date -u +%Y%m%dT%H%M%SZ)
LOG="$BASE/logs/prueba-archivos-repo$REPO-$SELLO.log"

export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required

case "$REPO" in
  1)
    export AWS_SHARED_CREDENTIALS_FILE="$SECRETOS/aws_credentials"
    export AWS_CONFIG_FILE="$SECRETOS/aws_config"
    ENDPOINT=https://axhwejrnfcr8.compat.objectstorage.us-phoenix-1.oraclecloud.com
    BUCKET=miti-backups
    CLAVE=$(grep -oP '^repo1-cipher-pass=\K.*' "$SECRETOS/pgbackrest.conf")
    ;;
  3)
    set -a; . "$SECRETOS/b2.env"; set +a
    export AWS_ACCESS_KEY_ID="$B2_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$B2_APP_KEY"
    ENDPOINT="https://${B2_ENDPOINT#https://}"
    BUCKET="$B2_BUCKET"
    CLAVE=$(grep -oP '^repo3-cipher-pass=\K.*' "$SECRETOS/pgbackrest.conf")
    ;;
  *) echo "repositorio desconocido: $REPO" >&2; exit 2 ;;
esac

TMP=$(mktemp -d)

fallar() {
  local detalle="${1:-ver $LOG}"
  echo "ERROR $(date -u +%FT%TZ) repo$REPO ($detalle)" > "$BASE/estado/prueba-archivos-repo$REPO.txt"
  /srv/miti/app/infra/respaldo/avisar.py "falló la prueba de restauración de comprobantes (repo$REPO)" \
    "$(printf 'La prueba de restauración de comprobantes en repo%s falló el %s.\n\n%s\n\nÚltimas líneas:\n%s' \
       "$REPO" "$(date -u +%FT%TZ)" "$detalle" "$(tail -15 "$LOG" 2>/dev/null)")" || true
  rm -rf "$TMP"
  exit 1
}
trap 'fallar' ERR

exec >>"$LOG" 2>&1

cd "$TMP"
mkdir -p restaurado

# La cadena útil es la última completa y todas las incrementales posteriores.
aws s3api list-objects-v2 --bucket "$BUCKET" --prefix archivos/ --endpoint-url "$ENDPOINT" \
    --query 'sort_by(Contents,&LastModified)[].Key' --output text \
  | tr '\t' '\n' | grep -v '^\(None\)\?$' > todas.txt

ULTIMA_COMPLETA=$(grep 'archivos-completa-' todas.txt | tail -1 || true)
[ -n "$ULTIMA_COMPLETA" ] || fallar "no hay ninguna copia completa en el destino"

CADENA=$(sed -n "/^${ULTIMA_COMPLETA//\//\\/}$/,\$p" todas.txt)
echo "cadena a restaurar:"; echo "$CADENA"

while read -r clave; do
  [ -n "$clave" ] || continue
  aws s3 cp "s3://$BUCKET/$clave" paquete.gpg --endpoint-url "$ENDPOINT" --only-show-errors
  gpg --batch --quiet --decrypt --passphrase "$CLAVE" paquete.gpg \
    | tar -xzf - -C restaurado --listed-incremental=/dev/null
  rm -f paquete.gpg
done <<< "$CADENA"

ORIG=$(find "$ORIGEN" -type f | wc -l)
REST=$(find restaurado -type f | wc -l)
echo "original: $ORIG archivos / restaurado: $REST archivos"

if ! diff -r "$ORIGEN" restaurado >/dev/null; then
  fallar "lo restaurado no coincide con $ORIGEN"
fi

echo "OK $(date -u +%FT%TZ) repo$REPO ($REST archivos, idénticos)" \
  > "$BASE/estado/prueba-archivos-repo$REPO.txt"
trap - ERR
rm -rf "$TMP"
find "$BASE/logs" -name 'prueba-archivos-*.log' -mtime +90 -delete
echo "listo"
