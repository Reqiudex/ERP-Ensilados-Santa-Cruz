import 'package:flutter/material.dart';

import '../../features/seguridad_accesos/domain/roles_y_permisos.dart';

/// Entrada del menú: un submódulo de la Figura 7 y su ruta.
class EntradaMenu {
  const EntradaMenu(this.submodulo, this.ruta, this.icono, {this.titulo, this.roles});
  final Submodulo submodulo;
  final String ruta;
  final IconData icono;
  final String? titulo;
  final Set<Rol>? roles;

  String get nombre => titulo ?? submodulo.titulo;
  bool permitido(Rol? rol) => rol != null && (roles?.contains(rol) ?? submodulo.permitido(rol));
}

class ModuloMenu {
  const ModuloMenu(this.titulo, this.icono, this.entradas);
  final String titulo;
  final IconData icono;
  final List<EntradaMenu> entradas;
}

const modulosMenu = <ModuloMenu>[
  ModuloMenu('Seguridad y Accesos', Icons.admin_panel_settings_outlined, [
    EntradaMenu(Submodulo.usuarios, '/seguridad/usuarios', Icons.people_alt_outlined),
    EntradaMenu(Submodulo.rbac, '/seguridad/aprobaciones', Icons.fact_check_outlined,
        titulo: 'Bandeja de aprobaciones', roles: {Rol.gerenteGeneral}),
    EntradaMenu(Submodulo.rbac, '/seguridad/permisos', Icons.grid_view_outlined, titulo: 'Control de acceso (RBAC)'),
    EntradaMenu(Submodulo.politicas, '/seguridad/politicas', Icons.password_outlined),
    EntradaMenu(Submodulo.sesiones, '/seguridad/sesiones', Icons.devices_outlined),
    EntradaMenu(Submodulo.bitacora, '/seguridad/bitacora', Icons.history_edu_outlined),
    EntradaMenu(Submodulo.mantenimiento, '/seguridad/mantenimiento', Icons.storage_outlined),
  ]),
  ModuloMenu('Operaciones y Procesamiento', Icons.agriculture_outlined, [
    EntradaMenu(Submodulo.bascula, '/operaciones/bascula', Icons.scale_outlined),
    EntradaMenu(Submodulo.ordenes, '/operaciones/ordenes', Icons.precision_manufacturing_outlined),
    EntradaMenu(Submodulo.insumos, '/operaciones/insumos', Icons.inventory_outlined),
    EntradaMenu(Submodulo.fermentacion, '/operaciones/fermentacion', Icons.thermostat_outlined),
  ]),
  ModuloMenu('Inventario y Logística', Icons.warehouse_outlined, [
    EntradaMenu(Submodulo.stockLotes, '/inventario/lotes', Icons.qr_code_2_outlined),
    EntradaMenu(Submodulo.multisede, '/inventario/sedes', Icons.hub_outlined),
    EntradaMenu(Submodulo.catalogo, '/inventario/catalogo', Icons.sell_outlined),
    EntradaMenu(Submodulo.guias, '/inventario/guias', Icons.local_shipping_outlined),
  ]),
  ModuloMenu('Comercial y Abastecimiento', Icons.storefront_outlined, [
    EntradaMenu(Submodulo.clientesProveedores, '/comercial/clientes', Icons.handshake_outlined),
    EntradaMenu(Submodulo.compras, '/comercial/compras', Icons.shopping_cart_outlined),
    EntradaMenu(Submodulo.pedidos, '/comercial/pedidos', Icons.request_quote_outlined),
    EntradaMenu(Submodulo.ventas, '/comercial/ventas', Icons.receipt_long_outlined),
    EntradaMenu(Submodulo.despachos, '/comercial/despachos', Icons.fire_truck_outlined),
  ]),
  ModuloMenu('Reportes', Icons.insights_outlined, [
    EntradaMenu(Submodulo.reporteRendimiento, '/reportes/rendimiento', Icons.trending_up),
    EntradaMenu(Submodulo.reporteExistencias, '/reportes/existencias', Icons.stacked_bar_chart),
    EntradaMenu(Submodulo.reporteVentas, '/reportes/ventas', Icons.point_of_sale_outlined),
    EntradaMenu(Submodulo.reporteMermas, '/reportes/mermas', Icons.report_gmailerrorred_outlined),
  ]),
];

/// Busca la entrada de menú de una ruta.
EntradaMenu? entradaDeRuta(String ruta) {
  for (final m in modulosMenu) {
    for (final e in m.entradas) {
      if (ruta.startsWith(e.ruta)) return e;
    }
  }
  return null;
}
