import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/supabase/api.dart';
import '../../../core/widgets/componentes.dart';
import '../data/repositorio_seguridad_supabase.dart';
import '../domain/roles_y_permisos.dart';
import 'sesion.dart';

final sesionesProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(repositorioSeguridadProvider).sesionesActivas());

String _dispositivo(String? agente) {
  final a = (agente ?? '').toLowerCase();
  final sistema = a.contains('android') ? 'Android' : a.contains('windows') ? 'Windows' : a.contains('mac') ? 'macOS' : a.contains('linux') ? 'Linux' : 'Otro';
  final nav = a.contains('edg') ? 'Edge' : a.contains('firefox') ? 'Firefox' : a.contains('chrome') ? 'Chrome' : a.contains('dart') ? 'App Android' : a.contains('safari') ? 'Safari' : '';
  return [nav, sistema].where((x) => x.isNotEmpty).join(' · ');
}

/// RF-04 Sesiones activas: cierre por usuario y «cerrar todas las demás» (revocación en Supabase Auth).
class SesionesPagina extends ConsumerWidget {
  const SesionesPagina({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(sesionesProvider);
    final puede = Accion.cerrarSesiones.permitida(ref.watch(perfilProvider)?.rol);
    final repo = ref.read(repositorioSeguridadProvider);
    return Pagina(
      etiquetaRf: 'Seguridad y Accesos · RF-04',
      titulo: 'Autenticación y sesiones',
      subtitulo: 'Sesiones abiertas en el portal y en la app. Cierre por inactividad: 15 minutos. PIN sin conexión: solo Android.',
      acciones: [
        if (puede)
          FilledButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('Cerrar todas las demás'),
            onPressed: () async {
              if (!await confirmar(context, 'Cerrar todas las demás sesiones', 'Se revocarán todas las sesiones excepto la suya.')) return;
              if (!context.mounted) return;
              final n = await ejecutar(context, () => repo.cerrarSesiones(null));
              if (n != null && context.mounted) avisar(context, '$n sesiones cerradas.');
              ref.invalidate(sesionesProvider);
            },
          ),
      ],
      alRefrescar: () async => ref.invalidate(sesionesProvider),
      hijos: [
        Asincrono(v,
            datos: (l) => TablaDatos(
                  titulo: 'Sesiones activas',
                  filas: l,
                  columnas: [
                    Columna('Usuario', (f) => '${f['usuario']}${f['actual'] == true ? ' (esta sesión)' : ''}'),
                    Columna('Rol', (f) => '${f['rol']}'),
                    Columna('Dispositivo o navegador', (f) => _dispositivo(f['agente'] as String?)),
                    Columna('IP', (f) => '${f['ip'] ?? '—'}'),
                    Columna('Inicio', (f) => fechaHora(f['inicio'])),
                    Columna('Última actividad', (f) => fechaHora(f['ultima_actividad'])),
                  ],
                  acciones: puede
                      ? (f) => [
                            if (f['actual'] != true)
                              TextButton.icon(
                                icon: const Icon(Icons.logout, size: 18),
                                label: const Text('Cerrar sesión'),
                                onPressed: () async {
                                  await ejecutar(context, () => repo.cerrarSesiones(f['usuario_id'] as String), exito: 'Sesiones del usuario cerradas.');
                                  ref.invalidate(sesionesProvider);
                                },
                              ),
                          ]
                      : null,
                )),
      ],
    );
  }
}
