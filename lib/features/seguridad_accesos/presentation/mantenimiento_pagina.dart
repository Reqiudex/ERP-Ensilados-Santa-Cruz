import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/conexion/conexion.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../data/repositorio_seguridad_supabase.dart';
import '../domain/roles_y_permisos.dart';
import 'politicas_pagina.dart';
import 'sesion.dart';

final respaldosProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(repositorioSeguridadProvider).respaldos());
final granosParametrosProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(repositorioSeguridadProvider).granos());

/// RF-06 Mantenimiento y operaciones de la base de datos: respaldos, restauración aprobada y parámetros.
class MantenimientoPagina extends ConsumerWidget {
  const MantenimientoPagina({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = Accion.pedirRespaldo.permitida(ref.watch(perfilProvider)?.rol);
    final lat = ref.watch(latenciaProvider);
    final resp = ref.watch(respaldosProvider);
    final repo = ref.read(repositorioSeguridadProvider);
    return Pagina(
      etiquetaRf: 'Seguridad y Accesos · RF-06',
      titulo: 'Mantenimiento de la base de datos',
      subtitulo: 'Respaldo diario con GitHub Actions (pg_dump). La restauración solo se ejecuta tras la aprobación del gerente.',
      acciones: [
        if (admin)
          FilledButton.icon(
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Pedir respaldo manual'),
            onPressed: () async {
              await ejecutar(context, () async {
                await repo.pedirRespaldo();
                return true;
              }, exito: 'Respaldo en cola: el flujo programado lo genera en los próximos minutos.');
              ref.invalidate(respaldosProvider);
            },
          ),
      ],
      alRefrescar: () async {
        ref.invalidate(respaldosProvider);
        ref.invalidate(latenciaProvider);
      },
      hijos: [
        FilaTarjetas([
          lat.when(
            data: (l) => TarjetaDato(
              titulo: 'Conexión con Supabase',
              valor: l.ok ? '${l.ms} ms' : 'Sin conexión',
              icono: l.ok ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
              color: !l.ok ? Colores.peligro : l.ms <= 2000 ? Colores.exito : Colores.alerta,
              detalle: l.ok ? 'PostgreSQL ${l.version.split(' ').first} · ${fechaHora(l.hora)}' : 'Reintente en unos segundos',
              alTocar: () => ref.invalidate(latenciaProvider),
            ),
            loading: () => const TarjetaDato(titulo: 'Conexión con Supabase', valor: 'Midiendo…', icono: Icons.speed),
            error: (_, _) => const TarjetaDato(titulo: 'Conexión con Supabase', valor: 'Error', icono: Icons.error_outline),
          ),
          TarjetaDato(
            titulo: 'Respaldos registrados',
            valor: '${resp.value?.where((r) => r['accion'] == 'respaldo').length ?? '…'}',
            icono: Icons.inventory_2_outlined,
            color: Colores.ambarOscuro,
          ),
        ]),
        Asincrono(resp,
            datos: (l) => TablaDatos(
                  titulo: 'Historial de respaldos',
                  filas: l,
                  columnas: [
                    Columna('Fecha', (r) => fechaHora(r['fecha'])),
                    Columna('Evento', (r) => switch (r['accion']) {
                          'respaldo' => 'Respaldo generado',
                          'respaldo_pedido' => 'Respaldo manual pedido',
                          'restauracion' => 'Restauración aprobada',
                          _ => '${r['accion']}',
                        }),
                    Columna('Archivo', (r) => '${r['datos']?['archivo'] ?? r['datos']?['respaldo'] ?? '—'}'),
                    Columna('Tamaño', (r) => r['datos']?['bytes'] == null ? '—' : '${dec2(aNumero(r['datos']['bytes']) / 1048576)} MB', numerica: true),
                    Columna('SHA-256', (r) => '${r['datos']?['sha256'] ?? r['datos']?['estado'] ?? '—'}', ancho: 300),
                  ],
                  acciones: admin
                      ? (r) => [
                            if (r['accion'] == 'respaldo')
                              TextButton.icon(
                                icon: const Icon(Icons.restore, size: 18),
                                label: const Text('Solicitar restauración'),
                                onPressed: () async {
                                  final m = await pedirTexto(context, 'Solicitar restauración', etiqueta: 'Motivo (lo revisa el gerente)', minimo: 10);
                                  if (m == null || !context.mounted) return;
                                  await ejecutar(context, () async {
                                    await repo.solicitarRestauracion('${r['datos']?['archivo'] ?? r['id']}', m);
                                    return true;
                                  }, exito: 'Solicitud enviada: queda pendiente del gerente.');
                                },
                              ),
                          ]
                      : null,
                )),
        if (admin) ...[
          const _ParametrosGranos(),
          const _ParametrosGenerales(),
        ],
      ],
    );
  }
}

class _ParametrosGranos extends ConsumerWidget {
  const _ParametrosGranos();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(granosParametrosProvider);
    return Asincrono(g,
        datos: (l) => Padding(
              padding: const EdgeInsets.only(top: 20),
              child: TablaDatos(
                titulo: 'Parámetros por grano',
                busqueda: false,
                exportar: false,
                filas: l,
                columnas: [
                  Columna('Grano', (f) => '${f['nombre']}'),
                  Columna('Humedad estándar', (f) => '${dec1(f['humedad_estandar'])} %', numerica: true),
                  Columna('Días de fermentación', (f) => '${f['dias_fermentacion']}', numerica: true),
                  Columna('Rollos por tonelada (rango normal)', (f) => '${dec2(f['rollos_ton_min'])} a ${dec2(f['rollos_ton_max'])}'),
                ],
                acciones: (f) => [
                  IconButton(
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editar(context, ref, f),
                  ),
                ],
              ),
            ));
  }

