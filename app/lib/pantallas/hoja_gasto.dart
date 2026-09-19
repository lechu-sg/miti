import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';

/// Hoja para registrar un gasto de campaña (§3.7 de DEFINICION.md).
/// Puede salir del bolsillo del participante (a reintegrar en liquidación)
/// o de la caja que tiene en custodia (descuenta saldo disponible de caja).
class HojaGasto extends ConsumerStatefulWidget {
  const HojaGasto({
    super.key,
    required this.campanaId,
    required this.campanaNombre,
    required this.cajas,
    this.cajasRecaudacion,
  });

  final String campanaId;
  final String campanaNombre;
  final List<Map<String, dynamic>> cajas;
  final dynamic cajasRecaudacion;

  @override
  ConsumerState<HojaGasto> createState() => _HojaGastoState();
}

class _HojaGastoState extends ConsumerState<HojaGasto> {
  final _claveForm = GlobalKey<FormState>();
  final _descControlador = TextEditingController();
  final _importeControlador = TextEditingController();

  String _origen = 'bolsillo'; // 'bolsillo' | 'caja'
  String? _cajaIdSeleccionada;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final miId = ref.read(sesionProvider).valueOrNull?['id'];
    final miCajaEfectivo = widget.cajas.where((c) => c['tipo'] == 'efectivo' && c['titular_id'] == miId).firstOrNull;
    if (miCajaEfectivo != null) {
      _cajaIdSeleccionada = miCajaEfectivo['id'] as String?;
    } else {
      final primeraCaja = widget.cajas.where((c) => c['titular_id'] == miId).firstOrNull;
      _cajaIdSeleccionada = primeraCaja?['id'] as String?;
    }
  }

  @override
  void dispose() {
    _descControlador.dispose();
    _importeControlador.dispose();
    super.dispose();
  }

  int _saldoCaja(String? cajaId) {
    if (cajaId == null) return 0;
    final listaRec = (widget.cajasRecaudacion is List ? widget.cajasRecaudacion : []).cast<Map<String, dynamic>>();
    final recC = listaRec.where((x) => x['caja_id'] == cajaId).firstOrNull;
    return recC?['confirmado'] as int? ?? 0;
  }

  int? get _importeCentavos {
    final t = _importeControlador.text.trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    if (n == null || n <= 0) return null;
    return n * 100;
  }

  Future<void> _guardar() async {
    if (!_claveForm.currentState!.validate()) return;
    final imp = _importeCentavos;
    if (imp == null) return;

    if (_origen == 'caja') {
      if (_cajaIdSeleccionada == null) {
        setState(() => _error = 'Seleccioná una caja para el egreso.');
        return;
      }
      final saldo = _saldoCaja(_cajaIdSeleccionada);
      if (saldo < imp) {
        setState(() => _error = 'Saldo insuficiente en tu caja (${plata(saldo)} disponibles).');
        return;
      }
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      await ref.read(apiProvider).crearGasto(
            widget.campanaId,
            descripcion: _descControlador.text.trim(),
            importe: imp,
            origen: _origen,
            cajaId: _origen == 'caja' ? _cajaIdSeleccionada : null,
          );

      ref.invalidate(gastosProvider(widget.campanaId));
      ref.invalidate(recaudacionProvider(widget.campanaId));
      ref.invalidate(movimientosProvider(widget.campanaId));
      ref.invalidate(campanaProvider(widget.campanaId));

      if (!mounted) return;
      Navigator.of(context).pop(true);
      mostrarAviso(context, 'Gasto registrado. Pendiente de aprobación.');
    } on ErrorApi catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos registrar el gasto. Revisá tu conexión.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final saldoDisponible = _saldoCaja(_cajaIdSeleccionada);
    final tieneCaja = _cajaIdSeleccionada != null;

    return MitiHoja(
      titulo: 'REGISTRAR GASTO',
      subtitulo: widget.campanaNombre,
      child: Form(
        key: _claveForm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _descControlador,
              textCapitalization: TextCapitalization.sentences,
              style: t.cuerpo.copyWith(color: c.tinta),
              decoration: InputDecoration(
                labelText: '¿En qué se gastó?',
                hintText: 'Ej: Carbón, leña, hielo, vasos...',
                hintStyle: t.cuerpo.copyWith(color: c.tintaSuave.withValues(alpha: 0.5)),
                labelStyle: t.etiqueta.copyWith(color: c.tintaSuave),
                prefixIcon: Icon(Icons.receipt_long_outlined, color: c.tinta),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: c.tinta, width: 2),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().length < 3) return 'Ingresá una descripción clara del gasto';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _importeControlador,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: t.importe.copyWith(color: c.tinta, fontSize: 26),
              decoration: InputDecoration(
                labelText: 'Importe del gasto',
                prefixText: '\$ ',
                prefixStyle: t.importe.copyWith(color: c.tinta, fontSize: 26),
                labelStyle: t.etiqueta.copyWith(color: c.tintaSuave),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: c.tinta, width: 2),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresá el importe';
                final n = int.tryParse(v.trim());
                if (n == null || n <= 0) return 'El importe debe ser mayor a 0';
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),

            Text('¿DE DÓNDE SALIÓ LA PLATA?', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
            const SizedBox(height: 8),

            // Opción 1: De mi bolsillo
            InkWell(
              onTap: () => setState(() {
                _origen = 'bolsillo';
                _error = null;
              }),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _origen == 'bolsillo' ? c.sello.withValues(alpha: 0.1) : c.papelHundido,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _origen == 'bolsillo' ? c.sello : c.troquel,
                    width: _origen == 'bolsillo' ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _origen == 'bolsillo' ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: _origen == 'bolsillo' ? c.sello : c.tintaSuave,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('De mi bolsillo', style: t.cuerpo.copyWith(fontWeight: FontWeight.w700, color: c.tinta)),
                          const SizedBox(height: 2),
                          Text(
                            'Pusiste de tu plata. Te lo reintegran en la liquidación final.',
                            style: t.pie.copyWith(color: c.tintaSuave),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Opción 2: De mi caja de efectivo
            InkWell(
              onTap: tieneCaja
                  ? () => setState(() {
                        _origen = 'caja';
                        _error = null;
                      })
                  : null,
              borderRadius: BorderRadius.circular(6),
              child: Opacity(
                opacity: tieneCaja ? 1.0 : 0.45,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _origen == 'caja' ? c.sello.withValues(alpha: 0.1) : c.papelHundido,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _origen == 'caja' ? c.sello : c.troquel,
                      width: _origen == 'caja' ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _origen == 'caja' ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: _origen == 'caja' ? c.sello : c.tintaSuave,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('De lo cobrado en mi caja',
                                    style: t.cuerpo.copyWith(fontWeight: FontWeight.w700, color: c.tinta)),
                                Text(
                                  plata(saldoDisponible),
                                  style: t.etiqueta.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: saldoDisponible > 0 ? c.ok : c.tintaSuave,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tieneCaja
                                  ? 'Salió del efectivo que tenés en custodia.'
                                  : 'No tenés una caja asignada con recaudación.',
                              style: t.pie.copyWith(color: c.tintaSuave),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.sello,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _error!,
                  style: t.cuerpo.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],

            const SizedBox(height: 24),

            MitiBoton(
              texto: 'Registrar gasto',
              cargando: _cargando,
              onTap: _cargando ? null : _guardar,
            ),
          ],
        ),
      ),
    );
  }
}
