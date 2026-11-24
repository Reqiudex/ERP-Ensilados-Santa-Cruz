import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/conexion/conexion.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../../seguridad_accesos/domain/roles_y_permisos.dart';
import '../../seguridad_accesos/presentation/sesion.dart';
import '../data/cola_sincronizacion.dart';
import '../data/repositorio_operaciones_supabase.dart';
import '../domain/calculos_operaciones.dart';
import 'ordenes_pagina.dart';

final insumosProvider = FutureProvider.autoDispose<List<Fila>>((ref) async {
  final repo = ref.watch(repositorioOperacionesProvider);
  return consultarConCopiaLocal(ref, 'insumos', remoto: () => repo.insumosDisponibles(), local: filasDeCopia);
});

final consumosProvider = FutureProvider.autoDispose.family<List<Fila>, String>((ref, orden) async {
  ref.watch(pendientesSincronizarProvider);
  List<Fila> deMapa(Object? mapa) => filasDeCopia(mapa is Map ? mapa[orden] : null);
  // Sin señal se observa la copia local; con señal se consulta el servidor sin observarla (evita recargas sin fin).
  if (!ref.watch(enLineaProvider)) {
    return deMapa(ref.watch(datosOperadorProvider.select((m) => m['consumos_por_orden'])));
  }
  final repo = ref.watch(repositorioOperacionesProvider);
  try {
    final l = await repo.consumos(orden);
    try {
      final actual = Map<String, dynamic>.from((ref.read(datosOperadorProvider)['consumos_por_orden'] as Map?) ?? const {});
      actual[orden] = l;
      ref.read(datosOperadorProvider.notifier).guardarClave('consumos_por_orden', actual);
    } catch (_) {}
    return l;
  } catch (_) {
    try {
      return deMapa(ref.read(datosOperadorProvider)['consumos_por_orden']);
    } catch (_) {
      return const <Fila>[];
    }
  }
});

const _insumos = {
  'dddddddd-dddd-dddd-dddd-dddddddddddd': ('Film estirable', 'film'),
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee': ('Malla tubular', 'malla'),
  'ffffffff-ffff-ffff-ffff-ffffffffffff': ('Inoculante', 'inoculante'),
};

/// RF-09 Consumo de insumos (film, malla e inoculante) por orden de ensilado.
class InsumosPagina extends ConsumerStatefulWidget {
  const InsumosPagina({super.key});
  @override
  ConsumerState<InsumosPagina> createState() => _InsumosPaginaState();
}

class _InsumosPaginaState extends ConsumerState<InsumosPagina> {
  String? _orden;

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(perfilProvider)!;
    final operador = Accion.registrarConsumo.permitida(perfil.rol);
    final stock = ref.watch(insumosProvider);
    final ordenes = (ref.watch(ordenesProvider).value ?? const []).where((o) => o['estado'] == 'abierta').toList();
    _orden ??= ordenes.firstOrNull?['id'] as String?;
    return Pagina(
      etiquetaRf: 'Operaciones y Procesamiento · RF-09',
      titulo: 'Consumo de insumos',
      subtitulo: 'Registre lo usado en cada orden abierta. Sin insumos suficientes la orden no se puede cerrar.',
      alRefrescar: () async {
        ref.invalidate(insumosProvider);
        ref.invalidate(ordenesProvider);
      },
      hijos: [
        Asincrono(stock,
            datos: (l) => !operador
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: TablaDatos(
                      titulo: 'Insumos por centro',
                      busqueda: false,
                      filas: l,
                      columnas: [
                        Columna('Centro', (s) => '${s['sede']}'),
                        Columna('Insumo', (s) => '${s['producto']}'),
                        Columna('Disponible', (s) => entero(s['disponible']), numerica: true),
                      ],
                    ),
                  )
                : FilaTarjetas([
                  for (final s in l)
                    TarjetaDato(
                      titulo: '${s['producto']}'.split(' ').take(2).join(' '),
                      valor: entero(s['disponible']),
                      icono: Icons.inventory_outlined,
                      color: aNumero(s['disponible']) < 10 ? Colores.peligro : Colores.primario,
                      detalle: 'unidades disponibles',
                    ),
                ])),
        if (ordenes.isEmpty) const MensajeVacio(titulo: 'No hay órdenes abiertas para registrar consumos.'),
        if (ordenes.isNotEmpty) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 360,
                  child: Selector(
                    etiqueta: 'Orden abierta',
                    opciones: ordenes,
                    valor: _orden,
                    texto: (o) => '${o['granos']?['nombre']} · ${fechaHora(o['fecha_apertura'])}',
                    alCambiar: (v) => setState(() => _orden = v),
                  ),
                ),
                if (operador && _orden != null)
                  FilledButton.icon(onPressed: () => _registrar(context), icon: const Icon(Icons.add), label: const Text('Registrar consumo')),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          if (_orden != null)
            Asincrono(ref.watch(consumosProvider(_orden!)), datos: (c) {
              final o = ordenes.firstWhere((x) => x['id'] == _orden, orElse: () => {});
              final kgAj = ((o['pesajes'] as List?) ?? const []).fold<double>(0, (a, p) => a + aNumero(p['peso_ajustado']));
              final estimado = (kgAj / 1000 * 1.18).round();
              final sug = consumoSugerido(estimado);
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (estimado > 0)
                  Aviso('Para unos $estimado rollos se sugieren ${sug['film']} film, ${sug['malla']} mallas y ${sug['inoculante']} inoculantes.'),
                TablaDatos(
                  titulo: 'Consumos de la orden',
                  busqueda: false,
                  filas: c,
                  columnas: [
                    Columna('Insumo', (f) => '${f['productos']?['nombre'] ?? '—'}'),
                    Columna('SKU', (f) => '${f['productos']?['sku'] ?? '—'}'),
                    Columna('Cantidad', (f) => dec2(f['cantidad']), numerica: true),
                  ],
                ),
              ]);
            }),
        ],
      ],
    );
  }

  Future<void> _registrar(BuildContext context) async {
    String? prod;
    final cant = TextEditingController();
    await dialogoFormulario<bool>(
      context,
      titulo: 'Registrar consumo',
      contenido: (c, s) => Column(mainAxisSize: MainAxisSize.min, children: [
        Selector(
          etiqueta: 'Insumo',
          opciones: [for (final e in _insumos.entries) {'id': e.key, 'nombre': e.value.$1}],
          valor: prod,
          alCambiar: (v) => s(() => prod = v),
        ),
        const SizedBox(height: 12),
        TextField(controller: cant, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad (unidades)')),
      ]),
      alGuardar: () async {
        final n = aNumero(cant.text.replaceAll(',', '.'));
        if (prod == null || n <= 0) {
          avisar(context, 'Elija el insumo y una cantidad mayor que cero.', error: true);
          return null;
        }
        await ref.read(colaProvider.notifier).registrar('consumos_insumo', {'orden_id': _orden, 'producto_id': prod, 'cantidad': n});
        ref.invalidate(consumosProvider(_orden!));
        return true;
      },
    );
  }
}
