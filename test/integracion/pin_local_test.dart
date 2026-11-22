// PIN sin conexión y credenciales offline 24/7: se guardan con bcrypt y permiten operar sin conexión ni datos.
import 'package:erp_ensilados_santa_cruz/core/almacenamiento/almacen_local.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/data/pin_local.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/domain/perfil.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/domain/reglas_seguridad.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/domain/roles_y_permisos.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/domain/servicio_seguridad.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Un PIN guardado con el formato anterior desbloquea y queda migrado a bcrypt', () async {
    final almacen = AlmacenSeguro.enMemoria();
    await almacen.escribir('pin_sal', 'c2FsLWRlLXBydWViYQ==');
    await almacen.escribir('pin_resumen', PinLocal.resumen('4826', 'c2FsLWRlLXBydWViYQ=='));
    await almacen.escribir('pin_usuario', 'u1');
    await almacen.escribir('ultima_sync', DateTime.now().toIso8601String());
    final pin = PinLocal(almacen);
    expect(await pin.desbloquear('4826'), ResultadoPin.desbloqueado);
    final nuevo = await almacen.leer('pin_resumen');
    expect(ServicioSeguridad.esHashBcrypt(nuevo), isTrue);
    expect(await almacen.leer('pin_sal'), isNull);
    expect(await pin.desbloquear('4826'), ResultadoPin.desbloqueado);
    expect(await pin.desbloquear('1111'), ResultadoPin.incorrecto);
  });

  test('Credenciales offline permiten iniciar sesión sin red por correo o CI y recuperar el perfil en frío', () async {
    final almacen = AlmacenSeguro.enMemoria();
    final pin = PinLocal(almacen);
    const perfil = Perfil(
      id: 'u-op-sr',
      nombre: 'MARIO VARGAS',
      ci: '7654321',
      correo: 'operador.sanramon@ensilados.demo',
      rol: Rol.operadorCentro,
      sedeId: '22222222-2222-2222-2222-222222222222',
      sede: 'Centro San Ramón',
      sedeTipo: 'centro',
      debeCambiarClave: false,
      parametros: {},
    );
    await pin.guardarCredencialesOffline(perfil, 'Ensilados2026!');

    // El perfil queda persistido aunque el operador aún no haya configurado un PIN de 4-6 dígitos.
    final recuperado = await pin.perfilGuardado();
    expect(recuperado?.id, perfil.id);
    expect(recuperado?.sedeId, perfil.sedeId);

    // Verifica login offline tanto con CI como con correo institucional.
    final porCi = await pin.verificarCredencialesOffline('7654321', 'Ensilados2026!');
    expect(porCi?.id, perfil.id);
    final porCorreo = await pin.verificarCredencialesOffline('OPERADOR.SANRAMON@ensilados.demo', 'Ensilados2026!');
    expect(porCorreo?.id, perfil.id);

    // Rechaza clave incorrecta o usuario distinto.
    expect(await pin.verificarCredencialesOffline('7654321', 'ClaveErronea1!'), isNull);
    expect(await pin.verificarCredencialesOffline('9999999', 'Ensilados2026!'), isNull);
  });
}
