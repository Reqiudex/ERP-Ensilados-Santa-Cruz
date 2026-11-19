// Apoyo para las pruebas de caja negra y de auditoría contra el proyecto de Supabase en línea.
// Cada cuenta de demostración inicia sesión con su propio rol; nunca se usa una clave secreta.
import 'dart:convert';

import 'package:erp_ensilados_santa_cruz/core/supabase/supabase_config.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

const claveDemo = String.fromEnvironment('CLAVE_DEMO', defaultValue: 'Ensilados2026!');

const cuentas = {
  'admin': 'admin@ensilados.demo',
  'ejecutivo': 'ventas@ensilados.demo',
  'cajero': 'caja@ensilados.demo',
  'gerente': 'gerencia@ensilados.demo',
  'op_sr': 'sanramon@ensilados.demo',
  'op_sj': 'sanjulian@ensilados.demo',
  'op_rv': 'sanrafael@ensilados.demo',
};

const sedeSanRamon = '22222222-2222-2222-2222-222222222222';
const sedeSanJulian = '33333333-3333-3333-3333-333333333333';
const sedeSanRafael = '44444444-4444-4444-4444-444444444444';

/// Respuesta HTTP cruda (para comprobar el código 403 y el cuerpo).
class Respuesta {
  Respuesta(this.estado, this.cuerpo);
  final int estado;
  final dynamic cuerpo;
  String get mensaje => cuerpo is Map ? '${cuerpo['message']}' : '$cuerpo';
  String get codigo => cuerpo is Map ? '${cuerpo['code']}' : '';
  @override
  String toString() =>
      'HTTP $estado ${cuerpo is Map && cuerpo['code'] != null ? '${cuerpo['code']} ${cuerpo['message']}' : jsonEncode(cuerpo)}';
}

class Sesion {
  Sesion._(this.rol, this.cliente, this.token, this.usuarioId);
  final String rol;
  final SupabaseClient cliente;
  final String token;
  final String usuarioId;

  static final _cache = <String, Sesion>{};

  static Future<Sesion> de(String rol) async {
    if (_cache[rol] != null) return _cache[rol]!;
    final c = SupabaseClient(SupabaseConfig.url, SupabaseConfig.publishableKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    final r = await c.auth.signInWithPassword(email: cuentas[rol]!, password: claveDemo);
    return _cache[rol] = Sesion._(rol, c, r.session!.accessToken, r.user!.id);
  }

  Map<String, String> get _cabeceras => {
        'apikey': SupabaseConfig.publishableKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      };

  Future<Respuesta> rpc(String funcion, [Map<String, dynamic> params = const {}]) async {
    final r = await http.post(Uri.parse('${SupabaseConfig.url}/rest/v1/rpc/$funcion'), headers: _cabeceras, body: jsonEncode(params));
    return Respuesta(r.statusCode, r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes)));
  }

  Future<Respuesta> get(String ruta) async {
    final r = await http.get(Uri.parse('${SupabaseConfig.url}/rest/v1/$ruta'), headers: _cabeceras);
    return Respuesta(r.statusCode, r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes)));
  }

  Future<Respuesta> post(String tabla, Object datos) async {
    final r = await http.post(Uri.parse('${SupabaseConfig.url}/rest/v1/$tabla'), headers: _cabeceras, body: jsonEncode(datos));
    return Respuesta(r.statusCode, r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes)));
  }

  Future<Respuesta> upsertIgnorar(String tabla, Object datos) async {
    final r = await http.post(Uri.parse('${SupabaseConfig.url}/rest/v1/$tabla?on_conflict=id'),
        headers: {..._cabeceras, 'Prefer': 'resolution=ignore-duplicates,return=minimal'}, body: jsonEncode(datos));
    return Respuesta(r.statusCode, r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes)));
  }

  Future<Respuesta> patch(String ruta, Object datos) async {
    final r = await http.patch(Uri.parse('${SupabaseConfig.url}/rest/v1/$ruta'), headers: _cabeceras, body: jsonEncode(datos));
    return Respuesta(r.statusCode, r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes)));
  }

  Future<Respuesta> delete(String ruta) async {
    final r = await http.delete(Uri.parse('${SupabaseConfig.url}/rest/v1/$ruta'), headers: _cabeceras);
    return Respuesta(r.statusCode, r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes)));
  }
}

/// Deja el resultado obtenido en la salida para que scripts/pruebas.sh lo copie al informe.
// ignore: avoid_print
void obtenido(String id, String texto) => print('OBTENIDO|$id|${texto.replaceAll('\n', ' ')}');

/// Evidencia de auditoría (código de respuesta, mensaje, filas y evento de bitácora).
// ignore: avoid_print
void evidencia(int n, String texto) => print('EVIDENCIA|$n|${texto.replaceAll('\n', ' ')}');

String sello() => DateTime.now().millisecondsSinceEpoch.toString().substring(5);
