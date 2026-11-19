import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/comercial_abastecimiento/presentation/clientes_proveedores_pagina.dart';
import '../../features/comercial_abastecimiento/presentation/compras_pagina.dart';
import '../../features/comercial_abastecimiento/presentation/despachos_pagina.dart';
import '../../features/comercial_abastecimiento/presentation/pedidos_pagina.dart';
import '../../features/comercial_abastecimiento/presentation/ventas_pagina.dart';
import '../../features/inventario_multisede/presentation/catalogo_pagina.dart';
import '../../features/inventario_multisede/presentation/guias_pagina.dart';
import '../../features/inventario_multisede/presentation/multisede_pagina.dart';
import '../../features/inventario_multisede/presentation/stock_lotes_pagina.dart';
import '../../features/operaciones_ensilado/presentation/bascula_pagina.dart';
import '../../features/operaciones_ensilado/presentation/fermentacion_pagina.dart';
import '../../features/operaciones_ensilado/presentation/insumos_pagina.dart';
import '../../features/operaciones_ensilado/presentation/ordenes_pagina.dart';
import '../../features/reportes/presentation/reportes_paginas.dart';
import '../../features/seguridad_accesos/presentation/aprobaciones_pagina.dart';
import '../../features/seguridad_accesos/presentation/bitacora_pagina.dart';
import '../../features/seguridad_accesos/presentation/ingreso_paginas.dart';
import '../../features/seguridad_accesos/presentation/inicio_pagina.dart';
import '../../features/seguridad_accesos/presentation/mantenimiento_pagina.dart';
import '../../features/seguridad_accesos/presentation/parametros_pagina.dart';
import '../../features/seguridad_accesos/presentation/matriz_pagina.dart';
import '../../features/seguridad_accesos/presentation/politicas_pagina.dart';
import '../../features/seguridad_accesos/presentation/sesion.dart';
import '../../features/seguridad_accesos/presentation/sesiones_pagina.dart';
import '../../features/seguridad_accesos/presentation/usuarios_pagina.dart';
import 'estructura.dart';
import 'menu.dart';

/// Avisa al router cuando cambia la sesión.
class _Aviso extends ChangeNotifier {
  void avisar() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final aviso = _Aviso();
  ref.listen(sesionProvider, (_, _) => aviso.avisar());
  ref.onDispose(aviso.dispose);

  Widget pagina(String ruta) => switch (ruta) {
        '/inicio' => const InicioPagina(),
        '/mis-solicitudes' => const MisSolicitudesPagina(),
        '/seguridad/usuarios' => const UsuariosPagina(),
        '/seguridad/aprobaciones' => const AprobacionesPagina(),
        '/seguridad/permisos' => const MatrizPagina(),
        '/seguridad/politicas' => const PoliticasPagina(),
        '/seguridad/sesiones' => const SesionesPagina(),
        '/seguridad/bitacora' => const BitacoraPagina(),
        '/seguridad/mantenimiento' => const MantenimientoPagina(),
        '/seguridad/parametros' => const ParametrosPagina(),
        '/operaciones/bascula' => const BasculaPagina(),
        '/operaciones/ordenes' => const OrdenesPagina(),
        '/operaciones/insumos' => const InsumosPagina(),
        '/operaciones/fermentacion' => const FermentacionPagina(),
        '/inventario/lotes' => const StockLotesPagina(),
        '/inventario/sedes' => const MultisedePagina(),
        '/inventario/catalogo' => const CatalogoPagina(),
        '/inventario/guias' => const GuiasPagina(),
        '/comercial/clientes' => const ClientesProveedoresPagina(),
        '/comercial/compras' => const ComprasPagina(),
        '/comercial/pedidos' => const PedidosPagina(),
        '/comercial/ventas' => const VentasPagina(),
        '/comercial/despachos' => const DespachosPagina(),
        '/reportes/rendimiento' => const ReporteRendimientoPagina(),
        '/reportes/existencias' => const ReporteExistenciasPagina(),
        '/reportes/ventas' => const ReporteVentasPagina(),
        '/reportes/mermas' => const ReporteMermasPagina(),
        _ => const InicioPagina(),
      };

  const rutasInternas = [
    '/inicio', '/mis-solicitudes', '/seguridad/usuarios', '/seguridad/aprobaciones', '/seguridad/permisos',
    '/seguridad/politicas', '/seguridad/sesiones', '/seguridad/bitacora', '/seguridad/mantenimiento', '/seguridad/parametros',
    '/operaciones/bascula', '/operaciones/ordenes', '/operaciones/insumos', '/operaciones/fermentacion',
    '/inventario/lotes', '/inventario/sedes', '/inventario/catalogo', '/inventario/guias', '/comercial/clientes',
    '/comercial/compras', '/comercial/pedidos', '/comercial/ventas', '/comercial/despachos', '/reportes/rendimiento',
    '/reportes/existencias', '/reportes/ventas', '/reportes/mermas',
  ];

  return GoRouter(
    initialLocation: '/inicio',
    refreshListenable: aviso,
    redirect: (context, estado) {
      final s = ref.read(sesionProvider);
      final ruta = estado.matchedLocation;
      if (s.isLoading) return ruta == '/cargando' ? null : '/cargando';
      final sesion = s.value;
      final perfil = sesion?.perfil;
      if (perfil == null) return ruta == '/ingresar' ? null : '/ingresar';
      if (sesion!.bloqueadaPorPin) return ruta == '/pin' ? null : '/pin';
      if (perfil.debeCambiarClave) return ruta == '/cambiar-clave' ? null : '/cambiar-clave';
      if (ruta == '/ingresar' || ruta == '/cargando' || (ruta == '/pin' && estado.uri.queryParameters['configurar'] == null)) {
        return '/inicio';
      }
      // La interfaz oculta lo que el rol no puede usar; si se escribe la ruta a mano, vuelve al inicio.
      final entrada = entradaDeRuta(ruta);
      if (entrada != null && !entrada.permitido(perfil.rol)) return '/inicio';
      return null;
    },
    routes: [
      GoRoute(path: '/cargando', builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(path: '/ingresar', builder: (_, _) => const IngresoPagina()),
      GoRoute(path: '/cambiar-clave', builder: (_, _) => const CambiarClavePagina()),
      GoRoute(path: '/pin', builder: (_, e) => PinPagina(configurar: e.uri.queryParameters['configurar'] != null)),
      ShellRoute(
        builder: (context, estado, hijo) => Estructura(ruta: estado.matchedLocation, hijo: hijo),
        routes: [for (final r in rutasInternas) GoRoute(path: r, pageBuilder: (_, _) => NoTransitionPage(child: pagina(r)))],
      ),
    ],
  );
});
