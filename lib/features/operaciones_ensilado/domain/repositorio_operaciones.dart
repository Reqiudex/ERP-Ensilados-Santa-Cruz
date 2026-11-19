typedef Registro = Map<String, dynamic>;

/// Contrato del módulo Operaciones y Procesamiento.
abstract interface class RepositorioOperaciones {
  Future<List<Registro>> granos();
  Future<List<Registro>> productores();
  Future<List<Registro>> pesajes({int limite = 100});
  Future<List<Registro>> ordenes({String? estado});
  Future<List<Registro>> consumos(String ordenId);
  Future<List<Registro>> insumosDisponibles();
  Future<List<Registro>> lotesEnFermentacion();
  Future<List<Registro>> revisiones(String loteId);

  /// Inserta un registro hecho con o sin conexión; no duplica si el identificador ya existe.
  Future<void> sincronizar(String tabla, Registro datos);

  Future<Registro> cerrarOrden(String ordenId, int rollos);
  Future<Registro> solicitarCorreccion(String pesajeId, double bruto, double tara, double humedad, double impurezas, String motivo);
  Future<int> actualizarAptos();
}
