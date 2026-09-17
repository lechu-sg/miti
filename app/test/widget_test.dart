import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miti/main.dart';

void main() {
  setUp(() {
    // En la prueba no hay Android: el almacén seguro se simula vacío.
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('sin sesión se ve la pantalla de ingreso', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AppMiti()));
    await tester.pumpAndSettle();

    expect(find.text('MITI'), findsOneWidget);
    expect(find.text('Mandame el código'), findsOneWidget);
  });
}
