import 'package:flutter/material.dart';

/// Paleta de marca fija (modo claro). Para pantallas usar `context.paleta`, que cambia con el tema;
/// estos valores fijos quedan para PDF/Excel y para fondos de marca que no cambian (portada de ingreso).
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


/// Colores semánticos del sistema que cambian según el tema (claro u oscuro).
@immutable
class PaletaErp extends ThemeExtension<PaletaErp> {
  const PaletaErp({
    required this.primario,
    required this.primarioOscuro,
    required this.primarioClaro,
    required this.ambar,
    required this.ambarOscuro,
    required this.fondo,
    required this.superficie,
    required this.borde,
    required this.texto,
    required this.textoSuave,
    required this.exito,
    required this.alerta,
    required this.peligro,
    required this.info,
    required this.sobrePrimario,
    required this.sobreAmbar,
  });

  /// Texto e íconos de marca sobre la superficie.
  final Color primario;
  /// Acento de marca más intenso (texto seleccionado).
  final Color primarioOscuro;
  /// Contenedor suave de marca (fondos de avatar, filas seleccionadas).
  final Color primarioClaro;
  final Color ambar;
  /// Ámbar legible como texto sobre la superficie.
  final Color ambarOscuro;
  final Color fondo;
  final Color superficie;
  final Color borde;
  final Color texto;
  final Color textoSuave;
  final Color exito;
  final Color alerta;
  final Color peligro;
  final Color info;
  /// Texto sobre un relleno de color [primario].
  final Color sobrePrimario;
  /// Texto sobre un relleno de color [ambar].
  final Color sobreAmbar;

  static const claro = PaletaErp(
    primario: Colores.primario,
    primarioOscuro: Colores.primarioOscuro,
    primarioClaro: Colores.primarioClaro,
    ambar: Colores.ambar,
    ambarOscuro: Colores.ambarOscuro,
    fondo: Colores.fondo,
    superficie: Colores.superficie,
    borde: Colores.borde,
    texto: Colores.texto,
    textoSuave: Colores.textoSuave,
    exito: Colores.exito,
    alerta: Colores.alerta,
    peligro: Colores.peligro,
    info: Colores.info,
    sobrePrimario: Colors.white,
    sobreAmbar: Color(0xFF2E1500),
  );

  // Modo oscuro: tonos claros de la misma marca sobre superficies verde-carbón (contraste AA ≥ 4.5:1 en texto).
  static const oscuro = PaletaErp(
    primario: Color(0xFF8ED6B8),
    primarioOscuro: Color(0xFFB5EED6),
    primarioClaro: Color(0xFF1F4A3C),
    ambar: Color(0xFFFFB870),
    ambarOscuro: Color(0xFFFFB77C),
    fondo: Color(0xFF0F1714),
    superficie: Color(0xFF18221E),
    borde: Color(0xFF34433C),
    texto: Color(0xFFE2EBE6),
    textoSuave: Color(0xFFA9BAB2),
    exito: Color(0xFF72D7A2),
    alerta: Color(0xFFFFC261),
    peligro: Color(0xFFFFB4AB),
    info: Color(0xFF9DCBFF),
    sobrePrimario: Color(0xFF00382A),
    sobreAmbar: Color(0xFF2E1500),
  );

  @override
  PaletaErp copyWith({Color? primario, Color? texto}) => PaletaErp(
        primario: primario ?? this.primario,
        primarioOscuro: primarioOscuro,
        primarioClaro: primarioClaro,
        ambar: ambar,
        ambarOscuro: ambarOscuro,
        fondo: fondo,
        superficie: superficie,
        borde: borde,
        texto: texto ?? this.texto,
        textoSuave: textoSuave,
        exito: exito,
        alerta: alerta,
        peligro: peligro,
        info: info,
        sobrePrimario: sobrePrimario,
        sobreAmbar: sobreAmbar,
      );

