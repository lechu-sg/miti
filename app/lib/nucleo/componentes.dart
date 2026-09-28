import 'package:flutter/material.dart';

import 'tema.dart';

/// Botón principal: el "sello". Uno solo por pantalla.
class MitiBoton extends StatelessWidget {
  const MitiBoton({
    super.key,
    required this.texto,
    this.onTap,
    this.secundario = false,
    this.cargando = false,
    this.icono,
  });

  final String texto;
  final VoidCallback? onTap;
  final bool secundario;
  final bool cargando;
  final IconData? icono;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final apagado = onTap == null || cargando;
    final fondo = secundario ? Colors.transparent : c.sello;
    final letra = secundario ? c.tinta : Colors.white;

    return Opacity(
      opacity: apagado ? 0.55 : 1,
      child: Material(
        color: fondo,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: apagado ? null : onTap,
          child: Container(
            height: 52,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: secundario ? Border.all(color: c.tinta, width: 1.5) : null,
            ),
            child: cargando
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: letra),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icono != null) ...[Icon(icono, size: 20, color: letra), const SizedBox(width: 8)],
                      // Flexible: un texto largo se parte en dos líneas en vez de desbordar el botón.
                      Flexible(
                        child: Text(
                          texto,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.texto.cuerpo.copyWith(fontWeight: FontWeight.w700, color: letra),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Línea troquelada: separa las partes de un talón.
class MitiTroquel extends StatelessWidget {
  const MitiTroquel({super.key, this.color, this.grosor = 1});

  final Color? color;
  final double grosor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(double.infinity, grosor),
      painter: _PintorTroquel(color ?? context.color.troquel, grosor),
    );
  }
}

class _PintorTroquel extends CustomPainter {
  _PintorTroquel(this.color, this.grosor);

  final Color color;
  final double grosor;

  @override
  void paint(Canvas lienzo, Size medida) {
    final pincel = Paint()
      ..color = color
      ..strokeWidth = grosor;
    const trazo = 5.0;
    const hueco = 4.0;
    for (var x = 0.0; x < medida.width; x += trazo + hueco) {
      lienzo.drawLine(Offset(x, 0), Offset(x + trazo, 0), pincel);
    }
  }

  @override
  bool shouldRepaint(_PintorTroquel otro) => otro.color != color || otro.grosor != grosor;
}

/// El ticket de recaudación: relleno de tinta, con su talón a la derecha.
class MitiTicket extends StatelessWidget {
  const MitiTicket({
    super.key,
    required this.sobrelinea,
    required this.importe,
    this.detalle,
    this.progreso,
    this.pie,
    this.talonArriba,
    this.talonAbajo,
  });

  final String sobrelinea;
  final String importe;
  final String? detalle;
  final double? progreso;
  final String? pie;
  final String? talonArriba;
  final String? talonAbajo;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    return Container(
      decoration: BoxDecoration(color: c.tinta, borderRadius: BorderRadius.circular(6)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(sobrelinea.toUpperCase(),
                        style: t.sobrelinea.copyWith(color: c.tintaSobre.withValues(alpha: 0.75))),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(importe, style: t.importe.copyWith(color: c.tintaSobre)),
                    ),
                    if (detalle != null) ...[
                      const SizedBox(height: 4),
                      Text(detalle!,
                          style: t.pie.copyWith(color: c.tintaSobre.withValues(alpha: 0.85), fontSize: 13)),
                    ],
                    if (progreso != null) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progreso!.clamp(0, 1),
                          minHeight: 8,
                          backgroundColor: c.tintaSobre.withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation(c.mostaza),
                        ),
                      ),
                    ],
                    if (pie != null) ...[
                      const SizedBox(height: 6),
                      Text(pie!, style: t.pie.copyWith(color: c.tintaSobre.withValues(alpha: 0.75))),
                    ],
                  ],
                ),
              ),
            ),
            if (talonArriba != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SizedBox(
                  width: 2,
                  child: CustomPaint(
                    painter: _PintorTroquelVertical(c.tintaSobre.withValues(alpha: 0.45)),
                  ),
                ),
              ),
              SizedBox(
                // Alcanza para "200" (cantidad de números) y para un importe
                // como "$ 93.700", que antes se partía letra por letra.
                width: 118,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(talonArriba!,
                          maxLines: 1,
                          style: t.importe.copyWith(color: c.tintaSobre, fontSize: 36, height: 1)),
                    ),
                    if (talonAbajo != null)
                      Text(talonAbajo!.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: t.sobrelinea.copyWith(
                            color: c.tintaSobre.withValues(alpha: 0.75),
                            fontSize: 11,
                            letterSpacing: 1.1,
                          )),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PintorTroquelVertical extends CustomPainter {
  _PintorTroquelVertical(this.color);

  final Color color;

  @override
  void paint(Canvas lienzo, Size medida) {
    final pincel = Paint()
      ..color = color
      ..strokeWidth = 2;
    const trazo = 5.0;
    const hueco = 4.0;
    for (var y = 0.0; y < medida.height; y += trazo + hueco) {
      lienzo.drawLine(Offset(1, y), Offset(1, y + trazo), pincel);
    }
  }

  @override
  bool shouldRepaint(_PintorTroquelVertical otro) => otro.color != color;
}

