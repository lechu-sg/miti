"""Arma el informe final del curso en PDF.

    python docs/entrega/armar_informe.py

Genera `docs/entrega/Miti-entrega-final.pdf`. Las capturas salen de
`docs/entrega/capturas/` (las mismas que están publicadas en
https://miti.sole.ar/descargas/entrega/).
"""

from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_JUSTIFY
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (
    Image,
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

AQUI = Path(__file__).parent
CAPTURAS = AQUI / "capturas"
SALIDA = AQUI / "Miti-entrega-final.pdf"

TINTA = colors.HexColor("#1E2A3A")
SELLO = colors.HexColor("#B7372A")
SUAVE = colors.HexColor("#5F5A4E")
PAPEL = colors.HexColor("#F1ECE0")

hojas = getSampleStyleSheet()
H1 = ParagraphStyle("H1", parent=hojas["Heading1"], fontName="Helvetica-Bold",
                    fontSize=18, textColor=TINTA, spaceBefore=16, spaceAfter=8)
H2 = ParagraphStyle("H2", parent=hojas["Heading2"], fontName="Helvetica-Bold",
                    fontSize=13, textColor=TINTA, spaceBefore=12, spaceAfter=6)
P = ParagraphStyle("P", parent=hojas["BodyText"], fontName="Helvetica", fontSize=10,
                   leading=15, alignment=TA_JUSTIFY, textColor=TINTA, spaceAfter=6)
PIE = ParagraphStyle("PIE", parent=P, fontSize=8.5, textColor=SUAVE)
CODIGO = ParagraphStyle("CODIGO", parent=P, fontName="Courier", fontSize=8.5, leading=11)


def tabla(datos, anchos, encabezado=True):
    t = Table(datos, colWidths=anchos, repeatRows=1 if encabezado else 0)
    estilo = [
        ("FONTNAME", (0, 0), (-1, -1), "Helvetica"),
        ("FONTSIZE", (0, 0), (-1, -1), 8.5),
        ("TEXTCOLOR", (0, 0), (-1, -1), TINTA),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#CFC6B2")),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]
    if encabezado:
        estilo += [("BACKGROUND", (0, 0), (-1, 0), PAPEL),
                   ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold")]
    t.setStyle(TableStyle(estilo))
    return t


def parrafos(*textos):
    return [Paragraph(t, P) for t in textos]


def captura(nombre, titulo, alto=9.5 * cm):
    ruta = CAPTURAS / nombre
    if not ruta.exists():
        return Paragraph(f"[falta la captura {nombre}]", PIE)
    img = Image(str(ruta))
    proporcion = img.imageWidth / img.imageHeight
    img.drawHeight = alto
    img.drawWidth = alto * proporcion
    img.hAlign = "CENTER"
    return KeepTogether([img, Spacer(1, 3), Paragraph(titulo, PIE), Spacer(1, 8)])


def encabezado_pie(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(SUAVE)
    canvas.drawString(2 * cm, A4[1] - 1.2 * cm,
                      "Miti · Entrega final · Curso de IA para Programadores · UTN FRBA")
    canvas.drawRightString(A4[0] - 2 * cm, 1.2 * cm, f"{doc.page}")
    canvas.restoreState()


def construir():
    doc = SimpleDocTemplate(
        str(SALIDA), pagesize=A4, title="Miti · Entrega final",
        author="Ezequiel Bari", leftMargin=2 * cm, rightMargin=2 * cm,
        topMargin=2 * cm, bottomMargin=1.8 * cm,
    )
    h = []

    # ---------------------------------------------------------------- portada
    h += [
        Spacer(1, 2.5 * cm),
        Paragraph("MITI", ParagraphStyle("T", parent=H1, fontSize=46, leading=48,
                                         textColor=TINTA, spaceAfter=4)),
        Paragraph("La rifa del grupo, sin planillas ni discusiones",
                  ParagraphStyle("S", parent=P, fontSize=14, textColor=SELLO)),
        Spacer(1, 1.2 * cm),
        Paragraph("Entrega final de proyecto · Inteligencia Artificial aplicada a organizaciones<br/>"
                  "Curso de Inteligencia Artificial para Programadores<br/>"
                  "Universidad Tecnológica Nacional · Facultad Regional Buenos Aires", P),
        Paragraph("<b>Integrante:</b> Ezequiel Bari — análisis, arquitectura, orquestación de "
                  "agentes, infraestructura y pruebas.", P),
        Spacer(1, 1 * cm),
        Paragraph("Links de acceso directo", H2),
        Paragraph("El docente evalúa en estos links. Todos funcionan al momento de la entrega.", PIE),
        Spacer(1, 4),
        tabla([
            ["Recurso", "URL"],
            ["Repositorio (público)", "https://github.com/lechu-sg/miti"],
            ["Sitio en producción", "https://miti.sole.ar"],
            ["APK para instalar", "https://miti.sole.ar/descargas/miti.apk"],
            ["Video de demostración (2:40)", "https://miti.sole.ar/descargas/entrega/miti-demo.mp4"],
            ["Capturas de pantalla", "https://miti.sole.ar/descargas/entrega/"],
            ["Panel de administración", "https://miti.sole.ar/admin"],
            ["Definición del sistema", "github.com/lechu-sg/miti/blob/main/docs/DEFINICION.md"],
            ["Traspaso entre agentes", "github.com/lechu-sg/miti/blob/main/docs/TRASPASO.md"],
            ["Anexo de IA local", "github.com/lechu-sg/miti/blob/main/docs/ANEXO_IA_LOCAL.md"],
        ], [5 * cm, 11.5 * cm]),
        PageBreak(),
    ]

    # ------------------------------------------------- 1. equipo y proyecto
    h += [Paragraph("Parte 1 · El proyecto como aplicación real", H1),
          Paragraph("1. Presentación del proyecto", H2)]
    h += parrafos(
        "<b>Qué es.</b> Miti es una aplicación Android para administrar una campaña de "
        "recaudación en grupo: una rifa con talonario de números o una venta de productos. "
        "Cada integrante registra lo que vende y, sobre todo, <b>dónde quedó la plata</b>.",
        "<b>El problema.</b> Cuando un grupo junta plata —el viaje de egresados, el club, la "
        "cooperadora— el dinero termina repartido: una parte en la cuenta de quien recibe las "
        "transferencias, otra en la billetera virtual de cada uno y otra en efectivo. Alguien "
        "adelantó las fotocopias y hay que devolvérselo. La cuenta la lleva una sola persona en "
        "una planilla que nadie más toca, y al repartir empieza la discusión: cuánto entró, "
        "cuánto se gastó y cuánto le toca a cada uno.",
        "<b>La solución implementada.</b> La app sabe en todo momento cuánto hay en cada caja, "
        "qué falta cobrar y quién debe. Los gastos requieren la aprobación de otro integrante; "
        "nadie se aprueba a sí mismo. Al cerrar, calcula el neto, lo divide en partes iguales y "
        "resuelve <b>las transferencias mínimas</b> para saldar al grupo.",
        "<b>Público objetivo.</b> Grupos de 3 a 50 personas sin conocimiento contable ni técnico: "
        "familias, cursos, clubes de barrio, equipos de baile. Gente que hoy usa WhatsApp y papel. "
        "La app se instala por link, sin pasar por Play Store.",
    )

    # ------------------------------------------------------- 2. arquitectura
    h += [Paragraph("2. Arquitectura", H2),
          Paragraph("2.1 · Cómo fluyen los datos", H2)]
    h += parrafos(
        "El celular es autónomo: guarda en SQLite y encola lo que se registra sin señal. Cuando "
        "hay conexión, sincroniza contra la API, que valida las reglas de negocio con "
        "transacciones y bloqueos en PostgreSQL. La memoria persistente del sistema vive en "
        "PostgreSQL (servidor) y en SQLite (celular); los comprobantes, como archivos en disco.",
        "<b>Qué es IA y qué es lógica tradicional.</b> Todo lo que toca dinero es lógica "
        "determinista: son cuentas entre personas y una alucinación no es aceptable. El único "
        "componente de IA en el producto es un modelo chico que corre en el mismo servidor y "
        "<b>redacta</b> el recordatorio de deuda; la persona lo revisa y decide si lo manda.",
        "<font face='Courier' size='8'>"
        "App Android (Flutter, SQLite + outbox) --HTTPS--&gt; Caddy (TLS) --&gt; API FastAPI<br/>"
        "API --&gt; PostgreSQL 18 (memoria persistente) --&gt; pgBackRest --&gt; Oracle + Backblaze<br/>"
        "API --&gt; archivos de comprobantes · SMTP (códigos de acceso) · MercadoPago (planes)<br/>"
        "API --&gt; Ollama + Llama 3.2 en el mismo VPS (redacción de recordatorios)"
        "</font>",
        "El diagrama completo (Mermaid), el flujo de agentes y el diagrama de secuencia de una "
        "venta sin señal están en <b>docs/DEFINICION.md</b> y en el anexo del repositorio, donde "
        "GitHub los dibuja.",
    )

    h += [Paragraph("2.2 · El orquestador y los agentes", H2)]
    h += parrafos(
        "Esta es la parte que da cuenta de lo aprendido en el curso: <b>el software no se "
        "escribió a mano, se orquestó</b>. Un humano define las reglas y decide; un orquestador "
        "(Antigravity y Claude Code) reparte cada etapa —análisis, arquitectura, backend, "
        "diseño, infraestructura, pruebas— entre agentes de <b>dos modelos de dos empresas "
        "distintas</b>, que se pasan el trabajo mediante documentos versionados en el repositorio.",
        "<b>El ciclo:</b> el humano decide → el orquestador lee la memoria (DEFINICION.md, "
        "TRASPASO.md, la skill de diseño) → asigna la etapa al agente que corresponde → el agente "
        "de pruebas corre las suites contra el servidor real → si falla vuelve al orquestador; si "
        "pasa, se despliega y el humano prueba en el celular. Cada vuelta actualiza la memoria.",
        "<b>La memoria persistente del sistema de agentes</b> no son mensajes de chat: son "
        "archivos en git. Por eso, cuando se agotó la cuota de un modelo, se escribió un documento "
        "de traspaso y el otro continuó desde la fase 2 hasta la 7 sin intervención manual sobre "
        "el código.",
        "<b>Evidencia verificable en el historial:</b> 90 commits en 11 días, de los cuales "
        "<b>47 están co-firmados por Claude Opus 5 y 43 por Gemini 3.8 Flash</b>.",
    )

    # ---------------------------------------------------------------- 3. stack
    h += [PageBreak(), Paragraph("3. Stack tecnológico", H2),
          tabla([
              ["Componente", "Tecnología", "Por qué esta y no otra"],
              ["Frontend", "Flutter 3.47 (APK Android)",
               "Un solo código, funciona sin señal y se distribuye por link sin pasar por "
               "Play Store, que era requisito del proyecto."],
              ["Backend", "Python + FastAPI (async)",
               "Tipado con Pydantic, documentación automática y el mismo lenguaje para la API, "
               "el panel y las tareas de mantenimiento."],
              ["Base de datos", "PostgreSQL 18",
               "Transacciones y bloqueos reales: sin eso, dos personas venden el mismo número. "
               "SQLite quedó del lado del celular."],
              ["Base local", "SQLite + outbox propio",
               "Permite vender sin señal, que es el caso más común en una rifa de barrio."],
              ["Modelo de IA (producto)", "Ollama + Llama 3.2 3B, local",
               "Los datos del comprador no pueden viajar a un tercero (Ley 25.326). Corre en el "
               "mismo VPS, sin costo por token y sin internet."],
              ["Modelos de IA (desarrollo)", "Claude Opus 5 y Gemini 3.8 Flash",
               "Dos proveedores para comparar criterios y para no depender de una sola cuota."],
              ["Orquestación", "Antigravity y Claude Code, memoria en archivos del repo",
               "No hacía falta LangChain: el orquestador ya ejecuta agentes. Lo que faltaba era "
               "memoria, y se resolvió con documentos versionados."],
              ["Despliegue", "Docker Compose + Caddy · VPS Oracle ARM",
               "HTTPS automático, costo cero en el nivel gratuito y control total del dato."],
              ["Pagos", "MercadoPago Checkout Pro",
               "Es lo que usa el público argentino; el servidor nunca ve datos de tarjeta."],
              ["Copias de seguridad", "pgBackRest + gpg a Oracle y Backblaze",
               "Dos proveedores distintos, cifradas y con restauración probada automáticamente."],
          ], [3.4 * cm, 4.4 * cm, 8.7 * cm])]

    # ------------------------------------------------------------ 4. evidencia
    h += [PageBreak(), Paragraph("4. Evidencia de funcionamiento", H2)]
    h += parrafos(
        "Los datos que se ven son los de una rifa real de 200 números a $5.000 del grupo "
        "<i>Femme Deluxe Bachata</i>, cargada íntegra en el servidor de producción: 10 "
        "integrantes, 141 ventas, gastos aprobados y la campaña gemela ya liquidada.",
    )
    h += [captura("01-inicio-campanas.png", "Inicio: las campañas de la usuaria."),
          captura("02-campana-en-curso.png",
                  "La campaña en curso: cobrado, vendido, cuánto falta y los accesos."),
          captura("04-grilla-de-numeros.png",
                  "El talonario completo: 200 números, con los libres resaltados."),
          captura("05-registrar-venta.png",
                  "Registrar una venta: quién compró y, sobre todo, dónde entró el dinero."),
          captura("06-billete-del-comprador.png",
                  "El billete que se le manda al comprador por WhatsApp."),
          captura("03-campana-liquidada-donde-esta-la-plata.png",
                  "Dónde está la plata: la cuenta principal y la billetera de cada integrante."),
          captura("09-liquidacion-y-transferencias.png",
                  "La liquidación: $937.000 netos, $93.700 por integrante y las transferencias "
                  "mínimas para saldar al grupo."),
          captura("08-numeros-disponibles-sobre-el-flyer.png",
                  "La imagen para redes: la app pega los números libres sobre el flyer del grupo."),
          ]
    h += [Paragraph("Video de demostración", H2)]
    h += parrafos(
        "Una sola toma de 2 minutos y 40 segundos con el ciclo completo: "
        "https://miti.sole.ar/descargas/entrega/miti-demo.mp4",
    )
    h += [Paragraph("Registro de una ejecución real", H2)]
    h += parrafos(
        "<font face='Courier' size='8'>"
        "Suites de prueba contra https://miti.sole.ar (datos reales, servidor de producción)<br/>"
        "fase1 39/39 · fase2 55/55 · productos 43/43 · sync 26/26 · liquidación 34/34<br/>"
        "gastos 33/33 · fase5 47/47 · fase6 26/26 · perfil 16/16 · planes 32/32<br/>"
        "admin 41/41 · IA local 15/15 &nbsp;&nbsp;=&gt; <b>407 pruebas, 0 fallas</b><br/><br/>"
        "2026-09-28 00:25:57 INFO miti.ia Recordatorio redactado por llama3.2:3b en 17885 ms<br/>"
        "POST /campanas/2e55.../ventas/7a78.../recordatorio HTTP/1.1 200 OK"
        "</font>",
    )

    # -------------------------------------------------------------- 5. UX/UI
    h += [PageBreak(), Paragraph("5. Evaluación UX/UI", H2),
          tabla([
              ["Heurística", "¿Cumple?", "Evidencia"],
              ["Visibilidad del estado", "Sí",
               "Cada venta muestra si está pagada, adeudada o «a confirmar» (registrada sin "
               "señal); el ícono de sincronización indica lo pendiente."],
              ["Coincidencia con el mundo real", "Sí",
               "El lenguaje es el del grupo: talonario, billete, caja, «dónde entró el dinero». "
               "Nada de «transacción» ni «entidad»."],
              ["Control y libertad", "Parcial",
               "Se puede anular una venta con aprobación de otro integrante; no hay deshacer "
               "inmediato."],
              ["Consistencia y estándares", "Sí",
               "Sistema de diseño propio («Talonario») escrito como skill obligatoria para los "
               "agentes: mismos componentes en todas las pantallas."],
              ["Prevención de errores", "Sí",
               "Nadie aprueba su propio gasto; la liquidación lista los impedimentos antes de "
               "cerrar; un número vendido no se puede vender dos veces, ni siquiera sin señal."],
              ["Reconocimiento sobre recuerdo", "Sí",
               "El destino del dinero se elige de una lista con los saldos a la vista."],
              ["Flexibilidad y eficiencia", "Parcial",
               "Se venden varios números en una operación; falta buscador de compradores."],
              ["Estético y minimalista", "Sí",
               "Una acción principal por pantalla; la publicidad del plan gratis nunca aparece "
               "en las pantallas de dinero."],
              ["Ayuda a reconocer errores", "Sí",
               "Mensajes en criollo («no pudimos conectarnos, ¿tenés señal?») y el error se "
               "muestra donde el teclado no lo tapa."],
              ["Ayuda y documentación", "Parcial",
               "Textos de ayuda en contexto; no hay manual."],
          ], [4 * cm, 2 * cm, 10.5 * cm])]
    h += [Paragraph("5.2 · Prueba con usuario real", H2)]
    h += parrafos(
        "Se probó con una usuaria real en un Android 16 y el feedback cambió el producto. En una "
        "sola sesión reportó cuatro cosas: el campo de mail no ofrecía autocompletado, el mensaje "
        "de error quedaba tapado por el teclado, el aviso era rojo con letra negra (ilegible) y el "
        "modo oscuro tenía poco contraste —medido: las líneas estaban en 1,6:1 contra un mínimo "
        "razonable de 3:1—.",
        "Las cuatro se corrigieron y, además, se incorporaron como <b>reglas permanentes en la "
        "skill de diseño</b>, para que ningún agente vuelva a cometerlas. Ese es el punto: el "
        "feedback de una usuaria real se convirtió en memoria del sistema de agentes.",
    )

    # ------------------------------------------------------- 6. ciberseguridad
    h += [PageBreak(), Paragraph("6. Ciberseguridad", H2),
          tabla([
              ["Riesgo", "Tipo", "Medida tomada"],
              ["Robo de la base con datos personales", "Privacidad (Ley 25.326)",
               "El email se guarda cifrado con AES-256-GCM; se busca por huella HMAC, nunca en claro."],
              ["Robo de credenciales", "Autenticación",
               "Sin contraseñas: código de 6 dígitos por mail, token de 15 minutos y refresco "
               "rotativo con detección de reuso (si se reusa, cae toda la cadena)."],
              ["Secretos en el código", "Secretos",
               "Ningún secreto versionado: archivos en /srv/miti/secrets inyectados como Docker "
               "secrets. Verificado sobre todo el historial antes de abrir el repositorio."],
              ["Pago falsificado", "Integridad / fraude",
               "El webhook de MercadoPago sólo avisa; el estado se consulta a su API con nuestro "
               "token y se validan importe y moneda antes de habilitar el plan."],
              ["Toma del panel de administración", "Control de acceso",
               "Código por mail más TOTP, cookie firmada de 2 h, token CSRF por formulario, CSP "
               "sin scripts y auditoría de cada ingreso, fallo y acción."],
              ["Inyección de instrucciones en el modelo", "Prompt injection",
               "Los datos del comprador entran como datos, separados de la consigna y recortados; "
               "la respuesta se valida (nombre, importe exacto, sin otras cifras) y, si no pasa, "
               "se usa la plantilla."],
              ["Espiar la pantalla con saldos", "Privacidad",
               "FLAG_SECURE opcional: bloquea capturas y oculta la app en la lista de recientes."],
              ["Uso de la app para molestar a terceros", "Abuso",
               "Tope de 5 códigos por hora por dirección y de envíos por hora; sólo se invita a "
               "quien ya tiene cuenta."],
              ["Pérdida de datos", "Disponibilidad",
               "Copias cifradas diarias en dos nubes distintas, con restauración probada "
               "automáticamente cada mes (base y archivos)."],
              ["Retención indefinida", "Privacidad",
               "Borrado automático 6 meses después de liquidada la campaña; baja de cuenta que "
               "anonimiza de forma irreversible."],
          ], [4.3 * cm, 3.2 * cm, 9 * cm])]

    # ------------------------------------------------------------- 7. co-work
    h += [PageBreak(), Paragraph("7. IAs usadas en el co-work de desarrollo", H2),
          tabla([
              ["Herramienta", "Para qué se usó", "Aportó bien / mal / sorprendió"],
              ["Claude Opus 5 (Claude Code)",
               "Orquestación, infraestructura, seguridad, sistema de diseño, pruebas de punta a "
               "punta, IA local.",
               "Sorprendió en infraestructura: dejó copias cifradas en dos nubes con restauración "
               "probada, algo que a mano se posterga siempre."],
              ["Gemini 3.8 Flash (Antigravity)",
               "Fases 2 a 7: rifa, modo sin señal, liquidación, productos, sorteo, avisos, y la "
               "pantalla del recordatorio con IA.",
               "Bien en volumen: 43 commits con la app y la API completas siguiendo el documento "
               "de traspaso, sin intervención sobre el código."],
              ["Llama 3.2 3B (Ollama, local)",
               "Redacta el recordatorio de deuda dentro del producto.",
               "Bien con consignas cerradas; mal en preguntas abiertas: en la prueba inventó un "
               "«algoritmo de gestión de loterías» que no existe."],
          ], [4 * cm, 6 * cm, 6.5 * cm])]
    h += [captura("07-recordatorio-escrito-por-la-IA-local.png",
                  "El modelo del servidor redacta el recordatorio; la app avisa que lo escribió "
                  "la IA y que hay que revisarlo antes de mandarlo.", 10 * cm)]
    h += [Paragraph("Reflexión", H2)]
    h += parrafos(
        "Sin co-work no existiría la mitad de lo que no se ve: las copias con restauración "
        "probada, el panel con segundo factor y 407 pruebas automáticas contra producción. En un "
        "proyecto de una persona eso se deja para después y nunca se hace.",
        "Lo que la IA hizo mal fue casi siempre <b>por no preguntar</b>. Un error de "
        "autenticación quemaba el código de acceso cuando faltaban datos y dejaba al usuario "
        "afuera. El tope de ventas del plan gratis se aplicó también a las rifas, que se miden "
        "por talonario. Los importes se mostraban como «15.000 $» en vez de «$ 15.000». Y una "
        "versión del APK no abría: el SDK de anuncios arrastra WorkManager, y el ofuscador "
        "renombraba una clase que Room busca por reflexión; ni las pruebas ni el analizador "
        "estático lo detectan, sólo instalarlo en un teléfono.",
        "La conclusión práctica del curso: el agente acelera la construcción, pero el criterio "
        "—qué es correcto para este negocio— sigue siendo humano, y hay que escribirlo en algún "
        "lado que el agente lea. En este proyecto ese lugar son la definición, el documento de "
        "traspaso y la skill de diseño.",
    )

    # ------------------------------------------------------ Parte 2 · IA local
    h += [PageBreak(), Paragraph("Parte 2 · IA local en el proyecto", H1)]
    h += parrafos(
        "<b>Qué se instaló.</b> Ollama con Llama 3.2 3B (2 GB) en el mismo VPS de la aplicación: "
        "Oracle A1, ARM, 4 núcleos, 23 GB de RAM y <b>sin GPU</b>. Escucha sólo en la puerta de "
        "enlace de la red interna de Docker: no está publicado en internet y el firewall acepta "
        "ese puerto únicamente desde esa subred.",
    )
    h += [Paragraph("1. Qué papel juega el modelo local", H2)]
    h += parrafos(
        "Es un <b>subagente de soporte</b>, nunca el que decide sobre la plata. Hoy hace una sola "
        "cosa: redactar el mensaje con el que un vendedor le recuerda a un comprador que debe su "
        "parte. Antes ese texto salía de una plantilla fija, siempre igual. No reemplaza ninguna "
        "API externa, porque el producto no usaba IA: <b>habilita algo que antes no se podía "
        "hacer</b>, porque mandar el nombre y la deuda de un tercero a una nube ajena no es "
        "aceptable.",
    )
    h += [Paragraph("2. Qué le aporta al usuario", H2)]
    h += parrafos(
        "Que la app escriba por él. Redactar un mensaje para cobrarle a un vecino es incómodo y "
        "por eso la deuda se posterga; que el sistema proponga el texto acelera la cobranza, que "
        "es el problema real del grupo. Y sobre todo: <b>los datos no salen del servidor</b>. "
        "Nombres y teléfonos de compradores son datos de terceros que nunca dieron consentimiento; "
        "con el modelo local, esa conversación legal no existe. El costo por token es cero, así "
        "que la función puede estar en el plan gratuito.",
    )
    h += [Paragraph("3. Qué aporta como profesional", H2)]
    h += parrafos(
        "Poder mirar lo que hoy no se puede mirar. Están los registros de operación, los "
        "movimientos y los avisos, pero analizarlos con una nube implicaría exportar datos "
        "personales. Con un modelo local se le puede preguntar al registro en qué pantalla "
        "abandona la gente, qué campañas se traban antes de liquidar o qué errores se repiten, "
        "sin sacar un byte del servidor. El análisis deja de ser un proyecto y pasa a ser una "
        "pregunta.",
    )
    h += [Paragraph("4. Limitaciones frente a una API en la nube", H2)]
    h += parrafos(
        "<b>Hardware:</b> 4 núcleos ARM sin GPU dan ≈14 tokens por segundo; un mensaje tarda "
        "entre 7 y 18 segundos. Sirve para una acción que la persona pide a propósito, no para "
        "algo que se escriba mientras mira la pantalla.",
        "<b>Calidad:</b> un modelo de 3B razona mal en preguntas abiertas. En la prueba de la "
        "terminal se inventó un «algoritmo de gestión de loterías» y ni mencionó la privacidad, "
        "que era la respuesta correcta. Por eso en el producto sólo recibe consignas cerradas, "
        "con ejemplo y datos concretos, y aun así se valida lo que devuelve: si no nombra a la "
        "persona, si no dice el importe exacto, si aparece cualquier otra cifra en pesos o si "
        "hace preguntas, se descarta y se usa la plantilla.",
        "<b>Mantenimiento:</b> actualizar el modelo, medir que no empeore y sostener las pruebas "
        "pasa a ser responsabilidad propia. Por eso el diseño lo deja como accesorio: si el "
        "modelo no está, la app funciona igual.",
        "<b>Medición registrada:</b> en la primera prueba, con el modelo todavía inalcanzable, el "
        "sistema devolvió la plantilla en 58 ms sin un solo error. Con el modelo disponible, "
        "redactó en 17,9 segundos. El detalle completo está en docs/ANEXO_IA_LOCAL.md.",
    )

    # ---------------------------------------------------------------- cierre
    h += [PageBreak(), Paragraph("Estado y próximos pasos", H1)]
    h += [tabla([
        ["Criterio de evaluación", "Estado"],
        ["App funcionando y demostrable",
         "Publicada y en uso: APK descargable, servidor en línea, video y capturas."],
        ["Arquitectura documentada",
         "Diagramas en DEFINICION.md (arquitectura, agentes, secuencia) y tabla de stack completa."],
        ["Evaluación UX/UI", "10 heurísticas evaluadas y prueba con usuaria real, con correcciones aplicadas."],
        ["Ciberseguridad", "10 riesgos con la medida tomada en cada uno."],
        ["Parte 2 · IA local", "Modelo corriendo en el VPS, integrado al producto y medido."],
    ], [7 * cm, 9.5 * cm])]
    h += [Spacer(1, 10)]
    h += parrafos(
        "<b>Lo que sigue.</b> Configurar Firebase para las notificaciones push y AdMob con las "
        "cuentas reales; cargar las credenciales de MercadoPago para habilitar el cobro de planes; "
        "y una prueba cerrada con uno o dos grupos reales antes de mover Miti a su dominio propio.",
    )

    doc.build(h, onFirstPage=encabezado_pie, onLaterPages=encabezado_pie)
    print(f"listo: {SALIDA}")


if __name__ == "__main__":
    construir()
