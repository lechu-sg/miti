import 'package:flutter/material.dart';

/// Sistema "Talonario": papel y tinta. Los colores salen SIEMPRE de acá.
/// La definición completa está en .claude/skills/diseno-miti/SKILL.md
@immutable
class MitiColores extends ThemeExtension<MitiColores> {
  const MitiColores({
    required this.papel,
    required this.hoja,
    required this.papelHundido,
    required this.tinta,
    required this.tintaSobre,
    required this.tintaSuave,
    required this.troquel,
    required this.sello,
    required this.selloTexto,
    required this.mostaza,
    required this.vendido,
    required this.vendidoTexto,
    required this.ok,
  });

  final Color papel;
  final Color hoja;
  final Color papelHundido;
  final Color tinta;
  final Color tintaSobre;
  final Color tintaSuave;
  final Color troquel;
  final Color sello;
  final Color selloTexto;
  final Color mostaza;
  final Color vendido;
  final Color vendidoTexto;
  final Color ok;

  static const claro = MitiColores(
    papel: Color(0xFFFBF9F4),
    hoja: Color(0xFFFFFFFF),
    papelHundido: Color(0xFFF1ECE0),
    tinta: Color(0xFF1E2A3A),
    tintaSobre: Color(0xFFFBF9F4),
    tintaSuave: Color(0xFF5F5A4E),
    troquel: Color(0xFFCFC6B2),
    sello: Color(0xFFB7372A),
    selloTexto: Color(0xFF8E2A20),
    mostaza: Color(0xFFE3A72F),
    vendido: Color(0xFFE4DDCB),
    vendidoTexto: Color(0xFFA39B88),
    ok: Color(0xFF2F7A57),
  );

  static const oscuro = MitiColores(
    papel: Color(0xFF141A23),
    hoja: Color(0xFF1B222D),
    papelHundido: Color(0xFF222B38),
    tinta: Color(0xFFEFE8D8),
    tintaSobre: Color(0xFF141A23),
    tintaSuave: Color(0xFFA9A291),
    troquel: Color(0xFF3A4556),
    sello: Color(0xFFC94A36),
    selloTexto: Color(0xFFF08A76),
    mostaza: Color(0xFFF0B84A),
    vendido: Color(0xFF212935),
    vendidoTexto: Color(0xFF58606D),
    ok: Color(0xFF6CC39A),
  );

  @override
  MitiColores copyWith({
    Color? papel,
    Color? hoja,
    Color? papelHundido,
    Color? tinta,
    Color? tintaSobre,
    Color? tintaSuave,
    Color? troquel,
    Color? sello,
    Color? selloTexto,
    Color? mostaza,
    Color? vendido,
    Color? vendidoTexto,
    Color? ok,
  }) {
    return MitiColores(
      papel: papel ?? this.papel,
      hoja: hoja ?? this.hoja,
      papelHundido: papelHundido ?? this.papelHundido,
      tinta: tinta ?? this.tinta,
      tintaSobre: tintaSobre ?? this.tintaSobre,
      tintaSuave: tintaSuave ?? this.tintaSuave,
      troquel: troquel ?? this.troquel,
      sello: sello ?? this.sello,
      selloTexto: selloTexto ?? this.selloTexto,
      mostaza: mostaza ?? this.mostaza,
      vendido: vendido ?? this.vendido,
      vendidoTexto: vendidoTexto ?? this.vendidoTexto,
      ok: ok ?? this.ok,
    );
  }

  @override
  MitiColores lerp(ThemeExtension<MitiColores>? otro, double t) {
    if (otro is! MitiColores) return this;
    return MitiColores(
      papel: Color.lerp(papel, otro.papel, t)!,
      hoja: Color.lerp(hoja, otro.hoja, t)!,
      papelHundido: Color.lerp(papelHundido, otro.papelHundido, t)!,
      tinta: Color.lerp(tinta, otro.tinta, t)!,
      tintaSobre: Color.lerp(tintaSobre, otro.tintaSobre, t)!,
      tintaSuave: Color.lerp(tintaSuave, otro.tintaSuave, t)!,
      troquel: Color.lerp(troquel, otro.troquel, t)!,
      sello: Color.lerp(sello, otro.sello, t)!,
      selloTexto: Color.lerp(selloTexto, otro.selloTexto, t)!,
      mostaza: Color.lerp(mostaza, otro.mostaza, t)!,
      vendido: Color.lerp(vendido, otro.vendido, t)!,
      vendidoTexto: Color.lerp(vendidoTexto, otro.vendidoTexto, t)!,
      ok: Color.lerp(ok, otro.ok, t)!,
    );
  }
}

/// Los textos del sistema. `titular`, `importe` y `cifra` van en Big Shoulders.
@immutable
class MitiTextos extends ThemeExtension<MitiTextos> {
  const MitiTextos({
    required this.titular,
    required this.importe,
    required this.seccion,
    required this.cifra,
    required this.cuerpo,
    required this.etiqueta,
    required this.sobrelinea,
    required this.pie,
  });

