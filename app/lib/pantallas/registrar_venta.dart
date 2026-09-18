import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';
import 'billete.dart';

/// Hoja para registrar una nueva venta de números seleccionados.
class HojaRegistrarVenta extends ConsumerStatefulWidget {
  const HojaRegistrarVenta({
    super.key,
    required this.campanaId,
    required this.campanaNombre,
    required this.numeros,
    required this.precioUnitario,
    this.fechaSorteo,
  });

  final String campanaId;
  final String campanaNombre;
  final List<int> numeros;
  final int precioUnitario;
  final String? fechaSorteo;

  @override
  ConsumerState<HojaRegistrarVenta> createState() => _HojaRegistrarVentaState();
}

class _HojaRegistrarVentaState extends ConsumerState<HojaRegistrarVenta> {
  final _claveForm = GlobalKey<FormState>();
  final _nombreControlador = TextEditingController();
  final _telefonoControlador = TextEditingController();
  final _operacionControlador = TextEditingController();

  String _destino = 'efectivo';
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _nombreControlador.dispose();
    _telefonoControlador.dispose();
    _operacionControlador.dispose();
    super.dispose();
  }

  int get _total => widget.precioUnitario * widget.numeros.length;

  Future<void> _confirmar() async {
    if (!_claveForm.currentState!.validate()) return;

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final res = await ref.read(apiProvider).registrarVenta(
        widget.campanaId,
        {
          'numeros': widget.numeros,
          'comprador': {
            'nombre': _nombreControlador.text.trim(),
            'telefono': _telefonoControlador.text.trim(),
          },
          'destino_cobro': _destino,
        },
      );

      // Refrescar estado en segundo plano
      ref.invalidate(numerosProvider(widget.campanaId));
      ref.invalidate(ventasProvider(widget.campanaId));
      ref.invalidate(recaudacionProvider(widget.campanaId));
      ref.invalidate(campanaProvider(widget.campanaId));

      if (!mounted) return;
      Navigator.of(context).pop(true); // Cerrar hoja

      // Abrir billete de compra
      final comprador = res['comprador'] as Map<String, dynamic>;
      final estaPagado = (res['total_cobrado'] as int? ?? 0) > 0;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PantallaBillete(
            campanaNombre: widget.campanaNombre,
            numeros: widget.numeros,
            importe: _total,
            compradorNombre: comprador['nombre'] as String? ?? _nombreControlador.text.trim(),
            compradorTelefono: _telefonoControlador.text.trim(),
            vendedorNombre: res['vendedor_nombre'] as String? ?? 'Vendedor',
            codigoCorto: res['codigo_corto'] as String? ?? '------',
            estaPagado: estaPagado,
            fechaSorteo: widget.fechaSorteo,
          ),
        ),
      );
    } on ErrorApi catch (e) {
      setState(() => _error = e.mensaje);
    } catch (_) {
      setState(() => _error = 'No pudimos registrar la venta. Fijate si tenés señal.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final numsStr = widget.numeros.map((n) => n.toString().padLeft(2, '0')).join(', ');

    return MitiHoja(
      titulo: 'REGISTRAR VENTA',
      subtitulo: '${widget.numeros.length} ${widget.numeros.length == 1 ? 'NÚMERO' : 'NÚMEROS'} ($numsStr)',
      child: Form(
        key: _claveForm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Resumen de importe
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.papelHundido,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('TOTAL A COBRAR', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                  Text(plata(_total), style: t.importe.copyWith(color: c.tinta, fontSize: 24)),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Datos del comprador
            Text('DATOS DEL COMPRADOR', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
            const SizedBox(height: 8),

            TextFormField(
              controller: _nombreControlador,
              textCapitalization: TextCapitalization.words,
              style: t.cuerpo.copyWith(color: c.tinta),
              decoration: InputDecoration(
                labelText: 'Nombre y apellido',
                labelStyle: t.etiqueta.copyWith(color: c.tintaSuave),
                prefixIcon: Icon(Icons.person_outline, color: c.tinta),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: c.tinta, width: 2),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().length < 2) return 'Escribí el nombre del comprador';
                return null;
              },
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _telefonoControlador,
              keyboardType: TextInputType.phone,
              style: t.cuerpo.copyWith(color: c.tinta),
              decoration: InputDecoration(
                labelText: 'Teléfono / WhatsApp',
                labelStyle: t.etiqueta.copyWith(color: c.tintaSuave),
                prefixIcon: Icon(Icons.phone_outlined, color: c.tinta),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: c.tinta, width: 2),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().length < 6) return 'Escribí un teléfono para mandarle el billete';
                return null;
              },
            ),
            const SizedBox(height: 20),

            // Destino del dinero
            Text('¿DÓNDE ENTRÓ EL DINERO?', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
            const SizedBox(height: 8),
            MitiDestinoDinero(
              seleccionado: _destino,
              onCambio: (nuevo) => setState(() => _destino = nuevo),
            ),

            if (_destino == 'cuenta_principal') ...[
              const SizedBox(height: 8),
              Text(
                'El dueño de la cuenta principal deberá confirmar que recibió la transferencia.',
                style: t.pie.copyWith(color: c.tintaSuave),
              ),
            ],

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
              texto: 'Vender y crear billete',
              cargando: _cargando,
              onTap: _cargando ? null : _confirmar,
            ),
          ],
        ),
      ),
    );
  }
}
