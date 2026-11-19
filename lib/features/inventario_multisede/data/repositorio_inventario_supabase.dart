import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/api.dart';
import '../domain/repositorio_inventario.dart';

class RepositorioInventarioSupabase implements RepositorioInventario {
  RepositorioInventarioSupabase(this._api);
  final Api _api;

  @override
  Future<List<Registro>> existencias() => _api.rpcLista('reporte_existencias');

  @override
  Stream<List<Registro>> existenciasEnVivo() => _api.flujo('existencias');

  @override
  Future<List<Registro>> sedes() => _api.consultar('sedes', 'id, nombre, tipo', orden: 'nombre', asc: true);

  @override
  Future<List<Registro>> lotes() => _api.consultar('lotes',
      'id, codigo, estado, fecha_sellado, rollos_producidos, peso_promedio_rollo, sede_id, sedes(nombre), productos(nombre, granos(nombre)), '
      'existencias(sede_id, disponible, reservado, en_transito)',
      orden: 'fecha_sellado', limite: 300);

  @override
  Future<Registro> trazabilidad(String loteId) async {
    final lote = (await _api.consultar('lotes',
            'id, codigo, estado, fecha_sellado, rollos_producidos, peso_promedio_rollo, sedes(nombre), productos(nombre), '
            'ordenes_ensilado(id, fecha_apertura, fecha_cierre, pesajes(placa, origen, peso_neto, humedad, peso_ajustado, estado, fecha_dispositivo))',
            igual: {'id': loteId}))
        .firstOrNull;
    final movimientos = await _api.consultar('movimientos_inventario',
        'tipo, cantidad, documento_tipo, fecha_registro, sedes(nombre)', igual: {'lote_id': loteId}, orden: 'fecha_registro', asc: true);
    final revisiones = await _api.consultar('revisiones_fermentacion', 'estado_film, observacion, fecha_registro',
        igual: {'lote_id': loteId}, orden: 'fecha_registro', asc: true);
    return {'lote': lote, 'movimientos': movimientos, 'revisiones': revisiones};
  }

  @override
  Future<List<Registro>> catalogo() => _api.rpcLista('catalogo_precios');

  @override
  Future<List<Registro>> catalogoSinPrecios() =>
      _api.consultar('productos', 'id, sku, nombre, tipo, grano_id, unidad, activo', orden: 'sku', asc: true);

  @override
  Future<List<Registro>> guias() => _api.consultar('guias_transferencia',
      'id, numero, estado, fecha_emision, fecha_recepcion, sede_origen, sede_destino, '
      'origen:sedes!guias_transferencia_sede_origen_fkey(nombre), destino:sedes!guias_transferencia_sede_destino_fkey(nombre), '
      'emisor:usuarios!guias_transferencia_emitido_por_fkey(nombre_completo), receptor:usuarios!guias_transferencia_recibido_por_fkey(nombre_completo), '
      'guia_detalle(lote_id, cantidad_enviada, cantidad_recibida, lotes(codigo))',
      orden: 'fecha_emision', limite: 100);

  @override
  Future<Registro> emitirGuia(String destino, List<Registro> items) => _api.rpc('emitir_guia', {'p_destino': destino, 'p_items': items});

  @override
  Future<Registro> recibirGuia(String guiaId, List<Registro> items) => _api.rpc('recibir_guia', {'p_guia': guiaId, 'p_items': items});

  @override
  Future<Registro> solicitarMerma(String loteId, int cantidad, String causa, String descripcion) => _api.rpc('solicitar_merma',
      {'p_lote': loteId, 'p_cantidad': cantidad, 'p_causa': causa, 'p_descripcion': descripcion});

  @override
  Future<Registro> solicitarAjuste(String productoId, String? loteId, double cantidad, String descripcion) => _api.rpc('solicitar_ajuste',
      {'p_producto': productoId, 'p_lote': loteId, 'p_cantidad': cantidad, 'p_descripcion': descripcion});

  @override
  Future<Registro> solicitarProducto(Registro d) => _api.rpc('solicitar_producto', {
        'p_sku': d['sku'],
        'p_nombre': d['nombre'],
        'p_tipo': d['tipo'],
        'p_grano': d['grano_id'],
        'p_unidad': d['unidad'],
        'p_precio_tonelada': d['precio_tonelada'],
        'p_precio_rollo': d['precio_rollo'],
        'p_motivo': d['motivo'],
      });

  @override
  Future<Registro> solicitarCambioPrecio(String productoId, double precioTonelada, double precioRollo, String motivo) => _api.rpc(
      'solicitar_cambio_precio', {'p_producto': productoId, 'p_precio_tonelada': precioTonelada, 'p_precio_rollo': precioRollo, 'p_motivo': motivo});
}

final repositorioInventarioProvider = Provider<RepositorioInventario>((ref) => RepositorioInventarioSupabase(ref.watch(apiProvider)));
