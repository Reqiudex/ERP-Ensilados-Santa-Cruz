// Pruebas complementarias de las reglas de seguridad del cliente (apoyan a CP-03, CP-04 y CP-26).
import 'package:erp_ensilados_santa_cruz/features/operaciones_ensilado/domain/registro_pendiente.dart';
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/domain/reglas_seguridad.dart';
import 'package:test/test.dart';

void main() {
  test('Política de contraseñas: «abc123» se rechaza por tener menos de 8 caracteres', () {
    final e = evaluarClave('abc123');
    expect(e.valida, isFalse);
    expect(e.faltantes, contains('Al menos 8 caracteres'));
    expect(evaluarClave('Ensilados2026!').valida, isTrue);
    expect(evaluarClave('Ensilados2026!').puntaje, 100);
  });

  test('Inactividad: a los 15 minutos sin uso la sesión vence', () {
    final t = DateTime(2026, 11, 18, 10);
    expect(sesionVencidaPorInactividad(t, t.add(const Duration(minutes: 14)), minutos: 15), isFalse);
    expect(sesionVencidaPorInactividad(t, t.add(const Duration(minutes: 15)), minutos: 15), isTrue);
  });

  test('PIN sin conexión: el tercer PIN erróneo exige iniciar sesión en línea; 12 horas sin sincronizar también', () {
    final ahora = DateTime(2026, 11, 18, 10);
    EstadoPin est(int i, {int horas = 1}) => EstadoPin(intentosFallidos: i, ultimaSincronizacion: ahora.subtract(Duration(hours: horas)));
    expect(evaluarIntentoPin(pinCorrecto: false, estado: est(0), ahora: ahora), ResultadoPin.incorrecto);
    expect(evaluarIntentoPin(pinCorrecto: false, estado: est(1), ahora: ahora), ResultadoPin.incorrecto);
    expect(evaluarIntentoPin(pinCorrecto: false, estado: est(2), ahora: ahora), ResultadoPin.exigeInicioEnLinea);
    expect(evaluarIntentoPin(pinCorrecto: true, estado: est(0, horas: 13), ahora: ahora), ResultadoPin.exigeInicioEnLinea);
    expect(evaluarIntentoPin(pinCorrecto: true, estado: est(1), ahora: ahora), ResultadoPin.desbloqueado);
    expect(pinConFormatoValido('123'), isFalse);
    expect(pinConFormatoValido('1234'), isTrue);
    expect(pinConFormatoValido('1234567'), isFalse);
  });

  test('Bitácora: correos y CI enmascarados; nunca muestra claves', () {
    expect(enmascararCorreo('usuario@dominio.com'), 'us*****@dominio.com');
    expect(enmascararCi('6543210'), '65***10');
    final m = enmascararDatos({'correo': 'admin@ensilados.demo', 'encrypted_password': 'x', 'nombre': 'Carla'}) as Map;
    expect(m['correo'], 'ad*****@ensilados.demo');
    expect(m['encrypted_password'], '••••');
    expect(m['nombre'], 'Carla');
  });

  test('Cola sin conexión: se envía en orden y las órdenes antes que sus pesajes', () {
    final t = DateTime(2026, 11, 18, 8);
    final cola = [
      RegistroPendiente(id: 'b', tabla: 'pesajes', datos: const {}, creado: t.add(const Duration(minutes: 5))),
      RegistroPendiente(id: 'a', tabla: 'ordenes_ensilado', datos: const {}, creado: t),
      RegistroPendiente(id: 'c', tabla: 'pesajes', datos: const {}, creado: t.add(const Duration(minutes: 1))).rechazar('x'),
    ];
    expect(ordenDeEnvio(cola).map((r) => r.id), ['a', 'b']);
  });
}
