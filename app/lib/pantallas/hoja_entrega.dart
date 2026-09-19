import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';

/// Hoja para registrar una entrega de dinero entre cajas (§3.6 de DEFINICION.md).
/// Un integrante transfiere dinero en custodia hacia otra caja (ej: entrega de efectivo
/// al tesorero/admin). Requiere confirmación del receptor.
class HojaEntrega extends ConsumerStatefulWidget {
  const HojaEntrega({
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
  ConsumerState<HojaEntrega> createState() => _HojaEntregaState();
}

class _HojaEntregaState extends ConsumerState<HojaEntrega> {
  final _claveForm = GlobalKey<FormState>();
  final _importeControlador = TextEditingController();
  final _notaControlador = TextEditingController();

  String? _cajaOrigenId;
  String? _cajaDestinoId;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final miId = ref.read(sesionProvider).valueOrNull?['id'];

    // Cajas del usuario actual
    final misCajas = widget.cajas.where((c) => c['titular_id'] == miId).toList();
    final miCajaEfectivo = misCajas.where((c) => c['tipo'] == 'efectivo').firstOrNull;
    _cajaOrigenId = miCajaEfectivo?['id'] as String? ?? misCajas.firstOrNull?['id'] as String?;

    // Cajas de otros integrantes o destino
    final otrasCajas = widget.cajas.where((c) => c['id'] != _cajaOrigenId).toList();
    _cajaDestinoId = otrasCajas.firstOrNull?['id'] as String?;
  }

  @override
  void dispose() {
    _importeControlador.dispose();
    _notaControlador.dispose();
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

  String _nombreCaja(Map<String, dynamic> c) {
    final titular = c['titular']?['nombre'] as String? ?? 'Campaña';
    final tipo = c['tipo'] == 'efectivo' ? 'Efectivo' : 'Cuenta';
    final nombre = c['nombre'] as String? ?? tipo;
    return '$nombre ($titular)';
  }

  Future<void> _guardar() async {
    if (!_claveForm.currentState!.validate()) return;
    final imp = _importeCentavos;
    if (imp == null) return;

    if (_cajaOrigenId == null || _cajaDestinoId == null) {
      setState(() => _error = 'Tenés que seleccionar caja origen y destino.');
      return;
    }

    if (_cajaOrigenId == _cajaDestinoId) {
      setState(() => _error = 'La caja destino debe ser distinta a la de origen.');
      return;
    }

    final saldo = _saldoCaja(_cajaOrigenId);
    if (saldo < imp) {
      setState(() => _error = 'Saldo insuficiente en tu caja (${plata(saldo)} disponibles).');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final nota = _notaControlador.text.trim();
      await ref.read(apiProvider).crearEntrega(
            widget.campanaId,
            cajaOrigenId: _cajaOrigenId!,
            cajaDestinoId: _cajaDestinoId!,
            importe: imp,
            nota: nota.isNotEmpty ? nota : null,
          );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final miId = ref.read(sesionProvider).valueOrNull?['id'];
    final misCajas = widget.cajas.where((c) => c['titular_id'] == miId).toList();
    final otrasCajas = widget.cajas.where((c) => c['id'] != _cajaOrigenId).toList();
    final saldoDisponible = _saldoCaja(_cajaOrigenId);

    return MitiHoja(
      titulo: 'PASAR DINERO / ENTREGA',
      subtitulo: 'TRANSFERENCIA ENTRE INTEGRANTES',
      child: Form(
        key: _claveForm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'DESDE MI CAJA',
              style: t.sobrelinea.copyWith(color: c.tintaSuave),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _cajaOrigenId,
              dropdownColor: c.hoja,
              style: t.cuerpo.copyWith(color: c.tinta),
              decoration: InputDecoration(
                filled: true,
                fillColor: c.papelHundido,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              items: misCajas.map((cx) {
                final id = cx['id'] as String;
                return DropdownMenuItem<String>(
                  value: id,
                  child: Text(
                    '${_nombreCaja(cx)} (${plata(_saldoCaja(id))})',
                    style: t.cuerpo.copyWith(color: c.tinta),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _cajaOrigenId = val;
                  if (_cajaDestinoId == val) {
                    _cajaDestinoId = widget.cajas.where((cx) => cx['id'] != val).firstOrNull?['id'] as String?;
                  }
                });
              },
            ),
            const SizedBox(height: 6),
            Text(
              'Saldo disponible: ${plata(saldoDisponible)}',
              style: t.pie.copyWith(
                color: saldoDisponible > 0 ? c.ok : c.selloTexto,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 16),

            Text(
              'HACIA LA CAJA DE',
              style: t.sobrelinea.copyWith(color: c.tintaSuave),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _cajaDestinoId,
              dropdownColor: c.hoja,
              style: t.cuerpo.copyWith(color: c.tinta),
              decoration: InputDecoration(
                filled: true,
                fillColor: c.papelHundido,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              items: otrasCajas.map((cx) {
                final id = cx['id'] as String;
                return DropdownMenuItem<String>(
                  value: id,
                  child: Text(
                    _nombreCaja(cx),
                    style: t.cuerpo.copyWith(color: c.tinta),
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _cajaDestinoId = val),
            ),

            const SizedBox(height: 16),

            TextFormField(
              controller: _importeControlador,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: t.importe.copyWith(color: c.tinta, fontSize: 26),
              decoration: InputDecoration(
                labelText: 'Monto a entregar',
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
                if ((n * 100) > saldoDisponible) return 'Supera el saldo disponible (${plata(saldoDisponible)})';
                return null;
              },
            ),

            const SizedBox(height: 14),

            TextFormField(
              controller: _notaControlador,
              textCapitalization: TextCapitalization.sentences,
              style: t.cuerpo.copyWith(color: c.tinta),
              decoration: InputDecoration(
                labelText: 'Nota / referencia (opcional)',
                hintText: 'Ej: Rendición ventas del domingo',
                hintStyle: t.cuerpo.copyWith(color: c.tintaSuave.withValues(alpha: 0.5)),
                labelStyle: t.etiqueta.copyWith(color: c.tintaSuave),
                prefixIcon: Icon(Icons.notes, color: c.tinta),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: c.tinta, width: 2),
                ),
              ),
            ),

            const SizedBox(height: 14),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.papelHundido,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.troquel),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: c.tinta, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'El titular de la caja receptora deberá confirmar la entrega para que se acredite en su saldo.',
                      style: t.pie.copyWith(color: c.tintaSuave),
                    ),
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.sello,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _error!,
                  style: t.cuerpo.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            const SizedBox(height: 20),

            MitiBoton(
              texto: 'Registrar entrega',
              cargando: _cargando,
              onTap: _guardar,
            ),
          ],
        ),
      ),
    );
  }
}
