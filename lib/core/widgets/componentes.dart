import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/formato.dart';
import '../errores/errores.dart';
import '../exportar/exportador.dart';
import '../supabase/api.dart';
import '../tema/tema.dart';

/// Ancho a partir del cual se usa el diseño de escritorio (portal web de oficina).
const anchoEscritorio = 900.0;
bool esAncho(BuildContext c) => MediaQuery.sizeOf(c).width >= anchoEscritorio;

/// Contenedor estándar de cada pantalla: título, submódulo/RF, acciones y contenido.
class Pagina extends StatelessWidget {
  const Pagina({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.etiquetaRf,
    this.acciones = const [],
    required this.hijos,
    this.alRefrescar,
  });

  final String titulo;
  final String? subtitulo;
  final String? etiquetaRf;
  final List<Widget> acciones;
  final List<Widget> hijos;
  final Future<void> Function()? alRefrescar;

  @override
  Widget build(BuildContext context) {
    final ancho = esAncho(context);
    final contenido = ListView(
      padding: EdgeInsets.fromLTRB(ancho ? 28 : 16, ancho ? 24 : 16, ancho ? 28 : 16, 32),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 12,
          spacing: 12,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (etiquetaRf != null)
                  Text(etiquetaRf!.toUpperCase(),
                      style: TextStyle(fontSize: 12, letterSpacing: .8, color: context.paleta.ambarOscuro, fontWeight: FontWeight.w600)),
                Text(titulo, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (subtitulo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(subtitulo!, style: TextStyle(color: context.paleta.textoSuave)),
                  ),
              ]),
            ),
            if (acciones.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: acciones),
          ],
        ),
        const SizedBox(height: 20),
        ...hijos,
      ],
    );
    return alRefrescar == null ? contenido : RefreshIndicator(onRefresh: alRefrescar!, child: contenido);
  }
}

/// Tarjeta de indicador (KPI).
class TarjetaDato extends StatelessWidget {
  const TarjetaDato({super.key, required this.titulo, required this.valor, this.icono, this.color, this.detalle, this.alTocar});
  final String titulo;
  final String valor;
  final IconData? icono;
  final Color? color;
  final String? detalle;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.paleta.primario;
    return SizedBox(
      width: esAncho(context) ? 220 : (MediaQuery.sizeOf(context).width - 44) / 2,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: alTocar,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (icono != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                    child: Icon(icono, color: c, size: 20),
                  ),
                const SizedBox(width: 10),
                Expanded(child: Text(titulo, style: TextStyle(color: context.paleta.textoSuave, fontSize: 13))),
              ]),
              const SizedBox(height: 12),
              // Una sola línea: si no cabe se achica (una fecha o un importe nunca se parte por la mitad).
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(valor, maxLines: 1, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: c)),
              ),
              if (detalle != null) Text(detalle!, style: TextStyle(fontSize: 12, color: context.paleta.textoSuave)),
            ]),
          ),
        ),
      ),
    );
  }
}

class FilaTarjetas extends StatelessWidget {
  const FilaTarjetas(this.tarjetas, {super.key});
  final List<Widget> tarjetas;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 20), child: Wrap(spacing: 12, runSpacing: 12, children: tarjetas));
}

/// Chip de estado con color semántico.
class Estado extends StatelessWidget {
  const Estado(this.valor, {super.key});
  final Object? valor;

  static Color colorDe(BuildContext context, String v) => switch (v) {
        'apto' || 'activo' || 'aprobada' || 'emitida' || 'pagada' || 'vigente' || 'recibida' || 'confirmado' ||
        'vendido' || 'cerrada' || 'integro' || 'despachado' || 'conforme' =>
          context.paleta.exito,
        'pendiente' || 'fermentacion' || 'en_transito' || 'abierta' || 'cotizacion' || 'pedido' || 'inactivo' =>
          context.paleta.alerta,
        'rechazada' || 'anulada' || 'anulado' || 'bloqueado' || 'suspendido' || 'danado' || 'observado' ||
        'cancelado' || 'no_conforme' =>
          context.paleta.peligro,
        _ => context.paleta.info,
      };