  Future<void> _editar(BuildContext context, WidgetRef ref, Fila f) async {
    final h = TextEditingController(text: '${f['humedad_estandar']}');
    final d = TextEditingController(text: '${f['dias_fermentacion']}');
    final mi = TextEditingController(text: '${f['rollos_ton_min']}');
    final ma = TextEditingController(text: '${f['rollos_ton_max']}');
    await dialogoFormulario<bool>(
      context,
      titulo: 'Parámetros de ${f['nombre']}',
      contenido: (c, s) => Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: h, decoration: const InputDecoration(labelText: 'Humedad estándar (%)')),
        const SizedBox(height: 10),
        TextField(controller: d, decoration: const InputDecoration(labelText: 'Días mínimos de fermentación')),
        const SizedBox(height: 10),
        TextField(controller: mi, decoration: const InputDecoration(labelText: 'Rollos por tonelada: mínimo')),
        const SizedBox(height: 10),
        TextField(controller: ma, decoration: const InputDecoration(labelText: 'Rollos por tonelada: máximo')),
      ]),
      alGuardar: () => ejecutar(context, () async {
        await ref.read(repositorioSeguridadProvider).actualizarGrano((f['id'] as num).toInt(), aNumero(h.text.replaceAll(',', '.')),
            int.tryParse(d.text) ?? 21, aNumero(mi.text.replaceAll(',', '.')), aNumero(ma.text.replaceAll(',', '.')));
        ref.invalidate(granosParametrosProvider);
        return true;
      }, exito: 'Parámetros actualizados.'),
    );
  }
}

class _ParametrosGenerales extends ConsumerWidget {
  const _ParametrosGenerales();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(parametrosProvider);
    const editables = {
      'tolerancia_despacho_pct': 'Tolerancia de despacho (%)',
      'peso_promedio_rollo_kg': 'Peso promedio por rollo (kg)',
      'pin_min': 'Dígitos mínimos del PIN',
      'pin_max': 'Dígitos máximos del PIN',
      'pin_intentos': 'Intentos de PIN',
      'horas_sin_sincronizar': 'Horas máximas sin sincronizar',
    };
    return Asincrono(p,
        datos: (todo) => Padding(
              padding: const EdgeInsets.only(top: 20),
              child: TablaDatos(
                titulo: 'Parámetros generales',
                busqueda: false,
                exportar: false,
                filas: [
                  for (final e in editables.entries) {'clave': e.key, 'nombre': e.value, ...Map<String, dynamic>.from(todo[e.key] as Map? ?? {})},
                ],
                columnas: [
                  Columna('Parámetro', (f) => '${f['nombre']}'),
                  Columna('Valor', (f) => '${f['valor']}', numerica: true),
                  Columna('Descripción', (f) => '${f['descripcion'] ?? ''}', ancho: 380),
                  Columna('Actualizado', (f) => fechaHora(f['actualizado_en'])),
                ],
                acciones: (f) => [
                  IconButton(
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      final t = await pedirTexto(context, f['nombre'] as String, etiqueta: 'Nuevo valor', minimo: 1, inicial: '${f['valor']}');
                      if (t == null || !context.mounted) return;
                      await ejecutar(context, () async {
                        await ref.read(repositorioSeguridadProvider).guardarParametros({f['clave'] as String: num.tryParse(t.replaceAll(',', '.')) ?? t});
                        ref.invalidate(parametrosProvider);
                        return true;
                      }, exito: 'Parámetro guardado.');
                    },
                  ),
                ],
              ),
            ));
  }
}
