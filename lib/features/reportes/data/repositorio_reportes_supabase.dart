import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/supabase/api.dart';
import '../domain/repositorio_reportes.dart';

class RepositorioReportesSupabase implements RepositorioReportes {
  RepositorioReportesSupabase(this._api);
  final Api _api;

  @override
  Future<List<Registro>> rendimiento(DateTime desde, DateTime hasta) =>
      _api.rpcLista('reporte_rendimiento', {'p_desde': isoDia(desde), 'p_hasta': isoDia(hasta)});

  @override
  Future<List<Registro>> existencias() => _api.rpcLista('reporte_existencias');

  @override
  Future<List<Registro>> rotacion(DateTime desde, DateTime hasta) =>
      _api.rpcLista('reporte_rotacion', {'p_desde': isoDia(desde), 'p_hasta': isoDia(hasta)});

  @override
  Future<Registro> ventas(DateTime desde, DateTime hasta, {String? clienteId}) =>
      _api.rpc('reporte_ventas', {'p_desde': isoDia(desde), 'p_hasta': isoDia(hasta), 'p_cliente': clienteId});

  @override
  Future<Registro> mermas(DateTime desde, DateTime hasta) =>
      _api.rpc('reporte_mermas', {'p_desde': isoDia(desde), 'p_hasta': isoDia(hasta)});

  @override
  Future<List<Registro>> clientes() => _api.consultar('clientes', 'id, razon_social', orden: 'razon_social', asc: true);
}

final repositorioReportesProvider = Provider<RepositorioReportes>((ref) => RepositorioReportesSupabase(ref.watch(apiProvider)));
