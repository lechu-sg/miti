import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';

class PantallaNuevaCampana extends ConsumerStatefulWidget {
  const PantallaNuevaCampana({super.key});

  @override
  ConsumerState<PantallaNuevaCampana> createState() => _PantallaNuevaCampanaState();
}

class _PantallaNuevaCampanaState extends ConsumerState<PantallaNuevaCampana> {
  final _nombre = TextEditingController();
  final _meta = TextEditingController();
  final _alias = TextEditingController();
  final _desde = TextEditingController(text: '0');
  final _hasta = TextEditingController(text: '99');
  final _precio = TextEditingController();
  final List<TextEditingController> _premios = [
    TextEditingController(text: 'Primer Premio'),
  ];
  final List<FocusNode> _focusPremios = [
    FocusNode(),
  ];

  String _tipo = 'rifa';
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _meta.dispose();
    _alias.dispose();
    _desde.dispose();
    _hasta.dispose();
    _precio.dispose();
    for (final p in _premios) {
      p.dispose();
    }
    for (final f in _focusPremios) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _crear() async {
    final nombre = _nombre.text.trim();
    if (nombre.length < 3) {
      mostrarAviso(context, 'Ponele un nombre a la campaña', error: true);
      return;
    }
    final precio = aCentavos(_precio.text);
    if (_tipo == 'rifa' && (precio == null || precio <= 0)) {
      mostrarAviso(context, 'Falta el precio de cada número', error: true);
      return;
    }
    final desde = int.tryParse(_desde.text.trim()) ?? 0;
    final hasta = int.tryParse(_hasta.text.trim()) ?? 0;
    if (_tipo == 'rifa' && hasta <= desde) {
      mostrarAviso(context, 'El número final tiene que ser mayor que el inicial', error: true);
      return;
    }

    final listaPremios = _premios.map((p) => p.text.trim()).where((p) => p.isNotEmpty).toList();

    setState(() => _guardando = true);
    try {
      final creada = await ref.read(apiProvider).crearCampana({
        'tipo': _tipo,
        'nombre': nombre,
        'meta': aCentavos(_meta.text),
        'alias_cuenta': _alias.text.trim().isEmpty ? null : _alias.text.trim(),
        if (_tipo == 'rifa')
          'rifa': {
            'desde': desde,
            'hasta': hasta,
            'precio': precio,
            'asignacion': 'bolsa',
            'sorteo': 'externo',
            'si_no_se_vendio': 'resortear',
            'premios': listaPremios.isEmpty ? ['Primer Premio'] : listaPremios,
          },
      });
      if (mounted) Navigator.of(context).pop(creada);
    } on ErrorApi catch (e) {
      if (mounted) mostrarAviso(context, e.mensaje, error: true);
    } catch (_) {
      if (mounted) mostrarAviso(context, 'No pudimos conectarnos. ¿Tenés señal?', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final esRifa = _tipo == 'rifa';
    final cantidad = (int.tryParse(_hasta.text) ?? 0) - (int.tryParse(_desde.text) ?? 0) + 1;
    final precio = aCentavos(_precio.text) ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text('Nueva campaña', style: t.seccion.copyWith(color: c.tinta))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text('QUÉ VAN A VENDER', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
            const SizedBox(height: 10),
            Row(
              children: [
                MitiChip(
                  texto: 'Números',
                  activo: esRifa,
                  onTap: () => setState(() => _tipo = 'rifa'),
                ),
                const SizedBox(width: 8),
                MitiChip(
                  texto: 'Productos',
                  activo: !esRifa,
                  onTap: () => setState(() => _tipo = 'productos'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre de la campaña',
                hintText: 'Viaje de egresados 6° B',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _meta,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Meta (opcional)',
                prefixText: r'$ ',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _alias,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Alias o CBU de la cuenta principal (opcional)',
                hintText: 'donde te transfieren',
              ),
            ),
            if (esRifa) ...[
              const SizedBox(height: 26),
              Text('LOS NÚMEROS', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _desde,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Desde'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hasta,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: 'Hasta'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _precio,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Precio de cada número', prefixText: r'$ '),
              ),
              const SizedBox(height: 16),
              if (cantidad > 0 && precio > 0)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.papelHundido,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calculate_outlined, color: c.tintaSuave, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Son $cantidad números. Si se venden todos, junta ${plata(cantidad * precio)}.',
                          style: t.cuerpo.copyWith(color: c.tinta),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              Text('PREMIOS DE LA RIFA', style: t.sobrelinea.copyWith(color: c.tintaSuave)),
              const SizedBox(height: 6),
              Text(
                'Ingresá los premios en orden del sorteo (1°, 2°, etc.). Podés editarlos más adelante.',
                style: t.pie.copyWith(color: c.tintaSuave),
              ),
              const SizedBox(height: 12),
              ...List.generate(_premios.length, (index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
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
                          controller: _premios[index],
                          focusNode: _focusPremios[index],
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: '${index + 1}° Premio',
                            hintText: 'Ej: Canasta navideña, Smart TV...',
                          ),
                        ),
                      ),
                      if (_premios.length > 1) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: c.sello, size: 22),
                          tooltip: 'Quitar premio',
                          onPressed: () {
                            setState(() {
                              final ctrl = _premios.removeAt(index);
                              ctrl.dispose();
                              final f = _focusPremios.removeAt(index);
                              f.dispose();
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                );
              }),
              const SizedBox(height: 4),
              InkWell(
                onTap: () {
                  final nuevoFocus = FocusNode();
                  setState(() {
                    _premios.add(TextEditingController());
                    _focusPremios.add(nuevoFocus);
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    nuevoFocus.requestFocus();
                  });
                },
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
            ],
            const SizedBox(height: 28),
            MitiBoton(texto: 'Crear la campaña', cargando: _guardando, onTap: _crear),
            const SizedBox(height: 12),
            Text(
              'Después podés invitar a los demás. La campaña arranca en borrador: '
              'nadie puede cargar ventas hasta que la actives.',
              style: t.pie.copyWith(color: c.tintaSuave),
            ),
          ],
        ),
      ),
    );
  }
}
