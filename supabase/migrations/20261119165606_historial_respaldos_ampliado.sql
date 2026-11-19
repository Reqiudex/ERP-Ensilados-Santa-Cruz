create or replace function public.respaldos() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('admin_sistema', 'gerente_general') then
    return app.denegar('respaldos', 'Solo el administrador y el gerente consultan los respaldos.');
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'accion', b.accion,
      'fecha', b.fecha_servidor, 'datos', b.datos_despues) order by b.fecha_servidor desc)
    from (select * from public.bitacora_eventos
           where accion in ('respaldo', 'respaldo_pedido', 'restauracion', 'respaldo_fallido', 'optimizacion',
                            'github_vinculado', 'github_desvinculado')
           order by fecha_servidor desc limit 60) b), '[]'::jsonb);
end $$;
