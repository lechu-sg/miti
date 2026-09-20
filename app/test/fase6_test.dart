import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miti/estado/sesion.dart';
import 'package:miti/nucleo/recordatorio_deuda.dart';
import 'package:miti/nucleo/tema.dart';
import 'package:miti/pantallas/hoja_ranking.dart';
import 'package:miti/pantallas/muro_avisos.dart';

class FakeSesion extends Sesion {
  @override
  Future<Map<String, dynamic>?> build() async => {'id': 'user-1', 'nombre': 'Ana'};
}

void main() {
  final tema = construirTema(MitiColores.claro, Brightness.light);

  group('Recordatorios de cobro a deudores', () {
    test('generarMensajeRecordatorio incluye datos de campana, saldo y alias', () {
      final venta = {
        'comprador': {'nombre': 'Carlos'},
        'saldo_adeudado': 250000,
        'codigo_corto': 'TK-01',
        'numeros': ['042', '088'],
      };
      final msg = generarMensajeRecordatorio(
        venta: venta,
        campanaNombre: 'Rifa Club',
        alias: 'club.miti.mp',
      );

      expect(msg.contains('Hola Carlos!'), isTrue);
      expect(msg.contains('Rifa Club'), isTrue);
      expect(msg.contains('2.500'), isTrue);
      expect(msg.contains('club.miti.mp'), isTrue);
      expect(msg.contains('#042, #088'), isTrue);
    });
  });

  group('Ranking y Muro de Avisos UI', () {
    testWidgets('HojaRanking se renderiza con podio y lista', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockRanking = {
        'campana_id': 'camp-1',
        'tipo': 'rifa',
        'items': [
          {'usuario_id': 'u1', 'nombre': 'Ana', 'cantidad': 15, 'recaudado': 1500000},
          {'usuario_id': 'u2', 'nombre': 'Beto', 'cantidad': 10, 'recaudado': 1000000},
          {'usuario_id': 'u3', 'nombre': 'Carla', 'cantidad': 5, 'recaudado': 500000},
          {'usuario_id': 'u4', 'nombre': 'Daniel', 'cantidad': 2, 'recaudado': 200000},
        ],
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sesionProvider.overrideWith(FakeSesion.new),
            rankingProvider('camp-1').overrideWith((ref) => Future.value(mockRanking)),
          ],
          child: MaterialApp(
            theme: tema,
            home: const Scaffold(
              body: HojaRanking(
                campanaId: 'camp-1',
                campanaNombre: 'Rifa Anual',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('POSICIONES DEL EQUIPO'), findsOneWidget);
      expect(find.text('Ana'), findsWidgets);
      expect(find.text('Beto'), findsWidgets);
      expect(find.text('Carla'), findsWidgets);
      expect(find.text('Daniel'), findsWidgets);
    });

    testWidgets('PantallaMuroAvisos muestra avisos fijados y regulares', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockAvisos = [
        {
          'id': 'av-1',
          'campana_id': 'camp-1',
          'autor_id': 'u1',
          'autor_nombre': 'Ana Admin',
          'titulo': '¡Atención al cierre!',
          'mensaje': 'Quedan pocas horas para liquidar.',
          'fijado': true,
          'creado_en': '2026-09-20T10:00:00Z',
        },
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sesionProvider.overrideWith(FakeSesion.new),
            avisosProvider('camp-1').overrideWith((ref) => Future.value(mockAvisos)),
          ],
          child: MaterialApp(
            theme: tema,
            home: const Scaffold(
              body: PantallaMuroAvisos(
                campanaId: 'camp-1',
                campanaNombre: 'Rifa Anual',
                esAdmin: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MURO DE AVISOS'), findsOneWidget);
      expect(find.text('Ana Admin'), findsOneWidget);
      expect(find.text('Quedan pocas horas para liquidar.'), findsOneWidget);
      expect(find.text('FIJADO'), findsOneWidget);
    });
  });
}
