import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';
import 'billete.dart';
import 'catalogo_productos.dart';
import 'compartir_disponibles.dart';
import 'grilla_numeros.dart';
import 'venta_productos.dart';

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
    final sesionUsuario = ref.watch(sesionProvider).valueOrNull;

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

            final rec = recAsync.valueOrNull;
            final cobrado = rec?['cobrado'] as int? ?? 0;
            final vendido = rec?['vendido'] as int? ?? 0;
            final faltaCobrar = rec?['falta_cobrar'] as int? ?? 0;
            final vendidosCount = rec?['numeros_vendidos'] as int? ?? 0;
            final totalesCount = rec?['numeros_totales'] as int? ?? 0;

            final progreso = (meta != null && meta > 0) ? (cobrado / meta) : null;

            // Movimientos pendientes que requieren aprobación del usuario actual
            final movs = movsAsync.valueOrNull ?? [];
            final pendientesDeAprobar = movs.where((m) {
              final req = m['requiere_aprobacion_de'] as String?;
              final est = m['estado'] as String?;
              return est == 'pendiente' && (req == sesionUsuario?['id'] || esAdmin);
            }).toList();

            final ventas = (ventasAsync.valueOrNull ?? []).cast<Map<String, dynamic>>();

            return RefreshIndicator(
              color: c.sello,
              onRefresh: () async {
                ref.invalidate(campanaProvider(campanaId));
                ref.invalidate(recaudacionProvider(campanaId));
                ref.invalidate(ventasProvider(campanaId));
                ref.invalidate(movimientosProvider(campanaId));
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
                      if (esAdmin && campana['estado'] == 'borrador')
                        TextButton(
                          onPressed: () => _activar(context, ref),
                          child: Text('Activar', style: t.etiqueta.copyWith(color: c.selloTexto)),
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

                  // Ticket de recaudación con datos reales
                  MitiTicket(
                    sobrelinea: 'Cobrado',
                    importe: plata(cobrado),
                    detalle: 'Vendido ${plata(vendido)} · falta cobrar ${plata(faltaCobrar)}',
                    progreso: progreso,
                    pie: meta == null ? 'Sin meta definida' : 'Meta ${plata(meta)}',
                    talonArriba: esRifa ? '$vendidosCount' : '${activos.length}',
                    talonAbajo: esRifa ? 'de $totalesCount nros' : (activos.length == 1 ? 'integrante' : 'integrantes'),
                  ),
                  const SizedBox(height: 14),

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

                  // Aviso si hay cobros en cuenta principal esperando confirmación
                  if (pendientesDeAprobar.isNotEmpty) ...[
                    MitiAviso(
                      cantidad: pendientesDeAprobar.length,
                      texto: pendientesDeAprobar.length == 1
                          ? 'cobro pendiente de tu confirmación'
                          : 'cobros pendientes de tu confirmación',
                      onTap: () => _mostrarAprobaciones(context, ref, pendientesDeAprobar),
                    ),
                    const SizedBox(height: 14),
                  ],

                  const SizedBox(height: 12),
                  Text('DÓNDE ESTÁ LA PLATA', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                  const SizedBox(height: 8),
                  MitiTroquel(color: c.tinta, grosor: 1.5),
                  ..._cajasConSaldos(context, cajas, rec?['cajas']),

                  // Desglose de productos vendidos (en campañas de productos)
                  if (!esRifa) ...[
                    Builder(
                      builder: (ctx) {
                        final desglose = (rec?['productos_desglose'] as List?)?.cast<Map<String, dynamic>>() ?? [];
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
                      ),
                  ],

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

    final listaRec = (cajasRecaudacion is List ? cajasRecaudacion : []).cast<Map<String, dynamic>>();

    final principal = cajas.where((x) => x['tipo'] == 'principal').firstOrNull;
    if (principal != null) {
      final recP = listaRec.where((x) => x['caja_id'] == principal['id']).firstOrNull;
      final conf = recP?['confirmado'] as int? ?? 0;
      final pend = recP?['pendiente'] as int? ?? 0;

      filas.add(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.troquel))),
          child: Row(
            children: [
              MitiIniciales(iniciales(principal['titular'] as String)),
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
      final titularId = caja['titular_id'] as String;
      if (titularesVistos.contains(titularId)) continue;
      titularesVistos.add(titularId);

      final cajasUsuario = cajas.where((x) => x['titular_id'] == titularId && x['tipo'] != 'principal');
      int totalConf = 0;
      int billete = 0;
      int efectivo = 0;

      for (final cu in cajasUsuario) {
        final recU = listaRec.where((x) => x['caja_id'] == cu['id']).firstOrNull;
        final conf = recU?['confirmado'] as int? ?? 0;
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
          titulo: 'COBROS A CONFIRMAR',
          subtitulo: 'CUENTA PRINCIPAL',
          child: Column(
            children: [
              for (final mov in pendientes) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.papelHundido,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plata(mov['importe'] as int),
                              style: t.importe.copyWith(color: c.tinta, fontSize: 22),
                            ),
                            Text(
                              'Transferencia a verificar',
                              style: t.pie.copyWith(color: c.tintaSuave),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          try {
                            await ref.read(apiProvider).confirmarMovimiento(
                                  campanaId,
                                  mov['id'] as String,
                                );
                            ref.invalidate(recaudacionProvider(campanaId));
                            ref.invalidate(movimientosProvider(campanaId));
                            if (context.mounted) mostrarAviso(context, 'Cobro confirmado');
                          } on ErrorApi catch (e) {
                            if (context.mounted) mostrarAviso(context, e.mensaje, error: true);
                          }
                        },
                        child: Text('Confirmar', style: t.etiqueta.copyWith(color: c.ok)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
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
}

class _FilaVenta extends ConsumerWidget {
  const _FilaVenta({
    required this.venta,
    required this.campanaId,
    required this.campanaNombre,
    required this.esRifa,
  });

  final Map<String, dynamic> venta;
  final String campanaId;
  final String campanaNombre;
  final bool esRifa;

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

    final numsStr = numeros.map((n) => n.toString().padLeft(2, '0')).join(', ');
    final resumenProd = itemsProductos.map((p) => '${p['cantidad']}x ${p['nombre']}').join(', ');
    final detalleTexto = esRifa
        ? 'Nros: $numsStr · Por $vendedorNombre'
        : '${resumenProd.isNotEmpty ? resumenProd : 'Productos'} · Por $vendedorNombre';

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
                          style: t.cuerpo.copyWith(fontWeight: FontWeight.w700, color: c.tinta),
                        ),
                      ),
                      const SizedBox(width: 8),
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
                  ),
                  const SizedBox(height: 2),
                  Text(detalleTexto, style: t.pie.copyWith(color: c.tintaSuave)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(plata(importe), style: t.cifra.copyWith(color: c.tinta)),
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
    final nombre = item['nombre'] as String;
    final cant = item['cantidad_vendida'] as int;
    final recaudado = item['recaudado'] as int;

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
          Text(plata(recaudado), style: t.cifra.copyWith(color: c.tinta, fontSize: 18)),
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
