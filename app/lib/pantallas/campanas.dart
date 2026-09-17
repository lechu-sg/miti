import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';
import 'campana.dart';
import 'nueva_campana.dart';

class PantallaCampanas extends ConsumerWidget {
  const PantallaCampanas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.color;
    final t = context.texto;
    final campanas = ref.watch(campanasProvider);
    final invitaciones = ref.watch(invitacionesProvider);
    final perfil = ref.watch(sesionProvider).value;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: c.sello,
          onRefresh: () async {
            ref.invalidate(campanasProvider);
            ref.invalidate(invitacionesProvider);
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('HOLA ${(perfil?['nombre'] as String? ?? '').split(' ').first.toUpperCase()}',
                                style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                            Text('Tus campañas', style: t.titular.copyWith(color: c.tinta)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Salir de la cuenta',
                        onPressed: () async {
                          final salir = await _confirmarSalida(context);
                          if (salir == true) await ref.read(sesionProvider.notifier).salir();
                        },
                        icon: Icon(Icons.logout, color: c.tinta),
                      ),
                    ],
                  ),
                ),
              ),

              // Invitaciones pendientes: lo primero que hay que resolver.
              SliverToBoxAdapter(
                child: invitaciones.maybeWhen(
                  data: (lista) => lista.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Column(
                            children: [
                              for (final inv in lista)
                                _FilaInvitacion(invitacion: inv as Map<String, dynamic>),
                            ],
                          ),
                        ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ),

              campanas.when(
                loading: () => const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => SliverFillRemaining(
                  hasScrollBody: false,
                  child: MitiVacio(
                    titulo: 'No pudimos traer tus campañas',
                    detalle: e is ErrorApi ? e.mensaje : 'Fijate si tenés señal y volvé a intentar.',
                    accion: MitiBoton(
                      texto: 'Reintentar',
                      secundario: true,
                      onTap: () => ref.invalidate(campanasProvider),
                    ),
                  ),
                ),
                data: (lista) {
                  final activas = lista.where((x) => (x['mi_estado'] as String) == 'activo').toList();
                  if (activas.isEmpty) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: MitiVacio(
                        titulo: 'Todavía no tenés campañas',
                        detalle: 'Creá una para empezar a cargar ventas y llevar la cuenta de la plata.',
                        accion: MitiBoton(
                          texto: 'Crear una campaña',
                          icono: Icons.add,
                          onTap: () => _nueva(context, ref),
                        ),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    sliver: SliverList.separated(
                      itemCount: activas.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _TarjetaCampana(campana: activas[i] as Map<String, dynamic>),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: campanas.maybeWhen(
        data: (lista) => lista.any((x) => x['mi_estado'] == 'activo')
            ? FloatingActionButton.extended(
                onPressed: () => _nueva(context, ref),
                backgroundColor: c.sello,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                icon: const Icon(Icons.add),
                label: Text('Nueva campaña',
                    style: t.cuerpo.copyWith(fontWeight: FontWeight.w700, color: Colors.white)),
              )
            : null,
        orElse: () => null,
      ),
    );
  }

  Future<bool?> _confirmarSalida(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.color.hoja,
        title: Text('¿Salir de la cuenta?', style: ctx.texto.seccion.copyWith(color: ctx.color.tinta)),
        content: Text('Vas a tener que pedir un código nuevo para volver a entrar.',
            style: ctx.texto.cuerpo.copyWith(color: ctx.color.tintaSuave)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Quedarme')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Salir', style: TextStyle(color: ctx.color.selloTexto)),
          ),
        ],
      ),
    );
  }

  Future<void> _nueva(BuildContext context, WidgetRef ref) async {
    final creada = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const PantallaNuevaCampana()),
    );
    ref.invalidate(campanasProvider);
    if (creada != null && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PantallaCampana(campanaId: creada['id'] as String)),
      );
      ref.invalidate(campanasProvider);
    }
  }
}

class _TarjetaCampana extends StatelessWidget {
  const _TarjetaCampana({required this.campana});

  final Map<String, dynamic> campana;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final meta = campana['meta'] as int?;
    final esRifa = campana['tipo'] == 'rifa';

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PantallaCampana(campanaId: campana['id'] as String)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.hoja,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.tinta, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${esRifa ? 'NÚMEROS' : 'PRODUCTOS'} · ${(campana['estado'] as String).toUpperCase()}',
                  style: t.sobrelinea.copyWith(color: c.tintaSuave),
                ),
                const Spacer(),
                if (campana['mi_rol'] == 'admin')
                  Text('ADMINISTRÁS', style: t.sobrelinea.copyWith(color: c.selloTexto)),
              ],
            ),
            const SizedBox(height: 6),
            Text(campana['nombre'] as String, style: t.seccion.copyWith(color: c.tinta)),
            const SizedBox(height: 10),
            MitiTroquel(color: c.troquel),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.flag_outlined, size: 18, color: c.tintaSuave),
                const SizedBox(width: 6),
                Text(
                  meta == null ? 'Sin meta definida' : 'Meta ${plata(meta)}',
                  style: t.cuerpo.copyWith(color: c.tintaSuave),
                ),
                const Spacer(),
                Icon(Icons.chevron_right, color: c.tinta),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaInvitacion extends ConsumerStatefulWidget {
  const _FilaInvitacion({required this.invitacion});

  final Map<String, dynamic> invitacion;

  @override
  ConsumerState<_FilaInvitacion> createState() => _FilaInvitacionState();
}

class _FilaInvitacionState extends ConsumerState<_FilaInvitacion> {
  bool _trabajando = false;

  Future<void> _responder(bool acepta) async {
    setState(() => _trabajando = true);
    try {
      await ref
          .read(apiProvider)
          .responderInvitacion(widget.invitacion['campana_id'] as String, acepta);
      ref.invalidate(invitacionesProvider);
      ref.invalidate(campanasProvider);
      if (mounted) {
        mostrarAviso(context, acepta ? 'Entraste a la campaña' : 'Rechazaste la invitación');
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
    final inv = widget.invitacion;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: c.sello, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TE INVITARON', style: t.sobrelinea.copyWith(color: c.selloTexto)),
          const SizedBox(height: 4),
          Text(inv['campana'] as String, style: t.seccion.copyWith(color: c.tinta)),
          const SizedBox(height: 2),
          Text('${inv['invitado_por'] ?? 'Alguien'} te invitó a participar',
              style: t.cuerpo.copyWith(color: c.tintaSuave)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: MitiBoton(
                  texto: 'Entrar',
                  cargando: _trabajando,
                  onTap: () => _responder(true),
                ),
              ),
              const SizedBox(width: 10),
              MitiBoton(
                texto: 'No, gracias',
                secundario: true,
                onTap: _trabajando ? null : () => _responder(false),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
