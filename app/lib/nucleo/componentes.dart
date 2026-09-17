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
                      Text(
                        texto,
                        style: context.texto.cuerpo.copyWith(fontWeight: FontWeight.w700, color: letra),
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
                width: 86,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(talonArriba!,
                        style: t.importe.copyWith(color: c.tintaSobre, fontSize: 36, height: 1)),
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
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? c.sello : c.tinta,
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
}
