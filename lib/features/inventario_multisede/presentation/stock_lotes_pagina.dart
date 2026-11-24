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

final lotesProvider = FutureProvider.autoDispose<List<Fila>>((ref) async {
  ref.watch(pendientesSincronizarProvider);
  final repo = ref.watch(repositorioInventarioProvider);
  return consultarConCopiaLocal(ref, 'lotes_stock', remoto: () => repo.lotes(), local: filasDeCopia);
});

double _total(Fila l, String campo, {String? sede}) => ((l['existencias'] as List?) ?? const [])
    .where((e) => sede == null || e['sede_id'] == sede)
    .fold<double>(0, (a, e) => a + aNumero(e[campo]));

/// RF-11 Stock por lotes y trazabilidad (incluye solicitudes de merma y ajuste por conteo).
class StockLotesPagina extends ConsumerStatefulWidget {
  const StockLotesPagina({super.key});
  @override
  ConsumerState<StockLotesPagina> createState() => _StockLotesPaginaState();
}

class _StockLotesPaginaState extends ConsumerState<StockLotesPagina> {
  bool _conStock = true;

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(perfilProvider)!;
    final operador = Accion.solicitarMerma.permitida(perfil.rol);
    final v = ref.watch(lotesProvider);
    final sede = operador ? perfil.sedeId : null;
    return Pagina(
      etiquetaRf: 'Inventario y Logística · RF-11',
      titulo: 'Stock por lote y trazabilidad',
      subtitulo: 'El stock no se edita a mano: cambia solo por movimientos con documento de origen. Toque un lote para ver su recorrido.',
      acciones: [
        FilterChip(label: const Text('Solo con stock'), selected: _conStock, onSelected: (b) => setState(() => _conStock = b)),
      ],
      alRefrescar: () async => ref.invalidate(lotesProvider),
      hijos: [
        if (operador) const Aviso('Las bajas (mermas) y los ajustes por conteo se solicitan aquí y los aprueba el gerente; el stock cambia solo tras la aprobación.'),
        Asincrono(v,
            alReintentar: () => ref.invalidate(lotesProvider),
            datos: (l) {
              final filas = l.where((x) => !_conStock || _total(x, 'disponible', sede: sede) + _total(x, 'reservado', sede: sede) + _total(x, 'en_transito', sede: sede) > 0).toList();
              return TablaDatos(
                titulo: 'Lotes',
                filas: filas,
                alTocar: (x) => _traza(context, x),
                columnas: [
                  Columna('Lote', (x) => '${x['codigo']}'),
                  Columna('Producto', (x) => '${x['productos']?['granos']?['nombre'] ?? x['productos']?['nombre']}'),
                  if (!operador) Columna('Centro de origen', (x) => '${x['sedes']?['nombre'] ?? ''}'),
                  Columna('Sellado', (x) => fecha(x['fecha_sellado'])),
                  Columna('Producidos', (x) => '${x['rollos_producidos']}', numerica: true),
                  Columna('Disponible', (x) => entero(_total(x, 'disponible', sede: sede)), numerica: true),
                  Columna('Reservado', (x) => entero(_total(x, 'reservado', sede: sede)), numerica: true),
                  Columna('En tránsito', (x) => entero(_total(x, 'en_transito', sede: sede)), numerica: true),
                  Columna('Estado', (x) => etiqueta(x['estado']), celda: (x) => Estado(x['estado'])),
                ],
                acciones: operador
                    ? (x) => [
                          if (_total(x, 'disponible', sede: sede) > 0)
                            PopupMenuButton<String>(
                              tooltip: 'Solicitar',
                              onSelected: (o) => o == 'merma' ? _merma(context, x, sede) : _ajuste(context, x, sede),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'merma', child: Text('Solicitar baja (merma)')),
                                PopupMenuItem(value: 'ajuste', child: Text('Solicitar ajuste por conteo')),
                              ],
                            ),
                        ]
                    : null,
              );
            }),
      ],
    );
  }

  Future<void> _merma(BuildContext context, Fila x, String? sede) async {
    final cant = TextEditingController();
    final desc = TextEditingController();
    String causa = 'film_roto';
    await dialogoFormulario<bool>(
      context,
      titulo: 'Solicitar baja · lote ${x['codigo']}',
      guardar: 'Enviar al gerente',
      contenido: (c, s) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Disponible en su centro: ${entero(_total(x, 'disponible', sede: sede))} rollos'),
        const SizedBox(height: 12),
        TextField(controller: cant, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rollos a dar de baja')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: causa,
          decoration: const InputDecoration(labelText: 'Causa'),
          items: [for (final k in ['film_roto', 'fermentacion', 'manipuleo', 'traslado', 'conteo']) DropdownMenuItem(value: k, child: Text(etiqueta(k)))],
          onChanged: (v) => causa = v ?? causa,
        ),
        const SizedBox(height: 12),
        TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Descripción (obligatoria)')),
      ]),
      alGuardar: () => ejecutar(context, () async {
        final n = int.tryParse(cant.text) ?? 0;
        if (!ref.read(enLineaProvider)) {
          await ref.read(colaProvider.notifier).registrar('solicitar_merma', {
            'lote_id': x['id'],
            'cantidad': n,
            'causa': causa,
            'descripcion': desc.text.trim(),
          });
          return true;
        }
        try {
          await ref.read(repositorioInventarioProvider).solicitarMerma(x['id'], n, causa, desc.text);
        } on ErrorNegocio catch (e) {
          if (e.codigo != 'red') rethrow;
          await ref.read(colaProvider.notifier).registrar('solicitar_merma', {
            'lote_id': x['id'],
            'cantidad': n,
            'causa': causa,
            'descripcion': desc.text.trim(),
          });
        }
        return true;
      }, exito: ref.read(enLineaProvider)
          ? 'Baja solicitada: el stock no cambia hasta que el gerente la apruebe.'
          : 'Solicitud de baja guardada en el teléfono: se enviará al recuperar la señal.'),
    );
  }

  Future<void> _ajuste(BuildContext context, Fila x, String? sede) async {
    final cant = TextEditingController();
    final desc = TextEditingController();
    await dialogoFormulario<bool>(
      context,
      titulo: 'Ajuste por conteo · lote ${x['codigo']}',
      guardar: 'Enviar al gerente',
      contenido: (c, s) => Column(mainAxisSize: MainAxisSize.min, children: [
        const Aviso('Escriba la diferencia contada: positiva si hay más rollos, negativa si faltan.'),
        TextField(controller: cant, keyboardType: const TextInputType.numberWithOptions(signed: true), decoration: const InputDecoration(labelText: 'Diferencia (rollos)')),
        const SizedBox(height: 12),
        TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'Descripción del conteo')),
      ]),
      alGuardar: () => ejecutar(context, () async {
        String? prod = (x['producto_id'] as String?) ?? (x['productos'] is Map ? (x['productos'] as Map)['id'] as String? : null);
        if (prod == null && ref.read(enLineaProvider)) {
          try {
            prod = (await ref.read(apiProvider).consultar('lotes', 'producto_id', igual: {'id': x['id']})).first['producto_id'] as String;
          } catch (_) {}
        }
        prod ??= 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
        if (!ref.read(enLineaProvider)) {
          await ref.read(colaProvider.notifier).registrar('solicitar_ajuste', {
            'producto_id': prod,
            'lote_id': x['id'],
            'cantidad': aNumero(cant.text),
            'descripcion': desc.text.trim(),
          });
          return true;
        }
        try {
          await ref.read(repositorioInventarioProvider).solicitarAjuste(prod, x['id'], aNumero(cant.text), desc.text);
        } on ErrorNegocio catch (e) {
          if (e.codigo != 'red') rethrow;
          await ref.read(colaProvider.notifier).registrar('solicitar_ajuste', {
            'producto_id': prod,
            'lote_id': x['id'],
            'cantidad': aNumero(cant.text),
            'descripcion': desc.text.trim(),
          });
        }
        return true;
      }, exito: ref.read(enLineaProvider)
          ? 'Ajuste solicitado al gerente.'
          : 'Ajuste guardado en el teléfono: se enviará al recuperar la señal.'),
    );
  }

  Future<void> _traza(BuildContext context, Fila x) async {
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Trazabilidad del lote ${x['codigo']}'),
        content: SizedBox(
          width: 640,
          child: FutureBuilder<Fila>(
            future: ref.read(repositorioInventarioProvider).trazabilidad(x['id']).catchError((_) => <String, dynamic>{
                  'lote': x,
                  'movimientos': const <Fila>[],
                  'revisiones': const <Fila>[],
                }),
            builder: (c, s) {
              if (!s.hasData) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
              final d = s.data!;
              final lote = d['lote'] as Fila? ?? {};
              final orden = lote['ordenes_ensilado'] as Fila?;
              final pesajes = ((orden?['pesajes'] as List?) ?? const []).cast<Fila>();
              final movs = ((d['movimientos'] as List?) ?? const []).cast<Fila>();
              final revs = ((d['revisiones'] as List?) ?? const []).cast<Fila>();
              Widget paso(IconData i, String t, String sub) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(backgroundColor: Colores.primarioClaro, child: Icon(i, color: Colores.primario, size: 20)),
                    title: Text(t),
                    subtitle: Text(sub),
                  );
              return SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${lote['productos']?['nombre']} · ${lote['sedes']?['nombre']} · ${lote['rollos_producidos']} rollos de ${kg(lote['peso_promedio_rollo'])} promedio'),
                  const SizedBox(height: 12),
                  for (final p in pesajes)
                    paso(Icons.scale, 'Pesaje ${p['placa']} (${etiqueta(p['origen'])})',
                        '${fechaHora(p['fecha_dispositivo'])} · neto ${kg(p['peso_neto'])} · humedad ${dec1(p['humedad'])} % · ajustado ${kg(p['peso_ajustado'])} · ${etiqueta(p['estado'])}'),
                  if (orden != null)
                    paso(Icons.precision_manufacturing, 'Orden de ensilado', 'Abierta ${fechaHora(orden['fecha_apertura'])} · cerrada ${fechaHora(orden['fecha_cierre'])}'),
                  for (final r in revs) paso(Icons.thermostat, 'Revisión: film ${etiqueta(r['estado_film'])}', '${fechaHora(r['fecha_registro'])} · ${r['observacion'] ?? ''}'),
                  for (final m in movs)
                    paso(
                        switch (m['tipo']) {
                          'ingreso' => Icons.add_box_outlined,
                          'salida' => Icons.fire_truck_outlined,
                          'envio' || 'recepcion' => Icons.local_shipping_outlined,
                          'merma' => Icons.remove_circle_outline,
                          _ => Icons.swap_horiz,
                        },
                        '${etiqueta(m['tipo']) == m['tipo'] ? '${m['tipo']}'.toUpperCase() : etiqueta(m['tipo'])} · ${m['cantidad']} rollos',
                        '${fechaHora(m['fecha_registro'])} · ${m['sedes']?['nombre'] ?? ''} · documento: ${m['documento_tipo']}'),
                ]),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar'))],
      ),
    );
  }
}
