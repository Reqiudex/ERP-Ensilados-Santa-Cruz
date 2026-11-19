import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/supabase/api.dart';
import '../../../core/widgets/componentes.dart';
import '../data/repositorio_seguridad_supabase.dart';
import '../domain/roles_y_permisos.dart';
import 'politicas_pagina.dart';
import 'sesion.dart';

final granosParametrosProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(repositorioSeguridadProvider).granos());

/// RF-06 Respaldos y parámetros: valores de referencia que usan los módulos de negocio.
/// Los mantiene el administrador (sección 3.1 de la tesis) y el gerente los consulta. Los parámetros de seguridad
/// están en sus propios submódulos: contraseñas en RF-03, sesiones y PIN en RF-04.
class ParametrosPagina extends ConsumerWidget {
  const ParametrosPagina({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin = Accion.pedirRespaldo.permitida(ref.watch(perfilProvider)?.rol);
    return Pagina(
      etiquetaRf: 'Seguridad y Accesos · RF-06',
      titulo: 'Parámetros del sistema',
      subtitulo: 'La tesis agrupa respaldos y parámetros en el RF-06. Aquí están solo los valores de referencia de la operación; '
          'cada cambio queda en la bitácora.',
      alRefrescar: () async {
        ref.invalidate(granosParametrosProvider);
        ref.invalidate(parametrosProvider);
      },
      hijos: [
        if (!admin) const Aviso('Solo el administrador del sistema modifica estos valores; usted los puede consultar.'),
        _ParametrosGranos(editable: admin),
        _ParametrosOperativos(editable: admin),
      ],
    );
  }
}

class _ParametrosGranos extends ConsumerWidget {
  const _ParametrosGranos({required this.editable});
  final bool editable;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(granosParametrosProvider);
    return Asincrono(g,
        datos: (l) => TablaDatos(
              titulo: 'Parámetros por grano (se usan en Recepción y báscula, Orden de ensilado y Fermentación)',
              busqueda: false,
              exportar: false,
              filas: l,
              columnas: [
                Columna('Grano', (f) => '${f['nombre']}'),
                Columna('Humedad estándar', (f) => '${dec1(f['humedad_estandar'])} %'),
                Columna('Días de fermentación', (f) => '${f['dias_fermentacion']}'),
                Columna('Rollos por tonelada (rango normal)', (f) => '${dec2(f['rollos_ton_min'])} a ${dec2(f['rollos_ton_max'])}'),
              ],
              acciones: editable
                  ? (f) => [
                        IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => _editar(context, ref, f)),
                      ]
                  : null,
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

class _ParametrosOperativos extends ConsumerWidget {
  const _ParametrosOperativos({required this.editable});
  final bool editable;

  static const _editables = {
    'tolerancia_despacho_pct': ('Tolerancia de despacho (%)', 'Control de despachos (RF-19)'),
    'peso_promedio_rollo_kg': ('Peso promedio por rollo (kg)', 'Orden de ensilado y reportes de rendimiento (RF-08, RF-20)'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(parametrosProvider);
    return Asincrono(p,
        datos: (todo) => Padding(
              padding: const EdgeInsets.only(top: 20),
              child: TablaDatos(
                titulo: 'Parámetros operativos',
                busqueda: false,
                exportar: false,
                filas: [
                  for (final e in _editables.entries)
                    {'clave': e.key, 'nombre': e.value.$1, 'uso': e.value.$2, ...Map<String, dynamic>.from(todo[e.key] as Map? ?? {})},
                ],
                columnas: [
                  Columna('Parámetro', (f) => '${f['nombre']}'),
                  Columna('Valor', (f) => '${f['valor']}'),
                  Columna('Se usa en', (f) => '${f['uso']}', ancho: 300),
                  Columna('Descripción', (f) => '${f['descripcion'] ?? ''}', ancho: 320),
                  Columna('Actualizado', (f) => fechaHora(f['actualizado_en'])),
                ],
                acciones: editable
                    ? (f) => [
                          IconButton(
                            tooltip: 'Editar',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final t = await pedirTexto(context, f['nombre'] as String, etiqueta: 'Nuevo valor', minimo: 1, inicial: '${f['valor']}');
                              if (t == null || !context.mounted) return;
                              await ejecutar(context, () async {
                                await ref
                                    .read(repositorioSeguridadProvider)
                                    .guardarParametros({f['clave'] as String: num.tryParse(t.replaceAll(',', '.')) ?? t});
                                ref.invalidate(parametrosProvider);
                                return true;
                              }, exito: 'Parámetro guardado.');
                            },
                          ),
                        ]
                    : null,
              ),
            ));
  }
}
