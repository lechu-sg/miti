import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Cliente de la API de Miti.
///
/// Guarda el token y el refresco en el almacén seguro de Android. Si el token
/// venció, lo renueva solo y repite el pedido una vez.
class ApiMiti {
  ApiMiti({String? base, http.Client? cliente, FlutterSecureStorage? almacen})
      : base = base ?? const String.fromEnvironment('MITI_API', defaultValue: 'https://miti.sole.ar'),
        _http = cliente ?? http.Client(),
        _almacen = almacen ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final String base;
  final http.Client _http;
  final FlutterSecureStorage _almacen;

  String? _token;
  String? _refresco;

  static const _claveToken = 'miti_token';
  static const _claveRefresco = 'miti_refresco';

  bool get haySesion => _refresco != null;

  Future<void> cargarSesion() async {
    _token = await _almacen.read(key: _claveToken);
    _refresco = await _almacen.read(key: _claveRefresco);
  }

  Future<void> _guardar(Map<String, dynamic> datos) async {
    _token = datos['token'] as String;
    _refresco = datos['refresco'] as String;
    await _almacen.write(key: _claveToken, value: _token);
    await _almacen.write(key: _claveRefresco, value: _refresco);
  }

  Future<void> olvidar() async {
    _token = null;
    _refresco = null;
    await _almacen.delete(key: _claveToken);
    await _almacen.delete(key: _claveRefresco);
  }

  Uri _url(String ruta) => Uri.parse('$base$ruta');

  Future<http.Response> _mandar(String metodo, String ruta, {Object? cuerpo, bool conToken = true}) {
    final encabezados = {
      'content-type': 'application/json',
      if (conToken && _token != null) 'authorization': 'Bearer $_token',
    };
    final datos = cuerpo == null ? null : jsonEncode(cuerpo);
    final url = _url(ruta);
    return switch (metodo) {
      'GET' => _http.get(url, headers: encabezados),
      'POST' => _http.post(url, headers: encabezados, body: datos),
      'PATCH' => _http.patch(url, headers: encabezados, body: datos),
      _ => throw ArgumentError('método desconocido: $metodo'),
    };
  }

  Future<dynamic> pedir(String metodo, String ruta, {Object? cuerpo, bool conToken = true}) async {
    var respuesta = await _mandar(metodo, ruta, cuerpo: cuerpo, conToken: conToken);

    if (respuesta.statusCode == 401 && conToken && _refresco != null) {
      if (await _renovar()) {
        respuesta = await _mandar(metodo, ruta, cuerpo: cuerpo, conToken: conToken);
      }
    }

    if (respuesta.statusCode >= 400) {
      throw ErrorApi.desde(respuesta);
    }
    if (respuesta.statusCode == 204 || respuesta.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(respuesta.bodyBytes));
  }

