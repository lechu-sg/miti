import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/tema.dart';

/// Catálogo de productos de la campaña: lista de productos, precios y altas/ediciones.
class PantallaCatalogoProductos extends ConsumerStatefulWidget {
  const PantallaCatalogoProductos({
    super.key,
    required this.campanaId,
    required this.campanaNombre,
    required this.esAdmin,
  });

  final String campanaId;
  final String campanaNombre;
  final bool esAdmin;

  @override
  ConsumerState<PantallaCatalogoProductos> createState() => _PantallaCatalogoProductosState();
}

class _PantallaCatalogoProductosState extends ConsumerState<PantallaCatalogoProductos> {
  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final productosAsync = ref.watch(productosProvider(widget.campanaId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.campanaNombre, style: t.titular.copyWith(fontSize: 18)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.tinta),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: productosAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => MitiVacio(
            titulo: 'No se pudo cargar el catálogo',
            detalle: e is ErrorApi ? e.mensaje : 'Fijate si tenés conexión.',
            accion: MitiBoton(
              texto: 'Reintentar',
              secundario: true,
              onTap: () => ref.invalidate(productosProvider(widget.campanaId)),
            ),
          ),
          data: (lista) {
            final productos = lista.cast<Map<String, dynamic>>();

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                Text(
                  'CATÁLOGO DE PRODUCTOS',
                  style: t.sobrelinea.copyWith(color: c.tintaSuave),
                ),
                const SizedBox(height: 4),
                Text(
                  'Productos y precios para la venta',
                  style: t.cuerpo.copyWith(color: c.tintaSuave),
                ),
                const SizedBox(height: 16),
                if (widget.esAdmin) ...[
                  MitiBoton(
                    texto: 'Agregar nuevo producto',
                    icono: Icons.add,
                    onTap: () => _abrirEditorProducto(context),
                  ),
                  const SizedBox(height: 20),
                ],
                if (productos.isEmpty)
                  MitiVacio(
                    titulo: 'No hay productos cargados',
                    detalle: widget.esAdmin
                        ? 'Tocá «Agregar nuevo producto» para cargar lo que van a vender.'
                        : 'El administrador todavía no cargó productos en esta campaña.',
                  )
                else ...[
                  MitiTroquel(color: c.tinta, grosor: 1.5),
                  for (final prod in productos)
                    _FilaProducto(
                      producto: prod,
                      esAdmin: widget.esAdmin,
                      onEditar: () => _abrirEditorProducto(context, producto: prod),
                      onToggleActivo: (nuevoActivo) => _toggleActivo(prod, nuevoActivo),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _toggleActivo(Map<String, dynamic> producto, bool nuevoActivo) async {
    try {
      final api = ref.read(apiProvider);
      await api.modificarProducto(
        widget.campanaId,
        producto['id'] as String,
        activo: nuevoActivo,
      );
      ref.invalidate(productosProvider(widget.campanaId));
    } on ErrorApi catch (e) {
      if (mounted) mostrarAviso(context, e.mensaje, error: true);
    }
  }

  Future<void> _abrirEditorProducto(BuildContext context, {Map<String, dynamic>? producto}) async {
    final guardado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HojaEditorProducto(
        campanaId: widget.campanaId,
        productoExistente: producto,
      ),
    );

    if (guardado == true) {
      ref.invalidate(productosProvider(widget.campanaId));
    }
  }
}

class _FilaProducto extends StatelessWidget {
  const _FilaProducto({
    required this.producto,
    required this.esAdmin,
    required this.onEditar,
    required this.onToggleActivo,
  });

  final Map<String, dynamic> producto;
  final bool esAdmin;
  final VoidCallback onEditar;
  final ValueChanged<bool> onToggleActivo;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final activo = producto['activo'] as bool? ?? true;
    final nombre = producto['nombre'] as String;
    final precio = producto['precio'] as int;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.troquel))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        nombre,
                        style: t.cuerpo.copyWith(
                          fontWeight: FontWeight.w700,
                          color: activo ? c.tinta : c.tintaSuave,
                          decoration: activo ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    if (!activo) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.sello.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'PAUSADO',
                          style: t.pie.copyWith(
                            color: c.selloTexto,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  plata(precio),
                  style: t.cifra.copyWith(
                    color: activo ? c.tinta : c.tintaSuave,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          if (esAdmin) ...[
            IconButton(
              icon: Icon(Icons.edit_outlined, size: 20, color: c.tintaSuave),
              tooltip: 'Editar producto',
              onPressed: onEditar,
            ),
            Switch(
              value: activo,
              activeThumbColor: c.sello,
              onChanged: onToggleActivo,
            ),
          ],
        ],
      ),
    );
  }
}

class _HojaEditorProducto extends ConsumerStatefulWidget {
  const _HojaEditorProducto({
    required this.campanaId,
    this.productoExistente,
  });

  final String campanaId;
  final Map<String, dynamic>? productoExistente;

  @override
  ConsumerState<_HojaEditorProducto> createState() => _HojaEditorProductoState();
}

class _HojaEditorProductoState extends ConsumerState<_HojaEditorProducto> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _precioCtrl;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.productoExistente;
    _nombreCtrl = TextEditingController(text: p?['nombre'] as String? ?? '');
    final precioCentavos = p?['precio'] as int?;
    _precioCtrl = TextEditingController(
      text: precioCentavos != null ? (precioCentavos ~/ 100).toString() : '',
    );
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _precioCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });

    final nombre = _nombreCtrl.text.trim();
    final pesos = int.tryParse(_precioCtrl.text.trim()) ?? 0;
    final centavos = pesos * 100;

    try {
      final api = ref.read(apiProvider);
      if (widget.productoExistente == null) {
        await api.crearProducto(
          widget.campanaId,
          nombre: nombre,
          precio: centavos,
        );
      } else {
        await api.modificarProducto(
          widget.campanaId,
          widget.productoExistente!['id'] as String,
          nombre: nombre,
          precio: centavos,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ErrorApi catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = e.mensaje;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo guardar el producto. Fijate si tenés señal.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final esEdicion = widget.productoExistente != null;

    return MitiHoja(
      titulo: esEdicion ? 'EDITAR PRODUCTO' : 'NUEVO PRODUCTO',
      subtitulo: 'CATÁLOGO',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nombreCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: t.cuerpo.copyWith(color: c.tinta),
              decoration: InputDecoration(
                labelText: 'Nombre del producto',
                hintText: 'Ej: Empanadas de carne (docena)',
                labelStyle: t.etiqueta.copyWith(color: c.tintaSuave),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresá el nombre del producto';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _precioCtrl,
              keyboardType: TextInputType.number,
              style: t.cifra.copyWith(color: c.tinta, fontSize: 24),
              decoration: InputDecoration(
                labelText: 'Precio en pesos',
                hintText: 'Ej: 12000',
                prefixText: '\$ ',
                labelStyle: t.etiqueta.copyWith(color: c.tintaSuave),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresá el precio';
                final n = int.tryParse(v.trim());
                if (n == null || n <= 0) return 'El precio debe ser mayor a 0';
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: c.sello.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.sello, width: 1.2),
                ),
                child: Text(
                  _error!,
                  style: t.pie.copyWith(color: c.selloTexto, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            const SizedBox(height: 24),
            MitiBoton(
              texto: esEdicion ? 'Guardar cambios' : 'Crear producto',
              cargando: _cargando,
              onTap: _guardar,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
