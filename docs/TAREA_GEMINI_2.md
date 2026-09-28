# Traspaso a Gemini — 27/09/2026, 22:00

Sos el asistente que continúa Miti. El agente anterior (Claude Opus 5) se quedó sin cuota.
**Leé primero `docs/TRASPASO.md` completo** (es la memoria del proyecto: entorno, servidor,
reglas que no se pueden romper y estado de cada fase). Este archivo es sólo lo de hoy y lo
que queda pendiente.

## Cómo trabajar

- Español rioplatense y simple. El usuario es Ezequiel Bari; sabe programar, no es experto
  en Flutter ni en Docker.
- **No supongas nada**: si una regla de negocio no está en `docs/DEFINICION.md`, preguntá.
- Antes de algo difícil de deshacer (borrar datos, firewall, secretos, `force push`),
  pedí confirmación.
- Nunca muestres ni subas el contenido de `/srv/miti/secrets/*`.
- Nada se da por terminado sin probarlo: `flutter analyze`, `flutter test` y, si tocás la
  API, la suite correspondiente en `api/pruebas/` contra el servidor.
- Commits chicos, en español, terminando con
  `Co-Authored-By: Gemini 3.8 Flash <noreply@google.com>`.

## Contexto: hoy es la entrega del curso

Miti es el trabajo final del **Curso de IA para Programadores (UTN FRBA)**. La consigna está
en el PDF que tiene el usuario; lo que importa:

- El docente **evalúa en los links**, no en el PDF: repositorio, sitio publicado y video.
- El repositorio tiene que estar **público, con historial real** (ya lo está: 90+ commits,
  47 co-firmados por Claude y 43 por Gemini; esa evidencia de orquestación multi-agente es
  parte de la nota).
- El informe ya está hecho: `docs/entrega/Miti-entrega-final.pdf` (14 páginas), generado por
  `docs/entrega/armar_informe.py` con reportlab. **Si hay que cambiar el informe, se edita ese
  script y se vuelve a correr**, no se edita el PDF.

### Links que ya funcionan

| Recurso | URL |
|---|---|
| Repositorio | https://github.com/lechu-sg/miti |
| Portada | https://miti.sole.ar |
| APK | https://miti.sole.ar/descargas/miti.apk |
| Informe PDF | https://miti.sole.ar/descargas/entrega/Miti-entrega-final.pdf |
| Video (2:40) | https://miti.sole.ar/descargas/entrega/miti-demo.mp4 |
| Capturas (10) | https://miti.sole.ar/descargas/entrega/ |
| Panel | https://miti.sole.ar/admin |

## Lo que se hizo hoy

1. **IA local en el producto.** Ollama + `llama3.2:3b` en el mismo VPS, atado a `172.28.0.1:11434`
   (puerta de enlace de la red `borde`, subred fija `172.28.0.0/16`). Regla de firewall agregada
   a mano en `/etc/iptables/rules.v4` y validada con `iptables-restore --test`.
   `POST /campanas/{id}/ventas/{id}/recordatorio` redacta el recordatorio de deuda; si el modelo
   falla o contesta algo que no pasa los controles, devuelve la plantilla (`origen: "plantilla"`).
   Prueba: `api/pruebas/prueba_ia_local.py` **15/15**. Detalle: `docs/ANEXO_IA_LOCAL.md`.
2. **Pantalla del recordatorio en la app** (la hizo Gemini, commit `903072b`).
3. **Datos de demostración** cargados en producción con dos cargadores reutilizables:
   - `api/pruebas/cargar_demo_deluxe.py` → rifa «Deluxe Femme», 200 números, liquidada.
   - `api/pruebas/cargar_demo_en_curso.py` → «Deluxe Femme · Nacional», activa, con números
     libres y compradores debiendo (campaña `2e55d2b1-103a-4fd8-950f-aae8328bdca3`).
   - Administradora: `eugenia.avila@live.com.ar` (real). Las otras nueve usan
     `@demo.miti.sole.ar`, un dominio al que la API **no manda correo** (si usás dominios reales
     inventados, los rebotes ensucian la reputación de `miti@sole.ar`).
4. **Video y capturas** grabados desde el celular por USB con `adb` y publicados.
5. **Arreglo**: el talón del ticket partía los importes largos (`$ / 93.70 / 0`), commit `cf188ad`.

## Pendiente inmediato (lo único a medio terminar)

