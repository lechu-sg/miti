import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Almacenamiento local SQLite para modo sin señal (§5 de DEFINICION.md).
///
/// Guarda una réplica de las campañas del usuario y la cola de salida (outbox)
/// para que la app funcione normalmente sin internet y sincronice al reconectar.
class BaseLocal {
  BaseLocal._();
  static final BaseLocal instancia = BaseLocal._();

  Database? _db;

  Future<Database> get db async {
    _db ??= await _abrir();
    return _db!;
  }

  Future<Database> _abrir() async {
    final rutaBases = await getDatabasesPath();
    final ruta = p.join(rutaBases, 'miti_local.db');

    return await openDatabase(
      ruta,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE campanas_cache (
            id TEXT PRIMARY KEY,
            nombre TEXT,
            tipo TEXT,
            estado TEXT,
            meta INTEGER,
            config TEXT,
            actualizado INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE numeros_cache (
            campana_id TEXT,
            numero INTEGER,
            estado TEXT,
            reservado_por TEXT,
            reserva_nota TEXT,
            venta_id TEXT,
            PRIMARY KEY (campana_id, numero)
          )
        ''');

        await db.execute('''
          CREATE TABLE productos_cache (
            id TEXT PRIMARY KEY,
            campana_id TEXT,
            nombre TEXT,
            precio INTEGER,
            activo INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE ventas_cache (
            id TEXT PRIMARY KEY,
            campana_id TEXT,
            vendedor_id TEXT,
            vendedor_nombre TEXT,
            comprador_nombre TEXT,
            comprador_telefono TEXT,
            importe INTEGER,
            estado TEXT,
            entrega TEXT,
            codigo_corto TEXT,
            items_json TEXT,
            creada TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE outbox (
            id TEXT PRIMARY KEY,
            campana_id TEXT,
            op TEXT,
            payload TEXT,
            creado INTEGER,
            estado TEXT,
            motivo TEXT,
            detalle TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE sync_estado (
            campana_id TEXT PRIMARY KEY,
            cursor INTEGER DEFAULT 0,
            ultima_sincro INTEGER
          )
        ''');
      },
    );
  }

  // --- Snapshot e Hidratación ---

  Future<void> guardarSnapshot(
    String campanaId,
    Map<String, dynamic> snapshot,
    int cursor,
  ) async {
    final d = await db;
    await d.transaction((txn) async {
      // 1. Guardar campaña
      final c = snapshot['campana'] as Map<String, dynamic>?;
      if (c != null) {
        await txn.insert(
          'campanas_cache',
          {
            'id': campanaId,
            'nombre': c['nombre'],
            'tipo': c['tipo'],
            'estado': c['estado'],
            'meta': c['meta'],
            'config': jsonEncode(c['config'] ?? {}),
            'actualizado': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 2. Guardar números (en lote para rapidez)
      final numeros = (snapshot['numeros'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (numeros.isNotEmpty) {
        final batch = txn.batch();
        for (final n in numeros) {
          batch.insert(
            'numeros_cache',
            {
              'campana_id': campanaId,
              'numero': n['numero'],
              'estado': n['estado'],
              'reservado_por': n['reservado_por'],
              'reserva_nota': n['reserva_nota'],
              'venta_id': n['venta_id'],
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // 3. Guardar productos
      final prods = (snapshot['productos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (prods.isNotEmpty) {
        final batch = txn.batch();
        for (final p in prods) {
          batch.insert(
            'productos_cache',
            {
              'id': p['id'],
              'campana_id': campanaId,
              'nombre': p['nombre'],
              'precio': p['precio'],
              'activo': (p['activo'] == true) ? 1 : 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // 4. Guardar ventas
      final ventas = (snapshot['ventas'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (ventas.isNotEmpty) {
        final batch = txn.batch();
        for (final v in ventas) {
          batch.insert(
            'ventas_cache',
            {
              'id': v['id'],
              'campana_id': campanaId,
              'vendedor_id': v['vendedor_id'],
              'vendedor_nombre': v['vendedor_nombre'],
              'comprador_nombre': v['comprador_nombre'],
              'comprador_telefono': v['comprador_telefono'],
              'importe': v['importe'],
              'estado': v['estado'],
              'entrega': v['entrega'],
              'codigo_corto': v['codigo_corto'],
              'items_json': jsonEncode(v['items_productos'] ?? v['numeros'] ?? []),
              'creada': v['creada'],
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }

      // 5. Cursor y última sincronización
      await txn.insert(
        'sync_estado',
        {
          'campana_id': campanaId,
          'cursor': cursor,
          'ultima_sincro': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<int> obtenerCursor(String campanaId) async {
    final d = await db;
    final res = await d.query(
      'sync_estado',
      columns: ['cursor'],
      where: 'campana_id = ?',
      whereArgs: [campanaId],
    );
    if (res.isEmpty) return 0;
    return (res.first['cursor'] as int?) ?? 0;
  }

  Future<void> actualizarCursor(String campanaId, int cursor) async {
    final d = await db;
    await d.insert(
      'sync_estado',
      {
        'campana_id': campanaId,
        'cursor': cursor,
        'ultima_sincro': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Aplicar cambios incrementales recibidos de pull ---

  Future<void> aplicarCambios(String campanaId, List<dynamic> cambios) async {
    final d = await db;
    await d.transaction((txn) async {
      for (final cambio in cambios) {
        if (cambio is! Map) continue;
        final tabla = cambio['tabla'] as String?;
        final op = cambio['op'] as String?;
        final datos = cambio['datos'] as Map<String, dynamic>? ?? {};

        if (tabla == 'ventas' && op == 'I') {
          // Nueva venta confirmada en el servidor
          final ventaId = datos['id'] as String;
          await txn.insert(
            'ventas_cache',
            {
              'id': ventaId,
              'campana_id': campanaId,
              'vendedor_id': datos['vendedor_id'],
              'vendedor_nombre': datos['vendedor_nombre'],
              'comprador_nombre': datos['comprador_nombre'],
              'importe': datos['importe'],
              'estado': 'confirmada',
              'entrega': datos['entrega'],
              'codigo_corto': datos['codigo_corto'],
              'items_json': jsonEncode(datos['items_productos'] ?? datos['numeros'] ?? []),
              'creada': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          // Si es rifa, marcar números vendidos
          final numeros = (datos['numeros'] as List?)?.cast<int>() ?? [];
          for (final n in numeros) {
            await txn.update(
              'numeros_cache',
              {'estado': 'vendido', 'venta_id': ventaId},
              where: 'campana_id = ? AND numero = ?',
              whereArgs: [campanaId, n],
            );
          }
        } else if (tabla == 'ventas' && op == 'U') {
          final ventaId = datos['id'] as String;
          final entrega = datos['entrega'] as String?;
          if (entrega != null) {
            await txn.update(
              'ventas_cache',
              {'entrega': entrega},
              where: 'id = ?',
              whereArgs: [ventaId],
            );
          }
        }
      }
    });
  }

  // --- Outbox (Cola de Operaciones Locales) ---

  Future<void> encolarOperacion(
    String campanaId,
    String id,
    String op,
    Map<String, dynamic> payload,
  ) async {
    final d = await db;
    await d.insert(
      'outbox',
      {
        'id': id,
        'campana_id': campanaId,
        'op': op,
        'payload': jsonEncode(payload),
        'creado': DateTime.now().millisecondsSinceEpoch,
        'estado': 'pendiente',
        'motivo': null,
        'detalle': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> obtenerOutbox(String campanaId) async {
    final d = await db;
    final res = await d.query(
      'outbox',
      where: 'campana_id = ?',
      whereArgs: [campanaId],
      orderBy: 'creado ASC',
    );
    return res.map((f) {
      return {
        'id': f['id'],
        'campana_id': f['campana_id'],
        'op': f['op'],
        'payload': jsonDecode(f['payload'] as String) as Map<String, dynamic>,
        'creado': f['creado'],
        'estado': f['estado'],
        'motivo': f['motivo'],
        'detalle': f['detalle'] != null ? jsonDecode(f['detalle'] as String) : null,
      };
    }).toList();
  }

  Future<int> contarPendientes(String campanaId) async {
    final d = await db;
    final res = await d.rawQuery(
      'SELECT COUNT(*) as cant FROM outbox WHERE campana_id = ? AND estado IN ("pendiente", "enviando")',
      [campanaId],
    );
    return (res.first['cant'] as int?) ?? 0;
  }

  Future<int> contarConflictos(String campanaId) async {
    final d = await db;
    final res = await d.rawQuery(
      'SELECT COUNT(*) as cant FROM outbox WHERE campana_id = ? AND estado = "conflicto"',
      [campanaId],
    );
    return (res.first['cant'] as int?) ?? 0;
  }

  Future<void> marcarOperacionOk(String id) async {
    final d = await db;
    await d.delete('outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> marcarOperacionConflicto(
    String id,
    String motivo,
    Map<String, dynamic>? detalle,
  ) async {
    final d = await db;
    await d.update(
      'outbox',
      {
        'estado': 'conflicto',
        'motivo': motivo,
        'detalle': detalle != null ? jsonEncode(detalle) : null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> resolverConflictoRifa(String id, int nuevoNumero) async {
    final d = await db;
    final filas = await d.query('outbox', where: 'id = ?', whereArgs: [id]);
    if (filas.isEmpty) return;

    final actual = jsonDecode(filas.first['payload'] as String) as Map<String, dynamic>;
    actual['numeros'] = [nuevoNumero];

    await d.update(
      'outbox',
      {
        'payload': jsonEncode(actual),
        'estado': 'pendiente',
        'motivo': null,
        'detalle': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> eliminarOperacion(String id) async {
    final d = await db;
    await d.delete('outbox', where: 'id = ?', whereArgs: [id]);
  }

  // --- Consultas a la réplica local para modo sin señal ---

  Future<List<Map<String, dynamic>>> obtenerNumeros(String campanaId) async {
    final d = await db;
    final res = await d.query(
      'numeros_cache',
      where: 'campana_id = ?',
      whereArgs: [campanaId],
      orderBy: 'numero ASC',
    );
    return res;
  }

  Future<List<Map<String, dynamic>>> obtenerProductos(String campanaId) async {
    final d = await db;
    final res = await d.query(
      'productos_cache',
      where: 'campana_id = ?',
      whereArgs: [campanaId],
      orderBy: 'nombre ASC',
    );
    return res.map((p) => {
      'id': p['id'],
      'nombre': p['nombre'],
      'precio': p['precio'],
      'activo': p['activo'] == 1,
    }).toList();
  }

  Future<List<Map<String, dynamic>>> obtenerVentas(String campanaId) async {
    final d = await db;
    final res = await d.query(
      'ventas_cache',
      where: 'campana_id = ?',
      whereArgs: [campanaId],
      orderBy: 'creada DESC',
    );
    return res.map((v) => {
      'id': v['id'],
      'vendedor_id': v['vendedor_id'],
      'vendedor_nombre': v['vendedor_nombre'],
      'comprador': {
        'nombre': v['comprador_nombre'],
        'telefono': v['comprador_telefono'],
      },
      'importe': v['importe'],
      'estado': v['estado'],
      'entrega': v['entrega'],
      'codigo_corto': v['codigo_corto'],
      'items': jsonDecode(v['items_json'] as String? ?? '[]'),
      'creada': v['creada'],
    }).toList();
  }

  Future<void> borrarBase() async {
    final d = await db;
    await d.delete('campanas_cache');
    await d.delete('numeros_cache');
    await d.delete('productos_cache');
    await d.delete('ventas_cache');
    await d.delete('outbox');
    await d.delete('sync_estado');
  }
}
