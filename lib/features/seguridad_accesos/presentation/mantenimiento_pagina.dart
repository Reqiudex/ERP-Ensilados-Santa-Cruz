import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/conexion/conexion.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../data/repositorio_seguridad_supabase.dart';
import '../domain/roles_y_permisos.dart';
import 'confirmar_clave.dart';
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
      subtitulo: 'Respaldos con GitHub Actions (pg_dump) según la programación. La restauración solo se ejecuta tras la aprobación del gerente.',
      acciones: [
        if (admin)
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text('Optimizar base de datos'),
            onPressed: () async {
              final n = await ejecutar(context, repo.optimizarBase);
              if (n != null && context.mounted) avisar(context, 'Estadísticas e índices actualizados en $n tablas (ANALYZE).');
              ref.invalidate(respaldosProvider);
            },
          ),
        if (admin)
          FilledButton.icon(
            icon: const Icon(Icons.backup_outlined),
            label: const Text('Respaldo manual ahora'),
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
        if (admin) const _ProgramacionRespaldos(),
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


/// Estrategia y programación automática de respaldos (la lee el flujo «Respaldo de la base de datos»).
class _ProgramacionRespaldos extends ConsumerStatefulWidget {
  const _ProgramacionRespaldos();
  @override
  ConsumerState<_ProgramacionRespaldos> createState() => _ProgramacionRespaldosState();
}

class _ProgramacionRespaldosState extends ConsumerState<_ProgramacionRespaldos> {
  Map<String, dynamic>? _v;
  static const _claves = ['respaldo_activo', 'respaldo_frecuencia', 'respaldo_hora_utc', 'respaldo_retencion_dias', 'respaldo_estrategia'];

  /// Bolivia está en UTC−4 todo el año.
  static int _horaLocal(String utc) => ((int.tryParse(utc.split(':').first) ?? 7) - 4 + 24) % 24;
  static String _horaUtc(int local) => '${((local + 4) % 24).toString().padLeft(2, '0')}:00';

  Future<void> _guardar() async {
    final ok = await confirmarConClave(context, ref,
        titulo: 'Confirmar programación de respaldos', detalle: 'Ingrese su contraseña de administrador para guardar la programación.');
    if (!ok || !mounted) return;
    await ejecutar(context, () async {
      await ref.read(repositorioSeguridadProvider).guardarParametros({for (final k in _claves) k: _v![k]});
      return true;
    }, exito: 'Programación guardada y registrada en la bitácora.');
    ref.invalidate(parametrosProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(parametrosProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Asincrono(p, datos: (todo) {
        _v ??= {for (final k in _claves) k: (todo[k] as Map?)?['valor']};
        final activo = _v!['respaldo_activo'] == true;
        return Seccion(
          titulo: 'Estrategia y programación de respaldos',
          icono: Icons.schedule_outlined,
          hijo: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Estrategia'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'completo', label: Text('Completo (Full)'), icon: Icon(Icons.storage)),
                ButtonSegment(value: 'incremental', label: Text('Incremental'), enabled: false),
                ButtonSegment(value: 'diferencial', label: Text('Diferencial'), enabled: false),
              ],
              selected: {'${_v!['respaldo_estrategia'] ?? 'completo'}'},
              onSelectionChanged: (x) => setState(() => _v!['respaldo_estrategia'] = x.first),
            ),
            const SizedBox(height: 6),
            Text('Incremental y diferencial no están disponibles: Supabase (plan gratuito) no da acceso a los registros WAL; '
                'cada respaldo es un volcado completo con pg_dump.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Respaldo automático en segundo plano'),
              value: activo,
              onChanged: (b) => setState(() => _v!['respaldo_activo'] = b),
            ),
            Wrap(spacing: 16, runSpacing: 16, children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: '${_v!['respaldo_frecuencia'] ?? 'diaria'}',
                  decoration: const InputDecoration(labelText: 'Frecuencia'),
                  items: const [
                    DropdownMenuItem(value: 'diaria', child: Text('Diario')),
                    DropdownMenuItem(value: 'semanal', child: Text('Semanal (lunes)')),
                    DropdownMenuItem(value: 'mensual', child: Text('Mensual (día 1)')),
                  ],
                  onChanged: activo ? (x) => setState(() => _v!['respaldo_frecuencia'] = x) : null,
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int>(
                  initialValue: _horaLocal('${_v!['respaldo_hora_utc'] ?? '07:00'}'),
                  decoration: const InputDecoration(labelText: 'Hora de ejecución (Bolivia)'),
                  items: [for (var h = 0; h < 24; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))],
                  onChanged: activo ? (x) => setState(() => _v!['respaldo_hora_utc'] = _horaUtc(x ?? 3)) : null,
                ),
              ),
            ]),
            const SizedBox(height: 16),
            const Text('Retención'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final d in const [7, 15, 30])
                ChoiceChip(
                  label: Text('Últimos $d días'),
                  selected: (_v!['respaldo_retencion_dias'] as num?)?.toInt() == d,
                  onSelected: (_) => setState(() => _v!['respaldo_retencion_dias'] = d),
                ),
            ]),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(icon: const Icon(Icons.save_outlined), label: const Text('Guardar programación'), onPressed: _guardar),
            ),
          ]),
        );
      }),
    );
  }
}
