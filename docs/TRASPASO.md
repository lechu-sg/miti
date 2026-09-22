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

## 6. Estado actual (21/09/2026)

- **Fase 0 (infra, respaldos, correo): HECHA.** mail-tester da 10/10 y la restauración está probada.
- **Fase 1 (cuentas, campañas, invitaciones, cajas): HECHA y probada en el celular.**
- **Fase 2 (rifa, números, ventas, cobros, billete y comprobantes): HECHA.**
  - Migración 0003 aplicada en la base del VPS.
  - Pruebas de API: `prueba_fase1.py` (39/39 en verde) y `prueba_fase2.py` (55/55 en verde).

- **Campañas de Venta de Productos (Opción 1): HECHA y AJUSTADA (v0.3.1).**
  - Migración 0004 aplicada en el VPS (`productos`, items con producto/cantidad, columna `entrega` en `ventas`).
  - Endpoints implementados y probados: catálogo (`GET/POST/PATCH /campanas/{id}/productos`), venta de productos (`POST /campanas/{id}/ventas/productos`), actualización de entrega (`PATCH /campanas/{id}/ventas/{id}/entrega`), recaudación con desglose de productos.
  - Regla financiera unificada de cobros: si quien vende es el titular de la cuenta principal de la campaña (sea o no admin), cuando elige "cuenta principal" o "en mi billetera", el dinero ingresa a la caja `principal` y queda `confirmado` al instante sin requerir auto-aprobación. Si vende otro participante a la cuenta principal, queda `pendiente` requiriendo confirmación del titular de la cuenta.
  - Hojas modales (`MitiHoja`) ajustadas con `viewInsets.bottom` para que el teclado nunca tape los campos de texto ni los botones. Errores mostrados inline dentro de la hoja.
  - Pruebas de API: `prueba_fase1.py` (39/39), `prueba_fase2.py` (55/55), `prueba_productos.py` (43/43).
  - App móvil Flutter (v0.3.1+7): `flutter analyze` 0 issues, `flutter test` 3/3 en verde.
  - **Última APK publicada:** `https://miti.sole.ar/descargas/miti-0.3.1.apk` (hash SHA256 `D758EFC134864C17F761DEF27C2E34255593A18EAAA2023F1BFE45E07A9CF52F`).

- **Fase 3 (Modo sin señal, persistencia SQLite, Outbox y Sync bidireccional): HECHA (v0.4.0).**
  - Migración 0005 aplicada en el VPS (`sync_log` con secuencia, `campana_id`, `tabla`, `fila_id`, `op`, `datos` JSONB, índice en `campana_id, secuencia`).
  - Endpoints implementados y probados:
    - `POST /campanas/{id}/sync/push`: lote de operaciones con control de idempotencia por UUID, transaccionalidad, bloqueo de concurrencia y detección de conflictos (`numeros_ocupados`, `producto_inactivo`).
    - `GET /campanas/{id}/sync/pull`: descarga de snapshot completo (`snapshot=true`) para hidratación de base local y bajada incremental (`desde=cursor`) de cambios.
  - Persistencia local en SQLite (`app/lib/nucleo/base_local.dart`): réplicas de campañas, números, productos, ventas, estado de cursor y cola de operaciones pendientes (`outbox`).
  - Servicio de sincronización (`app/lib/nucleo/sincronizador.dart`): orquestador push/pull, expone `sincroProvider` con contadores de pendientes y conflictos.
  - Respaldo automático offline en `registrar_venta.dart` y `venta_productos.dart`: si se pierde la conexión, la venta se encola en outbox como "a confirmar" y se emite el billete provisional de inmediato.
  - Resolución interactiva de conflictos (`app/lib/pantallas/hoja_conflictos.dart`): permite reasignar otro número disponible o descartar la venta en conflicto, con aviso talonario `MitiAviso` en la campaña.
  - Pruebas de API contra `miti.sole.ar`:
    - `prueba_fase1.py`: 39/39 en verde.
    - `prueba_fase2.py`: 55/55 en verde.
    - `prueba_productos.py`: 43/43 en verde.
    - `prueba_sync.py`: 26/26 en verde (snapshot, push offline, idempotencia, conflicto simultáneo, resolución y pull incremental).
  - App móvil Flutter (v0.4.0+8): `flutter analyze` 0 issues, `flutter test` 5/5 en verde.
  - **Última APK publicada:** `https://miti.sole.ar/descargas/miti-0.4.0.apk` (hash SHA256 `6A3160863E0FB355BB6AFC45CBC60C4B741EF76E63B244495714CA5591156F58`).

