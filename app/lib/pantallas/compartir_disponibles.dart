import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../nucleo/componentes.dart';
import '../nucleo/tema.dart';
import '../nucleo/publicidad.dart';

/// Generador de imagen con la grilla de números disponibles para compartir en redes.
/// Permite seleccionar el afiche/flyer de fondo y recortar el área donde se colocarán
/// exclusivamente los números disponibles mediante un cuadro interactivo arrastrable.
class PantallaCompartirDisponibles extends StatefulWidget {
  const PantallaCompartirDisponibles({
    super.key,
    required this.campanaNombre,
    required this.precioUnitario,
    required this.numeros,
    this.fechaSorteo,
    this.conPublicidad = false,
  });

  /// Plan con publicidad: al generar la imagen puede aparecer un intersticial.
  final bool conPublicidad;
  final String campanaNombre;
  final int precioUnitario;
  final List<Map<String, dynamic>> numeros;
  final String? fechaSorteo;

  @override
  State<PantallaCompartirDisponibles> createState() => _PantallaCompartirDisponiblesState();
}

enum _EstiloContraste {
  papelClaro,
  papelOscuro,
  textoNegro,
  textoBlanco,
}

class _PantallaCompartirDisponiblesState extends State<PantallaCompartirDisponibles> {
  final GlobalKey _canvasKey = GlobalKey();
  final ImagePicker _picker = ImagePicker();

  File? _imagenFondo;
  double _aspectRatioImagen = 9 / 16;
  bool _generando = false;
  bool _modoExportacion = false;

  // Cuadro delimitador en coordenadas relativas (0.0 a 1.0)
  double _boxLeft = 0.10;
  double _boxTop = 0.35;
  double _boxWidth = 0.80;
  double _boxHeight = 0.35;

  _EstiloContraste _estilo = _EstiloContraste.papelClaro;

  // Rango de números visibles
  late int _minTotal;
  late int _maxTotal;
  late int _rangoDesde;
  late int _rangoHasta;

  // Mapa rápido de estado por número
  late Map<int, String> _estadoPorNumero;

  @override
  void initState() {
    super.initState();
    _inicializarRango();
  }

  void _inicializarRango() {
    _estadoPorNumero = {
      for (final n in widget.numeros) n['numero'] as int: n['estado'] as String,
    };

    final todos = widget.numeros.map((n) => n['numero'] as int).toList()..sort();
    if (todos.isNotEmpty) {
      _minTotal = todos.first;
      _maxTotal = todos.last;
    } else {
      _minTotal = 0;
      _maxTotal = 99;
    }

    final totalCount = _maxTotal - _minTotal + 1;
    _rangoDesde = _minTotal;
    if (totalCount <= 200) {
      _rangoHasta = _maxTotal;
    } else {
      _rangoHasta = math.min(_minTotal + 99, _maxTotal);
    }
  }

  Future<void> _elegirFondo() async {
    try {
      final XFile? foto = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2560,
        maxHeight: 2560,
        imageQuality: 92,
      );
      if (foto == null) return;

      final bytes = await File(foto.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      final img = frameInfo.image;
      final ratio = (img.width > 0 && img.height > 0) ? (img.width / img.height) : (9 / 16);

      setState(() {
        _imagenFondo = File(foto.path);
        _aspectRatioImagen = ratio;
      });
    } catch (_) {
      if (mounted) mostrarAviso(context, 'No se pudo cargar la imagen', error: true);
    }
  }

