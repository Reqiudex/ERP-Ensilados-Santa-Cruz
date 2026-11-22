import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/conexion/conexion.dart';
import '../../../core/errores/errores.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../../operaciones_ensilado/data/cola_sincronizacion.dart';
import '../../seguridad_accesos/domain/roles_y_permisos.dart';
import '../../seguridad_accesos/presentation/sesion.dart';
import '../data/repositorio_inventario_supabase.dart';
import 'stock_lotes_pagina.dart';

final guiasProvider = FutureProvider.autoDispose<List<Fila>>((ref) async {
  ref.watch(pendientesSincronizarProvider);
  final enLinea = ref.watch(enLineaProvider);
  final cache = ref.watch(datosOperadorProvider.select((m) => m['guias']));
  List<Fila> locales() =>
      ((cache as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  if (!enLinea) return locales();
  try {
    final l = await ref.watch(repositorioInventarioProvider).guias();
    ref.read(datosOperadorProvider.notifier).guardarClave('guias', l);
    return l;
  } catch (_) {
    return locales();
  }
});

final sedesInventarioProvider = FutureProvider.autoDispose<List<Fila>>((ref) async {
  final enLinea = ref.watch(enLineaProvider);
  final cache = ref.watch(datosOperadorProvider.select((m) => m['sedes']));
  List<Fila> locales() {
    final l = ((cache as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    return l.isEmpty ? sedesPredeterminadas : l;
  }

  if (!enLinea) return locales();
  try {
    final l = await ref.watch(repositorioInventarioProvider).sedes();
    ref.read(datosOperadorProvider.notifier).guardarClave('sedes', l);
    return l.isEmpty ? locales() : l;
  } catch (_) {
    return locales();
  }
});

/// RF-14 Guías de remisión y transferencia entre centros.
class GuiasPagina extends ConsumerWidget {
  const GuiasPagina({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider)!;
    final operador = Accion.emitirGuia.permitida(perfil.rol);
    final enLinea = ref.watch(enLineaProvider);
    final v = ref.watch(guiasProvider);
    return Pagina(
      etiquetaRf: 'Inventario y Logística · RF-14',
      titulo: 'Guías de transferencia',
      subtitulo: 'El stock queda «en tránsito» hasta que un operador del centro de destino confirma lo recibido. '
          'Una diferencia genera sola la solicitud de merma de traslado.',
      acciones: [
        if (operador)
          FilledButton.icon(
              onPressed: () => _emitir(context, ref), icon: const Icon(Icons.local_shipping_outlined), label: const Text('Emitir guía')),
      ],
      alRefrescar: () async => ref.invalidate(guiasProvider),
      hijos: [
        if (operador && !enLinea)
          const Aviso('Sin conexión: las emisiones y recepciones de guías se guardan en el teléfono y se sincronizan al recuperar la señal.', tipo: 'alerta'),
        Asincrono(v, datos: (l) {
          final porRecibir = l.where((g) => g['estado'] == 'en_transito' && g['sede_destino'] == perfil.sedeId).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (operador && porRecibir.isNotEmpty)
              Seccion(
                titulo: 'Guías por recibir en su centro',
                icono: Icons.move_to_inbox_outlined,
                hijo: Column(children: [
                  for (final g in porRecibir)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const CircleAvatar(backgroundColor: Colores.primarioClaro, child: Icon(Icons.local_shipping, color: Colores.primario)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Guía N.º ${g['numero']} desde ${g['origen']?['nombre']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('${_detalle(g)} · emitida ${fechaHora(g['fecha_emision'])}', style: const TextStyle(color: Colores.textoSuave)),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                                onPressed: () => _recibir(context, ref, g),
                                icon: const Icon(Icons.fact_check_outlined),
                                label: const Text('Confirmar recepción')),
                          ]),
                        ),
                      ]),
                    ),
                ]),
              ),
            TablaDatos(
              titulo: 'Guías',
              filas: l,
              columnas: [
                Columna('N.º', (g) => '${g['numero']}', numerica: true),
                Columna('Origen', (g) => '${g['origen']?['nombre'] ?? '—'}'),
                Columna('Destino', (g) => '${g['destino']?['nombre'] ?? '—'}'),
                Columna('Lotes', _detalle, ancho: 280),
                Columna('Emitida', (g) => fechaHora(g['fecha_emision'])),
                Columna('Emisor', (g) => '${g['emisor']?['nombre_completo'] ?? '—'}'),
                Columna('Receptor', (g) => '${g['receptor']?['nombre_completo'] ?? '—'}'),
                Columna('Estado', (g) => etiqueta(g['estado']), celda: (g) => Estado(g['estado'])),
              ],
            ),
          ]);
        }),
      ],
    );
  }

  String _detalle(Fila g) => ((g['guia_detalle'] as List?) ?? const [])
      .map((d) => '${d['lotes']?['codigo']}: ${d['cantidad_enviada']}${d['cantidad_recibida'] != null ? ' → ${d['cantidad_recibida']}' : ''}')
      .join(', ');

  Future<void> _emitir(BuildContext context, WidgetRef ref) async {
    final perfil = ref.read(perfilProvider)!;
    final sedes = (await ref.read(sedesInventarioProvider.future)).where((s) => s['tipo'] == 'centro_acopio' && s['id'] != perfil.sedeId).toList();
    final lotes = (await ref.read(lotesProvider.future))
        .where((x) => ((x['existencias'] as List?) ?? const []).any((e) => e['sede_id'] == perfil.sedeId && aNumero(e['disponible']) > 0))
        .toList();
    if (!context.mounted) return;
    String? destino;
    String? lote;
    final cant = TextEditingController();
    final items = <Fila>[];
    await dialogoFormulario<bool>(
      context,
      titulo: 'Emitir guía de transferencia',
      guardar: 'Emitir guía',
      contenido: (c, s) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Selector(etiqueta: 'Centro de destino', opciones: sedes, valor: destino, alCambiar: (v) => s(() => destino = v)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            flex: 3,
            child: Selector(
              etiqueta: 'Lote',
              validar: false,
              opciones: lotes,
              valor: lote,
              texto: (x) {
                final d = ((x['existencias'] as List).firstWhere((e) => e['sede_id'] == perfil.sedeId))['disponible'];
                return '${x['codigo']} · ${entero(d)} disp.';
              },
              alCambiar: (v) => s(() => lote = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: cant, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rollos'))),
          IconButton(
            tooltip: 'Agregar',
            icon: const Icon(Icons.add_circle, color: Colores.primario),
            onPressed: () {
              final n = int.tryParse(cant.text) ?? 0;
              if (lote == null || n <= 0) return;
              s(() {
                items.add({'lote_id': lote, 'cantidad': n, 'codigo': lotes.firstWhere((x) => x['id'] == lote)['codigo']});
                cant.clear();
                lote = null;
              });
            },
          ),
        ]),
        const SizedBox(height: 8),
        for (final it in items)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${it['codigo']} · ${it['cantidad']} rollos'),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => s(() => items.remove(it))),
          ),
      ]),
      alGuardar: () async {
        if (destino == null || items.isEmpty) {
          avisar(context, 'Elija el destino y agregue al menos un lote.', error: true);
          return null;
        }
        final listaItems = [
          for (final i in items) {'lote_id': i['lote_id'], 'cantidad': i['cantidad'], 'codigo': i['codigo']}
        ];
        if (!ref.read(enLineaProvider)) {
          await ref.read(colaProvider.notifier).registrar('emitir_guia', {'destino': destino, 'items': listaItems});
          if (context.mounted) avisar(context, 'Guía guardada en el teléfono: se emitirá al recuperar la señal.');
          ref.invalidate(guiasProvider);
          return true;
        }
        final r = await ejecutar(context, () async {
          try {
            return await ref.read(repositorioInventarioProvider).emitirGuia(
                destino!, [for (final i in items) {'lote_id': i['lote_id'], 'cantidad': i['cantidad']}]);
          } on ErrorNegocio catch (e) {
            if (e.codigo != 'red') rethrow;
            await ref.read(colaProvider.notifier).registrar('emitir_guia', {'destino': destino, 'items': listaItems});
            return {'numero': 'PEND'};
          }
        });
        if (r == null) return null;
        if (context.mounted) {
          avisar(
              context,
              r['numero'] == 'PEND'
                  ? 'Guía guardada en el teléfono: se emitirá al recuperar la señal.'
                  : 'Guía N.º ${r['numero']} emitida: el stock quedó en tránsito.');
        }
        ref.invalidate(guiasProvider);
        ref.invalidate(lotesProvider);
        return true;
      },
    );
  }

  Future<void> _recibir(BuildContext context, WidgetRef ref, Fila g) async {
    final detalle = ((g['guia_detalle'] as List?) ?? const []).cast<Fila>();
    final ctrls = {for (final d in detalle) d['lote_id'] as String: TextEditingController(text: '${d['cantidad_enviada']}')};
    await dialogoFormulario<bool>(
      context,
      titulo: 'Recepción de la guía N.º ${g['numero']}',
      guardar: 'Confirmar recepción',
      contenido: (c, s) => Column(mainAxisSize: MainAxisSize.min, children: [
        const Aviso('Cuente los rollos que llegaron. Si faltan, se genera sola la solicitud de merma de traslado.'),
        for (final d in detalle)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: ctrls[d['lote_id']],
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: '${d['lotes']?['codigo']} (enviados ${d['cantidad_enviada']})'),
            ),
          ),
      ]),
      alGuardar: () async {
        final listaRec = [
          for (final d in detalle) {'lote_id': d['lote_id'], 'cantidad_recibida': int.tryParse(ctrls[d['lote_id']]!.text) ?? 0},
        ];
        if (!ref.read(enLineaProvider)) {
          await ref.read(colaProvider.notifier).registrar('recibir_guia', {'guia_id': g['id'], 'items': listaRec});
          if (context.mounted) avisar(context, 'Recepción guardada en el teléfono: se sincronizará al recuperar la señal.');
          ref.invalidate(guiasProvider);
          return true;
        }
        final r = await ejecutar(context, () async {
          try {
            return await ref.read(repositorioInventarioProvider).recibirGuia(g['id'], listaRec);
          } on ErrorNegocio catch (e) {
            if (e.codigo != 'red') rethrow;
            await ref.read(colaProvider.notifier).registrar('recibir_guia', {'guia_id': g['id'], 'items': listaRec});
            return {'offline': true};
          }
        });
        if (r == null) return null;
        if (context.mounted) {
          if (r['offline'] == true) {
            avisar(context, 'Recepción guardada en el teléfono: se sincronizará al recuperar la señal.');
          } else {
            avisar(context, (r['diferencia'] as num? ?? 0) > 0
                ? 'Recepción confirmada. Faltaron ${r['diferencia']} rollos: se envió la solicitud de merma de traslado al gerente.'
                : 'Recepción confirmada sin diferencias.');
          }
        }
        ref.invalidate(guiasProvider);
        return true;
      },
    );
  }
}
