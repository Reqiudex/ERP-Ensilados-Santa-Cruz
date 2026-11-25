-- Auditoría de la app del 25 de noviembre de 2026.
--  1. RBAC (RF-02): la tabla de roles solo la leen por la API el administrador del sistema, el gerente general y el
--     superadministrador (app.es incluye siempre al superadministrador). Las funciones del servidor que usan los roles
--     son SECURITY DEFINER y no dependen de esta política.
--  2. Reenvíos de la cola del teléfono: un pesaje u orden que ya está en el servidor (la respuesta anterior se perdió)
--     no se vuelve a validar, así el reenvío se ignora en lugar de rechazarse si la orden se cerró mientras tanto.
--  3. Permisos que la API no usa: sin TRUNCATE ni TRIGGER para las cuentas y sin escritura sobre las vistas de reportes.

-- ---------------------------------------------------------------- 1. Matriz de permisos solo para admin y gerente
drop policy if exists roles_solo_admin_gerente on public.roles;
create policy roles_solo_admin_gerente on public.roles as restrictive for select to authenticated
  using (app.es('admin_sistema', 'gerente_general'));

-- ---------------------------------------------------------------- 2. Reenvío de registros ya guardados
create or replace function app.registro_ya_guardado(p_tabla text, p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select case p_tabla
           when 'pesajes' then exists (select 1 from public.pesajes where id = p_id)
           when 'ordenes_ensilado' then exists (select 1 from public.ordenes_ensilado where id = p_id)
           else false
         end
$$;
revoke all on function app.registro_ya_guardado(text, uuid) from public, anon;
grant execute on function app.registro_ya_guardado(text, uuid) to authenticated;

do $$
declare d text;
begin
  d := pg_get_functiondef('app.validar_registro_campo()'::regprocedure);
  if position('app.registro_ya_guardado' in d) = 0 then
    if position(E'  if current_user::text <> ''authenticated'' then\n    return new;\n  end if;' in d) = 0 then
      raise exception 'validar_registro_campo no tiene el texto esperado';
    end if;
    d := replace(d, E'  if current_user::text <> ''authenticated'' then\n    return new;\n  end if;',
      E'  if current_user::text <> ''authenticated'' then\n    return new;\n  end if;\n'
      || E'  -- Reenvío de la cola: la fila ya existe y la inserción se ignorará (ON CONFLICT DO NOTHING).\n'
      || E'  if app.registro_ya_guardado(tg_table_name, (v ->> ''id'')::uuid) then\n    return new;\n  end if;');
    execute d;
  end if;
end $$;

-- ---------------------------------------------------------------- 3. Permisos que la API no necesita
do $$
declare t record;
begin
  for t in select c.relname, c.relkind from pg_class c
            where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v') loop
    execute format('revoke truncate, trigger on public.%I from anon, authenticated', t.relname);
    if t.relkind = 'v' then
      execute format('revoke insert, update, delete on public.%I from anon, authenticated', t.relname);
    end if;
  end loop;
end $$;
