/// Reglas de negocio de Comercial y Abastecimiento (RF-16 a RF-19). Dart puro.
library;

/// Conversión de toneladas a rollos (CP-19): toneladas × 1.000 ÷ peso promedio por rollo, al entero más cercano.
int toneladasARollos(double toneladas, double pesoPromedioKg) {
  if (pesoPromedioKg <= 0) throw ArgumentError('El peso promedio debe ser mayor que cero.');
  return (toneladas * 1000 / pesoPromedioKg).round();
}

/// Peso mínimo a despachar en una venta por tonelada (CP-27): vendido × (1 + tolerancia).
double pesoMinimoDespacho(double pesoVendidoKg, {double toleranciaPct = 5}) =>
    double.parse((pesoVendidoKg * (1 + toleranciaPct / 100)).toStringAsFixed(2));

/// Un despacho por tonelada que supera la tolerancia queda pendiente de aprobación del gerente (CP-27).
bool despachoRequiereAprobacion(double pesoDespachadoKg, double pesoVendidoKg, {double toleranciaPct = 5}) =>
    pesoDespachadoKg > pesoMinimoDespacho(pesoVendidoKg, toleranciaPct: toleranciaPct);

/// Lote disponible para la elección PEPS.
class LoteDisponible {
  const LoteDisponible({required this.codigo, required this.fechaSellado, required this.disponible, this.apto = true});
  final String codigo;
  final DateTime fechaSellado;
  final int disponible;
  final bool apto;
}

/// Primero en entrar, primero en salir (CP-21): propone el lote apto con stock sellado hace más tiempo.
LoteDisponible? elegirLotePeps(List<LoteDisponible> lotes) {
  final candidatos = lotes.where((l) => l.apto && l.disponible > 0).toList()
    ..sort((a, b) {
      final c = a.fechaSellado.compareTo(b.fechaSellado);
      return c != 0 ? c : a.codigo.compareTo(b.codigo);
    });
  return candidatos.isEmpty ? null : candidatos.first;
}

/// Un pago o cobro nunca supera el saldo pendiente (CP-18).
bool montoDentroDelSaldo(double monto, double saldo) => monto > 0 && monto <= saldo;

/// Una nota con descuento o que excede el crédito del cliente queda pendiente de aprobación.
bool notaRequiereAprobacion({
  required double descuento,
  required bool aCredito,
  required double deudaActual,
  required double totalNota,
  required double limiteCredito,
}) =>
    descuento > 0 || (aCredito && deudaActual + totalNota > limiteCredito);
