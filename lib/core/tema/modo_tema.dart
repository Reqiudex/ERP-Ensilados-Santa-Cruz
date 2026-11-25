import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencia de tema del usuario (Claro / Oscuro / Sistema), guardada en el dispositivo.
class ModoTema extends Notifier<ThemeMode> {
  static const clave = 'modo_tema';

  @override
  ThemeMode build() {
    _cargar();
    return ThemeMode.system;
  }

  Future<void> _cargar() async {
    try {
      final guardado = (await SharedPreferences.getInstance()).getString(clave);
      final modo = ThemeMode.values.where((m) => m.name == guardado).firstOrNull;
      if (modo != null && ref.mounted) state = modo;
    } catch (_) {
      // Sin almacenamiento disponible: se queda con el tema del sistema.
    }
  }

  Future<void> cambiar(ThemeMode modo) async {
    state = modo;
    try {
      await (await SharedPreferences.getInstance()).setString(clave, modo.name);
    } catch (_) {}
  }
}

final modoTemaProvider = NotifierProvider<ModoTema, ThemeMode>(ModoTema.new);

String nombreModoTema(ThemeMode m) => switch (m) {
      ThemeMode.light => 'Claro',
      ThemeMode.dark => 'Oscuro',
      ThemeMode.system => 'Sistema',
    };

IconData iconoModoTema(ThemeMode m) => switch (m) {
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
      ThemeMode.system => Icons.brightness_auto_outlined,
    };
