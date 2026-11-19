import 'dart:convert';

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
  var _f = FiltroBitacora(desde: DateTime.now().subtract(const Duration(days: 30)));

  static const _acciones = {
    'insert': 'Alta', 'update': 'Cambio', 'delete': 'Baja', 'login': 'Inicio de sesión', 'login_fallido': 'Intento fallido',
    'bloqueo': 'Bloqueo de cuenta', 'acceso_denegado': 'Acceso denegado', 'cambio_clave': 'Cambio de contraseña',
    'restablecer_clave': 'Restablecer contraseña', 'cierre_sesiones': 'Cierre de sesiones', 'parametro': 'Parámetro',
    'respaldo': 'Respaldo', 'respaldo_pedido': 'Respaldo pedido', 'restauracion': 'Restauración', 'desbloqueo': 'Desbloqueo',
  };
  static const _tablas = {
    'usuarios': 'Usuarios', 'solicitudes_aprobacion': 'Solicitudes', 'pesajes': 'Pesajes', 'ordenes_ensilado': 'Órdenes',
    'lotes': 'Lotes', 'guias_transferencia': 'Guías', 'mermas': 'Mermas', 'compras': 'Compras', 'pagos': 'Pagos',
    'pedidos': 'Pedidos', 'notas_venta': 'Notas de venta', 'cobros': 'Cobros', 'despachos': 'Despachos', 'productos': 'Productos',
    'clientes': 'Clientes', 'proveedores': 'Proveedores', 'parametros': 'Parámetros', 'respaldos': 'Respaldos', 'reportes': 'Reportes',
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

  Future<void> _fecha(bool desde) async {
    final d = await showDatePicker(
        context: context,
        firstDate: DateTime(2026),
        lastDate: DateTime.now(),
        initialDate: (desde ? _f.desde : _f.hasta) ?? DateTime.now());
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
                Columna('Registró', (e) => '${e['usuario']?['nombre_completo'] ?? 'Sistema / anónimo'}'),
                Columna('Aprobó', (e) => '${e['aprobador']?['nombre_completo'] ?? '—'}'),
                Columna('Acción', (e) => _acciones[e['accion']] ?? '${e['accion']}',
                    celda: (e) => Text(_acciones[e['accion']] ?? '${e['accion']}',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: ['acceso_denegado', 'login_fallido', 'bloqueo'].contains(e['accion']) ? Colores.peligro : null))),
                Columna('Tabla o módulo', (e) => _tablas[e['tabla']] ?? '${e['tabla']}'),
                Columna('IP', (e) => '${e['ip'] ?? '—'}'),
                Columna('Cambio', _cambio, ancho: 380),
              ],
              alTocar: (e) => showDialog(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text('Evento N.º ${e['id']}'),
                  content: SizedBox(
                    width: 560,
                    child: SingleChildScrollView(
                      child: SelectableText(const JsonEncoder.withIndent('  ').convert({
                        'antes': enmascararDatos(e['datos_antes']),
                        'despues': enmascararDatos(e['datos_despues']),
                      })),
                    ),
                  ),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar'))],
                ),
              ),
            )),
      ],
    );
  }
}
