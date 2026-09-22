import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../nucleo/base_local.dart';
import '../nucleo/componentes.dart';
import '../nucleo/sincronizador.dart';
import '../nucleo/tema.dart';

/// Hoja para resolver conflictos ocurridos al sincronizar ventas offline (§5 de DEFINICION.md).
class HojaConflictosSync extends ConsumerStatefulWidget {
  const HojaConflictosSync({
    super.key,
    required this.campanaId,
    required this.campanaNombre,
  });

  final String campanaId;
  final String campanaNombre;

  @override
  ConsumerState<HojaConflictosSync> createState() => _HojaConflictosSyncState();
}

class _HojaConflictosSyncState extends ConsumerState<HojaConflictosSync> {
  List<Map<String, dynamic>> _conflictos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final todos = await BaseLocal.instancia.obtenerOutbox(widget.campanaId);
    if (!mounted) return;
    setState(() {
      _conflictos = todos.where((op) => op['estado'] == 'conflicto').toList();
      _cargando = false;
    });
  }

  Future<void> _elegirNuevoNumero(Map<String, dynamic> op) async {
    final payload = op['payload'] as Map<String, dynamic>;
    final comprador = payload['comprador'] as Map<String, dynamic>? ?? {};
    final compNombre = comprador['nombre'] ?? 'Comprador';
    final ctrl = TextEditingController();

    final nuevoNum = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final c = ctx.color;
        final t = ctx.texto;
        return AlertDialog(
          backgroundColor: c.papel,
          title: Text('ELEGIR OTRO NÚMERO', style: t.seccion.copyWith(color: c.tinta)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ingresá un número disponible para $compNombre:',
                style: t.cuerpo.copyWith(color: c.tintaSuave),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Nuevo número',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancelar', style: t.etiqueta.copyWith(color: c.tintaSuave)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: c.sello),
              onPressed: () {
                final n = int.tryParse(ctrl.text.trim());
                if (n != null) Navigator.of(ctx).pop(n);
              },
              child: Text('Asignar', style: t.etiqueta.copyWith(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (nuevoNum != null) {
      final opId = op['id'] as String;
      await ref.read(sincroProvider(widget.campanaId).notifier).resolverConflictoRifa(opId, nuevoNum);
      if (mounted) {
        mostrarAviso(context, 'Número actualizado a $nuevoNum. Reintentando sincronizar...');
        await _cargar();
        if (_conflictos.isEmpty && mounted) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  Future<void> _descartar(Map<String, dynamic> op) async {
    final opId = op['id'] as String;
    await ref.read(sincroProvider(widget.campanaId).notifier).descartarOperacion(opId);
    if (mounted) {
      mostrarAviso(context, 'Venta en conflicto descartada');
      await _cargar();
      if (_conflictos.isEmpty && mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    return MitiHoja(
      titulo: 'CONFLICTOS SIN SEÑAL',
      subtitulo: widget.campanaNombre.toUpperCase(),
      child: _cargando
          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          : _conflictos.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No hay conflictos pendientes de resolución.',
                      style: t.cuerpo.copyWith(color: c.tintaSuave),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Estas ventas se registraron mientras no tenías señal, pero al sincronizar se detectó un conflicto con otra venta simultánea.',
                      style: t.cuerpo.copyWith(color: c.tintaSuave),
                    ),
                    const SizedBox(height: 16),
                    for (final op in _conflictos) ...[
                      _TarjetaConflicto(
                        op: op,
                        onElegirNumero: () => _elegirNuevoNumero(op),
                        onDescartar: () => _descartar(op),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
    );
  }
}

class _TarjetaConflicto extends StatelessWidget {
  const _TarjetaConflicto({
    required this.op,
    required this.onElegirNumero,
    required this.onDescartar,
  });

  final Map<String, dynamic> op;
  final VoidCallback onElegirNumero;
  final VoidCallback onDescartar;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final payload = op['payload'] as Map<String, dynamic>? ?? {};
    final opTipo = op['op'] as String? ?? '';
    final detalle = op['detalle'] as Map<String, dynamic>? ?? {};
    final comprador = payload['comprador'] as Map<String, dynamic>? ?? {};
    final compNombre = comprador['nombre'] as String? ?? 'Comprador';

    final esRifa = opTipo == 'vender_rifa';
    final numsConflicto = (detalle['numeros'] as List?)?.cast<int>() ?? [];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.papel,
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
              Expanded(
                child: Text(
                  esRifa ? 'NÚMERO YA VENDIDO' : 'PRODUCTO NO DISPONIBLE',
                  style: t.sobrelinea.copyWith(color: c.selloTexto),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Comprador: $compNombre',
            style: t.cuerpo.copyWith(fontWeight: FontWeight.bold, color: c.tinta),
          ),
          const SizedBox(height: 4),
          if (esRifa && numsConflicto.isNotEmpty)
            Text(
              'El número ${numsConflicto.join(", ")} ya fue vendido o reservado por otro integrante antes de tu sincronización.',
              style: t.pie.copyWith(color: c.tintaSuave),
            )
          else
            Text(
              op['motivo'] == 'limite_plan'
                  ? 'No entró porque la campaña llegó al tope de ventas de su plan. '
                      'Quien administra la campaña puede mejorarlo desde "Plan de la campaña".'
                  : 'La operación no pudo confirmarse (${op['motivo'] ?? 'conflicto'}).',
              style: t.pie.copyWith(color: c.tintaSuave),
            ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onDescartar,
                child: Text('Descartar', style: t.etiqueta.copyWith(color: c.tintaSuave)),
              ),
              if (esRifa) ...[
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.sello,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: onElegirNumero,
                  child: Text('Elegir otro número', style: t.etiqueta.copyWith(color: Colors.white)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
