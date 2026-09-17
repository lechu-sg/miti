# Miti — Documento de definición

> Versión 0.2 · 2026-09-17 · Estado: **definición cerrada (salvo el dominio definitivo), sin código**

---

## 1. Qué es Miti

App Android para que un **grupo** administre una **campaña de recaudación**, sea una rifa o una venta de productos. Cada integrante registra lo que vende y dónde quedó el dinero. Al cerrar, el neto se reparte **en partes iguales** y la liquidación queda registrada.

**Miti es una herramienta de registro.** No organiza sorteos, no vende números al público y no custodia ni mueve dinero de las campañas. Esta definición condiciona los textos, lo legal y la publicación: evitar la palabra "rifa" en la marca y en la ficha de la app, y usar "campaña", "números" y "sorteo".

### Público
Viajes de egresados, clubes, escuelas, ONGs y grupos de amigos. Lanzamiento solo en Argentina.

### Fuera del alcance de la V1
- Sección o acceso para compradores.
- Página pública de la campaña.
- Venta online y cobro dentro de la app.
- Lectura automática (OCR) de comprobantes.
- iOS y Play Store: la V1 se distribuye como **APK descargable**.
- Campañas mixtas (rifa y productos a la vez).
- Varias monedas dentro de una misma campaña.

---

## 2. Glosario

| Término | Significado |
|---|---|
| **Campaña** | Unidad de trabajo. Es de tipo `rifa` o `productos` y tiene **una moneda** (ARS en la V1). |
| **Creador / Administrador** | Quien crea la campaña. Invita, acepta y expulsa integrantes y **aprueba gastos**. Nada más lo diferencia. |
| **Integrante** | Usuario que aceptó la invitación. Ve todo lo mismo que el resto. |
| **Comprador** | Persona externa. Se guardan su nombre y teléfono; no usa la app. |
| **Caja** | Lugar donde hay dinero de la campaña: la *cuenta principal* (de un integrante), la *billetera* de cada integrante o el *efectivo* de cada integrante. |
| **Movimiento** | Asiento inmutable que mueve dinero entre cajas o lo registra. Se corrige con otro movimiento, nunca editando. |
| **Liquidación** | Cierre único: calcula la parte de cada uno y las transferencias para equilibrar. Después la campaña queda bloqueada. |

---

## 3. Reglas de negocio

### 3.1 Campaña
- **Estados:** `borrador → activa → cerrada → sorteada* → liquidada → archivada`. El estado marcado con * existe solo en las rifas.
- Una persona puede estar en **varias** campañas y cambia de una a otra desde el encabezado.
- **Meta** de recaudación opcional.
- Plan gratis: **1 campaña**, 5 integrantes, 100 números o 20 ventas (§11).

### 3.2 Integrantes
- Para unirse, primero hay que **registrarse** en Miti. El creador **busca** al usuario (por email exacto o escaneando su QR de perfil) y lo **invita**; el usuario **acepta** dentro de la app. No existen links de invitación: así la invitación no circula fuera del grupo.
- **Integrante que se va:** conserva su **parte completa** y sigue contando para el reparto. Antes de irse tiene que dejar su caja en cero (o decir a quién se la pasa).
- **Integrante expulsado** (lo decide el creador): el creador define **a qué caja pasa su dinero**. El expulsado queda **fuera de todo**: no cuenta para el reparto y pierde el acceso. Sus ventas siguen sumando a la campaña.
- **Creador que se va:** elige a su **reemplazo** entre los integrantes en el momento de irse. No puede irse sin elegirlo.
- Todos los integrantes ven lo mismo. **Excepción:** el **teléfono del comprador** solo lo ve quien hizo la venta; los demás ven nombre y apellido.

### 3.3 Rifa
- La campaña define el **rango** (por ejemplo 00–99, 000–999, 1–500) y un **precio único**.
- **Asignación:**
  - Por defecto, **bolsa común**: el primero que lo vende se lo queda.
  - Opcional, **talonarios**: bloques por integrante. Se pueden **pasar números** a otro integrante; el traspaso queda en el historial.
