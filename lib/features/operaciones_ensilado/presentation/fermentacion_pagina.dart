import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../../seguridad_accesos/domain/roles_y_permisos.dart';
import '../../seguridad_accesos/presentation/sesion.dart';
import '../data/cola_sincronizacion.dart';
import '../data/repositorio_operaciones_supabase.dart';
import '../domain/calculos_operaciones.dart';

final lotesFermentacionProvider = FutureProvider.autoDispose<List<Fila>>((ref) async {
  ref.watch(pendientesSincronizarProvider);
  final repo = ref.watch(repositorioOperacionesProvider);
  return consultarConCopiaLocal(ref, 'lotes_fermentacion', local: filasDeCopia, remoto: () async {
    try {
      await repo.actualizarAptos();
    } catch (_) {}
    return repo.lotesEnFermentacion();
  });
});

/// RF-10 Control de fermentación y calidad: días mínimos por grano y estado visual del film.
class FermentacionPagina extends ConsumerStatefulWidget {
  const FermentacionPagina({super.key});
  @override
  ConsumerState<FermentacionPagina> createState() => _FermentacionPaginaState();
}

class _FermentacionPaginaState extends ConsumerState<FermentacionPagina> {
  bool _soloFermentando = true;

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(perfilProvider)!;
    final operador = Accion.revisarFermentacion.permitida(perfil.rol);
    final v = ref.watch(lotesFermentacionProvider);
    return Pagina(
      etiquetaRf: 'Operaciones y Procesamiento · RF-10',
      titulo: 'Fermentación y calidad',
      subtitulo: 'Un lote pasa a «apto» al cumplir los días mínimos del grano; un film dañado lo deja «observado».',
      acciones: [
        FilterChip(label: const Text('Solo en fermentación u observados'), selected: _soloFermentando, onSelected: (b) => setState(() => _soloFermentando = b)),
      ],
      alRefrescar: () async => ref.invalidate(lotesFermentacionProvider),
      hijos: [
        Asincrono(v, datos: (l) {
          final hoy = DateTime.now();
          final filas = l.where((x) => !_soloFermentando || x['estado'] == 'fermentacion' || x['estado'] == 'observado').toList();
          if (filas.isEmpty) return const MensajeVacio(titulo: 'No hay lotes en fermentación.', icono: Icons.thermostat_outlined);
          return Wrap(spacing: 12, runSpacing: 12, children: [
            for (final x in filas)
              Builder(builder: (_) {
                final sellado = aFecha(x['fecha_sellado']) ?? hoy;
                final dias = (x['productos']?['granos']?['dias_fermentacion'] as num?)?.toInt() ?? 21;
                final transcurridos = hoy.difference(sellado).inDays;
                final faltan = diasParaApto(sellado, dias, hoy);
                return SizedBox(
                  width: esAncho(context) ? 330 : double.infinity,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${x['codigo']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                          Estado(x['estado']),
                        ]),
                        Text('${x['productos']?['granos']?['nombre']} · ${x['rollos_producidos']} rollos · ${x['sedes']?['nombre'] ?? ''}',
                            style: TextStyle(color: context.paleta.textoSuave)),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            minHeight: 10,
                            value: (transcurridos / dias).clamp(0, 1).toDouble(),
                            color: loteApto(sellado, dias, hoy) ? context.paleta.exito : context.paleta.ambar,
                            backgroundColor: context.paleta.borde,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(faltan == 0 ? 'Cumplió $dias días (sellado el ${fecha(x['fecha_sellado'])})' : 'Día $transcurridos de $dias · faltan $faltan días',
                            style: const TextStyle(fontSize: 13)),
                        if (operador) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _revisar(context, x, 'integro'),
                                icon: Icon(Icons.check_circle_outline, color: context.paleta.exito),
                                label: const Text('Film íntegro'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _revisar(context, x, 'danado'),
                                icon: Icon(Icons.report_outlined, color: context.paleta.peligro),
                                label: const Text('Film dañado'),
                              ),
                            ),
                          ]),
                        ],
                      ]),
                    ),
                  ),
                );
              }),
          ]);
        }),
      ],
    );
  }

  Future<void> _revisar(BuildContext context, Fila lote, String estado) async {
    final obs = await pedirTexto(context, 'Revisión del lote ${lote['codigo']} · film ${etiqueta(estado)}', etiqueta: 'Observación', minimo: 3);
    if (obs == null) return;
    final perfil = ref.read(perfilProvider)!;
    await ref.read(colaProvider.notifier).registrar('revisiones_fermentacion', {
      'lote_id': lote['id'],
      'estado_film': estado,
      'observacion': obs,
      'registrado_por': perfil.id,
    });
    if (context.mounted) avisar(context, 'Revisión registrada.');
    ref.invalidate(lotesFermentacionProvider);
  }
}