  @override
  Widget build(BuildContext context) {
    final v = '${valor ?? ''}';
    final c = colorDe(context, v);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Text(etiqueta(v), style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Sección con título dentro de una tarjeta.
class Seccion extends StatelessWidget {
  const Seccion({super.key, required this.titulo, required this.hijo, this.accion, this.icono});
  final String titulo;
  final Widget hijo;
  final Widget? accion;
  final IconData? icono;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (icono != null) ...[Icon(icono, size: 20, color: context.paleta.primario), const SizedBox(width: 8)],
                Expanded(child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                ?accion,
              ]),
              const SizedBox(height: 12),
              hijo,
            ]),
          ),
        ),
      );
}

/// Muestra un AsyncValue con carga, error amigable y contenido.
class Asincrono<T> extends StatelessWidget {
  const Asincrono(this.valor, {super.key, required this.datos, this.alReintentar});
  final AsyncValue<T> valor;
  final Widget Function(T) datos;
  final VoidCallback? alReintentar;

  @override
  Widget build(BuildContext context) {
    // Mientras se recarga se sigue mostrando el último dato: la pantalla no vuelve al círculo de carga en cada
    // actualización (sincronización, señal que vuelve, filtros).
    if (valor.hasValue) return datos(valor.requireValue);
    if (valor.hasError) {
      final error = valor.error!;
      return MensajeVacio(
        icono: error is ErrorNegocio && error.prohibido ? Icons.lock_outline : Icons.cloud_off_outlined,
        titulo: error is ErrorNegocio ? error.mensaje : traducirError(error).mensaje,
        accion: alReintentar == null ? null : OutlinedButton(onPressed: alReintentar, child: const Text('Reintentar')),
      );
    }
    return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
  }
}

class MensajeVacio extends StatelessWidget {
  const MensajeVacio({super.key, required this.titulo, this.icono = Icons.inbox_outlined, this.detalle, this.accion});
  final String titulo;
  final IconData icono;
  final String? detalle;
  final Widget? accion;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icono, size: 44, color: context.paleta.textoSuave),
            const SizedBox(height: 10),
            Text(titulo, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (detalle != null)
              Text(detalle!, textAlign: TextAlign.center, style: TextStyle(color: context.paleta.textoSuave)),
            if (accion != null) Padding(padding: const EdgeInsets.only(top: 12), child: accion),
          ]),
        ),
      );
}

/// Definición de una columna de tabla.
class Columna {
  const Columna(this.titulo, this.valor, {this.numerica = false, this.celda, this.ancho});
  final String titulo;
  final String Function(Fila) valor;
  final bool numerica;
  final Widget Function(Fila)? celda;
  final double? ancho;
}

/// Tabla con búsqueda en vivo, exportación y vista de tarjetas en pantallas angostas.
class TablaDatos extends StatefulWidget {
  const TablaDatos({
    super.key,
    required this.columnas,
    required this.filas,
    this.titulo,
    this.busqueda = true,
    this.exportar = true,
    this.csv = false,
    this.acciones,
    this.alTocar,
    this.filtros = const [],
    this.vacio = 'No hay registros.',
    this.resumen = const [],
  });

  final List<Columna> columnas;
  final List<Fila> filas;
  final String? titulo;
  final bool busqueda;
  final bool exportar;
  final bool csv;
  final List<Widget> Function(Fila)? acciones;
  final void Function(Fila)? alTocar;
  final List<Widget> filtros;
  final String vacio;
  final List<String> resumen;

  @override
  State<TablaDatos> createState() => _TablaDatosState();
}

class _TablaDatosState extends State<TablaDatos> {
  String _texto = '';
  int _pagina = 0;
  static const _porPagina = 15;

  List<Fila> get _filtradas {
    if (_texto.isEmpty) return widget.filas;
    final t = _texto.toLowerCase();
    return widget.filas.where((f) => widget.columnas.any((c) => c.valor(f).toLowerCase().contains(t))).toList();
  }

  List<List<String>> _matriz(List<Fila> filas) => filas.map((f) => widget.columnas.map((c) => c.valor(f)).toList()).toList();

