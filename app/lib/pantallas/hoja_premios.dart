import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/componentes.dart';
import '../nucleo/tema.dart';

Future<List<String>?> mostrarHojaPremios(
  BuildContext context, {
  required String campanaId,
  required List<String> premiosActuales,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => HojaPremios(
      campanaId: campanaId,
      premiosIniciales: premiosActuales,
    ),
  );
}

class HojaPremios extends ConsumerStatefulWidget {
  const HojaPremios({
    super.key,
    required this.campanaId,
    required this.premiosIniciales,
  });

  final String campanaId;
  final List<String> premiosIniciales;

  @override
  ConsumerState<HojaPremios> createState() => _HojaPremiosState();
}

class _HojaPremiosState extends ConsumerState<HojaPremios> {
  late final List<TextEditingController> _controladores;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final iniciales = widget.premiosIniciales.isNotEmpty
        ? widget.premiosIniciales
        : ['Primer Premio'];
    _controladores = iniciales
        .map((p) => TextEditingController(text: p))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _controladores) {
      c.dispose();
    }
    super.dispose();
  }

  void _agregarPremio() {
    setState(() {
      final orden = _controladores.length + 1;
      _controladores.add(TextEditingController(text: '$orden° Premio'));
    });
  }

  void _quitarPremio(int indice) {
    if (_controladores.length <= 1) return;
    setState(() {
      final c = _controladores.removeAt(indice);
      c.dispose();
    });
  }

  Future<void> _guardar() async {
    final premios = _controladores
        .map((c) => c.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (premios.isEmpty) {
      setState(() => _error = 'Tenés que ingresar al menos un premio');
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    try {
      final guardados = await ref.read(apiProvider).editarPremios(
            widget.campanaId,
            premios,
          );
      if (mounted) {
        mostrarAviso(context, 'Premios actualizados correctamente');
        Navigator.of(context).pop(guardados);
      }
    } on ErrorApi catch (e) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = e.mensaje;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = 'No pudimos conectarnos. ¿Tenés señal?';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    return MitiHoja(
      titulo: 'PREMIOS DE LA RIFA',
      subtitulo: 'CONFIGURACIÓN',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Configurá los premios en orden del sorteo (1°, 2°, 3°, etc.). '
              'Podés agregar o quitar premios mientras no se haya sorteado.',
              style: t.pie.copyWith(color: c.tintaSuave),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _controladores.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  return Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: c.papelHundido,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.troquel),
                        ),
                        child: Text(
                          '${index + 1}°',
                          style: t.etiqueta.copyWith(
                            fontWeight: FontWeight.bold,
                            color: c.tinta,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _controladores[index],
                          textCapitalization: TextCapitalization.sentences,
                          style: t.cuerpo.copyWith(color: c.tinta),
                          decoration: InputDecoration(
                            hintText: 'Ej: Canasta navideña, Smart TV...',
                            hintStyle: t.cuerpo.copyWith(color: c.tintaSuave.withValues(alpha: 0.6)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: c.tinta, width: 2),
                            ),
                          ),
                        ),
                      ),
                      if (_controladores.length > 1) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: c.sello, size: 22),
                          tooltip: 'Quitar premio',
                          onPressed: () => _quitarPremio(index),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _agregarPremio,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.tintaSuave.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 18, color: c.tinta),
                    const SizedBox(width: 6),
                    Text(
                      'Agregar otro premio',
                      style: t.etiqueta.copyWith(color: c.tinta, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: t.pie.copyWith(color: c.sello, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            MitiBoton(
              texto: 'Guardar premios',
              cargando: _guardando,
              onTap: _guardar,
            ),
          ],
        ),
      ),
    );
  }
}
