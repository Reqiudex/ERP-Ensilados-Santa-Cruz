typedef Registro = Map<String, dynamic>;

/// Contrato del módulo Comercial y Abastecimiento.
abstract interface class RepositorioComercial {
  Future<List<Registro>> clientes();
  Future<List<Registro>> proveedores();
  Future<void> registrarCliente(Registro datos);
  Future<void> registrarProveedor(Registro datos);
  Future<Registro> solicitarLimiteCredito(String clienteId, double limite, String motivo);

  Future<List<Registro>> compras();
  Future<List<Registro>> pesajesDeProductor(String proveedorId);
  Future<Registro> registrarCompra(String proveedorId, DateTime fecha, List<Registro> items);
  Future<Registro> registrarPago(String compraId, double monto, String metodo);

  Future<List<Registro>> pedidos();
  Future<Registro> registrarPedido(String clienteId, String unidad, List<Registro> items, String estado);
  Future<Registro> confirmarPedido(String pedidoId);
  Future<Registro> cancelarPedido(String pedidoId);

  Future<List<Registro>> notasVenta();
  Future<Registro> emitirNotaVenta(String pedidoId, String condicion, double descuento, String? factura);
  Future<Registro> registrarFactura(String notaId, String numero);
  Future<Registro> registrarCobro(String notaId, double monto, String metodo);
  Future<Registro> solicitarAnulacionVenta(String notaId, String motivo);
  Future<Registro> solicitarAnulacionCobro(String cobroId, String motivo);

  Future<List<Registro>> despachosPendientes();
  Future<List<Registro>> despachos();
  Future<Registro> registrarDespacho(String notaId, String loteId, List<double> pesos, String placa, String receptor, double? pesoBascula);
  Future<Registro> registrarPesoBascula(String despachoId, double peso);
}
