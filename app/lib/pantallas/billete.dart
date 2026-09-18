import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';

/// Pantalla del billete / talón para enviar al comprador.
class PantallaBillete extends StatefulWidget {
  const PantallaBillete({
    super.key,
    required this.campanaNombre,
    required this.numeros,
    required this.importe,
    required this.compradorNombre,
    required this.compradorTelefono,
    required this.vendedorNombre,
    required this.codigoCorto,
    required this.estaPagado,
    this.itemsProductos,
    this.entrega,
    this.fechaSorteo,
    this.autoCompartir = false,
  });

  final String campanaNombre;
  final List<int> numeros;
  final List<Map<String, dynamic>>? itemsProductos;
  final String? entrega;
  final int importe;
  final String compradorNombre;
  final String? compradorTelefono;
  final String vendedorNombre;
  final String codigoCorto;
  final bool estaPagado;
  final String? fechaSorteo;
  final bool autoCompartir;

  @override
  State<PantallaBillete> createState() => _PantallaBilleteState();
}

class _PantallaBilleteState extends State<PantallaBillete> {
  final GlobalKey _ticketKey = GlobalKey();
  bool _compartiendo = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoCompartir) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Le damos un momento breve para que renderice el widget antes de capturarlo
        Future.delayed(const Duration(milliseconds: 350), _enviarWhatsApp);
      });
    }
  }

  String _armarTextoCompartir() {
    final estado = widget.estaPagado ? 'PAGADO' : 'PENDIENTE DE PAGO';

    if (widget.itemsProductos != null && widget.itemsProductos!.isNotEmpty) {
      final lineas = widget.itemsProductos!.map((it) {
        final cant = it['cantidad'];
        final nom = it['nombre'];
        final sub = it['subtotal'] ?? ((it['precio_unitario'] as int? ?? 0) * (cant as int));
        return '• $cant x $nom: ${plata(sub as int)}';
      }).join('\n');

      final estadoEntrega = widget.entrega == 'entregado' ? 'ENTREGADO' : 'PENDIENTE';

      return '¡Hola ${widget.compradorNombre}! Acá tenés tu comprobante de compra:\n\n'
          '🛍️ *${widget.campanaNombre}*\n'
          '📦 Entrega: *$estadoEntrega*\n\n'
          'Detalle:\n$lineas\n\n'
          '💰 Total: *${plata(widget.importe)}* ($estado)\n'
          '🔑 Código: *${widget.codigoCorto}*\n'
          '👤 Atendido por: ${widget.vendedorNombre}\n'
          '\n¡Muchas gracias por tu compra!';
    }

    final numsStr = widget.numeros.map((n) => n.toString().padLeft(2, '0')).join(', ');
    return '¡Hola ${widget.compradorNombre}! Acá tenés tu comprobante de la campaña:\n\n'
        '🎟️ *${widget.campanaNombre}*\n'
        '🔢 Números: *$numsStr*\n'
        '💰 Importe: *${plata(widget.importe)}* ($estado)\n'
        '🔑 Código: *${widget.codigoCorto}*\n'
        '👤 Vendedor: ${widget.vendedorNombre}\n'
        '${widget.fechaSorteo != null ? '📅 Sorteo: ${widget.fechaSorteo}\n' : ''}'
        '\n¡Muchas gracias por colaborar!';
  }

  Future<File?> _generarImagen() async {
    try {
      final boundary = _ticketKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final tempDir = await getTemporaryDirectory();
      final archivo = File('${tempDir.path}/billete_${widget.codigoCorto}.png');
      await archivo.writeAsBytes(byteData.buffer.asUint8List());
      return archivo;
    } catch (_) {
      return null;
    }
  }

  Future<void> _enviarWhatsApp() async {
    if (_compartiendo) return;
    setState(() => _compartiendo = true);

    try {
      final archivo = await _generarImagen();
      final texto = _armarTextoCompartir();

      if (archivo != null) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(archivo.path, mimeType: 'image/png')],
            text: texto,
          ),
        );
      } else {
        // Fallback: compartir solo texto
        await SharePlus.instance.share(ShareParams(text: texto));
      }
    } catch (e) {
      if (mounted) mostrarAviso(context, 'No se pudo abrir el menú de compartir', error: true);
    } finally {
      if (mounted) setState(() => _compartiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final numsStr = widget.numeros.map((n) => n.toString().padLeft(2, '0')).join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: Text('BILLETE DE COMPRA', style: t.seccion.copyWith(color: c.tinta)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.tinta),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            // Billete estilo talonario capturable
            RepaintBoundary(
              key: _ticketKey,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFBF9F4), // Paleta clara fija para la imagen generada
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E2A3A), width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Encabezado del talón
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
                            child: Text(
                              '#${widget.codigoCorto}',
                              style: const TextStyle(
                                fontFamily: 'Figtree',
                                color: Color(0xFFFBF9F4),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Cuerpo del talón
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'COMPRADOR',
                                      style: TextStyle(
                                        fontFamily: 'Figtree',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF5F5A4E),
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.compradorNombre,
                                      style: const TextStyle(
                                        fontFamily: 'BigShoulders',
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1E2A3A),
                                      ),
                                    ),
                                    if (widget.compradorTelefono != null && widget.compradorTelefono!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        widget.compradorTelefono!,
                                        style: const TextStyle(
                                          fontFamily: 'Figtree',
                                          fontSize: 13,
                                          color: Color(0xFF5F5A4E),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // Sello de PAGADO o A PAGAR
                              Transform.rotate(
                                angle: -0.1,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: widget.estaPagado ? const Color(0xFF2F7A57) : const Color(0xFFB7372A),
                                      width: 2.5,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    widget.estaPagado ? 'PAGADO' : 'A PAGAR',
                                    style: TextStyle(
                                      fontFamily: 'BigShoulders',
                                      color: widget.estaPagado ? const Color(0xFF2F7A57) : const Color(0xFFB7372A),
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 18),
                          const MitiTroquel(color: Color(0xFFCFC6B2), grosor: 1.5),
                          const SizedBox(height: 18),

                          if (widget.itemsProductos != null && widget.itemsProductos!.isNotEmpty) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'PRODUCTOS',
                                  style: TextStyle(
                                    fontFamily: 'Figtree',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF5F5A4E),
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: widget.entrega == 'entregado'
                                        ? const Color(0xFF2F7A57).withValues(alpha: 0.15)
                                        : const Color(0xFFE5A93C).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    widget.entrega == 'entregado' ? 'ENTREGADO' : 'PEDIDO',
                                    style: TextStyle(
                                      fontFamily: 'Figtree',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: widget.entrega == 'entregado'
                                          ? const Color(0xFF2F7A57)
                                          : const Color(0xFF8A5D0A),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final it in widget.itemsProductos!) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E2A3A).withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${it['cantidad']}',
                                        style: const TextStyle(
                                          fontFamily: 'BigShoulders',
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1E2A3A),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        it['nombre'] as String,
                                        style: const TextStyle(
                                          fontFamily: 'Figtree',
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1E2A3A),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      plata(it['subtotal'] ?? ((it['precio_unitario'] as int? ?? 0) * (it['cantidad'] as int))),
                                      style: const TextStyle(
                                        fontFamily: 'BigShoulders',
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1E2A3A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ] else ...[
                            // Números asignados
                            Text(
                              widget.numeros.length == 1 ? 'NÚMERO ASIGNADO' : 'NÚMEROS ASIGNADOS',
                              style: const TextStyle(
                                fontFamily: 'Figtree',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF5F5A4E),
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                numsStr,
                                style: TextStyle(
                                  fontFamily: 'BigShoulders',
                                  color: const Color(0xFF1E2A3A),
                                  fontSize: widget.numeros.length > 3 ? 32 : 44,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'TOTAL',
                                    style: TextStyle(
                                      fontFamily: 'Figtree',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF5F5A4E),
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    plata(widget.importe),
                                    style: const TextStyle(
                                      fontFamily: 'BigShoulders',
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1E2A3A),
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text(
                                    'VENDEDOR',
                                    style: TextStyle(
                                      fontFamily: 'Figtree',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF5F5A4E),
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.vendedorNombre,
                                    style: const TextStyle(
                                      fontFamily: 'Figtree',
                                      color: Color(0xFF1E2A3A),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
                            'COMPROBANTE VÁLIDO DE LA CAMPAÑA',
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

            // Botón principal: Enviar imagen por WhatsApp
            MitiBoton(
              texto: (widget.itemsProductos?.isNotEmpty ?? false)
                  ? 'Enviar comprobante por WhatsApp'
                  : 'Enviar billete por WhatsApp',
              icono: Icons.send_rounded,
              cargando: _compartiendo,
              onTap: _enviarWhatsApp,
            ),

            const SizedBox(height: 10),

            // Botón secundario: Copiar solo texto
            MitiBoton(
              texto: 'Copiar texto del mensaje',
              icono: Icons.copy,
              secundario: true,
              onTap: () {
                Clipboard.setData(ClipboardData(text: _armarTextoCompartir()));
                mostrarAviso(context, 'Texto del billete copiado');
              },
            ),

            const SizedBox(height: 10),

            MitiBoton(
              texto: 'Volver a la campaña',
              secundario: true,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
