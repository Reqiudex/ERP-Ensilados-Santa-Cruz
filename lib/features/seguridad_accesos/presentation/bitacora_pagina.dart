import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/formato.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../data/repositorio_seguridad_supabase.dart';
import '../domain/reglas_seguridad.dart';
import 'usuarios_pagina.dart';

class FiltroBitacora {
  const FiltroBitacora({this.desde, this.hasta, this.accion, this.tabla, this.usuario});
  final DateTime? desde;
  final DateTime? hasta;
  final String? accion;
  final String? tabla;
  final String? usuario;
  @override
  bool operator ==(Object other) =>
      other is FiltroBitacora && other.desde == desde && other.hasta == hasta && other.accion == accion && other.tabla == tabla && other.usuario == usuario;
  @override
  int get hashCode => Object.hash(desde, hasta, accion, tabla, usuario);
}

final bitacoraProvider = FutureProvider.autoDispose.family<List<Fila>, FiltroBitacora>((ref, f) => ref
    .watch(repositorioSeguridadProvider)
    .bitacora(desde: f.desde, hasta: f.hasta, accion: f.accion, tabla: f.tabla, usuarioId: f.usuario));

/// RF-05 Bitácora de eventos: lista cronológica inalterable con datos personales enmascarados.
class BitacoraPagina extends ConsumerStatefulWidget {
  const BitacoraPagina({super.key});
  @override
  ConsumerState<BitacoraPagina> createState() => _BitacoraPaginaState();
}

class _BitacoraPaginaState extends ConsumerState<BitacoraPagina> {
  // Últimos 30 días completos (desde las 00:00 de ese día).
  var _f = FiltroBitacora(desde: DateUtils.dateOnly(DateTime.now()).subtract(const Duration(days: 30)));

  static const _acciones = {
    'insert': 'Alta', 'update': 'Cambio', 'delete': 'Baja', 'login': 'Inicio de sesión', 'login_fallido': 'Intento fallido',
    'bloqueo': 'Bloqueo de cuenta', 'acceso_denegado': 'Acceso denegado', 'cambio_clave': 'Cambio de contraseña',
    'restablecer_clave': 'Restablecer contraseña', 'cierre_sesiones': 'Cierre de sesiones', 'parametro': 'Parámetro',
    'respaldo': 'Respaldo', 'respaldo_pedido': 'Respaldo pedido', 'respaldo_fallido': 'Respaldo fallido',
    'restauracion': 'Restauración', 'desbloqueo': 'Desbloqueo', 'optimizacion': 'Mantenimiento de la base',
    'github_vinculado': 'GitHub vinculado', 'github_desvinculado': 'GitHub desvinculado',
  };
  static const _tablas = {
    'usuarios': 'Usuarios', 'solicitudes_aprobacion': 'Solicitudes', 'pesajes': 'Pesajes', 'ordenes_ensilado': 'Órdenes',
    'lotes': 'Lotes', 'guias_transferencia': 'Guías', 'mermas': 'Mermas', 'compras': 'Compras', 'pagos': 'Pagos',
    'pedidos': 'Pedidos', 'notas_venta': 'Notas de venta', 'cobros': 'Cobros', 'despachos': 'Despachos', 'productos': 'Productos',
    'clientes': 'Clientes', 'proveedores': 'Proveedores', 'parametros': 'Parámetros', 'respaldos': 'Respaldos', 'reportes': 'Reportes',
    'consumos_insumo': 'Consumo de insumos', 'revisiones_fermentacion': 'Revisiones de fermentación', 'granos': 'Parámetros por grano',
    'sesiones': 'Sesiones', 'existencias': 'Existencias',
  };

  String _cambio(Fila e) {
    final antes = enmascararDatos(e['datos_antes']);
    final despues = enmascararDatos(e['datos_despues']);
    if (antes is Map && despues is Map) {
      final cambios = <String>[];
      for (final k in despues.keys) {
        if ('${antes[k]}' != '${despues[k]}') cambios.add('$k: ${antes[k]} → ${despues[k]}');
      }
      return cambios.take(6).join(' · ');
    }
    final d = despues ?? antes;
    if (d is Map) {
      return d.entries.where((x) => x.value != null).take(6).map((x) => '${x.key}: ${x.value}').join(' · ');
    }
    return '';
  }

