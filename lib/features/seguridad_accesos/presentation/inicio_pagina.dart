import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/formato.dart';
import '../../../core/router/menu.dart';
import '../../../core/supabase/api.dart';
import '../../../core/tema/tema.dart';
import '../../../core/widgets/componentes.dart';
import '../../operaciones_ensilado/data/cola_sincronizacion.dart';
import '../domain/roles_y_permisos.dart';
import 'sesion.dart';

/// Indicadores del tablero de inicio según el rol.
final indicadoresInicioProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final perfil = ref.watch(perfilProvider);
  final api = ref.watch(apiProvider);
  if (perfil == null) return {};
  final r = <String, dynamic>{};
  Future<void> intentar(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  switch (perfil.rol) {
    case Rol.adminSistema:
      await intentar(() async => r['usuarios'] = await api.consultar('usuarios', 'estado'));
      await intentar(() async => r['sesiones'] = await api.rpcLista('sesiones_activas'));
      await intentar(() async => r['respaldos'] = await api.rpcLista('respaldos'));
    case Rol.operadorCentro:
      await intentar(() async => r['ordenes'] = await api.consultar('ordenes_ensilado', 'id', igual: {'estado': 'abierta'}));
      await intentar(() async => r['lotes'] = await api.consultar('lotes', 'id, estado'));
      await intentar(() async => r['guias'] = await api.consultar('guias_transferencia', 'id, sede_destino', igual: {'estado': 'en_transito'}));
      await intentar(() async => r['despachos'] = await api.rpcLista('despachos_pendientes'));
    case Rol.ejecutivoComercial || Rol.cajeroContador || Rol.gerenteGeneral || Rol.superadmin:
      await intentar(() async => r['existencias'] = await api.rpcLista('reporte_existencias'));
      await intentar(() async => r['notas'] = await api.consultar('notas_venta', 'id, estado, saldo, total, fecha_registro'));
      if (perfil.rol == Rol.cajeroContador || perfil.rol.comoGerente) {
        await intentar(() async => r['compras'] = await api.consultar('compras', 'id, estado, saldo'));
      }
      if (perfil.rol.comoGerente) {
        await intentar(() async => r['bandeja'] = await api.rpcLista('bandeja_aprobaciones', {'p_estado': 'pendiente'}));
        await intentar(() async => r['rendimiento'] = await api.rpcLista('reporte_rendimiento'));
      }
  }
  return r;
});

