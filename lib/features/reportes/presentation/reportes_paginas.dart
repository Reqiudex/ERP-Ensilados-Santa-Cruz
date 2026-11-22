import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/conexion/conexion.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../../operaciones_ensilado/data/cola_sincronizacion.dart';
import '../../seguridad_accesos/domain/roles_y_permisos.dart';
import '../../seguridad_accesos/presentation/sesion.dart';
import '../data/repositorio_reportes_supabase.dart';
import '../domain/calculos_reportes.dart';

typedef Periodo = ({DateTime desde, DateTime hasta});

/// Inicio de los datos del sistema (primera campaña registrada).
final inicioDatos = DateTime(2026, 8, 1);

DateTime _hoy() {
  final a = DateTime.now();
  return DateTime(a.year, a.month, a.day);
}

Periodo periodoInicial() => (desde: inicioDatos, hasta: _hoy());

bool _mismoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

const _meses = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];

/// Atajos: todo el período con datos y los últimos cuatro meses (el actual, hasta hoy), calculados desde la fecha actual.
List<(String, Periodo)> opcionesPeriodo() {
  final hoy = _hoy();
  final l = <(String, Periodo)>[('Todo', periodoInicial())];
  for (var i = 3; i >= 0; i--) {
    final ini = DateTime(hoy.year, hoy.month - i, 1);
    if (ini.isBefore(DateTime(inicioDatos.year, inicioDatos.month, 1))) continue;
    final fin = DateTime(ini.year, ini.month + 1, 0);
    l.add((_meses[ini.month - 1], (desde: ini, hasta: fin.isAfter(hoy) ? hoy : fin)));
  }
  return l;
}

/// Barra de período con selector de fechas.
class _BarraPeriodo extends StatelessWidget {
  const _BarraPeriodo(this.p, this.alCambiar, {this.extra = const []});
  final Periodo p;
  final ValueChanged<Periodo> alCambiar;
  final List<Widget> extra;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text('${fecha(p.desde.toIso8601String())} – ${fecha(p.hasta.toIso8601String())}'),
            onPressed: () async {
              final r = await showDateRangePicker(
                  context: context, firstDate: inicioDatos, lastDate: _hoy(), initialDateRange: DateTimeRange(start: p.desde, end: p.hasta));
              if (r != null) alCambiar((desde: r.start, hasta: r.end));
            },
          ),
          for (final o in opcionesPeriodo())
            ChoiceChip(
              label: Text(o.$1),
              selected: _mismoDia(p.desde, o.$2.desde) && _mismoDia(p.hasta, o.$2.hasta),
              onSelected: (_) => alCambiar(o.$2),
            ),
          ...extra,
        ]),
      );
}

