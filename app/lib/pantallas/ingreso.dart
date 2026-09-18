import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/componentes.dart';
import '../nucleo/tema.dart';

/// Entrar a Miti: primero el mail, después el código que llega por mail.
class PantallaIngreso extends ConsumerStatefulWidget {
  const PantallaIngreso({super.key});

  @override
  ConsumerState<PantallaIngreso> createState() => _PantallaIngresoState();
}

class _PantallaIngresoState extends ConsumerState<PantallaIngreso> {
  final _email = TextEditingController();
  final _codigo = TextEditingController();
  final _nombre = TextEditingController();

  bool _pidiendo = false;
  bool _codigoPedido = false;
  bool _cuentaNueva = false;
  DateTime? _nacimiento;

  @override
  void dispose() {
    _email.dispose();
    _codigo.dispose();
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _pedirCodigo() async {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      mostrarAviso(context, 'Escribí un mail válido', error: true);
      return;
    }
    setState(() => _pidiendo = true);
    try {
      await ref.read(sesionProvider.notifier).pedirCodigo(email);
      if (!mounted) return;
      setState(() => _codigoPedido = true);
      mostrarAviso(context, 'Te mandamos un código a $email');
    } on ErrorApi catch (e) {
      if (mounted) mostrarAviso(context, e.mensaje, error: true);
    } catch (_) {
      if (mounted) mostrarAviso(context, 'No pudimos conectarnos. ¿Tenés señal?', error: true);
    } finally {
      if (mounted) setState(() => _pidiendo = false);
    }
  }

  Future<void> _entrar() async {
    if (_codigo.text.trim().length != 6) {
      mostrarAviso(context, 'El código tiene 6 números', error: true);
      return;
    }
    if (_cuentaNueva && (_nombre.text.trim().length < 2 || _nacimiento == null)) {
      mostrarAviso(context, 'Faltan tu nombre y tu fecha de nacimiento', error: true);
      return;
    }
    setState(() => _pidiendo = true);
    try {
      await ref.read(sesionProvider.notifier).verificar(
            email: _email.text.trim(),
            codigo: _codigo.text.trim(),
            nombre: _cuentaNueva ? _nombre.text.trim() : null,
            nacimiento: _cuentaNueva ? _nacimiento : null,
          );
    } on ErrorApi catch (e) {
      if (!mounted) return;
      if (e.codigo == 422 && !_cuentaNueva) {
        // Es la primera vez: le pedimos nombre y fecha de nacimiento.
        setState(() => _cuentaNueva = true);
        mostrarAviso(context, 'Es tu primera vez acá: contanos quién sos');
      } else {
        mostrarAviso(context, e.mensaje, error: true);
      }
    } catch (_) {
      if (mounted) mostrarAviso(context, 'No pudimos conectarnos. ¿Tenés señal?', error: true);
    } finally {
      if (mounted) setState(() => _pidiendo = false);
    }
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: DateTime(hoy.year - 18, hoy.month, hoy.day),
      firstDate: DateTime(hoy.year - 100),
      lastDate: hoy,
      helpText: 'Tu fecha de nacimiento',
    );
    if (elegida != null) setState(() => _nacimiento = elegida);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 48, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MITI', style: t.titular.copyWith(fontSize: 56, color: c.tinta, letterSpacing: 2)),
              const SizedBox(height: 6),
              Text(
                'Campañas de recaudación, con las cuentas claras.',
                style: t.cuerpo.copyWith(color: c.tintaSuave),
              ),
              const SizedBox(height: 36),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: c.hoja,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.tinta, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_codigoPedido ? 'TU CÓDIGO' : 'TU MAIL', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
                    const SizedBox(height: 12),
                    if (!_codigoPedido) ...[
                      AutofillGroup(
                        child: TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          enableSuggestions: true,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => _pedirCodigo(),
                          decoration: const InputDecoration(
                            hintText: 'nombre@mail.com',
                            prefixIcon: Icon(Icons.alternate_email, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Te mandamos un código de 6 números. No hace falta contraseña.',
                          style: t.pie.copyWith(color: c.tintaSuave)),
                      const SizedBox(height: 18),
                      MitiBoton(texto: 'Mandame el código', cargando: _pidiendo, onTap: _pedirCodigo),
                    ] else ...[
                      Text(_email.text.trim(), style: t.cuerpo.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _codigo,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        autofocus: true,
                        // Android ofrece el código del SMS/mail si lo reconoce.
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: t.importe.copyWith(fontSize: 34, color: c.tinta, letterSpacing: 8),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(counterText: '', hintText: '------'),
                      ),
                      if (_cuentaNueva) ...[
                        const SizedBox(height: 16),
                        MitiTroquel(color: c.troquel, grosor: 2),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _nombre,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Nombre y apellido'),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _elegirFecha,
                          borderRadius: BorderRadius.circular(6),
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Fecha de nacimiento'),
                            child: Text(
                              _nacimiento == null
                                  ? 'Tocá para elegirla'
                                  : '${_nacimiento!.day}/${_nacimiento!.month}/${_nacimiento!.year}',
                              style: t.cuerpo.copyWith(
                                color: _nacimiento == null ? c.tintaSuave : c.tinta,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('Hay que tener 13 años o más para usar Miti.',
                            style: t.pie.copyWith(color: c.tintaSuave)),
                      ],
                      const SizedBox(height: 18),
                      MitiBoton(texto: 'Entrar', cargando: _pidiendo, onTap: _entrar),
                      const SizedBox(height: 10),
                      Align(
                        child: TextButton(
                          onPressed: _pidiendo
                              ? null
                              : () => setState(() {
                                    _codigoPedido = false;
                                    _cuentaNueva = false;
                                    _codigo.clear();
                                  }),
                          child: Text('Cambiar el mail', style: t.etiqueta.copyWith(color: c.selloTexto)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text('Al entrar aceptás los términos y la política de privacidad.',
                  style: t.pie.copyWith(color: c.tintaSuave)),
            ],
          ),
        ),
      ),
    );
  }
}
