import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../../inventario_multisede/data/repositorio_inventario_supabase.dart';
import '../../seguridad_accesos/domain/roles_y_permisos.dart';
import '../../seguridad_accesos/presentation/sesion.dart';
import '../data/repositorio_comercial_supabase.dart';
import '../domain/calculos_comerciales.dart';
import 'clientes_proveedores_pagina.dart';
import 'ventas_pagina.dart';

final pedidosProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(repositorioComercialProvider).pedidos());

/// RF-17 Cotización y pedidos: reserva solo rollos de lotes aptos, primero los más antiguos (PEPS).
class PedidosPagina extends ConsumerStatefulWidget {
  const PedidosPagina({super.key});
  @override
  ConsumerState<PedidosPagina> createState() => _PedidosPaginaState();
}

class _PedidosPaginaState extends ConsumerState<PedidosPagina> {
  String? _estado;

  @override
  Widget build(BuildContext context) {
    final ejecutivo = Accion.registrarPedido.permitida(ref.watch(perfilProvider)?.rol);
    final v = ref.watch(pedidosProvider);
    final repo = ref.read(repositorioComercialProvider);
    return Pagina(
      etiquetaRf: 'Comercial y Abastecimiento · RF-17',
      titulo: 'Cotizaciones y pedidos',
      subtitulo: 'Mayoristas compran por tonelada y minoristas por rollo. El pedido reserva rollos aptos del lote más antiguo.',
      acciones: [
        if (ejecutivo) FilledButton.icon(onPressed: () => _nuevo(context), icon: const Icon(Icons.add), label: const Text('Nueva cotización o pedido')),
      ],
      alRefrescar: () async => ref.invalidate(pedidosProvider),
      hijos: [
        Asincrono(v,
            datos: (l) => TablaDatos(
                  titulo: 'Pedidos',
                  filas: l.where((p) => _estado == null || p['estado'] == _estado).toList(),
                  filtros: [
                    for (final e in ['cotizacion', 'pedido', 'vendido', 'cancelado'])
                      FilterChip(label: Text(etiqueta(e)), selected: _estado == e, onSelected: (b) => setState(() => _estado = b ? e : null)),
                  ],
                  columnas: [
                    Columna('Fecha', (p) => fechaHora(p['fecha_registro'])),
                    Columna('Cliente', (p) => '${p['clientes']?['razon_social']}'),
                    Columna('Unidad', (p) => etiqueta(p['unidad_venta'])),
                    Columna('Lotes (PEPS)', (p) => ((p['pedido_detalle'] as List?) ?? const [])
                        .map((d) => '${d['lotes']?['codigo']} (${d['rollos_equivalentes']} r)')
                        .join(', '), ancho: 300),
                    Columna('Cantidad', (p) => _cantidad(p), numerica: true),
                    Columna('Importe', (p) => bs(_importe(p)), numerica: true),
                    Columna('Estado', (p) => etiqueta(p['estado']), celda: (p) => Estado(p['estado'])),
                  ],
                  acciones: ejecutivo
                      ? (p) => [
                            if (p['estado'] == 'cotizacion')
                              TextButton(
                                  onPressed: () async {
                                    await ejecutar(context, () => repo.confirmarPedido(p['id']), exito: 'Cotización confirmada: los rollos quedaron reservados.');
                                    ref.invalidate(pedidosProvider);
                                  },
                                  child: const Text('Confirmar')),
                            if (p['estado'] == 'pedido')
                              FilledButton.tonal(
                                  onPressed: () async {
                                    await emitirNota(context, ref, p);
                                    ref.invalidate(pedidosProvider);
                                  },
                                  child: const Text('Nota de venta')),
                            if (p['estado'] == 'cotizacion' || p['estado'] == 'pedido')
                              IconButton(
                                tooltip: 'Cancelar',
                                icon: const Icon(Icons.cancel_outlined, color: Colores.peligro),
                                onPressed: () async {
                                  if (!await confirmar(context, 'Cancelar pedido', 'Se liberarán los rollos reservados.')) return;
                                  if (!context.mounted) return;
                                  await ejecutar(context, () => repo.cancelarPedido(p['id']), exito: 'Pedido cancelado.');
                                  ref.invalidate(pedidosProvider);
                                },
                              ),
                          ]
                      : null,
                )),
      ],
    );
  }

  String _cantidad(Fila p) {
    final d = (p['pedido_detalle'] as List?) ?? const [];
    final rollos = d.fold<num>(0, (a, x) => a + (x['rollos_equivalentes'] as num));
    if (p['unidad_venta'] == 'tonelada') {
      return '${dec2(d.fold<double>(0, (a, x) => a + aNumero(x['cantidad'])))} t · $rollos rollos';
    }
    return '$rollos rollos';
  }

