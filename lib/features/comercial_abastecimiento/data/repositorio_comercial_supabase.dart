import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/supabase/api.dart';
import '../domain/repositorio_comercial.dart';

class RepositorioComercialSupabase implements RepositorioComercial {
  RepositorioComercialSupabase(this._api);
  final Api _api;

  @override
  Future<List<Registro>> clientes() => _api.consultar('clientes', '*', orden: 'razon_social', asc: true);

  @override
  Future<List<Registro>> proveedores() => _api.consultar('proveedores', '*', orden: 'razon_social', asc: true);

  @override
  Future<void> registrarCliente(Registro d) => _api.insertar('clientes', {...d, 'limite_credito': 0});

  @override
  Future<void> registrarProveedor(Registro d) => _api.insertar('proveedores', {...d, 'estado': 'inactivo'});

  @override
  Future<Registro> solicitarLimiteCredito(String clienteId, double limite, String motivo) =>
      _api.rpc('solicitar_limite_credito', {'p_cliente': clienteId, 'p_limite': limite, 'p_motivo': motivo});

  @override
  Future<List<Registro>> compras() => _api.consultar('compras',
      'id, fecha, total, saldo, estado, fecha_registro, proveedores(razon_social, tipo), '
      'registrante:usuarios!compras_registrado_por_fkey(nombre_completo), aprobador:usuarios!compras_aprobado_por_fkey(nombre_completo), '
      'compra_detalle(cantidad, precio_unitario, pesaje_id, productos(nombre)), pagos(monto, metodo, fecha_registro)',
      orden: 'fecha', limite: 200);

  @override
  Future<List<Registro>> pesajesDeProductor(String proveedorId) async {
    final l = await _api.consultar('pesajes', 'id, placa, peso_neto, humedad, peso_ajustado, fecha_dispositivo, granos(nombre), compra_detalle(id)',
        igual: {'proveedor_id': proveedorId, 'estado': 'confirmado'}, orden: 'fecha_dispositivo');
    return l.where((p) => (p['compra_detalle'] as List?)?.isEmpty ?? true).toList();
  }

  @override
  Future<Registro> registrarCompra(String proveedorId, DateTime fecha, List<Registro> items) =>
      _api.rpc('registrar_compra', {'p_proveedor': proveedorId, 'p_fecha': isoDia(fecha), 'p_items': items});

  @override
  Future<Registro> registrarPago(String compraId, double monto, String metodo) =>
      _api.rpc('registrar_pago', {'p_compra': compraId, 'p_monto': monto, 'p_metodo': metodo});

  @override
  Future<List<Registro>> pedidos() => _api.consultar('pedidos',
      'id, unidad_venta, estado, fecha_registro, clientes(razon_social, tipo), '
      'pedido_detalle(lote_id, cantidad, rollos_equivalentes, precio_unitario, lotes(codigo, fecha_sellado, productos(nombre))), notas_venta(id, numero, estado)',
      orden: 'fecha_registro', limite: 200);

  @override
  Future<Registro> registrarPedido(String clienteId, String unidad, List<Registro> items, String estado) =>
      _api.rpc('registrar_pedido', {'p_cliente': clienteId, 'p_unidad': unidad, 'p_items': items, 'p_estado': estado});

  @override
  Future<Registro> confirmarPedido(String pedidoId) => _api.rpc('confirmar_pedido', {'p_pedido': pedidoId});

  @override
  Future<Registro> cancelarPedido(String pedidoId) => _api.rpc('cancelar_pedido', {'p_pedido': pedidoId});

  @override
  Future<List<Registro>> notasVenta() => _api.rpcLista('notas_venta_detalle');

  @override
  Future<Registro> emitirNotaVenta(String pedidoId, String condicion, double descuento, String? factura) => _api.rpc('emitir_nota_venta',
      {'p_pedido': pedidoId, 'p_condicion': condicion, 'p_descuento': descuento, 'p_nro_factura': factura});

  @override
  Future<Registro> registrarFactura(String notaId, String numero) => _api.rpc('registrar_nro_factura', {'p_nota': notaId, 'p_nro': numero});

  @override
  Future<Registro> registrarCobro(String notaId, double monto, String metodo) =>
      _api.rpc('registrar_cobro', {'p_nota': notaId, 'p_monto': monto, 'p_metodo': metodo});

  @override
  Future<Registro> solicitarAnulacionVenta(String notaId, String motivo) =>
      _api.rpc('solicitar_anulacion_venta', {'p_nota': notaId, 'p_motivo': motivo});

  @override
  Future<Registro> solicitarAnulacionCobro(String cobroId, String motivo) =>
      _api.rpc('solicitar_anulacion_cobro', {'p_cobro': cobroId, 'p_motivo': motivo});

  @override
  Future<List<Registro>> despachosPendientes() => _api.rpcLista('despachos_pendientes');

  @override
  Future<List<Registro>> despachos() => _api.consultar('despachos',
      'id, cantidad, peso_vendido, tolerancia_pct, peso_despachado, peso_bascula_publica, placa, receptor, fecha_registro, '
      'lotes(codigo), sedes(nombre), notas_venta(numero), despacho_rollos(numero_rollo, peso)',
      orden: 'fecha_registro', limite: 200);

  @override
  Future<Registro> registrarDespacho(String notaId, String loteId, List<double> pesos, String placa, String receptor, double? pesoBascula) =>
      _api.rpc('registrar_despacho', {
        'p_nota': notaId,
        'p_lote': loteId,
        'p_pesos': pesos,
        'p_placa': placa,
        'p_receptor': receptor,
        'p_peso_bascula': pesoBascula,
      });

  @override
  Future<Registro> registrarPesoBascula(String despachoId, double peso) =>
      _api.rpc('registrar_peso_bascula', {'p_despacho': despachoId, 'p_peso': peso});
}

final repositorioComercialProvider = Provider<RepositorioComercial>((ref) => RepositorioComercialSupabase(ref.watch(apiProvider)));
