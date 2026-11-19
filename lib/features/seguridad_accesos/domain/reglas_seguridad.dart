/// Reglas de seguridad del cliente (RF-03 y RF-04). Dart puro; el servidor vuelve a validarlas.
library;

/// Política de contraseñas configurable (parámetros en la base de datos).
class PoliticaClave {
  const PoliticaClave({
    this.longitudMinima = 8,
    this.mayusculas = true,
    this.minusculas = true,
    this.numeros = true,
    this.simbolos = true,
  });

  factory PoliticaClave.desdeParametros(Map<String, dynamic> p) => PoliticaClave(
        longitudMinima: (p['clave_longitud_min'] as num?)?.toInt() ?? 8,
        mayusculas: p['clave_mayusculas'] as bool? ?? true,
        minusculas: p['clave_minusculas'] as bool? ?? true,
        numeros: p['clave_numeros'] as bool? ?? true,
        simbolos: p['clave_simbolos'] as bool? ?? true,
      );

  final int longitudMinima;
  final bool mayusculas;
  final bool minusculas;
  final bool numeros;
  final bool simbolos;
}

class EvaluacionClave {
  const EvaluacionClave(this.puntaje, this.faltantes);
  final int puntaje;
  final List<String> faltantes;
  bool get valida => faltantes.isEmpty;
  String get nivel => puntaje >= 85 ? 'Fuerte' : puntaje >= 60 ? 'Aceptable' : puntaje >= 30 ? 'Débil' : 'Muy débil';
}

/// Evaluador de 0 a 100 con la lista de reglas que faltan (misma lógica que app.evaluar_clave).
EvaluacionClave evaluarClave(String clave, [PoliticaClave politica = const PoliticaClave()]) {
  final faltan = <String>[];
  var puntaje = (clave.length * 40 ~/ (politica.longitudMinima < 1 ? 1 : politica.longitudMinima)).clamp(0, 40);
  if (clave.length < politica.longitudMinima) faltan.add('Al menos ${politica.longitudMinima} caracteres');
  if (RegExp(r'[A-ZÁÉÍÓÚÑ]').hasMatch(clave)) {
    puntaje += 15;
  } else if (politica.mayusculas) {
    faltan.add('Una letra mayúscula');
  }
  if (RegExp(r'[a-záéíóúñ]').hasMatch(clave)) {
    puntaje += 15;
  } else if (politica.minusculas) {
    faltan.add('Una letra minúscula');
  }
  if (RegExp(r'[0-9]').hasMatch(clave)) {
    puntaje += 15;
  } else if (politica.numeros) {
    faltan.add('Un número');
  }
  if (RegExp(r'[^A-Za-z0-9ÁÉÍÓÚÑáéíóúñ]').hasMatch(clave)) {
    puntaje += 15;
  } else if (politica.simbolos) {
    faltan.add('Un símbolo');
  }
  return EvaluacionClave(puntaje.clamp(0, 100), faltan);
}

/// Validaciones del formulario de usuario (RF-01).
String? validarNombre(String v) =>
    RegExp(r'^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ ]{3,120}$').hasMatch(v.trim()) ? null : 'Solo letras y espacios (mínimo 3).';
String? validarCi(String v) => RegExp(r'^[0-9]{5,15}$').hasMatch(v.trim()) ? null : 'Solo números (5 a 15 dígitos).';
String? validarCorreo(String v) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? null : 'Correo no válido.';

/// Cierre por inactividad (CP-04).
bool sesionVencidaPorInactividad(DateTime ultimaActividad, DateTime ahora, {int minutos = 15}) =>
    ahora.difference(ultimaActividad) >= Duration(minutes: minutos);

/// Estado del desbloqueo sin conexión con PIN (RF-04, CP-26).
class EstadoPin {
  const EstadoPin({required this.intentosFallidos, required this.ultimaSincronizacion});
  final int intentosFallidos;
  final DateTime ultimaSincronizacion;
}

enum ResultadoPin { desbloqueado, incorrecto, exigeInicioEnLinea }

/// Valida el formato del PIN (4 a 6 dígitos).
bool pinConFormatoValido(String pin, {int minimo = 4, int maximo = 6}) =>
    RegExp('^[0-9]{$minimo,$maximo}\$').hasMatch(pin);

/// Decide el resultado de un intento de PIN: tres errores o 12 horas sin sincronizar exigen iniciar sesión en línea.
ResultadoPin evaluarIntentoPin({
  required bool pinCorrecto,
  required EstadoPin estado,
  required DateTime ahora,
  int intentosMaximos = 3,
  int horasMaximas = 12,
}) {
  if (ahora.difference(estado.ultimaSincronizacion) > Duration(hours: horasMaximas)) {
    return ResultadoPin.exigeInicioEnLinea;
  }
  if (estado.intentosFallidos >= intentosMaximos) return ResultadoPin.exigeInicioEnLinea;
  if (pinCorrecto) return ResultadoPin.desbloqueado;
  return estado.intentosFallidos + 1 >= intentosMaximos ? ResultadoPin.exigeInicioEnLinea : ResultadoPin.incorrecto;
}

/// Enmascara datos personales en la bitácora (RF-05): us*****@dominio.com, 65****10.
String enmascararCorreo(String correo) {
  final partes = correo.split('@');
  if (partes.length != 2) return correo;
  final u = partes[0];
  return '${u.length <= 2 ? u : u.substring(0, 2)}*****@${partes[1]}';
}

String enmascararCi(String ci) => ci.length <= 4 ? '****' : '${ci.substring(0, 2)}${'*' * (ci.length - 4)}${ci.substring(ci.length - 2)}';

/// Enmascara recursivamente correos, CI y cualquier campo de claves en un mapa de datos.
Object? enmascararDatos(Object? dato) {
  if (dato is Map) {
    return dato.map((k, v) {
      final clave = k.toString().toLowerCase();
      if (clave.contains('password') || clave.contains('clave') || clave.contains('pin') || clave.contains('token')) {
        return MapEntry(k, '••••');
      }
      if (clave == 'correo' || clave == 'email') return MapEntry(k, v is String ? enmascararCorreo(v) : v);
      if (clave == 'ci' || clave == 'nit_ci') return MapEntry(k, v is String ? enmascararCi(v) : v);
      return MapEntry(k, enmascararDatos(v));
    });
  }
  if (dato is List) return dato.map(enmascararDatos).toList();
  return dato;
}
