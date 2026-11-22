// Pruebas complementarias de las reglas de seguridad del cliente y flujo offline 24/7 (apoyan a CP-03, CP-04, CP-09 y CP-26).
import 'package:erp_ensilados_santa_cruz/core/errores/errores.dart';
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

  test('Cola sin conexión: se envía en orden de dependencias completo del flujo 24/7', () {
    final t = DateTime(2026, 11, 18, 8);
    final cola = [
      RegistroPendiente(id: 'peso_basc', tabla: 'registrar_peso_bascula', datos: const {}, creado: t.add(const Duration(minutes: 1))),
      RegistroPendiente(id: 'desp', tabla: 'registrar_despacho', datos: const {}, creado: t.add(const Duration(minutes: 2))),
      RegistroPendiente(id: 'guia', tabla: 'emitir_guia', datos: const {}, creado: t.add(const Duration(minutes: 3))),
      RegistroPendiente(id: 'rev', tabla: 'revisiones_fermentacion', datos: const {}, creado: t.add(const Duration(minutes: 4))),
      RegistroPendiente(id: 'cierre', tabla: 'cerrar_orden', datos: const {}, creado: t.add(const Duration(minutes: 5))),
      RegistroPendiente(id: 'pesaje', tabla: 'pesajes', datos: const {}, creado: t.add(const Duration(minutes: 6))),
      RegistroPendiente(id: 'insumo', tabla: 'consumos_insumo', datos: const {}, creado: t.add(const Duration(minutes: 7))),
      RegistroPendiente(id: 'orden', tabla: 'ordenes_ensilado', datos: const {}, creado: t.add(const Duration(minutes: 8))),
      RegistroPendiente(id: 'rechazado', tabla: 'pesajes', datos: const {}, creado: t).rechazar('x'),
    ];
    expect(
      ordenDeEnvio(cola).map((r) => r.id).toList(),
      ['orden', 'pesaje', 'insumo', 'cierre', 'rev', 'guia', 'desp', 'peso_basc'],
    );
    expect(tablasSinConexion.containsAll([
      'pesajes',
      'ordenes_ensilado',
      'consumos_insumo',
      'revisiones_fermentacion',
      'cerrar_orden',
      'solicitar_correccion_pesaje',
      'solicitar_merma',
      'solicitar_ajuste',
      'emitir_guia',
      'recibir_guia',
      'registrar_despacho',
      'registrar_peso_bascula',
    ]), isTrue);
  });

  test('Detección de errores de red y sin datos móviles en Android', () {
    expect(esErrorRed(const ErrorNegocio('Sin conexión', codigo: 'red')), isTrue);
    expect(esErrorRed(Exception('SocketException: Failed host lookup: gklicbxcfomgesljhtyq.supabase.co')), isTrue);
    expect(esErrorRed(Exception('TimeoutException after 0:00:08.000000: Future not completed')), isTrue);
    expect(esErrorRed(Exception('HandshakeException: Connection terminated during handshake')), isTrue);
    expect(esErrorRed(Exception('ClientException with SocketException: Network is unreachable (errno = 101)')), isTrue);
    expect(traducirError(Exception('TimeoutException after 8s')).codigo, 'red');
    expect(esErrorRed(const ErrorNegocio('Stock insuficiente', codigo: 'negocio')), isFalse);
  });
}
