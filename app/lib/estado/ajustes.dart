import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum ModoTema {
  sistema,
  claro,
  oscuro;

  String get etiqueta => switch (this) {
        ModoTema.sistema => 'Automático',
        ModoTema.claro => 'Claro',
        ModoTema.oscuro => 'Oscuro',
      };
}

class SeguridadPantalla {
  static const _canal = MethodChannel('ar.sole.miti/seguridad');

  static Future<void> fijarProtegida(bool activa) async {
    try {
      await _canal.invokeMethod('setSecure', {'activa': activa});
    } catch (_) {
      // Ignorar en plataformas sin el canal nativo (tests, web, etc.)
    }
  }
}

const _almacenAjustes = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

const _claveModoTema = 'miti_modo_tema';
const _claveFlagSecure = 'miti_flag_secure';

class GestorModoTema extends Notifier<ModoTema> {
  @override
  ModoTema build() {
    _cargar();
    return ModoTema.sistema;
  }

  Future<void> _cargar() async {
    final guardado = await _almacenAjustes.read(key: _claveModoTema);
    if (guardado == 'claro') {
      state = ModoTema.claro;
    } else if (guardado == 'oscuro') {
      state = ModoTema.oscuro;
    } else {
      state = ModoTema.sistema;
    }
  }

  Future<void> fijarModo(ModoTema nuevoModo) async {
    state = nuevoModo;
    await _almacenAjustes.write(key: _claveModoTema, value: nuevoModo.name);
  }
}

final modoTemaProvider = NotifierProvider<GestorModoTema, ModoTema>(GestorModoTema.new);

class GestorProteccionPantalla extends Notifier<bool> {
  @override
  bool build() {
    _cargar();
    return true; // Por defecto activado (§9 DEFINICION.md)
  }

  Future<void> _cargar() async {
    final guardado = await _almacenAjustes.read(key: _claveFlagSecure);
    final activa = guardado == null ? true : guardado == 'true';
    state = activa;
    await SeguridadPantalla.fijarProtegida(activa);
  }

  Future<void> fijarProteccion(bool activa) async {
    state = activa;
    await _almacenAjustes.write(key: _claveFlagSecure, value: activa.toString());
    await SeguridadPantalla.fijarProtegida(activa);
  }
}

final proteccionPantallaProvider =
    NotifierProvider<GestorProteccionPantalla, bool>(GestorProteccionPantalla.new);
