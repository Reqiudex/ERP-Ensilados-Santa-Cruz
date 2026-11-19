-- Migración 20261118185006 «documento_tipo_solicitud», copiada del historial de Supabase (supabase_migrations.schema_migrations).
-- documento_tipo es varchar(20): los movimientos aprobados por solicitud usan 'solicitud'
do $$ declare src text; begin
  select pg_get_functiondef('app.aplicar_solicitud(public.solicitudes_aprobacion)'::regprocedure) into src;
  execute replace(src, '''solicitudes_aprobacion'', s.id', '''solicitud'', s.id');
end $$;