- **Fase 4 (Cierre y Liquidación de Campaña en partes iguales §3.9): HECHA (v0.5.0).**
  - Migración 0006 aplicada en el VPS (`liquidaciones` con campana_id PK, base, neto, parte, recaudado, gastos, detalle JSONB, confirmada_por; `transferencias_liq` con de_usuario_id, a_usuario_id, importe, estado, comprobante_id).
  - Endpoints implementados y probados:
    - `GET /campanas/{id}/liquidacion/simulacion`: simulación comparativa de Base Cobrada vs Base Vendida, detección de impedimentos (cobros en cuenta principal sin aprobar, números reservados activos).
    - `POST /campanas/{id}/liquidacion`: confirmación de liquidación en base elegida (solo admin), pasa estado a `liquidada`, bloquea la campaña (`bloqueada=now()`), genera transferencias mínimas con algoritmo greedy y reparto determinista de centavos sobrantes. Rechaza ventas o modificaciones posteriores con 409 Conflict.
    - `GET /campanas/{id}/liquidacion`: consulta de liquidación confirmada y lista de transferencias del grupo.
    - `PATCH /campanas/{id}/liquidacion/transferencias/{id}`: actualización de estado de transferencia (`pagar` por deudor/admin, `confirmar` por acreedor/admin).
  - Algoritmo de transferencias mínimas:
    - Conservación estricta de saldo ($\sum B_i = 0$).
    - Complejidad $O(K \log K)$ greedy con heaps de deudores y acreedores.
    - Reparto determinista de centavos restantes: un centavo adicional a los primeros $Neto \pmod N$ integrantes ordenados por antigüedad (`alta asc, usuario_id asc`).
  - Pruebas de API contra `miti.sole.ar`:
    - `prueba_fase1.py`: 39/39 en verde.
    - `prueba_fase2.py`: 55/55 en verde.
    - `prueba_productos.py`: 43/43 en verde.
    - `prueba_sync.py`: 26/26 en verde.
    - `prueba_liquidacion.py`: 34/34 en verde (simulación de ambas bases, bloqueo por reserva activa, rechazo 409, confirmación 201, bloqueo de ventas post-liquidación, flujo de transferencias pendiente -> pagada -> confirmada).
  - App móvil Flutter (v0.5.0+9):
    - `PantallaLiquidacion`: modo simulación con alternancia Base Cobrada / Base Vendida, visualización de impedimentos y balances individuales; modo liquidada con sección destacada "Tus transferencias" para marcar transferencias pagadas y confirmar cobros recibidos.
    - Integración en `PantallaCampana`: botón "Cerrar campaña" para el admin, banners y accesos dinámicos según estado (`activa`, `cerrada`, `liquidada`).
    - `flutter analyze` 0 issues, `flutter test` 7/7 en verde (incluyendo `liquidacion_test.dart`).
  - **Última APK publicada:** `https://miti.sole.ar/descargas/miti-0.5.0.apk` (hash SHA256 `952EC33D4AE9EEEDBF88ABC65CB89091A0BEB3F0167D90782C47263E39B11746`).

