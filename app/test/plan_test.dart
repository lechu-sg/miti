import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miti/nucleo/tema.dart';
import 'package:miti/pantallas/plan.dart';

Map<String, dynamic> _plan(String codigo, String nombre, int precio,
        {int? integrantes, int? numeros, int? ventas, bool publicidad = false}) =>
    {
      'codigo': codigo,
      'nombre': nombre,
      'orden': 0,
      'precio': precio,
      'limite_integrantes': integrantes,
      'limite_numeros': numeros,
      'limite_ventas': ventas,
      'limite_campanas_activas': null,
      'publicidad': publicidad,
    };

Map<String, dynamic> _estado({required bool puedePagar}) => {
      'actual': _plan('gratis', 'Gratis', 0, integrantes: 5, numeros: 100, ventas: 20, publicidad: true),
      'uso': {'integrantes': 5, 'numeros': 200, 'ventas': null},
      'mejoras': [
        {'plan': _plan('campana', 'Campaña', 1500000, integrantes: 15, numeros: 1000, ventas: 300), 'a_pagar': 1500000},
        {'plan': _plan('grande', 'Campaña Grande', 2500000, integrantes: 50, numeros: 10000), 'a_pagar': 2500000},
      ],
      'puede_pagar': puedePagar,
      'compra_pendiente': null,
    };

Widget _app(Map<String, dynamic> estado, {required bool esAdmin}) => ProviderScope(
      overrides: [estadoPlanProvider('c1').overrideWith((ref) async => estado)],
      child: MaterialApp(
        theme: construirTema(MitiColores.claro, Brightness.light),
        home: PantallaPlan(campanaId: 'c1', esAdmin: esAdmin),
      ),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  // Pantalla de celular alta, para que las dos mejoras entren sin desplazar.
  void celular(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('el admin ve las mejoras con el precio a pagar', (tester) async {
    celular(tester);
    await tester.pumpWidget(_app(_estado(puedePagar: true), esAdmin: true));
    await tester.pumpAndSettle();

    expect(find.text('Gratis'), findsOneWidget);
    expect(find.text('tenés 200'), findsOneWidget);
    expect(find.text(r'Pagar $ 15.000'), findsOneWidget);
    expect(find.text(r'Pagar $ 25.000'), findsOneWidget);
    expect(find.text('ventas de productos sin límite'), findsOneWidget);
  });

  testWidgets('sin MercadoPago configurado no ofrece pagar', (tester) async {
    celular(tester);
    await tester.pumpWidget(_app(_estado(puedePagar: false), esAdmin: true));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pagar'), findsNothing);
    expect(find.text('El cobro todavía no está habilitado.'), findsNWidgets(2));
  });

  testWidgets('un integrante ve los planes pero no puede pagar', (tester) async {
    celular(tester);
    await tester.pumpWidget(_app(_estado(puedePagar: true), esAdmin: false));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pagar'), findsNothing);
    expect(find.text('La mejora la paga quien administra la campaña.'), findsNWidgets(2));
  });
}