class InicioPagina extends ConsumerWidget {
  const InicioPagina({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider)!;
    final datos = ref.watch(indicadoresInicioProvider);
    final hora = DateTime.now().hour;
    final saludo = hora < 12 ? 'Buenos días' : hora < 19 ? 'Buenas tardes' : 'Buenas noches';
    final accesos = [
      for (final m in modulosMenu)
        for (final e in m.entradas)
          if (e.permitido(perfil.rol)) e,
    ];
    return Pagina(
      titulo: '$saludo, ${perfil.nombre.split(' ').first}',
      subtitulo: '${perfil.rol.nombre} · ${perfil.sede}',
      alRefrescar: () async => ref.invalidate(indicadoresInicioProvider),
      hijos: [
        Asincrono(datos, alReintentar: () => ref.invalidate(indicadoresInicioProvider), datos: (d) => _Indicadores(d)),
        Seccion(
          titulo: 'Accesos rápidos',
          icono: Icons.bolt_outlined,
          hijo: Wrap(spacing: 10, runSpacing: 10, children: [
            for (final e in accesos)
              SizedBox(
                width: esAncho(context) ? 250 : double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, minimumSize: const Size(48, 56)),
                  onPressed: () => context.go(e.ruta),
                  icon: Icon(e.icono),
                  label: Text(e.nombre, overflow: TextOverflow.ellipsis),
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

class _Indicadores extends ConsumerWidget {
  const _Indicadores(this.d);
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider)!;
    List<Fila> l(String k) => (d[k] as List?)?.cast<Fila>() ?? const [];
    final tarjetas = <Widget>[];
    switch (perfil.rol) {
      case Rol.adminSistema:
        final u = l('usuarios');
        tarjetas.addAll([
          TarjetaDato(titulo: 'Usuarios activos', valor: '${u.where((x) => x['estado'] == 'activo').length}', icono: Icons.people_alt_outlined,
              detalle: '${u.length} cuentas en total', alTocar: () => context.go('/seguridad/usuarios')),
          TarjetaDato(titulo: 'Sesiones abiertas', valor: '${l('sesiones').length}', icono: Icons.devices_outlined,
              color: Colores.info, alTocar: () => context.go('/seguridad/sesiones')),
          TarjetaDato(
              titulo: 'Último respaldo',
              valor: l('respaldos').where((x) => x['accion'] == 'respaldo').isEmpty
                  ? 'Sin datos'
                  : fecha(l('respaldos').firstWhere((x) => x['accion'] == 'respaldo')['fecha']),
              icono: Icons.backup_outlined,
              color: Colores.ambarOscuro,
              alTocar: () => context.go('/seguridad/mantenimiento')),
        ]);
      case Rol.operadorCentro:
        final pendientes = ref.watch(pendientesSincronizarProvider);
        final lotes = l('lotes');
        tarjetas.addAll([
          TarjetaDato(titulo: 'Por sincronizar', valor: '$pendientes', icono: Icons.sync, color: pendientes > 0 ? Colores.alerta : Colores.exito,
              alTocar: () => context.go('/operaciones/bascula')),
          TarjetaDato(titulo: 'Órdenes abiertas', valor: '${l('ordenes').length}', icono: Icons.precision_manufacturing_outlined,
              alTocar: () => context.go('/operaciones/ordenes')),
          TarjetaDato(titulo: 'Lotes en fermentación', valor: '${lotes.where((x) => x['estado'] == 'fermentacion').length}',
              icono: Icons.thermostat_outlined, color: Colores.ambarOscuro, alTocar: () => context.go('/operaciones/fermentacion')),
          TarjetaDato(titulo: 'Guías por recibir', valor: '${l('guias').where((g) => g['sede_destino'] == perfil.sedeId).length}',
              icono: Icons.local_shipping_outlined, color: Colores.info, alTocar: () => context.go('/inventario/guias')),
          TarjetaDato(titulo: 'Despachos pendientes', valor: '${l('despachos').length}', icono: Icons.fire_truck_outlined,
              alTocar: () => context.go('/comercial/despachos')),
        ]);
      default:
        final ex = l('existencias').where((x) => x['tipo'] == 'rollo');
        final aptos = ex.where((x) => x['estado_lote'] == 'apto').fold<double>(0, (a, x) => a + aNumero(x['disponible']));
        final notas = l('notas');
        final cartera = notas.where((n) => n['estado'] == 'emitida').fold<double>(0, (a, n) => a + aNumero(n['saldo']));
        final mes = DateTime.now();
        final ventasMes = notas
            .where((n) => n['estado'] != 'anulada' && aFecha(n['fecha_registro'])?.month == mes.month && aFecha(n['fecha_registro'])?.year == mes.year)
            .fold<double>(0, (a, n) => a + aNumero(n['total']));
        if (perfil.rol.comoGerente) {
          tarjetas.add(TarjetaDato(titulo: 'Solicitudes por aprobar', valor: '${l('bandeja').length}', icono: Icons.fact_check_outlined,
              color: l('bandeja').isEmpty ? Colores.exito : Colores.peligro, alTocar: () => context.go('/seguridad/aprobaciones')));
          final alertas = l('rendimiento').where((x) => '${x['dictamen_rendimiento']}'.startsWith('Alerta')).length;
          tarjetas.add(TarjetaDato(titulo: 'Alertas de rendimiento', valor: '$alertas', icono: Icons.warning_amber_rounded,
              color: alertas > 0 ? Colores.alerta : Colores.exito, alTocar: () => context.go('/reportes/rendimiento')));
        }
        tarjetas.addAll([
          TarjetaDato(titulo: 'Rollos aptos para venta', valor: entero(aptos), icono: Icons.inventory_2_outlined,
              alTocar: () => context.go('/inventario/sedes')),
          TarjetaDato(titulo: 'Cartera por cobrar', valor: bs(cartera), icono: Icons.account_balance_wallet_outlined,
              color: Colores.ambarOscuro, alTocar: () => context.go('/reportes/ventas')),
          TarjetaDato(titulo: 'Ventas del mes', valor: bs(ventasMes), icono: Icons.point_of_sale_outlined, color: Colores.info,
              alTocar: () => context.go('/comercial/ventas')),
        ]);
        if (perfil.rol != Rol.ejecutivoComercial) {
          final porPagar = l('compras').where((c) => c['estado'] == 'aprobada').fold<double>(0, (a, c) => a + aNumero(c['saldo']));
          tarjetas.add(TarjetaDato(titulo: 'Compras por pagar', valor: bs(porPagar), icono: Icons.payments_outlined,
              color: Colores.peligro, alTocar: () => context.go('/comercial/compras')));
        }
    }
    return FilaTarjetas(tarjetas);
  }
}

final misSolicitudesProvider = FutureProvider.autoDispose<List<Fila>>((ref) => ref.watch(apiProvider).rpcLista('mis_solicitudes'));

/// Seguimiento de las solicitudes que registró el usuario (para cualquier rol).
class MisSolicitudesPagina extends ConsumerWidget {
  const MisSolicitudesPagina({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(misSolicitudesProvider);
    return Pagina(
      titulo: 'Mis solicitudes',
      subtitulo: 'Lo que usted pidió al gerente: mermas, correcciones, precios, anulaciones y más.',
      alRefrescar: () async => ref.invalidate(misSolicitudesProvider),
      hijos: [
        Asincrono(v,
            datos: (filas) => TablaDatos(
                  titulo: 'Solicitudes registradas',
                  filas: filas,
                  columnas: [
                    Columna('Fecha', (f) => fechaHora(f['fecha_registro'])),
                    Columna('Tipo', (f) => etiqueta(f['tipo'])),
                    Columna('Motivo', (f) => '${f['motivo']}', ancho: 320),
                    Columna('Estado', (f) => etiqueta(f['estado']), celda: (f) => Estado(f['estado'])),
                    Columna('Resuelta por', (f) => '${f['aprobado_por'] ?? '—'}'),
                    Columna('Respuesta', (f) => '${(f['datos'] as Map?)?['motivo_decision'] ?? '—'}'),
                  ],
                )),
      ],
    );
  }
}
