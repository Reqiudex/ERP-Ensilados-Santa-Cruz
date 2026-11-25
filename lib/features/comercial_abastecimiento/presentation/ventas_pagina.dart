import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../../seguridad_accesos/domain/roles_y_permisos.dart';
import '../../seguridad_accesos/presentation/sesion.dart';
import '../data/repositorio_comercial_supabase.dart';
import '../domain/calculos_comerciales.dart';

final notasProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(repositorioComercialProvider).notasVenta());

/// Emite la nota de venta de un pedido (ejecutivo). Un descuento o una venta sobre el crédito la deja pendiente.
Future<void> emitirNota(BuildContext context, WidgetRef ref, Fila pedido) async {
  String condicion = 'contado';
  final desc = TextEditingController(text: '0');
  final factura = TextEditingController();
  final subtotal = ((pedido['pedido_detalle'] as List?) ?? const [])
      .fold<double>(0, (a, x) => a + aNumero(x['cantidad']) * aNumero(x['precio_unitario']));
  final r = await dialogoFormulario<Fila>(
    context,
    titulo: 'Nota de venta · ${pedido['clientes']?['razon_social']}',
    guardar: 'Emitir nota',
    contenido: (c, s) {
      final d = aNumero(desc.text.replaceAll(',', '.'));
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Subtotal según catálogo: ${bs(subtotal)}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'contado', label: Text('Contado')), ButtonSegment(value: 'credito', label: Text('Crédito'))],
          selected: {condicion},
          onSelectionChanged: (v) => s(() => condicion = v.first),
        ),
        const SizedBox(height: 12),
        TextField(controller: desc, decoration: const InputDecoration(labelText: 'Descuento (Bs)'), onChanged: (_) => s(() {})),
        const SizedBox(height: 12),
        TextField(controller: factura, decoration: const InputDecoration(labelText: 'N.º de factura del SIN (opcional; se emite en el sistema externo)')),
        const SizedBox(height: 12),
        Text('Total: ${bs(subtotal - d)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        if (d > 0) const Aviso('Con descuento la nota queda pendiente de aprobación del gerente.', tipo: 'alerta'),
        if (condicion == 'credito') const Aviso('Si la venta supera el límite de crédito del cliente, la aprueba el gerente.'),
      ]);
    },
    alGuardar: () => ejecutar(context, () => ref.read(repositorioComercialProvider).emitirNotaVenta(
        pedido['id'], condicion, aNumero(desc.text.replaceAll(',', '.')), factura.text.trim().isEmpty ? null : factura.text.trim())),
  );
  if (r != null && context.mounted) {
    avisar(context, r['estado'] == 'pendiente'
        ? 'Nota N.º ${r['numero']} registrada: pendiente de aprobación del gerente.'
        : 'Nota de venta N.º ${r['numero']} emitida por ${bs(r['total'])}.');
    ref.invalidate(notasProvider);
  }
}

/// RF-18 Facturación y ventas: notas de venta (ejecutivo), cobros (cajero) y anulaciones (gerente aprueba).
class VentasPagina extends ConsumerStatefulWidget {
  const VentasPagina({super.key});
  @override
  ConsumerState<VentasPagina> createState() => _VentasPaginaState();
}

class _VentasPaginaState extends ConsumerState<VentasPagina> {
  String? _estado;

  @override
  Widget build(BuildContext context) {
    final rol = ref.watch(perfilProvider)?.rol;
    final ejecutivo = Accion.emitirNotaVenta.permitida(rol);
    final cajero = Accion.registrarCobro.permitida(rol);
    final v = ref.watch(notasProvider);
    final repo = ref.read(repositorioComercialProvider);
    return Pagina(
      etiquetaRf: 'Comercial y Abastecimiento · RF-18',
      titulo: 'Ventas, cobros y anulaciones',
      subtitulo: 'Quien vende no cobra: el ejecutivo emite la nota y solo el cajero registra cobros. '
          'Notas y recibos con numeración correlativa; la factura del SIN se emite en el sistema externo y aquí se guarda su número.',
      alRefrescar: () async => ref.invalidate(notasProvider),
      hijos: [
        Asincrono(v, datos: (l) {
          final porCobrar = l.where((n) => n['estado'] == 'emitida' && aNumero(n['saldo']) > 0);
          return Column(children: [
            FilaTarjetas([
              TarjetaDato(titulo: 'Notas emitidas', valor: '${l.where((n) => n['estado'] == 'emitida').length}', icono: Icons.receipt_long_outlined),
              TarjetaDato(titulo: 'Por cobrar', valor: bs(porCobrar.fold<double>(0, (a, n) => a + aNumero(n['saldo']))), icono: Icons.account_balance_wallet_outlined, color: context.paleta.ambarOscuro),
              TarjetaDato(titulo: 'Pendientes de aprobación', valor: '${l.where((n) => n['estado'] == 'pendiente').length}', icono: Icons.hourglass_top, color: context.paleta.alerta),
            ]),
            TablaDatos(
              titulo: 'Notas de venta',
              filas: l.where((n) => _estado == null || n['estado'] == _estado).toList(),
              filtros: [
                for (final e in ['emitida', 'pendiente', 'anulada'])
                  FilterChip(label: Text(etiqueta(e)), selected: _estado == e, onSelected: (b) => setState(() => _estado = b ? e : null)),
              ],
              alTocar: (n) => _detalle(context, n),
              columnas: [
                Columna('N.º', (n) => '${n['numero']}', numerica: true),
                Columna('Fecha', (n) => fecha(n['fecha_registro'])),
                Columna('Cliente', (n) => '${n['pedidos']?['clientes']?['razon_social']}'),
                Columna('Condición', (n) => etiqueta(n['condicion_pago'])),
                Columna('Total', (n) => bs(n['total']), numerica: true),
                Columna('Saldo', (n) => bs(n['saldo']), numerica: true),
                Columna('Factura SIN', (n) => '${n['nro_factura'] ?? '—'}'),
                Columna('Estado', (n) => etiqueta(n['estado']), celda: (n) => Estado(n['estado'])),
              ],
              acciones: (n) => [
                if (cajero && n['estado'] == 'emitida' && aNumero(n['saldo']) > 0)
                  FilledButton.tonal(onPressed: () => _cobrar(context, n), child: const Text('Cobrar')),
                if (ejecutivo && n['nro_factura'] == null && n['estado'] != 'anulada')
                  TextButton(
                    onPressed: () async {
                      final t = await pedirTexto(context, 'N.º de factura del SIN', etiqueta: 'Número', minimo: 1);
                      if (t == null || !context.mounted) return;
                      await ejecutar(context, () => repo.registrarFactura(n['id'], t), exito: 'Número de factura guardado.');
                      ref.invalidate(notasProvider);
                    },
                    child: const Text('Factura'),
                  ),
                if (ejecutivo && n['estado'] != 'anulada')
                  IconButton(
                    tooltip: 'Solicitar anulación',
                    icon: Icon(Icons.block, color: context.paleta.peligro),
                    onPressed: () async {
                      final m = await pedirTexto(context, 'Solicitar anulación de la nota N.º ${n['numero']}', minimo: 10);
                      if (m == null || !context.mounted) return;
                      await ejecutar(context, () => repo.solicitarAnulacionVenta(n['id'], m), exito: 'Anulación solicitada al gerente.');
                    },
                  ),
              ],
            ),
          ]);
        }),
      ],
    );
  }

