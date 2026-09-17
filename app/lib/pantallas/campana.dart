import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';

/// La campaña por dentro: cuánto se juntó, dónde está la plata y quiénes son.
class PantallaCampana extends ConsumerWidget {
  const PantallaCampana({super.key, required this.campanaId});

  final String campanaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.color;
    final t = context.texto;
    final datos = ref.watch(campanaProvider(campanaId));

    return Scaffold(
      body: SafeArea(
        child: datos.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => MitiVacio(
            titulo: 'No pudimos abrir la campaña',
            detalle: e is ErrorApi ? e.mensaje : 'Fijate si tenés señal.',
            accion: MitiBoton(
              texto: 'Volver',
              secundario: true,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          data: (campana) {
            final integrantes = (campana['integrantes'] as List).cast<Map<String, dynamic>>();
            final cajas = (campana['cajas'] as List).cast<Map<String, dynamic>>();
            final activos = integrantes.where((i) => i['estado'] == 'activo').toList();
            final invitados = integrantes.where((i) => i['estado'] == 'invitado').toList();
            final esAdmin = campana['mi_rol'] == 'admin';
            final meta = campana['meta'] as int?;
            final esRifa = campana['tipo'] == 'rifa';
            final config = (campana['config'] as Map).cast<String, dynamic>();

            return RefreshIndicator(
              color: c.sello,
              onRefresh: () async => ref.invalidate(campanaProvider(campanaId)),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.arrow_back, color: c.tinta),
                      ),
                      const Spacer(),
                      if (esAdmin && campana['estado'] == 'borrador')
                        TextButton(
                          onPressed: () => _activar(context, ref),
                          child: Text('Activar', style: t.etiqueta.copyWith(color: c.selloTexto)),
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${esRifa ? 'CAMPAÑA DE NÚMEROS' : 'VENTA DE PRODUCTOS'} · '
                          '${(campana['estado'] as String).toUpperCase()}',
                          style: t.sobrelinea.copyWith(color: c.tintaSuave),
                        ),
                        const SizedBox(height: 4),
                        Text(campana['nombre'] as String, style: t.titular.copyWith(color: c.tinta)),
                        if (esRifa && config.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Números ${config['desde']} al ${config['hasta']} · '
                            '${plata(config['precio'] as int)} cada uno',
                            style: t.cuerpo.copyWith(color: c.tintaSuave),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Todavía no hay ventas: el ticket muestra ceros, pero ya enseña la forma.
                  MitiTicket(
                    sobrelinea: 'Cobrado',
                    importe: plata(0),
                    detalle: 'Vendido ${plata(0)} · falta cobrar ${plata(0)}',
                    progreso: meta == null ? null : 0,
                    pie: meta == null ? 'Sin meta definida' : 'Meta ${plata(meta)}',
                    talonArriba: '${activos.length}',
                    talonAbajo: activos.length == 1 ? 'integrante' : 'integrantes',
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.papelHundido,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.construction_outlined, size: 18, color: c.tintaSuave),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            esRifa
                                ? 'Las ventas de números llegan en la próxima etapa.'
                                : 'El catálogo de productos llega en una etapa más adelante.',
                            style: t.pie.copyWith(color: c.tintaSuave),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 26),
                  Text('DÓNDE ESTÁ LA PLATA', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                  const SizedBox(height: 8),
                  MitiTroquel(color: c.tinta, grosor: 1.5),
                  ..._cajasPorPersona(context, cajas, integrantes),

                  const SizedBox(height: 26),
                  Row(
                    children: [
                      Text('EL GRUPO', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                      const Spacer(),
                      if (esAdmin)
                        TextButton.icon(
                          onPressed: () => _invitar(context, ref),
                          icon: Icon(Icons.person_add_alt, size: 18, color: c.selloTexto),
                          label: Text('Invitar', style: t.etiqueta.copyWith(color: c.selloTexto)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final i in [...activos, ...invitados]) _FilaIntegrante(integrante: i),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _cajasPorPersona(
    BuildContext context,
    List<Map<String, dynamic>> cajas,
    List<Map<String, dynamic>> integrantes,
  ) {
    final c = context.color;
    final t = context.texto;
    final filas = <Widget>[];

    final principal = cajas.where((x) => x['tipo'] == 'principal').firstOrNull;
    if (principal != null) {
      filas.add(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.troquel)),
          ),
          child: Row(
            children: [
              MitiIniciales(iniciales(principal['titular'] as String)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cuenta principal · ${principal['titular']}',
                        style: t.cuerpo.copyWith(fontWeight: FontWeight.w600, color: c.tinta)),
                    Text(
                      (principal['alias'] as String?)?.isNotEmpty == true
                          ? 'Alias ${principal['alias']}'
                          : 'Sin alias cargado',
                      style: t.pie.copyWith(color: c.tintaSuave),
                    ),
                  ],
                ),
              ),
              Text(plata(0), style: t.cifra.copyWith(color: c.tinta)),
            ],
          ),
        ),
      );
    }

    for (final persona in integrantes.where((i) => i['estado'] == 'activo')) {
      final propias = cajas.where((x) => x['titular_id'] == persona['usuario_id'] && x['tipo'] != 'principal');
      if (propias.isEmpty) continue;
      filas.add(
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.troquel)),
          ),
          child: Row(
            children: [
              MitiIniciales(iniciales(persona['nombre'] as String)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(persona['nombre'] as String,
                        style: t.cuerpo.copyWith(fontWeight: FontWeight.w600, color: c.tinta)),
                    Text('Billetera ${plata(0)} · efectivo ${plata(0)}',
                        style: t.pie.copyWith(color: c.tintaSuave)),
                  ],
                ),
              ),
              Text(plata(0), style: t.cifra.copyWith(color: c.tinta)),
            ],
          ),
        ),
      );
    }
    return filas;
  }

  Future<void> _activar(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(apiProvider).cambiarEstado(campanaId, 'activa');
      ref.invalidate(campanaProvider(campanaId));
      ref.invalidate(campanasProvider);
      if (context.mounted) mostrarAviso(context, 'La campaña quedó activa');
    } on ErrorApi catch (e) {
      if (context.mounted) mostrarAviso(context, e.mensaje, error: true);
    }
  }

  Future<void> _invitar(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController();
    final invitado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HojaInvitar(email: email, campanaId: campanaId),
    );
    email.dispose();
    if (invitado == true) {
      ref.invalidate(campanaProvider(campanaId));
    }
  }
}