- **Reserva:** dura **48 h** y **exige conexión**. Al vencer, el número vuelve a estar libre.
- **Premios:** lista ordenada (1.º, 2.º…). Si un premio cuesta dinero, un integrante lo carga como **gasto**.
- **Sorteo:**
  - Por defecto, **externo** (por ejemplo, la Lotería Nacional de la fecha). Miti solo registra el resultado.
  - Opcional, **interno verificable:** antes de cerrar las ventas se publica el *hash* de una semilla. El sorteo usa esa semilla más un dato público posterior (por ejemplo, el número de la Lotería) y cualquiera puede recalcular el resultado.
- **Si el número ganador no se vendió**, la regla se elige al crear la campaña: se vuelve a sortear, el premio queda desierto o se pasa al siguiente número vendido.

### 3.4 Productos
- **Catálogo** con nombre y precio de venta; opcionalmente, foto.
- **Venta por encargo** con estados `pedido → entregado` (y `anulado`).
- El **costo** de la mercadería se registra como **gasto**.

### 3.5 Ventas y cobros
- Toda venta lleva comprador (**nombre y teléfono obligatorios**), el integrante que vendió, el importe y **dónde entró el dinero**:
  - **Cuenta principal:** queda *pendiente* hasta que el dueño de esa cuenta la **confirma**.
  - **Billetera propia** del vendedor: queda **confirmada** al registrarla.
  - **Efectivo propio** del vendedor: queda **confirmada** al registrarla.
  - **No cobrado todavía:** la venta queda *adeudada* y el comprador figura como deudor.
- Se admite **cobro parcial**; cada cobro es un movimiento.
- **Comprobante** opcional (imagen o PDF); lo sube el vendedor.
- **Duplicados:** se avisa si coincide el *hash* del archivo o el **número de operación** (si se cargó) con otro comprobante de la campaña.
- **Billete:** después de la venta se genera una **imagen** para mandarle al comprador (§8.2).

### 3.6 Cajas y movimientos entre cajas
- Cada integrante tiene dos cajas en cada campaña, **billetera** y **efectivo**, y uno de ellos es además dueño de la **cuenta principal**.
- **Entregas entre cajas** (por ejemplo, Martín le pasa a Laura $40.000 en efectivo): quedan *pendientes* hasta que el **receptor confirma**. Mientras tanto, el dinero sigue contando como de quien lo entregó.
- La pantalla **"Dónde está la plata"** muestra, por integrante, cuánto hay en su billetera, cuánto en efectivo y el total.

### 3.7 Gastos
- Los carga **cualquier integrante**, con **descripción** obligatoria, importe y comprobante opcional.
- **Origen del dinero:**
  - **Una caja:** al aprobarse, sale de esa caja.
  - **El bolsillo del integrante:** al aprobarse, la campaña le **debe** ese importe, que se le **reintegra** en la liquidación.
- **Todo gasto requiere la aprobación del administrador**, que puede aprobarlo o rechazarlo con un motivo.
- **Los gastos del propio administrador** los aprueba **cualquier otro integrante**: nadie se aprueba a sí mismo.
- No se carga un gasto a nombre de otro integrante.

### 3.8 Correcciones y anulaciones
- **Nada se borra.** Una venta, un cobro o un gasto se **anula** con un motivo, y la anulación genera un contra-movimiento.
- **Anular o corregir una venta requiere la aprobación de otro integrante** (cualquiera, pero distinto de quien la pide).
- **Historial** visible para todos: quién hizo qué y cuándo.

### 3.9 Liquidación
Hay **una sola** liquidación por campaña y, una vez confirmada, la campaña queda **bloqueada**. Antes de liquidar no puede quedar ningún movimiento pendiente de aprobar.

**Dos bases para elegir.** Miti muestra las dos y el administrador elige una al cerrar:
- **Base cobrada:** se reparte solo lo cobrado.
- **Base vendida:** se reparte también lo adeudado. La deuda de cada comprador queda a cargo del integrante que vendió: la cuenta como dinero que ese integrante ya tiene.

**Definiciones:**
- `N` = integrantes que cuentan para el reparto: todos, incluidos los que se fueron; los expulsados no.
- `G` = gastos aprobados (desde cajas y desde bolsillos).
- `Neto = Base − G`.
- `S = Neto / N` = parte de cada uno.
- `H_i` = dinero de la campaña en poder del integrante *i* (sus cajas, más la cuenta principal si es el dueño, más lo adeudado si la base es la vendida).
- `R_i` = gastos que *i* pagó de su bolsillo.

