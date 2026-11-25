import 'package:erp_ensilados_santa_cruz/core/tema/modo_tema.dart';
import 'package:erp_ensilados_santa_cruz/core/tema/tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

double contraste(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final (claro, oscuro) = la > lb ? (la, lb) : (lb, la);
  return (claro + 0.05) / (oscuro + 0.05);
}

void main() {
  test('Modo oscuro: texto y colores semánticos con contraste AA (≥ 4.5:1) sobre fondo y superficie', () {
    const p = PaletaErp.oscuro;
    final textos = {
      'texto': p.texto, 'textoSuave': p.textoSuave, 'primario': p.primario, 'primarioOscuro': p.primarioOscuro,
      'ambarOscuro': p.ambarOscuro, 'exito': p.exito, 'alerta': p.alerta, 'peligro': p.peligro, 'info': p.info,
    };
    for (final fondo in [p.fondo, p.superficie]) {
      textos.forEach((n, c) => expect(contraste(c, fondo), greaterThanOrEqualTo(4.5), reason: n));
    }
    expect(contraste(p.sobrePrimario, p.primario), greaterThanOrEqualTo(4.5));
    expect(contraste(p.primario, p.primarioClaro), greaterThanOrEqualTo(4.5));
    expect(contraste(PaletaErp.claro.sobreAmbar, PaletaErp.claro.ambar), greaterThanOrEqualTo(4.5));
  });

  test('Temas claro y oscuro: Material 3, brillo correcto y paleta incluida', () {
    final claro = temaSistema(), oscuro = temaOscuro();
    expect(claro.useMaterial3 && oscuro.useMaterial3, isTrue);
    expect(claro.colorScheme.brightness, Brightness.light);
    expect(oscuro.colorScheme.brightness, Brightness.dark);
    expect(claro.extension<PaletaErp>(), PaletaErp.claro);
    expect(oscuro.extension<PaletaErp>(), PaletaErp.oscuro);
    expect(oscuro.scaffoldBackgroundColor, PaletaErp.oscuro.fondo);
  });

  test('La preferencia de tema se guarda y se recupera', () async {
    SharedPreferences.setMockInitialValues({});
    final c1 = ProviderContainer();
    expect(c1.read(modoTemaProvider), ThemeMode.system);
    await c1.read(modoTemaProvider.notifier).cambiar(ThemeMode.dark);
    c1.dispose();
    final c2 = ProviderContainer();
    c2.read(modoTemaProvider);
    await Future<void>.delayed(Duration.zero);
    expect(c2.read(modoTemaProvider), ThemeMode.dark);
    c2.dispose();
  });

  testWidgets('context.paleta sigue al tema activo', (t) async {
    late PaletaErp vista;
    await t.pumpWidget(MaterialApp(
      theme: temaSistema(),
      darkTheme: temaOscuro(),
      themeMode: ThemeMode.dark,
      home: Builder(builder: (c) {
        vista = c.paleta;
        return const SizedBox();
      }),
    ));
    expect(vista, PaletaErp.oscuro);
  });
}
