/// Configuración pública del proyecto Supabase.
/// Solo la URL y la clave publicable: la seguridad la da RLS. Las claves secretas
/// (service_role / sb_secret) van únicamente en Secrets de GitHub, nunca en el código.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = 'https://gklicbxcfomgesljhtyq.supabase.co';

  /// Clave publicable (pública por diseño).
  static const String publishableKey = 'sb_publishable_GAEpmMhT4njOVXhkJvrGwA_DqjXORjk';
}
