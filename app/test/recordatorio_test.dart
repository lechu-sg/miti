import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miti/estado/sesion.dart';
import 'package:miti/nucleo/api.dart';
import 'package:miti/nucleo/tema.dart';
import 'package:miti/pantallas/hoja_recordatorio.dart';

class FakeApiRecordatorio extends ApiMiti {
  FakeApiRecordatorio({this.respuesta, this.debeFallar = false});

  final Map<String, dynamic>? respuesta;
  final bool debeFallar;

  @override
  Future<Map<String, dynamic>> redactarRecordatorio(
    String campanaId,
    String ventaId, {
    String tono = 'amable',
  }) async {
    if (debeFallar) {
      throw Exception('Fallo de red o servidor no disponible');
    }
    return respuesta ??
        {
          'mensaje': 'Hola Juan, te recordamos el pago de la rifa.',
          'origen': 'ia_local',
          'modelo': 'llama3.2:3b',
          'demoro_ms': 1500,
        };
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  final tema = construirTema(MitiColores.claro, Brightness.light);

  final ventaEjemplo = {
    'id': 'venta-123',
    'comprador': {'nombre': 'Juan Gómez'},
    'saldo_adeudado': 500000,
    'codigo_corto': 'TK-99',
    'numeros': [42],
  };

  void configurarPantalla(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('muestra el texto propuesto por la IA y la leyenda de aviso', (tester) async {
    configurarPantalla(tester);

    final api = FakeApiRecordatorio(
      respuesta: {
        'mensaje': 'Hola Juan! Mensaje redactado por IA para la rifa.',
        'origen': 'ia_local',
        'modelo': 'llama3.2:3b',
        'demoro_ms': 2000,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          theme: tema,
          home: Scaffold(
            body: HojaRecordatorio(
              campanaId: 'camp-1',
              campanaNombre: 'Rifa Club',
              venta: ventaEjemplo,
              alias: 'club.miti.mp',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Recordatorio de pago'), findsOneWidget);
    expect(find.text('PARA JUAN GÓMEZ'), findsOneWidget);
    expect(find.text('Hola Juan! Mensaje redactado por IA para la rifa.'), findsOneWidget);
    expect(
      find.text('Redactado por la IA del servidor de Miti. Revisalo antes de mandarlo.'),
      findsOneWidget,
    );
    expect(find.text('Enviar por WhatsApp'), findsOneWidget);
    expect(find.text('Otra redacción'), findsOneWidget);
  });

  testWidgets('el campo de texto es editable por el usuario', (tester) async {
    configurarPantalla(tester);

    final api = FakeApiRecordatorio(
      respuesta: {
        'mensaje': 'Mensaje inicial de IA',
        'origen': 'ia_local',
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          theme: tema,
          home: Scaffold(
            body: HojaRecordatorio(
              campanaId: 'camp-1',
              campanaNombre: 'Rifa Club',
              venta: ventaEjemplo,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verificamos el texto inicial
    expect(find.text('Mensaje inicial de IA'), findsOneWidget);

    // Editamos el campo
    await tester.enterText(find.byType(TextField), 'Mensaje editado por el usuario a mano');
    await tester.pump();

    // Verificamos que refleja el texto editado
    expect(find.text('Mensaje editado por el usuario a mano'), findsOneWidget);
    expect(find.text('Mensaje inicial de IA'), findsNothing);
  });

  testWidgets('con origen "plantilla" no aparece la leyenda de la IA', (tester) async {
    configurarPantalla(tester);

    final api = FakeApiRecordatorio(
      respuesta: {
        'mensaje': 'Hola Juan! Mensaje que vino de la plantilla.',
        'origen': 'plantilla',
        'modelo': null,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          theme: tema,
          home: Scaffold(
            body: HojaRecordatorio(
              campanaId: 'camp-1',
              campanaNombre: 'Rifa Club',
              venta: ventaEjemplo,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Hola Juan! Mensaje que vino de la plantilla.'), findsOneWidget);
    expect(
      find.text('Redactado por la IA del servidor de Miti. Revisalo antes de mandarlo.'),
      findsNothing,
    );
  });

  testWidgets('si el servidor falla se mantiene la plantilla local sin errores', (tester) async {
    configurarPantalla(tester);

    final api = FakeApiRecordatorio(debeFallar: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          theme: tema,
          home: Scaffold(
            body: HojaRecordatorio(
              campanaId: 'camp-1',
              campanaNombre: 'Rifa Club',
              venta: ventaEjemplo,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Muestra la plantilla local que contiene el nombre del comprador y el saldo
    expect(find.textContaining('Juan Gómez'), findsWidgets);
    expect(find.textContaining('Saldo a pagar'), findsOneWidget);
    expect(
      find.text('Redactado por la IA del servidor de Miti. Revisalo antes de mandarlo.'),
      findsNothing,
    );
  });
}
