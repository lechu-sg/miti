# Miti

App Android para administrar campañas de recaudación en grupo (números o productos) y liquidar el neto en partes iguales.

| Carpeta | Contenido |
|---|---|
| `docs/DEFINICION.md` | Reglas de negocio, modelo de datos, arquitectura, seguridad, legal y fases |
| `.claude/skills/diseno-miti/` | Sistema de diseño "Talonario" (obligatorio para cualquier pantalla) |
| `api/` | Backend FastAPI |
| `infra/` | Docker Compose, Caddy, PostgreSQL + pgBackRest, scripts del VPS |
| `app/` | App Flutter *(pendiente)* |

## Servidor de prueba

- `https://miti.sole.ar` — VPS Oracle A1 (arm64, Ubuntu 24.04, región Phoenix).
- El código vive en `/srv/miti/app` (clon de este repositorio con una deploy key de solo lectura).
- Los datos viven en `/srv/miti/data` y los secretos en `/srv/miti/secrets`; nada de eso está en el repositorio.

### Desplegar

Primero `git push` a `main`, y después:

```bash
ssh -i ~/.ssh/oracle_ollama ubuntu@129.146.57.10 /srv/miti/app/infra/desplegar.sh
```

### Copias de seguridad

- **Qué:** pgBackRest guarda el WAL de forma continua y hace copias completas y diferenciales en Object Storage (`miti-backups`).
- **Cuándo:** la programación está en `infra/respaldo/miti-respaldos.cron`.
- **Resultado:** el de la última ejecución queda en `/srv/miti/backups/estado/`.
- **Restauración:** la prueba corre sola cada mes; para correrla a mano, `sudo /srv/miti/app/infra/respaldo/prueba-restauracion.sh`.

### Reglas del servidor

- **No correr `netfilter-persistent save`:** con Docker andando, guarda sus reglas internas. El firewall se edita a mano en `/etc/iptables/rules.v4`.
- Un archivo montado en un contenedor no se edita con `sed -i`, o hay que reiniciar el contenedor después.