  Future<void> _exportar(String tipo) async {
    final titulo = widget.titulo ?? 'Listado';
    final cols = widget.columnas.map((c) => c.titulo).toList();
    final datos = _matriz(_filtradas);
    try {
      if (tipo == 'pdf') await Exportador.pdf(titulo, cols, datos, resumen: widget.resumen);
      if (tipo == 'xlsx') await Exportador.excel(titulo, cols, datos);
      if (tipo == 'csv') await Exportador.csv(titulo, cols, datos);
      if (mounted) avisar(context, 'Archivo $tipo generado.');
    } catch (e) {
      if (mounted) avisar(context, 'No se pudo exportar el archivo.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filas = _filtradas;
    final paginas = (filas.length / _porPagina).ceil().clamp(1, 9999);
    if (_pagina >= paginas) _pagina = 0;
    final visibles = filas.skip(_pagina * _porPagina).take(_porPagina).toList();
    final ancho = esAncho(context);

    final barra = Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (widget.busqueda)
        SizedBox(
          width: ancho ? 300 : double.infinity,
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar…', isDense: true),
            onChanged: (v) => setState(() {
              _texto = v.trim();
              _pagina = 0;
            }),
          ),
        ),
      ...widget.filtros,
      if (widget.exportar)
        PopupMenuButton<String>(
          tooltip: 'Exportar',
          onSelected: _exportar,
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'pdf', child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('PDF'))),
            const PopupMenuItem(value: 'xlsx', child: ListTile(leading: Icon(Icons.grid_on_outlined), title: Text('Excel'))),
            if (widget.csv)
              const PopupMenuItem(value: 'csv', child: ListTile(leading: Icon(Icons.description_outlined), title: Text('CSV'))),
          ],
          child: const Chip(avatar: Icon(Icons.download_outlined, size: 18), label: Text('Exportar')),
        ),
    ]);

    Widget cuerpo;
    if (filas.isEmpty) {
      cuerpo = MensajeVacio(titulo: widget.vacio);
    } else if (ancho) {
      cuerpo = LayoutBuilder(builder: (context, limites) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: limites.maxWidth),
          child: DataTable(
            showCheckboxColumn: false,
            columnSpacing: 20,
            // Estándar de tablas: altura fija por fila y celdas alineadas a la izquierda.
            dataRowMinHeight: 48,
            dataRowMaxHeight: 48,
            columns: [
              ...widget.columnas.map((c) => DataColumn(label: Text(c.titulo))),
              if (widget.acciones != null) const DataColumn(label: Text('Acciones')),
            ],
            rows: visibles
                .map((f) => DataRow(
                      onSelectChanged: widget.alTocar == null ? null : (_) => widget.alTocar!(f),
                      cells: [
                        ...widget.columnas.map((c) => DataCell(Align(
                            alignment: Alignment.centerLeft,
                            child: c.celda?.call(f) ??
                                ConstrainedBox(
                                    constraints: BoxConstraints(maxWidth: c.ancho ?? 260),
                                    child: Tooltip(
                                        message: c.valor(f),
                                        waitDuration: const Duration(milliseconds: 600),
                                        child: Text(c.valor(f), overflow: TextOverflow.ellipsis, maxLines: 1)))))),
                        if (widget.acciones != null)
                          DataCell(Align(alignment: Alignment.centerLeft, child: Row(mainAxisSize: MainAxisSize.min, children: widget.acciones!(f)))),
                      ],
                    ))
                .toList(),
          ),
        ),
      ));
    } else {
      cuerpo = Column(
        children: visibles
            .map((f) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: widget.alTocar == null ? null : () => widget.alTocar!(f),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final c in widget.columnas)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              SizedBox(
                                  width: 120,
                                  child: Text(c.titulo, style: TextStyle(color: context.paleta.textoSuave, fontSize: 13))),
                              Expanded(child: c.celda?.call(f) ?? Text(c.valor(f), style: const TextStyle(fontWeight: FontWeight.w500))),
                            ]),
                          ),
                        if (widget.acciones != null)
                          Align(alignment: Alignment.centerRight, child: Wrap(children: widget.acciones!(f))),
                      ]),
                    ),
                  ),
                ))
            .toList(),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.titulo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(widget.titulo!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          barra,
          const SizedBox(height: 12),
          cuerpo,
          if (paginas > 1)
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('${filas.length} registros · página ${_pagina + 1} de $paginas',
                  style: TextStyle(color: context.paleta.textoSuave)),
              IconButton(
                  onPressed: _pagina == 0 ? null : () => setState(() => _pagina--), icon: const Icon(Icons.chevron_left)),
              IconButton(
                  onPressed: _pagina >= paginas - 1 ? null : () => setState(() => _pagina++),
                  icon: const Icon(Icons.chevron_right)),
            ])
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${filas.length} registros', style: TextStyle(color: context.paleta.textoSuave, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}

/// Avisos breves.
void avisar(BuildContext context, String mensaje, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
        const SizedBox(width: 10),
        Expanded(child: Text(mensaje, style: const TextStyle(color: Colors.white))),
      ]),
      // Fondo de marca fijo: el texto blanco se lee igual en tema claro y oscuro.
      backgroundColor: error ? Colores.peligro : Colores.primarioOscuro,
      duration: Duration(seconds: error ? 6 : 3),
    ));
}