**Republicar el APK 0.10.2.** Quedó compilando cuando se cortó la sesión.

```bash
cd app && flutter build apk --release        # ya debería estar hecho
```

Después, **sin saltear ningún paso**:

```bash
# 1. instalarlo en el celular (está conectado por USB) y comprobar que ABRE
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am force-stop ar.sole.miti
adb shell monkey -p ar.sole.miti -c android.intent.category.LAUNCHER 1
sleep 8 && adb shell pidof ar.sole.miti          # tiene que devolver un número
adb logcat -d | grep -i "FATAL"                  # tiene que estar vacío

# 2. publicar y COMPARAR la huella local con la del servidor
scp -i ~/.ssh/oracle_ollama build/app/outputs/flutter-apk/app-release.apk \
    ubuntu@129.146.57.10:/tmp/miti-0.10.2.apk
ssh -i ~/.ssh/oracle_ollama ubuntu@129.146.57.10 \
  "cd /srv/miti/descargas && sudo mv /tmp/miti-0.10.2.apk . && sudo cp miti-0.10.2.apk miti.apk && \
   sudo sh -c 'sha256sum miti-0.10.2.apk > miti-0.10.2.apk.sha256; sha256sum miti.apk > miti.apk.sha256' && \
   sudo chmod 644 miti-0.10.2.apk* miti.apk*"
```

**Por qué tanto cuidado:** ya pasó dos veces. Una vez se publicó un APK viejo con nombre nuevo
porque la compilación había fallado y nadie miró. Otra vez se publicaron las versiones 0.9.0 y
0.10.0, que **no abrían**: el SDK de anuncios arrastra WorkManager, que usa Room, y el ofuscador
R8 renombraba la clase generada que Room busca por reflexión. `flutter analyze` y `flutter test`
**no ven ese error**: sólo aparece instalando el APK de release en un teléfono. La solución está
en `app/android/app/proguard-rules.pro`; no lo borres.

## Después de eso, en orden

1. **Avisarle al usuario** que el APK está publicado, con la huella.
2. **Pendientes del usuario** (no los podés hacer vos, necesitan sus cuentas):
   - **MercadoPago (prueba):** cargar con `nano` en `/srv/miti/secrets/mercadopago.env` la línea
     `MP_ACCESS_TOKEN=TEST-...` y, desde Webhooks, `MP_WEBHOOK_SECRET=...` apuntando a
     `https://miti.sole.ar/pagos/mercadopago/webhook`. No hace falta reiniciar nada.
   - **Firebase:** crear el proyecto, poner `google-services.json` en `app/android/app/` y subir
     la clave de cuenta de servicio a `/srv/miti/secrets/firebase.json`. Sin eso no hay push.
   - **AdMob:** pasar el ID de la app (va en `app/android/admob.properties`) y los de los bloques
     (van al compilar con `--dart-define=ADMOB_BANNER=... --dart-define=ADMOB_INTERSTICIAL=...`).
   - Confirmar que regeneró la master key de Backblaze y guardar las contraseñas de cifrado de
     pgBackRest en un gestor: **esas mismas claves abren los respaldos de los comprobantes**.
3. **Si el usuario quiere tocar el informe**, editá `docs/entrega/armar_informe.py`, corré
   `python docs/entrega/armar_informe.py` y volvé a subir el PDF a
   `/srv/miti/descargas/entrega/`.
4. **Fase 8** (cuando el curso esté entregado): prueba cerrada con uno o dos grupos reales y
   después mudanza al dominio definitivo, que es la única decisión que sigue abierta en
   `docs/DEFINICION.md`.

## Cosas que aprendimos a los golpes (no repetir)

- **Nunca** `netfilter-persistent save` con Docker corriendo.
- `git add -A` con otro agente trabajando en el mismo árbol **se lleva puestos sus archivos** y el
  commit queda mal atribuido. Pasó hoy; hubo que reescribir dos commits.
- Los textos de la app se prueban en el teléfono: `flutter test` no detecta que un botón desborde
  ni que un importe se parta en tres líneas.
- Para manejar el celular por `adb` desde Git Bash hace falta `export MSYS_NO_PATHCONV=1`, si no
  las rutas `/sdcard/...` se convierten en rutas de Windows.
- Al grabar un video con taps automáticos, cualquier venta agrega una fila y **corre todas las
  posiciones de la lista**: las acciones que dependen de coordenadas van antes de vender.
