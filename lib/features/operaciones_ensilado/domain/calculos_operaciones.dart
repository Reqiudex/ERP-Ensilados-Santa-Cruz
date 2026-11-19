/// Reglas de negocio de Operaciones y Procesamiento (RF-07 a RF-10).
/// Dart puro: no depende de Flutter ni de Supabase.
library;

/// Error de validación de un registro de báscula.
class PesajeInvalido implements Exception {
  const PesajeInvalido(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}

/// Peso neto = bruto − tara (CP-07). La tara debe ser positiva y menor que el bruto.
double pesoNeto(double bruto, double tara) {
  if (tara <= 0) throw const PesajeInvalido('La tara debe ser mayor que cero.');
  if (tara >= bruto) {
    throw const PesajeInvalido('El peso bruto debe ser mayor que la tara.');
  }
  return bruto - tara;
}

/// Ajuste por humedad (CP-08): neto × (100 − humedad) ÷ (100 − humedad estándar), redondeado a 0,1 kg.
double pesoAjustadoPorHumedad(double neto, double humedad, double humedadEstandar) {
  if (humedad < 0 || humedad >= 100) {
    throw const PesajeInvalido('La humedad debe estar entre 0 y 100 %.');
  }
  final ajustado = neto * (100 - humedad) / (100 - humedadEstandar);
  return (ajustado * 10).round() / 10;
}

/// Un lote está apto cuando cumplió los días mínimos de fermentación del grano (CP-12).
bool loteApto(DateTime fechaSellado, int diasMinimos, DateTime hoy) {
  final sellado = DateTime(fechaSellado.year, fechaSellado.month, fechaSellado.day);
  final dia = DateTime(hoy.year, hoy.month, hoy.day);
  return dia.difference(sellado).inDays >= diasMinimos;
}

/// Días que faltan para que el lote esté apto (0 si ya lo está).
int diasParaApto(DateTime fechaSellado, int diasMinimos, DateTime hoy) {
  final sellado = DateTime(fechaSellado.year, fechaSellado.month, fechaSellado.day);
  final dia = DateTime(hoy.year, hoy.month, hoy.day);
  final faltan = diasMinimos - dia.difference(sellado).inDays;
  return faltan < 0 ? 0 : faltan;
}

/// Consumo de insumos sugerido para una orden según los rollos (film, malla e inoculante).
Map<String, int> consumoSugerido(int rollos) => {
      'film': (rollos / 20).ceil(),
      'malla': (rollos / 30).ceil(),
      'inoculante': (rollos / 25).ceil(),
    };

/// Faltante de un insumo para cerrar la orden (CP-11). Devuelve 0 si alcanza.
double faltanteInsumo(double requerido, double disponible) =>
    requerido > disponible ? requerido - disponible : 0;