/// Ejecuta una operación mostrando el resultado; devuelve el resultado o null si falló.
Future<T?> ejecutar<T>(BuildContext context, Future<T> Function() accion, {String? exito}) async {
  try {
    final r = await accion();
    if (context.mounted && exito != null) avisar(context, exito);
    return r;
  } catch (e) {
    final err = e is ErrorNegocio ? e : traducirError(e);
    if (context.mounted) avisar(context, err.mensaje, error: true);
    return null;
  }
}

Future<bool> confirmar(BuildContext context, String titulo, String mensaje, {String si = 'Confirmar'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(si)),
        ],
      ),
    ) ??
    false;

/// Pide un texto obligatorio (motivo de una solicitud o de un rechazo).
Future<String?> pedirTexto(BuildContext context, String titulo, {String etiqueta = 'Motivo', int minimo = 5, String? inicial}) {
  final ctrl = TextEditingController(text: inicial);
  final clave = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Form(
        key: clave,
        child: SizedBox(
          width: 420,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(labelText: etiqueta),
            validator: (v) => (v ?? '').trim().length < minimo ? 'Escriba al menos $minimo caracteres.' : null,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () {
              if (clave.currentState!.validate()) Navigator.pop(c, ctrl.text.trim());
            },
            child: const Text('Enviar')),
      ],
    ),
  );
}

/// Diálogo de formulario genérico con ancho adaptable.
Future<T?> dialogoFormulario<T>(BuildContext context, {required String titulo, required Widget Function(BuildContext, StateSetter) contenido, required Future<T?> Function() alGuardar, String guardar = 'Guardar', GlobalKey<FormState>? formulario}) {
  return showDialog<T>(
    context: context,
    builder: (c) {
      var ocupado = false;
      return StatefulBuilder(builder: (c, setState) {
        return AlertDialog(
          title: Text(titulo),
          content: SizedBox(width: 520, child: SingleChildScrollView(child: contenido(c, setState))),
          actions: [
            TextButton(onPressed: ocupado ? null : () => Navigator.pop(c), child: const Text('Cancelar')),
            FilledButton(
              onPressed: ocupado
                  ? null
                  : () async {
                      if (formulario != null && !formulario.currentState!.validate()) return;
                      setState(() => ocupado = true);
                      final r = await alGuardar();
                      if (c.mounted) {
                        setState(() => ocupado = false);
                        if (r != null) Navigator.pop(c, r);
                      }
                    },
              child: ocupado
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(guardar),
            ),
          ],
        );
      });
    },
  );
}

/// Recuadro informativo (reglas de negocio visibles para el usuario).
class Aviso extends StatelessWidget {
  const Aviso(this.texto, {super.key, this.tipo = 'info', this.icono});
  final String texto;
  final String tipo;
  final IconData? icono;
  @override
  Widget build(BuildContext context) {
    final c = switch (tipo) { 'alerta' => context.paleta.alerta, 'error' => context.paleta.peligro, 'ok' => context.paleta.exito, _ => context.paleta.info };
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withValues(alpha: .08), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: .3))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icono ?? (tipo == 'alerta' ? Icons.warning_amber_rounded : tipo == 'error' ? Icons.block : Icons.info_outline), color: c),
        const SizedBox(width: 10),
        Expanded(child: Text(texto)),
      ]),
    );
  }
}

/// Selector desplegable de una lista de filas.
class Selector extends StatelessWidget {
  const Selector({super.key, required this.etiqueta, required this.opciones, required this.valor, required this.alCambiar, this.texto, this.clave = 'id', this.validar = true});
  final String etiqueta;
  final List<Fila> opciones;
  final String? valor;
  final ValueChanged<String?> alCambiar;
  final String Function(Fila)? texto;
  final String clave;
  final bool validar;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: opciones.any((o) => '${o[clave]}' == valor) ? valor : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: etiqueta),
        items: opciones
            .map((o) => DropdownMenuItem(value: '${o[clave]}', child: Text(texto?.call(o) ?? '${o['nombre'] ?? o[clave]}', overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: alCambiar,
        validator: validar ? (v) => v == null ? 'Seleccione una opción.' : null : null,
      );
}

final relojProvider = StreamProvider<DateTime>((ref) => Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now()));
