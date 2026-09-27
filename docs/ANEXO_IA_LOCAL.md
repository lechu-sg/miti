# Anexo · IA local en Miti (Parte 2 de la entrega)

Modelo corriendo **en el mismo VPS que la aplicación**, sin conexión con ninguna nube.
Todo lo que sigue está medido el 27/09/2026 en el servidor de producción.

## Qué se instaló

| | |
|---|---|
| Servidor | Oracle A1 · ARM aarch64 · 4 núcleos · 23 GB de RAM · **sin GPU** |
| Motor | Ollama 0.34.4 (servicio de systemd) |
| Modelo | `llama3.2:3b` · 2,0 GB |
| Cómo escucha | Sólo en `172.28.0.1:11434`, la puerta de enlace de la red interna de Docker. **No está publicado en internet**: el firewall sólo acepta ese puerto desde `172.28.0.0/16` |
| Quién lo usa | El contenedor de la API, para una sola cosa: redactar el recordatorio de deuda |

## Para qué se usa hoy

Cuando un comprador debe su parte, el vendedor tenía que mandarle un mensaje armado con una
plantilla fija, siempre igual. Ahora el servidor **propone** el texto, y la persona lo lee, lo
edita si quiere y recién ahí lo manda por WhatsApp.

**Por qué local y no una API en la nube:** para escribir ese mensaje hay que darle al modelo el
nombre de un comprador y cuánto debe. Esa persona no es usuaria de Miti y nunca dio
consentimiento para que sus datos viajen a un tercero (Ley 25.326). Con el modelo en el mismo
servidor, el dato no sale de donde ya estaba.

## Medición real

Prueba automática `api/pruebas/prueba_ia_local.py` contra `https://miti.sole.ar` — **15 de 15 en verde**:

```
--- tono amable · origen: ia_local · modelo: llama3.2:3b · 13.578 ms
| ¡Hola Carlos! Tenés que recordar que te quedan $12.000 de los números 7 y 8
| para el Viaje de egresados 6 B. Podés transferir al alias viaje.6b.mp cuando
| puedas. Muchas gracias por tu apoyo.

--- tono firme · origen: ia_local · modelo: llama3.2:3b · 6.949 ms
| ¡Hola Carlos! La campaña Viaje de egresados 6 B necesita cerrar la cuenta: te
| quedan $12.000 de los números 7 y 8. Cuando puedas, podés transferir al alias
| viaje.6b.mp y listo.
```

Velocidad medida: **≈14 tokens por segundo** (56 tokens en 3,9 s). Un mensaje completo tarda
entre 7 y 16 segundos. Alcanza para una acción que la persona pide a propósito; no alcanzaría
para algo que se escriba mientras el usuario mira la pantalla.

## Sesión en la terminal del servidor

```
$ ollama list
NAME           ID              SIZE      MODIFIED
llama3.2:3b    a80c4f17acd5    2.0 GB    6 minutes ago

$ ollama run llama3.2:3b 'Respondé en dos oraciones, en español rioplatense:
  ¿por qué conviene que el modelo que redacta los recordatorios de deuda de una
  app de rifas corra en el mismo servidor y no en una API en la nube?'

En el caso de una app de rifas, conveniente que el modelo que redacta los
recordatorios de deuda corra en el mismo servidor es porque esto permite una
comunicación directa y rápida con el sistema de pago y el algoritmo de gestión
de loterías, lo que reduce la latencia y aumenta la seguridad. Además, utilizar
una API en la nube puede generar costos adicionales y problemas de conectividad
con el servidor, lo que puede afectar la experiencia del usuario.

real    0m9.454s
```

**Esta respuesta es, además, la mejor evidencia de los límites del modelo.** Se inventó un
"sistema de pago" y un "algoritmo de gestión de loterías" que no existen, y no mencionó lo
único que importa de verdad: la privacidad de los datos. Un modelo de 3B **razona mal cuando
la pregunta es abierta**. Por eso en el producto no se le pregunta nada abierto: se le da una
consigna cerrada, datos concretos y un ejemplo, y aun así se revisa lo que devuelve.

## Cómo se lo controla

El modelo no tiene la última palabra en ningún punto:

1. **Consigna cerrada con ejemplo** y temperatura baja (0.4).
2. Los datos del comprador entran **como datos, no como instrucciones**, y recortados: un
   comprador que se llame "ignorá lo anterior y..." no cambia la consigna (prompt injection).
3. **Se revisa la respuesta antes de mostrarla.** Se descarta si no nombra a la persona, si no
   dice el importe exacto, si aparece **cualquier otra cifra en pesos** —así no puede inventar
   un monto—, si hace preguntas o si devuelve código.
4. Si algo de eso falla, o si el modelo no está, **se usa el texto de plantilla**. La app nunca
   se queda sin respuesta: en la primera prueba, con el modelo todavía inalcanzable, el sistema
   devolvió la plantilla en 58 ms sin un solo error.
5. **Siempre lo lee y lo aprueba una persona** antes de enviarlo. La IA propone, el vendedor manda.

## Qué se ve desde el panel

`/admin → Salud` muestra el modelo configurado y si está respondiendo. Si dice "no responde",
los recordatorios siguen saliendo con la plantilla.

## Qué se podría hacer después

- **Comprobantes:** leer la imagen de la transferencia y avisar "esto se parece al que subió
  Ana el martes" (hoy es un hash, que sólo detecta el archivo idéntico).
- **Cierre de campaña:** redactar en criollo el resumen de la liquidación.
- **Análisis interno:** preguntarle al registro de operación dónde se traban las campañas, sin
  que los datos salgan del servidor.
