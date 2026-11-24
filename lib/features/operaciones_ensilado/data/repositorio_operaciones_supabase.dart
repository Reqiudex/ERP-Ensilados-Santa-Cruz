import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/api.dart';
import '../domain/repositorio_operaciones.dart';

class RepositorioOperacionesSupabase implements RepositorioOperaciones {
  RepositorioOperacionesSupabase(this._api);
  final Api _api;

  @override
  Future<List<Registro>> granos() => _api.consultar('granos', '*', orden: 'id', asc: true);

  @override
  Future<List<Registro>> productores() => _api.rpcLista('productores_activos');

  @override
  Future<List<Registro>> pesajes({int limite = 100}) => _api.consultar('pesajes',
      'id, sede_id, origen, placa, peso_bruto, tara, peso_neto, humedad, impurezas, peso_ajustado, estado, orden_id, '
      'fecha_dispositivo, fecha_registro, granos(nombre), proveedores(razon_social), sedes(nombre)',
      orden: 'fecha_dispositivo', limite: limite);

  @override
  Future<List<Registro>> ordenes({String? estado}) => _api.consultar('ordenes_ensilado',
      'id, sede_id, grano_id, estado, fecha_apertura, fecha_cierre, rollos_obtenidos, granos(nombre, rollos_ton_min, rollos_ton_max), '
      'sedes(nombre), pesajes(id, peso_ajustado, estado), lotes(id, codigo, estado)',
      igual: estado == null ? null : {'estado': estado}, orden: 'fecha_apertura', limite: 80);

  @override
  Future<List<Registro>> consumos(String ordenId) =>
      _api.consultar('consumos_insumo', 'id, cantidad, producto_id, productos(nombre, sku)', igual: {'orden_id': ordenId});

  @override
  Future<List<Registro>> insumosDisponibles() async {
    final filas = await _api.rpcLista('reporte_existencias');
    return filas.where((f) => f['tipo'] == 'insumo').toList();
  }

  @override
  Future<List<Registro>> lotesEnFermentacion() => _api.consultar('lotes',
      'id, codigo, fecha_sellado, estado, rollos_producidos, sede_id, sedes(nombre), productos(nombre, granos(nombre, dias_fermentacion))',
      orden: 'fecha_sellado', limite: 200);

  @override
  Future<List<Registro>> revisiones(String loteId) => _api.consultar('revisiones_fermentacion',
      'id, estado_film, observacion, fecha_registro', igual: {'lote_id': loteId}, orden: 'fecha_registro');

  @override
  Future<void> sincronizar(String tabla, Registro datos, String id) async {
    switch (tabla) {
      // Inserciones simples: el id generado en el teléfono hace que un reenvío no duplique la fila.
      case 'pesajes' || 'ordenes_ensilado' || 'consumos_insumo' || 'revisiones_fermentacion':
        await _api.insertar(tabla, {...datos, 'id': datos['id'] ?? id}, ignorarDuplicado: true);
      // Operaciones con reglas de negocio: pasan por el servidor, que guarda el resultado por id (idempotente).
      default:
        final carga = {...datos};
        // El lote creado sin conexión conserva en el servidor el mismo id que ya usan el teléfono y la cola
        // (revisiones, mermas o guías registradas después sobre ese lote).
        if (tabla == 'cerrar_orden') carga['lote_id'] = datos['lote_id'] ?? id;
        await _api.rpc('sincronizar_operacion', {'p_id': id, 'p_operacion': tabla, 'p_datos': carga});
    }
  }

  @override
  Future<Registro> cerrarOrden(String ordenId, int rollos) =>
      _api.rpc('cerrar_orden', {'p_orden': ordenId, 'p_rollos': rollos, 'p_fecha_dispositivo': DateTime.now().toUtc().toIso8601String()});

  @override
  Future<Registro> solicitarCorreccion(String pesajeId, double bruto, double tara, double humedad, double impurezas, String motivo) =>
      _api.rpc('solicitar_correccion_pesaje', {
        'p_pesaje': pesajeId,
        'p_peso_bruto': bruto,
        'p_tara': tara,
        'p_humedad': humedad,
        'p_impurezas': impurezas,
        'p_motivo': motivo,
      });

  @override
  Future<int> actualizarAptos() async => ((await _api.rpc('actualizar_lotes_aptos'))['promovidos'] as num?)?.toInt() ?? 0;
}

final repositorioOperacionesProvider =
    Provider<RepositorioOperaciones>((ref) => RepositorioOperacionesSupabase(ref.watch(apiProvider)));
