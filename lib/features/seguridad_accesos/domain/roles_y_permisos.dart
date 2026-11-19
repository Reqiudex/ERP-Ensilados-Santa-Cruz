/// Roles fijos y matriz de permisos de la tesis. Dart puro.
library;

enum Rol {
  adminSistema('admin_sistema', 'Administrador del sistema'),
  operadorCentro('operador_centro', 'Operador de centro de acopio'),
  ejecutivoComercial('ejecutivo_comercial', 'Ejecutivo comercial'),
  cajeroContador('cajero_contador', 'Cajero o contador'),
  gerenteGeneral('gerente_general', 'Gerente general'),
  superadmin('superadmin', 'Superadministrador');

  const Rol(this.codigo, this.nombre);
  final String codigo;
  final String nombre;

  static Rol? desdeCodigo(String? codigo) {
    for (final r in Rol.values) {
      if (r.codigo == codigo) return r;
    }
    return null;
  }

  bool get privilegiado => this == Rol.adminSistema || this == Rol.gerenteGeneral || this == Rol.superadmin;

  /// Ve y hace lo mismo que el gerente general (el superadministrador incluye todos los roles).
  bool get comoGerente => this == Rol.gerenteGeneral || this == Rol.superadmin;

  /// Los 5 roles de la matriz de permisos de la tesis (sin el superadministrador).
  static List<Rol> get deLaMatriz => Rol.values.where((r) => r != Rol.superadmin).toList();

  String get nombreCorto => switch (this) {
        Rol.adminSistema => 'Administrador',
        Rol.operadorCentro => 'Operador',
        Rol.ejecutivoComercial => 'Ejecutivo',
        Rol.cajeroContador => 'Cajero',
        Rol.gerenteGeneral => 'Gerente',
        Rol.superadmin => 'Superadmin',
      };
}

/// Letras de la matriz: R registra o ejecuta, S solicita, A aprueba, C consulta, V verifica.
enum Acceso { r, s, a, c, v }

extension AccesoTexto on Acceso {
  String get letra => name.toUpperCase();
  String get descripcion => switch (this) {
        Acceso.r => 'Registra o ejecuta',
        Acceso.s => 'Solicita',
        Acceso.a => 'Aprueba',
        Acceso.c => 'Consulta',
        Acceso.v => 'Verifica',
      };
}

class OperacionMatriz {
  const OperacionMatriz(this.modulo, this.operacion, this.accesos);
  final String modulo;
  final String operacion;
  final Map<Rol, List<Acceso>> accesos;
}

const _ad = Rol.adminSistema, _op = Rol.operadorCentro, _ej = Rol.ejecutivoComercial,
    _ca = Rol.cajeroContador, _ge = Rol.gerenteGeneral;
const _r = Acceso.r, _s = Acceso.s, _a = Acceso.a, _c = Acceso.c, _v = Acceso.v;

/// Matriz de permisos por operación y por rol (Tabla de la sección 3.1 de la tesis).
const List<OperacionMatriz> matrizPermisos = [
  OperacionMatriz('Seguridad', 'Alta y suspensión de cuentas operativas', {_ad: [_r], _ge: [_c]}),
  OperacionMatriz('Seguridad', 'Asignación de roles privilegiados', {_ad: [_s], _ge: [_a]}),
  OperacionMatriz('Seguridad', 'Contraseñas y cierre de sesiones', {_ad: [_r], _ge: [_c]}),
  OperacionMatriz('Seguridad', 'Consulta de la bitácora', {_ad: [_c], _ge: [_c]}),
  OperacionMatriz('Seguridad', 'Respaldo / restauración', {_ad: [_r, _s], _ge: [_a]}),
  OperacionMatriz('Operaciones', 'Registro de pesaje', {_op: [_r], _ge: [_c]}),
  OperacionMatriz('Operaciones', 'Corrección de pesaje confirmado', {_op: [_s], _ge: [_a]}),
  OperacionMatriz('Operaciones', 'Orden de ensilado y cierre de lote', {_op: [_r], _ge: [_c]}),
  OperacionMatriz('Operaciones', 'Consumo de insumos', {_op: [_r], _ge: [_c]}),
  OperacionMatriz('Operaciones', 'Revisión de fermentación', {_op: [_r], _ge: [_c]}),
  OperacionMatriz('Inventario', 'Stock por lote y por sede', {_op: [_c], _ej: [_c], _ge: [_c]}),
  OperacionMatriz('Inventario', 'Catálogo y lista de precios', {_ej: [_s], _ge: [_a]}),
  OperacionMatriz('Inventario', 'Emisión de guía de transferencia', {_op: [_r], _ej: [_c], _ge: [_c]}),
  OperacionMatriz('Inventario', 'Recepción de guía', {_op: [_v], _ge: [_c]}),
  OperacionMatriz('Inventario', 'Merma o ajuste por conteo', {_op: [_s], _ge: [_a]}),
  OperacionMatriz('Comercial', 'Clientes y proveedores', {_ej: [_r], _ca: [_c], _ge: [_c]}),
  OperacionMatriz('Comercial', 'Activación de proveedor y límite de crédito', {_ej: [_s], _ge: [_a]}),
  OperacionMatriz('Comercial', 'Compra de grano o insumos', {_ej: [_r], _ca: [_c], _ge: [_a]}),
  OperacionMatriz('Comercial', 'Pago a proveedor', {_ej: [_c], _ca: [_r], _ge: [_c]}),
  OperacionMatriz('Comercial', 'Cotización y pedido', {_ej: [_r], _ge: [_c]}),
  OperacionMatriz('Comercial', 'Nota de venta', {_ej: [_r], _ca: [_c], _ge: [_c]}),
  OperacionMatriz('Comercial', 'Descuento o venta sobre el límite de crédito', {_ej: [_s], _ge: [_a]}),
  OperacionMatriz('Comercial', 'Cobro de nota de venta', {_ej: [_c], _ca: [_r], _ge: [_c]}),
  OperacionMatriz('Comercial', 'Anulación de venta / de cobro', {_ej: [_s], _ca: [_s], _ge: [_a]}),
  OperacionMatriz('Comercial', 'Despacho y entrega', {_op: [_r], _ej: [_c], _ge: [_c]}),
  OperacionMatriz('Reportes', 'Producción, rendimiento y merma', {_op: [_c], _ge: [_c]}),
  OperacionMatriz('Reportes', 'Ventas, cartera y rotación', {_ej: [_c], _ca: [_c], _ge: [_c]}),
];