class _FilaIntegrante extends StatelessWidget {
  const _FilaIntegrante({required this.integrante});

  final Map<String, dynamic> integrante;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final esInvitado = integrante['estado'] == 'invitado';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          Opacity(opacity: esInvitado ? 0.55 : 1, child: MitiIniciales(iniciales(integrante['nombre'] as String))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(integrante['nombre'] as String,
                style: t.cuerpo.copyWith(
                  fontWeight: FontWeight.w600,
                  color: esInvitado ? c.tintaSuave : c.tinta,
                )),
          ),
          if (integrante['rol'] == 'admin')
            Text('ADMIN', style: t.sobrelinea.copyWith(color: c.tintaSuave, fontSize: 11)),
          if (esInvitado)
            Text('INVITADO', style: t.sobrelinea.copyWith(color: c.selloTexto, fontSize: 11)),
        ],
      ),
    );
  }
}

class _HojaInvitar extends ConsumerStatefulWidget {
  const _HojaInvitar({required this.email, required this.campanaId});

  final TextEditingController email;
  final String campanaId;

  @override
  ConsumerState<_HojaInvitar> createState() => _HojaInvitarState();
}

class _HojaInvitarState extends ConsumerState<_HojaInvitar> {
  bool _trabajando = false;

  Future<void> _invitar() async {
    final email = widget.email.text.trim();
    if (!email.contains('@')) {
      mostrarAviso(context, 'Escribí el mail de la persona', error: true);
      return;
    }
    setState(() => _trabajando = true);
    try {
      final r = await ref.read(apiProvider).invitar(widget.campanaId, email);
      if (mounted) {
        Navigator.of(context).pop(true);
        mostrarAviso(context, 'Invitaste a ${r['nombre']}');
      }
    } on ErrorApi catch (e) {
      if (mounted) mostrarAviso(context, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        decoration: BoxDecoration(
          color: c.hoja,
          border: Border(top: BorderSide(color: c.tinta, width: 2)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('INVITAR A LA CAMPAÑA', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
            const SizedBox(height: 10),
            TextField(
              controller: widget.email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Mail de la persona'),
            ),
            const SizedBox(height: 8),
            Text('Tiene que tener cuenta en Miti. Le va a aparecer la invitación al entrar.',
                style: t.pie.copyWith(color: c.tintaSuave)),
            const SizedBox(height: 18),
            MitiBoton(texto: 'Invitar', cargando: _trabajando, onTap: _invitar),
          ],
        ),
      ),
    );
  }
}