**Cálculo:**
- Saldo de cada integrante: `B_i = H_i − (S + R_i)`.
  - `B_i > 0`: tiene que transferir ese importe.
  - `B_i < 0`: tiene que recibir ese importe.
  - La suma de todos los `B_i` es siempre cero.
- **Transferencias mínimas:** se emparejan deudores con acreedores con un algoritmo *greedy* (el mayor deudor paga al mayor acreedor), que como máximo genera `N−1` transferencias.
- **Redondeo:** todos los importes se guardan en **centavos enteros**. El resto de la división se asigna de forma determinística y visible.
- El reparto se hace **de verdad**: cada transferencia sugerida se marca como *hecha* (con comprobante opcional), el receptor la confirma y todo queda registrado.

---

## 4. Modelo de datos (borrador)

**Convenciones:**
- PostgreSQL 18.
- IDs `uuid` v7, **generados en el celular** para que la app pueda crear registros sin señal.
- Importes en `bigint` (centavos).
- Marcas de tiempo `timestamptz` en UTC.
- Toda tabla de campaña lleva `campana_id` y tiene *row-level security*.

```
usuarios            id, email (cifrado + hash para buscar), nombre, telefono (cifrado),
                    google_sub, totp_secreto (cifrado), creado, baja
dispositivos        id, usuario_id, fcm_token, plataforma, version_app, ultimo_uso
sesiones            id, usuario_id, dispositivo_id, refresh_hash, expira, revocada

campanas            id, tipo(rifa|productos), nombre, moneda, meta, estado,
                    creador_id, plan_id, imagen_fondo, config (jsonb), creada, bloqueada
integrantes         campana_id, usuario_id, rol(admin|integrante), estado(invitado|activo|
                    retirado|expulsado), cuenta_en_reparto (bool), alta, baja
cajas               id, campana_id, tipo(principal|billetera|efectivo), titular_id

-- rifa
numeros             campana_id, numero, estado(libre|reservado|vendido),
                    talonario_de (usuario), reserva_vence, venta_id, version
premios             id, campana_id, orden, descripcion
sorteos             campana_id, modo(externo|interno), semilla_hash, semilla,
                    dato_publico, resultado (jsonb), regla_no_vendido

-- productos
productos           id, campana_id, nombre, precio, foto, activo

compradores         id, campana_id, nombre (cifrado), telefono (cifrado), creado_por
ventas              id, campana_id, vendedor_id, comprador_id, importe, estado
                    (pendiente_sync|confirmada|anulada), entrega(pedido|entregado),
                    creada_en_dispositivo, sincronizada
venta_items         venta_id, numero | producto_id + cantidad, precio_unit

movimientos         id, campana_id, tipo(cobro|entrega|gasto|reintegro|liquidacion|anulacion),
                    caja_origen, caja_destino, importe, estado(pendiente|confirmado|rechazado),
                    requiere_aprobacion_de, aprobado_por, motivo, venta_id, anula_a,
                    comprobante_id, creado_por, creado
comprobantes        id, campana_id, objeto_storage, sha256, nro_operacion, mime, tamano,
                    clave_cifrada
gastos              id, campana_id, movimiento_id, descripcion, origen(caja|bolsillo)
liquidaciones       campana_id, base(cobrada|vendida), neto, parte, detalle (jsonb), confirmada
transferencias_liq  id, campana_id, de_id, a_id, importe, estado, comprobante_id

historial           id, campana_id, actor_id, accion, objeto, antes, despues, ts   (solo inserción)
notificaciones      id, usuario_id, tipo, payload, leida
sync_log            campana_id, secuencia (bigserial), tabla, fila_id, op   → cursor de sincronización

-- control (plataforma)
planes, compras_campana (MercadoPago), avisos_admin, bloqueos, metricas_diarias
```

**Saldos:** no se guardan. Se calculan a partir de `movimientos` confirmados, con vistas materializadas si hiciera falta.

---

## 5. Sincronización sin señal

