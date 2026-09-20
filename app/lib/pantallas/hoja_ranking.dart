import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';

Future<void> mostrarHojaRanking(
  BuildContext context, {
  required String campanaId,
  required String campanaNombre,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => HojaRanking(
      campanaId: campanaId,
      campanaNombre: campanaNombre,
    ),
  );
}

class HojaRanking extends ConsumerWidget {
  const HojaRanking({
    super.key,
    required this.campanaId,
    required this.campanaNombre,
  });

  final String campanaId;
  final String campanaNombre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.color;
    final t = context.texto;
    final rankingAsync = ref.watch(rankingProvider(campanaId));

    return MitiHoja(
      titulo: 'POSICIONES DEL EQUIPO',
      subtitulo: campanaNombre,
      child: rankingAsync.when(
        loading: () => Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: CircularProgressIndicator(color: c.sello),
          ),
        ),
        error: (err, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Center(
            child: Text(
              'No pudimos cargar el ranking. Revisá tu conexión.',
              style: t.cuerpo.copyWith(color: c.sello),
            ),
          ),
        ),
        data: (datos) {
          final items = (datos['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          final esRifa = (datos['tipo'] as String?) == 'rifa';

          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: MitiVacio(
                titulo: 'Sin ventas aún',
                detalle: 'Todavía no hay ventas registradas para armar el ranking.',
              ),
            );
          }

          final maxCantidad = items.fold<int>(0, (prev, it) {
            final cant = (it['cantidad'] as num?)?.toInt() ?? 0;
            return cant > prev ? cant : prev;
          });

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tabla de motivación grupal. No altera el reparto de la liquidación (§7.7).',
                style: t.pie.copyWith(color: c.tintaSuave),
              ),
              const SizedBox(height: 16),

              // Podio Top 3
              if (items.isNotEmpty) _construirPodio(context, items, esRifa),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('TABLA GENERAL', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                  Text('${items.length} integrantes', style: t.etiqueta.copyWith(color: c.tintaSuave)),
                ],
              ),
              const SizedBox(height: 8),
              MitiTroquel(color: c.tinta, grosor: 1.5),

              // Filas de integrantes
              for (final it in items)
                _FilaRanking(
                  item: it,
                  esRifa: esRifa,
                  maxCantidad: maxCantidad,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _construirPodio(
    BuildContext context,
    List<Map<String, dynamic>> items,
    bool esRifa,
  ) {
    final c = context.color;
    final primero = items.isNotEmpty ? items[0] : null;
    final segundo = items.length > 1 ? items[1] : null;
    final tercero = items.length > 2 ? items[2] : null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: c.papelHundido,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.troquel),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 2° Puesto (Plata)
          if (segundo != null)
            _TarjetaPodio(
              posicion: 2,
              item: segundo,
              medalla: '🥈',
              altura: 110,
              colorMedalla: const Color(0xFF9E9E9E),
              esRifa: esRifa,
            )
          else
            const SizedBox(width: 80),

          // 1° Puesto (Oro)
          if (primero != null)
            _TarjetaPodio(
              posicion: 1,
              item: primero,
              medalla: '🥇',
              altura: 135,
              colorMedalla: const Color(0xFFD4AF37),
              esRifa: esRifa,
              destacado: true,
            ),

          // 3° Puesto (Bronce)
          if (tercero != null)
            _TarjetaPodio(
              posicion: 3,
              item: tercero,
              medalla: '🥉',
              altura: 95,
              colorMedalla: const Color(0xFFCD7F32),
              esRifa: esRifa,
            )
          else
            const SizedBox(width: 80),
        ],
      ),
    );
  }
}

class _TarjetaPodio extends StatelessWidget {
  const _TarjetaPodio({
    required this.posicion,
    required this.item,
    required this.medalla,
    required this.altura,
    required this.colorMedalla,
    required this.esRifa,
    this.destacado = false,
  });

  final int posicion;
  final Map<String, dynamic> item;
  final String medalla;
  final double altura;
  final Color colorMedalla;
  final bool esRifa;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final nombre = item['nombre'] as String? ?? 'Usuario';
    final cant = (item['cantidad'] as num?)?.toInt() ?? 0;

    return SizedBox(
      width: destacado ? 100 : 85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(medalla, style: TextStyle(fontSize: destacado ? 32 : 24)),
          const SizedBox(height: 4),
          MitiIniciales(iniciales(nombre), medida: destacado ? 44 : 36),
          const SizedBox(height: 6),
          Text(
            nombre,
            style: t.cuerpo.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: destacado ? 14 : 12,
              color: c.tinta,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            '$cant ${esRifa ? (cant == 1 ? 'número' : 'números') : (cant == 1 ? 'unidad' : 'unidades')}',
            style: t.pie.copyWith(
              color: c.tintaSuave,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Container(
            height: altura * 0.35,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: destacado ? c.tinta : c.troquel,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$posicion°',
              style: TextStyle(
                fontFamily: 'BigShoulders',
                color: destacado ? Colors.white : c.tinta,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaRanking extends StatelessWidget {
  const _FilaRanking({
    required this.item,
    required this.esRifa,
    required this.maxCantidad,
  });

  final Map<String, dynamic> item;
  final bool esRifa;
  final int maxCantidad;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    final pos = (item['posicion'] as num?)?.toInt() ?? 1;
    final nombre = item['nombre'] as String? ?? 'Participante';
    final cant = (item['cantidad'] as num?)?.toInt() ?? 0;
    final total = (item['total_vendido'] as num?)?.toInt() ?? 0;

    final ratio = maxCantidad > 0 ? (cant / maxCantidad).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.troquel))),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: pos <= 3 ? c.tinta : c.papelHundido,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: c.troquel),
            ),
            child: Text(
              '$pos°',
              style: TextStyle(
                fontFamily: 'BigShoulders',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: pos <= 3 ? Colors.white : c.tinta,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        nombre,
                        style: t.cuerpo.copyWith(fontWeight: FontWeight.w600, color: c.tinta),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      plata(total),
                      style: t.cifra.copyWith(color: c.tinta, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: ratio,
                          backgroundColor: c.troquel,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            pos == 1 ? c.sello : c.tinta,
                          ),
                          minHeight: 5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$cant ${esRifa ? (cant == 1 ? 'número' : 'números') : (cant == 1 ? 'u.' : 'u.')}',
                      style: t.pie.copyWith(color: c.tintaSuave, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
