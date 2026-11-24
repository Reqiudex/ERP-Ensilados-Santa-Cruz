// Rol superadministrador: acceso total en la interfaz sin alterar la matriz de los cinco roles de la tesis.
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/domain/roles_y_permisos.dart';
import 'package:test/test.dart';

void main() {
  test('El superadministrador entra a los 23 submódulos y puede todas las acciones', () {
    for (final s in Submodulo.values) {
      expect(s.permitido(Rol.superadmin), isTrue, reason: s.titulo);
    }
    for (final a in Accion.values) {
      expect(a.permitida(Rol.superadmin), isTrue, reason: a.name);
    }
  });

  test('La matriz de la tesis sigue teniendo solo los cinco roles fijos', () {
    expect(Rol.deLaMatriz, hasLength(5));
    expect(Rol.deLaMatriz, isNot(contains(Rol.superadmin)));
    for (final o in matrizPermisos) {
      expect(o.accesos.keys, isNot(contains(Rol.superadmin)));
    }
  });

  test('Los demás roles conservan sus límites (separación de funciones en la interfaz)', () {
    expect(Accion.registrarCobro.permitida(Rol.ejecutivoComercial), isFalse); // CP-20: quien vende no cobra
    expect(Accion.registrarCobro.permitida(Rol.cajeroContador), isTrue);
    expect(Submodulo.usuarios.permitido(Rol.operadorCentro), isFalse);
    expect(Submodulo.bascula.permitido(Rol.adminSistema), isFalse); // el administrador no tiene permisos de negocio
    expect(Submodulo.politicas.permitido(Rol.gerenteGeneral), isFalse);
  });

  test('La matriz de permisos (RBAC) solo la ven el administrador, el gerente y el superadministrador', () {
    expect(Submodulo.rbac.permitido(Rol.adminSistema), isTrue);
    expect(Submodulo.rbac.permitido(Rol.gerenteGeneral), isTrue);
    expect(Submodulo.rbac.permitido(Rol.superadmin), isTrue);
    for (final r in [Rol.operadorCentro, Rol.ejecutivoComercial, Rol.cajeroContador]) {
      expect(Submodulo.rbac.permitido(r), isFalse, reason: r.name);
    }
  });
}
