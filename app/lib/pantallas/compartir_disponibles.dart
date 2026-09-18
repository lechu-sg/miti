import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';

/// Generador de imagen con la grilla de números disponibles para compartir en redes (historias o post).
class PantallaCompartirDisponibles extends StatefulWidget {
  const PantallaCompartirDisponibles({
    super.key,
    required this.campanaNombre,
    required this.precioUnitario,
    required this.numeros,
    this.fechaSorteo,
  });

  final String campanaNombre;
  final int precioUnitario;
  final List<Map<String, dynamic>> numeros;
  final String? fechaSorteo;

  @override
  State<PantallaCompartirDisponibles> createState() => _PantallaCompartirDisponiblesState();
}

class _PantallaCompartirDisponiblesState extends State<PantallaCompartirDisponibles> {
  bool _formatoHistoria = true; // true: 9:16 (1080x1920), false: 4:5 (1080x1350)

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final ahora = DateFormat('dd/MM HH:mm').format(DateTime.now());

    final libres = widget.numeros.where((n) => n['estado'] == 'libre').length;
    final vendidosOReservados = widget.numeros.length - libres;

    return Scaffold(
      appBar: AppBar(
        title: Text('COMPARTIR DISPONIBLES', style: t.seccion.copyWith(color: c.tinta)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.tinta),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Selector de formato (Historia 9:16 vs Post 4:5)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  MitiChip(
                    texto: 'Historia (9:16)',
                    activo: _formatoHistoria,
                    onTap: () => setState(() => _formatoHistoria = true),
                  ),
                  const SizedBox(width: 8),
                  MitiChip(
                    texto: 'Publicación (4:5)',
                    activo: !_formatoHistoria,
                    onTap: () => setState(() => _formatoHistoria = false),
                  ),
                ],
              ),
            ),

            // Visualización previa del canvas (siempre en paleta clara según la skill)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AspectRatio(
                    aspectRatio: _formatoHistoria ? 9 / 16 : 4 / 5,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBF9F4), // Papel claro siempre
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF1E2A3A), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Encabezado
                          Text(
                            widget.campanaNombre.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'BigShoulders',
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E2A3A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${plata(widget.precioUnitario)} cada número · $libres disponibles',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF5F5A4E),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Grilla de números
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return GridView.builder(
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 10,
                                    crossAxisSpacing: 3,
                                    mainAxisSpacing: 3,
                                    childAspectRatio: 1.1,
                                  ),
                                  itemCount: widget.numeros.length,
                                  itemBuilder: (context, i) {
                                    final num = widget.numeros[i];
                                    final n = num['numero'] as int;
                                    final estado = num['estado'] as String;
                                    // Regla §8.1: reservados se muestran igual que vendidos (casilla en blanco/vendido sin número)
                                    final estaLibre = estado == 'libre';

                                    return Container(
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: estaLibre ? Colors.white : const Color(0xFFE4DDCB),
                                        borderRadius: BorderRadius.circular(2),
                                        border: estaLibre
                                            ? Border.all(color: const Color(0xFF1E2A3A), width: 1)
                                            : null,
                                      ),
                                      child: estaLibre
                                          ? Text(
                                              n.toString().padLeft(2, '0'),
                                              style: const TextStyle(
                                                fontFamily: 'BigShoulders',
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF1E2A3A),
                                              ),
                                            )
                                          : null, // Casilla en blanco
                                    );
                                  },
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Pie de imagen
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                widget.fechaSorteo != null
                                    ? 'Sorteo: ${widget.fechaSorteo}'
                                    : '¡Pedí tu número!',
                                style: const TextStyle(
                                  fontFamily: 'Figtree',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E2A3A),
                                ),
                              ),
                              Text(
                                'Actualizado $ahora',
                                style: const TextStyle(
                                  fontFamily: 'Figtree',
                                  fontSize: 10,
                                  color: Color(0xFF5F5A4E),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Botón inferior
            Padding(
              padding: const EdgeInsets.all(20),
              child: MitiBoton(
                texto: 'Guardar o compartir imagen',
                icono: Icons.download_outlined,
                onTap: () {
                  mostrarAviso(context, 'Imagen lista con $libres libres y $vendidosOReservados ocupados.');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
