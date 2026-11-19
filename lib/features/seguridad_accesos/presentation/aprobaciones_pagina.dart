import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../data/repositorio_seguridad_supabase.dart';

/// Cambios en tiempo real de las solicitudes (Realtime): la bandeja se actualiza sola.
final cambiosSolicitudesProvider = StreamProvider.autoDispose<int>((ref) {
  var n = 0;
  return ref.watch(apiProvider).flujo('solicitudes_aprobacion').map((_) => ++n);
});

final bandejaProvider = FutureProvider.autoDispose.family<List<Fila>, String>((ref, estado) {
  ref.watch(cambiosSolicitudesProvider);
  return ref.watch(repositorioSeguridadProvider).bandeja(estado);
});

/// RF-02 Bandeja de aprobaciones del gerente: las solicitudes más antiguas primero.
class AprobacionesPagina extends ConsumerStatefulWidget {
  const AprobacionesPagina({super.key});
  @override
  ConsumerState<AprobacionesPagina> createState() => _AprobacionesPaginaState();
}

class _AprobacionesPaginaState extends ConsumerState<AprobacionesPagina> {
  String _estado = 'pendiente';

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(bandejaProvider(_estado));
    return Pagina(
      etiquetaRf: 'Seguridad y Accesos · RF-02',
      titulo: 'Bandeja de aprobaciones',
      subtitulo: 'Las más antiguas primero. Nadie aprueba lo que registró: la base de datos lo rechaza por restricción CHECK.',
      acciones: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'pendiente', label: Text('Pendientes'), icon: Icon(Icons.hourglass_top)),
            ButtonSegment(value: 'todas', label: Text('Historial'), icon: Icon(Icons.history)),
          ],
          selected: {_estado},
          onSelectionChanged: (s) => setState(() => _estado = s.first),
        ),
      ],
      alRefrescar: () async => ref.invalidate(bandejaProvider(_estado)),
      hijos: [
        Asincrono(v, alReintentar: () => ref.invalidate(bandejaProvider(_estado)), datos: (lista) {
          if (lista.isEmpty) {
            return const MensajeVacio(icono: Icons.task_alt, titulo: 'No hay solicitudes pendientes.', detalle: 'Todo está al día.');
          }
          return Column(children: [
            if (_estado == 'pendiente')
              FilaTarjetas([
                TarjetaDato(titulo: 'Pendientes', valor: '${lista.length}', icono: Icons.pending_actions, color: Colores.alerta),
                TarjetaDato(
                    titulo: 'La más antigua',
                    valor: fecha(lista.first['fecha_registro']),
                    icono: Icons.schedule,
                    detalle: etiqueta(lista.first['tipo'])),
              ]),
            for (final s in lista) _TarjetaSolicitud(s, alResolver: () => ref.invalidate(bandejaProvider(_estado))),
          ]);
        }),
      ],
    );
  }
}

class _TarjetaSolicitud extends ConsumerWidget {
  const _TarjetaSolicitud(this.s, {required this.alResolver});
  final Fila s;
  final VoidCallback alResolver;

