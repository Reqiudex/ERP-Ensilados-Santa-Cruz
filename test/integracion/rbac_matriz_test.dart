// RF-02 Control de acceso basado en roles: la matriz de permisos (pantalla y tabla de roles) solo la consultan el
// administrador del sistema y el gerente general (y el superadministrador). Se comprueba en la interfaz (menú y rutas)
// y en la API (RLS de la tabla de roles) con cada cuenta de la demostración.
import 'package:erp_ensilados_santa_cruz/core/router/menu.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/domain/roles_y_permisos.dart';
import 'package:flutter_test/flutter_test.dart';

import '../apoyo/cliente_prueba.dart';

void main() {
  test('Interfaz: la entrada «Control de Acceso (RBAC)» y su ruta solo existen para administrador, gerente y superadmin', () {
    final entrada = entradaDeRuta('/seguridad/permisos')!;
    expect(entrada.nombre, 'Control de Acceso (RBAC)');
    for (final r in Rol.values) {
      final debe = r == Rol.adminSistema || r == Rol.gerenteGeneral || r == Rol.superadmin;
      expect(entrada.permitido(r), debe, reason: r.name);
    }
  });

  test('API: la tabla de roles solo devuelve filas al administrador y al gerente', () async {
    final resultados = <String>[];
    for (final c in ['admin', 'gerente', 'ejecutivo', 'cajero', 'op_sr', 'op_sj', 'op_rv']) {
      final s = await Sesion.de(c);
      final r = await s.get('roles?select=codigo,nombre');
      expect(r.estado, 200, reason: '$c: $r');
      final n = (r.cuerpo as List).length;
      final debe = c == 'admin' || c == 'gerente';
      expect(n > 0, debe, reason: '$c ve $n filas de roles');
      // Tampoco por una consulta anidada desde la tabla de usuarios.
      final u = await s.get('usuarios?select=id,roles(codigo)&id=eq.${s.usuarioId}');
      final rol = ((u.cuerpo as List).firstOrNull as Map?)?['roles'];
      expect(rol != null, debe, reason: '$c: rol anidado $rol');
      resultados.add('$c: $n filas');
    }
    // ignore: avoid_print
    print('RBAC|${resultados.join('; ')}');
  });
}
