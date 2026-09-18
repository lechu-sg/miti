import 'package:intl/intl.dart';

/// La plata viaja SIEMPRE en centavos enteros. Acá se convierte para mostrar.
final _pesos = NumberFormat.currency(locale: 'es_AR', symbol: r'$ ', decimalDigits: 0);
final _conCentavos = NumberFormat.currency(locale: 'es_AR', symbol: r'$ ', decimalDigits: 2);
final _fecha = DateFormat('d/M/y', 'es_AR');

String plata(int centavos, {bool exacto = false}) {
  final valor = centavos / 100;
  if (!exacto && centavos % 100 == 0) return _pesos.format(valor);
  return _conCentavos.format(valor);
}

int? aCentavos(String texto) {
  final limpio = texto.replaceAll(RegExp(r'[^0-9,.]'), '').replaceAll('.', '').replaceAll(',', '.');
  final valor = double.tryParse(limpio);
  if (valor == null) return null;
  return (valor * 100).round();
}

String fechaCorta(DateTime cuando) => _fecha.format(cuando.toLocal());

String iniciales(String nombre) {
  final partes = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
  return (partes.first.substring(0, 1) + partes.last.substring(0, 1)).toUpperCase();
}

String generarUuid() {
  final rnd = DateTime.now().microsecondsSinceEpoch;
  final r = List<int>.generate(16, (i) => (rnd >> (i * 4) ^ (i * 31 + 7)) & 0xff);
  r[6] = (r[6] & 0x0f) | 0x40;
  r[8] = (r[8] & 0x3f) | 0x80;
  return [
    r.sublist(0, 4),
    r.sublist(4, 6),
    r.sublist(6, 8),
    r.sublist(8, 10),
    r.sublist(10, 16),
  ].map((p) => p.map((b) => b.toRadixString(16).padLeft(2, '0')).join()).join('-');
}
