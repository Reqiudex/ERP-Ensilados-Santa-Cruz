import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../../reportes/domain/calculos_reportes.dart';
import '../../seguridad_accesos/domain/roles_y_permisos.dart';
import '../../seguridad_accesos/presentation/sesion.dart';
import '../data/cola_sincronizacion.dart';
import '../data/repositorio_operaciones_supabase.dart';

final ordenesProvider = FutureProvider.autoDispose<List<Fila>>((ref) {
  ref.watch(pendientesSincronizarProvider);
  return ref.watch(repositorioOperacionesProvider).ordenes();
});

/// El lote de una orden llega como objeto (relación uno a uno) o como lista según la consulta.
Fila? _lote(Fila o) {
  final l = o['lotes'];
  if (l is List) return l.isEmpty ? null : Map<String, dynamic>.from(l.first as Map);
  return l == null ? null : Map<String, dynamic>.from(l as Map);
}

double _kgAjustado(Fila o) => ((o['pesajes'] as List?) ?? const [])
    .where((p) => p['estado'] == 'confirmado')
    .fold<double>(0, (a, p) => a + aNumero(p['peso_ajustado']));

/// RF-08 Orden de producción / ensilado: abrir, cerrar y crear el lote con código único.
class OrdenesPagina extends ConsumerWidget {
  const OrdenesPagina({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider)!;
    final operador = Accion.cerrarOrden.permitida(perfil.rol);
    final v = ref.watch(ordenesProvider);
    return Pagina(
      etiquetaRf: 'Operaciones y Procesamiento · RF-08',
      titulo: 'Órdenes de ensilado',
      subtitulo: 'Al cerrar la orden se crea el lote «en fermentación», ingresa el stock y se descuentan los insumos en la misma transacción.',
      acciones: [
        if (operador) FilledButton.icon(onPressed: () => _abrir(context, ref), icon: const Icon(Icons.add), label: const Text('Abrir orden')),
      ],
      alRefrescar: () async => ref.invalidate(ordenesProvider),
      hijos: [
        Asincrono(v, alReintentar: () => ref.invalidate(ordenesProvider), datos: (l) {
          final abiertas = l.where((o) => o['estado'] == 'abierta').toList();
          final cerradas = l.where((o) => o['estado'] == 'cerrada').toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (abiertas.isEmpty) const MensajeVacio(titulo: 'No hay órdenes abiertas.', icono: Icons.precision_manufacturing_outlined),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final o in abiertas)
                SizedBox(
                  width: esAncho(context) ? 360 : double.infinity,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${o['granos']?['nombre']} · ${o['sedes']?['nombre'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
                          const Estado('abierta'),
                        ]),
                        const SizedBox(height: 6),
                        Text('Abierta el ${fechaHora(o['fecha_apertura'])}', style: const TextStyle(color: Colores.textoSuave)),
                        const SizedBox(height: 10),
                        Text('${(o['pesajes'] as List?)?.where((p) => p['estado'] == 'confirmado').length ?? 0} pesajes · ${toneladas(_kgAjustado(o) / 1000)} ajustadas'),
                        const SizedBox(height: 12),
                        if (operador)
                          FilledButton.icon(
                            onPressed: () => _cerrar(context, ref, o),
                            icon: const Icon(Icons.lock_outline),
                            label: const Text('Cerrar orden y crear lote'),
                          ),
                      ]),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 20),
            TablaDatos(
              titulo: 'Órdenes cerradas y lotes',
              filas: cerradas,
              columnas: [
                Columna('Cierre', (o) => fecha(o['fecha_cierre'])),
                if (!operador) Columna('Centro', (o) => '${o['sedes']?['nombre'] ?? ''}'),
                Columna('Grano', (o) => '${o['granos']?['nombre']}'),
                Columna('Lote', (o) => '${_lote(o)?['codigo'] ?? '—'}'),
                Columna('Toneladas', (o) => toneladas(_kgAjustado(o) / 1000), numerica: true),
                Columna('Rollos', (o) => '${o['rollos_obtenidos']}', numerica: true),
                Columna('Rollos/t', (o) => dec2(rendimientoRollosPorTonelada((o['rollos_obtenidos'] as num).toInt(), _kgAjustado(o) / 1000)), numerica: true,
                    celda: (o) {
                  final r = rendimientoRollosPorTonelada((o['rollos_obtenidos'] as num).toInt(), _kgAjustado(o) / 1000);
                  final fuera = rendimientoFueraDeRango(r, aNumero(o['granos']?['rollos_ton_min']), aNumero(o['granos']?['rollos_ton_max']));
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(dec2(r), style: TextStyle(color: fuera ? Colores.peligro : null, fontWeight: fuera ? FontWeight.w700 : null)),
                    if (fuera) const Icon(Icons.warning_amber_rounded, size: 16, color: Colores.peligro),
                  ]);
                }),
                Columna('Estado del lote', (o) => etiqueta(_lote(o)?['estado']),
                    celda: (o) => Estado(_lote(o)?['estado'])),
              ],
            ),
          ]);
        }),
      ],
    );
  }

  Future<void> _abrir(BuildContext context, WidgetRef ref) async {
    final perfil = ref.read(perfilProvider)!;
    final granos = (((ref.read(datosOperadorProvider))['granos'] as List?) ?? const []).cast<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    String? grano;
    await dialogoFormulario<bool>(
      context,
      titulo: 'Abrir orden de ensilado',
      guardar: 'Abrir',
      contenido: (c, s) => Selector(etiqueta: 'Grano', opciones: granos, valor: grano, alCambiar: (v) => s(() => grano = v)),
      alGuardar: () async {
        if (grano == null) return null;
        final datos = {
          'sede_id': perfil.sedeId,
          'grano_id': int.parse(grano!),
          'fecha_apertura': DateTime.now().toUtc().toIso8601String(),
          'estado': 'abierta',
          'registrado_por': perfil.id,
        };
        final id = await ref.read(colaProvider.notifier).registrar('ordenes_ensilado', datos);
        ref.read(datosOperadorProvider.notifier).agregarOrdenLocal({
          'id': id,
          'grano_id': int.parse(grano!),
          'fecha_apertura': datos['fecha_apertura'],
          'grano': granos.firstWhere((g) => '${g['id']}' == grano)['nombre'],
        });
        ref.invalidate(ordenesProvider);
        return true;
      },
    );
  }

  Future<void> _cerrar(BuildContext context, WidgetRef ref, Fila o) async {
    final ctrl = TextEditingController();
    final t = _kgAjustado(o) / 1000;
    final mn = aNumero(o['granos']?['rollos_ton_min']);
    final mx = aNumero(o['granos']?['rollos_ton_max']);
    final r = await dialogoFormulario<Fila>(
      context,
      titulo: 'Cerrar orden de ${o['granos']?['nombre']}',
      guardar: 'Cerrar y crear lote',
      contenido: (c, s) {
        final rollos = int.tryParse(ctrl.text) ?? 0;
        final rend = rendimientoRollosPorTonelada(rollos, t);
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Grano recibido: ${toneladas(t)} ajustadas por humedad.'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(labelText: 'Rollos obtenidos'),
            onChanged: (_) => s(() {}),
          ),
          const SizedBox(height: 12),
          if (rollos > 0)
            Aviso('Rendimiento: ${dec2(rend)} rollos por tonelada (rango normal ${dec2(mn)} a ${dec2(mx)}).',
                tipo: rendimientoFueraDeRango(rend, mn, mx) ? 'alerta' : 'ok'),
          const Aviso('Si los insumos consumidos superan el stock del centro, el cierre se bloquea e indica el faltante.'),
        ]);
      },
      alGuardar: () => ejecutar(context, () => ref.read(repositorioOperacionesProvider).cerrarOrden(o['id'], int.tryParse(ctrl.text) ?? 0)),
    );
    if (r != null && context.mounted) {
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.qr_code_2, size: 40, color: Colores.primario),
          title: Text('Lote ${r['codigo']}'),
          content: Text('Creado «en fermentación» con ${ctrl.text} rollos.\nRendimiento ${dec2(r['rendimiento'])} rollos/t.'
              '${r['alerta'] != null ? '\n\n⚠ ${r['alerta']}' : ''}'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Aceptar'))],
        ),
      );
      ref.invalidate(ordenesProvider);
      ref.read(datosOperadorProvider.notifier).refrescar();
    }
  }
}
