#!/usr/bin/env bash
# Despliega en el VPS la última versión de main.
#   Desde el VPS:  /srv/miti/app/infra/desplegar.sh
#   Desde la PC:   ssh -i ~/.ssh/oracle_ollama ubuntu@129.146.57.10 /srv/miti/app/infra/desplegar.sh
set -euo pipefail

cd /srv/miti/app
ANTES=$(git rev-parse --short HEAD)
git fetch --quiet origin main
git merge --ff-only --quiet origin/main
DESPUES=$(git rev-parse --short HEAD)
echo "código: $ANTES → $DESPUES"

cd infra
sudo docker compose up -d --build --remove-orphans

# La programación de copias viaja en el repositorio.
if ! cmp -s respaldo/miti-respaldos.cron /etc/cron.d/miti-respaldos; then
  sudo install -o root -g root -m 644 respaldo/miti-respaldos.cron /etc/cron.d/miti-respaldos
  echo "cron de respaldos actualizado"
fi

DOMINIO=$(grep -oP '^MITI_DOMINIO=\K.*' .env)
for i in $(seq 1 30); do
  if curl -fs -m 5 "https://$DOMINIO/salud" >/dev/null; then
    echo "salud: ok ($DOMINIO)"
    exit 0
  fi
  sleep 2
done
echo "salud: FALLA ($DOMINIO)" >&2
sudo docker compose ps
exit 1