1. **En el celular:** SQLite (con `drift`) guarda una copia de cada campaña del usuario y una **cola de operaciones** (outbox).
2. **Cada operación** lleva un `uuid` propio que funciona como **clave de idempotencia**. Si se reenvía, el servidor no la duplica.
3. **Subida:** `POST /sync/push` manda las operaciones en orden. El servidor valida permisos y reglas y responde una por una: `ok`, `conflicto` o `rechazada`.
4. **Bajada:** `GET /sync/pull?desde=<secuencia>` devuelve los cambios de la campaña desde el último cursor.
5. **Rifas:**
   - Una venta hecha sin señal queda como **"a confirmar"** en el celular.
   - Si al sincronizar el número **ya estaba vendido o reservado**, el servidor responde `conflicto`, y la app pide **elegir otro número libre** o **cancelar** la venta.
   - Reservar **exige conexión**.
   - El servidor bloquea la fila (`SELECT … FOR UPDATE`) para que dos ventas simultáneas del mismo número no puedan confirmarse las dos.
6. **Aprobaciones, confirmaciones y liquidación** exigen conexión: dependen del estado real.
7. **Notificaciones push** avisan de cambios y la app hace un *pull* en segundo plano.

---

## 6. Arquitectura

```
                    ┌────────────────────── VPS Oracle A1 (arm64, Ubuntu 24.04) ───────────────────────┐
 APK Flutter ──TLS──►  Caddy (HTTPS automático, rate limit)                                              │
   · drift/SQLite    │    ├─► api   : FastAPI (uvicorn)  ──► PostgreSQL 18  ◄── pgBackRest ──┐           │
   · outbox          │    ├─► admin : FastAPI + Jinja + htmx (2FA)                           │           │
   · imágenes local  │    └─► /descargas : página + APK firmado                             │           │
                     │  worker (procrastinate, cola en PG): push, emails, PDF/Excel,         │           │
                     │         vencimiento de reservas, limpieza por retención               │           │
                     └──────────────────────────────────────────────────────────────────────┼───────────┘
                          │                    │                     │                      │
                   OCI Object Storage     Firebase (FCM)       Email (Resend/Brevo)   OCI Object Storage
                   (comprobantes cifrados)                                             (copias de seguridad)
                          MercadoPago (cobro de planes, webhook) · AdMob (publicidad del plan gratis)
```

### Decisiones
| Pieza | Elección | Por qué |
|---|---|---|
| App | **Flutter** + Riverpod + drift + dio + go_router | Funciona sin señal, diseño propio, deja abierto iOS |
| Backend | **FastAPI** + SQLAlchemy 2 + Alembic + Pydantic | Stack conocido |
| Base | **PostgreSQL 18** | Transacciones, *row-level security*, JSONB |
| Cola | **procrastinate** (vive en PostgreSQL) | Evita sumar Redis |
| Proxy | **Caddy** | Certificados automáticos |
| Contenedores | **Docker Compose**, imágenes `arm64` | El VPS es ARM |
| Archivos | OCI Object Storage (20 GB gratis) con cifrado propio | No ocupa el disco del VPS |
| Push | Firebase Cloud Messaging | Gratis; anda con APK descargado si el teléfono tiene Google Play Services |
| Admin | Web servida por el mismo backend en `/admin` | Solo para el dueño; sin otro frontend que mantener |

### Estructura del repositorio (monorepo)
```
miti/
  app/          Flutter
  api/          FastAPI (api + admin + worker)
  infra/        docker-compose, Caddyfile, pgbackrest, scripts de despliegue
  docs/         este documento, términos, privacidad, decisiones (ADR)
  .claude/skills/diseno-miti/   skill de diseño (§12)
```

### Entornos y dominios
- **Desarrollo:** local (Windows) con PostgreSQL y el emulador de Android.
- **Prueba (V1):** `miti.sole.ar` → registro **A** `129.146.57.10`.
  - Abrir los puertos 80 y 443 en la *Security List* de Oracle **y** en el `iptables` de Ubuntu. Las imágenes de Oracle traen reglas que bloquean todo menos SSH.
- **Producción:** dominio propio, a comprar antes de la versión pública. La URL de la API la resuelve la app al arrancar desde un `config.json` firmado, para poder mudar el dominio sin romper versiones viejas.

