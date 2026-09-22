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
import '../nucleo/publicidad.dart';
import 'hoja_premios.dart';

/// Pantalla de Sorteo y Ganadores (§3.3 y §7.8 de DEFINICION.md).
/// Permite al administrador cargar en orden los números sorteados para cada premio
/// y a todos los participantes consultar los ganadores y compartir la tarjeta por WhatsApp.
class PantallaGanador extends ConsumerStatefulWidget {
  const PantallaGanador({
    super.key,
    required this.campanaId,
    required this.campanaNombre,
    this.esAdmin = false,
    this.premios,
    this.sorteosIniciales,
    this.premioDefault,
    this.sorteoInicial,
  });

  final String campanaId;
  final String campanaNombre;
  final bool esAdmin;
  final List<String>? premios;
  final List<dynamic>? sorteosIniciales;
  final String? premioDefault;
  final Map<String, dynamic>? sorteoInicial;

  @override
  ConsumerState<PantallaGanador> createState() => _PantallaGanadorState();
}

class _PantallaGanadorState extends ConsumerState<PantallaGanador> {
  final _tarjetaKey = GlobalKey();
  late List<String> _premios;
  late List<TextEditingController> _numerosControladores;

  List<dynamic>? _sorteos;
  bool _cargando = true;
  bool _guardando = false;
  bool _compartiendo = false;
  String? _error;
  String _reglaNoVendido = 'desierto';

  @override
  void initState() {
    super.initState();
    if (widget.premios != null && widget.premios!.isNotEmpty) {
      _premios = List<String>.from(widget.premios!);
    } else if (widget.premioDefault != null && widget.premioDefault!.isNotEmpty) {
      _premios = [widget.premioDefault!];
    } else {
      _premios = ['Primer Premio'];
    }
    _numerosControladores = _premios.map((_) => TextEditingController()).toList();

    if (widget.sorteosIniciales != null && widget.sorteosIniciales!.isNotEmpty) {
      _sorteos = widget.sorteosIniciales;
      _cargando = false;
    } else if (widget.sorteoInicial != null) {
      _sorteos = [widget.sorteoInicial!];
      _cargando = false;
    } else {
      _cargarSorteo();
    }
  }

  @override
  void dispose() {
    for (final c in _numerosControladores) {
      c.dispose();
    }
    super.dispose();
  }

