-- Migración 20261118113851 «reportes_respetan_rls», copiada del historial de Supabase (supabase_migrations.schema_migrations).
-- En una base nueva las vistas se crean después (20261118193845, ya con security_invoker); aquí solo se ajustan si existen.
do $$ begin
  if to_regclass('public.v_reporte_rendimiento_ensilado') is not null then
    alter view public.v_reporte_rendimiento_ensilado set (security_invoker = true);
    alter view public.v_reporte_existencias_rotacion set (security_invoker = true);
    alter view public.v_reporte_ventas_producto set (security_invoker = true);
    alter view public.v_reporte_historico_mermas set (security_invoker = true);
    revoke all on public.v_reporte_rendimiento_ensilado, public.v_reporte_existencias_rotacion,
      public.v_reporte_ventas_producto, public.v_reporte_historico_mermas from anon;
  end if;
end $$;
