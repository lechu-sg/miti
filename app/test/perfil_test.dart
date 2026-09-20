import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miti/estado/ajustes.dart';
import 'package:miti/estado/sesion.dart';
import 'package:miti/nucleo/tema.dart';
import 'package:miti/pantallas/legales.dart';
import 'package:miti/pantallas/perfil.dart';

class FakeSesionPerfil extends Sesion {
  @override
  Future<Map<String, dynamic>?> build() async => {
        'id': 'u-perfil-1',
        'nombre': 'Martín Fierro',
        'email': 'martin@campo.ar',
      };
}

void main() {
  final tema = construirTema(MitiColores.claro, Brightness.light);

  group('Ajustes y Modo de Tema', () {
    test('ModoTema tiene etiquetas correctas en rioplatense', () {
      expect(ModoTema.sistema.etiqueta, 'Automático');
      expect(ModoTema.claro.etiqueta, 'Claro');
      expect(ModoTema.oscuro.etiqueta, 'Oscuro');
    });
  });

  group('PantallaPerfil UI', () {
    testWidgets('se renderiza con datos del usuario, tema, flag secure y legales', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sesionProvider.overrideWith(FakeSesionPerfil.new),
          ],
          child: MaterialApp(
            theme: tema,
            home: const PantallaPerfil(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MI PERFIL'), findsOneWidget);
      expect(find.text('Martín Fierro'), findsOneWidget);
      expect(find.text('martin@campo.ar'), findsOneWidget);
      expect(find.text('APARIENCIA'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Claro'), findsOneWidget);
      expect(find.text('Oscuro'), findsOneWidget);
      expect(find.text('SEGURIDAD'), findsOneWidget);
      expect(find.text('Protección de pantalla'), findsOneWidget);
      expect(find.text('Términos y Condiciones de Uso'), findsOneWidget);
      expect(find.text('Política de Privacidad (Ley 25.326)'), findsOneWidget);
      expect(find.text('Botón de arrepentimiento'), findsOneWidget);
      expect(find.text('Eliminar mi cuenta'), findsOneWidget);
    });
  });

  group('Pantallas Legales UI', () {
    testWidgets('PantallaLegales muestra términos y condiciones', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: tema,
          home: const PantallaLegales(tipo: TipoDocumentoLegal.terminos),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TÉRMINOS Y CONDICIONES'), findsOneWidget);
      expect(find.text('1. Herramienta de registro'), findsOneWidget);
    });

    testWidgets('PantallaLegales muestra botón de arrepentimiento con soporte', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: tema,
          home: const PantallaLegales(tipo: TipoDocumentoLegal.arrepentimiento),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BOTÓN DE ARREPENTIMIENTO'), findsOneWidget);
      expect(find.text('soporte@miti.sole.ar'), findsOneWidget);
    });
  });
}