- **Fase 5 (Entregas, Sorteo, Anulaciones y Exportación Excel/PDF): HECHA (v0.6.0).**
  - Migración 0008 aplicada en el VPS (`sorteos` con `campana_id PK, numero_sorteado, numero_ganador, premio, estado_resultado, ganador_nombre, ganador_telefono, vendedor_id, vendedor_nombre, venta_id, codigo_corto, creado_por, creado`).
  - Endpoints implementados y probados:
    - **Entregas entre cajas (§3.6):** `POST /campanas/{id}/entregas` (valida fondos disponibles de caja origen, crea `Movimiento(tipo="entrega")` pendiente de confirmación por el titular de la caja destino). Prohibida auto-confirmación (403).
    - **Anulación de ventas (§3.8):** `POST /campanas/{id}/ventas/{id}/anular` (motivo obligatorio, crea contra-movimiento de egreso de caja en estado pendiente). Aprobación cruzada por otro integrante activo; al confirmarse marca `venta.estado = 'anulada'` y libera los números vendidos a estado `'libre'`.
    - **Sorteo y Ganador (§3.3, §7.8):** `POST /campanas/{id}/sorteo` y `GET /campanas/{id}/sorteo` (carga número oficial de quiniela/lotería; busca automáticamente el ganador o aplica regla de negocio si no se vendió: siguiente vendido o desierto; pasa estado a `sorteada`).
    - **Exportación a Excel y PDF (§3.10, §7.5):** `GET /campanas/{id}/exportar/excel` (hojas Resumen, Cajas, Ventas, Gastos, Liquidación) y `GET /campanas/{id}/exportar/pdf` (informe formal estilizado con ReportLab, balance general, cuadro de cajas, desglose y firmas de conformidad de integrantes).
  - Pruebas de API contra `miti.sole.ar`:
- **Sorteos Múltiples y Edición de Premios (§3.3): HECHO (v0.6.1).**
  - Migración 0009 aplicada en el VPS (`api/migraciones/versions/0009_sorteos_multiples.py`):
    - Agrega columna `orden` (integer, default 1, not null).
    - Modifica la clave primaria de `sorteos` a una clave compuesta `(campana_id, orden)`.
  - Endpoints implementados y probados:
    - `PUT /campanas/{id}/premios`: modificación en cualquier momento (mientras la campaña no esté sorteada, liquidada ni archivada) de la cantidad y lista ordenada de premios. Solo admin (403 a otros).
    - `POST /campanas/{id}/sorteo`: soporte de múltiples premios en orden secuencial con `items: list[PremioSorteoEntrada]`. Determinación de ganadores con exclusión secuencial (un número ya ganador no vuelve a ganar en premios posteriores, pasando al siguiente vendido disponible o desierto según la regla configurada).
    - `GET /campanas/{id}/sorteo`: consulta de todos los premios y sus ganadores ordenados por `orden asc`.
  - Pruebas de API contra `miti.sole.ar`:
    - `prueba_fase5.py`: 47/47 en verde (edición de premios por admin, rechazo 403 a participantes, sorteo con 2 premios, adjudicación directa y circular wrap-around con exclusión de boletos ya premiados).
  - App móvil Flutter (v0.6.1+12):
    - `PantallaNuevaCampana`: lista dinámica de premios en campañas de números (1° Premio por defecto, botón "+ Agregar otro premio", botón de eliminar).
    - `HojaPremios` (`app/lib/pantallas/hoja_premios.dart`): modal para ver, agregar, renombrar o quitar premios durante la campaña activa/borrador/cerrada.
    - `PantallaCampana`: botón "Premios de la rifa (N)" para el admin con acceso directo a la edición.
    - `PantallaGanador` (`app/lib/pantallas/ganador.dart`):
      - Formulario de sorteo: carga de números oficiales para cada uno de los premios configurados con selector de regla si no fue vendido.
      - Tarjeta de ganadores multi-premio con diseño Talonario: lista de todos los premios, badges de número ganador, nombre, teléfono, vendedor y código de ticket.
      - Compartir en redes/WhatsApp: generación de tarjeta PNG multi-premio y texto detallado por cada premio.
    - `flutter analyze`: 0 issues.
    - `flutter test`: 10/10 en verde.
  - **Última APK publicada:** `https://miti.sole.ar/descargas/miti-0.6.1.apk`.

