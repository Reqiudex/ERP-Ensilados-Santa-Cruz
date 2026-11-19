// Pruebas del servicio de seguridad (Dart puro): hash bcrypt, límite de intentos, sanitización y guardia WORM.
// No forman parte de los CP-01 a CP-27 de la tesis.
import 'package:erp_ensilados_santa_cruz/features/seguridad_accesos/domain/servicio_seguridad.dart';
import 'package:test/test.dart';

void main() {
  test('Hash bcrypt con sal propia: dos hashes del mismo secreto difieren y ambos se verifican', () {
    final s = ServicioSeguridad();
    final a = s.hashCredencial('4821');
    final b = s.hashCredencial('4821');
    expect(a, isNot(b));
    expect(ServicioSeguridad.esHashBcrypt(a), isTrue);
    expect(s.verificarCredencial('4821', a), isTrue);
    expect(s.verificarCredencial('4822', a), isFalse);
    expect(s.verificarCredencial('4821', 'no-es-bcrypt'), isFalse);
  });

  test('Límite de intentos: al tercer fallo exige esperar y se libera al vencer la ventana', () {
    var ahora = DateTime(2026, 11, 19, 10);
    final s = ServicioSeguridad(reloj: () => ahora);
    for (var i = 0; i < 2; i++) {
      s.registrarFallo('ventas@ensilados.demo');
    }
    expect(s.minutosDeEspera('ventas@ensilados.demo', intentosMaximos: 3, minutosBloqueo: 15), 0);
    s.registrarFallo('VENTAS@ensilados.demo');
    expect(s.minutosDeEspera('ventas@ensilados.demo', intentosMaximos: 3, minutosBloqueo: 15), 15);
    ahora = ahora.add(const Duration(minutes: 16));
    expect(s.minutosDeEspera('ventas@ensilados.demo', intentosMaximos: 3, minutosBloqueo: 15), 0);
  });

  test('Sanitización: quita etiquetas, caracteres de control y de inyección', () {
    final s = ServicioSeguridad();
    expect(s.sanitizar("  <script>alert('x')</script> Juan;  DROP TABLE  "), 'alert(x) Juan DROP TABLE');
    expect(s.sanitizar('a\u0000b\u0007c'), 'abc');
    expect(s.sanitizar('x' * 600).length, 500);
  });

  test('Nombre en mayúsculas solo con letras; CI solo con dígitos', () {
    expect(ServicioSeguridad.normalizarNombre('Melvi Pedraza 2'), 'MELVI PEDRAZA ');
    expect(ServicioSeguridad.normalizarNombre('josé  ñandú@#'), 'JOSÉ ÑANDÚ');
    expect(ServicioSeguridad.normalizarCi('8.765-432 LP'), '8765432');
  });

  test('Guardia WORM: modificar o borrar la bitácora lanza una excepción', () {
    final s = ServicioSeguridad();
    expect(() => s.guardiaWorm('UPDATE'), throwsA(isA<OperacionNoPermitida>()));
    expect(() => s.guardiaWorm('DELETE'), throwsA(isA<OperacionNoPermitida>()));
  });
}
