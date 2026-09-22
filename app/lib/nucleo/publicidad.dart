import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../estado/sesion.dart';

/// Publicidad del plan gratis (§11): AdMob.
///
/// Reglas que NO se negocian:
/// - sólo en campañas cuyo plan tiene publicidad (el gratis);
/// - banner en listas; nunca en las pantallas de plata (inicio de la campaña,
///   cajas, ventas, gastos, liquidación);
/// - como mucho un intersticial al generar una imagen, y no más de uno cada 10 minutos.
///
/// Los ID de los bloques se pasan al compilar:
///   flutter build apk --dart-define=ADMOB_BANNER=ca-app-pub-.../... --dart-define=ADMOB_INTERSTICIAL=...
/// Sin eso se usan los ID de prueba de Google, que muestran anuncios de muestra.
class Publicidad {
  static const _banner = String.fromEnvironment(
    'ADMOB_BANNER',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );
  static const _intersticial = String.fromEnvironment(
    'ADMOB_INTERSTICIAL',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );

  static bool _iniciada = false;
  static DateTime? _ultimoIntersticial;

  static Future<void> iniciar() async {
    if (_iniciada) return;
    try {
      await MobileAds.instance.initialize();
      _iniciada = true;
    } catch (e) {
      debugPrint('AdMob no arrancó: $e');
    }
  }

  /// Muestra un intersticial si corresponde. Nunca frena lo que el usuario estaba haciendo:
  /// si el anuncio no carga, sigue de largo.
  static Future<void> intersticialAlGenerarImagen() async {
    if (!_iniciada) return;
    final ahora = DateTime.now();
    if (_ultimoIntersticial != null && ahora.difference(_ultimoIntersticial!) < const Duration(minutes: 10)) {
      return;
    }
    _ultimoIntersticial = ahora;
    await InterstitialAd.load(
      adUnitId: _intersticial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (anuncio) {
          anuncio.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (a) => a.dispose(),
            onAdFailedToShowFullScreenContent: (a, _) => a.dispose(),
          );
          anuncio.show();
        },
        onAdFailedToLoad: (e) => debugPrint('Intersticial no cargó: $e'),
      ),
    );
  }
}

/// Planes que llevan publicidad, según el servidor (se editan desde el panel).
final planesConPublicidadProvider = FutureProvider<Set<String>>((ref) async {
  try {
    final planes = await ref.watch(apiProvider).planes();
    return {for (final p in planes) if (p['publicidad'] == true) p['codigo'] as String};
  } catch (_) {
    return {'gratis'}; // sin señal: lo que dice §11
  }
});

/// ¿Esta campaña muestra publicidad?
final publicidadEnCampanaProvider = Provider.family<bool, String>((ref, campanaId) {
  final con = ref.watch(planesConPublicidadProvider).valueOrNull;
  final campana = ref.watch(campanaProvider(campanaId)).valueOrNull;
  if (con == null || campana == null) return false;
  return con.contains(campana['plan']);
});

/// Banner al pie de una lista. Si no carga, no ocupa lugar.
class BannerMiti extends StatefulWidget {
  const BannerMiti({super.key, required this.mostrar});

  final bool mostrar;

  @override
  State<BannerMiti> createState() => _BannerMitiState();
}

class _BannerMitiState extends State<BannerMiti> {
  BannerAd? _anuncio;
  bool _listo = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cargar();
  }

  @override
  void didUpdateWidget(BannerMiti anterior) {
    super.didUpdateWidget(anterior);
    if (widget.mostrar != anterior.mostrar) _cargar();
  }

  Future<void> _cargar() async {
    if (!widget.mostrar || _anuncio != null || !Publicidad._iniciada) return;
    final ancho = MediaQuery.of(context).size.width.truncate();
    final tamano = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(ancho);
    if (tamano == null || !mounted) return;
    final anuncio = BannerAd(
      adUnitId: Publicidad._banner,
      size: tamano,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _listo = true);
        },
        onAdFailedToLoad: (a, e) {
          a.dispose();
          debugPrint('Banner no cargó: $e');
        },
      ),
    );
    _anuncio = anuncio;
    await anuncio.load();
  }

  @override
  void dispose() {
    _anuncio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anuncio = _anuncio;
    if (!widget.mostrar || !_listo || anuncio == null) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: SizedBox(
        width: anuncio.size.width.toDouble(),
        height: anuncio.size.height.toDouble(),
        child: AdWidget(ad: anuncio),
      ),
    );
  }
}
