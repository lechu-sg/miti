# Traspaso — Miti (para retomar el trabajo con otro asistente)

Sos el asistente de desarrollo de **Miti** y retomás un trabajo empezado. Leé este archivo entero antes de tocar nada.

## 0. Cómo trabajar con el usuario

- Hablale en **español rioplatense** (vos, tenés) y con palabras simples. No es un usuario técnico en Flutter/Docker, pero sí sabe programar.
- **No supongas nada.** Si una regla de negocio no está en `docs/DEFINICION.md`, preguntá antes de implementar.
- Antes de cualquier acción difícil de deshacer (borrar datos, tocar el firewall, cambiar secretos, hacer `force push`), confirmá con el usuario.
- **Nunca muestres, copies ni subas al repositorio** el contenido de `/srv/miti/secrets/*`, las claves de cifrado de pgBackRest ni las de B2/OCI.
- Cada cambio tiene que quedar **probado** antes de decir que está listo: `flutter analyze` limpio, `flutter test` en verde, y la prueba de la API si tocaste el backend.
- Commits en español, chicos, uno por tema. Al final del mensaje agregá una línea `Co-Authored-By:` con el nombre del modelo que seas.

## 1. Qué es Miti

App Android (APK, sin Play Store) para administrar **campañas de recaudación en grupo**: rifas (números) o venta de productos.
- Cada integrante registra lo que vende.
- La app sabe dónde está la plata: en la cuenta principal, en la billetera virtual de cada uno o en efectivo.
- También registra los gastos (con aprobación) y los comprobantes de pago.
- Al final hay una **liquidación en partes iguales**, que cierra la campaña.

**Todo el detalle está en `docs/DEFINICION.md` (v0.2). Es la fuente de verdad.** Lo único pendiente de decidir ahí es el dominio definitivo; por ahora se usa `miti.sole.ar`.

## 2. Dónde está cada cosa

| Qué | Dónde |
|---|---|
| Código (PC Windows del usuario) | `D:\midesarrollo\miti` |
| Repositorio | `https://github.com/lechu-sg/miti`, rama `main` (el usuario ya hizo login con `gh`) |
| Definición completa | `docs/DEFINICION.md` |
| **Sistema de diseño "Talonario"** (obligatorio en toda pantalla) | `.claude/skills/diseno-miti/SKILL.md` |
| Backend FastAPI | `api/` (`miti_api/rutas/acceso.py`, `campanas.py`; `modelos.py`, `esquemas.py`, `seguridad.py`, `cripto.py`, `correo.py`) |
| Migraciones Alembic | `api/migraciones/versions/` (0001, 0002) |
| Prueba de punta a punta de la API | `api/pruebas/prueba_fase1.py` (39/39 en verde) + `api/pruebas/LEEME.md` |
| Infra | `infra/` (docker-compose, Caddyfile, `db/Dockerfile`, `desplegar.sh`, `respaldo/`) |
| App Flutter | `app/` (`lib/nucleo/`: tema, api, componentes, formato; `lib/estado/sesion.dart`; `lib/pantallas/`: ingreso, campanas, nueva_campana, campana) |

## 3. Entorno de la PC (Windows 10)

- Flutter 3.47.4 en `D:\dev\flutter` (`D:\dev\flutter\bin\flutter`). El SDK de Android también está en `D:\dev`.
- `JAVA_HOME` = `C:\Program Files\Android\Android Studio1\jbr` (también configurado con `flutter config --jdk-dir`).
- El plugin de Flutter necesita el NDK 28.2.13676358.
- Celular de prueba: Android 16.
- Con Git Bash en Windows, `curl -o /dev/null` falla si está `MSYS_NO_PATHCONV=1`. Por eso las pruebas están escritas en Python.

Comandos de la app (desde `D:\midesarrollo\miti\app`):
```
flutter analyze
flutter test
flutter build apk --release      # sale en build/app/outputs/flutter-apk/app-release.apk (~50 MB)
flutter run -d chrome            # solo para mirar pantallas; el producto es el APK
```

## 4. Servidor (VPS Oracle A1, arm64, Ubuntu 24.04)

