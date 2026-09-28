import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miti/nucleo/componentes.dart';
import 'package:miti/nucleo/tema.dart';

Widget _conTicket(String talon) => MaterialApp(
      theme: construirTema(MitiColores.claro, Brightness.light),
      home: Scaffold(
        body: MitiTicket(
          sobrelinea: 'Liquidada en base cobrada',
          importe: r'$ 937.000',
          detalle: r'Recaudado $ 1.000.000 · Gastos $ 63.000',
          talonArriba: talon,
          talonAbajo: 'por integrante',
        ),
      ),
    );

void main() {
  // El talón del ticket tenía un ancho fijo: un importe largo se partía
  // letra por letra ("$ / 93.70 / 0"). Ahora se achica para entrar en una línea.
  testWidgets('el talón muestra un importe largo en una sola línea', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_conTicket(r'$ 93.700'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final texto = tester.widget<Text>(find.text(r'$ 93.700'));
    expect(texto.maxLines, 1);
  });

  testWidgets('el talón sigue entrando con un número corto', (tester) async {
    await tester.pumpWidget(_conTicket('200'));
    await tester.pump();

    expect(find.text('200'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
