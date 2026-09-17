---
name: diseno-miti
description: Sistema de diseño "Talonario" de Miti (app Flutter de campañas de recaudación). Usala SIEMPRE antes de diseñar, maquetar o programar cualquier pantalla, widget, tema, color, tipografía, ícono o imagen generada de Miti (grilla de números, billete, imagen de disponibles, ganador), y también al revisar si una pantalla "se ve bien". No uses el aspecto Material por defecto ni el estilo genérico de panel de administración.
---

# Miti · Sistema "Talonario"

Maquetas de referencia: https://claude.ai/artifact/NJvCmyQiTzbihsthKYqZWM (página "A · Talonario", claro y oscuro).

## La idea en una frase
**Papel y tinta.** La app se ve como un talonario impreso:
- fondo de papel claro y tinta azul-noche;
- números grandes en tipografía condensada;
- líneas **troqueladas** (punteadas) donde algo "se corta";
- un **sello rojo** para lo que requiere atención.

La sobriedad viene del papel; lo festivo, de la tipografía y del sello. Nunca de degradados ni de ilustraciones.

## Tokens de color

Los nombres son los de `MitiColors` (un `ThemeExtension` de Flutter). **No se usa ningún color fuera de esta tabla.**

| Token | Claro | Oscuro | Uso |
|---|---|---|---|
| `papel` | `#FBF9F4` | `#141A23` | Fondo de pantalla |
| `hoja` | `#FFFFFF` | `#1B222D` | Hojas inferiores, diálogos, campos elevados |
| `papelHundido` | `#F1ECE0` | `#222B38` | Pestaña activa, fondos de fila presionada |
| `tinta` | `#1E2A3A` | `#EFE8D8` | Texto principal, bordes de control, relleno de "ticket" |
| `tintaSobre` | `#FBF9F4` | `#141A23` | Texto sobre un relleno de `tinta` |
| `tintaSuave` | `#5F5A4E` | `#A9A291` | Texto secundario, etiquetas, leyendas |
| `troquel` | `#CFC6B2` | `#3A4556` | Líneas punteadas y separadores |
| `sello` | `#B7372A` | `#C94A36` | Acción principal, número seleccionado, bordes de alerta |
| `selloTexto` | `#8E2A20` | `#F08A76` | Texto de alerta y enlaces |
| `mostaza` | `#E3A72F` | `#F0B84A` | Progreso y metas (solo como relleno, nunca como texto sobre papel) |
| `vendido` | `#E4DDCB` | `#212935` | Celda de número vendido o reservado en imágenes |
| `vendidoTexto` | `#A39B88` | `#58606D` | Número vendido dentro de la app (deshabilitado a propósito) |
| `ok` | `#2F7A57` | `#6CC39A` | Confirmado o aprobado (ícono y texto corto) |

**Reglas:**
- El **"ticket"** (la tarjeta de recaudación) usa `tinta` de fondo y `tintaSobre` de texto. En oscuro se **invierte solo**: papel claro sobre fondo oscuro.
- `sello` con texto blanco `#FFFFFF` en los botones principales, en los dos modos.
- **Contraste mínimo:** 4,5:1 para texto normal y 3:1 para texto de 24 px o más y para bordes de control. La única excepción es `vendidoTexto`, que es deshabilitado a propósito.
- **Un solo `sello` por pantalla** como acción principal. Si aparecen dos, sobra uno.

## Tipografía

Las dos fuentes son OFL. Se **empaquetan** en `assets/fonts` porque la app funciona sin señal; nada de `google_fonts` en tiempo de ejecución.

| Estilo | Fuente | Tamaño / peso | Uso |
|---|---|---|---|
| `titular` | Big Shoulders Display | 44 / 900, MAYÚSCULAS, interlineado 0,95 | Título de pantalla |
| `importe` | Big Shoulders Display | 46 / 800 | Monto protagonista |
| `seccion` | Big Shoulders Display | 24 / 800, MAYÚSCULAS | Títulos de sección |
| `cifra` | Big Shoulders Display | 17–22 / 800 | Números de la grilla, montos en listas |
| `cuerpo` | Figtree | 15 / 400–600 | Texto general |
| `etiqueta` | Figtree | 13 / 600 | Etiquetas de campos |
| `sobrelinea` | Figtree | 12 / 700, MAYÚSCULAS, espaciado +0,14 em | Estado arriba del título ("CAMPAÑA DE NÚMEROS · ACTIVA") |
| `pie` | Figtree | 11–12 / 400 | Aclaraciones |

**Reglas:**
- **Todo número de dinero o de rifa va en Big Shoulders**, con separador de miles `.` y `$ ` con espacio.
- Nunca Inter, Roboto ni Arial. Nunca una tercera familia.

## Forma y espacio
- **Espaciado:** grilla de 4 px. Márgenes laterales de pantalla de 16 o 20 px, huecos de 8, 10, 12 o 16.
- **Radios:** 6 px (campos, botones, tickets); 3 px (celdas de número); 50 % (avatares, botón redondo de acción secundaria); 18 o 22 px (chips).
- **Bordes:** 1,5 px `tinta` en controles; 2 px en lo seleccionado o en una alerta.
- **Troquel:** `2px dashed` para separar partes de un ticket y el borde superior de una hoja inferior. Separadores de lista: `1px dashed troquel`.
- **Sombras:** solo la hoja inferior (`0 -12 30 tinta@12%`). Ninguna otra superficie lleva sombra: la jerarquía la marcan el borde y la tinta.
- **Tamaño táctil:** mínimo **48 dp** (recomendación de Android), con botones principales de 52 dp.
- **Inclinación del sello:** una única pieza de "atención" por pantalla puede ir girada −0,6°. No más.

