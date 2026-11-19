import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errores/errores.dart';
import '../../../core/supabase/api.dart';
import '../domain/perfil.dart';
import '../domain/repositorio_seguridad.dart';
import '../domain/servicio_seguridad.dart';

class RepositorioSeguridadSupabase implements RepositorioSeguridad {
  RepositorioSeguridadSupabase(this._api);
  final Api _api;
  GoTrueClient get _auth => _api.cliente.auth;

  @override
  Future<Perfil> iniciarSesion(String identificador, String clave) async {
    final id = identificador.trim();
    if (id.isEmpty || clave.isEmpty) throw const ErrorNegocio('Escriba su CI o correo y su contraseña.');
    final correo = (await _api.rpc('correo_para_ingreso', {'p_identificador': id}))['valor'] as String;
    try {
      await _auth.signInWithPassword(email: correo, password: clave);
    } on AuthException catch (e) {
      final red = e.message.toLowerCase().contains('socket') || e.message.toLowerCase().contains('network');
      if (red) throw const ErrorNegocio('Sin conexión con el servidor. Revise su internet e intente de nuevo.', codigo: 'red');
      try {
        await _api.rpc('registrar_intento_fallido', {'p_identificador': id});
      } catch (_) {}
      // Mismo mensaje exista o no la cuenta (no revela qué CI o correo están registrados).
      throw const ErrorNegocio('Credenciales incorrectas o cuenta bloqueada temporalmente.');
    }
    try {
      return Perfil.desdeJson(await _api.rpc('registrar_ingreso'));
    } catch (e) {
      await _auth.signOut();
      rethrow;
    }
  }

  @override
  Future<Perfil?> perfilActual() async {
    if (_auth.currentSession == null) return null;
    final r = await _api.rpc('mi_perfil');
    if (r['valor'] == null && r['id'] == null) return null;
    final p = Perfil.desdeJson(r);
    return p;
  }

  @override
  Future<void> cerrarSesion() async {
    try {
      await _auth.signOut();
    } catch (_) {
      await _auth.signOut(scope: SignOutScope.local);
    }
  }

  @override
  Future<void> cambiarMiClave(String actual, String nueva) async {
    await _api.rpc('cambiar_mi_clave', {'p_actual': actual, 'p_nueva': nueva});
    try {
      await _auth.refreshSession();
    } catch (_) {}
  }

  @override
  Future<List<Registro>> sesionesActivas() => _api.rpcLista('sesiones_activas');

  @override
  Future<int> cerrarSesiones(String? usuarioId) async =>
      ((await _api.rpc('cerrar_sesiones', {'p_usuario': usuarioId}))['cerradas'] as num?)?.toInt() ?? 0;

  @override
  Future<List<Registro>> usuarios() => _api.consultar('usuarios',
      'id, nombre_completo, ci, correo, estado, rol_id, sede_id, roles(codigo, nombre, privilegiado), sedes(nombre, tipo)',
      orden: 'nombre_completo', asc: true);

  @override
  Future<List<Registro>> sedes() => _api.consultar('sedes', 'id, nombre, tipo, municipio, provincia, activa', orden: 'nombre', asc: true);

  @override
  Future<void> cambiarSedeTrabajo(String sedeId) => _api.rpc('cambiar_sede_trabajo', {'p_sede': sedeId});

  @override
  Future<Registro> crearUsuario(Registro d) => _api.rpc('crear_usuario', {
        'p_nombre': d['nombre'],
        'p_ci': d['ci'],
        'p_correo': d['correo'],
        'p_rol': d['rol'],
        'p_sede': d['sede_id'],
        'p_clave': d['clave'],
      });

  @override
  Future<Registro> editarUsuario(String id, Registro d) => _api.rpc('editar_usuario', {
        'p_usuario': id,
        'p_nombre': d['nombre'],
        'p_ci': d['ci'],
        'p_correo': d['correo'],
        'p_rol': d['rol'],
        'p_sede': d['sede_id'],
      });

  @override
  Future<void> cambiarEstadoUsuario(String id, String accion) =>
      _api.rpc('cambiar_estado_usuario', {'p_usuario': id, 'p_accion': accion});

