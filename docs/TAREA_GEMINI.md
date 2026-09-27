# Tarea para Gemini (Antigravity) — Redactar el recordatorio con IA local

Trabajo en paralelo. **Vos tocás solamente `app/`. No toques `api/`, `infra/` ni `docs/`**,
que los está cambiando otro agente al mismo tiempo. Si necesitás algo del servidor, está
todo en el contrato de acá abajo: ya funciona en producción.

Antes de empezar leé `docs/TRASPASO.md` (secciones 0 a 3) y
`.claude/skills/diseno-miti/SKILL.md` (el sistema de diseño es obligatorio).

## Qué hay que hacer

Hoy, cuando alguien debe plata, la campaña muestra un aviso con botón **RECORDAR** que arma
un mensaje con una plantilla fija (`app/lib/nucleo/recordatorio_deuda.dart`) y lo manda por
WhatsApp. El mensaje sale siempre igual.

Ahora el servidor puede **redactar ese mensaje con un modelo de IA que corre en el propio
VPS** (Ollama + Llama 3.2). Hay que darle lugar en la app.

### Comportamiento esperado

1. Al tocar **RECORDAR** ya no se abre WhatsApp directo: se abre una hoja (`MitiHoja`) que
   muestra el mensaje **propuesto**, en un campo de texto **editable**.
2. La hoja pide el mensaje al servidor (endpoint de abajo). Mientras llega, muestra el texto
   de la plantilla actual, que ya existe, para que nunca haya una pantalla vacía.
3. Botones: **Enviar por WhatsApp** (principal) y **Otra redacción** (secundario, vuelve a
   pedirle al servidor, que genera distinto cada vez).
4. Abajo, en letra chica: de dónde salió el texto. Si el servidor contestó
   `origen: "ia_local"`, decir *"Redactado por la IA del servidor de Miti. Revisalo antes de
   mandarlo."*; si contestó `"plantilla"`, no decir nada.
5. **La persona siempre revisa y puede editar antes de enviar.** Nunca se manda automático.
6. Sin señal o si el servidor falla: se usa la plantilla local de siempre y la hoja funciona
   igual. Nada de errores rojos por esto.

## Contrato de la API (ya desplegado en https://miti.sole.ar)

```
POST /campanas/{campana_id}/ventas/{venta_id}/recordatorio
Authorization: Bearer <token>
body (opcional): {"tono": "amable"}      // "amable" | "firme"

200 OK
{
  "mensaje": "Hola Carlos, ¿cómo andás? ...",
  "origen": "ia_local",        // o "plantilla" si el modelo no estaba disponible
  "modelo": "llama3.2:3b",     // null si vino de la plantilla
  "demoro_ms": 3480
}

404  la venta no existe en esa campaña
409  esa venta no tiene saldo pendiente
```

Puede tardar **varios segundos** (el modelo corre en CPU): poné un tiempo de espera de al
menos 60 segundos en esa llamada y mostrá el estado de "redactando…" en el botón.

Agregá el método en `app/lib/nucleo/api.dart` junto a los demás, con el mismo estilo:

```dart
Future<Map<String, dynamic>> redactarRecordatorio(String campanaId, String ventaId,
        {String tono = 'amable'}) async =>
    (await pedir('POST', '/campanas/$campanaId/ventas/$ventaId/recordatorio',
        cuerpo: {'tono': tono})) as Map<String, dynamic>;
```

## Reglas de la casa (no negociables)

- Español rioplatense, simple, en toda la interfaz.
- Diseño Talonario: `MitiHoja`, `MitiBoton`, `context.color`, `context.texto`. Nada de
  widgets Material genéricos ni colores fuera de los tokens.
- Los errores van **dentro** de la hoja (`MitiErrorEnLinea`), nunca en un aviso que el
  teclado pueda tapar.
- No agregues dependencias nuevas al `pubspec.yaml`.

## Cómo verificar antes de decir que está listo

```
cd app
flutter analyze          # tiene que dar 0 issues
flutter test             # 22/22 en verde
```

Agregá una prueba de widget en `app/test/` que monte la hoja con el proveedor de la API
sobreescrito y verifique: que muestra el texto propuesto, que el campo es editable y que
con `origen: "plantilla"` no aparece la leyenda de la IA.

**No compiles el APK ni lo publiques**: de eso se encarga el otro agente al final, para que
la versión salga una sola vez.

## Commits

Chicos, en español, y terminá el mensaje con:

```
Co-Authored-By: Gemini 3.8 Flash <noreply@google.com>
```

Cuando termines, avisá qué archivos tocaste.
