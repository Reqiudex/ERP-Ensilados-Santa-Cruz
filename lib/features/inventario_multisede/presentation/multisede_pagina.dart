import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/conexion/conexion.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../../operaciones_ensilado/data/cola_sincronizacion.dart';
import '../data/repositorio_inventario_supabase.dart';

class FotoStock {
  const FotoStock(this.filas, this.hora, this.eventos);
  final List<Fila> filas;
  final DateTime hora;
  final int eventos;
}

/// Stock por sede en tiempo real con respaldo local sin conexión en SQLite.
final stockEnVivoProvider = StreamProvider.autoDispose<FotoStock>((ref) async* {
  final repo = ref.watch(repositorioInventarioProvider);
  final enLinea = ref.watch(enLineaProvider);
  if (!enLinea) {
    // Sin señal se observa la copia local del teléfono.
    yield FotoStock(filasDeCopia(ref.watch(datosOperadorProvider.select((m) => m['existencias']))), DateTime.now(), 0);
    return;
  }
  // Con señal la copia solo se escribe (observarla aquí reiniciaba el flujo en vivo sin fin).
  List<Fila> locales() {
    try {
      return filasDeCopia(ref.read(datosOperadorProvider)['existencias']);
    } catch (_) {
      return const <Fila>[];
    }
  }

  void guardar(List<Fila> l) {
    try {
      ref.read(datosOperadorProvider.notifier).guardarClave('existencias', l);
    } catch (_) {}
  }

  var eventos = 0;
  try {
    final inicial = await repo.existencias();
    guardar(inicial);
    yield FotoStock(inicial, DateTime.now(), eventos);
  } catch (_) {
    yield FotoStock(locales(), DateTime.now(), eventos);
    return;
  }

  try {
    await for (final _ in repo.existenciasEnVivo()) {
      eventos++;
      try {
        final act = await repo.existencias();
        guardar(act);
        yield FotoStock(act, DateTime.now(), eventos);
      } catch (_) {}
    }
  } catch (_) {}
});

/// RF-12 Gestión multisede.
class MultisedePagina extends ConsumerWidget {
  const MultisedePagina({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(stockEnVivoProvider);
    return Pagina(
      etiquetaRf: 'Inventario y Logística · RF-12',
      titulo: 'Inventario por sede',
      subtitulo: 'Rollos disponibles, reservados y en tránsito por centro de acopio. Se actualiza solo cuando otra sede registra un movimiento.',
      hijos: [
        Asincrono(v, alReintentar: () => ref.invalidate(stockEnVivoProvider), datos: (foto) {
          final rollos = foto.filas.where((f) => f['tipo'] == 'rollo').toList();
          final sedes = <String>{for (final f in rollos) '${f['sede']}'}.toList()..sort();
          double suma(Iterable<Fila> l, String c) => l.fold(0, (a, f) => a + aNumero(f[c]));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.wifi_tethering, color: Colores.exito, size: 18),
              const SizedBox(width: 6),
              Text('En vivo · última actualización ${fechaHora(foto.hora.toIso8601String())}'
                  '${foto.eventos > 0 ? ' · ${foto.eventos} cambios recibidos' : ''}',
                  style: const TextStyle(color: Colores.textoSuave)),
            ]),
            const SizedBox(height: 16),
            FilaTarjetas([
              TarjetaDato(titulo: 'Disponible', valor: entero(suma(rollos, 'disponible')), icono: Icons.inventory_2_outlined, detalle: 'rollos'),
              TarjetaDato(titulo: 'Reservado', valor: entero(suma(rollos, 'reservado')), icono: Icons.bookmark_added_outlined, color: Colores.info, detalle: 'rollos para pedidos'),
              TarjetaDato(titulo: 'En tránsito', valor: entero(suma(rollos, 'en_transito')), icono: Icons.local_shipping_outlined, color: Colores.ambarOscuro, detalle: 'rollos en guías'),
              TarjetaDato(titulo: 'Toneladas disponibles', valor: dec2(suma(rollos, 'toneladas')), icono: Icons.scale_outlined, color: Colores.exito),
            ]),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final s in sedes)
                SizedBox(
                  width: esAncho(context) ? 360 : double.infinity,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 10),
                        for (final prod in <String>{for (final f in rollos.where((f) => f['sede'] == s)) '${f['producto']}'})
                          Builder(builder: (_) {
                            final l = rollos.where((f) => f['sede'] == s && f['producto'] == prod);
                            final aptos = suma(l.where((f) => f['estado_lote'] == 'apto'), 'disponible');
                            final ferm = suma(l.where((f) => f['estado_lote'] == 'fermentacion'), 'disponible');
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(prod, style: const TextStyle(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Wrap(spacing: 6, runSpacing: 4, children: [
                                  _Mini('Aptos', aptos, Colores.exito),
                                  _Mini('Fermentando', ferm, Colores.alerta),
                                  _Mini('Reservados', suma(l, 'reservado'), Colores.info),
                                  _Mini('En tránsito', suma(l, 'en_transito'), Colores.ambarOscuro),
                                ]),
                              ]),
                            );
                          }),
                      ]),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 20),
            TablaDatos(
              titulo: 'Detalle por sede, lote e insumo',
              filas: foto.filas,
              columnas: [
                Columna('Sede', (f) => '${f['sede']}'),
                Columna('Producto', (f) => '${f['producto']}'),
                Columna('Lote', (f) => '${f['lote'] ?? '—'}'),
                Columna('Estado', (f) => etiqueta(f['estado_lote'] ?? 'insumo'), celda: (f) => f['estado_lote'] == null ? const Text('Insumo') : Estado(f['estado_lote'])),
                Columna('Disponible', (f) => entero(f['disponible']), numerica: true),
                Columna('Reservado', (f) => entero(f['reservado']), numerica: true),
                Columna('En tránsito', (f) => entero(f['en_transito']), numerica: true),
              ],
            ),
          ]);
        }),
      ],
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.t, this.v, this.c);
  final String t;
  final double v;
  final Color c;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: .1), borderRadius: BorderRadius.circular(8)),
        child: Text('$t: ${entero(v)}', style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
      );
}