- **Correcciones de Estabilidad y UX en Sorteos, Gastos y Productos (v0.6.2): HECHO.**
  - **Auto-focus al agregar premio:** En `nueva_campana.dart` y `hoja_premios.dart`, al presionar "+ Agregar otro premio", se enfoca automáticamente el nuevo campo listo para escribir.
  - **Sorteo y Ganador (Pantalla en blanco corregida):** Eliminación de dynamic dispatch en `ganador.dart` (`MitiColores c, MitiTextos t`) y conversión estricta a `double` en `fontSize: 22.0`, evitando `TypeError` en tiempo de ejecución que dejaba la pantalla en blanco en release.
  - **Registrar Gasto (Blindaje de saldos):** En `hoja_gasto.dart` y `campana.dart`, tipado defensivo de `cajasRecaudacion` y saldos numéricos para evitar caídas runtime por formato de datos.
  - **Desglose de Productos Vendidos (Cuadro blanco corregido):** En `_FilaDesgloseProducto` de `campana.dart`, mapeo seguro a las claves `cantidad`/`cantidad_vendida` y `total`/`recaudado` con conversión `num.toInt()`, evitando caída por `null as int` en el listado de productos de campaña.
  - **Calidad de código:** `flutter analyze` 0 issues, `flutter test` 10/10 en verde.
- **Fase 6 (Recordatorios a deudores, Ranking, Muro de avisos y Push FCM): HECHO (v0.7.0).**
  - **Base de datos (Alembic 0010):**
    - Tabla `avisos` (`id PK, campana_id FK, autor_id FK, mensaje, fijado, creado, actualizado`).
    - Tabla `dispositivos` (`id PK, usuario_id FK, token_fcm, plataforma, modelo, app_version, ultimo_acceso`).
  - **Backend FastAPI:**
    - `GET, POST, DELETE /campanas/{id}/avisos`: Muro de avisos de campaña, con opción de fijado (`fijado=true`) y eliminación por autor o admin.
    - `GET /campanas/{id}/ranking`: Tabla de clasificación de ventas por participante (top ventas por cantidad de números o productos y total recaudado).
    - `GET /campanas/{id}/ventas?adeudadas=true`: Filtro directo para ventas con saldo pendiente de pago.
    - `POST /dispositivos/token`: Registro y rotación de tokens FCM por usuario y plataforma.
    - Módulo `push.py`: Despacho resiliente de notificaciones push con fallback a log si FCM no está configurado.
    - Pruebas de API contra `miti.sole.ar`: `api/pruebas/prueba_fase6.py` con **26/26 pruebas en verde**.
  - **App Flutter (v0.7.0+14):**
    - `app/lib/nucleo/recordatorio_deuda.dart`: Generador de mensajes personalizados de deuda con monto, alias de campaña, números/productos y enlace directo para enviar por WhatsApp (`SharePlus`).
    - `app/lib/pantallas/hoja_ranking.dart`: Tablero de clasificación con estética Talonario, podio destacado (🥇 Oro, 🥈 Plata, 🥉 Bronce) y barras proporcionales para el resto del equipo.
    - `app/lib/pantallas/muro_avisos.dart`: Canal de comunicados para integrantes, badges de fijado, diálogo de publicación para admin y eliminación.
    - `app/lib/pantallas/campana.dart`:
      - Tarjeta destacada `_TarjetaAvisoDestacado` en el inicio de campaña cuando hay comunicados vigentes.
      - Botones de acceso rápido "Ranking del equipo" y "Muro de avisos (N)".
      - Banner de alerta de cobros pendientes con listado de deudores y botón "RECORDAR" directo para enviar mensaje de WhatsApp.
    - Calidad y pruebas:
      - `flutter analyze`: 0 issues.
      - `flutter test`: 13/13 en verde (incluye `test/fase6_test.dart`).
  - **Última APK publicada:** `https://miti.sole.ar/descargas/miti-0.7.0.apk` (también en `https://miti.sole.ar/descargas/miti.apk`, SHA256 `b64a880f310efde40f6ea643384da9b757076a9f645e92d59a1496e85f7ac09b`).

