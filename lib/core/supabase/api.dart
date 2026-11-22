import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../conexion/conexion.dart';
import '../errores/errores.dart';

typedef Fila = Map<String, dynamic>;

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Acceso a la API de Supabase con traducción de errores y límite de espera para no bloquear la app sin señal.
/// Toda escritura de negocio pasa por funciones RPC.
class Api {
  Api(this.cliente, {this.enLinea, this.alCambiarAlcance});
  final SupabaseClient cliente;
  final bool Function()? enLinea;
  final void Function(bool alcanzable)? alCambiarAlcance;

  static const _timeout = Duration(seconds: 8);

  Future<T> _seguro<T>(Future<T> Function() f) async {
    if (enLinea != null && !enLinea!()) {
      throw const ErrorNegocio('Sin conexión con el servidor. Revise su internet e intente de nuevo.', codigo: 'red');
    }
    try {
      final res = await f().timeout(_timeout);
      alCambiarAlcance?.call(true);
      return res;
    } on PostgrestException catch (e) {
      final err = traducirError(e, codigo: e.code, mensaje: e.message, detalle: e.details?.toString());
      if (err.codigo == 'red') alCambiarAlcance?.call(false);
      throw err;
    } on AuthException catch (e) {
      final err = traducirError(e, codigo: e.statusCode, mensaje: e.message);
      if (err.codigo == 'red') alCambiarAlcance?.call(false);
      throw err;
    } on ErrorNegocio catch (e) {
      if (e.codigo == 'red') alCambiarAlcance?.call(false);
      rethrow;
    } catch (e) {
      final err = traducirError(e);
      if (err.codigo == 'red') alCambiarAlcance?.call(false);
      throw err;
    }
  }

  /// Llama a una función del servidor que devuelve un objeto JSON.
  Future<Fila> rpc(String funcion, [Map<String, dynamic>? params]) => _seguro(() async {
        final r = await cliente.rpc(funcion, params: params);
        if (r is Map) {
          final m = Map<String, dynamic>.from(r);
          if (m['code'] == '42501') throw ErrorNegocio(m['message'] as String, codigo: '42501', prohibido: true);
          return m;
        }
        return {'valor': r};
      });

  /// Llama a una función del servidor que devuelve una lista JSON.
  Future<List<Fila>> rpcLista(String funcion, [Map<String, dynamic>? params]) => _seguro(() async {
        final r = await cliente.rpc(funcion, params: params);
        if (r is Map && r['code'] == '42501') {
          throw ErrorNegocio(r['message'] as String, codigo: '42501', prohibido: true);
        }
        return (r as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });

  /// Consulta de lectura sujeta a RLS.
  Future<List<Fila>> consultar(String tabla, String columnas,
          {Map<String, Object>? igual, String? orden, bool asc = false, int? limite}) =>
      _seguro(() async {
        PostgrestFilterBuilder<List<Map<String, dynamic>>> q = cliente.from(tabla).select(columnas);
        igual?.forEach((k, v) => q = q.eq(k, v));
        PostgrestTransformBuilder<List<Map<String, dynamic>>> t = q;
        if (orden != null) t = t.order(orden, ascending: asc);
        if (limite != null) t = t.limit(limite);
        return await t;
      });

  /// Inserción directa (solo en las tablas que la matriz permite: pesajes, órdenes, consumos, revisiones,
  /// clientes, proveedores y solicitudes). RLS valida rol, sede y estado.
  Future<void> insertar(String tabla, Fila datos, {bool ignorarDuplicado = false}) => _seguro(() async {
        if (ignorarDuplicado) {
          await cliente.from(tabla).upsert(datos, onConflict: 'id', ignoreDuplicates: true);
        } else {
          await cliente.from(tabla).insert(datos);
        }
      });

  /// Flujo en tiempo real (Supabase Realtime, respeta RLS).
  Stream<List<Fila>> flujo(String tabla, {String clave = 'id'}) =>
      cliente.from(tabla).stream(primaryKey: [clave]);
}

final apiProvider = Provider<Api>((ref) => Api(
      ref.watch(supabaseProvider),
      enLinea: () => !ref.read(modoSinRedProvider) && (ref.read(redProvider).value ?? true),
      alCambiarAlcance: (ok) =>
          ok ? ref.read(alcanceServidorProvider.notifier).marcarEnLinea() : ref.read(alcanceServidorProvider.notifier).marcarCaido(),
    ));
