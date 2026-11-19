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
  });

  factory RegistroPendiente.desdeJson(Map<String, dynamic> j) => RegistroPendiente(
        id: j['id'] as String,
        tabla: j['tabla'] as String,
        datos: Map<String, dynamic>.from(j['datos'] as Map),
        creado: DateTime.parse(j['creado'] as String),
        estado: j['estado'] as String? ?? 'pendiente',
        motivo: j['motivo'] as String?,
      );

  final String id;
  final String tabla;
  final Map<String, dynamic> datos;
  final DateTime creado;
  final String estado;
  final String? motivo;

  bool get rechazado => estado == 'rechazado';

  Map<String, dynamic> aJson() =>
      {'id': id, 'tabla': tabla, 'datos': datos, 'creado': creado.toIso8601String(), 'estado': estado, 'motivo': motivo};

  RegistroPendiente rechazar(String m) =>
      RegistroPendiente(id: id, tabla: tabla, datos: datos, creado: creado, estado: 'rechazado', motivo: m);

  String get descripcion => switch (tabla) {
        'pesajes' => 'Pesaje placa ${datos['placa']} · ${datos['peso_bruto']} kg bruto',
        'ordenes_ensilado' => 'Apertura de orden de ensilado',
        'consumos_insumo' => 'Consumo de insumo · ${datos['cantidad']}',
        'revisiones_fermentacion' => 'Revisión de fermentación · film ${datos['estado_film']}',
        _ => tabla,
      };
}

/// Tablas que admiten registro sin conexión (el resto exige conexión: despachos, guías, ventas y cobros).
const tablasSinConexion = {'pesajes', 'ordenes_ensilado', 'consumos_insumo', 'revisiones_fermentacion'};

/// Ordena la cola para enviarla: primero lo más antiguo, y las órdenes antes que sus pesajes y consumos.
List<RegistroPendiente> ordenDeEnvio(List<RegistroPendiente> cola) {
  int peso(String t) => t == 'ordenes_ensilado' ? 0 : 1;
  final l = cola.where((r) => !r.rechazado).toList()
    ..sort((a, b) {
      final c = a.creado.compareTo(b.creado);
      return c != 0 ? c : peso(a.tabla).compareTo(peso(b.tabla));
    });
  return l;
}
