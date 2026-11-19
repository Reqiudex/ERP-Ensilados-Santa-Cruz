// Casos de prueba unitarios de la tesis: prueban el dominio en Dart puro,
// sin Flutter ni Supabase. Cada prueba lleva su identificador CP en el nombre.
import 'package:erp_ensilados_santa_cruz/features/comercial_abastecimiento/domain/calculos_comerciales.dart';
import 'package:erp_ensilados_santa_cruz/features/operaciones_ensilado/domain/calculos_operaciones.dart';
import 'package:erp_ensilados_santa_cruz/features/reportes/domain/calculos_reportes.dart';
import 'package:test/test.dart';

void main() {
  test('CP-07 RF-07 Calcular el peso neto: bruto 32.000 kg y tara 12.000 kg dan 20.000 kg; tara ≥ bruto lanza error', () {
    expect(pesoNeto(32000, 12000), 20000);
    expect(() => pesoNeto(12000, 12000), throwsA(isA<PesajeInvalido>()));
    expect(() => pesoNeto(10000, 12000), throwsA(isA<PesajeInvalido>()));
  });

  test('CP-08 RF-07 Ajustar el peso por humedad: 20.000 kg al 18 % con estándar 14 % dan 19.069,8 kg', () {
    expect(pesoAjustadoPorHumedad(20000, 18, 14), 19069.8);
  });

  test('CP-12 RF-10 Evaluar si un lote está apto: mínimo 21 días; sellado hace 15 no apto y hace 21 apto', () {
    final hoy = DateTime(2026, 11, 18);
    expect(loteApto(hoy.subtract(const Duration(days: 15)), 21, hoy), isFalse);
    expect(loteApto(hoy.subtract(const Duration(days: 21)), 21, hoy), isTrue);
    expect(diasParaApto(hoy.subtract(const Duration(days: 15)), 21, hoy), 6);
  });

  test('CP-19 RF-17 Convertir toneladas en rollos: 8,5 t con 850 kg por rollo son 10 rollos', () {
    expect(toneladasARollos(8.5, 850), 10);
  });

  test('CP-21 RF-19 Elegir el lote de despacho (PEPS): entre el 1 y el 15 de septiembre propone el del 1', () {
    final lotes = [
      LoteDisponible(codigo: 'L-MAI-260915', fechaSellado: DateTime(2026, 9, 15), disponible: 82),
      LoteDisponible(codigo: 'L-MAI-260901', fechaSellado: DateTime(2026, 9, 1), disponible: 79),
    ];
    expect(elegirLotePeps(lotes)!.codigo, 'L-MAI-260901');
  });

  test('CP-22 RF-20 Calcular el rendimiento: 120 rollos con 102 t netas dan 1,18 rollos por tonelada', () {
    expect(rendimientoRollosPorTonelada(120, 102), 1.18);
  });

  test('CP-23 RF-21 Calcular la rotación: salidas 300 rollos y stock promedio 150 dan rotación 2,0', () {
    expect(rotacion(300, 150), 2.0);
  });

  test('CP-25 RF-23 Calcular el porcentaje de merma: 12 rollos dados de baja de 400 son 3,0 %', () {
    expect(porcentajeMerma(12, 400), 3.0);
  });

  test('CP-27 RF-19 Calcular el peso a despachar por tonelada: venta de 10 t con 5 % exige 10.500 kg; más requiere aprobación', () {
    expect(pesoMinimoDespacho(10000, toleranciaPct: 5), 10500);
    expect(despachoRequiereAprobacion(10500, 10000, toleranciaPct: 5), isFalse);
    expect(despachoRequiereAprobacion(10600, 10000, toleranciaPct: 5), isTrue);
  });
}