  @override
  Future<void> restablecerClave(String id, String clave) => _api.rpc('restablecer_clave', {'p_usuario': id, 'p_clave': clave});

  @override
  Future<List<Registro>> bandeja(String estado) => _api.rpcLista('bandeja_aprobaciones', {'p_estado': estado});

  @override
  Future<void> resolverSolicitud(String id, bool aprobar, String? motivo) =>
      _api.rpc('resolver_solicitud', {'p_solicitud': id, 'p_aprobar': aprobar, 'p_motivo': motivo});

  @override
  Future<List<Registro>> misSolicitudes() => _api.rpcLista('mis_solicitudes');

  @override
  Future<Map<String, dynamic>> parametros() async => await _api.rpc('obtener_parametros');

  @override
  Future<void> guardarParametros(Map<String, dynamic> valores) => _api.rpc('guardar_parametros', {'p_valores': valores});

  @override
  Future<List<Registro>> granos() => _api.consultar('granos', '*', orden: 'id', asc: true);

  @override
  Future<void> actualizarGrano(int id, double humedad, int dias, double minimo, double maximo) => _api.rpc('actualizar_grano', {
        'p_grano': id,
        'p_humedad': humedad,
        'p_dias': dias,
        'p_rollos_min': minimo,
        'p_rollos_max': maximo,
      });

  @override
  Future<List<Registro>> respaldos() => _api.rpcLista('respaldos');

  @override
  Future<void> pedirRespaldo() => _api.rpc('pedir_respaldo');

  @override
  Future<int> optimizarBase() async => ((await _api.rpc('optimizar_base'))['tablas'] as num?)?.toInt() ?? 0;

  @override
  Future<void> revocarSesion(String sesionId) => _api.rpc('cerrar_sesion', {'p_sesion': sesionId});

  @override
  Future<bool> sesionVigente() async => (await _api.rpc('sesion_vigente'))['valor'] == true;

  @override
  Future<bool> verificarMiClave(String clave) async => (await _api.rpc('verificar_mi_clave', {'p_clave': clave}))['valor'] == true;

  @override
  Future<List<String>> duplicadosUsuario(String nombre, String ci, String correo, {String? excluir}) async {
    final r = await _api.rpc('verificar_duplicados_usuario',
        {'p_nombre': nombre, 'p_ci': ci, 'p_correo': correo, 'p_excluir': excluir});
    return [for (final x in (r['duplicados'] as List? ?? const [])) '$x'];
  }

  @override
  Future<void> modificarEvento(int id, Registro datos) async => ServicioSeguridad().guardiaWorm('UPDATE');

  @override
  Future<void> eliminarEvento(int id) async => ServicioSeguridad().guardiaWorm('DELETE');

  @override
  Future<void> solicitarRestauracion(String respaldo, String motivo) =>
      _api.rpc('solicitar_restauracion', {'p_respaldo': respaldo, 'p_motivo': motivo});

  @override
  Future<List<Registro>> bitacora({DateTime? desde, DateTime? hasta, String? accion, String? tabla, String? usuarioId}) async {
    var q = _api.cliente.from('bitacora_eventos').select(
        'id, accion, tabla, registro_id, datos_antes, datos_despues, ip, fecha_dispositivo, fecha_servidor, '
        'usuario:usuarios!bitacora_eventos_usuario_id_fkey(nombre_completo), '
        'aprobador:usuarios!bitacora_eventos_aprobador_id_fkey(nombre_completo)');
    if (desde != null) q = q.gte('fecha_servidor', desde.toUtc().toIso8601String());
    if (hasta != null) q = q.lt('fecha_servidor', hasta.add(const Duration(days: 1)).toUtc().toIso8601String());
    if (accion != null) q = q.eq('accion', accion);
    if (tabla != null) q = q.eq('tabla', tabla);
    if (usuarioId != null) q = q.eq('usuario_id', usuarioId);
    try {
      return await q.order('fecha_servidor', ascending: false).limit(500);
    } on PostgrestException catch (e) {
      throw traducirError(e, codigo: e.code, mensaje: e.message);
    }
  }
}

final repositorioSeguridadProvider =
    Provider<RepositorioSeguridad>((ref) => RepositorioSeguridadSupabase(ref.watch(apiProvider)));