/// Barras horizontales simples para los reportes.
class Barras extends StatelessWidget {
  const Barras(this.datos, {super.key, this.formato, this.color = Colores.primario, this.marcas = const {}});
  final Map<String, double> datos;
  final String Function(double)? formato;
  final Color color;
  final Map<String, Color> marcas;
  @override
  Widget build(BuildContext context) {
    final max = datos.values.fold<double>(0, (a, b) => b > a ? b : a);
    return Column(children: [
      for (final e in datos.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            // «Centro de Acopio» se omite en la etiqueta para que el nombre de la sede quepa en pantallas angostas.
            SizedBox(
                width: 170,
                child: Tooltip(
                    message: e.key,
                    child: Text(e.key.replaceFirst('Centro de Acopio ', ''), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))),
            Expanded(
              child: LayoutBuilder(
                builder: (c, k) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 18,
                    width: max == 0 ? 0 : k.maxWidth * (e.value / max),
                    decoration: BoxDecoration(color: marcas[e.key] ?? color, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
            ),
            SizedBox(width: 110, child: Text(formato?.call(e.value) ?? dec2(e.value), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
    ]);
  }
}

// ------------------------------------------------------------------------------------------------
// RF-20 Rendimiento y producción de ensilado
// ------------------------------------------------------------------------------------------------
final _rendimientoProvider = FutureProvider.autoDispose.family<List<Fila>, Periodo>((ref, p) async {
  final enLinea = ref.watch(enLineaProvider);
  final cache = ref.watch(datosOperadorProvider.select((m) => m['reporte_rendimiento']));
  List<Fila> locales() =>
      ((cache as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  if (!enLinea) return locales();
  try {
    final l = await ref.watch(repositorioReportesProvider).rendimiento(p.desde, p.hasta);
    ref.read(datosOperadorProvider.notifier).guardarClave('reporte_rendimiento', l);
    return l;
  } catch (_) {
    return locales();
  }
});

class ReporteRendimientoPagina extends ConsumerStatefulWidget {
  const ReporteRendimientoPagina({super.key});
  @override
  ConsumerState<ReporteRendimientoPagina> createState() => _ReporteRendimientoPaginaState();
}

class _ReporteRendimientoPaginaState extends ConsumerState<ReporteRendimientoPagina> {
  Periodo _p = periodoInicial();
  @override
  Widget build(BuildContext context) {
    final v = ref.watch(_rendimientoProvider(_p));
    return Pagina(
      etiquetaRf: 'Reportes · RF-20',
      titulo: 'Rendimiento del ensilado',
      subtitulo: 'Rollos por tonelada de grano ajustado. La alerta marca lotes fuera del rango normal del grano (control compensatorio).',
      hijos: [
        _BarraPeriodo(_p, (x) => setState(() => _p = x)),
        Asincrono(v, datos: (l) {
          final rollos = l.fold<int>(0, (a, x) => a + (x['rollos_producidos'] as num).toInt());
          final t = l.fold<double>(0, (a, x) => a + aNumero(x['toneladas_grano_ajustadas']));
          final alertas = l.where((x) => '${x['dictamen_rendimiento']}'.startsWith('Alerta')).length;
          final porSede = <String, double>{};
          final tonSede = <String, double>{};
          for (final x in l) {
            porSede[x['sede']] = (porSede[x['sede']] ?? 0) + aNumero(x['rollos_producidos']);
            tonSede[x['sede']] = (tonSede[x['sede']] ?? 0) + aNumero(x['toneladas_grano_ajustadas']);
          }
          return Column(children: [
            FilaTarjetas([
              TarjetaDato(titulo: 'Lotes sellados', valor: '${l.length}', icono: Icons.qr_code_2),
              TarjetaDato(titulo: 'Rollos producidos', valor: entero(rollos), icono: Icons.inventory_2_outlined),
              TarjetaDato(titulo: 'Grano ajustado', valor: toneladas(t), icono: Icons.scale_outlined, color: Colores.ambarOscuro),
              TarjetaDato(titulo: 'Rendimiento global', valor: '${dec2(rendimientoRollosPorTonelada(rollos, t))} r/t', icono: Icons.trending_up, color: Colores.info),
              TarjetaDato(titulo: 'Alertas', valor: '$alertas', icono: Icons.warning_amber_rounded, color: alertas > 0 ? Colores.peligro : Colores.exito),
            ]),
            Seccion(
              titulo: 'Rendimiento por centro (rollos por tonelada)',
              icono: Icons.bar_chart,
              hijo: Barras({for (final k in porSede.keys) k: rendimientoRollosPorTonelada(porSede[k]!.round(), tonSede[k]!)}),
            ),
            TablaDatos(
              titulo: 'Rendimiento por lote',
              filas: l,
              resumen: ['Rollos: ${entero(rollos)}', 'Toneladas: ${dec2(t)}', 'Alertas: $alertas'],
              columnas: [
                Columna('Lote', (x) => '${x['codigo_lote']}'),
                Columna('Centro', (x) => '${x['sede']}'),
                Columna('Grano', (x) => '${x['grano']}'),
                Columna('Sellado', (x) => fecha(x['fecha_sellado'])),
                Columna('Toneladas', (x) => dec2(x['toneladas_grano_ajustadas']), numerica: true),
                Columna('Rollos', (x) => '${x['rollos_producidos']}', numerica: true),
                Columna('Rollos/t', (x) => dec2(x['rollos_por_tonelada']), numerica: true),
                Columna('Rango normal', (x) => '${dec2(x['rollos_ton_min'])} a ${dec2(x['rollos_ton_max'])}'),
                Columna('Dictamen', (x) => '${x['dictamen_rendimiento']}',
                    celda: (x) => Text('${x['dictamen_rendimiento']}',
                        style: TextStyle(fontWeight: FontWeight.w600, color: '${x['dictamen_rendimiento']}'.startsWith('Alerta') ? Colores.peligro : Colores.exito))),
              ],
            ),
          ]);
        }),
      ],
    );
  }
}

// ------------------------------------------------------------------------------------------------
// RF-21 Existencias y rotación por sede
// ------------------------------------------------------------------------------------------------
final _existenciasProvider = FutureProvider.autoDispose<List<Fila>>((ref) async {
  final enLinea = ref.watch(enLineaProvider);
  final cache = ref.watch(datosOperadorProvider.select((m) => m['existencias']));
  List<Fila> locales() =>
      ((cache as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  if (!enLinea) return locales();
  try {
    final l = await ref.watch(repositorioReportesProvider).existencias();
    ref.read(datosOperadorProvider.notifier).guardarClave('existencias', l);
    return l;
  } catch (_) {
    return locales();
  }
});
final _rotacionProvider = FutureProvider.autoDispose.family<List<Fila>, Periodo>((ref, p) async {
  final enLinea = ref.watch(enLineaProvider);
  final cache = ref.watch(datosOperadorProvider.select((m) => m['reporte_rotacion']));
  List<Fila> locales() =>
      ((cache as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  if (!enLinea) return locales();
  try {
    final l = await ref.watch(repositorioReportesProvider).rotacion(p.desde, p.hasta);
    ref.read(datosOperadorProvider.notifier).guardarClave('reporte_rotacion', l);
    return l;
  } catch (_) {
    return locales();
  }
});

class ReporteExistenciasPagina extends ConsumerStatefulWidget {
  const ReporteExistenciasPagina({super.key});
  @override
  ConsumerState<ReporteExistenciasPagina> createState() => _ReporteExistenciasPaginaState();
}

class _ReporteExistenciasPaginaState extends ConsumerState<ReporteExistenciasPagina> {
  Periodo _p = periodoInicial();
  @override
  Widget build(BuildContext context) {
    final rol = ref.watch(perfilProvider)?.rol;
    final verRotacion = rol != Rol.operadorCentro;
    final ex = ref.watch(_existenciasProvider);
    return Pagina(
      etiquetaRf: 'Reportes · RF-21',
      titulo: 'Existencias y rotación',
      subtitulo: verRotacion
          ? 'Stock actual por sede y lote, y rotación del período (salidas ÷ stock promedio).'
          : 'Stock actual de su centro por lote. La rotación la consultan el área comercial, finanzas y la gerencia.',
      hijos: [
        Asincrono(ex, datos: (l) {
          final rollos = l.where((x) => x['tipo'] == 'rollo').toList();
          final porSede = <String, double>{};
          for (final x in rollos) {
            porSede[x['sede']] = (porSede[x['sede']] ?? 0) + aNumero(x['disponible']) + aNumero(x['reservado']);
          }
          return Column(children: [
            Seccion(titulo: 'Rollos en stock por sede', icono: Icons.stacked_bar_chart, hijo: Barras(porSede, formato: (v) => '${entero(v)} rollos')),
            TablaDatos(
              titulo: 'Existencias por sede y lote',
              filas: l,
              columnas: [
                Columna('Sede', (x) => '${x['sede']}'),
                Columna('Producto', (x) => '${x['producto']}'),
                Columna('Lote', (x) => '${x['lote'] ?? '—'}'),
                Columna('Estado', (x) => etiqueta(x['estado_lote'] ?? 'insumo')),
                Columna('Días', (x) => x['dias'] == null ? '—' : '${x['dias']}', numerica: true),
                Columna('Disponible', (x) => entero(x['disponible']), numerica: true),
                Columna('Reservado', (x) => entero(x['reservado']), numerica: true),
                Columna('En tránsito', (x) => entero(x['en_transito']), numerica: true),
                Columna('Toneladas', (x) => dec2(x['toneladas']), numerica: true),
              ],
            ),
          ]);
        }),
        if (verRotacion) ...[
          const SizedBox(height: 20),
          _BarraPeriodo(_p, (x) => setState(() => _p = x)),
          Asincrono(ref.watch(_rotacionProvider(_p)),
              datos: (l) => TablaDatos(
                    titulo: 'Rotación del período',
                    filas: l,
                    columnas: [
                      Columna('Sede', (x) => '${x['sede']}'),
                      Columna('Producto', (x) => '${x['producto']}'),
                      Columna('Salidas', (x) => entero(x['salidas']), numerica: true),
                      Columna('Stock inicial', (x) => entero(x['stock_inicial']), numerica: true),
                      Columna('Stock final', (x) => entero(x['stock_final']), numerica: true),
                      Columna('Stock promedio', (x) => dec1(x['stock_promedio']), numerica: true),
                      Columna('Rotación', (x) => dec2(rotacion(aNumero(x['salidas']), aNumero(x['stock_promedio']))), numerica: true),
                    ],
                  )),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------------------------------------
// RF-22 Ventas por producto y cartera
// ------------------------------------------------------------------------------------------------
typedef FiltroVentas = ({Periodo p, String? cliente});
final _ventasProvider = FutureProvider.autoDispose.family<Fila, FiltroVentas>(
    (ref, f) => ref.watch(repositorioReportesProvider).ventas(f.p.desde, f.p.hasta, clienteId: f.cliente));
final _clientesReporteProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(repositorioReportesProvider).clientes());

class ReporteVentasPagina extends ConsumerStatefulWidget {
  const ReporteVentasPagina({super.key});
  @override
  ConsumerState<ReporteVentasPagina> createState() => _ReporteVentasPaginaState();
}

class _ReporteVentasPaginaState extends ConsumerState<ReporteVentasPagina> {
  Periodo _p = periodoInicial();
  String? _cliente;
  @override
  Widget build(BuildContext context) {
    final clientes = ref.watch(_clientesReporteProvider).value ?? const [];
    final v = ref.watch(_ventasProvider((p: _p, cliente: _cliente)));
    return Pagina(
      etiquetaRf: 'Reportes · RF-22',
      titulo: 'Ventas y cartera',
      subtitulo: 'Totales del período, por producto y por cliente; cartera de notas emitidas con saldo.',
      hijos: [
        _BarraPeriodo(_p, (x) => setState(() => _p = x), extra: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String?>(
              initialValue: _cliente,
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Cliente', isDense: true),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todos los clientes')),
                for (final c in clientes) DropdownMenuItem<String?>(value: c['id'] as String, child: Text('${c['razon_social']}', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (x) => setState(() => _cliente = x),
            ),
          ),
        ]),
        Asincrono(v, datos: (d) {
          final notas = ((d['notas'] as List?) ?? const []).cast<Fila>();
          final productos = ((d['productos'] as List?) ?? const []).cast<Fila>();
          final cartera = ((d['cartera'] as List?) ?? const []).cast<Fila>();
          final total = notas.fold<double>(0, (a, n) => a + aNumero(n['total']));
          final cobrado = notas.fold<double>(0, (a, n) => a + aNumero(n['cobrado']));
          return Column(children: [
            FilaTarjetas([
              TarjetaDato(titulo: 'Notas de venta', valor: '${notas.length}', icono: Icons.receipt_long_outlined),
              TarjetaDato(titulo: 'Total vendido', valor: bs(total), icono: Icons.point_of_sale_outlined),
              TarjetaDato(titulo: 'Cobrado', valor: bs(cobrado), icono: Icons.savings_outlined, color: Colores.exito),
              TarjetaDato(titulo: 'Por cobrar', valor: bs(total - cobrado), icono: Icons.account_balance_wallet_outlined, color: Colores.ambarOscuro),
            ]),
            Seccion(
              titulo: 'Importe por producto',
              icono: Icons.bar_chart,
              hijo: Barras({for (final p in productos) '${p['producto']}': aNumero(p['importe'])}, formato: bs),
            ),
            TablaDatos(
              titulo: 'Ventas por producto',
              busqueda: false,
              filas: productos,
              columnas: [
                Columna('Producto', (p) => '${p['producto']}'),
                Columna('Rollos', (p) => entero(p['rollos']), numerica: true),
                Columna('Toneladas', (p) => dec2(p['toneladas']), numerica: true),
                Columna('Importe', (p) => bs(p['importe']), numerica: true),
              ],
            ),
            const SizedBox(height: 20),
            TablaDatos(
              titulo: 'Notas de venta del período',
              filas: notas,
              resumen: ['Total ${bs(total)}', 'Cobrado ${bs(cobrado)}', 'Saldo ${bs(total - cobrado)}'],
              columnas: [
                Columna('N.º', (n) => '${n['numero']}', numerica: true),
                Columna('Fecha', (n) => fecha(n['fecha'])),
                Columna('Cliente', (n) => '${n['cliente']}'),
                Columna('Tipo', (n) => etiqueta(n['tipo_cliente'])),
                Columna('Condición', (n) => etiqueta(n['condicion'])),
                Columna('Total', (n) => bs(n['total']), numerica: true),
                Columna('Cobrado', (n) => bs(n['cobrado']), numerica: true),
                Columna('Saldo', (n) => bs(n['saldo']), numerica: true),
                Columna('Estado', (n) => etiqueta(n['estado'])),
              ],
            ),
            const SizedBox(height: 20),
            TablaDatos(
              titulo: 'Cartera por cliente (saldo al día de hoy)',
              busqueda: false,
              filas: cartera,
              columnas: [
                Columna('Cliente', (c) => '${c['cliente']}'),
                Columna('Notas con saldo', (c) => '${c['notas']}', numerica: true),
                Columna('Saldo', (c) => bs(c['saldo']), numerica: true),
                Columna('Límite de crédito', (c) => bs(c['limite_credito']), numerica: true),
              ],
            ),
          ]);
        }),
      ],
    );
  }
}

// ------------------------------------------------------------------------------------------------
// RF-23 Histórico de pérdidas y merma
// ------------------------------------------------------------------------------------------------
final _mermasProvider = FutureProvider.autoDispose.family<Fila, Periodo>((ref, p) async {
  final enLinea = ref.watch(enLineaProvider);
  final cache = ref.watch(datosOperadorProvider.select((m) => m['reporte_mermas']));
  Fila locales() => cache is Map ? Map<String, dynamic>.from(cache) : const {'bajas': <Fila>[], 'por_sede': <Fila>[]};
  if (!enLinea) return locales();
  try {
    final d = await ref.watch(repositorioReportesProvider).mermas(p.desde, p.hasta);
    ref.read(datosOperadorProvider.notifier).guardarClave('reporte_mermas', d);
    return d;
  } catch (_) {
    return locales();
  }
});

class ReporteMermasPagina extends ConsumerStatefulWidget {
  const ReporteMermasPagina({super.key});
  @override
  ConsumerState<ReporteMermasPagina> createState() => _ReporteMermasPaginaState();
}

class _ReporteMermasPaginaState extends ConsumerState<ReporteMermasPagina> {
  Periodo _p = periodoInicial();
  @override
  Widget build(BuildContext context) {
    final v = ref.watch(_mermasProvider(_p));
    return Pagina(
      etiquetaRf: 'Reportes · RF-23',
      titulo: 'Pérdidas y merma',
      subtitulo: 'Cada baja con su causa, quién la solicitó y quién la aprobó.',
      hijos: [
        _BarraPeriodo(_p, (x) => setState(() => _p = x)),
        Asincrono(v, datos: (d) {
          final bajas = ((d['bajas'] as List?) ?? const []).cast<Fila>();
          final sedes = ((d['por_sede'] as List?) ?? const []).cast<Fila>();
          final total = bajas.fold<int>(0, (a, b) => a + (b['cantidad'] as num).toInt());
          final producidos = sedes.fold<int>(0, (a, s) => a + (s['producidos'] as num).toInt());
          final porCausa = <String, double>{};
          for (final b in bajas) {
            porCausa[etiqueta(b['causa'])] = (porCausa[etiqueta(b['causa'])] ?? 0) + aNumero(b['cantidad']);
          }
          return Column(children: [
            FilaTarjetas([
              TarjetaDato(titulo: 'Rollos dados de baja', valor: '$total', icono: Icons.remove_circle_outline, color: Colores.peligro),
              TarjetaDato(titulo: 'Merma sobre lo producido', valor: '${dec1(porcentajeMerma(total, producidos))} %', icono: Icons.percent, color: Colores.ambarOscuro),
              TarjetaDato(titulo: 'Bajas aprobadas', valor: '${bajas.length}', icono: Icons.fact_check_outlined),
            ]),
            Wrap(spacing: 20, runSpacing: 0, children: [
              SizedBox(
                width: esAncho(context) ? 460 : double.infinity,
                child: Seccion(titulo: 'Merma por sede (%)', icono: Icons.bar_chart, hijo: Barras({
                  for (final s in sedes) '${s['sede']}'.replaceAll('Centro de Acopio ', ''): aNumero(s['porcentaje']),
                }, formato: (v) => '${dec1(v)} %', color: Colores.peligro)),
              ),
              SizedBox(
                width: esAncho(context) ? 460 : double.infinity,
                child: Seccion(titulo: 'Rollos por causa', icono: Icons.pie_chart_outline, hijo: Barras(porCausa, formato: (v) => entero(v), color: Colores.ambarOscuro)),
              ),
            ]),
            TablaDatos(
              titulo: 'Bajas aprobadas',
              filas: bajas,
              resumen: ['Total: $total rollos', 'Merma: ${dec1(porcentajeMerma(total, producidos))} %'],
              columnas: [
                Columna('Fecha', (b) => fecha(b['fecha'])),
                Columna('Sede', (b) => '${b['sede']}'),
                Columna('Lote', (b) => '${b['lote']}'),
                Columna('Grano', (b) => '${b['grano']}'),
                Columna('Rollos', (b) => '${b['cantidad']}', numerica: true),
                Columna('Causa', (b) => etiqueta(b['causa'])),
                Columna('Descripción', (b) => '${b['descripcion']}', ancho: 280),
                Columna('Solicitó', (b) => '${b['solicitado_por']}'),
                Columna('Aprobó', (b) => '${b['aprobado_por'] ?? '—'}'),
              ],
            ),
          ]);
        }),
      ],
    );
  }
}

