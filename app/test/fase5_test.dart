import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miti/estado/sesion.dart';
import 'package:miti/nucleo/tema.dart';
import 'package:miti/pantallas/ganador.dart';
import 'package:miti/pantallas/hoja_entrega.dart';

class FakeSesion extends Sesion {
  @override
  Future<Map<String, dynamic>?> build() async => {'id': 'user-1', 'nombre': 'Ana'};
}

void main() {
  final tema = construirTema(MitiColores.claro, Brightness.light);

  testWidgets('HojaEntrega se renderiza con campos y saldos de origen y destino', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final cajas = [
      {'id': 'caja-1', 'tipo': 'efectivo', 'titular_id': 'user-1', 'titular': {'nombre': 'Ana'}},
      {'id': 'caja-2', 'tipo': 'efectivo', 'titular_id': 'user-2', 'titular': {'nombre': 'Beto'}},
    ];
    final cajasRec = [
      {'caja_id': 'caja-1', 'confirmado': 2000000, 'pendiente': 0},
      {'caja_id': 'caja-2', 'confirmado': 500000, 'pendiente': 0},
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sesionProvider.overrideWith(FakeSesion.new),
        ],
        child: MaterialApp(
          theme: tema,
          home: Scaffold(
            body: HojaEntrega(
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

    expect(find.text('PASAR DINERO / ENTREGA'), findsOneWidget);
    expect(find.text('DESDE MI CAJA'), findsOneWidget);
    expect(find.text('HACIA LA CAJA DE'), findsOneWidget);
    expect(find.text('Monto a entregar'), findsOneWidget);
    expect(find.text('Registrar entrega'), findsOneWidget);
  });

  testWidgets('PantallaGanador muestra tarjeta con número ganador', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final sorteo = {
      'numero_sorteado': 77,
      'numero_ganador': 77,
      'premio': 'Bicicleta Rodado 29',
      'estado_resultado': 'ganador_encontrado',
      'ganador_nombre': 'Carlos Ganador',
      'ganador_telefono': '1122334455',
      'vendedor_nombre': 'Ana Vendedora',
      'codigo_corto': 'GAN001',
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sesionProvider.overrideWith(FakeSesion.new),
        ],
        child: MaterialApp(
          theme: tema,
          home: PantallaGanador(
            campanaId: 'camp-1',
            campanaNombre: 'Gran Rifa Anual',
            esAdmin: true,
            sorteoInicial: sorteo,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SORTEO Y GANADOR'), findsOneWidget);
    expect(find.text('GRAN RIFA ANUAL'), findsOneWidget);
    expect(find.text('¡TENEMOS GANADOR!'), findsOneWidget);
    expect(find.text('Bicicleta Rodado 29'), findsOneWidget);
    expect(find.text('#77'), findsOneWidget);
    expect(find.text('Carlos Ganador'), findsOneWidget);
    expect(find.text('1122334455'), findsOneWidget);
    expect(find.text('Enviar resultado por WhatsApp'), findsOneWidget);
  });
}
