import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';

/// Pantalla del billete / talón para enviar al comprador.
class PantallaBillete extends StatelessWidget {
  const PantallaBillete({
    super.key,
    required this.campanaNombre,
    required this.numeros,
    required this.importe,
    required this.compradorNombre,
    required this.compradorTelefono,
    required this.vendedorNombre,
    required this.codigoCorto,
    required this.estaPagado,
    this.fechaSorteo,
  });

  final String campanaNombre;
  final List<int> numeros;
  final int importe;
  final String compradorNombre;
  final String? compradorTelefono;
  final String vendedorNombre;
  final String codigoCorto;
  final bool estaPagado;
  final String? fechaSorteo;

  String _armarTextoCompartir() {
    final numsStr = numeros.map((n) => n.toString().padLeft(2, '0')).join(', ');
    final estado = estaPagado ? 'PAGADO' : 'PENDIENTE DE PAGO';
    return '¡Hola $compradorNombre! Acá tenés tu comprobante de la campaña:\n\n'
        '🎟️ *$campanaNombre*\n'
        '🔢 Números: *$numsStr*\n'
        '💰 Importe: *${plata(importe)}* ($estado)\n'
        '🔑 Código: *$codigoCorto*\n'
        '👤 Vendedor: $vendedorNombre\n'
        '${fechaSorteo != null ? '📅 Sorteo: $fechaSorteo\n' : ''}'
        '\n¡Muchas gracias por colaborar!';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final numsStr = numeros.map((n) => n.toString().padLeft(2, '0')).join(' · ');

    return Scaffold(
      appBar: AppBar(
        title: Text('BILLETE DE COMPRA', style: t.seccion.copyWith(color: c.tinta)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.tinta),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            // Billete estilo talonario
            Container(
              decoration: BoxDecoration(
                color: c.hoja,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.tinta, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: c.tinta.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Encabezado del talón
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: c.tinta,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            campanaNombre.toUpperCase(),
                            style: t.titular.copyWith(
                              color: c.tintaSobre,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            border: Border.all(color: c.tintaSobre, width: 1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#$codigoCorto',
                            style: t.etiqueta.copyWith(
                              color: c.tintaSobre,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Cuerpo del talón
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('COMPRADOR', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                                  const SizedBox(height: 2),
                                  Text(
                                    compradorNombre,
                                    style: t.seccion.copyWith(color: c.tinta, fontSize: 20),
                                  ),
                                  if (compradorTelefono != null && compradorTelefono!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      compradorTelefono!,
                                      style: t.cuerpo.copyWith(color: c.tintaSuave, fontSize: 13),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // Sello de PAGADO o A PAGAR
                            Transform.rotate(
                              angle: -0.1,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: estaPagado ? c.ok : c.sello,
                                    width: 2.5,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  estaPagado ? 'PAGADO' : 'A PAGAR',
                                  style: t.titular.copyWith(
                                    color: estaPagado ? c.ok : c.sello,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),
                        const MitiTroquel(grosor: 1.5),
                        const SizedBox(height: 18),

                        // Números asignados
                        Text(
                          numeros.length == 1 ? 'NÚMERO ASIGNADO' : 'NÚMEROS ASIGNADOS',
                          style: t.sobrelinea.copyWith(color: c.tintaSuave),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            numsStr,
                            style: t.importe.copyWith(
                              color: c.tinta,
                              fontSize: numeros.length > 3 ? 32 : 44,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('TOTAL', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                                const SizedBox(height: 2),
                                Text(
                                  plata(importe),
                                  style: t.importe.copyWith(color: c.tinta, fontSize: 26),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('VENDEDOR', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                                const SizedBox(height: 2),
                                Text(
                                  vendedorNombre,
                                  style: t.cuerpo.copyWith(color: c.tinta, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Pie troquelado
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: c.papelHundido,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified_outlined, size: 16, color: c.tintaSuave),
                        const SizedBox(width: 6),
                        Text(
                          'COMPROBANTE VÁLIDO DE LA CAMPAÑA',
                          style: t.pie.copyWith(color: c.tintaSuave, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Botón para copiar texto del comprobante
            MitiBoton(
              texto: 'Copiar mensaje para WhatsApp',
              icono: Icons.copy,
              onTap: () {
                Clipboard.setData(ClipboardData(text: _armarTextoCompartir()));
                mostrarAviso(context, 'Mensaje del billete copiado al portapapeles');
              },
            ),

            const SizedBox(height: 12),

            MitiBoton(
              texto: 'Listo',
              secundario: true,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
