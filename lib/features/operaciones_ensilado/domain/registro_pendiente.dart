/// Registro hecho en el dispositivo que espera sincronizarse (pesajes, órdenes, consumos y revisiones).
/// Queda cerrado al guardarse: no se edita; si el servidor lo rechaza vuelve al operador con el motivo.
class RegistroPendiente {
  const RegistroPendiente({
    required this.id,
    required this.tabla,
    required this.datos,
    required this.creado,
    this.estado = 'pendiente',
    this.motivo,
    this.usuario,
    this.intentos = 0,
    this.ultimoError,
  });

  factory RegistroPendiente.desdeJson(Map<String, dynamic> j) => RegistroPendiente(
        id: j['id'] as String,
        tabla: j['tabla'] as String,
        datos: Map<String, dynamic>.from(j['datos'] as Map),
        creado: DateTime.parse(j['creado'] as String),
        estado: j['estado'] as String? ?? 'pendiente',
        motivo: j['motivo'] as String?,
        usuario: j['usuario'] as String?,
        intentos: (j['intentos'] as num?)?.toInt() ?? 0,
        ultimoError: j['ultimo_error'] as String?,
      );

  final String id;
  final String tabla;
  final Map<String, dynamic> datos;
  final DateTime creado;
  final String estado;
  final String? motivo;

  /// Cuenta que lo registró en el teléfono: solo esa cuenta lo envía al servidor.
  final String? usuario;

  /// Envíos fallidos por causas pasajeras (señal, sesión, servidor ocupado). No se descarta por ellos.
  final int intentos;
  final String? ultimoError;

  bool get rechazado => estado == 'rechazado';

  Map<String, dynamic> aJson() => {
        'id': id,
        'tabla': tabla,
        'datos': datos,
        'creado': creado.toIso8601String(),
        'estado': estado,
        'motivo': motivo,
        'usuario': usuario,
        'intentos': intentos,
        'ultimo_error': ultimoError,
      };

  RegistroPendiente rechazar(String m) => RegistroPendiente(
      id: id, tabla: tabla, datos: datos, creado: creado, estado: 'rechazado', motivo: m, usuario: usuario, intentos: intentos);

  /// Sigue pendiente, con el último error pasajero anotado.
  RegistroPendiente conError(String m) => RegistroPendiente(
      id: id, tabla: tabla, datos: datos, creado: creado, usuario: usuario, intentos: intentos + 1, ultimoError: m);

  /// Vuelve a la cola un registro rechazado (el operador decide reintentarlo).
  RegistroPendiente reintentar() =>
      RegistroPendiente(id: id, tabla: tabla, datos: datos, creado: creado, usuario: usuario);

  String get descripcion => switch (tabla) {
        'pesajes' => 'Pesaje placa ${datos['placa']} · ${datos['peso_bruto']} kg bruto',
        'ordenes_ensilado' => 'Apertura de orden de ensilado',
        'consumos_insumo' => 'Consumo de insumo · ${datos['cantidad']}',
        'revisiones_fermentacion' => 'Revisión de fermentación · film ${datos['estado_film']}',
        'cerrar_orden' => 'Cierre de orden de ensilado · ${datos['rollos']} rollos',
        'solicitar_correccion_pesaje' => 'Solicitud de corrección de pesaje',
        'solicitar_merma' => 'Solicitud de baja (merma) · ${datos['cantidad']} rollos',
        'solicitar_ajuste' => 'Solicitud de ajuste por conteo · ${datos['cantidad']} rollos',
        'emitir_guia' => 'Emisión de guía de transferencia',
        'recibir_guia' => 'Confirmación de recepción de guía',
        'registrar_despacho' => 'Despacho de rollos · placa ${datos['placa']}',
        'registrar_peso_bascula' => 'Registro de peso en báscula pública · ${datos['peso']} kg',
        _ => tabla,
      };
}

/// Tablas y operaciones RPC del centro de acopio que admiten registro sin conexión 24/7.
/// Al reconectar se sincronizan en orden cronológico y de dependencia.
const tablasSinConexion = {
  'pesajes',
  'ordenes_ensilado',
  'consumos_insumo',
  'revisiones_fermentacion',
  'cerrar_orden',
  'solicitar_correccion_pesaje',
  'solicitar_merma',
  'solicitar_ajuste',
  'emitir_guia',
  'recibir_guia',
  'registrar_despacho',
  'registrar_peso_bascula',
};

/// Ordena la cola para enviarla: primero lo más antiguo, respetando la cadena de dependencias
/// (apertura de orden → pesajes y consumos → cierre de orden → revisiones, guías, mermas, despachos y báscula).
List<RegistroPendiente> ordenDeEnvio(List<RegistroPendiente> cola) {
  int peso(String t) => switch (t) {
        'ordenes_ensilado' => 0,
        'pesajes' || 'consumos_insumo' => 1,
        'cerrar_orden' => 2,
        'revisiones_fermentacion' || 'solicitar_correccion_pesaje' => 3,
        'emitir_guia' || 'recibir_guia' || 'solicitar_merma' || 'solicitar_ajuste' => 4,
        'registrar_despacho' => 5,
        'registrar_peso_bascula' => 6,
        _ => 7,
      };
  final l = cola.where((r) => !r.rechazado).toList()
    ..sort((a, b) {
      final p = peso(a.tabla).compareTo(peso(b.tabla));
      return p != 0 ? p : a.creado.compareTo(b.creado);
    });
  return l;
}