  @override
  PaletaErp lerp(ThemeExtension<PaletaErp>? other, double t) {
    if (other is! PaletaErp) return this;
    Color m(Color a, Color b) => Color.lerp(a, b, t)!;
    return PaletaErp(
      primario: m(primario, other.primario),
      primarioOscuro: m(primarioOscuro, other.primarioOscuro),
      primarioClaro: m(primarioClaro, other.primarioClaro),
      ambar: m(ambar, other.ambar),
      ambarOscuro: m(ambarOscuro, other.ambarOscuro),
      fondo: m(fondo, other.fondo),
      superficie: m(superficie, other.superficie),
      borde: m(borde, other.borde),
      texto: m(texto, other.texto),
      textoSuave: m(textoSuave, other.textoSuave),
      exito: m(exito, other.exito),
      alerta: m(alerta, other.alerta),
      peligro: m(peligro, other.peligro),
      info: m(info, other.info),
      sobrePrimario: m(sobrePrimario, other.sobrePrimario),
      sobreAmbar: m(sobreAmbar, other.sobreAmbar),
    );
  }
}

extension PaletaContexto on BuildContext {
  /// Paleta del tema activo (claro u oscuro).
  PaletaErp get paleta => Theme.of(this).extension<PaletaErp>() ?? PaletaErp.claro;
}

ThemeData temaSistema() => _tema(Brightness.light);

ThemeData temaOscuro() => _tema(Brightness.dark);

ThemeData _tema(Brightness brillo) {
  final oscuro = brillo == Brightness.dark;
  final p = oscuro ? PaletaErp.oscuro : PaletaErp.claro;
  final esquema = oscuro
      ? ColorScheme.fromSeed(
          seedColor: Colores.primario,
          brightness: Brightness.dark,
          primary: p.primario,
          onPrimary: p.sobrePrimario,
          primaryContainer: p.primarioClaro,
          onPrimaryContainer: p.primarioOscuro,
          secondary: p.ambarOscuro,
          onSecondary: const Color(0xFF4A2800),
          secondaryContainer: const Color(0xFF6E3A00),
          onSecondaryContainer: const Color(0xFFFFDCC3),
          surface: p.superficie,
          onSurface: p.texto,
          onSurfaceVariant: p.textoSuave,
          outline: const Color(0xFF7D8F87),
          outlineVariant: p.borde,
          error: p.peligro,
          onError: const Color(0xFF690005),
        )
      : ColorScheme.fromSeed(
          seedColor: Colores.primario,
          primary: Colores.primario,
          secondary: Colores.ambarOscuro,
          secondaryContainer: const Color(0xFFFFDCC3),
          surface: Colores.superficie,
          error: Colores.peligro,
        );
  final base = ThemeData(useMaterial3: true, colorScheme: esquema, brightness: brillo);
  const radio = BorderRadius.all(Radius.circular(12));
  return base.copyWith(
    extensions: [p],
    scaffoldBackgroundColor: p.fondo,
    textTheme: base.textTheme.apply(bodyColor: p.texto, displayColor: p.texto),
    appBarTheme: AppBarTheme(
      backgroundColor: p.superficie,
      foregroundColor: p.texto,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: p.superficie,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radio, side: BorderSide(color: p.borde)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.superficie),
    popupMenuTheme: PopupMenuThemeData(color: p.superficie),
    drawerTheme: DrawerThemeData(backgroundColor: p.superficie),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.superficie),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: oscuro ? const Color(0xFF121B17) : Colores.superficie,
      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(10)), borderSide: BorderSide(color: p.borde)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
    chipTheme: base.chipTheme.copyWith(side: BorderSide(color: p.borde)),
    dividerTheme: DividerThemeData(color: p.borde, space: 1),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: p.superficie),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: TextStyle(fontWeight: FontWeight.w600, color: p.textoSuave, fontSize: 13),
      dataRowMinHeight: 48,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
