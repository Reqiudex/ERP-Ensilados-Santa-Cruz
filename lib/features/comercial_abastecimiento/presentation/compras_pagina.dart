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
import 'clientes_proveedores_pagina.dart';

final comprasProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(repositorioComercialProvider).compras());

const _centros = {
  '22222222-2222-2222-2222-222222222222': 'San Ramón',
  '33333333-3333-3333-3333-333333333333': 'San Julián',
  '44444444-4444-4444-4444-444444444444': 'San Rafael de Velasco',
};
const _insumos = {
  'dddddddd-dddd-dddd-dddd-dddddddddddd': 'Film estirable',
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee': 'Malla tubular',
  'ffffffff-ffff-ffff-ffff-ffffffffffff': 'Inoculante',
};

/// RF-16 Registro de compras de materia prima e insumos, y pagos del cajero.
class ComprasPagina extends ConsumerStatefulWidget {
  const ComprasPagina({super.key});
  @override
  ConsumerState<ComprasPagina> createState() => _ComprasPaginaState();
}

class _ComprasPaginaState extends ConsumerState<ComprasPagina> {
  String? _estado;

  @override
  Widget build(BuildContext context) {
    final rol = ref.watch(perfilProvider)?.rol;
    final ejecutivo = Accion.registrarCompra.permitida(rol);
    final cajero = Accion.registrarPago.permitida(rol);
    final v = ref.watch(comprasProvider);
    return Pagina(
      etiquetaRf: 'Comercial y Abastecimiento · RF-16',
      titulo: 'Compras y pagos',
      subtitulo: 'La compra de grano exige pesajes confirmados del productor y proveedor activo; la aprueba el gerente. '
          'Solo el cajero paga, solo compras aprobadas y nunca más que el saldo.',
      acciones: [
        if (ejecutivo) FilledButton.icon(onPressed: () => _nueva(context), icon: const Icon(Icons.add_shopping_cart), label: const Text('Registrar compra')),
      ],
      alRefrescar: () async => ref.invalidate(comprasProvider),
      hijos: [
        Asincrono(v, datos: (l) {
          double suma(String est) => l.where((c) => c['estado'] == est).fold(0, (a, c) => a + aNumero(c['saldo']));
          final filas = l.where((c) => _estado == null || c['estado'] == _estado).toList();
          return Column(children: [
            FilaTarjetas([
              TarjetaDato(titulo: 'Pendientes de aprobación', valor: '${l.where((c) => c['estado'] == 'pendiente').length}', icono: Icons.hourglass_top, color: context.paleta.alerta),
              TarjetaDato(titulo: 'Saldo por pagar (aprobadas)', valor: bs(suma('aprobada')), icono: Icons.payments_outlined, color: context.paleta.peligro),
              TarjetaDato(titulo: 'Compras pagadas', valor: '${l.where((c) => c['estado'] == 'pagada').length}', icono: Icons.task_alt, color: context.paleta.exito),
            ]),
            TablaDatos(
              titulo: 'Compras',
              filas: filas,
              filtros: [
                for (final e in ['pendiente', 'aprobada', 'pagada', 'anulada'])
                  FilterChip(label: Text(etiqueta(e)), selected: _estado == e, onSelected: (b) => setState(() => _estado = b ? e : null)),
              ],
              columnas: [
                Columna('Fecha', (c) => fecha(c['fecha'])),
                Columna('Proveedor', (c) => '${c['proveedores']?['razon_social'] ?? '—'}'),
                Columna('Tipo', (c) => etiqueta(c['proveedores']?['tipo'])),
                Columna('Total', (c) => bs(c['total']), numerica: true),
                Columna('Saldo', (c) => bs(c['saldo']), numerica: true),
                Columna('Registró', (c) => '${c['registrante']?['nombre_completo'] ?? 'Ejecutivo comercial'}'),
                Columna('Aprobó', (c) => c['aprobador']?['nombre_completo'] ?? (c['estado'] == 'pendiente' || c['estado'] == 'anulada' ? '—' : 'Gerente general')),
                Columna('Estado', (c) => etiqueta(c['estado']), celda: (c) => Estado(c['estado'])),
              ],
              acciones: cajero
                  ? (c) => [
                        if (c['estado'] == 'aprobada')
                          FilledButton.tonal(onPressed: () => _pagar(context, c), child: const Text('Pagar')),
                      ]
                  : null,
            ),
          ]);
        }),
      ],
    );
  }

