import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../estado/sesion.dart';
import '../nucleo/componentes.dart';
import '../nucleo/tema.dart';

/// Pantalla de Sorteo y Ganador (§3.3 y §7.8 de DEFINICION.md).
/// Permite al administrador cargar el número sorteado y a todos los participantes
/// consultar el ganador y compartir la tarjeta por WhatsApp.
class PantallaGanador extends ConsumerStatefulWidget {
  const PantallaGanador({
    super.key,
    required this.campanaId,
    required this.campanaNombre,
    this.esAdmin = false,
    this.premioDefault,
    this.sorteoInicial,
  });

  final String campanaId;
  final String campanaNombre;
  final bool esAdmin;
  final String? premioDefault;
  final Map<String, dynamic>? sorteoInicial;

  @override
  ConsumerState<PantallaGanador> createState() => _PantallaGanadorState();
}

class _PantallaGanadorState extends ConsumerState<PantallaGanador> {
  final _tarjetaKey = GlobalKey();
  final _numeroControlador = TextEditingController();
  final _premioControlador = TextEditingController();

  Map<String, dynamic>? _sorteo;
  bool _cargando = true;
  bool _guardando = false;
  bool _compartiendo = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _premioControlador.text = widget.premioDefault ?? 'Primer Premio';
    if (widget.sorteoInicial != null) {
      _sorteo = widget.sorteoInicial;
      _cargando = false;
    } else {
      _cargarSorteo();
    }
  }

  @override
  void dispose() {
    _numeroControlador.dispose();
    _premioControlador.dispose();
    super.dispose();
  }

  Future<void> _cargarSorteo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final res = await ref.read(apiProvider).sorteo(widget.campanaId);
      if (mounted) {
        setState(() {
          _sorteo = res;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _registrar() async {
    final numStr = _numeroControlador.text.trim();
    if (numStr.isEmpty) {
      setState(() => _error = 'Ingresá el número sorteado');
      return;
    }
    final numVal = int.tryParse(numStr);
    if (numVal == null) {
      setState(() => _error = 'Número inválido');
      return;
    }

    final premio = _premioControlador.text.trim();
    if (premio.isEmpty) {
      setState(() => _error = 'Ingresá la descripción del premio');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final res = await ref.read(apiProvider).registrarSorteo(
            widget.campanaId,
            numeroSorteado: numVal,
            premio: premio,
          );
      if (mounted) {
        setState(() {
          _sorteo = res;
          _guardando = false;
        });
        mostrarAviso(context, '¡Sorteo registrado con éxito!');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<File?> _generarImagen() async {
    try {
      final boundary = _tarjetaKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final tempDir = await getTemporaryDirectory();
      final archivo = File('${tempDir.path}/ganador_${widget.campanaId}.png');
      await archivo.writeAsBytes(byteData.buffer.asUint8List());
      return archivo;
    } catch (_) {
      return null;
    }
  }

  Future<void> _compartir() async {
    if (_compartiendo || _sorteo == null) return;
    setState(() => _compartiendo = true);

    try {
      final archivo = await _generarImagen();
      final numGanador = _sorteo!['numero_ganador'] ?? _sorteo!['numero_sorteado'];
      final ganadorNom = _sorteo!['ganador_nombre'] ?? 'Sin asignar';
      final premio = _sorteo!['premio'] ?? 'Premio';

      final texto = '🎉 ¡RESULTADO DEL SORTEO! 🎉\n\n'
          '🏆 Campaña: *${widget.campanaNombre}*\n'
          '🔢 Número Ganador: *#$numGanador*\n'
          '🎁 Premio: *$premio*\n'
          '👤 Ganador/a: *$ganadorNom*\n\n'
          '¡Felicitaciones y gracias a todos por colaborar!';

      if (archivo != null) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(archivo.path, mimeType: 'image/png')],
            text: texto,
          ),
        );
      } else {
        await SharePlus.instance.share(ShareParams(text: texto));
      }
    } catch (_) {
      if (mounted) mostrarAviso(context, 'No se pudo abrir el menú de compartir', error: true);
    } finally {
      if (mounted) setState(() => _compartiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'SORTEO Y GANADOR',
          style: t.seccion.copyWith(color: c.tinta),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.tinta),
          onPressed: () => Navigator.of(context).pop(_sorteo != null),
        ),
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: c.sello))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              child: _sorteo != null ? _construirResultado(c, t) : _construirFormularioRegistro(c, t),
            ),
    );
  }

  Widget _construirFormularioRegistro(dynamic c, dynamic t) {
    if (!widget.esAdmin) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.hourglass_empty, size: 60, color: c.tintaSuave),
              const SizedBox(height: 16),
              Text(
                'El sorteo aún no fue registrado',
                style: t.titular.copyWith(color: c.tinta, fontSize: 20),
              ),
              const SizedBox(height: 8),
              Text(
                'El administrador de la campaña cargará el resultado oficial de la lotería una vez realizado.',
                textAlign: TextAlign.center,
                style: t.cuerpo.copyWith(color: c.tintaSuave),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.sello.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.sello.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.emoji_events_outlined, color: c.selloTexto, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cargar el número favorecido de la lotería para determinar automáticamente el ganador.',
                  style: t.pie.copyWith(color: c.tinta, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _numeroControlador,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: t.importe.copyWith(color: c.tinta, fontSize: 26),
          decoration: InputDecoration(
            labelText: 'Número sorteado (lotería / quiniela)',
            labelStyle: t.etiqueta.copyWith(color: c.tintaSuave),
            prefixIcon: Icon(Icons.confirmation_number_outlined, color: c.tinta),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: c.tinta, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _premioControlador,
          textCapitalization: TextCapitalization.sentences,
          style: t.cuerpo.copyWith(color: c.tinta),
          decoration: InputDecoration(
            labelText: 'Descripción del premio',
            labelStyle: t.etiqueta.copyWith(color: c.tintaSuave),
            prefixIcon: Icon(Icons.card_giftcard_outlined, color: c.tinta),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: c.tinta, width: 2),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.sello,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _error!,
              style: t.cuerpo.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 24),
        MitiBoton(
          texto: 'Buscar ganador y registrar',
          icono: Icons.check,
          cargando: _guardando,
          onTap: _registrar,
        ),
      ],
    );
  }

  Widget _construirResultado(dynamic c, dynamic t) {
    final s = _sorteo!;
    final numSorteado = s['numero_sorteado'];
    final numGanador = s['numero_ganador'];
    final premio = s['premio'] ?? 'Premio';
    final estadoRes = s['estado_resultado'] ?? 'ganador_encontrado';
    final ganadorNom = s['ganador_nombre'];
    final ganadorTel = s['ganador_telefono'];
    final vendedorNom = s['vendedor_nombre'];
    final codigoCorto = s['codigo_corto'];

    final hayGanador = numGanador != null && ganadorNom != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tarjeta compartible estilo talón
        RepaintBoundary(
          key: _tarjetaKey,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFBF9F4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E2A3A), width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Encabezado
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E2A3A),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          widget.campanaNombre.toUpperCase(),
                          style: const TextStyle(
                            fontFamily: 'BigShoulders',
                            color: Color(0xFFFBF9F4),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFFBF9F4), width: 1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'SORTEO',
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 10,
                            color: Color(0xFFFBF9F4),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Cuerpo
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        hayGanador ? '¡TENEMOS GANADOR!' : 'SORTEO REALIZADO',
                        style: const TextStyle(
                          fontFamily: 'BigShoulders',
                          color: Color(0xFFC0392B),
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        premio,
                        style: const TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 16,
                          color: Color(0xFF1E2A3A),
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),

                      // Bloque número
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1ECE0),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFD4CCBA)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              hayGanador ? 'NÚMERO GANADOR' : 'NÚMERO SORTEADO',
                              style: const TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 11,
                                color: Color(0xFF5F5A4E),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '#${numGanador ?? numSorteado}',
                              style: const TextStyle(
                                fontFamily: 'BigShoulders',
                                color: Color(0xFF1E2A3A),
                                fontSize: 52,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (estadoRes == 'siguiente_vendido' && numSorteado != numGanador)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '(Sorteado #$numSorteado no vendido, adjudicado por regla)',
                                  style: const TextStyle(
                                    fontFamily: 'Figtree',
                                    fontSize: 10,
                                    color: Color(0xFF5F5A4E),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      if (hayGanador) ...[
                        Text(
                          ganadorNom,
                          style: const TextStyle(
                            fontFamily: 'Figtree',
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E2A3A),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (ganadorTel != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            ganadorTel,
                            style: const TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 13,
                              color: Color(0xFF5F5A4E),
                            ),
                          ),
                        ],
                        if (vendedorNom != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Vendido por: $vendedorNom',
                            style: const TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 12,
                              color: Color(0xFF1E2A3A),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (codigoCorto != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Ticket: #$codigoCorto',
                            style: const TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 11,
                              color: Color(0xFF5F5A4E),
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ] else ...[
                        const Text(
                          'Premio desierto / No vendido',
                          style: TextStyle(
                            fontFamily: 'Figtree',
                            color: Color(0xFFC0392B),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Pie troquelado
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1ECE0),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_outlined, size: 16, color: Color(0xFF5F5A4E)),
                      SizedBox(width: 6),
                      Text(
                        'RESULTADO OFICIAL DE LA CAMPAÑA',
                        style: TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 11,
                          color: Color(0xFF5F5A4E),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        MitiBoton(
          texto: 'Enviar resultado por WhatsApp',
          icono: Icons.send_rounded,
          cargando: _compartiendo,
          onTap: _compartir,
        ),

        const SizedBox(height: 10),

        MitiBoton(
          texto: 'Volver a la campaña',
          secundario: true,
          onTap: () => Navigator.of(context).pop(_sorteo != null),
        ),
      ],
    );
  }
}
