import 'perfil.dart';

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

  // RF-01 Gestión de usuarios
  Future<List<Registro>> usuarios();
  Future<List<Registro>> sedes();
  Future<Registro> crearUsuario(Registro datos);
  Future<Registro> editarUsuario(String id, Registro datos);
  Future<void> cambiarEstadoUsuario(String id, String accion);
  Future<void> restablecerClave(String id, String clave);

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

  // RF-05 Bitácora
  Future<List<Registro>> bitacora({DateTime? desde, DateTime? hasta, String? accion, String? tabla, String? usuarioId});
}