  List<(String, String)> _detalle() {
    final d = Map<String, dynamic>.from(s['datos'] as Map? ?? const {});
    String v(Object? x) => x == null ? '—' : '$x';
    return switch (s['tipo']) {
      'correccion_pesaje' => [
          ('Antes', 'Bruto ${kg(d['antes']?['peso_bruto'])}, tara ${kg(d['antes']?['tara'])}, humedad ${v(d['antes']?['humedad'])} %'),
          ('Nuevo', 'Bruto ${kg(d['nuevo']?['peso_bruto'])}, tara ${kg(d['nuevo']?['tara'])}, humedad ${v(d['nuevo']?['humedad'])} %'),
          ('Placa', v(d['antes']?['placa'])),
        ],
      'merma' => [('Lote', v(d['codigo'])), ('Rollos', v(d['cantidad'])), ('Causa', etiqueta(d['causa'])), ('Descripción', v(d['descripcion']))],
      'ajuste' => [('Diferencia', v(d['cantidad'])), ('Descripción', v(d['descripcion']))],
      'cambio_precio' => [
          ('Producto', v(d['sku'])),
          ('Antes', '${bs(d['antes']?['precio_tonelada'])}/t · ${bs(d['antes']?['precio_rollo'])}/rollo'),
          ('Nuevo', '${bs(d['nuevo']?['precio_tonelada'])}/t · ${bs(d['nuevo']?['precio_rollo'])}/rollo'),
        ],
      'producto_nuevo' => [('SKU', v(d['sku'])), ('Nombre', v(d['nombre'])), ('Precios', '${bs(d['precio_tonelada'])}/t · ${bs(d['precio_rollo'])}/rollo')],
      'activar_proveedor' => [('Proveedor', v(d['razon_social'])), ('NIT/CI', v(d['nit_ci'])), ('Tipo', etiqueta(d['tipo']))],
      'limite_credito' => [('Cliente', v(d['cliente'])), ('Límite actual', bs(d['antes'])), ('Límite pedido', bs(d['nuevo']))],
      'compra' => [('Proveedor', v(d['proveedor'])), ('Total', bs(d['total']))],
      'nota_venta' => [
          ('Nota', 'N.º ${v(d['numero'])} · ${v(d['cliente'])}'),
          ('Subtotal / descuento', '${bs(d['subtotal'])} / ${bs(d['descuento'])}'),
          ('Total', '${bs(d['total'])} · ${etiqueta(d['condicion'])}'),
          if (d['excede_credito'] == true) ('Crédito', 'Deuda ${bs(d['deuda'])} + nota supera el límite de ${bs(d['limite_credito'])}'),
        ],
      'anulacion_venta' => [('Nota', 'N.º ${v(d['numero'])}'), ('Total', bs(d['total']))],
      'anulacion_cobro' => [('Recibo', 'N.º ${v(d['recibo'])}'), ('Monto', bs(d['monto']))],
      'despacho_exceso' => [
          ('Nota', 'N.º ${v(d['nota'])} · placa ${v(d['placa'])}'),
          ('Peso vendido', kg(d['peso_vendido'])),
          ('Peso despachado', '${kg(d['peso_despachado'])} (${(d['pesos'] as List?)?.length ?? 0} rollos)'),
        ],
      'rol_privilegiado' => [('Usuario', v(d['usuario'])), ('Rol pedido', etiqueta(d['rol']))],
      'restauracion' => [('Respaldo', v(d['respaldo']))],
      _ => [for (final e in d.entries) (e.key, v(e.value))],
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendiente = s['estado'] == 'pendiente';
    final propia = s['propia'] == true;
    final dias = DateTime.now().difference(aFecha(s['fecha_registro']) ?? DateTime.now()).inDays;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(etiqueta(s['tipo']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Estado(s['estado']),
              if (pendiente && dias > 0) Chip(visualDensity: VisualDensity.compact, label: Text('hace $dias días')),
            ]),
            const SizedBox(height: 6),
            Text('${s['registrado_por']} · ${s['rol']} · ${s['sede']} · ${fechaHora(s['fecha_registro'])}',
                style: const TextStyle(color: Colores.textoSuave, fontSize: 13)),
            const SizedBox(height: 10),
            Text('Motivo: ${s['motivo']}'),
            const SizedBox(height: 8),
            for (final (k, v) in _detalle())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 170, child: Text(k, style: const TextStyle(color: Colores.textoSuave))),
                  Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500))),
                ]),
              ),
            if (!pendiente) ...[
              const SizedBox(height: 8),
              Text('Resuelta por ${s['aprobado_por'] ?? '—'} el ${fechaHora(s['fecha_decision'])}'
                  '${(s['datos'] as Map?)?['motivo_decision'] != null ? ' · ${(s['datos'] as Map)['motivo_decision']}' : ''}',
                  style: const TextStyle(color: Colores.textoSuave)),
            ],
            if (pendiente) ...[
              const SizedBox(height: 12),
              if (propia) const Aviso('Usted registró esta solicitud: debe aprobarla otra persona.', tipo: 'alerta'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: () async {
                    if (!await confirmar(context, 'Aprobar solicitud', 'La operación se aplicará en la misma transacción y quedará en la bitácora.', si: 'Aprobar')) return;
                    if (!context.mounted) return;
                    await ejecutar(context, () => ref.read(repositorioSeguridadProvider).resolverSolicitud(s['id'], true, null), exito: 'Solicitud aprobada.');
                    alResolver();
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Aprobar'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colores.peligro),
                  onPressed: () async {
                    final m = await pedirTexto(context, 'Rechazar solicitud', etiqueta: 'Motivo del rechazo');
                    if (m == null || !context.mounted) return;
                    await ejecutar(context, () => ref.read(repositorioSeguridadProvider).resolverSolicitud(s['id'], false, m), exito: 'Solicitud rechazada.');
                    alResolver();
                  },
                  icon: const Icon(Icons.close),
                  label: const Text('Rechazar'),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