  double _importe(Fila p) =>
      ((p['pedido_detalle'] as List?) ?? const []).fold<double>(0, (a, x) => a + aNumero(x['cantidad']) * aNumero(x['precio_unitario']));

  Future<void> _nuevo(BuildContext context) async {
    final clientes = await ref.read(clientesProvider.future);
    final catalogo = (await ref.read(repositorioInventarioProvider).catalogo()).where((p) => p['tipo'] == 'rollo' && p['activo'] == true).toList();
    final stock = await ref.read(repositorioInventarioProvider).existencias();
    if (!context.mounted) return;
    String? cliente;
    String unidad = 'tonelada';
    String? producto;
    String estado = 'pedido';
    final cant = TextEditingController();
    await dialogoFormulario<bool>(
      context,
      titulo: 'Nueva cotización o pedido',
      guardar: 'Guardar',
      contenido: (c, s) {
        final prod = catalogo.where((p) => p['id'] == producto).firstOrNull;
        final aptos = stock.where((e) => e['producto'] == prod?['nombre'] && e['estado_lote'] == 'apto' && aNumero(e['disponible']) > 0).toList();
        final peps = elegirLotePeps([
          for (final e in aptos)
            LoteDisponible(codigo: '${e['lote']}', fechaSellado: aFecha(e['fecha_sellado']) ?? DateTime.now(), disponible: aNumero(e['disponible']).round()),
        ]);
        final n = aNumero(cant.text.replaceAll(',', '.'));
        final rollos = unidad == 'tonelada' && n > 0 ? toneladasARollos(n, 850) : n.round();
        final precio = unidad == 'tonelada' ? aNumero(prod?['precio_tonelada']) : aNumero(prod?['precio_rollo']);
        final disponibles = aptos.fold<double>(0, (a, e) => a + aNumero(e['disponible']));
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Selector(
            etiqueta: 'Cliente',
            opciones: clientes,
            valor: cliente,
            texto: (x) => '${x['razon_social']} (${etiqueta(x['tipo'])})',
            alCambiar: (v) => s(() {
              cliente = v;
              unidad = clientes.firstWhere((x) => x['id'] == v)['tipo'] == 'minorista' ? 'rollo' : 'tonelada';
            }),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'tonelada', label: Text('Por tonelada')), ButtonSegment(value: 'rollo', label: Text('Por rollo'))],
            selected: {unidad},
            onSelectionChanged: (v) => s(() => unidad = v.first),
          ),
          const SizedBox(height: 12),
          Selector(etiqueta: 'Producto', opciones: catalogo, valor: producto, alCambiar: (v) => s(() => producto = v)),
          const SizedBox(height: 12),
          TextField(
            controller: cant,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: unidad == 'tonelada' ? 'Toneladas' : 'Rollos'),
            onChanged: (_) => s(() {}),
          ),
          const SizedBox(height: 12),
          if (prod != null) ...[
            Aviso('Stock apto: ${entero(disponibles)} rollos. '
                '${peps != null ? 'PEPS propone el lote ${peps.codigo} (sellado el ${fecha(peps.fechaSellado.toIso8601String())}).' : 'No hay lotes aptos.'}'),
            if (n > 0)
              Card(
                color: Colores.primarioClaro.withValues(alpha: .3),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    unidad == 'tonelada'
                        ? '${dec2(n)} t ≈ $rollos rollos de 850 kg · ${bs(precio)}/t · importe ${bs(n * precio)}'
                        : '$rollos rollos · ${bs(precio)}/rollo · importe ${bs(n * precio)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'cotizacion', label: Text('Cotización (no reserva)')),
              ButtonSegment(value: 'pedido', label: Text('Pedido (reserva)')),
            ],
            selected: {estado},
            onSelectionChanged: (v) => s(() => estado = v.first),
          ),
        ]);
      },
      alGuardar: () async {
        if (cliente == null || producto == null || aNumero(cant.text.replaceAll(',', '.')) <= 0) {
          avisar(context, 'Complete cliente, producto y cantidad.', error: true);
          return null;
        }
        final r = await ejecutar(context, () => ref.read(repositorioComercialProvider).registrarPedido(cliente!, unidad, [
              {'producto_id': producto, 'cantidad': aNumero(cant.text.replaceAll(',', '.'))}
            ], estado));
        if (r == null) return null;
        final lotes = ((r['detalle'] as List?) ?? const []).map((d) => '${d['lote']} (${d['rollos']} rollos)').join(', ');
        if (context.mounted) avisar(context, '${estado == 'pedido' ? 'Pedido registrado y reservado' : 'Cotización registrada'}: $lotes.');
        ref.invalidate(pedidosProvider);
        return true;
      },
    );
  }
}

