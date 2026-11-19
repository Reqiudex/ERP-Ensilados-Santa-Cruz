import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/almacenamiento/almacen_local.dart';
import '../domain/perfil.dart';
import '../domain/reglas_seguridad.dart';

/// PIN personal para desbloquear sin conexión (solo Android): se guarda el resumen SHA-256 con sal,
/// nunca el PIN. Tres errores o 12 horas sin sincronizar obligan a iniciar sesión en línea.
class PinLocal {
  PinLocal(this._almacen);
  final AlmacenSeguro _almacen;

  static String resumen(String pin, String sal) {
    List<int> bytes = utf8.encode('$sal:$pin');
    for (var i = 0; i < 5000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64Encode(bytes);
  }

  Future<bool> tienePin(String usuarioId) async => (await _almacen.leer('pin_usuario')) == usuarioId &&
      (await _almacen.leer('pin_resumen')) != null;

  Future<void> configurar(Perfil perfil, String pin) async {
    final r = Random.secure();
    final sal = base64Encode(List<int>.generate(16, (_) => r.nextInt(256)));
    await _almacen.escribir('pin_sal', sal);
    await _almacen.escribir('pin_resumen', resumen(pin, sal));
    await _almacen.escribir('pin_usuario', perfil.id);
    await _almacen.escribir('pin_intentos', '0');
    await guardarPerfil(perfil);
  }

  Future<void> guardarPerfil(Perfil perfil) async {
    await _almacen.escribir('perfil_cache', jsonEncode(perfil.aJson()));
    await marcarSincronizado();
  }

  Future<void> marcarSincronizado() => _almacen.escribir('ultima_sync', DateTime.now().toIso8601String());

  Future<Perfil?> perfilGuardado() async {
    final t = await _almacen.leer('perfil_cache');
    return t == null ? null : Perfil.desdeJson(jsonDecode(t) as Map<String, dynamic>);
  }

  Future<EstadoPin> estado() async => EstadoPin(
        intentosFallidos: int.tryParse(await _almacen.leer('pin_intentos') ?? '0') ?? 0,
        ultimaSincronizacion: DateTime.tryParse(await _almacen.leer('ultima_sync') ?? '') ?? DateTime(2000),
      );

  /// Intenta desbloquear; si se agotan los intentos borra el PIN y exige iniciar sesión en línea.
  Future<ResultadoPin> desbloquear(String pin, {int intentos = 3, int horas = 12}) async {
    final sal = await _almacen.leer('pin_sal') ?? '';
    final guardado = await _almacen.leer('pin_resumen');
    final est = await estado();
    final resultado = evaluarIntentoPin(
        pinCorrecto: guardado != null && resumen(pin, sal) == guardado,
        estado: est,
        ahora: DateTime.now(),
        intentosMaximos: intentos,
        horasMaximas: horas);
    switch (resultado) {
      case ResultadoPin.desbloqueado:
        await _almacen.escribir('pin_intentos', '0');
      case ResultadoPin.incorrecto:
        await _almacen.escribir('pin_intentos', '${est.intentosFallidos + 1}');
      case ResultadoPin.exigeInicioEnLinea:
        await borrar();
    }
    return resultado;
  }

  Future<void> borrar() async {
    for (final k in ['pin_sal', 'pin_resumen', 'pin_usuario', 'pin_intentos']) {
      await _almacen.escribir(k, null);
    }
  }
}

final pinLocalProvider = Provider<PinLocal>((ref) => PinLocal(ref.watch(almacenSeguroProvider)));
