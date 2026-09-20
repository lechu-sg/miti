import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'formato.dart';

/// Helper para enviar recordatorios de cobro a compradores deudores (§7.4 de DEFINICION.md).
String generarMensajeRecordatorio({
  required Map<String, dynamic> venta,
  required String campanaNombre,
  String? alias,
}) {
  final comprador = (venta['comprador'] as Map?)?.cast<String, dynamic>() ?? {};
  final nombre = comprador['nombre'] as String? ?? 'Hola';
  final saldo = (venta['saldo_adeudado'] as num?)?.toInt() ?? 0;
  final codigoCorto = venta['codigo_corto'] as String? ?? '';

  final numeros = (venta['numeros'] as List?)?.map((e) => '#$e').join(', ');
  final itemsProd = (venta['items_productos'] as List?)
      ?.map((it) => '${it['cantidad']}x ${it['nombre']}')
      .join(', ');

  final detalle = (numeros != null && numeros.isNotEmpty)
      ? 'Números: $numeros'
      : ((itemsProd != null && itemsProd.isNotEmpty) ? 'Detalle: $itemsProd' : '');

  var msg = '¡Hola $nombre! Te escribo de la campaña *$campanaNombre*.\n\n'
      'Te recordamos que tenés pendiente de abonar tu colaboración:\n'
      '💰 *Saldo a pagar:* ${plata(saldo)}\n';

  if (detalle.isNotEmpty) {
    msg += '🎟️ *$detalle*\n';
  }
  if (codigoCorto.isNotEmpty) {
    msg += '📌 *Ticket:* #$codigoCorto\n';
  }
  if (alias != null && alias.trim().isNotEmpty) {
    msg += '\nPodés transferir a la cuenta de la campaña:\n'
        '🏦 *Alias:* `$alias`\n';
  }

  msg += '\n¡Muchas gracias por colaborar!';
  return msg;
}

Future<void> enviarRecordatorioDeuda(
  BuildContext context, {
  required Map<String, dynamic> venta,
  required String campanaNombre,
  String? alias,
}) async {
  final msg = generarMensajeRecordatorio(
    venta: venta,
    campanaNombre: campanaNombre,
    alias: alias,
  );

  await SharePlus.instance.share(ShareParams(text: msg));
}
