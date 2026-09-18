import 'package:flutter_test/flutter_test.dart';
import 'package:miti/nucleo/formato.dart';
import 'package:miti/nucleo/sincronizador.dart';

void main() {
  test('generarUuid genera cadenas UUID v4 válidas', () {
    final uuid1 = generarUuid();
    final uuid2 = generarUuid();

    expect(uuid1, isNot(equals(uuid2)));
    // Formato xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
    final exp = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    expect(exp.hasMatch(uuid1), isTrue);
    expect(exp.hasMatch(uuid2), isTrue);
  });

  test('EstadoSincro detecta pendientes y conflictos', () {
    const s0 = EstadoSincro();
    expect(s0.tienePendientes, isFalse);
    expect(s0.tieneConflictos, isFalse);

    final s1 = s0.copiarCon(pendientes: 2);
    expect(s1.tienePendientes, isTrue);
    expect(s1.tieneConflictos, isFalse);

    final s2 = s1.copiarCon(conflictos: 1);
    expect(s2.tienePendientes, isTrue);
    expect(s2.tieneConflictos, isTrue);
  });
}
