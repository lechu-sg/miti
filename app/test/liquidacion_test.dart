import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miti/estado/sesion.dart';
import 'package:miti/nucleo/tema.dart';
import 'package:miti/pantallas/liquidacion.dart';

void main() {
  final tema = construirTema(MitiColores.claro, Brightness.light);

  testWidgets('PantallaLiquidacion en modo simulación muestra bases e integrantes', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final mockSimulacion = {
      'puede_liquidar': true,
      'impedimentos': <String>[],
      'base_cobrada': {
        'neto': 600000,
        'parte': 200000,
        'recaudado': 600000,
        'gastos': 0,
        'participantes': [
          {'usuario_id': 'u1', 'nombre': 'Ana', 'recaudado': 600000, 'parte': 200000, 'balance': 400000},
          {'usuario_id': 'u2', 'nombre': 'Beto', 'recaudado': 0, 'parte': 200000, 'balance': -200000},
          {'usuario_id': 'u3', 'nombre': 'Carlos', 'recaudado': 0, 'parte': 200000, 'balance': -200000},
        ],
        'transferencias': [
          {'de_usuario_id': 'u1', 'de_nombre': 'Ana', 'a_usuario_id': 'u2', 'a_nombre': 'Beto', 'importe': 200000},
          {'de_usuario_id': 'u1', 'de_nombre': 'Ana', 'a_usuario_id': 'u3', 'a_nombre': 'Carlos', 'importe': 200000},
        ],
      },
      'base_vendida': {
        'neto': 900000,
        'parte': 300000,
        'recaudado': 900000,
        'gastos': 0,
        'participantes': [
          {'usuario_id': 'u1', 'nombre': 'Ana', 'recaudado': 600000, 'parte': 300000, 'balance': 300000},
          {'usuario_id': 'u2', 'nombre': 'Beto', 'recaudado': 300000, 'parte': 300000, 'balance': 0},
          {'usuario_id': 'u3', 'nombre': 'Carlos', 'recaudado': 0, 'parte': 300000, 'balance': -300000},
        ],
        'transferencias': [
          {'de_usuario_id': 'u1', 'de_nombre': 'Ana', 'a_usuario_id': 'u3', 'a_nombre': 'Carlos', 'importe': 300000},
        ],
      },
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          simulacionLiquidacionProvider('camp-123').overrideWith((ref) async => mockSimulacion),
        ],
        child: MaterialApp(
          theme: tema,
          home: const PantallaLiquidacion(
            campanaId: 'camp-123',
            campanaNombre: 'Rifa Fin de Año',
            esAdmin: true,
            estadoCampana: 'cerrada',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('CIERRE Y LIQUIDACIÓN'), findsOneWidget);
    expect(find.text('Rifa Fin de Año'), findsOneWidget);
    expect(find.text('Base Cobrada'), findsOneWidget);
    expect(find.text('Base Vendida'), findsOneWidget);
    expect(find.text('Ana'), findsWidgets);
    expect(find.text('Beto'), findsWidgets);
    expect(find.text('Carlos'), findsWidgets);
    expect(find.text('Confirmar liquidación'), findsOneWidget);
  });

  testWidgets('PantallaLiquidacion en modo liquidada muestra transferencias y estado', (tester) async {
    final mockLiquidacion = {
      'campana_id': 'camp-123',
      'base': 'cobrada',
      'neto': 600000,
      'parte': 200000,
      'recaudado': 600000,
      'gastos': 0,
      'confirmada_por_nombre': 'Ana',
      'transferencias': [
        {
          'id': 'tr-1',
          'de_usuario_id': 'u1',
          'de_nombre': 'Ana',
          'a_usuario_id': 'u2',
          'a_nombre': 'Beto',
          'importe': 200000,
          'estado': 'pendiente',
        },
      ],
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          liquidacionProvider('camp-123').overrideWith((ref) async => mockLiquidacion),
        ],
        child: MaterialApp(
          theme: tema,
          home: const PantallaLiquidacion(
            campanaId: 'camp-123',
            campanaNombre: 'Rifa Fin de Año',
            esAdmin: false,
            estadoCampana: 'liquidada',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('LIQUIDACIÓN FINAL'), findsOneWidget);
    expect(find.text('TODAS LAS TRANSFERENCIAS'), findsOneWidget);
    expect(find.text('PENDIENTE'), findsOneWidget);
  });
}
