import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/api.dart';

/// Simulación de falta de red (modo avión) para la demostración y las pruebas CP-09 y CP-26.
class ModoSinRed extends Notifier<bool> {
  @override
  bool build() => false;
  void cambiar(bool v) => state = v;
}

final modoSinRedProvider = NotifierProvider<ModoSinRed, bool>(ModoSinRed.new);

/// Estado de la red del dispositivo.
final redProvider = StreamProvider<bool>((ref) async* {
  if (kIsWeb) {
    yield true;
    return;
  }
  final c = Connectivity();
  bool hay(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);
  yield hay(await c.checkConnectivity());
  yield* c.onConnectivityChanged.map(hay);
});

/// En línea = hay red y no se está simulando el modo avión.
final enLineaProvider = Provider<bool>((ref) {
  if (ref.watch(modoSinRedProvider)) return false;
  return ref.watch(redProvider).value ?? true;
});

/// Latencia con el servidor (indicador de RF-06).
class Latencia {
  const Latencia({required this.ms, required this.ok, required this.version, required this.hora});
  final int ms;
  final bool ok;
  final String version;
  final DateTime hora;
}

final latenciaProvider = FutureProvider.autoDispose<Latencia>((ref) async {
  final api = ref.watch(apiProvider);
  final reloj = Stopwatch()..start();
  try {
    final r = await api.rpc('estado_conexion');
    reloj.stop();
    return Latencia(ms: reloj.elapsedMilliseconds, ok: true, version: '${r['version'] ?? ''}', hora: DateTime.now());
  } catch (_) {
    return Latencia(ms: reloj.elapsedMilliseconds, ok: false, version: '', hora: DateTime.now());
  }
});
