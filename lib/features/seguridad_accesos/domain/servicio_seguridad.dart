/// Servicio de seguridad del módulo de Seguridad y Accesos (Dart puro, sin Flutter).
///
/// Centraliza las reglas que la interfaz aplica antes de llamar al servidor. El servidor (funciones y RLS de
/// Supabase) vuelve a validar todo; este servicio no reemplaza esos controles, solo los adelanta.
library;

import 'package:bcrypt/bcrypt.dart';

/// Error de negocio de la guardia WORM: la bitácora no admite cambios ni borrados.
class OperacionNoPermitida implements Exception {
  const OperacionNoPermitida(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}

class ServicioSeguridad {
  ServicioSeguridad({DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;
  final DateTime Function() _reloj;

  // ------------------------------------------------------------------ 1. Hash seguro (bcrypt con sal dinámica)
  /// Costo de bcrypt para credenciales locales (PIN sin conexión). Cada hash lleva su propia sal aleatoria.
  static const costoBcrypt = 10;

  String hashCredencial(String secreto) => BCrypt.hashpw(secreto, BCrypt.gensalt(logRounds: costoBcrypt));

  bool verificarCredencial(String secreto, String hash) {
    if (!esHashBcrypt(hash)) return false;
    try {
      return BCrypt.checkpw(secreto, hash);
    } catch (_) {
      return false;
    }
  }

  static bool esHashBcrypt(String? hash) => hash != null && RegExp(r'^\$2[aby]\$\d{2}\$').hasMatch(hash);

  // ------------------------------------------------------------------ 3. Límite de intentos (antes del servidor)
  final Map<String, List<DateTime>> _fallos = {};

  /// Registra un intento fallido para una clave (usuario o identificador).
  void registrarFallo(String clave) => (_fallos[clave.toLowerCase()] ??= []).add(_reloj());

  void limpiarFallos(String clave) => _fallos.remove(clave.toLowerCase());

  /// Minutos que faltan para volver a intentar, o 0 si puede intentar. Usa los mismos parámetros que el servidor.
  int minutosDeEspera(String clave, {required int intentosMaximos, required int minutosBloqueo}) {
    final ahora = _reloj();
    final ventana = Duration(minutes: minutosBloqueo);
    final l = (_fallos[clave.toLowerCase()] ?? [])..removeWhere((t) => ahora.difference(t) > ventana);
    if (l.length < intentosMaximos) return 0;
    final libre = l[l.length - intentosMaximos].add(ventana);
    return (libre.difference(ahora).inSeconds / 60).ceil().clamp(1, minutosBloqueo);
  }

  // ------------------------------------------------------------------ 4. Sanitización de entradas
  static final _control = RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]');
  static final _etiquetas = RegExp(r'<[^>]*>');
  static final _peligrosos = RegExp(r'''[<>"'`;\\]''');

  /// Quita caracteres de control, etiquetas HTML y caracteres usados en XSS o inyección, y normaliza espacios.
  /// Las consultas al servidor son siempre parametrizadas (PostgREST/RPC); esto es una defensa adicional.
  String sanitizar(String? texto, {int maximo = 500}) {
    var t = (texto ?? '').replaceAll(_control, '').replaceAll(_etiquetas, '').replaceAll(_peligrosos, '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > maximo ? t.substring(0, maximo) : t;
  }

  /// Nombre completo: solo letras (con tildes y ñ) y espacios, en MAYÚSCULAS.
  static String normalizarNombre(String texto) =>
      texto.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ ]'), '').replaceAll(RegExp(r' {2,}'), ' ').toUpperCase();

  /// Documento de identidad: solo dígitos.
  static String normalizarCi(String texto) => texto.replaceAll(RegExp(r'[^0-9]'), '');

  // ------------------------------------------------------------------ 5. Guardia WORM
  /// La bitácora es de solo inserción y lectura (Write Once, Read Many). Cualquier intento de modificarla o
  /// borrarla desde la aplicación se detiene aquí; la base de datos también lo rechaza con un disparador.
  Never guardiaWorm(String operacion) =>
      throw OperacionNoPermitida('La bitácora es inalterable: la operación «$operacion» no está permitida.');
}
