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

  testWidgets('PantallaGanador muestra tarjeta con múltiples premios y ganadores', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final sorteos = [
      {
        'orden': 1,
        'numero_sorteado': 77,
        'numero_ganador': 77,
        'premio': 'Moto 110cc 0km',
        'estado_resultado': 'ganador_encontrado',
        'ganador_nombre': 'Carlos Ganador',
        'ganador_telefono': '1122334455',
        'vendedor_nombre': 'Ana Vendedora',
        'codigo_corto': 'GAN001',
      },
      {
        'orden': 2,
        'numero_sorteado': 12,
        'numero_ganador': 1,
        'premio': 'Smart TV 50 pulgadas',
        'estado_resultado': 'siguiente_vendido',
        'ganador_nombre': 'Lucia Ganadora',
        'ganador_telefono': '1199887766',
        'vendedor_nombre': 'Beto Vendedor',
        'codigo_corto': 'GAN002',
      },
    ];

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
            sorteosIniciales: sorteos,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('RESULTADOS DEL SORTEO'), findsOneWidget);
    expect(find.text('GRAN RIFA ANUAL'), findsOneWidget);
    expect(find.text('¡RESULTADOS DEL SORTEO!'), findsOneWidget);
    expect(find.text('1° PREMIO'), findsOneWidget);
    expect(find.text('Moto 110cc 0km'), findsOneWidget);
    expect(find.text('#77'), findsOneWidget);
    expect(find.text('Carlos Ganador'), findsOneWidget);
    expect(find.text('2° PREMIO'), findsOneWidget);
    expect(find.text('Smart TV 50 pulgadas'), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);
    expect(find.text('Lucia Ganadora'), findsOneWidget);
    expect(find.text('Enviar resultados por WhatsApp'), findsOneWidget);
  });
}
