#!/usr/bin/env bash
# Copia de seguridad de los comprobantes (§3.5): imágenes y PDF que viven en
# /srv/miti/data/archivos. pgBackRest solo cubre PostgreSQL, así que estos
# archivos necesitan su propia copia o la base quedaría apuntando a la nada.
#
#   respaldo-archivos.sh diaria   → incremental a Object Storage de Oracle
#   respaldo-archivos.sh semanal  → completa a Oracle y reinicia la cadena
#   respaldo-archivos.sh externa  → completa a Backblaze B2
#
# Cada copia se comprime y se cifra con gpg usando la MISMA contraseña que
# pgBackRest ya usa en ese destino (repo1 para Oracle, repo3 para Backblaze),
# así no hay una contraseña nueva que guardar.
#
# Para restaurar:
#   gpg --decrypt archivo.tar.gz.gpg | tar -xzf - -C /destino
#   (primero la completa, después las incrementales en orden de fecha)
set -euo pipefail

TIPO="${1:?uso: respaldo-archivos.sh diaria|semanal|externa}"

ORIGEN=/srv/miti/data/archivos
BASE=/srv/miti/backups
SECRETOS=/srv/miti/secrets
SNAR="$BASE/archivos.snar"          # estado de la cadena incremental (tar)
DIAS_A_GUARDAR=45                   # en Oracle; en Backblaze se guardan 4 completas

OCI_ENDPOINT=https://axhwejrnfcr8.compat.objectstorage.us-phoenix-1.oraclecloud.com
OCI_BUCKET=miti-backups

mkdir -p "$BASE/logs" "$BASE/estado"
SELLO=$(date -u +%Y%m%dT%H%M%SZ)
LOG="$BASE/logs/archivos-$TIPO-$SELLO.log"

fallar() {
  echo "ERROR $(date -u +%FT%TZ) $TIPO (ver $LOG)" > "$BASE/estado/archivos-$TIPO.txt"
  /srv/miti/app/infra/respaldo/avisar.py "falló la copia de comprobantes ($TIPO)" \
    "$(printf 'La copia de comprobantes %s falló el %s.\n\nÚltimas líneas:\n%s' \
       "$TIPO" "$(date -u +%FT%TZ)" "$(tail -15 "$LOG" 2>/dev/null)")" || true
  exit 1
}
trap fallar ERR

exec 3>&1 4>&2
exec >>"$LOG" 2>&1

clave_de() {  # lee la contraseña de cifrado que pgBackRest ya usa en ese repositorio
  local repo="$1"
  local valor
  valor=$(grep -oP "^${repo}-cipher-pass=\K.*" "$SECRETOS/pgbackrest.conf" || true)
  [ -n "$valor" ] || { echo "falta ${repo}-cipher-pass en pgbackrest.conf"; return 1; }
  printf '%s' "$valor"
}

mkdir -p "$ORIGEN"

# Oracle (y Backblaze) rechazan el "chunked encoding" que la CLI de AWS usa
# por defecto desde la 2.23: sin esto la subida falla con NotImplemented.
export AWS_REQUEST_CHECKSUM_CALCULATION=when_required
export AWS_RESPONSE_CHECKSUM_VALIDATION=when_required

case "$TIPO" in
  diaria|semanal)
    # La semanal arranca una cadena nueva; la diaria continúa la última.
    if [ "$TIPO" = semanal ] || [ ! -f "$SNAR" ]; then
      rm -f "$SNAR"
      NIVEL=completa
    else
      NIVEL=incremental
    fi
    NOMBRE="archivos-$NIVEL-$SELLO.tar.gz.gpg"
    CLAVE=$(clave_de repo1)
    export AWS_SHARED_CREDENTIALS_FILE="$SECRETOS/aws_credentials"
    export AWS_CONFIG_FILE="$SECRETOS/aws_config"
    ENDPOINT="$OCI_ENDPOINT"
    BUCKET="$OCI_BUCKET"
    ;;
  externa)
    # A Backblaze siempre va completa, sin tocar la cadena de Oracle.
    NIVEL=completa
    NOMBRE="archivos-completa-$SELLO.tar.gz.gpg"
    CLAVE=$(clave_de repo3)
    # shellcheck disable=SC1091
    set -a; . "$SECRETOS/b2.env"; set +a
    export AWS_ACCESS_KEY_ID="$B2_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$B2_APP_KEY"
    unset AWS_SHARED_CREDENTIALS_FILE AWS_CONFIG_FILE
    ENDPOINT="$B2_ENDPOINT"
    BUCKET="$B2_BUCKET"
    ;;
  *) echo "tipo desconocido: $TIPO"; exit 2 ;;
esac

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; fallar' ERR
PAQUETE="$TMP/$NOMBRE"

# tar --listed-incremental deja en el .snar qué se llevó, para que la próxima
# incremental mande solo lo nuevo. La externa usa un .snar descartable.
if [ "$TIPO" = externa ]; then
  SNAR_USO="$TMP/externa.snar"
else
  SNAR_USO="$SNAR"
fi

tar --listed-incremental="$SNAR_USO" -czf - -C "$ORIGEN" . \
  | gpg --batch --yes --symmetric --cipher-algo AES256 \
        --passphrase "$CLAVE" --output "$PAQUETE"

TAMANO=$(stat -c %s "$PAQUETE")
echo "$(date -u +%FT%TZ) $NIVEL: $TAMANO bytes → s3://$BUCKET/archivos/$NOMBRE"

aws s3 cp "$PAQUETE" "s3://$BUCKET/archivos/$NOMBRE" --endpoint-url "$ENDPOINT" --only-show-errors

rm -rf "$TMP"
trap fallar ERR

# Limpieza: en Oracle se borra lo que pasó los 45 días (hay una completa por
# semana, así que siempre quedan varias cadenas enteras). En Backblaze se
# conservan las 4 completas más nuevas, igual que pgBackRest.
LIMITE=$(date -u -d "-$DIAS_A_GUARDAR days" +%Y-%m-%d)
VIEJAS=""
if [ "$TIPO" = externa ]; then
  VIEJAS=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix archivos/ \
      --endpoint-url "$ENDPOINT" --query 'sort_by(Contents,&LastModified)[].Key' --output text \
    | tr '\t' '\n' | grep -v '^\(None\)\?$' | head -n -4 || true)
elif [ "$TIPO" = semanal ]; then
  VIEJAS=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix archivos/ \
      --endpoint-url "$ENDPOINT" \
      --query "Contents[?LastModified<='${LIMITE}'].Key" --output text \
    | tr '\t' '\n' | grep -v '^\(None\)\?$' || true)
fi
if [ -n "$VIEJAS" ]; then
  while read -r vieja; do
    [ -n "$vieja" ] || continue
    echo "borrando $vieja"
    aws s3 rm "s3://$BUCKET/$vieja" --endpoint-url "$ENDPOINT" --only-show-errors
  done <<< "$VIEJAS"
fi

echo "OK $(date -u +%FT%TZ) $TIPO ($NIVEL, $TAMANO bytes)" > "$BASE/estado/archivos-$TIPO.txt"
find "$BASE/logs" -name 'archivos-*.log' -mtime +90 -delete
trap - ERR
echo "listo"
