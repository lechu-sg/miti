import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../estado/sesion.dart';
import '../nucleo/api.dart';
import '../nucleo/base_local.dart';
import '../nucleo/componentes.dart';
import '../nucleo/formato.dart';
import '../nucleo/sincronizador.dart';
import '../nucleo/tema.dart';
import 'billete.dart';

/// Pantalla para tomar un pedido o registrar venta de productos.
class PantallaVentaProductos extends ConsumerStatefulWidget {
  const PantallaVentaProductos({
    super.key,
    required this.campanaId,
    required this.campanaNombre,
  });

  final String campanaId;
  final String campanaNombre;

  @override
  ConsumerState<PantallaVentaProductos> createState() => _PantallaVentaProductosState();
}

class _PantallaVentaProductosState extends ConsumerState<PantallaVentaProductos> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();

  final Map<String, int> _cantidades = {};
  String _destinoCobro = 'efectivo';
  String _entrega = 'pedido'; // 'pedido' o 'entregado'
  bool _enviando = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  int _calcularTotal(List<Map<String, dynamic>> productos) {
    int total = 0;
    for (final prod in productos) {
      final id = prod['id'] as String;
      final cant = _cantidades[id] ?? 0;
      final precio = prod['precio'] as int;
      total += cant * precio;
    }
    return total;
  }

  int _calcularTotalItems() {
    return _cantidades.values.fold(0, (sum, c) => sum + c);
  }

  Future<void> _registrarVenta(List<Map<String, dynamic>> productos) async {
    if (_calcularTotalItems() == 0) {
      mostrarAviso(context, 'Elegí al menos un producto para registrar la venta', error: true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final itemsParaEnviar = <Map<String, dynamic>>[];
    final itemsParaBillete = <Map<String, dynamic>>[];

    for (final prod in productos) {
      final id = prod['id'] as String;
      final cant = _cantidades[id] ?? 0;
      if (cant > 0) {
        final precio = prod['precio'] as int;
        itemsParaEnviar.add({
          'producto_id': id,
          'cantidad': cant,
        });
        itemsParaBillete.add({
          'producto_id': id,
          'nombre': prod['nombre'] as String,
          'cantidad': cant,
          'precio_unitario': precio,
          'subtotal': cant * precio,
        });
      }
    }

    final tel = _telefonoCtrl.text.trim();
    final cuerpo = {
      'comprador': {
        'nombre': _nombreCtrl.text.trim(),
        if (tel.isNotEmpty) 'telefono': tel,
      },
      'items': itemsParaEnviar,
      'destino_cobro': _destinoCobro,
      'entrega': _entrega,
    };

    setState(() => _enviando = true);

    try {
      final api = ref.read(apiProvider);
      final venta = await api.venderProductos(widget.campanaId, cuerpo);

      ref.invalidate(campanaProvider(widget.campanaId));
      ref.invalidate(recaudacionProvider(widget.campanaId));
      ref.invalidate(ventasProvider(widget.campanaId));
      ref.invalidate(movimientosProvider(widget.campanaId));

      if (!mounted) return;

      final comprador = venta['comprador'] as Map<String, dynamic>;
      final compradorNombre = comprador['nombre'] as String;
      final compradorTelefono = comprador['telefono'] as String?;
      final vendedorNombre = venta['vendedor_nombre'] as String;
      final importe = venta['importe'] as int;
      final codigoCorto = venta['codigo_corto'] as String;
      final saldoAdeudado = venta['saldo_adeudado'] as int? ?? 0;
      final estaPagado = saldoAdeudado == 0;
      final entregaEstado = venta['entrega'] as String? ?? _entrega;

      // Reemplazamos la pantalla actual por el billete con autoCompartir para WhatsApp
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PantallaBillete(
            campanaNombre: widget.campanaNombre,
            numeros: const [],
            itemsProductos: itemsParaBillete,
            importe: importe,
            compradorNombre: compradorNombre,
            compradorTelefono: compradorTelefono,
            vendedorNombre: vendedorNombre,
            codigoCorto: codigoCorto,
            estaPagado: estaPagado,
            entrega: entregaEstado,
            autoCompartir: true,
          ),
        ),
      );
    } on ErrorApi catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        mostrarAviso(context, e.mensaje, error: true);
      }
    } catch (_) {
      // Sin señal / error de red: guardar en outbox (§5 de DEFINICION.md)
      final opId = generarUuid();
      await BaseLocal.instancia.encolarOperacion(
        widget.campanaId,
        opId,
        'vender_productos',
        cuerpo,
      );

      ref.read(sincroProvider(widget.campanaId).notifier).actualizarContadores();

      if (!mounted) return;
      mostrarAviso(
        context,
        'Venta guardada sin señal. Se confirmará al recuperar internet.',
      );

      final importe = _calcularTotal(productos);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PantallaBillete(
            campanaNombre: widget.campanaNombre,
            numeros: const [],
            itemsProductos: itemsParaBillete,
            importe: importe,
            compradorNombre: _nombreCtrl.text.trim(),
            compradorTelefono: _telefonoCtrl.text.trim().isNotEmpty ? _telefonoCtrl.text.trim() : null,
            vendedorNombre: 'Venta sin señal',
            codigoCorto: 'PENDIENTE',
            estaPagado: _destinoCobro != 'adeudado',
            entrega: _entrega,
            autoCompartir: true,
          ),
        ),
      );
    }
  }

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
            titulo: 'No se pudieron cargar los productos',
            detalle: e is ErrorApi ? e.mensaje : 'Fijate si tenés conexión.',
            accion: MitiBoton(
              texto: 'Reintentar',
              secundario: true,
              onTap: () => ref.invalidate(productosProvider(widget.campanaId)),
            ),
          ),
          data: (lista) {
            final todos = lista.cast<Map<String, dynamic>>();
            final activos = todos.where((p) => p['activo'] == true).toList();

            if (activos.isEmpty) {
              return MitiVacio(
                titulo: 'No hay productos disponibles',
                detalle: 'No podés registrar ventas porque el catálogo no tiene productos activos.',
                accion: MitiBoton(
                  texto: 'Volver',
                  secundario: true,
                  onTap: () => Navigator.of(context).pop(),
                ),
              );
            }

            final totalImporte = _calcularTotal(activos);
            final totalCant = _calcularTotalItems();

            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  Text(
                    'TOMAR PEDIDO / VENDER',
                    style: t.sobrelinea.copyWith(color: c.tintaSuave),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Seleccioná los productos y cantidades',
                    style: t.cuerpo.copyWith(color: c.tintaSuave),
                  ),
                  const SizedBox(height: 16),
                  MitiTroquel(color: c.tinta, grosor: 1.5),

                  // Lista de productos con selector de cantidad
                  for (final prod in activos) ...[
                    _SelectorItemProducto(
                      producto: prod,
                      cantidad: _cantidades[prod['id'] as String] ?? 0,
                      onIncrementar: () {
                        final id = prod['id'] as String;
                        setState(() {
                          _cantidades[id] = (_cantidades[id] ?? 0) + 1;
                        });
                      },
                      onDecrementar: () {
                        final id = prod['id'] as String;
                        final actual = _cantidades[id] ?? 0;
                        if (actual > 0) {
                          setState(() {
                            _cantidades[id] = actual - 1;
                          });
                        }
                      },
                    ),
                  ],

                  const SizedBox(height: 16),
                  // Resumen de total de productos
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.tinta.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: c.troquel),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$totalCant ${totalCant == 1 ? 'ítem' : 'ítems'} seleccionados',
                          style: t.etiqueta.copyWith(color: c.tinta),
                        ),
                        Text(
                          plata(totalImporte),
                          style: t.cifra.copyWith(color: c.tinta, fontSize: 24),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'DATOS DEL COMPRADOR',
                    style: t.sobrelinea.copyWith(color: c.tintaSuave),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _nombreCtrl,
                    textCapitalization: TextCapitalization.words,
                    style: t.cuerpo.copyWith(color: c.tinta),
                    decoration: InputDecoration(
                      labelText: 'Nombre y apellido',
                      hintText: '¿Quién te compra?',
                      labelStyle: t.etiqueta.copyWith(color: c.tintaSuave),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Ingresá el nombre del comprador';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _telefonoCtrl,
                    keyboardType: TextInputType.phone,
                    style: t.cuerpo.copyWith(color: c.tinta),
                    decoration: InputDecoration(
                      labelText: 'Teléfono / WhatsApp (opcional)',
                      hintText: 'Para enviarle el comprobante',
                      labelStyle: t.etiqueta.copyWith(color: c.tintaSuave),
                    ),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'DESTINO DEL COBRO',
                    style: t.sobrelinea.copyWith(color: c.tintaSuave),
                  ),
                  const SizedBox(height: 10),
                  MitiDestinoDinero(
                    seleccionado: _destinoCobro,
                    onCambio: (v) => setState(() => _destinoCobro = v),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    'ESTADO DE ENTREGA',
                    style: t.sobrelinea.copyWith(color: c.tintaSuave),
                  ),
                  const SizedBox(height: 10),
                  _SelectorEntrega(
                    seleccionado: _entrega,
                    onCambio: (v) => setState(() => _entrega = v),
                  ),

                  const SizedBox(height: 32),
                  MitiBoton(
                    texto: totalImporte > 0
                        ? 'Registrar venta · ${plata(totalImporte)}'
                        : 'Elegí al menos 1 producto',
                    icono: Icons.check_circle_outline,
                    cargando: _enviando,
                    onTap: (totalImporte > 0 && !_enviando)
                        ? () => _registrarVenta(activos)
                        : null,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SelectorItemProducto extends StatelessWidget {
  const _SelectorItemProducto({
    required this.producto,
    required this.cantidad,
    required this.onIncrementar,
    required this.onDecrementar,
  });

  final Map<String, dynamic> producto;
  final int cantidad;
  final VoidCallback onIncrementar;
  final VoidCallback onDecrementar;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;
    final nombre = producto['nombre'] as String;
    final precio = producto['precio'] as int;
    final subtotal = cantidad * precio;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.troquel))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre, style: t.cuerpo.copyWith(fontWeight: FontWeight.w700, color: c.tinta)),
                const SizedBox(height: 2),
                Text(
                  '${plata(precio)} c/u${cantidad > 0 ? ' · Subtotal ${plata(subtotal)}' : ''}',
                  style: t.pie.copyWith(color: cantidad > 0 ? c.selloTexto : c.tintaSuave),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _BotonContador(
                icono: Icons.remove,
                habilitado: cantidad > 0,
                onTap: onDecrementar,
              ),
              Container(
                width: 38,
                alignment: Alignment.center,
                child: Text(
                  '$cantidad',
                  style: t.cifra.copyWith(
                    color: cantidad > 0 ? c.tinta : c.tintaSuave,
                    fontSize: 20,
                  ),
                ),
              ),
              _BotonContador(
                icono: Icons.add,
                habilitado: true,
                onTap: onIncrementar,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BotonContador extends StatelessWidget {
  const _BotonContador({
    required this.icono,
    required this.habilitado,
    required this.onTap,
  });

  final IconData icono;
  final bool habilitado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.color;

    return InkWell(
      onTap: habilitado ? onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: habilitado ? c.tinta : c.troquel,
            width: 1.5,
          ),
          color: habilitado ? Colors.transparent : c.tinta.withValues(alpha: 0.05),
        ),
        alignment: Alignment.center,
        child: Icon(
          icono,
          size: 18,
          color: habilitado ? c.tinta : c.tintaSuave.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

class _SelectorEntrega extends StatelessWidget {
  const _SelectorEntrega({
    required this.seleccionado,
    required this.onCambio,
  });

  final String seleccionado; // 'pedido' o 'entregado'
  final ValueChanged<String> onCambio;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    final esPedido = seleccionado == 'pedido';
    final esEntregado = seleccionado == 'entregado';

    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => onCambio('pedido'),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: esPedido ? c.tinta : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.tinta, width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 18,
                    color: esPedido ? c.tintaSobre : c.tinta,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Es un pedido',
                      style: t.etiqueta.copyWith(
                        color: esPedido ? c.tintaSobre : c.tinta,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () => onCambio('entregado'),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: esEntregado ? c.tinta : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.tinta, width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outlined,
                    size: 18,
                    color: esEntregado ? c.tintaSobre : c.tinta,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Ya entregado',
                      style: t.etiqueta.copyWith(
                        color: esEntregado ? c.tintaSobre : c.tinta,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