- **Fase 7 · Parte 1 (Perfil, Selector de Tema, FLAG_SECURE, Legales y Baja de Cuenta): HECHO (v0.8.0).**
  - **Backend FastAPI:**
    - `DELETE /yo`: Baja de cuenta definitiva y derecho al olvido (Ley 25.326). Anonimiza irreversiblemente datos personales (`nombre = "Usuario eliminado"`, email disociado con tombstone hash), revoca todas las sesiones activas en la tabla `sesiones` y purga dispositivos FCM. Bloquea futuros accesos (401).
    - `PATCH /yo`: Permite actualizar el nombre de usuario desde la app.
    - `POST /acceso/salir-de-todos`: Cierre masivo de sesiones en todos los dispositivos.
    - Suite de prueba de API: `api/pruebas/prueba_fase7_perfil.py` con **12/12 pruebas en verde**.
  - **Plataforma Android Nativa:**
    - `app/android/app/src/main/kotlin/ar/sole/miti/MainActivity.kt`: Canal nativo `ar.sole.miti/seguridad` con método `setSecure(activa)` para activar o remover `WindowManager.LayoutParams.FLAG_SECURE`.
  - **App Flutter (v0.8.0+15):**
    - `app/lib/estado/ajustes.dart`: Providers `modoTemaProvider` (`sistema`, `claro`, `oscuro`) y `proteccionPantallaProvider` con persistencia en `FlutterSecureStorage`.
    - `app/lib/main.dart`: Configuración reactiva de `themeMode` en `MaterialApp` e inicialización de protección de pantalla.
    - `app/lib/pantallas/perfil.dart`: Pantalla completa de perfil con tarjeta de usuario, edición de nombre, copia rápida de email para invitaciones, selector de tema con chips Talonario, switch de `FLAG_SECURE`, enlaces a legales y zona de cierre/baja de cuenta con doble confirmación.
    - `app/lib/pantallas/legales.dart`: Términos y Condiciones (Miti como herramienta de registro), Política de Privacidad (Ley 25.326) y Botón de arrepentimiento (Res. SCI 424/2020).
    - `app/lib/pantallas/campanas.dart`: Acceso al perfil desde el avatar del usuario en la barra superior.
    - Pruebas y calidad:
      - `flutter analyze`: 0 issues.
      - `flutter test`: 17/17 pruebas en verde (incluye `test/perfil_test.dart`).
  - **Última APK publicada:** `https://miti.sole.ar/descargas/miti-0.8.0.apk` (también en `https://miti.sole.ar/descargas/miti.apk`, SHA256 `9b3c3a6d36a42634fad4df9f6eab8290f2d1a75bd88fee17569267a40ab507e0`).

