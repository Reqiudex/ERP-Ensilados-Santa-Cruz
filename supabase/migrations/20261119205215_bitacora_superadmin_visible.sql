-- Las acciones del superadministrador quedan visibles en la bitácora como las de cualquier cuenta (RNF-03, RNF-04).
-- Se quita el ocultamiento de las migraciones 20261119130047 y 20261119130212; el resto del ocultamiento
-- (gestión de usuarios, sesiones, roles) no cambia.
drop policy if exists bitacora_superadmin_oculto on public.bitacora_eventos;
drop function if exists app.menciona_oculto(text);

-- Nombre de quien registró y de quien aprobó cada evento. Son columnas calculadas para PostgREST: así la bitácora
-- muestra el nombre aunque la cuenta no sea visible en Gestión de usuarios. Solo devuelven el nombre de usuarios
-- citados en filas de la bitácora que el rol ya puede leer (administrador y gerente).
create or replace function public.nombre_registro(b public.bitacora_eventos) returns text
language sql stable security definer set search_path = '' as $$
  select u.nombre_completo from public.usuarios u where u.id = b.usuario_id
$$;
create or replace function public.nombre_aprobador(b public.bitacora_eventos) returns text
language sql stable security definer set search_path = '' as $$
  select u.nombre_completo from public.usuarios u where u.id = b.aprobador_id
$$;
revoke all on function public.nombre_registro(public.bitacora_eventos), public.nombre_aprobador(public.bitacora_eventos) from public, anon;
grant execute on function public.nombre_registro(public.bitacora_eventos), public.nombre_aprobador(public.bitacora_eventos) to authenticated;

-- El respaldo conserva la bitácora completa (es el registro de auditoría); solo se omiten las filas de cuentas ocultas
-- en las demás tablas.
create or replace function app.exportar_datos() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t record; v_tablas jsonb := '{}'; v_filas jsonb; v_ocultos text[];
begin
  select coalesce(array_agg(u.id::text), '{}') into v_ocultos
    from public.usuarios u join public.roles r on r.id = u.rol_id where r.codigo = 'superadmin';
  for t in select tablename from pg_tables where schemaname = 'public' order by tablename loop
    if t.tablename = 'bitacora_eventos' then
      execute 'select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from public.bitacora_eventos x' into v_filas;
    else
      execute format($q$select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.%I x
                        where not (to_jsonb(x)::text ilike '%%superadmin%%'
                                   or exists (select 1 from unnest($1) o where position(o in to_jsonb(x)::text) > 0))$q$,
                     t.tablename)
        into v_filas using v_ocultos;
    end if;
    v_tablas := v_tablas || jsonb_build_object(t.tablename, v_filas);
  end loop;
  v_tablas := v_tablas || jsonb_build_object('parametros',
    (select coalesce(jsonb_agg(jsonb_build_object('clave', p.clave, 'valor', p.valor)), '[]') from app.parametros p));
  return jsonb_build_object(
    'sistema', 'ERP Ensilados Santa Cruz',
    'formato', 'respaldo-json-v1',
    'generado_en', now(),
    'version_postgres', split_part(version(), ' ', 2),
    'tablas', v_tablas);
end $$;
revoke all on function app.exportar_datos() from public, anon, authenticated;
