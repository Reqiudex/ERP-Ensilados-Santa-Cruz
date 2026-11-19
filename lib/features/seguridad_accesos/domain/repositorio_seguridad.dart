import 'perfil.dart';
import 'servicio_seguridad.dart';

export 'servicio_seguridad.dart' show OperacionNoPermitida;

typedef Registro = Map<String, dynamic>;

/// Contrato del módulo Seguridad y Accesos (la implementación vive en data/).
abstract interface class RepositorioSeguridad {
  // RF-04 Autenticación y sesiones
  Future<Perfil> iniciarSesion(String identificador, String clave);
  Future<Perfil?> perfilActual();
  Future<void> cerrarSesion();
  Future<void> cambiarMiClave(String actual, String nueva);
  Future<List<Registro>> sesionesActivas();
  Future<int> cerrarSesiones(String? usuarioId);

  /// Revoca una sesión concreta («matar sesión»): el servidor la rechaza en el mismo instante.
  Future<void> revocarSesion(String sesionId);

  /// Indica si la sesión de este dispositivo sigue vigente (no fue revocada).
  Future<bool> sesionVigente();

  /// Confirma la contraseña del usuario actual antes de una acción sensible.
  Future<bool> verificarMiClave(String clave);

  // RF-01 Gestión de usuarios
  Future<List<Registro>> usuarios();
  Future<List<Registro>> sedes();

  /// Solo el superadministrador: cambia la sede desde la que trabaja.
  Future<void> cambiarSedeTrabajo(String sedeId);
  Future<Registro> crearUsuario(Registro datos);
  Future<Registro> editarUsuario(String id, Registro datos);
  Future<void> cambiarEstadoUsuario(String id, String accion);
  Future<void> restablecerClave(String id, String clave);

  /// Campos que ya existen en otra cuenta: 'nombre', 'ci' o 'correo'.
  Future<List<String>> duplicadosUsuario(String nombre, String ci, String correo, {String? excluir});

  // RF-02 Aprobaciones
  Future<List<Registro>> bandeja(String estado);
  Future<void> resolverSolicitud(String id, bool aprobar, String? motivo);
  Future<List<Registro>> misSolicitudes();

  // RF-03 y RF-06 Parámetros y mantenimiento
  Future<Map<String, dynamic>> parametros();
  Future<void> guardarParametros(Map<String, dynamic> valores);
  Future<List<Registro>> granos();
  Future<void> actualizarGrano(int id, double humedad, int dias, double minimo, double maximo);
  Future<List<Registro>> respaldos();
  Future<void> pedirRespaldo();
  Future<void> solicitarRestauracion(String respaldo, String motivo);
  Future<int> optimizarBase();

  // RF-05 Bitácora
  Future<List<Registro>> bitacora({DateTime? desde, DateTime? hasta, String? accion, String? tabla, String? usuarioId});

  /// Guardia WORM: la bitácora no se modifica ni se borra; ambas operaciones lanzan [OperacionNoPermitida].
  Future<void> modificarEvento(int id, Registro datos);
  Future<void> eliminarEvento(int id);
}
