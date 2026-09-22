import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';
import '../nucleo/publicidad.dart';

class PantallaMuroAvisos extends ConsumerStatefulWidget {
  const PantallaMuroAvisos({
    super.key,
    required this.campanaId,
    required this.campanaNombre,
    this.esAdmin = false,
  });

  final String campanaId;
  final String campanaNombre;
  final bool esAdmin;

  @override
  ConsumerState<PantallaMuroAvisos> createState() => _PantallaMuroAvisosState();
}

class _PantallaMuroAvisosState extends ConsumerState<PantallaMuroAvisos> {
  Future<void> _abrirNuevoAviso() async {
    final mensajeCtrl = TextEditingController();
    var fijado = false;
    String? error;
    var publicando = false;

    final publicado = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final c = context.color;
            final t = context.texto;

            return AlertDialog(
              backgroundColor: c.papel,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              title: Text('NUEVO AVISO DEL GRUPO', style: t.seccion.copyWith(color: c.tinta)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Se enviará a todos los integrantes activos de la campaña.',
                    style: t.pie.copyWith(color: c.tintaSuave),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: mensajeCtrl,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    style: t.cuerpo.copyWith(color: c.tinta),
                    decoration: InputDecoration(
                      hintText: 'Escribí el comunicado para el grupo...',
                      hintStyle: t.cuerpo.copyWith(color: c.tintaSuave.withValues(alpha: 0.5)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => setDialogState(() => fijado = !fijado),
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      children: [
                        Checkbox(
                          value: fijado,
                          onChanged: (val) => setDialogState(() => fijado = val ?? false),
                          activeColor: c.sello,
                        ),
                        Text('Fijar al inicio del muro', style: t.etiqueta.copyWith(color: c.tinta)),
                      ],
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: t.pie.copyWith(color: c.sello, fontWeight: FontWeight.bold)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: publicando ? null : () => Navigator.of(context).pop(false),
                  child: Text('Cancelar', style: t.etiqueta.copyWith(color: c.tintaSuave)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.tinta,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: publicando
                      ? null
                      : () async {
                          final texto = mensajeCtrl.text.trim();
                          if (texto.isEmpty) {
                            setDialogState(() => error = 'Escribí un mensaje');
                            return;
                          }
                          setDialogState(() {
                            publicando = true;
                            error = null;
                          });
                          try {
                            await ref.read(apiProvider).crearAviso(
                                  widget.campanaId,
                                  mensaje: texto,
                                  fijado: fijado,
                                );
                            if (ctx.mounted) Navigator.of(context).pop(true);
                          } on ErrorApi catch (e) {
                            setDialogState(() {
                              publicando = false;
                              error = e.mensaje;
                            });
                          } catch (_) {
                            setDialogState(() {
                              publicando = false;
                              error = 'No se pudo publicar el aviso';
                            });
                          }
                        },
                  child: publicando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text('Publicar', style: t.etiqueta.copyWith(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (publicado == true && mounted) {
      ref.invalidate(avisosProvider(widget.campanaId));
      mostrarAviso(context, 'Aviso publicado en el muro');
    }
  }

  Future<void> _eliminarAviso(String avisoId) async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar aviso?'),
        content: const Text('El aviso se borrará del muro de la campaña.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (seguro == true && mounted) {
      try {
        await ref.read(apiProvider).eliminarAviso(widget.campanaId, avisoId);
        ref.invalidate(avisosProvider(widget.campanaId));
        if (mounted) mostrarAviso(context, 'Aviso eliminado');
      } catch (_) {
        if (mounted) mostrarAviso(context, 'No se pudo eliminar el aviso', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final miId = ref.watch(sesionProvider).valueOrNull?['id'];
    final avisosAsync = ref.watch(avisosProvider(widget.campanaId));

    return Scaffold(
      bottomNavigationBar: BannerMiti(mostrar: ref.watch(publicidadEnCampanaProvider(widget.campanaId))),
      appBar: AppBar(
        title: Text('MURO DE AVISOS', style: t.seccion.copyWith(color: c.tinta)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.tinta),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (widget.esAdmin)
            IconButton(
              icon: Icon(Icons.add_comment_outlined, color: c.tinta),
              tooltip: 'Publicar aviso',
              onPressed: _abrirNuevoAviso,
            ),
        ],
      ),
      body: avisosAsync.when(
        loading: () => Center(child: CircularProgressIndicator(color: c.sello)),
        error: (err, _) => Center(
          child: Text(
            'No se pudieron cargar los avisos',
            style: t.cuerpo.copyWith(color: c.sello),
          ),
        ),
        data: (avisos) {
          if (avisos.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const MitiVacio(
                      titulo: 'Sin comunicados',
                      detalle: 'Todavía no hay comunicados publicados en el muro.',
                    ),
                    if (widget.esAdmin) ...[
                      const SizedBox(height: 16),
                      MitiBoton(
                        texto: 'Publicar primer aviso',
                        icono: Icons.campaign_rounded,
                        onTap: _abrirNuevoAviso,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(avisosProvider(widget.campanaId)),
            color: c.sello,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
              itemCount: avisos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final av = avisos[index];
                final id = av['id']?.toString() ?? '';
                final autorId = av['autor_id']?.toString();
                final autorNombre = av['autor_nombre'] as String? ?? 'Administración';
                final mensaje = av['mensaje'] as String? ?? '';
                final fijado = av['fijado'] as bool? ?? false;
                final creadoStr = av['creado'] as String?;
                final fecha = creadoStr != null ? DateTime.tryParse(creadoStr)?.toLocal() : null;
                final fechaFormateada = fecha != null
                    ? DateFormat('dd/MM HH:mm').format(fecha)
                    : '';

                final puedoEliminar = widget.esAdmin || (autorId != null && autorId == miId);

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: fijado ? c.mostaza.withValues(alpha: 0.08) : c.papelHundido,
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
                          if (fijado) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: c.mostaza,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.push_pin, size: 12, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text(
                                    'FIJADO',
                                    style: TextStyle(
                                      fontFamily: 'Figtree',
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          MitiIniciales(iniciales(autorNombre), medida: 24),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              autorNombre,
                              style: t.cuerpo.copyWith(
                                fontWeight: FontWeight.bold,
                                color: c.tinta,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (fechaFormateada.isNotEmpty)
                            Text(
                              fechaFormateada,
                              style: t.pie.copyWith(color: c.tintaSuave, fontSize: 11),
                            ),
                          if (puedoEliminar) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 18, color: c.tintaSuave),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              onPressed: () => _eliminarAviso(id),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        mensaje,
                        style: t.cuerpo.copyWith(color: c.tinta, height: 1.35),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: widget.esAdmin
          ? FloatingActionButton.extended(
              backgroundColor: c.tinta,
              foregroundColor: Colors.white,
              onPressed: _abrirNuevoAviso,
              icon: const Icon(Icons.add),
              label: Text('Nuevo aviso', style: t.etiqueta.copyWith(color: Colors.white)),
            )
          : null,
    );
  }
}