  Future<bool> _renovar() async {
    try {
      final respuesta = await _http.post(
        _url('/acceso/refrescar'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'refresco': _refresco}),
      );
      if (respuesta.statusCode >= 400) {
        await olvidar();
        return false;
      }
      await _guardar(jsonDecode(utf8.decode(respuesta.bodyBytes)) as Map<String, dynamic>);
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- acceso ---

  Future<void> pedirCodigo(String email) => pedir('POST', '/acceso/codigo', cuerpo: {'email': email}, conToken: false);

  Future<void> verificar({
    required String email,
    required String codigo,
    String? nombre,
    DateTime? nacimiento,
  }) async {
    final datos = await pedir('POST', '/acceso/verificar', conToken: false, cuerpo: {
      'email': email,
      'codigo': codigo,
      if (nombre != null) 'nombre': nombre,
      if (nacimiento != null) 'nacimiento': nacimiento.toIso8601String().substring(0, 10),
      'dispositivo': 'android',
    });
    await _guardar(datos as Map<String, dynamic>);
  }

  Future<void> salir() async {
    try {
      if (_refresco != null) {
        await pedir('POST', '/acceso/salir', cuerpo: {'refresco': _refresco});
      }
    } catch (_) {
      // si el servidor no contesta, igual borramos la sesión del celular
    }
    await olvidar();
  }

  Future<Map<String, dynamic>> yo() async => (await pedir('GET', '/yo')) as Map<String, dynamic>;

  // --- campañas ---

  Future<List<dynamic>> campanas() async => (await pedir('GET', '/campanas')) as List<dynamic>;

  Future<Map<String, dynamic>> campana(String id) async =>
      (await pedir('GET', '/campanas/$id')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> crearCampana(Map<String, dynamic> datos) async =>
      (await pedir('POST', '/campanas', cuerpo: datos)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> cambiarEstado(String id, String estado) async =>
      (await pedir('PATCH', '/campanas/$id/estado', cuerpo: {'estado': estado})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> invitar(String id, String email) async =>
      (await pedir('POST', '/campanas/$id/invitaciones', cuerpo: {'email': email})) as Map<String, dynamic>;

  Future<List<dynamic>> invitaciones() async => (await pedir('GET', '/invitaciones')) as List<dynamic>;

  Future<Map<String, dynamic>> responderInvitacion(String id, bool acepta) async =>
      (await pedir('POST', '/campanas/$id/invitacion',
          cuerpo: {'respuesta': acepta ? 'acepto' : 'rechazo'})) as Map<String, dynamic>;

  // --- Fase 2: Rifas, números, ventas y recaudación ---

  Future<List<dynamic>> numeros(String campanaId) async =>
      (await pedir('GET', '/campanas/$campanaId/numeros')) as List<dynamic>;

  Future<Map<String, dynamic>> reservarNumero(String campanaId, int numero, {String? nota}) async =>
      (await pedir('POST', '/campanas/$campanaId/numeros/$numero/reservar',
          cuerpo: {'nota': nota})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> liberarNumero(String campanaId, int numero) async =>
      (await pedir('POST', '/campanas/$campanaId/numeros/$numero/liberar')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> registrarVenta(String campanaId, Map<String, dynamic> datos) async =>
      (await pedir('POST', '/campanas/$campanaId/ventas', cuerpo: datos)) as Map<String, dynamic>;

  Future<List<dynamic>> ventas(String campanaId) async =>
      (await pedir('GET', '/campanas/$campanaId/ventas')) as List<dynamic>;

  Future<Map<String, dynamic>> detalleVenta(String campanaId, String ventaId) async =>
      (await pedir('GET', '/campanas/$campanaId/ventas/$ventaId')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> registrarCobro(
          String campanaId, String ventaId, Map<String, dynamic> datos) async =>
      (await pedir('POST', '/campanas/$campanaId/ventas/$ventaId/cobros', cuerpo: datos))
          as Map<String, dynamic>;

  Future<List<dynamic>> movimientos(String campanaId, {String? estado}) async {
    final ruta = estado != null ? '/campanas/$campanaId/movimientos?estado=$estado' : '/campanas/$campanaId/movimientos';
    return (await pedir('GET', ruta)) as List<dynamic>;
  }

  Future<Map<String, dynamic>> confirmarMovimiento(String campanaId, String movimientoId) async =>
      (await pedir('POST', '/campanas/$campanaId/movimientos/$movimientoId/confirmar'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> rechazarMovimiento(
          String campanaId, String movimientoId, String motivo) async =>
      (await pedir('POST', '/campanas/$campanaId/movimientos/$movimientoId/rechazar',
          cuerpo: {'motivo': motivo})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> recaudacion(String campanaId) async =>
      (await pedir('GET', '/campanas/$campanaId/recaudacion')) as Map<String, dynamic>;

  Future<Map<String, dynamic>> subirComprobante(String campanaId, Map<String, dynamic> datos) async =>
      (await pedir('POST', '/campanas/$campanaId/comprobantes', cuerpo: datos))
          as Map<String, dynamic>;

  // Productos y ventas de productos
  Future<List<dynamic>> productos(String campanaId) async =>
      (await pedir('GET', '/campanas/$campanaId/productos')) as List<dynamic>;

  Future<Map<String, dynamic>> crearProducto(
    String campanaId, {
    required String nombre,
    required int precio,
    String? foto,
  }) async =>
      (await pedir('POST', '/campanas/$campanaId/productos', cuerpo: {
        'nombre': nombre,
        'precio': precio,
        if (foto != null) 'foto': foto,
      })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> modificarProducto(
    String campanaId,
    String productoId, {
    String? nombre,
    int? precio,
    String? foto,
    bool? activo,
  }) async {
    final cuerpo = <String, dynamic>{};
    if (nombre != null) cuerpo['nombre'] = nombre;
    if (precio != null) cuerpo['precio'] = precio;
    if (foto != null) cuerpo['foto'] = foto;
    if (activo != null) cuerpo['activo'] = activo;
    return (await pedir('PATCH', '/campanas/$campanaId/productos/$productoId', cuerpo: cuerpo))
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> venderProductos(String campanaId, Map<String, dynamic> datos) async =>
      (await pedir('POST', '/campanas/$campanaId/ventas/productos', cuerpo: datos))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> actualizarEntrega(
    String campanaId,
    String ventaId,
    String entrega,
  ) async =>
      (await pedir('PATCH', '/campanas/$campanaId/ventas/$ventaId/entrega', cuerpo: {
        'entrega': entrega,
      })) as Map<String, dynamic>;

  // Sincronización offline (§5)
  Future<Map<String, dynamic>> syncPush(
    String campanaId,
    List<Map<String, dynamic>> operaciones,
  ) async =>
      (await pedir('POST', '/campanas/$campanaId/sync/push', cuerpo: {
        'operaciones': operaciones,
      })) as Map<String, dynamic>;

  Future<Map<String, dynamic>> syncPull(
    String campanaId, {
    int desde = 0,
    bool snapshot = false,
  }) async {
    final params = [
      'desde=$desde',
      if (snapshot) 'snapshot=true',
    ].join('&');
    return (await pedir('GET', '/campanas/$campanaId/sync/pull?$params'))
        as Map<String, dynamic>;
  }

  // --- Fase 4: Cierre y liquidación (§3.9) ---

  Future<Map<String, dynamic>> simularLiquidacion(String campanaId) async =>
      (await pedir('GET', '/campanas/$campanaId/liquidacion/simulacion'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> confirmarLiquidacion(
          String campanaId, String base) async =>
      (await pedir('POST', '/campanas/$campanaId/liquidacion',
          cuerpo: {'base': base})) as Map<String, dynamic>;

  Future<Map<String, dynamic>> obtenerLiquidacion(String campanaId) async =>
      (await pedir('GET', '/campanas/$campanaId/liquidacion'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> actualizarTransferencia(
    String campanaId,
    String transferenciaId, {
    required String accion,
    String? comprobanteId,
  }) async =>
      (await pedir(
        'PATCH',
        '/campanas/$campanaId/liquidacion/transferencias/$transferenciaId',
        cuerpo: {
          'accion': accion,
          if (comprobanteId != null) 'comprobante_id': comprobanteId,
        },
      )) as Map<String, dynamic>;

  // --- Gastos (§3.7) ---

  Future<List<dynamic>> gastos(String campanaId) async =>
      (await pedir('GET', '/campanas/$campanaId/gastos')) as List<dynamic>;

  Future<Map<String, dynamic>> crearGasto(
    String campanaId, {
    required String descripcion,
    required int importe,
    required String origen,
    String? cajaId,
    String? comprobanteId,
  }) async =>
      (await pedir('POST', '/campanas/$campanaId/gastos', cuerpo: {
        'descripcion': descripcion,
        'importe': importe,
        'origen': origen,
        if (cajaId != null) 'caja_id': cajaId,
        if (comprobanteId != null) 'comprobante_id': comprobanteId,
      })) as Map<String, dynamic>;
}

/// Un error que vino de la API, ya traducido a algo que se le puede mostrar a la gente.
class ErrorApi implements Exception {
  ErrorApi(this.codigo, this.mensaje);

  final int codigo;
  final String mensaje;

  static ErrorApi desde(http.Response respuesta) {
    String mensaje = 'algo salió mal (${respuesta.statusCode})';
    try {
      final cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes));
      final detalle = cuerpo is Map ? cuerpo['detail'] : null;
      if (detalle is String) {
        mensaje = detalle;
      } else if (detalle is List && detalle.isNotEmpty) {
        final primero = detalle.first;
        if (primero is Map && primero['msg'] is String) {
          mensaje = (primero['msg'] as String).replaceFirst('Value error, ', '');
        }
      }
    } catch (_) {
      // nos quedamos con el mensaje genérico
    }
    return ErrorApi(respuesta.statusCode, mensaje);
  }

  @override
  String toString() => mensaje;
}