### Distribución del APK
- **Firma:** keystore propio, con copia fuera del VPS. Si se pierde, no se pueden publicar actualizaciones.
- **Descarga** en `/descargas`, con el hash SHA-256 publicado junto al archivo.
- **Actualizaciones:** la app consulta `GET /version`. Si hay una versión nueva, ofrece descargarla; si la versión instalada ya no es compatible, obliga a actualizar.

---

## 7. Funciones extra aprobadas

| # | Función | Dónde se hace |
|---|---|---|
| 1 | **Imagen de números disponibles** (§8.1) | En el celular (anda sin señal) |
| 2 | **Billete / comprobante** para el comprador (§8.2) | En el celular |
| 4 | **Recordatorios a deudores**: link `wa.me` con el mensaje armado | En el celular, sin costo de API |
| 5 | **Exportar** la liquidación y los movimientos a PDF y Excel | En el servidor (worker) |
| 6 | **Historial** visible | Tabla `historial` |
| 7 | **Ranking de ventas** | Solo informativo; no altera el reparto |
| 8 | **Ganador publicado**, con la prueba del sorteo si fue interno | Tarjeta e imagen para compartir |
| 9 | **Muro de avisos** de la campaña | Mensajes simples con notificación push |

---

## 8. Imágenes generadas

### 8.1 Números disponibles
- **Fondo:** una imagen que sube el administrador.
  - Formatos de salida: 1080×1350 (publicación) o 1080×1920 (historia).
  - El usuario ajusta el **recuadro** donde va la grilla; por defecto, centrado al 80 %.
- **Números por imagen:** lo configura la campaña (por ejemplo 100 o 200).
  - Una rifa de 1000 números con 200 por imagen genera **5 imágenes**, numeradas "1/5"…"5/5", con el rango de cada una ("000–199").
- **Grilla:** muestra **todas las posiciones** del rango de esa imagen.
  - Un número **disponible** aparece con su número.
  - Un número **vendido** aparece como celda con **fondo fijo sin número**; el color o la textura se configuran.
  - Un número **reservado** se muestra **igual que uno vendido**: en la imagen no figura como disponible.
- **Columnas:** se calculan solas según la cantidad de números y la proporción del recuadro.
- **Pie de imagen:** nombre de la campaña, precio, fecha del sorteo y "Actualizado dd/mm hh:mm". Si la app no tiene señal, además: "puede no estar al día".
- **Salida:** se comparte desde el menú de Android (WhatsApp, Instagram) o se guarda en la galería.

### 8.2 Billete / comprobante de compra
- **Contenido:** nombre de la campaña, número (o productos), nombre del comprador, importe, fecha, vendedor, fecha del sorteo, premios y **código corto** de la venta.
- Estado **"PAGADO"** o **"A PAGAR"**, según el cobro.
- Se genera al registrar la venta; se puede **volver a generar**.
- **Envío:** menú de compartir de Android, con el teléfono del comprador precargado si se elige WhatsApp.

---

## 9. Seguridad

### Cuenta y acceso
- **Ingreso:** email con **código de un solo uso** (sin contraseña) o **Google**.
- **Doble factor opcional:** TOTP.
- **Tokens:**
  - *Access* JWT de 15 minutos.
  - *Refresh* rotativo, de un solo uso, guardado como hash; si se detecta reutilización, se revoca toda la cadena.
  - En el celular se guardan en `flutter_secure_storage` (Android Keystore).
- **Bloqueo local** opcional con PIN o huella al abrir la app.
- **Cerrar sesión** en otros dispositivos desde el perfil.

### Autorización
- Cada consulta se valida **en el servidor**: pertenencia a la campaña, rol y estado.
- **Row-level security** en PostgreSQL como segunda barrera: la API fija `app.usuario_id` en cada transacción.
- **Nunca** se confía en un precio, un estado o un permiso que mande el celular.

### Cifrado
- **En tránsito:** TLS 1.2 o superior (Caddy).
- **Disco:** volumen cifrado de Oracle (viene activado por defecto).
- **Por campo** (teléfonos, emails, nombres de compradores, secretos TOTP): AES-256-GCM con **cifrado de sobre**.
  - Una clave de datos por campaña, cifrada con una **clave maestra** que **no está en la base**.
  - La clave maestra vive en OCI Vault (llaves por software, gratis) o, en la V1, en un archivo con permisos 600 fuera del repositorio y con copia offline.
