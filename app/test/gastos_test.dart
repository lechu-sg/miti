import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miti/estado/sesion.dart';
import 'package:miti/nucleo/tema.dart';
import 'package:miti/pantallas/hoja_gasto.dart';

class FakeSesion extends Sesion {
  @override
  Future<Map<String, dynamic>?> build() async => {'id': 'user-1', 'nombre': 'Ana'};
}

void main() {
  final tema = construirTema(MitiColores.claro, Brightness.light);

  testWidgets('HojaGasto se renderiza con campos y opciones de origen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final cajas = [
      {'id': 'caja-1', 'tipo': 'efectivo', 'titular_id': 'user-1', 'titular': 'Ana'},
    ];
    final cajasRec = [
      {'caja_id': 'caja-1', 'confirmado': 1500000, 'pendiente': 0},
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sesionProvider.overrideWith(FakeSesion.new),
        ],
        child: MaterialApp(
          theme: tema,
          home: Scaffold(
            body: HojaGasto(
              campanaId: 'camp-1',
              campanaNombre: 'Rifa Prueba',
              cajas: cajas,
              cajasRecaudacion: cajasRec,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('REGISTRAR GASTO'), findsOneWidget);
    expect(find.text('¿En qué se gastó?'), findsOneWidget);
    expect(find.text('Importe del gasto'), findsOneWidget);
    expect(find.text('De mi bolsillo'), findsOneWidget);
    expect(find.text('De lo cobrado en mi caja'), findsOneWidget);
    expect(find.text('Registrar gasto'), findsOneWidget);
  });
}