  Future<void> _pagar(BuildContext context, Fila c) async {
    final m = TextEditingController(text: aNumero(c['saldo']).toStringAsFixed(2));
    String metodo = 'transferencia';
    await dialogoFormulario<bool>(
      context,
      titulo: 'Pago a ${c['proveedores']?['razon_social']}',
      guardar: 'Registrar pago',
      contenido: (x, s) {
        final monto = aNumero(m.text.replaceAll(',', '.'));
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Saldo pendiente: ${bs(c['saldo'])}'),
          const SizedBox(height: 12),
          TextField(controller: m, decoration: const InputDecoration(labelText: 'Monto (Bs)'), onChanged: (_) => s(() {})),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'efectivo', label: Text('Efectivo')),
              ButtonSegment(value: 'transferencia', label: Text('Transferencia')),
              ButtonSegment(value: 'qr', label: Text('QR')),
            ],
            selected: {metodo},
            onSelectionChanged: (v) => s(() => metodo = v.first),
          ),
          const SizedBox(height: 12),
          if (!montoDentroDelSaldo(monto, aNumero(c['saldo']))) const Aviso('El pago no puede superar el saldo pendiente.', tipo: 'error'),
        ]);
      },
      alGuardar: () => ejecutar(context, () async {
        final r = await ref.read(repositorioComercialProvider).registrarPago(c['id'], aNumero(m.text.replaceAll(',', '.')), metodo);
        ref.invalidate(comprasProvider);
        return r['ok'] == true;
      }, exito: 'Pago registrado.'),
    );
  }

  Future<void> _nueva(BuildContext context) async {
    final proveedores = (await ref.read(proveedoresProvider.future)).where((p) => p['estado'] == 'activo').toList();
    if (!context.mounted) return;
    String? prov;
    List<Fila> pesajes = [];
    final seleccion = <String>{};
    final precio = TextEditingController(text: '950');
    final items = <Fila>[];
    String? insumo;
    String? centro;
    final cant = TextEditingController();
    final pu = TextEditingController();
    DateTime fechaCompra = DateTime.now();
    await dialogoFormulario<bool>(
      context,
      titulo: 'Registrar compra',
      guardar: 'Registrar y enviar a aprobación',
      contenido: (c, s) {
        final tipo = proveedores.where((p) => p['id'] == prov).firstOrNull?['tipo'];
        final total = tipo == 'productor'
            ? pesajes.where((p) => seleccion.contains(p['id'])).fold<double>(0, (a, p) => a + aNumero(p['peso_ajustado']) / 1000 * aNumero(precio.text))
            : items.fold<double>(0, (a, i) => a + aNumero(i['cantidad']) * aNumero(i['precio_unitario']));
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Selector(
            etiqueta: 'Proveedor activo',
            opciones: proveedores,
            valor: prov,
            texto: (p) => '${p['razon_social']} (${etiqueta(p['tipo'])})',
            alCambiar: (v) async {
              s(() {
                prov = v;
                pesajes = [];
                seleccion.clear();
              });
              final t = proveedores.firstWhere((p) => p['id'] == v)['tipo'];
              if (t == 'productor') {
                final l = await ref.read(repositorioComercialProvider).pesajesDeProductor(v!);
                s(() => pesajes = l);
              }
            },
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text('Fecha: ${fecha(fechaCompra.toIso8601String())}'),
            onTap: () async {
              final d = await showDatePicker(context: c, firstDate: DateTime(2026), lastDate: DateTime.now(), initialDate: fechaCompra);
              if (d != null) s(() => fechaCompra = d);
            },
          ),
          if (tipo == 'productor') ...[
            TextField(controller: precio, decoration: const InputDecoration(labelText: 'Precio por tonelada ajustada (Bs)'), onChanged: (_) => s(() {})),
            const SizedBox(height: 8),
            if (pesajes.isEmpty) const Aviso('Este productor no tiene pesajes confirmados sin comprar.', tipo: 'alerta'),
            for (final p in pesajes)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: seleccion.contains(p['id']),
                onChanged: (b) => s(() => b! ? seleccion.add(p['id']) : seleccion.remove(p['id'])),
                title: Text('${p['placa']} · ${p['granos']?['nombre']} · ${kg(p['peso_ajustado'])} ajustados'),
                subtitle: Text('${fechaHora(p['fecha_dispositivo'])} · humedad ${dec1(p['humedad'])} %'),
              ),
          ],
          if (tipo == 'insumos') ...[
            Row(children: [
              Expanded(child: Selector(etiqueta: 'Insumo', validar: false, opciones: [for (final e in _insumos.entries) {'id': e.key, 'nombre': e.value}], valor: insumo, alCambiar: (v) => s(() => insumo = v))),
              const SizedBox(width: 8),
              Expanded(child: Selector(etiqueta: 'Centro', validar: false, opciones: [for (final e in _centros.entries) {'id': e.key, 'nombre': e.value}], valor: centro, alCambiar: (v) => s(() => centro = v))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: cant, decoration: const InputDecoration(labelText: 'Cantidad'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: pu, decoration: const InputDecoration(labelText: 'Precio unitario (Bs)'))),
              IconButton(
                icon: Icon(Icons.add_circle, color: context.paleta.primario),
                onPressed: () {
                  if (insumo == null || centro == null || aNumero(cant.text) <= 0 || aNumero(pu.text) <= 0) return;
                  s(() {
                    items.add({'producto_id': insumo, 'sede_id': centro, 'cantidad': aNumero(cant.text), 'precio_unitario': aNumero(pu.text.replaceAll(',', '.'))});
                    cant.clear();
                  });
                },
              ),
            ]),
            for (final i in items)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${_insumos[i['producto_id']]} · ${_centros[i['sede_id']]} · ${dec2(i['cantidad'])} × ${bs(i['precio_unitario'])}'),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => s(() => items.remove(i))),
              ),
          ],
          const SizedBox(height: 8),
          Text('Total estimado: ${bs(total)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ]);
      },
      alGuardar: () async {
        final tipo = proveedores.where((p) => p['id'] == prov).firstOrNull?['tipo'];
        if (prov == null) return null;
        final lista = tipo == 'productor'
            ? [for (final id in seleccion) {'pesaje_id': id, 'precio_unitario': aNumero(precio.text.replaceAll(',', '.'))}]
            : items;
        final r = await ejecutar(context, () => ref.read(repositorioComercialProvider).registrarCompra(prov!, fechaCompra, lista));
        if (r == null) return null;
        if (context.mounted) avisar(context, 'Compra de ${bs(r['total'])} registrada: queda pendiente de aprobación del gerente.');
        ref.invalidate(comprasProvider);
        return true;
      },
    );
  }
}
