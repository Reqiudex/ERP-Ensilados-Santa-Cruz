import 'package:flutter/material.dart';

/// Estilo único del sistema (paleta: verde ensilado y ámbar de cosecha).
class Colores {
  Colores._();
  static const primario = Color(0xFF1B4D3E);
  static const primarioOscuro = Color(0xFF003629);
  static const primarioClaro = Color(0xFFBAEED9);
  static const ambar = Color(0xFFFE932C);
  static const ambarOscuro = Color(0xFF904D00);
  static const fondo = Color(0xFFF5F8F6);
  static const superficie = Colors.white;
  static const borde = Color(0xFFD9E2DD);
  static const texto = Color(0xFF14201B);
  static const textoSuave = Color(0xFF5A6B63);
  static const exito = Color(0xFF1E8E5A);
  static const alerta = Color(0xFFC77700);
  static const peligro = Color(0xFFBA1A1A);
  static const info = Color(0xFF1F6FB2);
}

ThemeData temaSistema() {
  final esquema = ColorScheme.fromSeed(
    seedColor: Colores.primario,
    primary: Colores.primario,
    secondary: Colores.ambarOscuro,
    secondaryContainer: const Color(0xFFFFDCC3),
    surface: Colores.superficie,
    error: Colores.peligro,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: esquema);
  const radio = BorderRadius.all(Radius.circular(12));
  return base.copyWith(
    scaffoldBackgroundColor: Colores.fondo,
    textTheme: base.textTheme.apply(bodyColor: Colores.texto, displayColor: Colores.texto),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colores.superficie,
      foregroundColor: Colores.texto,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: Colores.superficie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radio, side: BorderSide(color: Colores.borde)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colores.superficie,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: Colores.borde)),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 48))),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
    chipTheme: base.chipTheme.copyWith(side: const BorderSide(color: Colores.borde)),
    dividerTheme: const DividerThemeData(color: Colores.borde, space: 1),
    navigationRailTheme: const NavigationRailThemeData(backgroundColor: Colores.superficie),
    dataTableTheme: const DataTableThemeData(
      headingTextStyle: TextStyle(fontWeight: FontWeight.w600, color: Colores.textoSuave, fontSize: 13),
      dataRowMinHeight: 48,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
