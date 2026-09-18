import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';

/// Generador de imagen con la grilla de números disponibles para compartir en redes (historias o post).
class PantallaCompartirDisponibles extends StatefulWidget {
  const PantallaCompartirDisponibles({
    super.key,
    required this.campanaNombre,
    required this.precioUnitario,
    required this.numeros,
    this.fechaSorteo,
  });

  final String campanaNombre;
  final int precioUnitario;
  final List<Map<String, dynamic>> numeros;
  final String? fechaSorteo;

  @override
  State<PantallaCompartirDisponibles> createState() => _PantallaCompartirDisponiblesState();
}

class _PantallaCompartirDisponiblesState extends State<PantallaCompartirDisponibles> {
  final GlobalKey _canvasKey = GlobalKey();
  final ImagePicker _picker = ImagePicker();

  File? _imagenFondo;
  bool _formatoHistoria = true; // true: 9:16, false: 4:5
  bool _generando = false;

  // Parámetros del recuadro central donde se ubica la grilla
  double _posicionY = 0.32; // de 0.05 a 0.65
  final double _anchoRecuadro = 0.88; // fijo per diseño
  double _altoRecuadro = 0.54; // de 0.35 a 0.75
  final double _opacidadPapel = 0.94; // semi-opaco para contrastar sobre fotos

  bool _mostrarAjustes = false;

