import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';

/// Pantalla de liquidación de campaña (§3.9 de DEFINICION.md).
///
/// Si la campaña está cerrada o sorteada, muestra la simulación comparando
/// Base Cobrada y Base Vendida, valida impedimentos y permite al admin confirmar.
///
/// Si la campaña ya fue liquidada, muestra el desglose final y las transferencias
/// sugeridas entre integrantes con sus estados (pendiente / pagada / confirmada).
class PantallaLiquidacion extends ConsumerStatefulWidget {
  const PantallaLiquidacion({
    super.key,
    required this.campanaId,
    required this.campanaNombre,
    required this.esAdmin,
    required this.estadoCampana,
  });

  final String campanaId;
  final String campanaNombre;
  final bool esAdmin;
  final String estadoCampana;

  @override
  ConsumerState<PantallaLiquidacion> createState() => _PantallaLiquidacionState();
}

class _PantallaLiquidacionState extends ConsumerState<PantallaLiquidacion> {
  String _baseSeleccionada = 'cobrada'; // 'cobrada' o 'vendida'
  bool _confirmando = false;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final esLiquidada = widget.estadoCampana == 'liquidada';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Barra superior
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back, color: c.tinta),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          esLiquidada
                              ? 'LIQUIDACIÓN FINAL'
                              : 'CIERRE Y LIQUIDACIÓN',
                          style: t.sobrelinea.copyWith(color: c.tintaSuave),
                        ),
                        Text(
                          widget.campanaNombre,
                          style: t.etiqueta.copyWith(
                            color: c.tinta,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Contenido principal
            Expanded(
              child: esLiquidada
                  ? _VistaLiquidada(
                      campanaId: widget.campanaId,
                      esAdmin: widget.esAdmin,
                    )
                  : _VistaSimulacion(
                      campanaId: widget.campanaId,
                      esAdmin: widget.esAdmin,
                      baseSeleccionada: _baseSeleccionada,
                      onCambiarBase: (base) => setState(() => _baseSeleccionada = base),
                      confirmando: _confirmando,
                      onConfirmar: _confirmarLiquidacion,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarLiquidacion() async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.color.hoja,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: Text('¿Confirmar liquidación?', style: context.texto.seccion),
        content: Text(
          'Se liquidará en Base ${_baseSeleccionada == 'cobrada' ? 'Cobrada' : 'Vendida'}.\n\n'
          'La campaña quedará bloqueada para nuevas ventas y se fijarán las transferencias '
          'entre los integrantes para equilibrar los saldos.',
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
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirma != true || !mounted) return;

    setState(() => _confirmando = true);
    try {
      await ref.read(apiProvider).confirmarLiquidacion(
            widget.campanaId,
            _baseSeleccionada,
          );
      ref.invalidate(campanaProvider(widget.campanaId));
      ref.invalidate(liquidacionProvider(widget.campanaId));
      if (mounted) {
        mostrarAviso(context, 'Campaña liquidada con éxito');
        Navigator.of(context).pop(true);
      }
    } on ErrorApi catch (e) {
      if (mounted) mostrarAviso(context, e.mensaje, error: true);
    } catch (_) {
      if (mounted) mostrarAviso(context, 'Error de conexión. ¿Tenés señal?', error: true);
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }
}

/// Vista de simulación antes de liquidar
class _VistaSimulacion extends ConsumerWidget {
  const _VistaSimulacion({
    required this.campanaId,
    required this.esAdmin,
    required this.baseSeleccionada,
    required this.onCambiarBase,
    required this.confirmando,
    required this.onConfirmar,
  });

  final String campanaId;
  final bool esAdmin;
  final String baseSeleccionada;
  final ValueChanged<String> onCambiarBase;
  final bool confirmando;
  final VoidCallback onConfirmar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.color;
    final t = context.texto;
    final simAsync = ref.watch(simulacionLiquidacionProvider(campanaId));

    return simAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No se pudo cargar la simulación',
                style: t.seccion.copyWith(color: c.selloTexto),
              ),
              const SizedBox(height: 8),
              Text(
                e is ErrorApi ? e.mensaje : 'Fijate si tenés señal.',
                style: t.cuerpo.copyWith(color: c.tintaSuave),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              MitiBoton(
                texto: 'Reintentar',
                secundario: true,
                onTap: () => ref.invalidate(simulacionLiquidacionProvider(campanaId)),
              ),
            ],
          ),
        ),
      ),
      data: (sim) {
        final puedeLiquidar = sim['puede_liquidar'] as bool? ?? false;
        final impedimentos = (sim['impedimentos'] as List?)?.cast<String>() ?? [];
        final opcionCobrada = sim['base_cobrada'] as Map<String, dynamic>;
        final opcionVendida = sim['base_vendida'] as Map<String, dynamic>;
        final opcionActual = baseSeleccionada == 'cobrada' ? opcionCobrada : opcionVendida;

        final neto = opcionActual['neto'] as int? ?? 0;
        final cuotaParte = opcionActual['parte'] as int? ?? 0;
        final recaudado = opcionActual['recaudado'] as int? ?? 0;
        final gastos = opcionActual['gastos'] as int? ?? 0;
        final participantes =
            (opcionActual['participantes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final transferencias =
            (opcionActual['transferencias'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // Selector de bases
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: c.papelHundido,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.troquel),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _BotonPestanaBase(
                      titulo: 'Base Cobrada',
                      subtitulo: 'Solo lo cobrado',
                      activa: baseSeleccionada == 'cobrada',
                      onTap: () => onCambiarBase('cobrada'),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _BotonPestanaBase(
                      titulo: 'Base Vendida',
                      subtitulo: 'Total vendido',
                      activa: baseSeleccionada == 'vendida',
                      onTap: () => onCambiarBase('vendida'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Explicación de la base seleccionada
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.hoja,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.troquel),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: c.tintaSuave),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      baseSeleccionada == 'cobrada'
                          ? 'Base Cobrada (§3.9): Reparte solo la plata efectivamente ingresada en las cajas '
                            '(${plata(recaudado)}). Lo que quedó debiendo algún comprador se cobrará luego fuera del reparto.'
                          : 'Base Vendida (§3.9): Reparte todo lo vendido (${plata(recaudado)}). Quien registró '
                            'una venta adeudada asume esa cobranza en su saldo a favor.',
                      style: t.pie.copyWith(color: c.tinta),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tarjeta de recaudación y cuota parte
            MitiTicket(
              sobrelinea: 'Neto a repartir',
              importe: plata(neto),
              detalle: 'Total ${plata(recaudado)} · Gastos ${plata(gastos)}',
              talonArriba: plata(cuotaParte),
              talonAbajo: 'por integrante',
            ),
            const SizedBox(height: 16),

            // Impedimentos si existen
            if (!puedeLiquidar && impedimentos.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.sello.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.sello, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: c.selloTexto, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'HAY ACCIONES PENDIENTES',
                          style: t.etiqueta.copyWith(
                            color: c.selloTexto,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final imp in impedimentos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• ', style: TextStyle(color: c.selloTexto, fontWeight: FontWeight.bold)),
                            Expanded(
                              child: Text(
                                imp,
                                style: t.cuerpo.copyWith(color: c.tinta, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      'Debés aprobar o rechazar los cobros en cuenta principal y liberar las reservas '
                      'activas de números antes de liquidar.',
                      style: t.pie.copyWith(color: c.tintaSuave),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Detalle por integrante
            Text('INTEGRANTES Y SALDOS', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
            const SizedBox(height: 8),
            MitiTroquel(color: c.tinta, grosor: 1.5),
            for (final p in participantes) _FilaParticipanteSimulacion(p: p),
            const SizedBox(height: 24),

            // Transferencias sugeridas
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TRANSFERENCIAS SUGERIDAS', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                Text('${transferencias.length}', style: t.etiqueta.copyWith(color: c.tintaSuave)),
              ],
            ),
            const SizedBox(height: 8),
            MitiTroquel(color: c.tinta, grosor: 1.5),
            if (transferencias.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'No se requieren transferencias. Cada uno ya tiene en mano su parte exacta.',
                    style: t.cuerpo.copyWith(color: c.tintaSuave),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              for (final tr in transferencias) _FilaTransferenciaSugerida(tr: tr),

            const SizedBox(height: 28),

            // Botón de confirmación (solo admin)
            if (esAdmin)
              MitiBoton(
                texto: puedeLiquidar
                    ? 'Confirmar liquidación'
                    : 'Resolver pendientes para liquidar',
                cargando: confirmando,
                onTap: puedeLiquidar && !confirmando ? onConfirmar : null,
              ),
          ],
        );
      },
    );
  }
}

/// Pestaña toggle de base
class _BotonPestanaBase extends StatelessWidget {
  const _BotonPestanaBase({
    required this.titulo,
    required this.subtitulo,
    required this.activa,
    required this.onTap,
  });

  final String titulo;
  final String subtitulo;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: activa ? c.hoja : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: activa ? Border.all(color: c.tinta, width: 1.5) : null,
        ),
        child: Column(
          children: [
            Text(
              titulo,
              style: t.etiqueta.copyWith(
                fontWeight: activa ? FontWeight.w800 : FontWeight.w600,
                color: c.tinta,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitulo,
              style: t.pie.copyWith(
                color: activa ? c.tintaSuave : c.tintaSuave.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila de participante en simulación
class _FilaParticipanteSimulacion extends StatelessWidget {
  const _FilaParticipanteSimulacion({required this.p});

  final Map<String, dynamic> p;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    final nombre = p['nombre'] as String? ?? 'Integrante';
    final recaudado = p['recaudado'] as int? ?? 0;
    final parte = p['parte'] as int? ?? 0;
    final balance = p['balance'] as int? ?? 0;

    final debe = balance > 0;
    final recibe = balance < 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.troquel))),
      child: Row(
        children: [
          MitiIniciales(iniciales(nombre)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre, style: t.cuerpo.copyWith(fontWeight: FontWeight.w600, color: c.tinta)),
                Text(
                  'En caja: ${plata(recaudado)} · Cuota: ${plata(parte)}',
                  style: t.pie.copyWith(color: c.tintaSuave),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (debe) ...[
                Text('Transfiere', style: t.pie.copyWith(color: c.selloTexto, fontWeight: FontWeight.bold)),
                Text(plata(balance), style: t.cifra.copyWith(color: c.selloTexto)),
              ] else if (recibe) ...[
                Text('Recibe', style: t.pie.copyWith(color: c.ok, fontWeight: FontWeight.bold)),
                Text(plata(-balance), style: t.cifra.copyWith(color: c.ok)),
              ] else ...[
                Text('Equilibrado', style: t.pie.copyWith(color: c.tintaSuave)),
                Text('\$ 0', style: t.cifra.copyWith(color: c.tintaSuave)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Fila de transferencia sugerida
class _FilaTransferenciaSugerida extends StatelessWidget {
  const _FilaTransferenciaSugerida({required this.tr});

  final Map<String, dynamic> tr;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    final deNombre = tr['de_nombre'] as String? ?? 'Deudor';
    final aNombre = tr['a_nombre'] as String? ?? 'Acreedor';
    final importe = tr['importe'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.troquel))),
      child: Row(
        children: [
          Icon(Icons.arrow_forward_rounded, color: c.selloTexto, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: t.cuerpo.copyWith(color: c.tinta),
                children: [
                  TextSpan(
                    text: deNombre,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' le transfiere a '),
                  TextSpan(
                    text: aNombre,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          Text(plata(importe), style: t.cifra.copyWith(color: c.tinta)),
        ],
      ),
    );
  }
}

/// Vista final cuando la campaña ya fue liquidada
class _VistaLiquidada extends ConsumerWidget {
  const _VistaLiquidada({
    required this.campanaId,
    required this.esAdmin,
  });

  final String campanaId;
  final bool esAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.color;
    final t = context.texto;
    final liqAsync = ref.watch(liquidacionProvider(campanaId));
    final sesionUsuario = ref.watch(sesionProvider).valueOrNull;
    final miId = sesionUsuario?['id'] as String?;

    return liqAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No se pudo cargar la liquidación', style: t.seccion.copyWith(color: c.selloTexto)),
              const SizedBox(height: 8),
              Text(
                e is ErrorApi ? e.mensaje : 'Fijate si tenés señal.',
                style: t.cuerpo.copyWith(color: c.tintaSuave),
              ),
              const SizedBox(height: 16),
              MitiBoton(
                texto: 'Reintentar',
                secundario: true,
                onTap: () => ref.invalidate(liquidacionProvider(campanaId)),
              ),
            ],
          ),
        ),
      ),
      data: (liq) {
        final base = liq['base'] as String? ?? 'cobrada';
        final neto = liq['neto'] as int? ?? 0;
        final parte = liq['parte'] as int? ?? 0;
        final recaudado = liq['recaudado'] as int? ?? 0;
        final gastos = liq['gastos'] as int? ?? 0;
        final confirmadaPorNombre = liq['confirmada_por_nombre'] as String? ?? 'Administrador';
        final transfs = (liq['transferencias'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        // Filtramos las transferencias del usuario actual
        final misTransferencias = transfs.where((tr) {
          final deId = tr['de_usuario_id'] as String?;
          final aId = tr['a_usuario_id'] as String?;
          return deId == miId || aId == miId;
        }).toList();

        return RefreshIndicator(
          color: c.sello,
          onRefresh: () async {
            ref.invalidate(liquidacionProvider(campanaId));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // Ticket resumen
              MitiTicket(
                sobrelinea: 'Liquidada en Base ${base.toUpperCase()}',
                importe: plata(neto),
                detalle: 'Recaudado ${plata(recaudado)} · Gastos ${plata(gastos)}',
                talonArriba: plata(parte),
                talonAbajo: 'por integrante',
                pie: 'Confirmada por $confirmadaPorNombre',
              ),
              const SizedBox(height: 20),

              // Sección "Tus transferencias" si tiene alguna
              if (misTransferencias.isNotEmpty) ...[
                Text('TUS TRANSFERENCIAS', style: t.sobrelinea.copyWith(color: c.selloTexto)),
                const SizedBox(height: 8),
                MitiTroquel(color: c.sello, grosor: 1.5),
                for (final tr in misTransferencias)
                  _TarjetaTransferenciaUsuario(
                    tr: tr,
                    miId: miId,
                    esAdmin: esAdmin,
                    campanaId: campanaId,
                  ),
                const SizedBox(height: 24),
              ],

              // Sección "Todas las transferencias"
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('TODAS LAS TRANSFERENCIAS', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                  Text('${transfs.length}', style: t.etiqueta.copyWith(color: c.tintaSuave)),
                ],
              ),
              const SizedBox(height: 8),
              MitiTroquel(color: c.tinta, grosor: 1.5),
              if (transfs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No hubo transferencias pendientes. Los saldos quedaron cerrados de forma directa.',
                      style: t.cuerpo.copyWith(color: c.tintaSuave),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                for (final tr in transfs)
                  _FilaTransferenciaLiquidada(
                    tr: tr,
                    miId: miId,
                    esAdmin: esAdmin,
                    campanaId: campanaId,
                  ),
            ],
          ),
        );
      },
    );
  }
}

/// Tarjeta destacada de transferencia para el usuario conectado
class _TarjetaTransferenciaUsuario extends ConsumerStatefulWidget {
  const _TarjetaTransferenciaUsuario({
    required this.tr,
    required this.miId,
    required this.esAdmin,
    required this.campanaId,
  });

  final Map<String, dynamic> tr;
  final String? miId;
  final bool esAdmin;
  final String campanaId;

  @override
  ConsumerState<_TarjetaTransferenciaUsuario> createState() =>
      _TarjetaTransferenciaUsuarioState();
}

class _TarjetaTransferenciaUsuarioState
    extends ConsumerState<_TarjetaTransferenciaUsuario> {
  bool _accionando = false;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    final id = widget.tr['id'] as String;
    final deId = widget.tr['de_usuario_id'] as String?;
    final deNombre = widget.tr['de_nombre'] as String? ?? 'Deudor';
    final aId = widget.tr['a_usuario_id'] as String?;
    final aNombre = widget.tr['a_nombre'] as String? ?? 'Acreedor';
    final importe = widget.tr['importe'] as int? ?? 0;
    final estado = widget.tr['estado'] as String? ?? 'pendiente';

    final esDeudor = deId == widget.miId;
    final esAcreedor = aId == widget.miId;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.hoja,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: estado == 'confirmada' ? c.ok : (estado == 'pagada' ? c.mostaza : c.sello),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                esDeudor ? 'TENÉS QUE TRANSFERIR' : 'TE TIENEN QUE TRANSFERIR',
                style: t.sobrelinea.copyWith(
                  color: esDeudor ? c.selloTexto : c.ok,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _ChipEstadoTransferencia(estado: estado),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  esDeudor ? 'a $aNombre' : 'de $deNombre',
                  style: t.seccion.copyWith(color: c.tinta, fontSize: 20),
                ),
              ),
              Text(plata(importe), style: t.cifra.copyWith(color: c.tinta, fontSize: 22)),
            ],
          ),
          const SizedBox(height: 12),

          // Botones de acción según el rol y estado
          if (estado == 'pendiente' && (esDeudor || widget.esAdmin)) ...[
            MitiBoton(
              texto: 'Marcar como transferida',
              cargando: _accionando,
              onTap: () => _actualizar(id, 'pagar'),
            ),
          ] else if (estado == 'pagada') ...[
            if (esAcreedor || widget.esAdmin) ...[
              MitiBoton(
                texto: 'Confirmar cobro recibido',
                cargando: _accionando,
                onTap: () => _actualizar(id, 'confirmar'),
              ),
            ] else ...[
              Text(
                'Marcaste la transferencia como enviada. Esperando que $aNombre confirme la recepción.',
                style: t.pie.copyWith(color: c.tintaSuave),
              ),
            ],
          ] else if (estado == 'confirmada') ...[
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: c.ok, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Transferencia completada y confirmada',
                  style: t.pie.copyWith(color: c.ok, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _actualizar(String trId, String accion) async {
    setState(() => _accionando = true);
    try {
      await ref.read(apiProvider).actualizarTransferencia(
            widget.campanaId,
            trId,
            accion: accion,
          );
      ref.invalidate(liquidacionProvider(widget.campanaId));
      if (mounted) {
        mostrarAviso(
          context,
          accion == 'pagar'
              ? 'Transferencia marcada como pagada'
              : 'Cobro confirmado con éxito',
        );
      }
    } on ErrorApi catch (e) {
      if (mounted) mostrarAviso(context, e.mensaje, error: true);
    } catch (_) {
      if (mounted) mostrarAviso(context, 'Fijate si tenés señal.', error: true);
    } finally {
      if (mounted) setState(() => _accionando = false);
    }
  }
}

/// Fila general de transferencia en lista
class _FilaTransferenciaLiquidada extends ConsumerWidget {
  const _FilaTransferenciaLiquidada({
    required this.tr,
    required this.miId,
    required this.esAdmin,
    required this.campanaId,
  });

  final Map<String, dynamic> tr;
  final String? miId;
  final bool esAdmin;
  final String campanaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.color;
    final t = context.texto;

    final deNombre = tr['de_nombre'] as String? ?? 'Deudor';
    final aNombre = tr['a_nombre'] as String? ?? 'Acreedor';
    final importe = tr['importe'] as int? ?? 0;
    final estado = tr['estado'] as String? ?? 'pendiente';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.troquel))),
      child: Row(
        children: [
          _ChipEstadoTransferencia(estado: estado),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: t.cuerpo.copyWith(color: c.tinta),
                    children: [
                      TextSpan(text: deNombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' → '),
                      TextSpan(text: aNombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Text(plata(importe), style: t.cifra.copyWith(color: c.tinta)),
        ],
      ),
    );
  }
}

/// Chip de estado de transferencia
class _ChipEstadoTransferencia extends StatelessWidget {
  const _ChipEstadoTransferencia({required this.estado});

  final String estado;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    final colorFondo = switch (estado) {
      'confirmada' => c.ok.withValues(alpha: 0.15),
      'pagada' => c.mostaza.withValues(alpha: 0.2),
      _ => c.sello.withValues(alpha: 0.12),
    };

    final colorTexto = switch (estado) {
      'confirmada' => c.ok,
      'pagada' => c.tinta,
      _ => c.selloTexto,
    };

    final etiqueta = switch (estado) {
      'confirmada' => 'CONFIRMADA',
      'pagada' => 'PAGADA',
      _ => 'PENDIENTE',
    };

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
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}