/// Aviso de lo que espera una decisión. Es la única pieza que va girada.
class MitiAviso extends StatelessWidget {
  const MitiAviso({super.key, required this.cantidad, required this.texto, this.onTap});

  final int cantidad;
  final String texto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    return Transform.rotate(
      angle: -0.01,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: c.sello, width: 2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Text('$cantidad',
                  style: context.texto.seccion.copyWith(color: c.selloTexto, fontSize: 30)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(texto,
                    style: context.texto.cuerpo.copyWith(
                      color: c.selloTexto,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    )),
              ),
              Icon(Icons.chevron_right, color: c.selloTexto),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar con iniciales.
class MitiIniciales extends StatelessWidget {
  const MitiIniciales(this.texto, {super.key, this.medida = 36});

  final String texto;
  final double medida;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    return Container(
      width: medida,
      height: medida,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.tinta, width: 1.5),
      ),
      child: Text(texto,
          style: context.texto.etiqueta.copyWith(fontWeight: FontWeight.w700, color: c.tinta)),
    );
  }
}

/// Chip de filtro o de estado.
class MitiChip extends StatelessWidget {
  const MitiChip({super.key, required this.texto, this.activo = false, this.onTap});

  final String texto;
  final bool activo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: activo ? c.tinta : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: activo ? null : Border.all(color: c.tinta, width: 1.5),
        ),
        child: Text(
          texto,
          style: context.texto.etiqueta.copyWith(
            color: activo ? c.tintaSobre : c.tinta,
            fontWeight: activo ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Estado vacío: qué falta y qué se puede hacer.
class MitiVacio extends StatelessWidget {
  const MitiVacio({super.key, required this.titulo, required this.detalle, this.accion});

  final String titulo;
  final String detalle;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(color: c.troquel, width: 2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.receipt_long_outlined, size: 40, color: c.tintaSuave),
            ),
            const SizedBox(height: 18),
            Text(titulo, textAlign: TextAlign.center, style: context.texto.seccion.copyWith(color: c.tinta)),
            const SizedBox(height: 8),
            Text(detalle,
                textAlign: TextAlign.center,
                style: context.texto.cuerpo.copyWith(color: c.tintaSuave)),
            if (accion != null) ...[const SizedBox(height: 20), accion!],
          ],
        ),
      ),
    );
  }
}

