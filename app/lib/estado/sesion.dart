import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nucleo/api.dart';

final apiProvider = Provider<ApiMiti>((ref) => ApiMiti());

/// Quién está usando la app. `null` = nadie entró todavía.
class Sesion extends AsyncNotifier<Map<String, dynamic>?> {
  ApiMiti get _api => ref.read(apiProvider);

  @override
  Future<Map<String, dynamic>?> build() async {
    await _api.cargarSesion();
    if (!_api.haySesion) return null;
    try {
      return await _api.yo();
    } on ErrorApi {
      await _api.olvidar();
      return null;
    }
  }

  Future<void> pedirCodigo(String email) => _api.pedirCodigo(email);

  Future<void> verificar({
    required String email,
    required String codigo,
    String? nombre,
    DateTime? nacimiento,
  }) async {
    await _api.verificar(email: email, codigo: codigo, nombre: nombre, nacimiento: nacimiento);
    state = AsyncData(await _api.yo());
  }

  Future<void> salir() async {
    await _api.salir();
    ref.invalidate(campanasProvider);
    ref.invalidate(invitacionesProvider);
    state = const AsyncData(null);
  }
}

final sesionProvider = AsyncNotifierProvider<Sesion, Map<String, dynamic>?>(Sesion.new);

final campanasProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return ref.watch(apiProvider).campanas();
});

final invitacionesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  return ref.watch(apiProvider).invitaciones();
});

final campanaProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  return ref.watch(apiProvider).campana(id);
});

final numerosProvider =
    FutureProvider.autoDispose.family<List<dynamic>, String>((ref, id) async {
  return ref.watch(apiProvider).numeros(id);
});

final ventasProvider =
    FutureProvider.autoDispose.family<List<dynamic>, String>((ref, id) async {
  return ref.watch(apiProvider).ventas(id);
});

final movimientosProvider =
    FutureProvider.autoDispose.family<List<dynamic>, String>((ref, id) async {
  return ref.watch(apiProvider).movimientos(id);
});

final recaudacionProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  return ref.watch(apiProvider).recaudacion(id);
});

final productosProvider =
    FutureProvider.autoDispose.family<List<dynamic>, String>((ref, id) async {
  return ref.watch(apiProvider).productos(id);
});

final simulacionLiquidacionProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  return ref.watch(apiProvider).simularLiquidacion(id);
});

final liquidacionProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  return ref.watch(apiProvider).obtenerLiquidacion(id);
});


