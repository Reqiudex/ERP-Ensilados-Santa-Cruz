import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/almacenamiento/almacen_local.dart';
import '../domain/perfil.dart';
import '../domain/reglas_seguridad.dart';
import '../domain/servicio_seguridad.dart';

/// PIN personal para desbloquear sin conexión (solo Android): se guarda su hash bcrypt (sal aleatoria por PIN),
/// nunca el PIN. Tres errores o 12 horas sin sincronizar obligan a iniciar sesión en línea.
class PinLocal {
  PinLocal(this._almacen, [ServicioSeguridad? seguridad]) : _seguridad = seguridad ?? ServicioSeguridad();
  final AlmacenSeguro _almacen;
  final ServicioSeguridad _seguridad;

  /// Formato anterior (SHA-256 iterado con sal). Solo se usa para verificar PIN antiguos y migrarlos a bcrypt.
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
    await _almacen.escribir('pin_sal', null);
    await _almacen.escribir('pin_resumen', _seguridad.hashCredencial(pin));
    await _almacen.escribir('pin_usuario', perfil.id);
    await _almacen.escribir('pin_intentos', '0');
    await guardarPerfil(perfil);
  }

  Future<void> guardarPerfil(Perfil perfil) async {
    await _almacen.escribir('perfil_cache', jsonEncode(perfil.aJson()));
    await marcarSincronizado();
  }

  /// Guarda el resumen bcrypt de la contraseña del último ingreso en línea para permitir entrar sin señal
  /// incluso si el operador cerró sesión o el teléfono se reinició sin PIN configurado.
  Future<void> guardarCredencialesOffline(Perfil perfil, String clave) async {
    await guardarPerfil(perfil);
    await _almacen.escribir('clave_resumen', _seguridad.hashCredencial(clave));
    await _almacen.escribir('clave_usuario', perfil.id);
    await _almacen.escribir('clave_correo', perfil.correo.toLowerCase());
    await _almacen.escribir('clave_ci', perfil.ci.trim());
  }

  /// Verifica el identificador (CI o correo) y la contraseña contra el caché local cuando no hay señal.
  Future<Perfil?> verificarCredencialesOffline(String identificador, String clave) async {
    final id = identificador.trim().toLowerCase();
    if (id.isEmpty || clave.isEmpty) return null;
    final guardado = await perfilGuardado();
    if (guardado == null) return null;
    final correo = (await _almacen.leer('clave_correo')) ?? guardado.correo.toLowerCase();
    final ci = (await _almacen.leer('clave_ci')) ?? guardado.ci.trim();
    if (id != correo && id != ci) return null;
    final hash = await _almacen.leer('clave_resumen');
    if (hash == null || !_seguridad.verificarCredencial(clave, hash)) return null;
    return guardado;
  }

  Future<void> marcarSincronizado() => _almacen.escribir('ultima_sync', DateTime.now().toIso8601String());

  Future<Perfil?> perfilGuardado() async {
    final t = await _almacen.leer('perfil_cache');
    if (t == null) return null;
    try {
      return Perfil.desdeJson(jsonDecode(t) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
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
    final bcrypt = ServicioSeguridad.esHashBcrypt(guardado);
    final correcto = guardado != null && (bcrypt ? _seguridad.verificarCredencial(pin, guardado) : resumen(pin, sal) == guardado);
    final resultado = evaluarIntentoPin(
        pinCorrecto: correcto,
        estado: est,
        ahora: DateTime.now(),
        intentosMaximos: intentos,
        horasMaximas: horas);
    switch (resultado) {
      case ResultadoPin.desbloqueado:
        await _almacen.escribir('pin_intentos', '0');
        if (!bcrypt) {
          // PIN guardado con el formato anterior: se migra a bcrypt.
          await _almacen.escribir('pin_resumen', _seguridad.hashCredencial(pin));
          await _almacen.escribir('pin_sal', null);
        }
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
