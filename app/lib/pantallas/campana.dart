import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';
import 'billete.dart';
import 'catalogo_productos.dart';
import 'compartir_disponibles.dart';
import 'ganador.dart';
import 'grilla_numeros.dart';
import 'hoja_conflictos.dart';
import 'hoja_entrega.dart';
import 'hoja_gasto.dart';
import 'hoja_premios.dart';
import 'hoja_ranking.dart';
import 'liquidacion.dart';
import 'muro_avisos.dart';
import 'venta_productos.dart';
import '../nucleo/recordatorio_deuda.dart';
import '../nucleo/sincronizador.dart';

/// La campaña por dentro: cuánto se juntó, dónde está la plata y quiénes son.
class PantallaCampana extends ConsumerWidget {
  const PantallaCampana({super.key, required this.campanaId});

  final String campanaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.color;
    final t = context.texto;
    final datos = ref.watch(campanaProvider(campanaId));
    final recAsync = ref.watch(recaudacionProvider(campanaId));
    final ventasAsync = ref.watch(ventasProvider(campanaId));
    final movsAsync = ref.watch(movimientosProvider(campanaId));
    final gastosAsync = ref.watch(gastosProvider(campanaId));
    final avisosAsync = ref.watch(avisosProvider(campanaId));
    final sesionUsuario = ref.watch(sesionProvider).valueOrNull;
    final sincro = ref.watch(sincroProvider(campanaId));