- **Conexión:** `ssh -i ~/.ssh/oracle_ollama ubuntu@129.146.57.10`. La clave está en la PC del usuario, en `C:\Users\SERGIO\.ssh\oracle_ollama`.
- **Dominio:** `https://miti.sole.ar`. Chequeo de salud en `/salud`.
- **Código:** `/srv/miti/app`, un clon del repo con una deploy key de solo lectura.
- **Datos:** `/srv/miti/data`. La carpeta `pg` es de 999:999 con permisos 700.
- **Secretos:** `/srv/miti/secrets`, carpeta 700 de root. Adentro están `db_password`, `claves.env`, `smtp.env` y `pgbackrest.conf`.
- **Contenedores** (`infra/docker-compose.yml`):
  - `caddy`: TLS automático; además sirve `/descargas` desde `/srv/miti/descargas`.
  - `db`: PostgreSQL 18 con pgBackRest y archivado de WAL. No se expone afuera.
  - `api`: FastAPI, corre con el uid 10001.

### Desplegar (backend / infra)
1. Commit y `git push` a `main` desde la PC.
2. Correr:
   ```
   ssh -i ~/.ssh/oracle_ollama ubuntu@129.146.57.10 /srv/miti/app/infra/desplegar.sh
   ```
   El script hace fast-forward de main, rebuild de los contenedores y `alembic upgrade head`. También actualiza el cron si cambió y verifica `/salud`.
3. Correr la prueba de la API: `python api/pruebas/prueba_fase1.py`. Lee los códigos de acceso de los logs por SSH; los detalles están en `api/pruebas/LEEME.md`.

### Publicar una APK nueva
El archivo pesa ~50 MB y no se puede mandar por chat; se publica en el servidor.
1. `flutter build apk --release`
2. Subirla a `/srv/miti/descargas/miti-<versión>.apk`, con su `.sha256` al lado. Hay que usar `scp` a `/tmp` y después `sudo mv`, y dejarla legible.
3. Verificar que `https://miti.sole.ar/descargas/miti-<versión>.apk` devuelva 200.
4. Pasarle el link al usuario. Si se reusa el mismo nombre, se instala encima de la anterior.

Antes de publicar una versión nueva, subí `version:` en `app/pubspec.yaml`. La actual es 0.1.0.

### Reglas del servidor (IMPORTANTES)
- **NUNCA correr `netfilter-persistent save`** con Docker andando, porque guarda las cadenas de Docker y rompe el firewall. Las reglas se editan a mano en `/etc/iptables/rules.v4`.
- **No editar con `sed -i`** un archivo que está montado en un contenedor: se crea un inodo nuevo y el contenedor no ve el cambio. Hay que editarlo en el lugar o reiniciar el contenedor.
- **No hacer `chmod` a mano** en `/srv/miti/app` porque bloquea el `git merge`. Los bits de ejecución se ponen desde git con `git update-index --chmod=+x`.
- `smtp.env` y `claves.env` tienen que quedar en 644 dentro de la carpeta 700; si no, la api (uid 10001) no los puede leer.
- Respaldos: los programa `infra/respaldo/miti-respaldos.cron` (UTC).
  - Repositorios: repo1 = OCI diario (30 días), repo2 = OCI mensual (6), repo3 = Backblaze B2 (4).
  - Hay pruebas de restauración automáticas los días 2 y 3 de cada mes.
  - **No cambies la configuración de pgBackRest sin preguntar.** Con `repo-bundle=y` se cuida la cuota gratis de OCI de 50k pedidos por mes.

## 5. Decisiones técnicas ya tomadas (no cambiar sin consultar)

- **Plata:** siempre en **centavos enteros**. Los IDs son UUID y los puede generar el celular, para cuando funcione sin conexión.
- **Ingreso:** código de 6 dígitos por mail, JWT de 15 minutos y refresh rotativo con detección de reuso. La edad mínima es 13 años.
  - Si falta el nombre o la fecha de nacimiento en el alta, **el código NO se quema** (hace `rollback`). Esto tiene una prueba de regresión.