- **Revisión de la fase 7 y cuatro huecos tapados (21/09/2026): HECHO.**
  - **Respaldo de los comprobantes.** pgBackRest sólo cubre PostgreSQL, así que los
    archivos de `/srv/miti/data/archivos` no tenían ninguna copia.
    `infra/respaldo/respaldo-archivos.sh` hace una completa semanal y una
    incremental diaria a Oracle, y una completa semanal a Backblaze, comprimidas
    con tar y cifradas con gpg usando **la misma contraseña que pgBackRest ya usa
    en ese destino** (repo1 / repo3): no hay una contraseña nueva que guardar.
    `infra/respaldo/prueba-restauracion-archivos.sh 1|3` baja la última cadena,
    la restaura y la compara con el disco; corre sola los días 4 y 5 de cada mes.
    Probado a mano en los dos destinos: 16 archivos, idénticos.
  - **Baja de cuenta.** `DELETE /yo` ahora borra también la fecha de nacimiento y
    se rechaza con 409 si la persona participa de una campaña sin liquidar o si
    le quedan transferencias de liquidación sin confirmar (si no, quedaba un
    "Usuario eliminado" debiendo o esperando plata). `prueba_fase7_perfil.py`: 16/16.
  - **Limpieza por retención (§9).** `python -m miti_api.limpieza` borra las
    campañas liquidadas o archivadas hace más de 6 meses con todo lo que cuelga
    de ellas, los archivos de comprobantes en disco, las carpetas huérfanas y los
    rastros de acceso viejos (códigos +30 días, envíos de correo +90 días).
    Se corre desde `infra/limpieza.sh` (con `--simulacion` sólo informa), todos
    los días a las 05:00 UTC. Probado de punta a punta con una campaña envejecida.
  - **Notificaciones push.** Estaban a medias: el servidor las registraba pero
    Firebase no estaba configurado, y la app **nunca pedía un token**. Ahora está
    todo conectado: en el servidor las credenciales entran por el secreto
    `/srv/miti/secrets/firebase.json`, el envío usa `send_each` en un hilo aparte
    y da de baja los tokens muertos; en la app `lib/nucleo/push.dart` pide permiso
    (Android 13+), saca el token y lo registra al entrar.
    **FALTA UN PASO DEL USUARIO** (ver abajo): sin el proyecto de Firebase las push
    siguen sin llegar, pero la app compila y anda igual.
  - **Pruebas contra el servidor tras estos cambios:** las nueve suites en verde
    (fase1 39, fase2 55, productos 43, sync 26, liquidación 34, gastos 33,
    fase5 47, fase6 26, perfil 16) = **319 pruebas, 0 fallas**.
    `flutter analyze` sin problemas y `flutter test` 17/17.
  - **Última APK publicada:** `https://miti.sole.ar/descargas/miti-0.8.1.apk`
    (también en `miti.apk`, SHA256 `5674b263db649aac5e5698a5b6e62edb0db7a05457bff8c594002f20acb6101a`).

- **Fase 7 · Parte 2 (planes y límites, MercadoPago, panel de administración, AdMob): HECHA (v0.9.0), 22/09/2026.**
  - **Migración 0011:** tabla `planes` (gratis / Campaña $15.000 / Campaña Grande $25.000),
    `compras_campana`, `usuarios.bloqueado`, `campanas.suspendida`, `administradores` y
    `admin_accesos`. Clave foránea `campanas.plan → planes.codigo`.
  - **Límites** (`api/miti_api/planes.py`, un solo lugar): integrantes, **tamaño del talonario al
    activar**, ventas sólo de productos, una campaña gratis en curso por creador. Contesta 402.
    **Arreglo:** antes a las rifas gratis se les aplicaba el tope de 20 ventas.
    Las ventas sin señal que pasan el tope quedan en conflicto `limite_plan`.
  - **MercadoPago** (`api/miti_api/mercadopago.py`, `rutas/pagos.py`): `GET /planes`,
    `GET /campanas/{id}/plan`, `POST /campanas/{id}/mejora` (sólo admin, cobra la diferencia),
    `POST /pagos/mercadopago/webhook` (valida `x-signature` si hay secreto; el estado real se
    trae siempre de la API de MP y se controla importe y moneda), `GET /campanas/{id}/compras/{id}`
    (si sigue pendiente, busca el pago por la referencia externa) y `/pagos/vuelta`.
    Credenciales en `/srv/miti/secrets/mercadopago.env` (`MP_ACCESS_TOKEN`, `MP_WEBHOOK_SECRET`);
    hoy **vacío**: la mejora contesta 503 y la app muestra "el cobro todavía no está habilitado".
  - **Panel `/admin`** (`api/miti_api/admin/`): código por email + TOTP (se enrola la primera vez),
    cookie firmada de 2 h, CSRF, sin JavaScript, CSP estricta. Métricas, usuarios (bloquear),
    campañas (suspender, cambiar plan a mano), planes (precios y límites en vivo), salud (copias,
    restauraciones, limpieza, correo, espacio, pagos raros) y accesos (auditoría).
    Alta: `docker compose run --rm --no-deps -T api python -m miti_api.admin.alta EMAIL`
    (`--baja`, `--reenrolar` si se pierde el celular).
  - **App:** pantalla "Plan de la campaña" (`pantallas/plan.dart`), un 402 ofrece mejorar, aviso
    de campaña suspendida, AdMob (`nucleo/publicidad.dart`) con los **ID de prueba de Google**.
    **Arreglo:** `plata()` mostraba "15.000 $" (formato es_AR de intl); ahora "$ 15.000".
    `MitiBoton` parte los textos largos en dos líneas.
  - **Pruebas:** `prueba_fase7_planes.py` 32/32, `prueba_fase7_admin.py` 41/41, y las nueve
    anteriores en verde. App: `flutter analyze` limpio, `flutter test` 22/22.