## Componentes

- **Ticket de recaudación:** relleno `tinta` con dos zonas separadas por un troquel vertical.
  - A la izquierda: cobrado (`importe`), vendido y lo que falta cobrar, y una barra `mostaza` de 8 px.
  - A la derecha, el talón: vendidos / total.
- **Fila de caja:** avatar con iniciales (círculo con borde de `tinta`), nombre y, debajo, el desglose "Billetera $ X · efectivo $ Y". El total a la derecha, en `cifra`. Separador troquel.
- **Aviso de pendientes:** borde de 2 px `sello`, texto `selloTexto` y el número grande en Big Shoulders 30. Es la pieza que puede ir girada.
- **Grilla de números:** 10 columnas, 4 px de hueco, celdas de 30 dp de alto.
  - `libre`: borde `tinta`.
  - `reservado`: borde punteado `sello` y texto `selloTexto`.
  - `vendido`: relleno `vendido` y texto `vendidoTexto`.
  - `seleccionado`: relleno `sello` y texto blanco.
  - `a confirmar` (vendido sin señal): borde punteado `tinta` con un punto `mostaza` en una esquina.
- **Chips de filtro:** activo con relleno `tinta`; inactivo con borde de 1,5 px. Siempre con la cantidad: "Libres 21".
- **Hoja inferior:** fondo `hoja`, borde superior troquelado de 2 px y botón de cerrar a la derecha.
- **Selector de destino del dinero:** grilla de 2×2 con título y aclaración en cada opción.
  - Seleccionada: relleno `tinta`.
  - "Todavía no pagó": borde punteado `sello`.
- **Barra de navegación:** 4 pestañas (Inicio · Números/Productos · Caja · Grupo), 64 dp, borde superior de 1,5 px `tinta`. La activa lleva fondo `papelHundido` y texto en negrita.
- **Íconos:** trazo de 2 px, extremos redondeados, 20–22 dp, del mismo color que el texto. Un solo set (Lucide o dibujados); **nunca emojis**.

## Imágenes generadas (se dibujan en el celular con `dart:ui`)

- **Disponibles:**
  - La imagen de fondo del usuario, con un recuadro de papel al 92 % de opacidad donde va la grilla.
  - Disponibles en `tinta` con Big Shoulders; vendidos y reservados, celda `vendido` **sin número**.
  - Pie con la campaña, el precio, la fecha del sorteo, "Actualizado dd/mm hh:mm" y "1/5".
- **Billete:**
  - Formato talón: cuerpo y talón separados por un troquel, con el número enorme en el talón.
  - Sello girado **"PAGADO"** (`ok`) o **"A PAGAR"** (`sello`), y el código corto abajo en Figtree.
- **Ganador:** el número en el centro dentro de un círculo de sello doble, el premio y "Sorteo del [fecha]".
- Las imágenes **siempre usan la paleta clara**, aunque la app esté en oscuro.

## Tono de los textos
- **Voseo rioplatense** y frases cortas: "¿Dónde entró el dinero?", "Todavía no pagó", "Vender y crear billete".
- **Verbos en los botones**, nunca "Aceptar" ni "OK" solos.
- **Montos siempre con signo y moneda**: `$ 20.000`.
- En los textos de la app y de la página de descarga, **evitar la palabra "rifa"**. Usar "campaña de números", "números" y "sorteo".

## Prohibido
- El aspecto Material por defecto: FAB flotante, sombras en tarjetas, violeta, ondas de toque llamativas.
- Tarjetas grises genéricas, bordes de color a la izquierda, degradados de cualquier tipo, fondos con desenfoque.
- Paneles de "KPIs" en cuadrícula con íconos de colores.
- Emojis como íconos, ilustraciones de personas, confeti.
- Colores o tipografías que no estén en este archivo.
- Texto gris claro sobre papel (no pasa el contraste).

## En Flutter
- `ThemeData(useMaterial3: true)` solo como base. `colorScheme` se arma desde los tokens (`primary` = `sello`, `surface` = `papel`, `onSurface` = `tinta`) y se **anulan** las sombras y los radios por defecto.
- `ThemeExtension<MitiColors>` y `ThemeExtension<MitiTexto>` con los tokens de arriba. Los widgets leen **solo** de ahí: `context.miti.sello`, nunca `Color(0x…)` suelto.
- **Widgets propios** en `lib/ui/`: `MitiTicket`, `MitiCeldaNumero`, `MitiHoja`, `MitiChip`, `MitiBoton` (principal y secundario), `MitiTroquel` (`CustomPainter`), `MitiSello`.
- **Pantallas de dinero:** `FLAG_SECURE` activado al entrar y desactivado al salir.

## Antes de dar una pantalla por terminada
1. ¿Hay un solo botón `sello`?
2. ¿Todos los colores salen de `MitiColors`?
3. ¿Los montos y los números van en Big Shoulders?
4. ¿Los objetivos táctiles miden 48 dp o más?
5. ¿Se ve bien en claro **y** en oscuro?
6. ¿Algo de la lista de prohibidos se coló?