- **Búsquedas** sobre datos cifrados (email exacto): un HMAC aparte.
- **Comprobantes:** se cifran **antes** de subirlos al Object Storage y se sirven a través de la API, nunca con URLs públicas.

### Servidor
- SSH solo con clave y sin root.
- `unattended-upgrades` y `fail2ban`.
- Firewall: solo los puertos 22, 80 y 443.
- Contenedores sin root; secretos en archivos `.env` con permisos 600.
- *Rate limit* en el ingreso y en el envío de códigos.
- **Auditoría de accesos** del panel de administración.

### App
- **`FLAG_SECURE` en las pantallas de dinero** (inicio, cajas, movimientos, liquidación): impide capturas y oculta la pantalla en la lista de apps recientes. No hace falta capturar el saldo: todos los integrantes lo ven. Las imágenes para compartir (disponibles, billete, ganador) se generan aparte y no se ven afectadas.
- Ofuscación del código Dart.
- Sin datos sensibles en los logs.
- Referencia: **OWASP MASVS** nivel L1.

### Datos personales
- **Retención:** **6 meses** después de liquidada la campaña. Durante ese tiempo se puede exportar; después se borra en el servidor.
- **Baja de cuenta** desde la app: borra los datos personales y deja el historial de las campañas con "Usuario eliminado".

---

## 10. Legal (borrador; lo revisa un abogado)

**Documentos a redactar:**
- **Términos y Condiciones:**
  - Miti es una herramienta de registro: no organiza sorteos, no vende números, no recibe ni custodia fondos.
  - El organizador es responsable de contar con las autorizaciones que exija su jurisdicción para rifas.
  - La plataforma no responde por deudas entre integrantes.
- **Política de Privacidad** (Ley 25.326): responsable Sergio [APELLIDO, CUIT, domicilio], finalidades, cesiones (Oracle, Google/Firebase, proveedor de email, MercadoPago), retención de 6 meses y derechos de acceso, rectificación y supresión.
- **Registro de la base de datos ante la AAIP.**
- **Defensa del consumidor** para los planes pagos:
  - **"Botón de arrepentimiento"** (Res. SCI 424/2020): un enlace visible para revocar la compra dentro de los 10 días.
  - **"Botón de baja"** (Res. 316/2024).
- **Edad mínima: 13 años** (la edad desde la que en Argentina se puede tener una cuenta bancaria propia).
  - El registro pide la fecha de nacimiento y rechaza a los menores de 13.
  - De 13 a 17 años: los términos piden declarar la autorización de un adulto responsable. Si esa declaración alcanza, o si hace falta un consentimiento verificable, **lo define el abogado**.
- **Datos de terceros:** quien carga un comprador declara tener su consentimiento para registrar nombre y teléfono con este fin.
- **Publicidad y menores:** para usuarios de 13 a 17 años, AdMob se configura para público no adulto (sin anuncios personalizados). Lo más simple es aplicarlo a todos.

---

## 11. Monetización

### Planes (precios aprobados como punto de partida)
| Plan | Límites | Publicidad | Precio sugerido |
|---|---|---|---|
| **Gratis** | 1 campaña activa · 5 integrantes · 100 números o 20 ventas | Sí, nunca en las pantallas de dinero ni en la liquidación | $0 |
| **Campaña** | 1 campaña · hasta 15 integrantes · 1.000 números o 300 ventas | No | ≈ **US$ 10** en pesos |
| **Campaña Grande** | 1 campaña · hasta 50 integrantes · 10.000 números · ventas sin límite | No | ≈ **US$ 25** en pesos |

**Criterio del precio:** una campaña chica de 10 integrantes con 1.000 números suele recaudar mucho más de lo que cuesta el plan; el precio queda en torno al **1 % o menos** de lo recaudado. El precio en pesos se guarda en la configuración y se actualiza sin publicar una versión nueva.

