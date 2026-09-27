import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../estado/sesion.dart';
import '../nucleo/componentes.dart';
import '../nucleo/recordatorio_deuda.dart';
import '../nucleo/tema.dart';

/// Abre la hoja inferior para revisar, pedir redacción con IA y enviar el recordatorio.
Future<void> mostrarHojaRecordatorio(
  BuildContext context, {
  required String campanaId,
  required Map<String, dynamic> venta,
  required String campanaNombre,
  String? alias,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => HojaRecordatorio(
      campanaId: campanaId,
      venta: venta,
      campanaNombre: campanaNombre,
      alias: alias,
    ),
  );
}

/// Hoja para redactar y enviar recordatorio de pago a compradores deudores (§7.4 de DEFINICION.md).
class HojaRecordatorio extends ConsumerStatefulWidget {
  const HojaRecordatorio({
    super.key,
    required this.campanaId,
    required this.venta,
    required this.campanaNombre,
    this.alias,
  });

  final String campanaId;
  final Map<String, dynamic> venta;
  final String campanaNombre;
  final String? alias;

  @override
  ConsumerState<HojaRecordatorio> createState() => _HojaRecordatorioState();
}

class _HojaRecordatorioState extends ConsumerState<HojaRecordatorio> {
  late final TextEditingController _controlador;
  bool _redactando = false;
  String? _origen;

  @override
  void initState() {
    super.initState();
    // Mientras llega la redacción del servidor, mostramos la plantilla local.
    final textoInicial = generarMensajeRecordatorio(
      venta: widget.venta,
      campanaNombre: widget.campanaNombre,
      alias: widget.alias,
    );
    _controlador = TextEditingController(text: textoInicial);
    _pedirRedaccion();
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _pedirRedaccion({String tono = 'amable'}) async {
    if (_redactando) return;

    final ventaId = widget.venta['id']?.toString();
    if (ventaId == null || ventaId.isEmpty) {
      if (mounted) setState(() => _origen = 'plantilla');
      return;
    }

    setState(() => _redactando = true);

    try {
      final res = await ref.read(apiProvider).redactarRecordatorio(
            widget.campanaId,
            ventaId,
            tono: tono,
          );
      if (mounted) {
        final nuevoTexto = res['mensaje'] as String?;
        if (nuevoTexto != null && nuevoTexto.trim().isNotEmpty) {
          _controlador.text = nuevoTexto;
        }
        setState(() {
          _origen = res['origen'] as String? ?? 'plantilla';
          _redactando = false;
        });
      }
    } catch (_) {
      // Sin señal o si el servidor falla: se usa la plantilla local y la hoja funciona igual.
      if (mounted) {
        setState(() {
          _origen = 'plantilla';
          _redactando = false;
        });
      }
    }
  }

  Future<void> _enviarPorWhatsApp() async {
    final texto = _controlador.text.trim();
    if (texto.isEmpty) return;

    Navigator.of(context).pop();
    await SharePlus.instance.share(ShareParams(text: texto));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    final comprador = (widget.venta['comprador'] as Map?)?.cast<String, dynamic>() ?? {};
    final compradorNombre = comprador['nombre'] as String? ?? 'Comprador';

    return MitiHoja(
      titulo: 'RECORDATORIO DE PAGO',
      subtitulo: 'Para $compradorNombre',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Mensaje a enviar:',
            style: t.etiqueta.copyWith(color: c.tinta),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controlador,
            maxLines: 8,
            minLines: 4,
            style: t.cuerpo.copyWith(color: c.tinta, height: 1.4),
            decoration: InputDecoration(
              filled: true,
              fillColor: c.papelHundido,
              hintText: 'Escribí el mensaje para el comprador...',
              hintStyle: t.cuerpo.copyWith(color: c.tintaSuave),
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: c.troquel),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: c.troquel),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: c.tinta, width: 1.5),
              ),
            ),
          ),
          if (_origen == 'ia_local') ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, size: 14, color: c.tintaSuave),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Redactado por la IA del servidor de Miti. Revisalo antes de mandarlo.',
                    style: t.pie.copyWith(color: c.tintaSuave),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          MitiBoton(
            texto: 'Enviar por WhatsApp',
            icono: Icons.send_rounded,
            onTap: _enviarPorWhatsApp,
          ),
          const SizedBox(height: 10),
          MitiBoton(
            texto: _redactando ? 'Redactando...' : 'Otra redacción',
            secundario: true,
            cargando: _redactando,
            icono: Icons.refresh_rounded,
            onTap: _redactando ? null : () => _pedirRedaccion(),
          ),
        ],
      ),
    );
  }
}