  final TextStyle titular;
  final TextStyle importe;
  final TextStyle seccion;
  final TextStyle cifra;
  final TextStyle cuerpo;
  final TextStyle etiqueta;
  final TextStyle sobrelinea;
  final TextStyle pie;

  static const _display = 'BigShoulders';
  static const _texto = 'Figtree';

  // Son fuentes variables: además del peso, se pide el eje "wght".

  static const base = MitiTextos(
    titular: TextStyle(fontFamily: _display, fontWeight: FontWeight.w900, fontVariations: [FontVariation('wght', 900)], fontSize: 40, height: 0.95),
    importe: TextStyle(fontFamily: _display, fontWeight: FontWeight.w800, fontVariations: [FontVariation('wght', 800)], fontSize: 44, height: 1),
    seccion: TextStyle(fontFamily: _display, fontWeight: FontWeight.w800, fontVariations: [FontVariation('wght', 800)], fontSize: 24, height: 1),
    cifra: TextStyle(fontFamily: _display, fontWeight: FontWeight.w800, fontVariations: [FontVariation('wght', 800)], fontSize: 20, height: 1),
    cuerpo: TextStyle(fontFamily: _texto, fontWeight: FontWeight.w400, fontVariations: [FontVariation('wght', 400)], fontSize: 15, height: 1.35),
    etiqueta: TextStyle(fontFamily: _texto, fontWeight: FontWeight.w600, fontVariations: [FontVariation('wght', 600)], fontSize: 13),
    sobrelinea: TextStyle(
      fontFamily: _texto,
      fontWeight: FontWeight.w700,
      fontVariations: [FontVariation('wght', 700)],
      fontSize: 12,
      letterSpacing: 1.7,
    ),
    pie: TextStyle(fontFamily: _texto, fontWeight: FontWeight.w400, fontVariations: [FontVariation('wght', 400)], fontSize: 12),
  );

  @override
  MitiTextos copyWith({
    TextStyle? titular,
    TextStyle? importe,
    TextStyle? seccion,
    TextStyle? cifra,
    TextStyle? cuerpo,
    TextStyle? etiqueta,
    TextStyle? sobrelinea,
    TextStyle? pie,
  }) {
    return MitiTextos(
      titular: titular ?? this.titular,
      importe: importe ?? this.importe,
      seccion: seccion ?? this.seccion,
      cifra: cifra ?? this.cifra,
      cuerpo: cuerpo ?? this.cuerpo,
      etiqueta: etiqueta ?? this.etiqueta,
      sobrelinea: sobrelinea ?? this.sobrelinea,
      pie: pie ?? this.pie,
    );
  }

  @override
  MitiTextos lerp(ThemeExtension<MitiTextos>? otro, double t) {
    if (otro is! MitiTextos) return this;
    return MitiTextos(
      titular: TextStyle.lerp(titular, otro.titular, t)!,
      importe: TextStyle.lerp(importe, otro.importe, t)!,
      seccion: TextStyle.lerp(seccion, otro.seccion, t)!,
      cifra: TextStyle.lerp(cifra, otro.cifra, t)!,
      cuerpo: TextStyle.lerp(cuerpo, otro.cuerpo, t)!,
      etiqueta: TextStyle.lerp(etiqueta, otro.etiqueta, t)!,
      sobrelinea: TextStyle.lerp(sobrelinea, otro.sobrelinea, t)!,
      pie: TextStyle.lerp(pie, otro.pie, t)!,
    );
  }
}

extension MitiTema on BuildContext {
  MitiColores get color => Theme.of(this).extension<MitiColores>()!;
  MitiTextos get texto => Theme.of(this).extension<MitiTextos>()!;
}

ThemeData construirTema(MitiColores c, Brightness brillo) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: brillo,
    fontFamily: 'Figtree',
    scaffoldBackgroundColor: c.papel,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.sello,
      brightness: brillo,
    ).copyWith(
      primary: c.sello,
      surface: c.papel,
      onSurface: c.tinta,
      error: c.sello,
    ),
  );

  return base.copyWith(
    extensions: [c, MitiTextos.base],
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: c.papel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: c.tinta,
      centerTitle: false,
    ),
    dividerTheme: DividerThemeData(color: c.troquel, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.tinta,
      contentTextStyle: MitiTextos.base.cuerpo.copyWith(color: c.tintaSobre),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      labelStyle: MitiTextos.base.etiqueta.copyWith(color: c.tintaSuave),
      hintStyle: MitiTextos.base.cuerpo.copyWith(color: c.tintaSuave),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: c.tinta, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: c.sello, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: c.sello, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: c.sello, width: 2),
      ),
    ),
  );
}
