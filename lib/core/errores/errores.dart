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

ErrorNegocio traducirError(Object error, {String? codigo, String? mensaje, String? detalle}) {
  final c = codigo ?? '';
  final m = mensaje ?? error.toString();
  if (c == 'red' || esErrorRed(error, m)) {
    return const ErrorNegocio('Sin conexión con el servidor. Revise su internet e intente de nuevo.', codigo: 'red');
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
    'PGRST301' || '401' => ErrorNegocio('Su sesión venció. Vuelva a iniciar sesión.', codigo: c),
    _ when m.toLowerCase().contains('invalid login') || m.toLowerCase().contains('banned') =>
      const ErrorNegocio('Credenciales incorrectas o cuenta bloqueada temporalmente.'),
    _ => const ErrorNegocio('No se pudo completar la operación. Intente de nuevo o avise al administrador.'),
  };
}