/// Submódulos de la Figura 7 (5 módulos, 23 submódulos) y qué roles los usan.
enum Submodulo {
  usuarios('Gestión de Usuarios', 'RF-01', {_ad, _ge}),
  rbac('Control de Acceso Basado en Roles', 'RF-02', {_ad, _op, _ej, _ca, _ge}),
  politicas('Políticas de Contraseñas', 'RF-03', {_ad}),
  sesiones('Autenticación y Sesiones', 'RF-04', {_ad, _ge}),
  bitacora('Bitácora de Eventos', 'RF-05', {_ad, _ge}),
  mantenimiento('Mantenimiento y Operaciones de la Base de Datos', 'RF-06', {_ad, _ge}),
  bascula('Recepción y Báscula', 'RF-07', {_op, _ge}),
  ordenes('Orden de Producción / Ensilado', 'RF-08', {_op, _ge}),
  insumos('Consumo de Insumos', 'RF-09', {_op, _ge}),
  fermentacion('Control de Fermentación y Calidad', 'RF-10', {_op, _ge}),
  stockLotes('Control de Stock por Lotes y Trazabilidad', 'RF-11', {_op, _ej, _ge}),
  multisede('Gestión Multisede', 'RF-12', {_op, _ej, _ge}),
  catalogo('Catálogo de Productos', 'RF-13', {_ej, _ca, _ge}),
  guias('Guías de Remisión y Transferencia', 'RF-14', {_op, _ej, _ge}),
  clientesProveedores('Gestión de Clientes y Proveedores', 'RF-15', {_ej, _ca, _ge}),
  compras('Registro de Compras de Materia Prima e Insumos', 'RF-16', {_ej, _ca, _ge}),
  pedidos('Cotización y Pedidos', 'RF-17', {_ej, _ge}),
  ventas('Facturación y Ventas', 'RF-18', {_ej, _ca, _ge}),
  despachos('Control de Despachos', 'RF-19', {_op, _ej, _ge}),
  reporteRendimiento('Rendimiento y Producción de Ensilado', 'RF-20', {_op, _ge}),
  reporteExistencias('Existencias y Rotación por Sede', 'RF-21', {_op, _ej, _ca, _ge}),
  reporteVentas('Reporte de Ventas por Producto', 'RF-22', {_ej, _ca, _ge}),
  reporteMermas('Histórico de Pérdidas y Merma', 'RF-23', {_op, _ge});

  const Submodulo(this.titulo, this.requerimiento, this.roles);
  final String titulo;
  final String requerimiento;
  final Set<Rol> roles;

  bool permitido(Rol? rol) => rol == Rol.superadmin || (rol != null && roles.contains(rol));
}

/// Acciones concretas que la interfaz oculta según el rol (la API y la base vuelven a validarlas).
enum Accion {
  crearUsuario({_ad}),
  aprobarSolicitudes({_ge}),
  cambiarPoliticas({_ad}),
  cerrarSesiones({_ad}),
  pedirRespaldo({_ad}),
  registrarPesaje({_op}),
  cerrarOrden({_op}),
  registrarConsumo({_op}),
  revisarFermentacion({_op}),
  solicitarMerma({_op}),
  emitirGuia({_op}),
  recibirGuia({_op}),
  proponerProducto({_ej}),
  registrarClienteProveedor({_ej}),
  registrarCompra({_ej}),
  registrarPago({_ca}),
  registrarPedido({_ej}),
  emitirNotaVenta({_ej}),
  registrarCobro({_ca}),
  solicitarAnulacionVenta({_ej}),
  solicitarAnulacionCobro({_ca}),
  registrarDespacho({_op}),
  verPrecios({_ej, _ca, _ge});

  const Accion(this.roles);
  final Set<Rol> roles;
  bool permitida(Rol? rol) => rol == Rol.superadmin || (rol != null && roles.contains(rol));
}
