import 'package:flutter_test/flutter_test.dart';
import 'package:miti/nucleo/formato.dart';

void main() {
  test('los pesos se escriben con el signo adelante, como en Argentina', () {
    expect(plata(1500000), r'$ 15.000');
    expect(plata(123456), r'$ 1.234,56');
    expect(plata(100, exacto: true), r'$ 1,00');
    expect(plata(-250000), r'-$ 2.500');
    expect(plata(0), r'$ 0');
  });

  test('miles separa con punto', () {
    expect(miles(10000), '10.000');
  });
}