  Future<void> _compartirEnRedes() async {
    if (_generando) return;
    if (_imagenFondo == null) {
      mostrarAviso(context, 'Primero seleccioná una imagen de fondo', error: true);
      return;
    }

    setState(() {
      _generando = true;
      _modoExportacion = true;
    });

    await WidgetsBinding.instance.endOfFrame;

    try {
      final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('No se encontró el lienzo');

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Error al procesar la imagen');

      final tempDir = await getTemporaryDirectory();
      final ahoraMs = DateTime.now().millisecondsSinceEpoch;
      final archivo = File('${tempDir.path}/miti_disponibles_$ahoraMs.png');
      await archivo.writeAsBytes(byteData.buffer.asUint8List());

      // Contar libres dentro del rango mostrado
      int libresEnRango = 0;
      for (int n = _rangoDesde; n <= _rangoHasta; n++) {
        if (_estadoPorNumero[n] == 'libre') libresEnRango++;
      }

      final texto = '🎟️ ¡Elegí tu número para ${widget.campanaNombre}!\n'
          'Quedan $libresEnRango números disponibles entre el $_rangoDesde y el $_rangoHasta.\n'
          '¡Escribime para reservar el tuyo!';

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(archivo.path, mimeType: 'image/png')],
          text: texto,
        ),
      );
      if (widget.conPublicidad) await Publicidad.intersticialAlGenerarImagen();
    } catch (e) {
      if (mounted) mostrarAviso(context, 'No se pudo exportar la imagen', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _generando = false;
          _modoExportacion = false;
        });
      }
    }
  }

  void _moverCuadro(double dxRel, double dyRel) {
    setState(() {
      _boxLeft = (_boxLeft + dxRel).clamp(0.0, 1.0 - _boxWidth);
      _boxTop = (_boxTop + dyRel).clamp(0.0, 1.0 - _boxHeight);
    });
  }

  void _redimensionarEsquina({
    required bool arriba,
    required bool izquierda,
    required double dxRel,
    required double dyRel,
  }) {
    const minW = 0.15;
    const minH = 0.08;

    setState(() {
      if (izquierda) {
        final newLeft = (_boxLeft + dxRel).clamp(0.0, _boxLeft + _boxWidth - minW);
        _boxWidth += (_boxLeft - newLeft);
        _boxLeft = newLeft;
      } else {
        final newRight = (_boxLeft + _boxWidth + dxRel).clamp(_boxLeft + minW, 1.0);
        _boxWidth = newRight - _boxLeft;
      }

      if (arriba) {
        final newTop = (_boxTop + dyRel).clamp(0.0, _boxTop + _boxHeight - minH);
        _boxHeight += (_boxTop - newTop);
        _boxTop = newTop;
      } else {
        final newBottom = (_boxTop + _boxHeight + dyRel).clamp(_boxTop + minH, 1.0);
        _boxHeight = newBottom - _boxTop;
      }
    });
  }

  void _redimensionarBorde({
    bool? horizontal,
    required bool inicio,
    required double dxRel,
    required double dyRel,
  }) {
    const minW = 0.15;
    const minH = 0.08;

    setState(() {
      if (horizontal == true) {
        if (inicio) {
          final newLeft = (_boxLeft + dxRel).clamp(0.0, _boxLeft + _boxWidth - minW);
          _boxWidth += (_boxLeft - newLeft);
          _boxLeft = newLeft;
        } else {
          final newRight = (_boxLeft + _boxWidth + dxRel).clamp(_boxLeft + minW, 1.0);
          _boxWidth = newRight - _boxLeft;
        }
      } else {
        if (inicio) {
          final newTop = (_boxTop + dyRel).clamp(0.0, _boxTop + _boxHeight - minH);
          _boxHeight += (_boxTop - newTop);
          _boxTop = newTop;
        } else {
          final newBottom = (_boxTop + _boxHeight + dyRel).clamp(_boxTop + minH, 1.0);
          _boxHeight = newBottom - _boxTop;
        }
      }
    });
  }

  void _abrirAjusteRango() {
    final c = context.color;
    final t = context.texto;
    final desdeCtrl = TextEditingController(text: '$_rangoDesde');
    final hastaCtrl = TextEditingController(text: '$_rangoHasta');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: MitiHoja(
            titulo: 'RANGO DE NÚMEROS A MOSTRAR',
            subtitulo: 'TOTAL DE LA RIFA: $_minTotal AL $_maxTotal',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Elegí qué números querés que salgan en esta imagen (máximo recomendado: 200 para que se lean bien).',
                  style: t.cuerpo.copyWith(color: c.tintaSuave),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: desdeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Desde el número',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: hastaCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Hasta el número',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                MitiBoton(
                  texto: 'Aplicar rango',
                  onTap: () {
                    final d = int.tryParse(desdeCtrl.text.trim()) ?? _rangoDesde;
                    final h = int.tryParse(hastaCtrl.text.trim()) ?? _rangoHasta;
                    if (d <= h && d >= _minTotal && h <= _maxTotal) {
                      setState(() {
                        _rangoDesde = d;
                        _rangoHasta = h;
                      });
                      Navigator.of(context).pop();
                    } else {
                      mostrarAviso(context, 'Rango no válido ($_minTotal a $_maxTotal)', error: true);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    final totalCount = _maxTotal - _minTotal + 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('NÚMEROS DISPONIBLES', style: t.seccion.copyWith(color: c.tinta)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.tinta),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_imagenFondo != null)
            TextButton.icon(
              onPressed: _elegirFondo,
              icon: Icon(Icons.photo_library_outlined, size: 18, color: c.selloTexto),
              label: Text('Cambiar foto', style: t.etiqueta.copyWith(color: c.selloTexto)),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_imagenFondo != null) ...[
              // 1. Selector de estilo de números
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text('Estilo: ', style: t.pie.copyWith(color: c.tintaSuave)),
                    const SizedBox(width: 4),
                    MitiChip(
                      texto: 'Fondo blanco',
                      activo: _estilo == _EstiloContraste.papelClaro,
                      onTap: () => setState(() => _estilo = _EstiloContraste.papelClaro),
                    ),
                    const SizedBox(width: 6),
                    MitiChip(
                      texto: 'Fondo oscuro',
                      activo: _estilo == _EstiloContraste.papelOscuro,
                      onTap: () => setState(() => _estilo = _EstiloContraste.papelOscuro),
                    ),
                    const SizedBox(width: 6),
                    MitiChip(
                      texto: 'Solo negros',
                      activo: _estilo == _EstiloContraste.textoNegro,
                      onTap: () => setState(() => _estilo = _EstiloContraste.textoNegro),
                    ),
                    const SizedBox(width: 6),
                    MitiChip(
                      texto: 'Solo blancos',
                      activo: _estilo == _EstiloContraste.textoBlanco,
                      onTap: () => setState(() => _estilo = _EstiloContraste.textoBlanco),
                    ),
                  ],
                ),
              ),

              // 2. Selector de rango Desde - Hasta
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Text('Números: ', style: t.pie.copyWith(color: c.tintaSuave)),
                    const SizedBox(width: 4),
                    // Si hay más de 100 números, mostramos tandas sugeridas
                    if (totalCount > 100) ...[
                      // Bloque 1: 0 a 99
                      MitiChip(
                        texto: '$_minTotal al ${math.min(_minTotal + 99, _maxTotal)}',
                        activo: _rangoDesde == _minTotal && _rangoHasta == math.min(_minTotal + 99, _maxTotal),
                        onTap: () => setState(() {
                          _rangoDesde = _minTotal;
                          _rangoHasta = math.min(_minTotal + 99, _maxTotal);
                        }),
                      ),
                      const SizedBox(width: 6),
                      // Bloque 2: 100 a 199 si existe
                      if (_maxTotal >= _minTotal + 100) ...[
                        MitiChip(
                          texto: '${_minTotal + 100} al ${math.min(_minTotal + 199, _maxTotal)}',
                          activo: _rangoDesde == _minTotal + 100 && _rangoHasta == math.min(_minTotal + 199, _maxTotal),
                          onTap: () => setState(() {
                            _rangoDesde = _minTotal + 100;
                            _rangoHasta = math.min(_minTotal + 199, _maxTotal);
                          }),
                        ),
                        const SizedBox(width: 6),
                      ],
                      // Opción hasta 200 juntos si la rifa llega a 200
                      if (_maxTotal <= _minTotal + 199 && totalCount > 100) ...[
                        MitiChip(
                          texto: '$_minTotal al $_maxTotal (todos)',
                          activo: _rangoDesde == _minTotal && _rangoHasta == _maxTotal,
                          onTap: () => setState(() {
                            _rangoDesde = _minTotal;
                            _rangoHasta = _maxTotal;
                          }),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                    // Botón para personalizar rango
                    ActionChip(
                      avatar: Icon(Icons.tune, size: 14, color: c.tinta),
                      label: Text('$_rangoDesde a $_rangoHasta', style: t.etiqueta.copyWith(color: c.tinta, fontSize: 11)),
                      backgroundColor: c.hoja,
                      side: BorderSide(color: c.tinta, width: 1),
                      onPressed: _abrirAjusteRango,
                    ),
                  ],
                ),
              ),
            ],

            // Vista principal: bienvenida o canvas interactivo
            Expanded(
              child: _imagenFondo == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c.tinta.withValues(alpha: 0.05),
                                border: Border.all(color: c.tintaSuave.withValues(alpha: 0.3)),
                              ),
                              child: Icon(Icons.add_photo_alternate_outlined, size: 56, color: c.tinta),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Elegí la imagen de la campaña',
                              style: t.seccion.copyWith(color: c.tinta, fontSize: 20),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Subí el flyer o afiche donde querés pegar los números disponibles.',
                              style: t.cuerpo.copyWith(color: c.tintaSuave),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            MitiBoton(
                              texto: 'Seleccionar imagen de la galería',
                              icono: Icons.photo_library_outlined,
                              onTap: _elegirFondo,
                            ),
                          ],
                        ),
                      ),
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            double viewW = constraints.maxWidth;
                            double viewH = constraints.maxHeight;

                            if (viewW / viewH > _aspectRatioImagen) {
                              viewW = viewH * _aspectRatioImagen;
                            } else {
                              viewH = viewW / _aspectRatioImagen;
                            }

                            return SizedBox(
                              width: viewW,
                              height: viewH,
                              child: RepaintBoundary(
                                key: _canvasKey,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // 1. Imagen de fondo
                                    Positioned.fill(
                                      child: Image.file(
                                        _imagenFondo!,
                                        fit: BoxFit.fill,
                                      ),
                                    ),

                                    // 2. Área delimitada con exactamente 10 números por fila, espacios libres y solo números
                                    Positioned(
                                      left: _boxLeft * viewW,
                                      top: _boxTop * viewH,
                                      width: _boxWidth * viewW,
                                      height: _boxHeight * viewH,
                                      child: _AreaNumerosDisponibles(
                                        rangoDesde: _rangoDesde,
                                        rangoHasta: _rangoHasta,
                                        estadoPorNumero: _estadoPorNumero,
                                        ancho: _boxWidth * viewW,
                                        alto: _boxHeight * viewH,
                                        estilo: _estilo,
                                      ),
                                    ),

                                    // 3. Cuadro interactivo de recorte (oculto en exportación)
                                    if (!_modoExportacion)
                                      _CuadroInteractivosEditor(
                                        viewW: viewW,
                                        viewH: viewH,
                                        boxLeft: _boxLeft,
                                        boxTop: _boxTop,
                                        boxWidth: _boxWidth,
                                        boxHeight: _boxHeight,
                                        onMover: _moverCuadro,
                                        onRedimensionarEsquina: _redimensionarEsquina,
                                        onRedimensionarBorde: _redimensionarBorde,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),

            // Botón inferior para exportar y compartir
            if (_imagenFondo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: MitiBoton(
                  texto: 'Compartir imagen en redes',
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

/// Renderiza la grilla de números:
/// - Exactamente 10 números por fila.
/// - Espacio libre (vacío) para números vendidos o reservados.
/// - Tipografía Big Shoulders más liviana (FontWeight.w600/w700).
/// - Márgenes reducidos para aprovechar al máximo el área.
/// - Sin desbordes con FittedBox.
class _AreaNumerosDisponibles extends StatelessWidget {
  const _AreaNumerosDisponibles({
    required this.rangoDesde,
    required this.rangoHasta,
    required this.estadoPorNumero,
    required this.ancho,
    required this.alto,
    required this.estilo,
  });

  final int rangoDesde;
  final int rangoHasta;
  final Map<int, String> estadoPorNumero;
  final double ancho;
  final double alto;
  final _EstiloContraste estilo;

  @override
  Widget build(BuildContext context) {
    final totalEnRango = (rangoHasta - rangoDesde + 1).clamp(1, 1000);
    const int cols = 10;
    final int rows = (totalEnRango / cols).ceil();

    // Márgenes mínimos para aprovechar el área
    const double paddingH = 3.0;
    const double paddingV = 3.0;

    final double anchoUtil = math.max(ancho - (paddingH * 2), 10.0);
    final double altoUtil = math.max(alto - (paddingV * 2), 10.0);

    final double cellW = anchoUtil / cols;
    final double cellH = altoUtil / math.max(rows, 1);

    // Tamaño de fuente calculado para que quepan hasta 3 dígitos sin apretar
    final maxDigitos = rangoHasta.toString().length;
    final double fontSize = (math.min(
      cellW * (maxDigitos >= 3 ? 0.48 : 0.68),
      cellH * 0.85,
    )).clamp(6.0, 30.0);

    final (Color? bgColor, Color textColor, List<Shadow>? shadows, Border? border) = switch (estilo) {
      _EstiloContraste.papelClaro => (
          const Color(0xFFFBF9F4).withValues(alpha: 0.92),
          const Color(0xFF1E2A3A),
          null,
          Border.all(color: const Color(0xFF1E2A3A).withValues(alpha: 0.4), width: 1.0),
        ),
      _EstiloContraste.papelOscuro => (
          const Color(0xFF1E2A3A).withValues(alpha: 0.88),
          Colors.white,
          null,
          Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.0),
        ),
      _EstiloContraste.textoNegro => (
          null,
          const Color(0xFF1E2A3A),
          [const Shadow(color: Colors.white, blurRadius: 2.5)],
          null,
        ),
      _EstiloContraste.textoBlanco => (
          null,
          Colors.white,
          [const Shadow(color: Colors.black, blurRadius: 2.5)],
          null,
        ),
    };

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: border,
      ),
      padding: const EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(rows, (r) {
          return Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(cols, (c) {
                final numero = rangoDesde + (r * cols) + c;
                if (numero > rangoHasta) {
                  return SizedBox(width: cellW);
                }

                final estaLibre = estadoPorNumero[numero] == 'libre';

                // Si no está libre (vendido o reservado), queda el espacio libre
                if (!estaLibre) {
                  return SizedBox(width: cellW);
                }

                final textoNum = numero < 10 ? '0$numero' : '$numero';

                return SizedBox(
                  width: cellW,
                  height: cellH,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        textoNum,
                        style: TextStyle(
                          fontFamily: 'BigShoulders',
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                          height: 1.0,
                          shadows: shadows,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }
}

/// Overlay interactivo que dibuja el marco de edición tipo recorte
/// con manijas táctiles en esquinas y bordes, permitiendo mover y redimensionar.
class _CuadroInteractivosEditor extends StatelessWidget {
  const _CuadroInteractivosEditor({
    required this.viewW,
    required this.viewH,
    required this.boxLeft,
    required this.boxTop,
    required this.boxWidth,
    required this.boxHeight,
    required this.onMover,
    required this.onRedimensionarEsquina,
    required this.onRedimensionarBorde,
  });

  final double viewW;
  final double viewH;
  final double boxLeft;
  final double boxTop;
  final double boxWidth;
  final double boxHeight;
  final void Function(double dxRel, double dyRel) onMover;
  final void Function({
    required bool arriba,
    required bool izquierda,
    required double dxRel,
    required double dyRel,
  }) onRedimensionarEsquina;
  final void Function({
    bool? horizontal,
    required bool inicio,
    required double dxRel,
    required double dyRel,
  }) onRedimensionarBorde;

  @override
  Widget build(BuildContext context) {
    final leftPx = boxLeft * viewW;
    final topPx = boxTop * viewH;
    final widthPx = boxWidth * viewW;
    final heightPx = boxHeight * viewH;

    const handleSize = 28.0;
    const halfHandle = handleSize / 2;

    return Stack(
      children: [
        // Marco delimitador con borde y botón central para mover
        Positioned(
          left: leftPx,
          top: topPx,
          width: widthPx,
          height: heightPx,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanUpdate: (details) {
              onMover(details.delta.dx / viewW, details.delta.dy / viewH);
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFB8860B), width: 2.0),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.open_with_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),

        // Manijas en las 4 esquinas
        // 1. Superior Izquierda (TL)
        Positioned(
          left: leftPx - halfHandle,
          top: topPx - halfHandle,
          width: handleSize,
          height: handleSize,
          child: _ManijaTaktil(
            onPanUpdate: (d) => onRedimensionarEsquina(
              arriba: true,
              izquierda: true,
              dxRel: d.delta.dx / viewW,
              dyRel: d.delta.dy / viewH,
            ),
          ),
        ),

        // 2. Superior Derecha (TR)
        Positioned(
          left: leftPx + widthPx - halfHandle,
          top: topPx - halfHandle,
          width: handleSize,
          height: handleSize,
          child: _ManijaTaktil(
            onPanUpdate: (d) => onRedimensionarEsquina(
              arriba: true,
              izquierda: false,
              dxRel: d.delta.dx / viewW,
              dyRel: d.delta.dy / viewH,
            ),
          ),
        ),

        // 3. Inferior Izquierda (BL)
        Positioned(
          left: leftPx - halfHandle,
          top: topPx + heightPx - halfHandle,
          width: handleSize,
          height: handleSize,
          child: _ManijaTaktil(
            onPanUpdate: (d) => onRedimensionarEsquina(
              arriba: false,
              izquierda: true,
              dxRel: d.delta.dx / viewW,
              dyRel: d.delta.dy / viewH,
            ),
          ),
        ),

        // 4. Inferior Derecha (BR)
        Positioned(
          left: leftPx + widthPx - halfHandle,
          top: topPx + heightPx - halfHandle,
          width: handleSize,
          height: handleSize,
          child: _ManijaTaktil(
            onPanUpdate: (d) => onRedimensionarEsquina(
              arriba: false,
              izquierda: false,
              dxRel: d.delta.dx / viewW,
              dyRel: d.delta.dy / viewH,
            ),
          ),
        ),

        // Manijas en los bordes laterales y verticales
        // Borde Superior
        Positioned(
          left: leftPx + widthPx / 2 - 20,
          top: topPx - halfHandle,
          width: 40,
          height: handleSize,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => onRedimensionarBorde(
              horizontal: false,
              inicio: true,
              dxRel: 0,
              dyRel: d.delta.dy / viewH,
            ),
            child: const Center(
              child: _BarraControl(horizontal: true),
            ),
          ),
        ),

        // Borde Inferior
        Positioned(
          left: leftPx + widthPx / 2 - 20,
          top: topPx + heightPx - halfHandle,
          width: 40,
          height: handleSize,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => onRedimensionarBorde(
              horizontal: false,
              inicio: false,
              dxRel: 0,
              dyRel: d.delta.dy / viewH,
            ),
            child: const Center(
              child: _BarraControl(horizontal: true),
            ),
          ),
        ),

        // Borde Izquierdo
        Positioned(
          left: leftPx - halfHandle,
          top: topPx + heightPx / 2 - 20,
          width: handleSize,
          height: 40,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => onRedimensionarBorde(
              horizontal: true,
              inicio: true,
              dxRel: d.delta.dx / viewW,
              dyRel: 0,
            ),
            child: const Center(
              child: _BarraControl(horizontal: false),
            ),
          ),
        ),

        // Borde Derecho
        Positioned(
          left: leftPx + widthPx - halfHandle,
          top: topPx + heightPx / 2 - 20,
          width: handleSize,
          height: 40,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => onRedimensionarBorde(
              horizontal: true,
              inicio: false,
              dxRel: d.delta.dx / viewW,
              dyRel: 0,
            ),
            child: const Center(
              child: _BarraControl(horizontal: false),
            ),
          ),
        ),
      ],
    );
  }
}

class _ManijaTaktil extends StatelessWidget {
  const _ManijaTaktil({required this.onPanUpdate});

  final void Function(DragUpdateDetails details) onPanUpdate;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: onPanUpdate,
      child: Center(
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFFB8860B),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarraControl extends StatelessWidget {
  const _BarraControl({required this.horizontal});

  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: horizontal ? 24 : 6,
      height: horizontal ? 6 : 24,
      decoration: BoxDecoration(
        color: const Color(0xFFB8860B),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.white, width: 1),
      ),
    );
  }
}
