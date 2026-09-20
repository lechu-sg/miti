import 'package:flutter/material.dart';

import '../nucleo/componentes.dart';
import '../nucleo/tema.dart';

enum TipoDocumentoLegal {
  terminos,
  privacidad,
  arrepentimiento,
}

class PantallaLegales extends StatelessWidget {
  const PantallaLegales({
    super.key,
    required this.tipo,
  });

  final TipoDocumentoLegal tipo;

  @override
  Widget build(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    final titulo = switch (tipo) {
      TipoDocumentoLegal.terminos => 'TÉRMINOS Y CONDICIONES',
      TipoDocumentoLegal.privacidad => 'POLÍTICA DE PRIVACIDAD',
      TipoDocumentoLegal.arrepentimiento => 'BOTÓN DE ARREPENTIMIENTO',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(titulo, style: t.seccion.copyWith(color: c.tinta, fontSize: 16)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.tinta),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: c.papelHundido,
                border: Border.all(color: c.troquel),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: switch (tipo) {
                  TipoDocumentoLegal.terminos => _construirTerminos(context),
                  TipoDocumentoLegal.privacidad => _construirPrivacidad(context),
                  TipoDocumentoLegal.arrepentimiento => _construirArrepentimiento(context),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _construirTerminos(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    return [
      Text('Condiciones de uso de Miti', style: t.titular.copyWith(color: c.tinta, fontSize: 18)),
      const SizedBox(height: 8),
      Text('Última actualización: Septiembre 2026 · República Argentina',
          style: t.pie.copyWith(color: c.tintaSuave)),
      const Divider(height: 28),
      _seccion(
        t,
        c,
        '1. Herramienta de registro',
        'Miti es exclusivamente una herramienta tecnológica de colaboración y registro contable entre particulares para grupos cerrados (clubes, egresados, escuelas, ONGs o familias).\n\n'
            'Miti NO organiza ni promociona sorteos, rifas ni ventas al público, NO vende billetes ni mercaderías, y NO es entidad financiera ni custodia, intermedia o gira dinero de los participantes.',
      ),
      _seccion(
        t,
        c,
        '2. Responsabilidad de los organizadores',
        'Cada grupo u organizador de una campaña es el único y exclusivo responsable de obtener las autorizaciones, permisos y cumplir las normativas fiscales y administrativas aplicables en su respectiva jurisdicción.',
      ),
      _seccion(
        t,
        c,
        '3. Cajas y transacciones',
        'El dinero registrado en Miti permanece en todo momento en las cuentas bancarias personales, billeteras virtuales o efectivo físico de los propios integrantes designados. Miti no se responsabiliza por discrepancias, faltantes o demoras en las transferencias entre integrantes o compradores.',
      ),
      _seccion(
        t,
        c,
        '4. Edad mínima',
        'El uso de la aplicación está habilitado para personas mayores de 13 años. Las personas menores de 18 años declaran contar con el consentimiento y supervisión de un adulto responsable.',
      ),
      _seccion(
        t,
        c,
        '5. Conducta y uso indebido',
        'Está prohibido utilizar la plataforma para fines ilícitos, engaños o captación pública no autorizada. La administración de Miti se reserva el derecho de dar de baja campañas que violen estas normas.',
      ),
    ];
  }

  List<Widget> _construirPrivacidad(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    return [
      Text('Protección de Datos Personales', style: t.titular.copyWith(color: c.tinta, fontSize: 18)),
      const SizedBox(height: 8),
      Text('Cumplimiento Ley 25.326 · República Argentina',
          style: t.pie.copyWith(color: c.tintaSuave)),
      const Divider(height: 28),
      _seccion(
        t,
        c,
        '1. Información que recopilamos',
        'Para operar la app recabamos únicamente tu dirección de correo electrónico (para el acceso sin contraseña), nombre de usuario y los registros de las campañas en las que participás activamente.',
      ),
      _seccion(
        t,
        c,
        '2. Cifrado y confidencialidad',
        'Los datos personales sensibles (correos, teléfonos y comprobantes) se almacenan en bases de datos con cifrado AES-256 y viajan bajo protocolos seguros TLS. El teléfono de los compradores solo es visible para el integrante que registró la venta.',
      ),
      _seccion(
        t,
        c,
        '3. Plazo de conservación',
        'Los datos de una campaña se conservan durante su vigencia y hasta 6 meses posteriores a la liquidación definitiva para posibilitar la exportación de comprobantes y balances, tras lo cual se purgan del servidor.',
      ),
      _seccion(
        t,
        c,
        '4. Derecho de supresión y baja',
        'Tenés derecho a solicitar el acceso, rectificación y eliminación total de tus datos personales ("derecho al olvido") en cualquier momento a través del botón "Eliminar mi cuenta" en tu perfil.',
      ),
    ];
  }

  List<Widget> _construirArrepentimiento(BuildContext context) {
    final c = context.color;
    final t = context.texto;

    return [
      Text('Revocación de contratación', style: t.titular.copyWith(color: c.tinta, fontSize: 18)),
      const SizedBox(height: 8),
      Text('Resolución SCI 424/2020 · Defensa del Consumidor',
          style: t.pie.copyWith(color: c.tintaSuave)),
      const Divider(height: 28),
      Text(
        'De acuerdo con las leyes vigentes de defensa del consumidor en la República Argentina, contás con un plazo de 10 (diez) días corridos desde la contratación de cualquier plan de pago para revocar la operación sin costo ni penalidad alguna.',
        style: t.cuerpo.copyWith(color: c.tinta, height: 1.4),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.papel,
          border: Border.all(color: c.troquel),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Para solicitar la cancelación inmediata:',
                style: t.cuerpo.copyWith(fontWeight: FontWeight.bold, color: c.tinta)),
            const SizedBox(height: 8),
            Text('Escribinos indicando tu correo y el identificador de la campaña a:',
                style: t.cuerpo.copyWith(color: c.tintaSuave)),
            const SizedBox(height: 6),
            SelectableText(
              'soporte@miti.sole.ar',
              style: t.cuerpo.copyWith(
                fontWeight: FontWeight.w700,
                color: c.sello,
                fontFamily: 'Figtree',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      MitiBoton(
        texto: 'Volver a mi perfil',
        icono: Icons.check,
        onTap: () => Navigator.of(context).pop(),
      ),
    ];
  }

  Widget _seccion(MitiTextos t, MitiColores c, String subtitulo, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitulo, style: t.cuerpo.copyWith(fontWeight: FontWeight.bold, color: c.tinta)),
          const SizedBox(height: 6),
          Text(texto, style: t.cuerpo.copyWith(color: c.tinta, height: 1.35)),
        ],
      ),
    );
  }
}
