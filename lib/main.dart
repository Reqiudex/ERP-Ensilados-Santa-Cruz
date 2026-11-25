import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/router/rutas.dart';
import 'core/supabase/supabase_config.dart';
import 'core/tema/modo_tema.dart';
import 'core/tema/tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.publishableKey);
  // Accesibilidad en el portal web (lectores de pantalla y pruebas automáticas de interfaz).
  if (kIsWeb && Uri.base.queryParameters['semantica'] == '1') SemanticsBinding.instance.ensureSemantics();
  runApp(const ProviderScope(child: AplicacionErp()));
}

class AplicacionErp extends ConsumerWidget {
  const AplicacionErp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movil = Uri.base.queryParameters['vista'] == 'movil';
    return MaterialApp.router(
      title: 'ERP Ensilados Santa Cruz',
      debugShowCheckedModeBanner: false,
      theme: temaSistema(),
      darkTheme: temaOscuro(),
      themeMode: ref.watch(modoTemaProvider),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('es', 'BO'),
      supportedLocales: const [Locale('es', 'BO'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, hijo) {
        if (!movil) return hijo!;
        // Vista previa del diseño Android dentro del navegador (mismo código, pantalla de 360 × 800).
        return ColoredBox(
          color: const Color(0xFF2B3A34),
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 360,
                height: 800,
                child: MediaQuery(data: MediaQuery.of(context).copyWith(size: const Size(360, 800)), child: hijo!),
              ),
            ),
          ),
        );
      },
    );
  }
}
