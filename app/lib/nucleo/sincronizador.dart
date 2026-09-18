import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import 'api.dart';
import 'base_local.dart';

/// Estado de sincronización para la interfaz (§5 de DEFINICION.md).
class EstadoSincro {
  const EstadoSincro({
    this.sincronizando = false,
    this.pendientes = 0,
    this.conflictos = 0,
    this.ultimaSincro,
    this.error,
  });

  final bool sincronizando;
  final int pendientes;
  final int conflictos;
  final DateTime? ultimaSincro;
  final String? error;

  bool get tienePendientes => pendientes > 0;
  bool get tieneConflictos => conflictos > 0;

  EstadoSincro copiarCon({
    bool? sincronizando,
    int? pendientes,
    int? conflictos,
    DateTime? ultimaSincro,
    String? error,
  }) {
    return EstadoSincro(
      sincronizando: sincronizando ?? this.sincronizando,
      pendientes: pendientes ?? this.pendientes,
      conflictos: conflictos ?? this.conflictos,
      ultimaSincro: ultimaSincro ?? this.ultimaSincro,
      error: error,
    );
  }
}

/// Notificador que coordina la sincronización push/pull de una campaña.
class SincroNotifier extends StateNotifier<EstadoSincro> {
  SincroNotifier(this._campanaId, this._api, this._base)
      : super(const EstadoSincro()) {
    actualizarContadores();
  }

  final String _campanaId;
  final ApiMiti _api;
  final BaseLocal _base;

  Future<void> actualizarContadores() async {
    final p = await _base.contarPendientes(_campanaId);
    final c = await _base.contarConflictos(_campanaId);
    state = state.copiarCon(pendientes: p, conflictos: c);
  }

  /// Ejecuta el ciclo completo de sincronización:
  /// 1. Push de outbox pendiente.
  /// 2. Pull incremental (o snapshot si es la primera vez).
  Future<bool> sincronizar({bool forzarSnapshot = false}) async {
    if (state.sincronizando) return false;

    state = state.copiarCon(sincronizando: true, error: null);

    try {
      int cursor = await _base.obtenerCursor(_campanaId);

      // Si nunca descargamos snapshot o se fuerza:
      if (cursor == 0 || forzarSnapshot) {
        final pull0 = await _api.syncPull(_campanaId, snapshot: true);
        final snap = pull0['snapshot'] as Map<String, dynamic>?;
        final nuevoCursor = pull0['cursor'] as int? ?? 0;
        if (snap != null) {
          await _base.guardarSnapshot(_campanaId, snap, nuevoCursor);
          cursor = nuevoCursor;
        }
      }

      // 1. PUSH: Mandar operaciones pendientes en outbox
      final outbox = await _base.obtenerOutbox(_campanaId);
      final pendientes = outbox.where((op) => op['estado'] == 'pendiente').toList();

      if (pendientes.isNotEmpty) {
        final payloadOps = pendientes.map((op) {
          return {
            'id': op['id'],
            'op': op['op'],
            'payload': op['payload'],
            'creado': DateTime.fromMillisecondsSinceEpoch(op['creado'] as int).toIso8601String(),
          };
        }).toList();

        final resPush = await _api.syncPush(_campanaId, payloadOps);
        final resultados = (resPush['resultados'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        for (final r in resultados) {
          final opId = r['id'] as String;
          final est = r['estado'] as String;

          if (est == 'ok') {
            await _base.marcarOperacionOk(opId);
          } else if (est == 'conflicto') {
            await _base.marcarOperacionConflicto(
              opId,
              r['motivo'] as String? ?? 'conflicto',
              r['detalle'] as Map<String, dynamic>?,
            );
          } else {
            await _base.marcarOperacionConflicto(
              opId,
              r['motivo'] as String? ?? 'rechazado',
              null,
            );
          }
        }
      }

      // 2. PULL: Descargar cambios incrementales desde el cursor
      bool hayMas = true;
      while (hayMas) {
        final resPull = await _api.syncPull(_campanaId, desde: cursor);
        final cambios = resPull['cambios'] as List? ?? [];
        final nuevoCursor = resPull['cursor'] as int? ?? cursor;
        hayMas = resPull['hay_mas'] == true;

        if (cambios.isNotEmpty) {
          await _base.aplicarCambios(_campanaId, cambios);
        }
        await _base.actualizarCursor(_campanaId, nuevoCursor);
        cursor = nuevoCursor;
      }

      final p = await _base.contarPendientes(_campanaId);
      final c = await _base.contarConflictos(_campanaId);

      state = state.copiarCon(
        sincronizando: false,
        pendientes: p,
        conflictos: c,
        ultimaSincro: DateTime.now(),
      );
      return true;
    } catch (e) {
      final p = await _base.contarPendientes(_campanaId);
      final c = await _base.contarConflictos(_campanaId);
      state = state.copiarCon(
        sincronizando: false,
        pendientes: p,
        conflictos: c,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Resuelve un conflicto de rifa cambiando el número asignado
  Future<void> resolverConflictoRifa(String opId, int nuevoNumero) async {
    await _base.resolverConflictoRifa(opId, nuevoNumero);
    await actualizarContadores();
    await sincronizar();
  }

  /// Cancela una venta en conflicto
  Future<void> descartarOperacion(String opId) async {
    await _base.eliminarOperacion(opId);
    await actualizarContadores();
  }
}

final sincroProvider =
    StateNotifierProvider.family<SincroNotifier, EstadoSincro, String>(
  (ref, campanaId) {
    return SincroNotifier(
      campanaId,
      ref.watch(apiProvider),
      BaseLocal.instancia,
    );
  },
);