  Future<void> _detalle(BuildContext context, Fila n) async {
    final cajero = Accion.solicitarAnulacionCobro.permitida(ref.read(perfilProvider)?.rol);
    final cobros = ((n['cobros'] as List?) ?? const []).cast<Fila>();
    final despachos = ((n['despachos'] as List?) ?? const []).cast<Fila>();
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Nota de venta N.º ${n['numero']}'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${n['pedidos']?['clientes']?['razon_social']} · ${etiqueta(n['condicion_pago'])} · ${etiqueta(n['pedidos']?['unidad_venta'])}'),
            Text('Total ${bs(n['total'])} · descuento ${bs(n['descuento'])} · saldo ${bs(n['saldo'])}'),
            const SizedBox(height: 12),
            const Text('Cobros', style: TextStyle(fontWeight: FontWeight.w700)),
            if (cobros.isEmpty) const Text('Sin cobros.'),
            for (final r in cobros)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Recibo N.º ${r['recibo']} · ${bs(r['monto'])} · ${etiqueta(r['metodo'])}'),
                subtitle: Text('${fechaHora(r['fecha_registro'])} · ${etiqueta(r['estado'])}'),
                trailing: cajero && r['estado'] == 'vigente'
                    ? TextButton(
                        onPressed: () async {
                          final m = await pedirTexto(c, 'Anular recibo N.º ${r['recibo']}', minimo: 10);
                          if (m == null || !c.mounted) return;
                          await ejecutar(c, () => ref.read(repositorioComercialProvider).solicitarAnulacionCobro(r['id'], m),
                              exito: 'Anulación del cobro solicitada al gerente.');
                        },
                        child: const Text('Pedir anulación'))
                    : null,
              ),
            const SizedBox(height: 8),
            const Text('Despachos', style: TextStyle(fontWeight: FontWeight.w700)),
            if (despachos.isEmpty) const Text('Sin despachos.'),
            for (final d in despachos) Text('${fechaHora(d['fecha_registro'])} · ${d['cantidad']} rollos · ${kg(d['peso_despachado'])}'),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar'))],
      ),
    );
  }

  Future<void> _cobrar(BuildContext context, Fila n) async {
    final m = TextEditingController(text: aNumero(n['saldo']).toStringAsFixed(2));
    String metodo = 'efectivo';
    final r = await dialogoFormulario<Fila>(
      context,
      titulo: 'Cobro de la nota N.º ${n['numero']}',
      guardar: 'Registrar cobro',
      contenido: (c, s) {
        final monto = aNumero(m.text.replaceAll(',', '.'));
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${n['pedidos']?['clientes']?['razon_social']} · saldo ${bs(n['saldo'])}'),
          const SizedBox(height: 12),
          TextField(controller: m, decoration: const InputDecoration(labelText: 'Monto (Bs)'), onChanged: (_) => s(() {}),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'efectivo', label: Text('Efectivo'), icon: Icon(Icons.payments_outlined)),
              ButtonSegment(value: 'transferencia', label: Text('Transferencia'), icon: Icon(Icons.account_balance_outlined)),
              ButtonSegment(value: 'qr', label: Text('QR'), icon: Icon(Icons.qr_code)),
            ],
            selected: {metodo},
            onSelectionChanged: (v) => s(() => metodo = v.first),
          ),
          const SizedBox(height: 12),
          if (!montoDentroDelSaldo(monto, aNumero(n['saldo']))) const Aviso('El cobro no puede superar el saldo de la nota.', tipo: 'error'),
        ]);
      },
      alGuardar: () => ejecutar(context, () => ref.read(repositorioComercialProvider).registrarCobro(n['id'], aNumero(m.text.replaceAll(',', '.')), metodo)),
    );
    if (r != null && context.mounted) {
      avisar(context, 'Recibo N.º ${r['recibo']} emitido. Saldo restante: ${bs(r['saldo'])}.');
      ref.invalidate(notasProvider);
    }
  }
}
