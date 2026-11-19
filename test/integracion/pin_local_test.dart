// PIN sin conexión: se guarda con bcrypt y los PIN del formato anterior (SHA-256 con sal) se migran al desbloquear.
import 'package:erp_ensilados_santa_cruz/core/almacenamiento/almacen_local.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/data/pin_local.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/domain/reglas_seguridad.dart';
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
}