    return Scaffold(
      body: SafeArea(
        child: datos.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => MitiVacio(
            titulo: 'No pudimos abrir la campaña',
            detalle: e is ErrorApi ? e.mensaje : 'Fijate si tenés señal.',
            accion: MitiBoton(
              texto: 'Volver',
              secundario: true,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          data: (campana) {
            final integrantes = (campana['integrantes'] as List).cast<Map<String, dynamic>>();
            final cajas = (campana['cajas'] as List).cast<Map<String, dynamic>>();
            final activos = integrantes.where((i) => i['estado'] == 'activo').toList();
            final invitados = integrantes.where((i) => i['estado'] == 'invitado').toList();
            final esAdmin = campana['mi_rol'] == 'admin';
            final meta = campana['meta'] as int?;
            final esRifa = campana['tipo'] == 'rifa';
            final config = (campana['config'] as Map).cast<String, dynamic>();
            final estaActiva = campana['estado'] == 'activa';
            final estaCerrada = campana['estado'] == 'cerrada' || campana['estado'] == 'sorteada';
            final estaLiquidada = campana['estado'] == 'liquidada';

            final principalCaja = cajas.where((c) => c['tipo'] == 'principal').firstOrNull;
            final aliasPrincipal = principalCaja?['alias'] as String?;

            final rec = recAsync.valueOrNull;
            final cobrado = rec?['cobrado'] as int? ?? 0;
            final vendido = rec?['vendido'] as int? ?? 0;
            final faltaCobrar = rec?['falta_cobrar'] as int? ?? 0;
            final totalGastos = rec?['gastos'] as int? ?? 0;
            final vendidosCount = rec?['numeros_vendidos'] as int? ?? 0;
            final totalesCount = rec?['numeros_totales'] as int? ?? 0;

            final progreso = (meta != null && meta > 0) ? (cobrado / meta) : null;

            // Movimientos pendientes que requieren aprobación del usuario actual (§3.7)
            final miId = sesionUsuario?['id'];
            final movs = movsAsync.valueOrNull ?? [];
            final pendientesDeAprobar = movs.where((m) {
              final est = m['estado'] as String?;
              if (est != 'pendiente') return false;
              final creador = m['creado_por'] as String?;
              if (creador == miId) return false; // Jamás auto-aprobar

              final req = m['requiere_aprobacion_de'] as String?;
              if (req != null) {
                return req == miId;
              }
              // Si requiere_aprobacion_de es null (gasto del admin), cualquier integrante activo puede aprobar
              return true;
            }).toList();

            final ventas = (ventasAsync.valueOrNull ?? []).cast<Map<String, dynamic>>();

            return RefreshIndicator(
              color: c.sello,
              onRefresh: () async {
                ref.invalidate(campanaProvider(campanaId));
                ref.invalidate(recaudacionProvider(campanaId));
                ref.invalidate(ventasProvider(campanaId));
                ref.invalidate(movimientosProvider(campanaId));
                ref.invalidate(gastosProvider(campanaId));
                ref.invalidate(avisosProvider(campanaId));
                ref.invalidate(rankingProvider(campanaId));
                if (esRifa) ref.invalidate(numerosProvider(campanaId));
                await ref.read(sincroProvider(campanaId).notifier).sincronizar();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.arrow_back, color: c.tinta),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: sincro.sincronizando ? 'Sincronizando...' : 'Sincronizar ahora',
                        onPressed: sincro.sincronizando
                            ? null
                            : () async {
                                final ok = await ref.read(sincroProvider(campanaId).notifier).sincronizar();
                                if (context.mounted) {
                                  if (ok) {
                                    mostrarAviso(context, 'Campaña sincronizada');
                                    ref.invalidate(campanaProvider(campanaId));
                                    ref.invalidate(recaudacionProvider(campanaId));
                                    ref.invalidate(ventasProvider(campanaId));
                                    ref.invalidate(movimientosProvider(campanaId));
                                    if (esRifa) ref.invalidate(numerosProvider(campanaId));
                                  } else {
                                    mostrarAviso(context, 'No se pudo sincronizar. Fijate si tenés señal.', error: true);
                                  }
                                }
                              },
                        icon: sincro.sincronizando
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: c.sello),
                              )
                            : Icon(
                                Icons.sync,
                                color: sincro.tieneConflictos ? c.selloTexto : c.tinta,
                              ),
                      ),
                      IconButton(
                        tooltip: 'Exportar balance (Excel / PDF)',
                        icon: Icon(Icons.file_download_outlined, color: c.tinta),
                        onPressed: () => _mostrarMenuExportar(context, ref, campana['nombre'] as String),
                      ),
                      if (esAdmin && campana['estado'] == 'borrador')
                        TextButton(
                          onPressed: () => _activar(context, ref),
                          child: Text('Activar', style: t.etiqueta.copyWith(color: c.selloTexto)),
                        ),
                      if (esAdmin && estaActiva)
                        TextButton(
                          onPressed: () => _cerrarCampana(context, ref, campana['nombre'] as String),
                          child: Text('Cerrar', style: t.etiqueta.copyWith(color: c.selloTexto)),
                        ),
                      if (estaCerrada)
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PantallaLiquidacion(
                                campanaId: campanaId,
                                campanaNombre: campana['nombre'] as String,
                                esAdmin: esAdmin,
                                estadoCampana: campana['estado'] as String,
                              ),
                            ),
                          ),
                          child: Text('Liquidar', style: t.etiqueta.copyWith(color: c.selloTexto)),
                        ),
                      if (estaLiquidada)
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PantallaLiquidacion(
                                campanaId: campanaId,
                                campanaNombre: campana['nombre'] as String,
                                esAdmin: esAdmin,
                                estadoCampana: 'liquidada',
                              ),
                            ),
                          ),
                          child: Text('Liquidación', style: t.etiqueta.copyWith(color: c.ok)),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${esRifa ? 'CAMPAÑA DE NÚMEROS' : 'VENTA DE PRODUCTOS'} · '
                          '${(campana['estado'] as String).toUpperCase()}',
                          style: t.sobrelinea.copyWith(color: c.tintaSuave),
                        ),
                        const SizedBox(height: 4),
                        Text(campana['nombre'] as String, style: t.titular.copyWith(color: c.tinta)),
                        if (esRifa && config.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Números ${config['desde']} al ${config['hasta']} · '
                            '${plata(config['precio'] as int)} cada uno',
                            style: t.cuerpo.copyWith(color: c.tintaSuave),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (sincro.tieneConflictos) ...[
                    MitiAviso(
                      cantidad: sincro.conflictos,
                      texto: 'Conflictos en ventas sin señal que resolver',
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => HojaConflictosSync(
                            campanaId: campanaId,
                            campanaNombre: campana['nombre'] as String,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                  ] else if (sincro.tienePendientes) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: c.mostaza.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.mostaza.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_upload_outlined, color: c.tinta, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${sincro.pendientes} venta(s) guardadas sin señal pendientes de subir',
                              style: t.pie.copyWith(color: c.tinta, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Muro de avisos: tarjeta destacada (§7.9)
                  Builder(
                    builder: (ctx) {
                      final avisos = avisosAsync.valueOrNull ?? [];
                      if (avisos.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TarjetaAvisoDestacado(
                            aviso: avisos.first,
                            totalAvisos: avisos.length,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PantallaMuroAvisos(
                                  campanaId: campanaId,
                                  campanaNombre: campana['nombre'] as String,
                                  esAdmin: esAdmin,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      );
                    },
                  ),

                  // Ticket de recaudación con datos reales
                  MitiTicket(
                    sobrelinea: 'Cobrado',
                    importe: plata(cobrado),
                    detalle: totalGastos > 0
                        ? 'Vendido ${plata(vendido)} · Gastos ${plata(totalGastos)} · Falta cobrar ${plata(faltaCobrar)}'
                        : 'Vendido ${plata(vendido)} · Falta cobrar ${plata(faltaCobrar)}',
                    progreso: progreso,
                    pie: meta == null ? 'Sin meta definida' : 'Meta ${plata(meta)}',
                    talonArriba: esRifa ? '$vendidosCount' : '${activos.length}',
                    talonAbajo: esRifa ? 'de $totalesCount nros' : (activos.length == 1 ? 'integrante' : 'integrantes'),
                  ),
                  const SizedBox(height: 14),

                  // Aviso y acceso a Liquidación según estado
                  if (estaLiquidada) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: c.ok.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.ok),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: c.ok, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('CAMPAÑA LIQUIDADA', style: t.etiqueta.copyWith(color: c.ok, fontWeight: FontWeight.bold)),
                                Text('Se fijaron las transferencias y el reparto entre integrantes.', style: t.pie.copyWith(color: c.tinta)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    MitiBoton(
                      texto: 'Ver reparto y transferencias',
                      icono: Icons.receipt_long_outlined,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PantallaLiquidacion(
                              campanaId: campanaId,
                              campanaNombre: campana['nombre'] as String,
                              esAdmin: esAdmin,
                              estadoCampana: 'liquidada',
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                  ] else if (estaCerrada) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: c.mostaza.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.mostaza.withValues(alpha: 0.8)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline, color: c.tinta, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('CAMPAÑA CERRADA', style: t.etiqueta.copyWith(color: c.tinta, fontWeight: FontWeight.bold)),
                                Text('No se pueden hacer más ventas. Lista para liquidar.', style: t.pie.copyWith(color: c.tintaSuave)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    MitiBoton(
                      texto: esAdmin ? 'Simular y liquidar campaña' : 'Ver simulación de liquidación',
                      icono: Icons.balance_outlined,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PantallaLiquidacion(
                              campanaId: campanaId,
                              campanaNombre: campana['nombre'] as String,
                              esAdmin: esAdmin,
                              estadoCampana: campana['estado'] as String,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Acciones según el tipo de campaña
                  if (esRifa && estaActiva) ...[
                    MitiBoton(
                      texto: 'Ver números y vender',
                      icono: Icons.grid_view_outlined,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PantallaGrillaNumeros(
                              campanaId: campanaId,
                              campanaNombre: campana['nombre'] as String,
                              precioUnitario: config['precio'] as int? ?? 0,
                              fechaSorteo: config['fecha_sorteo'] as String?,
                              esAdmin: esAdmin,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    MitiBoton(
                      texto: 'Generar imagen para redes',
                      icono: Icons.photo_camera_back_outlined,
                      secundario: true,
                      onTap: () async {
                        try {
                          final nums = await ref.read(numerosProvider(campanaId).future);
                          if (!context.mounted) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PantallaCompartirDisponibles(
                                campanaNombre: campana['nombre'] as String,
                                precioUnitario: config['precio'] as int? ?? 0,
                                fechaSorteo: config['fecha_sorteo'] as String?,
                                numeros: nums.cast<Map<String, dynamic>>(),
                              ),
                            ),
                          );
                        } catch (e) {
                          if (context.mounted) mostrarAviso(context, 'No se pudieron cargar los números', error: true);
                        }
                      },
                    ),
                    if (esAdmin && campana['estado'] != 'sorteada' && !estaLiquidada && campana['estado'] != 'archivada') ...[
                      const SizedBox(height: 10),
                      MitiBoton(
                        texto: 'Premios de la rifa (${(config['premios'] as List<dynamic>?)?.length ?? 1})',
                        icono: Icons.card_giftcard_outlined,
                        secundario: true,
                        onTap: () async {
                          final premiosList = (config['premios'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
                              [config['premio'] as String? ?? 'Primer Premio'];
                          final res = await mostrarHojaPremios(
                            context,
                            campanaId: campanaId,
                            premiosActuales: premiosList,
                          );
                          if (res != null) {
                            ref.invalidate(campanaProvider(campanaId));
                          }
                        },
                      ),
                    ],
                    if (estaActiva || estaCerrada) ...[
                      const SizedBox(height: 10),
                      MitiBoton(
                        texto: campana['estado'] == 'sorteada' ? 'Ver ganadores del sorteo' : 'Sorteo y ganadores',
                        icono: Icons.emoji_events_outlined,
                        secundario: true,
                        onTap: () async {
                          final premiosList = (config['premios'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
                              [config['premio'] as String? ?? 'Primer Premio'];
                          final res = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PantallaGanador(
                                campanaId: campanaId,
                                campanaNombre: campana['nombre'] as String,
                                esAdmin: esAdmin,
                                premios: premiosList,
                              ),
                            ),
                          );
                          if (res == true) {
                            ref.invalidate(campanaProvider(campanaId));
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 14),
                  ] else if (!esRifa) ...[
                    if (estaActiva) ...[
                      MitiBoton(
                        texto: 'Tomar pedido / Vender',
                        icono: Icons.shopping_bag_outlined,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PantallaVentaProductos(
                                campanaId: campanaId,
                                campanaNombre: campana['nombre'] as String,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    MitiBoton(
                      texto: 'Catálogo de productos',
                      icono: Icons.inventory_2_outlined,
                      secundario: true,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PantallaCatalogoProductos(
                              campanaId: campanaId,
                              campanaNombre: campana['nombre'] as String,
                              esAdmin: esAdmin,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (estaActiva || estaCerrada) ...[
                    MitiBoton(
                      texto: 'Registrar gasto',
                      icono: Icons.receipt_long_outlined,
                      secundario: true,
                      onTap: () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => HojaGasto(
                            campanaId: campanaId,
                            campanaNombre: campana['nombre'] as String,
                            cajas: cajas,
                            cajasRecaudacion: rec?['cajas'],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    MitiBoton(
                      texto: 'Exportar balance (Excel / PDF)',
                      icono: Icons.file_download_outlined,
                      secundario: true,
                      onTap: () => _mostrarMenuExportar(context, ref, campana['nombre'] as String),
                    ),
                    const SizedBox(height: 10),
                    MitiBoton(
                      texto: 'Ranking del equipo',
                      icono: Icons.military_tech_outlined,
                      secundario: true,
                      onTap: () => mostrarHojaRanking(
                        context,
                        campanaId: campanaId,
                        campanaNombre: campana['nombre'] as String,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Builder(
                      builder: (ctx) {
                        final cantAvisos = (avisosAsync.valueOrNull ?? []).length;
                        return MitiBoton(
                          texto: cantAvisos > 0 ? 'Muro de avisos ($cantAvisos)' : 'Muro de avisos',
                          icono: Icons.campaign_outlined,
                          secundario: true,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PantallaMuroAvisos(
                                campanaId: campanaId,
                                campanaNombre: campana['nombre'] as String,
                                esAdmin: esAdmin,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Aviso si hay cobros o gastos esperando aprobación del usuario (§3.7)
                  if (pendientesDeAprobar.isNotEmpty) ...[
                    MitiAviso(
                      cantidad: pendientesDeAprobar.length,
                      texto: pendientesDeAprobar.length == 1
                          ? 'movimiento pendiente de tu aprobación'
                          : 'movimientos pendientes de tu aprobación',
                      onTap: () => _mostrarAprobaciones(context, ref, pendientesDeAprobar),
                    ),
                    const SizedBox(height: 14),
                  ],

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('DÓNDE ESTÁ LA PLATA', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                      const Spacer(),
                      if (estaActiva || estaCerrada)
                        TextButton.icon(
                          onPressed: () async {
                            final res = await showModalBottomSheet<bool>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => HojaEntrega(
                                campanaId: campanaId,
                                campanaNombre: campana['nombre'] as String,
                                cajas: cajas,
                                cajasRecaudacion: rec?['cajas'],
                              ),
                            );
                            if (res == true && context.mounted) {
                              ref.invalidate(campanaProvider(campanaId));
                              ref.invalidate(recaudacionProvider(campanaId));
                              ref.invalidate(movimientosProvider(campanaId));
                              mostrarAviso(context, 'Entrega registrada. El receptor debe confirmarla.');
                            }
                          },
                          icon: Icon(Icons.swap_horiz_rounded, size: 18, color: c.selloTexto),
                          label: Text('Pasar dinero', style: t.etiqueta.copyWith(color: c.selloTexto)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  MitiTroquel(color: c.tinta, grosor: 1.5),
                  ..._cajasConSaldos(context, cajas, rec?['cajas']),

                  // Desglose de productos vendidos (en campañas de productos)
                  if (!esRifa) ...[
                    Builder(
                      builder: (ctx) {
                        final desglose = (rec?['productos_desglose'] as List?)
                                ?.whereType<Map>()
                                .map((m) => m.cast<String, dynamic>())
                                .toList() ??
                            [];
                        if (desglose.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 26),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('PRODUCTOS VENDIDOS', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                                Text('${desglose.length}', style: t.etiqueta.copyWith(color: c.tintaSuave)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            MitiTroquel(color: c.tinta, grosor: 1.5),
                            for (final item in desglose) _FilaDesgloseProducto(item: item),
                          ],
                        );
                      },
                    ),
                  ],

                  // Cobros pendientes / Recordatorios (§7.4)
                  if (faltaCobrar > 0) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: c.sello.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.sello.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.hourglass_top_outlined, color: c.selloTexto, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'COBROS PENDIENTES: ${plata(faltaCobrar)}',
                                  style: t.etiqueta.copyWith(color: c.selloTexto, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Tocá "RECORDAR" en las ventas adeudadas para enviar el mensaje por WhatsApp.',
                                  style: t.pie.copyWith(color: c.tintaSuave),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Ventas recientes
                  if (ventas.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          esRifa ? 'VENTAS REGISTRADAS' : 'PEDIDOS Y VENTAS',
                          style: t.sobrelinea.copyWith(color: c.tintaSuave),
                        ),
                        Text('${ventas.length}', style: t.etiqueta.copyWith(color: c.tintaSuave)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    MitiTroquel(color: c.tinta, grosor: 1.5),
                    for (final v in ventas)
                      _FilaVenta(
                        venta: v,
                        campanaId: campanaId,
                        campanaNombre: campana['nombre'] as String,
                        esRifa: esRifa,
                        alias: aliasPrincipal,
                      ),
                  ],

                  // Gastos de campaña (§3.7)
                  Builder(
                    builder: (ctx) {
                      final gastos = (gastosAsync.valueOrNull ?? []).cast<Map<String, dynamic>>();
                      if (gastos.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 26),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('GASTOS DE CAMPAÑA', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                              Text('${gastos.length}', style: t.etiqueta.copyWith(color: c.tintaSuave)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          MitiTroquel(color: c.tinta, grosor: 1.5),
                          for (final g in gastos)
                            _FilaGasto(
                              gasto: g,
                              campanaId: campanaId,
                              miId: miId,
                            ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 26),
                  Row(
                    children: [
                      Text('EL GRUPO', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                      const Spacer(),
                      if (esAdmin)
                        TextButton.icon(
                          onPressed: () => _invitar(context, ref),
                          icon: Icon(Icons.person_add_alt, size: 18, color: c.selloTexto),
                          label: Text('Invitar', style: t.etiqueta.copyWith(color: c.selloTexto)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final i in [...activos, ...invitados]) _FilaIntegrante(integrante: i),
                  if (esAdmin && estaActiva) ...[
                    const SizedBox(height: 28),
                    MitiBoton(
                      texto: 'Cerrar campaña para liquidar',
                      icono: Icons.lock_clock_outlined,
                      secundario: true,
                      onTap: () => _cerrarCampana(context, ref, campana['nombre'] as String),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _cajasConSaldos(
    BuildContext context,
    List<Map<String, dynamic>> cajas,
    dynamic cajasRecaudacion,
  ) {
    final c = context.color;
    final t = context.texto;
    final filas = <Widget>[];

    final listaRec = (cajasRecaudacion is List ? cajasRecaudacion : [])
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();

    final principal = cajas.where((x) => x['tipo'] == 'principal').firstOrNull;
    if (principal != null) {
      final recP = listaRec.where((x) => x['caja_id']?.toString() == principal['id']?.toString()).firstOrNull;
      final conf = (recP?['confirmado'] as num?)?.toInt() ?? 0;
      final pend = (recP?['pendiente'] as num?)?.toInt() ?? 0;

      filas.add(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.troquel))),
          child: Row(
            children: [
              MitiIniciales(iniciales(principal['titular'] as String? ?? '')),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cuenta principal · ${principal['titular']}',
                        style: t.cuerpo.copyWith(fontWeight: FontWeight.w600, color: c.tinta)),
                    Text(
                      pend > 0
                          ? 'Confirmado ${plata(conf)} · Pendiente ${plata(pend)}'
                          : ((principal['alias'] as String?)?.isNotEmpty == true
                              ? 'Alias ${principal['alias']}'
                              : 'Sin alias cargado'),
                      style: t.pie.copyWith(color: pend > 0 ? c.selloTexto : c.tintaSuave),
                    ),
                  ],
                ),
              ),
              Text(plata(conf), style: t.cifra.copyWith(color: c.tinta)),
            ],
          ),
        ),
      );
    }

    final titularesVistos = <String>{};
    for (final caja in cajas.where((x) => x['tipo'] != 'principal')) {
      final titularId = caja['titular_id'] as String? ?? '';
      if (titularesVistos.contains(titularId)) continue;
      titularesVistos.add(titularId);

      final cajasUsuario = cajas.where((x) => (x['titular_id'] as String? ?? '') == titularId && x['tipo'] != 'principal');
      int totalConf = 0;
      int billete = 0;
      int efectivo = 0;

      for (final cu in cajasUsuario) {
        final recU = listaRec.where((x) => x['caja_id']?.toString() == cu['id']?.toString()).firstOrNull;
        final conf = (recU?['confirmado'] as num?)?.toInt() ?? 0;
        totalConf += conf;
        if (cu['tipo'] == 'billetera') billete = conf;
        if (cu['tipo'] == 'efectivo') efectivo = conf;
      }

      filas.add(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.troquel))),
          child: Row(
            children: [
              MitiIniciales(iniciales(caja['titular'] as String)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(caja['titular'] as String,
                        style: t.cuerpo.copyWith(fontWeight: FontWeight.w600, color: c.tinta)),
                    Text('Billetera ${plata(billete)} · efectivo ${plata(efectivo)}',
                        style: t.pie.copyWith(color: c.tintaSuave)),
                  ],
                ),
              ),
              Text(plata(totalConf), style: t.cifra.copyWith(color: c.tinta)),
            ],
          ),
        ),
      );
    }

    return filas;
  }

  void _mostrarAprobaciones(
    BuildContext context,
    WidgetRef ref,
    List<dynamic> pendientes,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final c = context.color;
        final t = context.texto;

        return MitiHoja(
          titulo: 'MOVIMIENTOS A EVALUAR',
          subtitulo: 'PENDIENTES DE TU APROBACIÓN',
          child: Column(
            children: [
              for (final mov in pendientes) ...[
                Builder(
                  builder: (ctx) {
                    final tipo = mov['tipo'] as String? ?? '';
                    final esGasto = tipo == 'gasto' || tipo.startsWith('gasto_');
                    final motivo = mov['motivo'] as String?;
                    final importe = mov['importe'] as int? ?? 0;
                    final origenCaja = mov['caja_origen'] != null;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.papelHundido,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          plata(importe),
                                          style: t.importe.copyWith(color: c.tinta, fontSize: 22),
                                        ),
                                        const SizedBox(width: 8),
                                        Builder(
                                          builder: (_) {
                                            String etiqueta;
                                            Color colorFondo;
                                            Color colorTexto;
                                            if (tipo == 'entrega') {
                                              etiqueta = 'ENTREGA / PASE';
                                              colorFondo = c.ok.withValues(alpha: 0.15);
                                              colorTexto = c.ok;
                                            } else if (tipo == 'anulacion') {
                                              etiqueta = 'ANULACIÓN';
                                              colorFondo = c.sello.withValues(alpha: 0.15);
                                              colorTexto = c.selloTexto;
                                            } else if (esGasto) {
                                              etiqueta = origenCaja ? 'GASTO DE CAJA' : 'GASTO BOLSILLO';
                                              colorFondo = c.sello.withValues(alpha: 0.15);
                                              colorTexto = c.selloTexto;
                                            } else {
                                              etiqueta = 'COBRO EN CUENTA';
                                              colorFondo = c.mostaza.withValues(alpha: 0.2);
                                              colorTexto = c.tinta;
                                            }

                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: colorFondo,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                etiqueta,
                                                style: t.pie.copyWith(
                                                  color: colorTexto,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      tipo == 'entrega'
                                          ? (motivo != null && motivo.isNotEmpty ? motivo : 'Entrega de dinero entre cajas')
                                          : tipo == 'anulacion'
                                              ? (motivo != null && motivo.isNotEmpty ? 'Anulación: $motivo' : 'Solicitud de anulación de venta')
                                              : esGasto
                                                  ? (motivo != null && motivo.isNotEmpty ? motivo : 'Gasto a verificar')
                                                  : 'Transferencia a cuenta principal a verificar',
                                      style: t.cuerpo.copyWith(color: c.tinta, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () async {
                                  final motivoRechazo = await _pedirMotivoRechazo(context);
                                  if (motivoRechazo == null) return;
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                  try {
                                    await ref.read(apiProvider).rechazarMovimiento(
                                          campanaId,
                                          mov['id'] as String,
                                          motivoRechazo,
                                        );
                                    ref.invalidate(campanaProvider(campanaId));
                                    ref.invalidate(recaudacionProvider(campanaId));
                                    ref.invalidate(movimientosProvider(campanaId));
                                    ref.invalidate(gastosProvider(campanaId));
                                    ref.invalidate(ventasProvider(campanaId));
                                    ref.invalidate(numerosProvider(campanaId));
                                    if (context.mounted) mostrarAviso(context, 'Movimiento rechazado');
                                  } on ErrorApi catch (e) {
                                    if (context.mounted) mostrarAviso(context, e.mensaje, error: true);
                                  }
                                },
                                child: Text('Rechazar', style: t.etiqueta.copyWith(color: c.selloTexto)),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  try {
                                    await ref.read(apiProvider).confirmarMovimiento(
                                          campanaId,
                                          mov['id'] as String,
                                        );
                                    ref.invalidate(campanaProvider(campanaId));
                                    ref.invalidate(recaudacionProvider(campanaId));
                                    ref.invalidate(movimientosProvider(campanaId));
                                    ref.invalidate(gastosProvider(campanaId));
                                    ref.invalidate(ventasProvider(campanaId));
                                    ref.invalidate(numerosProvider(campanaId));
                                    if (context.mounted) mostrarAviso(context, 'Movimiento aprobado');
                                  } on ErrorApi catch (e) {
                                    if (context.mounted) mostrarAviso(context, e.mensaje, error: true);
                                  }
                                },
                                child: Text('Aprobar',
                                    style: t.etiqueta.copyWith(color: c.ok, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<String?> _pedirMotivoRechazo(BuildContext context) async {
    final c = context.color;
    final t = context.texto;
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.hoja,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: Text('Rechazar movimiento', style: t.seccion.copyWith(color: c.tinta)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ingresá el motivo del rechazo para que quede registrado:',
                style: t.pie.copyWith(color: c.tintaSuave)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: t.cuerpo.copyWith(color: c.tinta),
              decoration: InputDecoration(
                hintText: 'Ej: No coincide / No autorizado',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text('Cancelar', style: t.etiqueta.copyWith(color: c.tintaSuave)),
          ),
          TextButton(
            onPressed: () {
              final val = ctrl.text.trim();
              Navigator.of(ctx).pop(val.isNotEmpty ? val : 'Rechazado por integrante');
            },
            child: Text('Rechazar', style: t.etiqueta.copyWith(color: c.selloTexto, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _activar(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(apiProvider).cambiarEstado(campanaId, 'activa');
      ref.invalidate(campanaProvider(campanaId));
      ref.invalidate(campanasProvider);
      ref.invalidate(numerosProvider(campanaId));
      if (context.mounted) mostrarAviso(context, 'La campaña quedó activa');
    } on ErrorApi catch (e) {
      if (context.mounted) mostrarAviso(context, e.mensaje, error: true);
    }
  }

  Future<void> _cerrarCampana(BuildContext context, WidgetRef ref, String campanaNombre) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.color.hoja,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: Text('¿Cerrar la campaña?', style: context.texto.seccion),
        content: Text(
          'Al cerrar la campaña no se podrán registrar más ventas ni reservas.\n\n'
          'Podrás simular la liquidación en Base Cobrada o Base Vendida y equilibrar los saldos del grupo.',
          style: context.texto.cuerpo,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar', style: TextStyle(color: context.color.tintaSuave)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.color.sello,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cerrar campaña'),
          ),
        ],
      ),
    );

    if (confirma != true || !context.mounted) return;

    try {
      await ref.read(apiProvider).cambiarEstado(campanaId, 'cerrada');
      ref.invalidate(campanaProvider(campanaId));
      ref.invalidate(campanasProvider);
      if (context.mounted) {
        mostrarAviso(context, 'Campaña cerrada para ventas');
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PantallaLiquidacion(
              campanaId: campanaId,
              campanaNombre: campanaNombre,
              esAdmin: true,
              estadoCampana: 'cerrada',
            ),
          ),
        );
      }
    } on ErrorApi catch (e) {
      if (context.mounted) mostrarAviso(context, e.mensaje, error: true);
    } catch (_) {
      if (context.mounted) mostrarAviso(context, 'Fijate si tenés señal.', error: true);
    }
  }

  Future<void> _invitar(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController();
    final invitado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HojaInvitar(email: email, campanaId: campanaId),
    );
    email.dispose();
    if (invitado == true) {
      ref.invalidate(campanaProvider(campanaId));
    }
  }

  Future<void> _exportar(BuildContext context, WidgetRef ref, String campanaNombre, String tipo) async {
    mostrarAviso(context, 'Preparando archivo $tipo...');
    try {
      final api = ref.read(apiProvider);
      final bytes = tipo == 'Excel'
          ? await api.descargarExcel(campanaId)
          : await api.descargarPdf(campanaId);

      final extension = tipo == 'Excel' ? 'xlsx' : 'pdf';
      final mime = tipo == 'Excel'
          ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
          : 'application/pdf';

      final tempDir = await getTemporaryDirectory();
      final slug = campanaNombre.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final archivo = File('${tempDir.path}/miti_${slug}_balance.$extension');
      await archivo.writeAsBytes(bytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(archivo.path, mimeType: mime)],
          text: 'Balance de campaña: $campanaNombre ($tipo)',
        ),
      );
    } on ErrorApi catch (e) {
      if (context.mounted) mostrarAviso(context, e.mensaje, error: true);
    } catch (e) {
      if (context.mounted) mostrarAviso(context, 'No se pudo generar el archivo para exportar', error: true);
    }
  }

  void _mostrarMenuExportar(BuildContext context, WidgetRef ref, String campanaNombre) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.color.hoja,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('EXPORTAR BALANCE DE CAMPAÑA', style: ctx.texto.seccion),
              const SizedBox(height: 6),
              Text(
                'Descargá o compartí la rendición completa con todas las cajas, cobros, gastos y liquidación.',
                style: ctx.texto.pie.copyWith(color: ctx.color.tintaSuave),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D6F42).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.table_chart_outlined, color: Color(0xFF1D6F42)),
                ),
                title: Text('Planilla Excel (.xlsx)', style: ctx.texto.cuerpo.copyWith(fontWeight: FontWeight.w700)),
                subtitle: Text('Balance, Cajas, Ventas, Gastos y Reparto detallados', style: ctx.texto.pie),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _exportar(context, ref, campanaNombre, 'Excel');
                },
              ),
              const Divider(),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ctx.color.sello.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.picture_as_pdf_outlined, color: ctx.color.sello),
                ),
                title: Text('Documento PDF (.pdf)', style: ctx.texto.cuerpo.copyWith(fontWeight: FontWeight.w700)),
                subtitle: Text('Informe formal listo para imprimir con firmas de conformidad', style: ctx.texto.pie),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _exportar(context, ref, campanaNombre, 'PDF');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilaVenta extends ConsumerWidget {
  const _FilaVenta({
    required this.venta,
    required this.campanaId,
    required this.campanaNombre,
    required this.esRifa,
    this.alias,
  });

  final Map<String, dynamic> venta;
  final String campanaId;
  final String campanaNombre;
  final bool esRifa;
  final String? alias;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.color;
    final t = context.texto;

    final comprador = venta['comprador'] as Map<String, dynamic>;
    final compradorNombre = comprador['nombre'] as String;
    final compradorTelefono = comprador['telefono'] as String?;
    final vendedorNombre = venta['vendedor_nombre'] as String;
    final numeros = (venta['numeros'] as List).cast<int>();
    final itemsProductos = (venta['items_productos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final importe = venta['importe'] as int;
    final codigoCorto = venta['codigo_corto'] as String;
    final saldoAdeudado = venta['saldo_adeudado'] as int? ?? 0;
    final estaPagado = saldoAdeudado == 0;
    final entrega = venta['entrega'] as String? ?? 'pedido';
    final esEntregado = entrega == 'entregado';

    final estado = venta['estado'] as String? ?? 'confirmada';
    final esAnulada = estado == 'anulada';

    final numsStr = numeros.map((n) => n.toString().padLeft(2, '0')).join(', ');
    final resumenProd = itemsProductos.map((p) => '${p['cantidad']}x ${p['nombre']}').join(', ');
    final detalleTexto = esAnulada
        ? 'VENTA ANULADA · Por $vendedorNombre'
        : (esRifa
            ? 'Nros: $numsStr · Por $vendedorNombre'
            : '${resumenProd.isNotEmpty ? resumenProd : 'Productos'} · Por $vendedorNombre');

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PantallaBillete(
              campanaNombre: campanaNombre,
              numeros: numeros,
              itemsProductos: itemsProductos.isNotEmpty ? itemsProductos : null,
              entrega: entrega,
              importe: importe,
              compradorNombre: compradorNombre,
              compradorTelefono: compradorTelefono,
              vendedorNombre: vendedorNombre,
              codigoCorto: codigoCorto,
              estaPagado: estaPagado,
              esAnulada: esAnulada,
              onSolicitarAnulacion: (motivo) async {
                try {
                  await ref.read(apiProvider).anularVenta(
                        campanaId,
                        venta['id'] as String,
                        motivo: motivo,
                      );
                  ref.invalidate(campanaProvider(campanaId));
                  ref.invalidate(ventasProvider(campanaId));
                  ref.invalidate(recaudacionProvider(campanaId));
                  ref.invalidate(movimientosProvider(campanaId));
                  if (esRifa) ref.invalidate(numerosProvider(campanaId));
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    mostrarAviso(context, 'Solicitud de anulación enviada.');
                  }
                } catch (e) {
                  if (context.mounted) {
                    mostrarAviso(context, 'No se pudo anular la venta.', error: true);
                  }
                }
              },
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.troquel))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          compradorNombre,
                          style: t.cuerpo.copyWith(
                            fontWeight: FontWeight.w700,
                            color: esAnulada ? c.tintaSuave : c.tinta,
                            decoration: esAnulada ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (esAnulada)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.sello.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'ANULADA',
                            style: t.pie.copyWith(
                              color: c.selloTexto,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        )
                      else ...[
                        // Chip de Pago
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: estaPagado ? c.ok.withValues(alpha: 0.15) : c.sello.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            estaPagado ? 'PAGADO' : 'A PAGAR',
                            style: t.pie.copyWith(
                              color: estaPagado ? c.ok : c.selloTexto,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        if (!estaPagado) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => enviarRecordatorioDeuda(
                              context,
                              venta: venta,
                              campanaNombre: campanaNombre,
                              alias: alias,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF25D366)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.send_rounded, size: 9, color: Color(0xFF1E7E34)),
                                  const SizedBox(width: 3),
                                  Text(
                                    'RECORDAR',
                                    style: t.pie.copyWith(
                                      color: const Color(0xFF1E7E34),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        // Chip de Entrega (en productos)
                        if (!esRifa) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () async {
                              try {
                                final api = ref.read(apiProvider);
                                final nuevo = esEntregado ? 'pedido' : 'entregado';
                                await api.actualizarEntrega(campanaId, venta['id'] as String, nuevo);
                                ref.invalidate(ventasProvider(campanaId));
                                if (context.mounted) {
                                  mostrarAviso(
                                    context,
                                    nuevo == 'entregado'
                                        ? 'Pedido marcado como entregado'
                                        : 'Pedido marcado como pendiente',
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  mostrarAviso(context, 'No se pudo actualizar la entrega', error: true);
                                }
                              }
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: esEntregado
                                    ? c.ok.withValues(alpha: 0.15)
                                    : c.mostaza.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: esEntregado ? c.ok : c.tinta.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    esEntregado ? Icons.check : Icons.inventory_2_outlined,
                                    size: 10,
                                    color: esEntregado ? c.ok : c.tinta,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    esEntregado ? 'ENTREGADO' : 'PEDIDO',
                                    style: t.pie.copyWith(
                                      color: esEntregado ? c.ok : c.tinta,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(detalleTexto, style: t.pie.copyWith(color: c.tintaSuave)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  plata(importe),
                  style: t.cifra.copyWith(
                    color: esAnulada ? c.tintaSuave : c.tinta,
                    decoration: esAnulada ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text('#$codigoCorto', style: t.pie.copyWith(color: c.tintaSuave, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaDesgloseProducto extends StatelessWidget {
  const _FilaDesgloseProducto({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final nombre = item['nombre'] as String? ?? '';
    final cant = ((item['cantidad'] ?? item['cantidad_vendida'] ?? 0) as num).toInt();
    final recaudado = ((item['total'] ?? item['recaudado'] ?? 0) as num).toInt();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.troquel))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre, style: t.cuerpo.copyWith(fontWeight: FontWeight.w600, color: c.tinta)),
                Text('$cant ${cant == 1 ? 'unidad vendida' : 'unidades vendidas'}',
                    style: t.pie.copyWith(color: c.tintaSuave)),
              ],
            ),
          ),
          Text(plata(recaudado), style: t.cifra.copyWith(color: c.tinta, fontSize: 18.0)),
        ],
      ),
    );
  }
}

class _FilaIntegrante extends StatelessWidget {
  const _FilaIntegrante({required this.integrante});

  final Map<String, dynamic> integrante;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final esInvitado = integrante['estado'] == 'invitado';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          Opacity(opacity: esInvitado ? 0.55 : 1, child: MitiIniciales(iniciales(integrante['nombre'] as String))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(integrante['nombre'] as String,
                style: t.cuerpo.copyWith(
                  fontWeight: FontWeight.w600,
                  color: esInvitado ? c.tintaSuave : c.tinta,
                )),
          ),
          if (integrante['rol'] == 'admin')
            Text('ADMIN', style: t.sobrelinea.copyWith(color: c.tintaSuave, fontSize: 11)),
          if (esInvitado)
            Text('INVITADO', style: t.sobrelinea.copyWith(color: c.selloTexto, fontSize: 11)),
        ],
      ),
    );
  }
}

class _HojaInvitar extends ConsumerStatefulWidget {
  const _HojaInvitar({required this.email, required this.campanaId});

  final TextEditingController email;
  final String campanaId;

  @override
  ConsumerState<_HojaInvitar> createState() => _HojaInvitarState();
}

class _HojaInvitarState extends ConsumerState<_HojaInvitar> {
  bool _trabajando = false;
  String? _error;

  Future<void> _invitar() async {
    final email = widget.email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Escribí el mail completo de la persona');
      return;
    }
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      final r = await ref.read(apiProvider).invitar(widget.campanaId, email);
      if (mounted) {
        Navigator.of(context).pop(true);
        mostrarAviso(context, 'Invitaste a ${r['nombre']}');
      }
    } on ErrorApi catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos conectarnos. ¿Tenés señal?');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        decoration: BoxDecoration(
          color: c.hoja,
          border: Border(top: BorderSide(color: c.tinta, width: 2)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('INVITAR A LA CAMPAÑA', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
            const SizedBox(height: 10),
            AutofillGroup(
              child: TextField(
                controller: widget.email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: true,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.send,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _invitar(),
                decoration: const InputDecoration(
                  labelText: 'Mail de la persona',
                  hintText: 'nombre@mail.com',
                  prefixIcon: Icon(Icons.alternate_email, size: 20),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: c.sello, width: 2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 18, color: c.selloTexto),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: t.cuerpo.copyWith(color: c.selloTexto, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text('Tiene que tener cuenta en Miti. Le va a aparecer la invitación al entrar.',
                style: t.pie.copyWith(color: c.tintaSuave)),
            const SizedBox(height: 18),
            MitiBoton(texto: 'Invitar', cargando: _trabajando, onTap: _invitar),
          ],
        ),
      ),
    );
  }
}

class _FilaGasto extends StatelessWidget {
  const _FilaGasto({
    required this.gasto,
    required this.campanaId,
    this.miId,
  });

  final Map<String, dynamic> gasto;
  final String campanaId;
  final String? miId;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    final descripcion = gasto['descripcion'] as String? ?? 'Gasto';
    final importe = gasto['importe'] as int? ?? 0;
    final origen = gasto['origen'] as String? ?? 'bolsillo';
    final estado = gasto['estado'] as String? ?? 'pendiente';
    final creadoPorNombre = gasto['creado_por_nombre'] as String? ?? 'Integrante';
    final cajaNombre = gasto['caja_nombre'] as String?;
    final motivoRechazo = gasto['motivo_rechazo'] as String?;

    final esConfirmado = estado == 'confirmado';
    final esRechazado = estado == 'rechazado';

    Color colorEstado;
    String textoEstado;
    if (esConfirmado) {
      colorEstado = c.ok;
      textoEstado = 'APROBADO';
    } else if (esRechazado) {
      colorEstado = c.selloTexto;
      textoEstado = 'RECHAZADO';
    } else {
      colorEstado = c.mostaza;
      textoEstado = 'PENDIENTE';
    }

    final detalleOrigen = origen == 'bolsillo'
        ? 'Puso de su bolsillo · Por $creadoPorNombre'
        : 'De ${cajaNombre ?? 'caja'} · Por $creadoPorNombre';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.troquel))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        descripcion,
                        style: t.cuerpo.copyWith(fontWeight: FontWeight.w700, color: c.tinta),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorEstado.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        textoEstado,
                        style: t.pie.copyWith(
                          color: colorEstado,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(detalleOrigen, style: t.pie.copyWith(color: c.tintaSuave)),
                if (esRechazado && motivoRechazo != null && motivoRechazo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Motivo: $motivoRechazo',
                    style: t.pie.copyWith(color: c.selloTexto, fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            plata(importe),
            style: t.importe.copyWith(
              color: c.tinta,
              fontSize: 18.0,
              decoration: esRechazado ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaAvisoDestacado extends StatelessWidget {
  const _TarjetaAvisoDestacado({
    required this.aviso,
    required this.totalAvisos,
    required this.onTap,
  });

  final Map<String, dynamic> aviso;
  final int totalAvisos;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final mensaje = aviso['mensaje'] as String? ?? '';
    final autor = aviso['autor_nombre'] as String? ?? 'Administración';
    final fijado = aviso['fijado'] as bool? ?? false;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: fijado ? c.mostaza.withValues(alpha: 0.12) : c.papelHundido,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: fijado ? c.mostaza : c.troquel,
            width: fijado ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  fijado ? Icons.push_pin : Icons.campaign_outlined,
                  size: 16,
                  color: fijado ? c.mostaza : c.selloTexto,
                ),
                const SizedBox(width: 6),
                Text(
                  fijado ? 'AVISO FIJADO · $autor' : 'AVISO RECIENTE · $autor',
                  style: t.pie.copyWith(
                    fontWeight: FontWeight.w800,
                    color: fijado ? c.tinta : c.selloTexto,
                    fontSize: 10,
                  ),
                ),
                const Spacer(),
                Text(
                  'Ver muro ($totalAvisos) →',
                  style: t.pie.copyWith(
                    fontWeight: FontWeight.bold,
                    color: c.tinta,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              mensaje,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.cuerpo.copyWith(color: c.tinta, fontSize: 13, height: 1.25),
            ),
          ],
        ),
      ),
    );
  }
}

