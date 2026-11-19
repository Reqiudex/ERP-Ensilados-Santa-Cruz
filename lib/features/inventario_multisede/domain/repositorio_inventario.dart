typedef Registro = Map<String, dynamic>;

/// Contrato del módulo Inventario y Logística.
abstract interface class RepositorioInventario {
  Future<List<Registro>> existencias();
  Stream<List<Registro>> existenciasEnVivo();
  Future<List<Registro>> sedes();
  Future<List<Registro>> lotes();
  Future<Registro> trazabilidad(String loteId);
  Future<List<Registro>> catalogo();
  Future<List<Registro>> catalogoSinPrecios();
  Future<List<Registro>> guias();
  Future<Registro> emitirGuia(String destino, List<Registro> items);
  Future<Registro> recibirGuia(String guiaId, List<Registro> items);
  Future<Registro> solicitarMerma(String loteId, int cantidad, String causa, String descripcion);
  Future<Registro> solicitarAjuste(String productoId, String? loteId, double cantidad, String descripcion);
  Future<Registro> solicitarProducto(Registro datos);
  Future<Registro> solicitarCambioPrecio(String productoId, double precioTonelada, double precioRollo, String motivo);
}
