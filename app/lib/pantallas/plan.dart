import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';

final estadoPlanProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, campanaId) => ref.watch(apiProvider).estadoPlan(campanaId),
);

/// Cuando la API contesta 402 (se pasó un límite del plan): explica y ofrece mejorar.
Future<void> ofrecerMejora(
  BuildContext context, {
  required String campanaId,
  required String mensaje,
  required bool esAdmin,
}) {
  final c = context.color;
  final t = context.texto;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => MitiHoja(
      subtitulo: 'Límite del plan',
      titulo: 'La campaña llegó a su tope',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_primeraMayuscula(mensaje), style: t.cuerpo.copyWith(color: c.tinta)),
          const SizedBox(height: 18),
          if (esAdmin)
            MitiBoton(
              texto: 'Ver planes',
              icono: Icons.workspace_premium_outlined,
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PantallaPlan(campanaId: campanaId, esAdmin: true)),
                );
              },
            )
          else
            Text(
              'La mejora la paga quien administra la campaña. Avisale para que la haga desde "Plan de la campaña".',
              style: t.pie.copyWith(color: c.tintaSuave),
            ),
        ],
      ),
    ),
  );
}

String _primeraMayuscula(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _limite(int? n, String unidad) => n == null ? '$unidad sin límite' : '${miles(n)} $unidad';

class PantallaPlan extends ConsumerStatefulWidget {
  const PantallaPlan({super.key, required this.campanaId, required this.esAdmin});

  final String campanaId;
  final bool esAdmin;

  @override
  ConsumerState<PantallaPlan> createState() => _PantallaPlanState();
}

class _PantallaPlanState extends ConsumerState<PantallaPlan> with WidgetsBindingObserver {
  String? _pagando; // código del plan cuyo pago está en curso
  String? _compraId;
  bool _revisando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Al volver del navegador se revisa solo si el pago entró.
  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed && _compraId != null) _revisarPago();
  }

  Future<void> _pagar(String plan) async {
    setState(() {
      _pagando = plan;
      _error = null;
    });
    try {
      final r = await ref.read(apiProvider).pedirMejora(widget.campanaId, plan);
      _compraId = r['compra_id'] as String;
      final abierto = await launchUrl(Uri.parse(r['url_pago'] as String), mode: LaunchMode.externalApplication);
      if (!abierto && mounted) setState(() => _error = 'No se pudo abrir MercadoPago en el navegador.');
    } on ErrorApi catch (e) {
      if (mounted) setState(() => _error = _primeraMayuscula(e.mensaje));
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos conectarnos. ¿Tenés señal?');
    } finally {
      if (mounted) setState(() => _pagando = null);
    }
  }

  Future<void> _revisarPago() async {
    final compraId = _compraId;
    if (compraId == null || _revisando) return;
    setState(() => _revisando = true);
    try {
      // MercadoPago puede tardar unos segundos en avisar: se pregunta unas veces.
      for (var intento = 0; intento < 5; intento++) {
        final compra = await ref.read(apiProvider).verCompra(widget.campanaId, compraId);
        final estado = compra['estado'] as String;
        if (estado == 'aprobada') {
          _compraId = null;
          ref.invalidate(estadoPlanProvider(widget.campanaId));
          ref.invalidate(campanaProvider(widget.campanaId));
          ref.invalidate(campanasProvider);
          if (mounted) _mostrarAprobado(compra);
          return;
        }
        if (estado == 'rechazada' || estado == 'cancelada') {
          _compraId = null;
          if (mounted) setState(() => _error = 'MercadoPago no aprobó el pago. No se cobró nada: podés probar de nuevo.');
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (mounted) {
        setState(() => _error = 'El pago todavía no se acreditó. Si pagaste, se habilita solo apenas MercadoPago lo apruebe.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos revisar el pago. ¿Tenés señal?');
    } finally {
      if (mounted) setState(() => _revisando = false);
    }
  }

  void _mostrarAprobado(Map<String, dynamic> compra) {
    final c = context.color;
    final t = context.texto;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MitiHoja(
        subtitulo: 'Pago aprobado',
        titulo: 'Listo, la campaña ya tiene el plan nuevo',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pagaste ${plata(compra['importe'] as int)}. Si querés que lo pague el grupo, '
              'cargalo como gasto de la campaña: se reparte como cualquier otro.',
              style: t.cuerpo.copyWith(color: c.tinta),
            ),
            const SizedBox(height: 18),
            MitiBoton(texto: 'Entendido', onTap: () => Navigator.of(ctx).pop()),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final datos = ref.watch(estadoPlanProvider(widget.campanaId));

    return Scaffold(
      appBar: AppBar(title: Text('Plan de la campaña', style: t.seccion.copyWith(color: c.tinta))),
      body: SafeArea(
        child: datos.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => MitiVacio(
            titulo: 'No pudimos traer el plan',
            detalle: e is ErrorApi ? _primeraMayuscula(e.mensaje) : '¿Tenés señal?',
          ),
          data: (d) {
            final actual = (d['actual'] as Map).cast<String, dynamic>();
            final uso = (d['uso'] as Map).cast<String, dynamic>();
            final mejoras = (d['mejoras'] as List).cast<Map<String, dynamic>>();
            final puedePagar = d['puede_pagar'] == true;
            if (d['compra_pendiente'] != null && _compraId == null) {
              _compraId = d['compra_pendiente'] as String;
            }

            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(estadoPlanProvider(widget.campanaId)),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Text('PLAN ACTUAL', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                  const SizedBox(height: 8),
                  _TarjetaPlan(plan: actual, uso: uso, actual: true),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    MitiErrorEnLinea(texto: _error!),
                  ],
                  if (_compraId != null) ...[
                    const SizedBox(height: 14),
                    MitiBoton(
                      texto: 'Ya pagué: revisar el pago',
                      secundario: true,
                      cargando: _revisando,
                      icono: Icons.refresh,
                      onTap: _revisarPago,
                    ),
                  ],
                  if (mejoras.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Text('MEJORAR', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                    const SizedBox(height: 8),
                    for (final m in mejoras) ...[
                      _TarjetaPlan(
                        plan: (m['plan'] as Map).cast<String, dynamic>(),
                        aPagar: m['a_pagar'] as int,
                        pie: widget.esAdmin
                            ? (puedePagar
                                ? MitiBoton(
                                    texto: 'Pagar ${plata(m['a_pagar'] as int)}',
                                    cargando: _pagando == (m['plan'] as Map)['codigo'],
                                    onTap: _pagando == null
                                        ? () => _pagar((m['plan'] as Map)['codigo'] as String)
                                        : null,
                                  )
                                : Text('El cobro todavía no está habilitado.',
                                    style: t.pie.copyWith(color: c.tintaSuave)))
                            : Text('La mejora la paga quien administra la campaña.',
                                style: t.pie.copyWith(color: c.tintaSuave)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'Se paga con MercadoPago, una vez por campaña, y se cobra la diferencia con el '
                      'plan que ya tiene. Lo que ya cargaron no se toca.',
                      style: t.pie.copyWith(color: c.tintaSuave),
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
}

class _TarjetaPlan extends StatelessWidget {
  const _TarjetaPlan({required this.plan, this.uso, this.actual = false, this.aPagar, this.pie});

  final Map<String, dynamic> plan;
  final Map<String, dynamic>? uso;
  final bool actual;
  final int? aPagar;
  final Widget? pie;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    Widget fila(String texto, {String? usado}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(Icons.check, size: 16, color: c.tintaSuave),
              const SizedBox(width: 8),
              Expanded(child: Text(texto, style: t.cuerpo.copyWith(color: c.tinta))),
              if (usado != null) Text(usado, style: t.etiqueta.copyWith(color: c.tintaSuave)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.hoja,
        border: Border.all(color: c.tinta, width: actual ? 2 : 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(plan['nombre'] as String, style: t.seccion.copyWith(color: c.tinta))),
              if (aPagar != null) Text(plata(aPagar!), style: t.cifra.copyWith(color: c.tinta)),
            ],
          ),
          const SizedBox(height: 8),
          const MitiTroquel(),
          const SizedBox(height: 8),
          fila(_limite(plan['limite_integrantes'] as int?, 'integrantes'),
              usado: uso == null ? null : 'usás ${uso!['integrantes']}'),
          fila(_limite(plan['limite_numeros'] as int?, 'números de talonario'),
              usado: uso?['numeros'] == null ? null : 'tenés ${miles(uso!['numeros'] as int)}'),
          fila(_limite(plan['limite_ventas'] as int?, 'ventas de productos'),
              usado: uso?['ventas'] == null ? null : 'llevás ${uso!['ventas']}'),
          fila(plan['publicidad'] == true ? 'Con publicidad' : 'Sin publicidad'),
          if (pie != null) ...[const SizedBox(height: 12), pie!],
        ],
      ),
    );
  }
}