## 7. Pasos a seguir, en orden

0. **Pendiente del usuario para que las push funcionen** (nadie más puede hacerlo,
   hace falta su cuenta de Google):
   1. Crear un proyecto en la consola de Firebase y agregarle una app Android con
      el identificador `ar.sole.miti`.
   2. Bajar `google-services.json` y dejarlo en `app/android/app/`. **No va al
      repositorio.** Con ese archivo presente, el build lo toma solo.
   3. En Configuración del proyecto → Cuentas de servicio, generar una clave
      privada y subir ese JSON al VPS como `/srv/miti/secrets/firebase.json`
      (644, dentro de la carpeta 700), reemplazando el `{}` de ejemplo. Después
      `desplegar.sh` y probar una invitación: tiene que llegar la notificación.
0.b **Pendientes del usuario para cerrar la Fase 7** (necesitan sus cuentas):
   1. **Panel:** decir con qué email entra al panel; se lo da de alta con `miti_api.admin.alta`
      y entra en `https://miti.sole.ar/admin` (la primera vez enrola la app autenticadora).
   2. **MercadoPago (prueba):** en developers de MercadoPago → la aplicación → Credenciales de
      prueba, cargar con nano en `/srv/miti/secrets/mercadopago.env` la línea
      `MP_ACCESS_TOKEN=TEST-...`; en Webhooks, poner la URL
      `https://miti.sole.ar/pagos/mercadopago/webhook` con el evento "Pagos", copiar la clave
      secreta como `MP_WEBHOOK_SECRET=...`. Después `docker compose restart api` no hace falta
      (se lee en cada uso). Probar con un usuario comprador de prueba.
   3. **AdMob:** crear la app en AdMob y pasar el ID de la app y los de los bloques banner e
      intersticial. El de la app va en `app/android/admob.properties` (`ADMOB_APP_ID=...`) y los
      bloques al compilar: `--dart-define=ADMOB_BANNER=... --dart-define=ADMOB_INTERSTICIAL=...`.
1. **El usuario prueba la APK 0.8.0 en el celular**:
   - Abrir "Mi perfil" tocando el avatar en la esquina superior derecha del inicio.
   - Probar el cambio de tema entre **Automático**, **Claro** y **Oscuro** comprobando el cambio visual inmediato en toda la app.
   - Probar la opción de "Protección de pantalla" para verificar el bloqueo de capturas en Android.
   - Revisar las pantallas de Términos y Privacidad.
2. **Siguientes pasos de la Fase 7**:
   - Control de límites del plan gratuito (5 integrantes, 100 números o 20 ventas).
   - Integración de MercadoPago Checkout Pro para mejoras de campaña.
   - Panel web de administración en `/admin`.


