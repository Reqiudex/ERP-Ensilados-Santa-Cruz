-- Índices para todas las llaves foráneas sin índice (avisos de rendimiento de Supabase)
do $$ declare r record; begin
  for r in
    select c.conrelid::regclass as tabla, c.conname, a.attname as columna, n.nspname, t.relname
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
     where c.contype = 'f' and n.nspname in ('public', 'app') and array_length(c.conkey, 1) = 1
       and not exists (select 1 from pg_index i where i.indrelid = c.conrelid and i.indkey[0] = c.conkey[1])
  loop
    execute format('create index if not exists %I on %s (%I)', 'idx_' || r.relname || '_' || r.columna, r.tabla, r.columna);
  end loop;
end $$;

-- Una sola política de lectura de lotes (antes eran tres permisivas)
drop policy if exists lotes_lectura on public.lotes;
drop policy if exists lotes_lectura_por_stock on public.lotes;
drop policy if exists lotes_lectura_por_guia on public.lotes;
create policy lotes_lectura on public.lotes for select to authenticated
  using (
    app.es('ejecutivo_comercial', 'gerente_general')
    or (app.es('operador_centro') and (
          sede_id = app.sede()
       or exists (select 1 from public.existencias e where e.lote_id = lotes.id and e.sede_id = app.sede())
       or exists (select 1 from public.guia_detalle d join public.guias_transferencia g on g.id = d.guia_id
                   where d.lote_id = lotes.id and app.sede() in (g.sede_origen, g.sede_destino)))));
