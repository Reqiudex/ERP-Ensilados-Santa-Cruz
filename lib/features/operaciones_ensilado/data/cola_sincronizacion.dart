import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/experimental/persist.dart';
import 'package:uuid/uuid.dart';

import '../../../core/almacenamiento/almacen_local.dart';
import '../../../core/conexion/conexion.dart';
import '../../../core/errores/errores.dart';
import '../domain/registro_pendiente.dart';
import 'repositorio_operaciones_supabase.dart';

/// Cola local de solo inserción (persistencia de Riverpod 3 + SQLite en Android).
/// Cada registro lleva un UUID generado en el dispositivo y la hora del dispositivo; al reconectar se envía en orden
/// y sin duplicarse. Si el servidor lo rechaza, queda «rechazado» con el motivo para el operador.
class ColaSincronizacion extends Notifier<List<RegistroPendiente>> {
  bool _enviando = false;

  @override
  List<RegistroPendiente> build() {
    // ignore: experimental_member_use
    persist(
      ref.watch(almacenPersistenteProvider.future),
      key: 'cola_sincronizacion_v1',
      encode: (s) => jsonEncode(s.map((r) => r.aJson()).toList()),
      decode: (t) => (jsonDecode(t) as List).map((e) => RegistroPendiente.desdeJson(e as Map<String, dynamic>)).toList(),
      options: const StorageOptions(cacheTime: StorageCacheTime.unsafe_forever),
    );
    return const [];
  }

  static const _uuid = Uuid();

  /// Guarda el registro y lo envía si hay conexión. Devuelve el identificador generado en el dispositivo.
  Future<String> registrar(String tabla, Map<String, dynamic> datos) async {
    if (!tablasSinConexion.contains(tabla)) throw ArgumentError('$tabla exige conexión');
    final id = (datos['id'] as String?) ?? _uuid.v4();
    final r = RegistroPendiente(id: id, tabla: tabla, datos: {...datos, 'id': id}, creado: DateTime.now());
    state = [...state, r];
    if (ref.read(enLineaProvider)) await sincronizar();
    return id;
  }

  int get pendientes => state.where((r) => !r.rechazado).length;

  /// Envía la cola en orden. Se detiene si se pierde la conexión.
  Future<void> sincronizar() async {
    if (_enviando || !ref.read(enLineaProvider)) return;
    _enviando = true;
    try {
      final repo = ref.read(repositorioOperacionesProvider);
      for (final r in ordenDeEnvio(state)) {
        try {
          await repo.sincronizar(r.tabla, r.datos);
          state = state.where((x) => x.id != r.id).toList();
        } on ErrorNegocio catch (e) {
          if (e.codigo == 'red') break;
          state = [for (final x in state) x.id == r.id ? x.rechazar(e.mensaje) : x];
        }
      }
    } finally {
      _enviando = false;
    }
  }

  /// El operador descarta un registro rechazado después de leer el motivo (no se edita: se vuelve a registrar).
  void descartar(String id) => state = state.where((r) => r.id != id).toList();
}

final colaProvider = NotifierProvider<ColaSincronizacion, List<RegistroPendiente>>(ColaSincronizacion.new);

final pendientesSincronizarProvider = Provider<int>((ref) => ref.watch(colaProvider).where((r) => !r.rechazado).length);

/// Datos que el operador necesita sin conexión (granos, productores, órdenes abiertas), guardados en el teléfono.
class DatosOperador extends Notifier<Map<String, dynamic>> {
  @override
  Map<String, dynamic> build() {
    // ignore: experimental_member_use
    persist(
      ref.watch(almacenPersistenteProvider.future),
      key: 'datos_operador_v1',
      encode: jsonEncode,
      decode: (t) => Map<String, dynamic>.from(jsonDecode(t) as Map),
      options: const StorageOptions(cacheTime: StorageCacheTime(Duration(days: 7))),
    );
    return const {};
  }

  Future<void> refrescar() async {
    if (!ref.read(enLineaProvider)) return;
    final repo = ref.read(repositorioOperacionesProvider);
    final nuevo = {...state};
    try {
      nuevo['granos'] = await repo.granos();
    } catch (_) {}
    try {
      nuevo['productores'] = await repo.productores();
    } catch (_) {}
    try {
      final o = await repo.ordenes(estado: 'abierta');
      nuevo['ordenes'] =
          o.map((x) => {'id': x['id'], 'grano_id': x['grano_id'], 'fecha_apertura': x['fecha_apertura'], 'grano': x['granos']?['nombre']}).toList();
    } catch (_) {}
    nuevo['actualizado'] = DateTime.now().toIso8601String();
    state = nuevo;
  }

  void agregarOrdenLocal(Map<String, dynamic> orden) {
    final l = [...(state['ordenes'] as List? ?? const []), orden];
    state = {...state, 'ordenes': l};
  }
}

final datosOperadorProvider = NotifierProvider<DatosOperador, Map<String, dynamic>>(DatosOperador.new);