  /// «Desde» no puede quedar después de «Hasta» (ni al revés): cada selector se limita por la otra fecha.
  Future<void> _fecha(bool desde) async {
    final hoy = DateTime.now();
    final primera = DateTime(2026);
    final d = await showDatePicker(
        context: context,
        firstDate: desde ? primera : (_f.desde ?? primera),
        lastDate: desde ? (_f.hasta ?? hoy) : hoy,
        initialDate: (desde ? _f.desde : _f.hasta) ?? hoy);
    if (d == null) return;
    setState(() => _f = FiltroBitacora(
        desde: desde ? d : _f.desde, hasta: desde ? _f.hasta : d, accion: _f.accion, tabla: _f.tabla, usuario: _f.usuario));
  }

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(bitacoraProvider(_f));
    final usuarios = ref.watch(usuariosProvider).value ?? const [];
    return Pagina(
      etiquetaRf: 'Seguridad y Accesos · RF-05',
      titulo: 'Bitácora de eventos',
      subtitulo: 'Registro automático e inalterable (sin UPDATE ni DELETE para ningún rol). CI y correos se muestran enmascarados.',
      alRefrescar: () async => ref.invalidate(bitacoraProvider(_f)),
      hijos: [
        const _BannerWorm(),
        const SizedBox(height: 12),
        Asincrono(v, datos: (l) => TablaDatos(
              titulo: 'Eventos',
              csv: true,
              filas: l,
              filtros: [
                OutlinedButton.icon(onPressed: () => _fecha(true), icon: const Icon(Icons.event), label: Text('Desde ${fecha(_f.desde)}')),
                OutlinedButton.icon(onPressed: () => _fecha(false), icon: const Icon(Icons.event), label: Text('Hasta ${_f.hasta == null ? 'hoy' : fecha(_f.hasta)}')),
                filtroDesplegable('Acción', _f.accion, _acciones, (a) => setState(() => _f = FiltroBitacora(desde: _f.desde, hasta: _f.hasta, accion: a, tabla: _f.tabla, usuario: _f.usuario))),
                filtroDesplegable('Módulo o tabla', _f.tabla, _tablas, (t) => setState(() => _f = FiltroBitacora(desde: _f.desde, hasta: _f.hasta, accion: _f.accion, tabla: t, usuario: _f.usuario))),
                filtroDesplegable('Usuario', _f.usuario, {for (final u in usuarios) '${u['id']}': '${u['nombre_completo']}'},
                    (u) => setState(() => _f = FiltroBitacora(desde: _f.desde, hasta: _f.hasta, accion: _f.accion, tabla: _f.tabla, usuario: u))),
              ],
              columnas: [
                Columna('Fecha servidor', (e) => fechaHora(e['fecha_servidor'])),
                Columna('Fecha dispositivo', (e) => fechaHora(e['fecha_dispositivo'])),
                Columna('Registró', (e) => '${e['nombre_registro'] ?? 'Sistema / anónimo'}'),
                Columna('Aprobó', (e) => '${e['nombre_aprobador'] ?? '—'}'),
                Columna('Acción', (e) => _acciones[e['accion']] ?? '${e['accion']}',
                    celda: (e) => Text(_acciones[e['accion']] ?? '${e['accion']}',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: ['acceso_denegado', 'login_fallido', 'bloqueo'].contains(e['accion']) ? Colores.peligro : null))),
                Columna('Tabla o módulo', (e) => _tablas[e['tabla']] ?? '${e['tabla']}'),
                Columna('IP', (e) => '${e['ip'] ?? '—'}'),
                Columna('Cambio', _cambio, ancho: 380),
              ],
              alTocar: (e) => showDialog(context: context, builder: (_) => InspectorCambios(evento: e, accion: _acciones[e['accion']] ?? '${e['accion']}')),
            )),
      ],
    );
  }
}

/// Aviso de inmutabilidad: la bitácora es de escritura única y lectura múltiple (WORM).
class _BannerWorm extends StatelessWidget {
  const _BannerWorm();
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.secondaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(Icons.lock_outline, color: c.onSecondaryContainer),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Registros inmutables (WORM: se escriben una vez y solo se leen). La base de datos rechaza cualquier UPDATE o DELETE '
            'sobre la bitácora, para todos los roles.',
            style: TextStyle(color: c.onSecondaryContainer),
          ),
        ),
      ]),
    );
  }
}

/// Inspector de cambios: compara lado a lado el valor anterior (rojo) y el nuevo (verde) de cada campo.
class InspectorCambios extends StatelessWidget {
  const InspectorCambios({super.key, required this.evento, required this.accion});
  final Fila evento;
  final String accion;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final antes = enmascararDatos(evento['datos_antes']);
    final despues = enmascararDatos(evento['datos_despues']);
    final ma = antes is Map ? antes : const {};
    final md = despues is Map ? despues : const {};
    final claves = {...ma.keys, ...md.keys}.map((k) => '$k').toList()..sort();
    final ancho = esAncho(context);

    Widget columna(String titulo, Map datos, Color fondo, Color texto, IconData icono) => Expanded(
          child: Container(
            decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icono, size: 18, color: texto),
                const SizedBox(width: 6),
                Text(titulo, style: TextStyle(color: texto, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              if (datos.isEmpty) Text('(sin datos)', style: TextStyle(color: texto)),
              for (final k in claves)
                if (datos.containsKey(k))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: SelectableText.rich(TextSpan(children: [
                      TextSpan(text: '$k: ', style: TextStyle(color: texto, fontWeight: FontWeight.w600)),
                      TextSpan(
                        text: '${datos[k]}',
                        style: TextStyle(
                          color: texto,
                          backgroundColor: '${ma[k]}' != '${md[k]}' ? texto.withValues(alpha: .12) : null,
                        ),
                      ),
                    ])),
                  ),
            ]),
          ),
        );

    final cuerpo = [
      columna('Antes', ma, c.errorContainer, c.onErrorContainer, Icons.remove_circle_outline),
      SizedBox(width: ancho ? 12 : 0, height: ancho ? 0 : 12),
      columna('Después', md, c.primaryContainer, c.onPrimaryContainer, Icons.add_circle_outline),
    ];
    return AlertDialog(
      title: Text('Evento N.º ${evento['id']} · $accion'),
      content: SizedBox(
        width: 820,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${evento['tabla']} · ${fechaHora(evento['fecha_servidor'])} · '
                '${evento['nombre_registro'] ?? 'Sistema / anónimo'}'),
            const SizedBox(height: 12),
            ancho
                ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cuerpo))
                : Column(children: [for (final w in cuerpo) w is Expanded ? w.child : w]),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}
