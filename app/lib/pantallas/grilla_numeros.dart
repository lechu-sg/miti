import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';
import '../nucleo/publicidad.dart';
import 'compartir_disponibles.dart';
import 'registrar_venta.dart';

/// Grilla interactiva de 10 columnas con los números de la rifa.
class PantallaGrillaNumeros extends ConsumerStatefulWidget {
  const PantallaGrillaNumeros({
    super.key,
    required this.campanaId,
    required this.campanaNombre,
    required this.precioUnitario,
    this.fechaSorteo,
    this.esAdmin = false,
  });

  final String campanaId;
  final String campanaNombre;
  final int precioUnitario;
  final String? fechaSorteo;
  final bool esAdmin;

  @override
  ConsumerState<PantallaGrillaNumeros> createState() => _PantallaGrillaNumerosState();
}

class _PantallaGrillaNumerosState extends ConsumerState<PantallaGrillaNumeros> {
  final Set<int> _seleccionados = {};
  String _filtro = 'todos'; // todos, libres, reservados, vendidos

  void _alternar(int n) {
    setState(() {
      if (_seleccionados.contains(n)) {
        _seleccionados.remove(n);
      } else {
        _seleccionados.add(n);
      }
    });
  }

  void _abrirVenta() {
    if (_seleccionados.isEmpty) return;
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: HojaRegistrarVenta(
          campanaId: widget.campanaId,
          campanaNombre: widget.campanaNombre,
          numeros: _seleccionados.toList()..sort(),
          precioUnitario: widget.precioUnitario,
          fechaSorteo: widget.fechaSorteo,
        ),
      ),
    ).then((vendio) {
      if (vendio == true) {
        setState(() => _seleccionados.clear());
      }
    });
  }

  void _abrirReserva() {
    if (_seleccionados.isEmpty) return;
    final notaControlador = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final c = context.color;
        final t = context.texto;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: MitiHoja(
            titulo: 'RESERVAR NÚMEROS',
            subtitulo: '${_seleccionados.length} SELECCIONADOS (48 HORAS)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Los números reservados no podrán ser vendidos por otros integrantes durante 48 horas.',
                  style: t.cuerpo.copyWith(color: c.tintaSuave),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notaControlador,
                  decoration: InputDecoration(
                    labelText: 'Nota opcional (ej: Para mi prima)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                const SizedBox(height: 20),
                MitiBoton(
                  texto: 'Confirmar reserva',
                  onTap: () async {
                    Navigator.of(context).pop();
                    try {
                      for (final n in _seleccionados) {
                        await ref.read(apiProvider).reservarNumero(
                              widget.campanaId,
                              n,
                              nota: notaControlador.text.trim().isEmpty ? null : notaControlador.text.trim(),
                            );
                      }
                      ref.invalidate(numerosProvider(widget.campanaId));
                      ref.invalidate(recaudacionProvider(widget.campanaId));
                      setState(() => _seleccionados.clear());
                      if (mounted) mostrarAviso(context, 'Números reservados por 48 h');
                    } on ErrorApi catch (e) {
                      if (mounted) mostrarAviso(context, e.mensaje, error: true);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _verDetalleNumero(Map<String, dynamic> num) {
    final numero = num['numero'] as int;
    final estado = num['estado'] as String;
    final reservaNota = num['reserva_nota'] as String?;
    final reservadoPorMi = num['reservado_por_mi'] as bool? ?? false;
    final vendedor = num['vendedor_nombre'] as String?;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final c = context.color;
        final t = context.texto;
        return MitiHoja(
          titulo: 'NÚMERO ${numero.toString().padLeft(2, '0')}',
          subtitulo: estado.toUpperCase(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (estado == 'reservado') ...[
                Text(
                  reservadoPorMi ? 'Reservado por vos' : 'Reservado por otro integrante',
                  style: t.seccion.copyWith(color: c.selloTexto, fontSize: 18),
                ),
                if (reservaNota != null && reservaNota.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Nota: "$reservaNota"', style: t.cuerpo.copyWith(color: c.tinta)),
                ],
                const SizedBox(height: 16),
                if (reservadoPorMi || widget.esAdmin)
                  MitiBoton(
                    texto: 'Liberar número',
                    secundario: true,
                    onTap: () async {
                      Navigator.of(context).pop();
                      try {
                        await ref.read(apiProvider).liberarNumero(widget.campanaId, numero);
                        ref.invalidate(numerosProvider(widget.campanaId));
                        ref.invalidate(recaudacionProvider(widget.campanaId));
                        if (mounted) mostrarAviso(context, 'Número $numero liberado');
                      } on ErrorApi catch (e) {
                        if (mounted) mostrarAviso(context, e.mensaje, error: true);
                      }
                    },
                  ),
              ] else if (estado == 'vendido') ...[
                Text('Vendido', style: t.seccion.copyWith(color: c.tinta, fontSize: 18)),
                if (vendedor != null) ...[
                  const SizedBox(height: 4),
                  Text('Vendido por: $vendedor', style: t.cuerpo.copyWith(color: c.tintaSuave)),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final asyncNums = ref.watch(numerosProvider(widget.campanaId));

    return Scaffold(
      bottomNavigationBar: BannerMiti(mostrar: ref.watch(publicidadEnCampanaProvider(widget.campanaId))),
      appBar: AppBar(
        title: Text(widget.campanaNombre, style: t.seccion.copyWith(color: c.tinta)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Compartir disponibles',
            icon: Icon(Icons.share_outlined, color: c.tinta),
            onPressed: () {
              final nums = asyncNums.valueOrNull ?? [];
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PantallaCompartirDisponibles(
                    campanaNombre: widget.campanaNombre,
                    precioUnitario: widget.precioUnitario,
                    fechaSorteo: widget.fechaSorteo,
                    numeros: nums.cast<Map<String, dynamic>>(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: asyncNums.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => MitiVacio(
          titulo: 'No pudimos cargar los números',
          detalle: e is ErrorApi ? e.mensaje : 'Fijate si tenés conexión.',
          accion: MitiBoton(
            texto: 'Reintentar',
            secundario: true,
            onTap: () => ref.invalidate(numerosProvider(widget.campanaId)),
          ),
        ),
        data: (lista) {
          final todos = lista.cast<Map<String, dynamic>>();
          final libres = todos.where((n) => n['estado'] == 'libre').toList();
          final reservados = todos.where((n) => n['estado'] == 'reservado').toList();
          final vendidos = todos.where((n) => n['estado'] == 'vendido').toList();

          final filtrados = switch (_filtro) {
            'libres' => libres,
            'reservados' => reservados,
            'vendidos' => vendidos,
            _ => todos,
          };

          return Column(
            children: [
              // Botón destacado para compartir números en redes
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: MitiBoton(
                  texto: 'Compartir números en redes',
                  icono: Icons.photo_camera_back_outlined,
                  secundario: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PantallaCompartirDisponibles(
                          campanaNombre: widget.campanaNombre,
                          precioUnitario: widget.precioUnitario,
                          fechaSorteo: widget.fechaSorteo,
                          numeros: todos,
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Chips de filtro
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    MitiChip(
                      texto: 'Todos ${todos.length}',
                      activo: _filtro == 'todos',
                      onTap: () => setState(() => _filtro = 'todos'),
                    ),
                    const SizedBox(width: 8),
                    MitiChip(
                      texto: 'Libres ${libres.length}',
                      activo: _filtro == 'libres',
                      onTap: () => setState(() => _filtro = 'libres'),
                    ),
                    const SizedBox(width: 8),
                    MitiChip(
                      texto: 'Reservados ${reservados.length}',
                      activo: _filtro == 'reservados',
                      onTap: () => setState(() => _filtro = 'reservados'),
                    ),
                    const SizedBox(width: 8),
                    MitiChip(
                      texto: 'Vendidos ${vendidos.length}',
                      activo: _filtro == 'vendidos',
                      onTap: () => setState(() => _filtro = 'vendidos'),
                    ),
                  ],
                ),
              ),

              // Grilla de 10 columnas
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 10,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: filtrados.length,
                  itemBuilder: (context, i) {
                    final item = filtrados[i];
                    final num = item['numero'] as int;
                    final estado = item['estado'] as String;
                    final estaSeleccionado = _seleccionados.contains(num);

                    return MitiCeldaNumero(
                      numero: num,
                      estado: estado,
                      seleccionado: estaSeleccionado,
                      onTap: () {
                        if (estado == 'libre' || (estado == 'reservado' && (item['reservado_por_mi'] == true))) {
                          _alternar(num);
                        } else {
                          _verDetalleNumero(item);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),

      // Barra inferior flotante de acción cuando hay selección
      bottomSheet: _seleccionados.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: c.hoja,
                border: Border(top: BorderSide(color: c.tinta, width: 1.5)),
                boxShadow: [
                  BoxShadow(
                    color: c.tinta.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_seleccionados.length} ${_seleccionados.length == 1 ? 'NÚMERO' : 'NÚMEROS'}',
                            style: t.sobrelinea.copyWith(color: c.tintaSuave),
                          ),
                          Text(
                            plata(widget.precioUnitario * _seleccionados.length),
                            style: t.importe.copyWith(color: c.tinta, fontSize: 24),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _seleccionados.clear()),
                      child: Text('Limpiar', style: t.etiqueta.copyWith(color: c.tintaSuave)),
                    ),
                    const SizedBox(width: 8),
                    MitiBoton(
                      texto: 'Reservar',
                      secundario: true,
                      onTap: _abrirReserva,
                    ),
                    const SizedBox(width: 8),
                    MitiBoton(
                      texto: 'Vender',
                      onTap: _abrirVenta,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