  Future<void> _elegirFondo() async {
    try {
      final XFile? foto = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2160,
        maxHeight: 2160,
        imageQuality: 90,
      );
      if (foto != null) {
        setState(() => _imagenFondo = File(foto.path));
      }
    } catch (_) {
      if (mounted) mostrarAviso(context, 'No se pudo cargar la imagen', error: true);
    }
  }

  Future<void> _compartirEnRedes() async {
    if (_generando) return;
    setState(() => _generando = true);

    try {
      final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('No se encontró el lienzo');

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('No se pudieron obtener los datos de la imagen');

      final tempDir = await getTemporaryDirectory();
      final ahoraMs = DateTime.now().millisecondsSinceEpoch;
      final archivo = File('${tempDir.path}/disponibles_$ahoraMs.png');
      await archivo.writeAsBytes(byteData.buffer.asUint8List());

      final libres = widget.numeros.where((n) => n['estado'] == 'libre').length;
      final texto = '🎟️ ¡Elegí tu número para *${widget.campanaNombre}*!\n'
          'Quedan $libres números disponibles a ${plata(widget.precioUnitario)} cada uno.\n'
          '${widget.fechaSorteo != null ? '📅 Fecha de sorteo: ${widget.fechaSorteo}\n' : ''}'
          '¡Escribime para reservar el tuyo!';

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(archivo.path, mimeType: 'image/png')],
          text: texto,
        ),
      );
    } catch (e) {
      if (mounted) mostrarAviso(context, 'No se pudo exportar la imagen', error: true);
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final ahora = DateFormat('dd/MM HH:mm').format(DateTime.now());

    final libres = widget.numeros.where((n) => n['estado'] == 'libre').length;

    return Scaffold(
      appBar: AppBar(
        title: Text('COMPARTIR DISPONIBLES', style: t.seccion.copyWith(color: c.tinta)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.tinta),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: _mostrarAjustes ? 'Ocultar ajustes' : 'Ajustar recuadro',
            icon: Icon(_mostrarAjustes ? Icons.tune : Icons.tune_outlined, color: c.tinta),
            onPressed: () => setState(() => _mostrarAjustes = !_mostrarAjustes),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Barra superior de formatos y fondo
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  MitiChip(
                    texto: 'Historia 9:16',
                    activo: _formatoHistoria,
                    onTap: () => setState(() => _formatoHistoria = true),
                  ),
                  const SizedBox(width: 8),
                  MitiChip(
                    texto: 'Post 4:5',
                    activo: !_formatoHistoria,
                    onTap: () => setState(() => _formatoHistoria = false),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _elegirFondo,
                    icon: Icon(Icons.add_photo_alternate_outlined, size: 18, color: c.selloTexto),
                    label: Text(
                      _imagenFondo == null ? 'Poner fondo' : 'Cambiar fondo',
                      style: t.etiqueta.copyWith(color: c.selloTexto),
                    ),
                  ),
                ],
              ),
            ),

            // Controles de ajuste si está desplegado
            if (_mostrarAjustes) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                decoration: BoxDecoration(
                  color: c.hoja,
                  border: Border.all(color: c.tinta, width: 1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('POSICIÓN VERTICAL DEL RECUADRO', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                        Text('${(_posicionY * 100).toInt()}%', style: t.pie.copyWith(color: c.tinta)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: c.tinta,
                        thumbColor: c.sello,
                      ),
                      child: Slider(
                        value: _posicionY,
                        min: 0.05,
                        max: 0.65,
                        onChanged: (v) => setState(() => _posicionY = v),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('ALTO DEL RECUADRO', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                        Text('${(_altoRecuadro * 100).toInt()}%', style: t.pie.copyWith(color: c.tinta)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: c.tinta,
                        thumbColor: c.sello,
                      ),
                      child: Slider(
                        value: _altoRecuadro,
                        min: 0.35,
                        max: 0.75,
                        onChanged: (v) => setState(() => _altoRecuadro = v),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Canvas interactivo con el fondo y el recuadro ajustable
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: AspectRatio(
                    aspectRatio: _formatoHistoria ? 9 / 16 : 4 / 5,
                    child: RepaintBoundary(
                      key: _canvasKey,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // 1. Imagen de fondo o papel claro base
                            if (_imagenFondo != null)
                              Image.file(
                                _imagenFondo!,
                                fit: BoxFit.cover,
                              )
                            else
                              Container(
                                color: const Color(0xFFFBF9F4),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.image_outlined, size: 48, color: const Color(0xFF5F5A4E).withValues(alpha: 0.4)),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Fondo blanco de papel',
                                      style: TextStyle(
                                        fontFamily: 'Figtree',
                                        color: Color(0xFF5F5A4E),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // 2. Encabezado de la campaña (visible si no hay imagen de fondo o arriba)
                            if (_imagenFondo == null)
                              Positioned(
                                top: 18,
                                left: 16,
                                right: 16,
                                child: Column(
                                  children: [
                                    Text(
                                      widget.campanaNombre.toUpperCase(),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontFamily: 'BigShoulders',
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF1E2A3A),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${plata(widget.precioUnitario)} cada número · $libres disponibles',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontFamily: 'Figtree',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF5F5A4E),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // 3. Recuadro ajustable donde se ubica la grilla
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final topOffset = constraints.maxHeight * _posicionY;
                                final boxWidth = constraints.maxWidth * _anchoRecuadro;
                                final boxHeight = constraints.maxHeight * _altoRecuadro;

                                return Positioned(
                                  top: topOffset,
                                  left: (constraints.maxWidth - boxWidth) / 2,
                                  width: boxWidth,
                                  height: boxHeight,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFBF9F4).withValues(alpha: _opacidadPapel),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF1E2A3A), width: 1.5),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.15),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        // Título del recuadro
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'NÚMEROS DISPONIBLES ($libres)',
                                              style: const TextStyle(
                                                fontFamily: 'Figtree',
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF1E2A3A),
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                            Text(
                                              plata(widget.precioUnitario),
                                              style: const TextStyle(
                                                fontFamily: 'BigShoulders',
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF1E2A3A),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),

                                        // Grilla de números
                                        Expanded(
                                          child: GridView.builder(
                                            physics: const NeverScrollableScrollPhysics(),
                                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 10,
                                              crossAxisSpacing: 2.5,
                                              mainAxisSpacing: 2.5,
                                              childAspectRatio: 1.05,
                                            ),
                                            itemCount: widget.numeros.length,
                                            itemBuilder: (context, i) {
                                              final num = widget.numeros[i];
                                              final n = num['numero'] as int;
                                              final estado = num['estado'] as String;
                                              final estaLibre = estado == 'libre';

                                              return Container(
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: estaLibre ? Colors.white : const Color(0xFFE4DDCB),
                                                  borderRadius: BorderRadius.circular(2),
                                                  border: estaLibre
                                                      ? Border.all(color: const Color(0xFF1E2A3A), width: 0.8)
                                                      : null,
                                                ),
                                                child: estaLibre
                                                    ? Text(
                                                        n.toString().padLeft(2, '0'),
                                                        style: const TextStyle(
                                                          fontFamily: 'BigShoulders',
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.w800,
                                                          color: Color(0xFF1E2A3A),
                                                        ),
                                                      )
                                                    : null, // Casilla en blanco si está vendido o reservado
                                              );
                                            },
                                          ),
                                        ),

                                        const SizedBox(height: 4),
                                        // Pie dentro del recuadro
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              widget.fechaSorteo != null ? 'Sorteo: ${widget.fechaSorteo}' : '¡Pedí el tuyo!',
                                              style: const TextStyle(
                                                fontFamily: 'Figtree',
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF1E2A3A),
                                              ),
                                            ),
                                            Text(
                                              'Act. $ahora',
                                              style: const TextStyle(
                                                fontFamily: 'Figtree',
                                                fontSize: 9,
                                                color: Color(0xFF5F5A4E),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Botón inferior para exportar y compartir
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: MitiBoton(
                texto: 'Compartir en redes sociales',
                icono: Icons.share_rounded,
                cargando: _generando,
                onTap: _compartirEnRedes,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
