/// Indicadores de los reportes (RF-20 a RF-23). Dart puro.
library;

double _redondear(double v, int decimales) => double.parse(v.toStringAsFixed(decimales));

/// Rendimiento del ensilado (CP-22): rollos ÷ toneladas netas, con dos decimales.
double rendimientoRollosPorTonelada(int rollos, double toneladasNetas) {
  if (toneladasNetas <= 0) return 0;
  return _redondear(rollos / toneladasNetas, 2);
}

/// Alerta de control compensatorio: el rendimiento salió del rango normal del grano.
bool rendimientoFueraDeRango(double rendimiento, double minimo, double maximo) =>
    rendimiento < minimo || rendimiento > maximo;

/// Rotación (CP-23): salidas ÷ stock promedio.
double rotacion(double salidas, double stockPromedio) {
  if (stockPromedio <= 0) return 0;
  return _redondear(salidas / stockPromedio, 2);
}

/// Porcentaje de merma (CP-25): bajas ÷ total × 100, con un decimal.
double porcentajeMerma(int bajas, int total) {
  if (total <= 0) return 0;
  return _redondear(bajas / total * 100, 1);
}
