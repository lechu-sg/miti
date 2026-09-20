import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/ajustes.dart';
import '../estado/sesion.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';
import 'legales.dart';

class PantallaPerfil extends ConsumerStatefulWidget {
  const PantallaPerfil({super.key});

  @override
  ConsumerState<PantallaPerfil> createState() => _PantallaPerfilState();
}

class _PantallaPerfilState extends ConsumerState<PantallaPerfil> {
  bool _guardando = false;

  Future<void> _editarNombre(String nombreActual) async {
    final c = context.color;
    final t = context.texto;
    final ctrl = TextEditingController(text: nombreActual);

    final nuevoNombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.papel,
        title: Text('EDITAR NOMBRE', style: t.seccion.copyWith(color: c.tinta)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Tu nombre y apellido',
            hintText: 'Ej. Juan Pérez',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancelar', style: t.cuerpo.copyWith(color: c.tintaSuave)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.tinta,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final texto = ctrl.text.trim();
              if (texto.isNotEmpty) Navigator.of(ctx).pop(texto);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (nuevoNombre != null && nuevoNombre != nombreActual && mounted) {
      setState(() => _guardando = true);
      try {
        await ref.read(sesionProvider.notifier).cambiarNombre(nuevoNombre);
        if (mounted) mostrarAviso(context, 'Nombre actualizado');
      } catch (_) {
        if (mounted) mostrarAviso(context, 'No pudimos actualizar tu nombre', error: true);
      } finally {
        if (mounted) setState(() => _guardando = false);
      }
    }
  }

  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.color;
        final t = ctx.texto;
        return AlertDialog(
          backgroundColor: c.papel,
          title: Text('¿CERRAR SESIÓN?', style: t.seccion.copyWith(color: c.tinta)),
          content: Text(
            'Vas a tener que volver a ingresar con tu código por correo electrónico.',
            style: t.cuerpo.copyWith(color: c.tinta),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancelar', style: t.cuerpo.copyWith(color: c.tintaSuave)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: c.tinta,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Salir'),
            ),
          ],
        );
      },
    );

    if (confirmar == true && mounted) {
      Navigator.of(context).pop();
      await ref.read(sesionProvider.notifier).salir();
    }
  }

  Future<void> _cerrarSesionDeTodos() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.color;
        final t = ctx.texto;
        return AlertDialog(
          backgroundColor: c.papel,
          title: Text('¿CERRAR TODAS LAS SESIONES?', style: t.seccion.copyWith(color: c.tinta)),
          content: Text(
            'Se desconectarán todos los dispositivos donde tengas la cuenta abierta.',
            style: t.cuerpo.copyWith(color: c.tinta),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Cancelar', style: t.cuerpo.copyWith(color: c.tintaSuave)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: c.sello,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Cerrar en todos'),
            ),
          ],
        );
      },
    );

    if (confirmar == true && mounted) {
      Navigator.of(context).pop();
      await ref.read(sesionProvider.notifier).salirDeTodos();
    }
  }

  Future<void> _eliminarCuenta() async {
    final c = context.color;
    final t = context.texto;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.papel,
        title: Text('¿ELIMINAR MI CUENTA?', style: t.seccion.copyWith(color: c.sello)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Esta acción es definitiva e irreversible (Ley 25.326 de Protección de Datos Personales):',
              style: t.cuerpo.copyWith(fontWeight: FontWeight.bold, color: c.tinta),
            ),
            const SizedBox(height: 8),
            Text(
              '• Se anonimizarán tus datos personales (nombre y correo).\n'
              '• Se cerrarán todas tus sesiones activas.\n'
              '• Tu participación histórica en campañas figurará como "Usuario eliminado".\n'
              '• No vas a poder recuperar el acceso con este correo.',
              style: t.cuerpo.copyWith(color: c.tinta, fontSize: 13, height: 1.35),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar', style: t.cuerpo.copyWith(color: c.tintaSuave)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.sello,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sí, eliminar cuenta'),
          ),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      setState(() => _guardando = true);
      try {
        Navigator.of(context).pop();
        await ref.read(sesionProvider.notifier).eliminarCuenta();
      } catch (_) {
        if (mounted) {
          setState(() => _guardando = false);
          mostrarAviso(context, 'No se pudo eliminar la cuenta. Revisá tu conexión.', error: true);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final perfil = ref.watch(sesionProvider).valueOrNull;
    final modoTema = ref.watch(modoTemaProvider);
    final proteccion = ref.watch(proteccionPantallaProvider);

    final nombre = perfil?['nombre'] as String? ?? 'Usuario';
    final email = perfil?['email'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text('MI PERFIL', style: t.seccion.copyWith(color: c.tinta)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.tinta),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            // 1. Tarjeta de Usuario
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: c.papelHundido,
                border: Border.all(color: c.troquel),
                borderRadius: BorderRadius.circular(8),
              ),
                child: Row(
                  children: [
                    MitiIniciales(iniciales(nombre), medida: 56),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  nombre,
                                  style: t.titular.copyWith(fontSize: 19, color: c.tinta),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.edit_outlined, size: 20, color: c.tintaSuave),
                                tooltip: 'Editar nombre',
                                onPressed: _guardando ? null : () => _editarNombre(nombre),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            email,
                            style: t.cuerpo.copyWith(color: c.tintaSuave, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: email));
                              mostrarAviso(context, 'Correo copiado al portapapeles');
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.copy_rounded, size: 14, color: c.sello),
                                const SizedBox(width: 4),
                                Text(
                                  'Copiar para invitaciones',
                                  style: t.pie.copyWith(
                                    color: c.sello,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // 2. Apariencia y Tema
            _seccionTitulo(t, c, 'APARIENCIA'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.papelHundido,
                border: Border.all(color: c.troquel),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tema visual', style: t.cuerpo.copyWith(fontWeight: FontWeight.bold, color: c.tinta)),
                  const SizedBox(height: 4),
                  Text(
                    'Elegí el estilo de talonario que mejor se adapte a tu luz ambiente.',
                    style: t.pie.copyWith(color: c.tintaSuave),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _botonTema(
                        ref: ref,
                        modo: ModoTema.sistema,
                        activo: modoTema == ModoTema.sistema,
                        icono: Icons.brightness_auto_outlined,
                        etiqueta: 'Auto',
                      ),
                      const SizedBox(width: 8),
                      _botonTema(
                        ref: ref,
                        modo: ModoTema.claro,
                        activo: modoTema == ModoTema.claro,
                        icono: Icons.light_mode_outlined,
                        etiqueta: 'Claro',
                      ),
                      const SizedBox(width: 8),
                      _botonTema(
                        ref: ref,
                        modo: ModoTema.oscuro,
                        activo: modoTema == ModoTema.oscuro,
                        icono: Icons.dark_mode_outlined,
                        etiqueta: 'Oscuro',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 3. Seguridad y Privacidad
            _seccionTitulo(t, c, 'SEGURIDAD'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.papelHundido,
                border: Border.all(color: c.troquel),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: c.tinta, size: 24),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Protección de pantalla',
                          style: t.cuerpo.copyWith(fontWeight: FontWeight.bold, color: c.tinta),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Bloquea capturas y oculta importes de dinero en apps recientes.',
                          style: t.pie.copyWith(color: c.tintaSuave),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: proteccion,
                    activeTrackColor: c.sello,
                    onChanged: (val) =>
                        ref.read(proteccionPantallaProvider.notifier).fijarProteccion(val),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 4. Legales y Ayuda
            _seccionTitulo(t, c, 'INFORMACIÓN Y LEGALES'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: c.papelHundido,
                border: Border.all(color: c.troquel),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _filaEnlace(
                    icono: Icons.description_outlined,
                    texto: 'Términos y Condiciones de Uso',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PantallaLegales(tipo: TipoDocumentoLegal.terminos),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: c.troquel),
                  _filaEnlace(
                    icono: Icons.privacy_tip_outlined,
                    texto: 'Política de Privacidad (Ley 25.326)',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PantallaLegales(tipo: TipoDocumentoLegal.privacidad),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: c.troquel),
                  _filaEnlace(
                    icono: Icons.undo_outlined,
                    texto: 'Botón de arrepentimiento',
                    colorIcono: c.sello,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const PantallaLegales(tipo: TipoDocumentoLegal.arrepentimiento),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // 5. Zona de Cuenta
            _seccionTitulo(t, c, 'CUENTA'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: c.papelHundido,
                border: Border.all(color: c.troquel),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _filaEnlace(
                    icono: Icons.logout,
                    texto: 'Cerrar sesión en este dispositivo',
                    onTap: _cerrarSesion,
                  ),
                  Divider(height: 1, color: c.troquel),
                  _filaEnlace(
                    icono: Icons.phonelink_erase_outlined,
                    texto: 'Cerrar sesión en todos los dispositivos',
                    onTap: _cerrarSesionDeTodos,
                  ),
                  Divider(height: 1, color: c.troquel),
                  _filaEnlace(
                    icono: Icons.delete_forever_outlined,
                    texto: 'Eliminar mi cuenta',
                    colorTexto: c.sello,
                    colorIcono: c.sello,
                    onTap: _eliminarCuenta,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            Center(
              child: Text(
                'Miti · Versión 0.8.0',
                style: t.pie.copyWith(color: c.tintaSuave, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seccionTitulo(MitiTextos t, MitiColores c, String titulo) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        titulo,
        style: t.sobrelinea.copyWith(
          color: c.tintaSuave,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _botonTema({
    required WidgetRef ref,
    required ModoTema modo,
    required bool activo,
    required IconData icono,
    required String etiqueta,
  }) {
    final c = context.color;
    final t = context.texto;

    return Expanded(
      child: InkWell(
        onTap: () => ref.read(modoTemaProvider.notifier).fijarModo(modo),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: activo ? c.tinta : c.papel,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: activo ? c.tinta : c.troquel,
              width: activo ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icono,
                size: 20,
                color: activo ? Colors.white : c.tinta,
              ),
              const SizedBox(height: 4),
              Text(
                etiqueta,
                style: t.pie.copyWith(
                  fontWeight: FontWeight.bold,
                  color: activo ? Colors.white : c.tinta,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filaEnlace({
    required IconData icono,
    required String texto,
    required VoidCallback onTap,
    Color? colorTexto,
    Color? colorIcono,
  }) {
    final c = context.color;
    final t = context.texto;

    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: Icon(icono, color: colorIcono ?? c.tinta, size: 22),
        title: Text(
          texto,
          style: t.cuerpo.copyWith(
            color: colorTexto ?? c.tinta,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: c.selloTexto, size: 18),
        onTap: onTap,
      ),
    );
  }
}
