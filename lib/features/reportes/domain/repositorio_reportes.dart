typedef Registro = Map<String, dynamic>;

/// Contrato del módulo Reportes (RF-20 a RF-23).
abstract interface class RepositorioReportes {
  Future<List<Registro>> rendimiento(DateTime desde, DateTime hasta);
  Future<List<Registro>> existencias();
  Future<List<Registro>> rotacion(DateTime desde, DateTime hasta);
  Future<Registro> ventas(DateTime desde, DateTime hasta, {String? clienteId});
  Future<Registro> mermas(DateTime desde, DateTime hasta);
  Future<List<Registro>> clientes();
}