void mostrarAviso(BuildContext context, String mensaje, {bool error = false}) {
  final c = context.color;
  // Con el teclado abierto el aviso queda tapado: lo bajamos antes de mostrarlo.
  if (error) FocusManager.instance.primaryFocus?.unfocus();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          // Sobre el rojo del sello, la letra va blanca sí o sí.
          style: context.texto.cuerpo.copyWith(
            color: error ? Colors.white : c.tintaSobre,
            fontWeight: error ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        backgroundColor: error ? c.sello : c.tinta,
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
}

/// Celda de número en la grilla de rifa.
class MitiCeldaNumero extends StatelessWidget {
  const MitiCeldaNumero({
    super.key,
    required this.numero,
    required this.estado,
    this.seleccionado = false,
    this.onTap,
  });

  final int numero;
  final String estado; // libre, reservado, vendido
  final bool seleccionado;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    Color fondo;
    Color bordeColor;
    Color letraColor;
    bool punteado = false;

    if (seleccionado) {
      fondo = c.sello;
      bordeColor = c.sello;
      letraColor = Colors.white;
    } else if (estado == 'vendido') {
      fondo = c.vendido;
      bordeColor = Colors.transparent;
      letraColor = c.vendidoTexto;
    } else if (estado == 'reservado') {
      fondo = Colors.transparent;
      bordeColor = c.sello;
      letraColor = c.selloTexto;
      punteado = true;
    } else {
      // libre
      fondo = Colors.transparent;
      bordeColor = c.tinta;
      letraColor = c.tinta;
    }

    final textoFormateado = numero.toString().padLeft(2, '0');

    return InkWell(
      onTap: estado == 'vendido' ? null : onTap,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(3),
          border: punteado
              ? Border.all(color: bordeColor, width: 1.5, strokeAlign: BorderSide.strokeAlignCenter)
              : (bordeColor != Colors.transparent ? Border.all(color: bordeColor, width: 1.5) : null),
        ),
        child: Text(
          textoFormateado,
          style: t.cifra.copyWith(
            color: letraColor,
            fontSize: 16,
            height: 1,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Selector de destino del dinero (grilla 2x2).
class MitiDestinoDinero extends StatelessWidget {
  const MitiDestinoDinero({
    super.key,
    required this.seleccionado,
    required this.onCambio,
  });

  final String seleccionado; // billetera, efectivo, cuenta_principal, adeudado
  final ValueChanged<String> onCambio;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _opcion(
                context,
                clave: 'efectivo',
                titulo: 'En efectivo',
                aclaracion: 'Lo tenés vos',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _opcion(
                context,
                clave: 'billetera',
                titulo: 'En mi billetera',
                aclaracion: 'En tu cuenta propia',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _opcion(
                context,
                clave: 'cuenta_principal',
                titulo: 'Cuenta principal',
                aclaracion: 'Pasa a confirmar',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _opcion(
                context,
                clave: 'adeudado',
                titulo: 'Todavía no pagó',
                aclaracion: 'Queda adeudado',
                esDeuda: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _opcion(
    BuildContext context, {
    required String clave,
    required String titulo,
    required String aclaracion,
    bool esDeuda = false,
  }) {
    final c = context.color;
    final t = context.texto;
    final activa = seleccionado == clave;

    return InkWell(
      onTap: () => onCambio(clave),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: activa ? c.tinta : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: activa ? c.tinta : (esDeuda ? c.sello : c.tinta),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              titulo,
              style: t.etiqueta.copyWith(
                color: activa ? c.tintaSobre : (esDeuda ? c.selloTexto : c.tinta),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              aclaracion,
              style: t.pie.copyWith(
                color: activa ? c.tintaSobre.withValues(alpha: 0.75) : c.tintaSuave,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Contenedor estándar para hojas inferiores (bottom sheets) de Talonario.
class MitiHoja extends StatelessWidget {
  const MitiHoja({
    super.key,
    required this.titulo,
    required this.child,
    this.subtitulo,
  });

  final String titulo;
  final String? subtitulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: c.hoja,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          boxShadow: [
            BoxShadow(
              color: c.tinta.withValues(alpha: 0.12),
              blurRadius: 30,
              offset: const Offset(0, -12),
            ),
          ],
        ),
        child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MitiTroquel(grosor: 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (subtitulo != null) ...[
                          Text(subtitulo!.toUpperCase(), style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                          const SizedBox(height: 2),
                        ],
                        Text(titulo, style: t.seccion.copyWith(color: c.tinta)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: c.tinta),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: child,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}

/// Error que se muestra dentro de la pantalla o de la hoja, donde el teclado no lo tapa.
class MitiErrorEnLinea extends StatelessWidget {
  const MitiErrorEnLinea({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: c.sello, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: c.selloTexto),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto, style: t.cuerpo.copyWith(color: c.selloTexto, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
