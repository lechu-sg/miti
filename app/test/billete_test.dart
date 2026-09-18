import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miti/nucleo/formato.dart';
import 'package:miti/nucleo/tema.dart';
import 'package:miti/pantallas/billete.dart';

void main() {
  final tema = construirTema(MitiColores.claro, Brightness.light);

  testWidgets('PantallaBillete muestra números de rifa', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tema,
        home: const PantallaBillete(
          campanaNombre: 'Rifa Anual',
          numeros: [42, 43],
          importe: 400000, // $4.000
          compradorNombre: 'Carlos Gómez',
          compradorTelefono: '1122334455',
          vendedorNombre: 'Ana',
          codigoCorto: 'A1B2C3',
          estaPagado: true,
        ),
      ),
    );

    expect(find.text('RIFA ANUAL'), findsOneWidget);
    expect(find.text('Carlos Gómez'), findsOneWidget);
    expect(find.text('PAGADO'), findsOneWidget);
    expect(find.text('NÚMEROS ASIGNADOS'), findsOneWidget);
    expect(find.text('42 · 43'), findsOneWidget);
    expect(find.text(plata(400000)), findsOneWidget);
    expect(find.text('#A1B2C3'), findsOneWidget);
  });

  testWidgets('PantallaBillete muestra lista de productos y estado de entrega', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: tema,
        home: const PantallaBillete(
          campanaNombre: 'Venta de Empanadas',
          numeros: [],
          itemsProductos: [
            {'cantidad': 2, 'nombre': 'Docena Carne', 'subtotal': 2400000},
            {'cantidad': 1, 'nombre': 'Docena JyQ', 'subtotal': 1200000},
          ],
          entrega: 'pedido',
          importe: 3600000, // $36.000
          compradorNombre: 'Beatriz',
          compradorTelefono: null,
          vendedorNombre: 'Beto',
          codigoCorto: 'EMP001',
          estaPagado: false,
        ),
      ),
    );

    expect(find.text('VENTA DE EMPANADAS'), findsOneWidget);
    expect(find.text('Beatriz'), findsOneWidget);
    expect(find.text('A PAGAR'), findsOneWidget);
    expect(find.text('PRODUCTOS'), findsOneWidget);
    expect(find.text('PEDIDO'), findsOneWidget);
    expect(find.text('Docena Carne'), findsOneWidget);
    expect(find.text('Docena JyQ'), findsOneWidget);
    expect(find.text(plata(3600000)), findsOneWidget);
    expect(find.text('Enviar comprobante por WhatsApp'), findsOneWidget);
  });
}
