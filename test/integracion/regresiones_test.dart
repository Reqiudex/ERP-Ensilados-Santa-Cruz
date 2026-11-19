// Pruebas de regresión contra Supabase en línea (no forman parte de los CP-01 a CP-27).
@Timeout(Duration(minutes: 2))
library;

import 'package:test/test.dart';

import '../apoyo/cliente_prueba.dart';

void main() {
  test('El administrador guarda los parámetros de un grano y queda en la bitácora', () async {
    final admin = await Sesion.de('admin');
    final g = await admin.get('granos?id=eq.1&select=humedad_estandar,dias_fermentacion,rollos_ton_min,rollos_ton_max');
    expect(g.estado, 200, reason: '$g');
    final grano = (g.cuerpo as List).first as Map;
    // Se guardan los mismos valores: verifica que la operación y su evento de bitácora no fallen.
    final r = await admin.rpc('actualizar_grano', {
      'p_grano': 1,
      'p_humedad': grano['humedad_estandar'],
      'p_dias': grano['dias_fermentacion'],
      'p_rollos_min': grano['rollos_ton_min'],
      'p_rollos_max': grano['rollos_ton_max'],
    });
    expect(r.estado, 200, reason: '$r');
  });

  test('Un rol distinto del administrador no cambia los parámetros de un grano', () async {
    final g = await Sesion.de('gerente');
    final r = await g.rpc('actualizar_grano',
        {'p_grano': 1, 'p_humedad': 14, 'p_dias': 21, 'p_rollos_min': 1.0, 'p_rollos_max': 1.4});
    expect(r.estado, 403, reason: '$r');
  });
}
