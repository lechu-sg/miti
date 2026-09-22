import 'package:intl/intl.dart';

/// La plata viaja SIEMPRE en centavos enteros. Acá se convierte para mostrar.
// Ojo: el formato de moneda de es_AR de intl pone el signo DESPUÉS ("15.000 $").
// En Argentina se escribe "$ 15.000", así que se usa el número solo y el signo adelante.
final _pesos = NumberFormat('#,##0', 'es_AR');
final _conCentavos = NumberFormat('#,##0.00', 'es_AR');
final _fecha = DateFormat('d/M/y', 'es_AR');

String plata(int centavos, {bool exacto = false}) {
  final valor = centavos / 100;
  final signo = valor < 0 ? '-' : '';
  final cifra = (!exacto && centavos % 100 == 0 ? _pesos : _conCentavos).format(valor.abs());
  return '$signo\$ $cifra';
}

int? aCentavos(String texto) {
  final limpio = texto.replaceAll(RegExp(r'[^0-9,.]'), '').replaceAll('.', '').replaceAll(',', '.');
  final valor = double.tryParse(limpio);
  if (valor == null) return null;
  return (valor * 100).round();
}

/// 10000 → "10.000".
String miles(int n) => NumberFormat.decimalPattern('es_AR').format(n);

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