  void _actualizarPremios(List<String> nuevos) {
    setState(() {
      _premios = nuevos;
      for (final c in _numerosControladores) {
        c.dispose();
      }
      _numerosControladores = _premios.map((_) => TextEditingController()).toList();
    });
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
          _sorteos = res.isNotEmpty ? res : null;
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
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < _premios.length; i++) {
      final numStr = _numerosControladores[i].text.trim();
      if (numStr.isEmpty) {
        setState(() => _error = 'Ingresá el número sorteado para el ${i + 1}° premio (${_premios[i]})');
        return;
      }
      final numVal = int.tryParse(numStr);
      if (numVal == null || numVal < 0) {
        setState(() => _error = 'Número inválido para el ${i + 1}° premio');
        return;
      }
      items.add({
        'orden': i + 1,
        'numero_sorteado': numVal,
        'premio': _premios[i],
      });
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final res = await ref.read(apiProvider).registrarSorteo(
            widget.campanaId,
            items: items,
            reglaNoVendido: _reglaNoVendido,
          );
      if (mounted) {
        setState(() {
          _sorteos = res;
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
      final archivo = File('${tempDir.path}/ganadores_${widget.campanaId}.png');
      await archivo.writeAsBytes(byteData.buffer.asUint8List());
      return archivo;
    } catch (_) {
      return null;
    }
  }

  Future<void> _compartir() async {
    if (_compartiendo || _sorteos == null || _sorteos!.isEmpty) return;
    setState(() => _compartiendo = true);

    try {
      final archivo = await _generarImagen();

      var texto = '🎉 ¡RESULTADOS DEL SORTEO! 🎉\n\n'
          '🏆 Campaña: *${widget.campanaNombre}*\n\n';

      for (final s in _sorteos!) {
        final orden = s['orden'] ?? 1;
        final premio = s['premio'] ?? 'Premio';
        final numGanador = s['numero_ganador'];
        final numSorteado = s['numero_sorteado'];
        final ganadorNom = s['ganador_nombre'];
        final vendedorNom = s['vendedor_nombre'];
        final estado = s['estado_resultado'];

        texto += '🎁 *$orden° Premio:* $premio\n';
        if (numGanador != null && ganadorNom != null) {
          texto += '🔢 Número Ganador: *#$numGanador*\n'
              '👤 Ganador/a: *$ganadorNom*\n';
          if (vendedorNom != null) {
            texto += '🤝 Vendido por: $vendedorNom\n';
          }
          if (estado == 'siguiente_vendido' && numSorteado != numGanador) {
            texto += '(Sorteado #$numSorteado no vendido, adjudicado por regla)\n';
          }
        } else {
          texto += '🔢 Número sorteado: #$numSorteado\n'
              '❌ Vacante / Desierto\n';
        }
        texto += '\n';
      }

      texto += '¡Felicitaciones a los ganadores y gracias a todos por colaborar!';

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
      if (ref.read(publicidadEnCampanaProvider(widget.campanaId))) {
        await Publicidad.intersticialAlGenerarImagen();
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
    final tieneResultado = _sorteos != null && _sorteos!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          tieneResultado ? 'RESULTADOS DEL SORTEO' : 'SORTEO Y GANADORES',
          style: t.seccion.copyWith(color: c.tinta),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.tinta),
          onPressed: () => Navigator.of(context).pop(tieneResultado),
        ),
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: c.sello))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              child: tieneResultado ? _construirResultado(c, t) : _construirFormularioRegistro(c, t),
            ),
    );
  }

  Widget _construirFormularioRegistro(MitiColores c, MitiTextos t) {
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
                style: t.titular.copyWith(color: c.tinta, fontSize: 20.0),
              ),
              const SizedBox(height: 8),
              Text(
                'El administrador de la campaña cargará los números oficiales de la lotería una vez realizado el sorteo.',
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
                  'Cargá en orden los números favorecidos de la lotería para cada premio configurado.',
                  style: t.pie.copyWith(color: c.tinta, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PREMIOS A SORTEAR (${_premios.length})',
              style: t.sobrelinea.copyWith(color: c.tintaSuave),
            ),
            TextButton.icon(
              icon: Icon(Icons.edit_outlined, size: 16, color: c.tinta),
              label: Text(
                'Editar premios',
                style: t.etiqueta.copyWith(color: c.tinta, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                final nuevos = await mostrarHojaPremios(
                  context,
                  campanaId: widget.campanaId,
                  premiosActuales: _premios,
                );
                if (nuevos != null && mounted) {
                  _actualizarPremios(nuevos);
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        ...List.generate(_premios.length, (index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.papelHundido,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.troquel),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: c.tinta,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${index + 1}° PREMIO',
                        style: const TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _premios[index],
                        style: t.cuerpo.copyWith(
                          fontWeight: FontWeight.bold,
                          color: c.tinta,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _numerosControladores[index],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: t.importe.copyWith(color: c.tinta, fontSize: 22.0),
                  decoration: InputDecoration(
                    labelText: 'Número sorteado para este premio',
                    labelStyle: t.etiqueta.copyWith(color: c.tintaSuave),
                    prefixIcon: Icon(Icons.confirmation_number_outlined, color: c.tinta),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: c.tinta, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 8),
        Text('SI UN NÚMERO NO FUE VENDIDO', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: c.papelHundido,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.troquel),
          ),
          child: Column(
            children: [
              InkWell(
                onTap: () => setState(() => _reglaNoVendido = 'desierto'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        _reglaNoVendido == 'desierto' ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: _reglaNoVendido == 'desierto' ? c.sello : c.tintaSuave,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Declarar premio desierto', style: t.cuerpo.copyWith(color: c.tinta, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('El premio no se adjudica si nadie compró el número.', style: t.pie.copyWith(color: c.tintaSuave)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              InkWell(
                onTap: () => setState(() => _reglaNoVendido = 'siguiente_vendido'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        _reglaNoVendido == 'siguiente_vendido' ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: _reglaNoVendido == 'siguiente_vendido' ? c.sello : c.tintaSuave,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Siguiente número vendido', style: t.cuerpo.copyWith(color: c.tinta, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('Gana el siguiente vendido que no haya ganado ya otro premio.', style: t.pie.copyWith(color: c.tintaSuave)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
          texto: 'Determinar ganadores y registrar',
          icono: Icons.check,
          cargando: _guardando,
          onTap: _registrar,
        ),
      ],
    );
  }

  Widget _construirResultado(MitiColores c, MitiTextos t) {
    final sorteos = _sorteos!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tarjeta compartible estilo talón multi-premio
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
                          'SORTEO OFICIAL',
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

                // Título principal
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '¡RESULTADOS DEL SORTEO!',
                    style: const TextStyle(
                      fontFamily: 'BigShoulders',
                      color: Color(0xFFC0392B),
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Lista de premios
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: List.generate(sorteos.length, (idx) {
                      final s = sorteos[idx] as Map<String, dynamic>;
                      final orden = s['orden'] ?? (idx + 1);
                      final numSorteado = s['numero_sorteado'];
                      final numGanador = s['numero_ganador'];
                      final premio = s['premio'] ?? 'Premio';
                      final estadoRes = s['estado_resultado'] ?? 'ganador_encontrado';
                      final ganadorNom = s['ganador_nombre'];
                      final ganadorTel = s['ganador_telefono'];
                      final vendedorNom = s['vendedor_nombre'];
                      final codigoCorto = s['codigo_corto'];
                      final hayGanador = numGanador != null && ganadorNom != null;

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1ECE0),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFD4CCBA)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E2A3A),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '$orden° PREMIO',
                                    style: const TextStyle(
                                      fontFamily: 'Figtree',
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                if (hayGanador)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFC0392B).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: const Color(0xFFC0392B)),
                                    ),
                                    child: const Text(
                                      '¡GANADOR!',
                                      style: TextStyle(
                                        fontFamily: 'Figtree',
                                        fontSize: 10,
                                        color: Color(0xFFC0392B),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              premio,
                              style: const TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 16,
                                color: Color(0xFF1E2A3A),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E2A3A),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '#${numGanador ?? numSorteado}',
                                    style: const TextStyle(
                                      fontFamily: 'BigShoulders',
                                      color: Color(0xFFFBF9F4),
                                      fontSize: 32,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: hayGanador
                                      ? Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              ganadorNom,
                                              style: const TextStyle(
                                                fontFamily: 'Figtree',
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF1E2A3A),
                                              ),
                                            ),
                                            if (ganadorTel != null)
                                              Text(
                                                ganadorTel,
                                                style: const TextStyle(
                                                  fontFamily: 'Figtree',
                                                  fontSize: 12,
                                                  color: Color(0xFF5F5A4E),
                                                ),
                                              ),
                                            if (vendedorNom != null)
                                              Text(
                                                'Vendido por: $vendedorNom',
                                                style: const TextStyle(
                                                  fontFamily: 'Figtree',
                                                  fontSize: 11,
                                                  color: Color(0xFF1E2A3A),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            if (codigoCorto != null)
                                              Text(
                                                'Ticket: #$codigoCorto',
                                                style: const TextStyle(
                                                  fontFamily: 'Figtree',
                                                  fontSize: 10,
                                                  color: Color(0xFF5F5A4E),
                                                ),
                                              ),
                                          ],
                                        )
                                      : const Text(
                                          'Premio desierto / No vendido',
                                          style: TextStyle(
                                            fontFamily: 'Figtree',
                                            color: Color(0xFFC0392B),
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                            if (estadoRes == 'siguiente_vendido' && numSorteado != numGanador)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '(Sorteado #$numSorteado no vendido, adjudicado por regla al vendido disponible)',
                                  style: const TextStyle(
                                    fontFamily: 'Figtree',
                                    fontSize: 10,
                                    color: Color(0xFF5F5A4E),
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),

                const SizedBox(height: 12),

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
          texto: 'Enviar resultados por WhatsApp',
          icono: Icons.send_rounded,
          cargando: _compartiendo,
          onTap: _compartir,
        ),

        const SizedBox(height: 10),

        MitiBoton(
          texto: 'Volver a la campaña',
          secundario: true,
          onTap: () => Navigator.of(context).pop(_sorteos != null),
        ),
      ],
    );
  }
}