- **Email:** se guarda cifrado con AES-256-GCM y se busca por una huella HMAC.
- **Correo:** sale por el SMTP de `mail.sole.ar:465` desde `miti@sole.ar`.
  - Topes propios: 150 mails por hora, 100 destinatarios distintos por hora y 5 códigos por hora por dirección.
  - Al dominio `pruebas.miti.sole.ar` no se envía nada. Úsenlo para las pruebas, porque las direcciones `.test` se rechazan.
- **Plan gratis:** 1 campaña, 5 integrantes, 100 números o 20 ventas. El creador es el único que invita, y solo a usuarios que ya tienen cuenta.
- **App:** Flutter + Riverpod + http + flutter_secure_storage + intl.
  - El tema está en `lib/nucleo/tema.dart`, con los ThemeExtension `MitiColores` y `MitiTextos`. Se accede con `context.color` y `context.texto`.
  - Fuentes variables: Big Shoulders Display y Figtree, con `FontVariation('wght', n)`.

### Reglas de diseño que el usuario ya reclamó (no repetir el error)
- En modo oscuro, las líneas tienen que tener un contraste de al menos **3:1**. Los tokens oscuros vigentes están en la skill.
- Los errores van **siempre en letra blanca** sobre `sello` (rojo). Para avisar se usa `mostrarAviso(context, msg, error: true)`, que además baja el teclado.
- Dentro de las hojas (bottom sheets), el error se muestra **dentro de la hoja**, abajo del campo, para que el teclado no lo tape.
- Los campos de mail van en un `AutofillGroup`, con `autofillHints: [AutofillHints.email]`, sugerencias activadas, ícono @ y `textInputAction.send`.
- Nada de pantallas "genéricas de Material". Seguí la skill Talonario al pie de la letra: tokens, componentes (`MitiBoton`, `MitiTroquel`, `MitiTicket`, `MitiAviso`, `MitiIniciales`, `MitiChip`, `MitiVacio`) y la lista de prohibidos.

## 6. Estado actual (18/09/2026)

- **Fase 0 (infra, respaldos, correo): HECHA.** mail-tester da 10/10 y la restauración está probada.
- **Fase 1 (cuentas, campañas, invitaciones, cajas): HECHA y probada en el celular.**
- **Fase 2 (rifa, números, ventas, cobros, billete y comprobantes): HECHA.**
  - Migración 0003 aplicada en la base del VPS.
  - API ampliada con rutas para números (libres, reservados por 48h, vendidos), ventas con compradores cifrados, destinos de fondos (billetera, efectivo, cuenta principal), subida de comprobantes con hash y detección de duplicados, y métricas de recaudación.
  - Pruebas de API: `prueba_fase1.py` (39/39 en verde) y `prueba_fase2.py` (55/55 en verde).
  - App móvil actualizada con componentes Talonario: grilla interactiva de 10 columnas, selector de destino del dinero, registro de ventas, talón/billete para WhatsApp y pantalla para compartir disponibles en historias/post.
  - **Última APK publicada:** `https://miti.sole.ar/descargas/miti-0.2.1.apk` (hash SHA256 `3e62bf01...`).
    - En el envío del billete se exporta el PNG real del talón y se abre WhatsApp con la imagen adjunta y el texto predefinido.
    - Generador de imagen para redes con selección de imagen base desde la galería, recuadro de números personalizable y botón nativo para compartir en redes.
    - Accesos bien visibles al generador desde la pantalla de campaña y desde la grilla de números.

## 7. Pasos a seguir, en orden

1. **El usuario prueba la APK 0.2.1 en el celular**:
   - Vender un número y comprobar el envío del billete como imagen por WhatsApp.
   - Probar el generador de imagen de números disponibles con imagen de fondo propia y compartir en redes sociales.
   - Atender cualquier detalle de uso o diseño que reporte.
2. **Fase 3**, cuando el usuario dé el visto bueno a la APK 0.2.0:
   - Modo sin señal / offline: drift (SQLite) en el celular.
   - Cola de operaciones (outbox) con UUIDs de idempotencia.
   - Sincronización `POST /sync/push` y `GET /sync/pull?desde=<secuencia>`.
   - Resolución de conflictos en ventas de números simultáneas sin conexión.
