import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';

/// Notificaciones push (§5.7).
///
/// Todo esto sólo funciona si la app se compiló con el `google-services.json`
/// del proyecto de Firebase. Si no está, no pasa nada: la app anda igual y las
/// novedades se ven al abrirla.
class Push {
  static bool _listo = false;

  /// Arranca Firebase, pide permiso y deja el token registrado en el servidor.
  /// Se llama después de entrar, porque el token va atado al usuario.
  static Future<void> encender(ApiMiti api) async {
    if (_listo) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Push apagadas: falta la configuración de Firebase ($e)');
      return;
    }

    try {
      final mensajeria = FirebaseMessaging.instance;

      // En Android 13 y arriba hay que pedir permiso; si lo niegan, seguimos sin push.
      final permiso = await mensajeria.requestPermission();
      if (permiso.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Push: el usuario no dio permiso');
        return;
      }

      final token = await mensajeria.getToken();
      if (token != null) await _registrar(api, token);

      // El token se renueva solo cada tanto: hay que volver a avisarle al servidor.
      mensajeria.onTokenRefresh.listen((nuevo) => _registrar(api, nuevo));
      _listo = true;
    } catch (e) {
      debugPrint('Push: no se pudo registrar el dispositivo ($e)');
    }
  }

  static Future<void> _registrar(ApiMiti api, String token) async {
    try {
      await api.registrarTokenDispositivo(fcmToken: token);
    } catch (e) {
      // Sin señal o servidor caído: se reintenta la próxima vez que abra la app.
      debugPrint('Push: no se pudo avisar al servidor ($e)');
    }
  }
}