### Cobro
- Lo paga el **creador**, que puede cargarlo como **gasto** de la campaña: se reparte como cualquier otro.
- **Mejora de plan:** al pasar un límite, se paga para **mejorar la campaña existente**; no hace falta crear otra.
- **Cómo se cobra:** MercadoPago **Checkout Pro**. La app abre el navegador y el **webhook** habilita el plan; la confirmación siempre la valida el servidor contra la API de MercadoPago.
- **Facturación:** fuera de Miti (el dueño factura por su cuenta).

### Publicidad
- **AdMob:** banner en listas y, como mucho, un intersticial al generar una imagen.
- **[A VERIFICAR]** Las condiciones de AdMob para apps que **no están publicadas en una tienda**: puede limitar los anuncios.

---

## 12. Diseño

- **Dirección elegida: A · Talonario**, con el fondo más claro: papel y tinta, tipografía condensada, perforaciones, sello rojo. Maquetas en claro y oscuro: https://claude.ai/artifact/NJvCmyQiTzbihsthKYqZWM (las direcciones B y C quedan en la página "Descartadas").
- La **skill** `.claude/skills/diseno-miti/` es la fuente de verdad del diseño. Incluye:
  - tokens de color, tipografía y espaciado;
  - componentes (tarjeta de dinero, celda de número, hoja inferior, chip, barra de navegación);
  - movimiento y tono de los textos;
  - lista de **prohibidos** (tarjetas grises genéricas, degradados violetas, Inter o Roboto, emojis como íconos, el aspecto Material por defecto).
  - En Flutter se traduce a un `ThemeExtension` propio.

---

## 13. Operación

### Copias de seguridad
- **pgBackRest** con archivado continuo de WAL (se puede volver a cualquier minuto) hacia OCI Object Storage, cifrado.
- **Retención:** copia completa semanal, diferenciales diarias, **30 días** de recuperación a un minuto dado y **una copia mensual durante 6 meses**.
- **Prueba de restauración mensual** automática en un contenedor aparte, con aviso por email del resultado.
- **Copia secundaria** semanal, fuera de Oracle (disco local o un segundo proveedor), por si se pierde la cuenta de Oracle.

**Costo:**
- $0 mientras todo (comprobantes y copias) quepa en los **20 GB gratis** de Object Storage y no pase de **50.000 solicitudes por mes**.
- `archive_timeout` en 5 minutos: como máximo unas 9.000 subidas de WAL por mes.
- Pasados los 20 GB, del orden de **US$ 0,03 por GB por mes**. *(Verificar en la lista de precios de Oracle antes de configurar.)*

### Monitoreo
- Chequeo externo de disponibilidad.
- Logs estructurados con rotación.
- Alertas por email: disco, errores 5xx, copia fallida.

### Riesgo del plan Always Free
Oracle puede recuperar instancias ociosas. Mitigación: la copia secundaria y pasar a **pago por uso** cuando haya usuarios reales.

---

## 14. Decisiones pendientes

1. **Dominio definitivo** para la versión pública.

Cerradas el 2026-09-17:
- Imagen de disponibles: los reservados se muestran como vendidos.
- Edad mínima: 13 años.
- Los gastos del administrador los aprueba otro integrante.
- Precios: los sugeridos en §11.
- Dirección visual: A · Talonario, con el fondo claro.
- `FLAG_SECURE` en las pantallas de dinero: sí.

## 15. Fases (propuesta)

| Fase | Contenido |
|---|---|
| 0 | Skill de diseño; VPS preparado (Docker, Caddy, PostgreSQL, copias); DNS; esqueleto de API y app; CI que compila el APK |
| 1 | Cuentas (código por email y Google), campañas, invitación interna, cajas |
| 2 | Rifa: números, reservas, ventas, cobros, comprobantes, billete, imagen de disponibles |
| 3 | Sin señal: outbox, sincronización, conflictos de números |
| 4 | Gastos y aprobaciones, entregas entre cajas, anulaciones, historial, muro, notificaciones push |
| 5 | Liquidación, exportación a PDF y Excel, sorteo y ganador, recordatorios, ranking |
| 6 | Productos (catálogo, encargos, entregas) |
| 7 | Planes y límites, MercadoPago, AdMob, panel de administración, textos legales, retención y baja de cuenta |
| 8 | Prueba cerrada en `miti.sole.ar` con 1 o 2 grupos reales → ajustes → dominio propio |
