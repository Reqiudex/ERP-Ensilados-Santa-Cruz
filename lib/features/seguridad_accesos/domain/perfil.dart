import 'roles_y_permisos.dart';

/// Usuario autenticado con su rol y sede (lo devuelve la función registrar_ingreso).
class Perfil {
  const Perfil({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.ci,
    required this.rol,
    required this.sedeId,
    required this.sede,
    required this.sedeTipo,
    required this.debeCambiarClave,
    required this.parametros,
  });

  factory Perfil.desdeJson(Map<String, dynamic> j) => Perfil(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        correo: j['correo'] as String,
        ci: j['ci'] as String,
        rol: Rol.desdeCodigo(j['rol'] as String?) ?? Rol.operadorCentro,
        sedeId: j['sede_id'] as String,
        sede: j['sede'] as String,
        sedeTipo: j['sede_tipo'] as String? ?? 'oficina',
        debeCambiarClave: j['debe_cambiar_clave'] as bool? ?? false,
        parametros: Map<String, dynamic>.from(j['parametros'] as Map? ?? const {}),
      );

  Map<String, dynamic> aJson() => {
        'id': id,
        'nombre': nombre,
        'correo': correo,
        'ci': ci,
        'rol': rol.codigo,
        'sede_id': sedeId,
        'sede': sede,
        'sede_tipo': sedeTipo,
        'debe_cambiar_clave': debeCambiarClave,
        'parametros': parametros,
      };

  final String id;
  final String nombre;
  final String correo;
  final String ci;
  final Rol rol;
  final String sedeId;
  final String sede;
  final String sedeTipo;
  final bool debeCambiarClave;
  final Map<String, dynamic> parametros;

  int get minutosInactividad => (parametros['inactividad_minutos'] as num?)?.toInt() ?? 15;
  double get toleranciaDespacho => (parametros['tolerancia_despacho_pct'] as num?)?.toDouble() ?? 5;

  String get iniciales {
    final p = nombre.trim().split(RegExp(r'\s+'));
    return (p.first[0] + (p.length > 1 ? p[1][0] : '')).toUpperCase();
  }

  Perfil copiar({bool? debeCambiarClave}) => Perfil(
        id: id,
        nombre: nombre,
        correo: correo,
        ci: ci,
        rol: rol,
        sedeId: sedeId,
        sede: sede,
        sedeTipo: sedeTipo,
        debeCambiarClave: debeCambiarClave ?? this.debeCambiarClave,
        parametros: parametros,
      );
}
