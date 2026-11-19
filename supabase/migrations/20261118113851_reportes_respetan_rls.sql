-- Migración 20261118113851 «reportes_respetan_rls», copiada del historial de Supabase (supabase_migrations.schema_migrations).
alter view public.v_reporte_rendimiento_ensilado set (security_invoker = true);
alter view public.v_reporte_existencias_rotacion set (security_invoker = true);
alter view public.v_reporte_ventas_producto set (security_invoker = true);
alter view public.v_reporte_historico_mermas set (security_invoker = true);
revoke all on public.v_reporte_rendimiento_ensilado, public.v_reporte_existencias_rotacion,
  public.v_reporte_ventas_producto, public.v_reporte_historico_mermas from anon;;
