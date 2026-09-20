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
  - **Última APK publicada:** `https://miti.sole.ar/descargas/miti-0.6.2.apk` (también disponible en `https://miti.sole.ar/descargas/miti.apk`, SHA256 `A60BADB8D32E391D0DEA937B74F3AF3C823A5A155F33CA16C0CA600784F97C47`).

## 7. Pasos a seguir, en orden

1. **El usuario prueba la APK 0.6.2 en el celular**:
   - Crear o editar premios en rifa y comprobar que el cursor se posiciona inmediatamente en el nuevo campo listo para escribir.
   - Entrar a una campaña de productos y confirmar que el desglose de productos vendidos se ve correctamente sin ningún cuadro blanco.
   - Registrar un gasto desde la campaña y verificar que la hoja abra sin pantallas en blanco y permita registrar egreso de bolsillo o caja.
   - Entrar a "Sorteo y ganadores" en una rifa y verificar que el formulario cargue fluido y sin pantallas en blanco.
2. **Siguientes funciones del backlog**:
   - Notificaciones push con Firebase Cloud Messaging (FCM).


