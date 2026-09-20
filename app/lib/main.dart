import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'estado/ajustes.dart';
import 'estado/sesion.dart';
import 'nucleo/tema.dart';
import 'pantallas/campanas.dart';
import 'pantallas/ingreso.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_AR');
  runApp(const ProviderScope(child: AppMiti()));
}

class AppMiti extends ConsumerWidget {
  const AppMiti({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modo = ref.watch(modoTemaProvider);
    // Activa la protección de pantalla configurada
    ref.watch(proteccionPantallaProvider);

    final themeMode = switch (modo) {
      ModoTema.sistema => ThemeMode.system,
      ModoTema.claro => ThemeMode.light,
      ModoTema.oscuro => ThemeMode.dark,
    };

    return MaterialApp(
      title: 'Miti',
      debugShowCheckedModeBanner: false,
      theme: construirTema(MitiColores.claro, Brightness.light),
      darkTheme: construirTema(MitiColores.oscuro, Brightness.dark),
      themeMode: themeMode,
      home: const _Puerta(),
    );
  }
}

/// Decide qué mostrar según si hay alguien con sesión abierta.
class _Puerta extends ConsumerWidget {
  const _Puerta();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);
    final oscuro = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: oscuro ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: sesion.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, __) => const PantallaIngreso(),
        data: (perfil) => perfil == null ? const PantallaIngreso() : const PantallaCampanas(),
      ),
    );
  }
}
