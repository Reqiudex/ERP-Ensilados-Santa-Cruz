import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../data/repositorio_comercial_supabase.dart';
import '../domain/calculos_comerciales.dart';

final despachosPendientesProvider = FutureProvider.autoDispose<List<Fila>>((ref) async {
  ref.watch(pendientesSincronizarProvider);
  final enLinea = ref.watch(enLineaProvider);
  final cache = ref.watch(datosOperadorProvider.select((m) => m['despachos_pendientes']));
  List<Fila> locales() =>
      ((cache as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  if (!enLinea) return locales();
  try {
    final l = await ref.watch(repositorioComercialProvider).despachosPendientes();
    ref.read(datosOperadorProvider.notifier).guardarClave('despachos_pendientes', l);
    return l;
  } catch (_) {
    return locales();
  }
});

final despachosProvider = FutureProvider.autoDispose<List<Fila>>((ref) async {
  ref.watch(pendientesSincronizarProvider);
  final enLinea = ref.watch(enLineaProvider);
  final cache = ref.watch(datosOperadorProvider.select((m) => m['despachos']));
  List<Fila> locales() =>
      ((cache as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  if (!enLinea) return locales();
  try {
    final l = await ref.watch(repositorioComercialProvider).despachos();
    ref.read(datosOperadorProvider.notifier).guardarClave('despachos', l);
    return l;
  } catch (_) {
    return locales();
  }
});

/// RF-19 Control de despachos: cada rollo se pesa; en ventas por tonelada se controla la tolerancia del 5 %.
class DespachosPagina extends ConsumerWidget {
  const DespachosPagina({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider)!;
    final operador = Accion.registrarDespacho.permitida(perfil.rol);
    final enLinea = ref.watch(enLineaProvider);
    return Pagina(
      etiquetaRf: 'Comercial y Abastecimiento · RF-19',
      titulo: 'Despachos',
      subtitulo: 'El despacho exige una nota de venta emitida por el ejecutivo. Si el peso supera el ${dec1(perfil.toleranciaDespacho)} % '
          'sobre lo vendido por tonelada, queda pendiente del gerente.',
      alRefrescar: () async {
        ref.invalidate(despachosPendientesProvider);
        ref.invalidate(despachosProvider);
      },
      hijos: [
        if (operador && !enLinea)
          const Aviso('Sin conexión: los despachos sobre notas descargadas se guardan en el teléfono y se sincronizan al recuperar la señal.', tipo: 'alerta'),
        if (operador || perfil.rol.comoGerente)
          Asincrono(ref.watch(despachosPendientesProvider), datos: (l) {
            if (l.isEmpty) return const MensajeVacio(titulo: 'No hay notas de venta por despachar en su centro.', icono: Icons.fire_truck_outlined);
            return Wrap(spacing: 12, runSpacing: 12, children: [
              for (final d in l)
                SizedBox(
                  width: esAncho(context) ? 380 : double.infinity,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('Nota N.º ${d['numero']} · ${d['cliente']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                          if (d['pendiente_aprobacion'] == true) const Estado('pendiente'),
                        ]),
                        const SizedBox(height: 4),
                        Text('${d['producto']} · lote ${d['lote']}', style: const TextStyle(color: Colores.textoSuave)),
                        const SizedBox(height: 8),
                        Text(d['unidad'] == 'tonelada'
                            ? '${dec2(d['cantidad'])} t vendidas · ${d['rollos']} rollos'
                            : '${d['rollos']} rollos vendidos'),
                        Text('Despachados: ${d['despachados']} · reservados en su centro: ${entero(d['reservado_sede'])}'),
                        const SizedBox(height: 12),
                        if (operador)
                          FilledButton.icon(
                            onPressed: d['pendiente_aprobacion'] != true && aNumero(d['reservado_sede']) > 0 ? () => _despachar(context, ref, d) : null,
                            icon: const Icon(Icons.scale),
                            label: const Text('Pesar rollos y despachar'),
                          ),
                      ]),
                    ),
                  ),
                ),
            ]);
          }),
        const SizedBox(height: 20),
        Asincrono(ref.watch(despachosProvider),
            datos: (l) => TablaDatos(
                  titulo: 'Despachos registrados',
                  filas: l,
                  columnas: [
                    Columna('Fecha', (d) => fechaHora(d['fecha_registro'])),
                    Columna('Nota', (d) => '${d['notas_venta']?['numero'] ?? '—'}'),
                    Columna('Centro', (d) => '${d['sedes']?['nombre'] ?? '—'}'),
                    Columna('Lote', (d) => '${d['lotes']?['codigo'] ?? '—'}'),
                    Columna('Rollos', (d) => '${d['cantidad']}', numerica: true),
                    Columna('Vendido', (d) => kg(d['peso_vendido']), numerica: true),
                    Columna('Despachado', (d) => kg(d['peso_despachado']), numerica: true),
                    Columna('Diferencia', (d) {
                      final v = aNumero(d['peso_vendido']);
                      return v == 0 ? '—' : '${dec1((aNumero(d['peso_despachado']) - v) / v * 100)} %';
                    }, numerica: true),
                    Columna('Báscula pública', (d) => d['peso_bascula_publica'] == null ? '—' : kg(d['peso_bascula_publica']), numerica: true),
                    Columna('Placa', (d) => '${d['placa']}'),
                    Columna('Receptor', (d) => '${d['receptor']}'),
                  ],
                  acciones: (d) => [
                    if (d['peso_bascula_publica'] == null && (operador || perfil.rol == Rol.ejecutivoComercial || perfil.rol == Rol.superadmin))
                      TextButton(
                        onPressed: () async {
                          final t = await pedirTexto(context, 'Peso reportado por el cliente (báscula pública)', etiqueta: 'Peso en kg', minimo: 2);
                          if (t == null || !context.mounted) return;
                          final pKg = aNumero(t.replaceAll(',', '.'));
                          await ejecutar(context, () async {
                            if (!ref.read(enLineaProvider)) {
                              await ref.read(colaProvider.notifier).registrar('registrar_peso_bascula', {'despacho_id': d['id'], 'peso': pKg});
                              return {'ok': true};
                            }
                            try {
                              return await ref.read(repositorioComercialProvider).registrarPesoBascula(d['id'], pKg);
                            } on ErrorNegocio catch (e) {
                              if (e.codigo != 'red') rethrow;
                              await ref.read(colaProvider.notifier).registrar('registrar_peso_bascula', {'despacho_id': d['id'], 'peso': pKg});
                              return {'ok': true};
                            }
                          }, exito: ref.read(enLineaProvider) ? 'Peso de báscula pública anotado.' : 'Peso guardado en el teléfono: se enviará al recuperar la señal.');
                          ref.invalidate(despachosProvider);
                        },
                        child: const Text('Báscula pública'),
                      ),
                  ],
                )),
      ],
    );
  }

  Future<void> _despachar(BuildContext context, WidgetRef ref, Fila d) async {
    final perfil = ref.read(perfilProvider)!;
    final pendientes = (d['rollos'] as num).toInt() - (d['despachados'] as num).toInt();
    final maxRollos = pendientes < aNumero(d['reservado_sede']) ? pendientes : aNumero(d['reservado_sede']).toInt();
    final pesos = <double>[];
    final peso = TextEditingController();
    final placa = TextEditingController();
    final receptor = TextEditingController();
    final bascula = TextEditingController();
    final foco = FocusNode();
    final porTonelada = d['unidad'] == 'tonelada';
    final r = await dialogoFormulario<Fila>(
      context,
      titulo: 'Despacho · nota N.º ${d['numero']}',
      guardar: 'Registrar despacho',
      contenido: (c, s) {
        final total = pesos.fold<double>(0, (a, x) => a + x);
        final vendidoKg = porTonelada
            ? aNumero(d['cantidad']) * 1000 * pesos.length / (d['rollos'] as num)
            : pesos.length * aNumero(d['peso_promedio']);
        final minimo = pesoMinimoDespacho(vendidoKg, toleranciaPct: perfil.toleranciaDespacho);
        final exceso = porTonelada && despachoRequiereAprobacion(total, vendidoKg, toleranciaPct: perfil.toleranciaDespacho);
        void agregar() {
          final v = double.tryParse(peso.text.replaceAll(',', '.'));
          if (v == null || v <= 0 || pesos.length >= maxRollos) return;
          s(() {
            pesos.add(v);
            peso.clear();
          });
          foco.requestFocus();
        }

        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${d['cliente']} · lote ${d['lote']} · hasta $maxRollos rollos'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: peso,
                focusNode: foco,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                decoration: InputDecoration(labelText: 'Peso del rollo ${pesos.length + 1} (kg)'),
                // Enter agrega el rollo y deja el cursor en el campo para pesar el siguiente.
                onEditingComplete: agregar,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
                height: 56,
                child: Tooltip(message: 'Agregar rollo', child: FilledButton(onPressed: agregar, child: const Icon(Icons.add)))),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var i = 0; i < pesos.length; i++)
              InputChip(label: Text('${i + 1}: ${dec1(pesos[i])}'), onDeleted: () => s(() => pesos.removeAt(i))),
          ]),
          const SizedBox(height: 12),
          Card(
            color: (exceso ? Colores.peligro : Colores.exito).withValues(alpha: .08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${pesos.length} rollos · ${kg(total)} despachados', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                if (pesos.isNotEmpty) ...[
                  Text('Vendido: ${kg(vendidoKg)}${porTonelada ? ' · con ${dec1(perfil.toleranciaDespacho)} %: ${kg(minimo)}' : ''}'),
                  if (porTonelada && vendidoKg > 0) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: (total / minimo).clamp(0, 1.2) / 1.2,
                        color: exceso ? Colores.peligro : Colores.exito,
                        backgroundColor: Colores.borde,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(exceso
                        ? 'Supera el ${dec1(perfil.toleranciaDespacho)} %: el despacho quedará pendiente de aprobación del gerente.'
                        : 'Dentro de la tolerancia.'),
                  ],
                ],
              ]),
            ),
          ),
          const SizedBox(height: 12),
          TextField(controller: placa, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Placa del vehículo')),
          const SizedBox(height: 10),
          TextField(controller: receptor, decoration: const InputDecoration(labelText: 'Quién recibe')),
          const SizedBox(height: 10),
          TextField(controller: bascula, decoration: const InputDecoration(labelText: 'Peso en báscula pública (opcional, kg)')),
        ]);
      },
      alGuardar: () => ejecutar(context, () async {
        final pBascula = bascula.text.trim().isEmpty ? null : aNumero(bascula.text.replaceAll(',', '.'));
        final totalKg = pesos.fold<double>(0, (a, x) => a + x);
        final vendidoKg = porTonelada
            ? aNumero(d['cantidad']) * 1000 * pesos.length / (d['rollos'] as num)
            : pesos.length * aNumero(d['peso_promedio']);
        Future<Fila> encolarLocal() async {
          await ref.read(colaProvider.notifier).registrar('registrar_despacho', {
            'nota_id': d['nota_id'],
            'numero_nota': d['numero'],
            'lote_id': d['lote_id'],
            'codigo_lote': d['lote'],
            'pesos': pesos,
            'peso_vendido': vendidoKg,
            'placa': placa.text.trim().toUpperCase(),
            'receptor': receptor.text.trim(),
            'peso_bascula': pBascula,
          });
          return {'estado': 'offline', 'peso_despachado': totalKg};
        }

        if (!ref.read(enLineaProvider)) return await encolarLocal();
        try {
          return await ref.read(repositorioComercialProvider).registrarDespacho(
              d['nota_id'], d['lote_id'], pesos, placa.text.trim(), receptor.text.trim(), pBascula);
        } on ErrorNegocio catch (e) {
          if (e.codigo != 'red') rethrow;
          return await encolarLocal();
        }
      }),
    );
    if (r != null && context.mounted) {
      avisar(
          context,
          r['estado'] == 'offline'
              ? 'Despacho de ${kg(r['peso_despachado'])} guardado en el teléfono: se enviará al recuperar la señal.'
              : r['estado'] == 'pendiente'
                  ? 'Despacho de ${kg(r['peso_despachado'])} enviado al gerente: supera la tolerancia.'
                  : 'Despacho registrado: ${kg(r['peso_despachado'])}.');
      ref.invalidate(despachosPendientesProvider);
      ref.invalidate(despachosProvider);
    }
  }
}
