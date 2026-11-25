/// Traduce cualquier error técnico a un mensaje amigable (OWASP A05/A09): nunca muestra nombres de tablas,
/// restricciones ni detalles internos. El detalle técnico queda en la bitácora del servidor.
library;

class ErrorNegocio implements Exception {
  const ErrorNegocio(this.mensaje, {this.codigo, this.prohibido = false});
  final String mensaje;
  final String? codigo;
  final bool prohibido;
  @override
  String toString() => mensaje;
}

/// Mensajes por restricción CHECK o UNIQUE conocida.
const _restricciones = <String, String>{
  'solicitudes_aprobacion_check': 'Nadie puede aprobar una solicitud que registró: debe aprobarla otra persona.',
  'guias_transferencia_check1': 'La guía debe confirmarla un operador de otro centro (el receptor no puede ser el emisor).',
  'compras_check1': 'Quien registró la compra no puede aprobarla.',
  'pesajes_check': 'El peso bruto debe ser mayor que la tara.',
  'pesajes_tara_check': 'La tara debe ser mayor que cero.',
  'pesajes_humedad_check': 'La humedad debe estar entre 0 y 100 %.',
  'pesajes_check1': 'Indique el productor cuando el grano es de un productor.',
  'usuarios_ci_key': 'Ya existe una cuenta registrada con ese CI.',
  'usuarios_correo_key': 'Ya existe una cuenta registrada con ese correo.',
  'clientes_nit_ci_key': 'Ya existe un cliente con ese NIT o CI.',
  'proveedores_nit_ci_key': 'Ya existe un proveedor con ese NIT o CI.',
  'productos_sku_key': 'Ya existe un producto con ese SKU.',
};

/// Errores propios (lanzados por las funciones del servidor con un texto ya pensado para el usuario).
const _codigosPropios = {'P0001'};

/// Detecta si el error proviene de falta de red, DNS, socket o timeout (Android, iOS, web o pruebas).
bool esErrorRed(Object error, [String? mensaje]) {
  final m = '${mensaje ?? ''} $error'.toLowerCase();
  return m.contains('socket') ||
      m.contains('failed host') ||
      m.contains('clientexception') ||
      m.contains('network') ||
      m.contains('connection') ||
      m.contains('unreachable') ||
      m.contains('timed out') ||
      m.contains('timeout') ||
      m.contains('handshake') ||
      m.contains('errno =') ||
      m.contains('xmlhttprequest') ||
      m.contains('sin conexión');
}

/// Errores que no dependen de los datos: la operación se vuelve a intentar más tarde sin descartarla
/// (sin señal, sesión vencida o por renovar, servidor ocupado o en mantenimiento).
bool esErrorPasajero(ErrorNegocio e) => const {'red', 'sesion', 'servidor'}.contains(e.codigo);

ErrorNegocio traducirError(Object error, {String? codigo, String? mensaje, String? detalle}) {
  final c = codigo ?? '';
  final m = mensaje ?? error.toString();
  final ml = m.toLowerCase();
  // Un código SQLSTATE o de PostgREST significa que el servidor respondió: no es falta de señal aunque el texto
  // diga «sin conexión» (si se tomara por red, el registro bloquearía la cola para siempre).
  final respondio = RegExp(r'^([0-9A-Z]{5}|PGRST\d+)$').hasMatch(c);
  if (c == 'red' || (!respondio && esErrorRed(error, m))) {
    return const ErrorNegocio('Sin conexión con el servidor. Revise su internet e intente de nuevo.', codigo: 'red');
  }
  // Token vencido o inválido (PostgREST PGRST301/302/303, Auth 401): se renueva la sesión y se reintenta.
  if (const {'PGRST301', 'PGRST302', 'PGRST303', '401', 'sesion'}.contains(c) || ml.contains('jwt')) {
    return const ErrorNegocio('Su sesión venció. Vuelva a iniciar sesión.', codigo: 'sesion');
  }
  // Servidor caído, en pausa o recargando su esquema (5xx, 429, PGRST000/001/002).
  if (const {'500', '502', '503', '504', '429', 'PGRST000', 'PGRST001', 'PGRST002', '57014', '53300'}.contains(c) ||
      ml.contains('bad gateway') || ml.contains('service unavailable') || ml.contains('<html')) {
    return const ErrorNegocio('El servidor no responde por ahora. Se reintentará automáticamente.', codigo: 'servidor');
  }
  if (c == '42501' || c == '403') {
    final propio = m.isNotEmpty && !m.toLowerCase().contains('permission denied') && !m.contains('policy');
    return ErrorNegocio(propio ? m : 'Su rol no tiene permiso para esta operación.', codigo: '42501', prohibido: true);
  }
  if (_codigosPropios.contains(c)) return ErrorNegocio(m, codigo: c);
  for (final e in _restricciones.entries) {
    if (m.contains(e.key) || (detalle ?? '').contains(e.key)) return ErrorNegocio(e.value, codigo: c);
  }
  return switch (c) {
    '23505' => ErrorNegocio('Ya existe un registro con esos datos.', codigo: c),
    '23514' => ErrorNegocio('Los datos no cumplen una regla del sistema.', codigo: c),
    '23503' => ErrorNegocio('El registro está relacionado con otros datos y no puede usarse así.', codigo: c),
    '22001' || '22P02' || '22003' => ErrorNegocio('Algún dato tiene un formato o tamaño no válido.', codigo: c),
    _ when m.toLowerCase().contains('invalid login') || m.toLowerCase().contains('banned') =>
      const ErrorNegocio('Credenciales incorrectas o cuenta bloqueada temporalmente.'),
    _ => const ErrorNegocio('No se pudo completar la operación. Intente de nuevo o avise al administrador.'),
  };
}
