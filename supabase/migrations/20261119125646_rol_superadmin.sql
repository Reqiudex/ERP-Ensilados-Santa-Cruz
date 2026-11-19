-- Rol superadministrador: pasa todos los controles de rol, trabaja en cualquier sede y queda exento de la
-- separación registro–aprobación. Solo otro superadministrador (o el mantenimiento del servidor) puede asignarlo.

insert into public.roles (id, codigo, nombre, privilegiado)
values (6, 'superadmin', 'Superadministrador', true)
on conflict (id) do update set codigo = excluded.codigo, nombre = excluded.nombre, privilegiado = excluded.privilegiado;

-- Todos los controles de rol pasan por app.es(): el superadministrador cumple cualquiera.
create or replace function app.es(variadic roles_permitidos text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(app.rol() = any(roles_permitidos) or app.rol() = 'superadmin', false)
$$;

-- Único filtro que restringe cuando el usuario ES operador: se compara con el rol exacto para que el
-- superadministrador vea todas las sedes en el reporte de existencias.
do $$
declare
  f record;
begin
  for f in select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prosrc like '%not app.es(''operador_centro'') or%' loop
    execute replace(pg_get_functiondef(f.oid), 'not app.es(''operador_centro'') or',
                    'app.rol() is distinct from ''operador_centro'' or');
  end loop;
end $$;

-- Sede de trabajo: el superadministrador elige en qué sede opera (para registrar como operador de un centro).
create or replace function public.cambiar_sede_trabajo(p_sede uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if app.rol() is distinct from 'superadmin' then
    return app.denegar('usuarios', 'Solo el superadministrador cambia de sede de trabajo.');
  end if;
  if not exists (select 1 from public.sedes where id = p_sede and activa) then
    raise exception 'Seleccione una sede válida.';
  end if;
  update public.usuarios set sede_id = p_sede where id = (select auth.uid());
  return jsonb_build_object('ok', true, 'sede_id', p_sede);
end $$;
revoke all on function public.cambiar_sede_trabajo(uuid) from public, anon;
grant execute on function public.cambiar_sede_trabajo(uuid) to authenticated;

-- Separación de funciones: las restricciones CHECK pasan a un disparador con el mismo código de error (23514) y el
-- mismo nombre de restricción, que exceptúa al superadministrador.
create or replace function app.separacion_funciones() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid;
  v_otro uuid;
  v_nombre text;
begin
  if tg_table_name = 'guias_transferencia' then
    v_actor := new.recibido_por; v_otro := new.emitido_por; v_nombre := 'guias_transferencia_check1';
  else
    v_actor := new.aprobado_por; v_otro := new.registrado_por;
    v_nombre := case tg_table_name when 'compras' then 'compras_check1' else 'solicitudes_aprobacion_check' end;
  end if;
  if v_actor is not null and v_actor = v_otro and not exists (
       select 1 from public.usuarios u join public.roles r on r.id = u.rol_id
        where u.id = v_actor and r.codigo = 'superadmin') then
    raise exception using errcode = '23514', constraint = v_nombre,
      message = format('new row for relation "%s" violates check constraint "%s"', tg_table_name, v_nombre);
  end if;
  return new;
end $$;

alter table public.solicitudes_aprobacion drop constraint if exists solicitudes_aprobacion_check;
alter table public.compras drop constraint if exists compras_check1;
alter table public.guias_transferencia drop constraint if exists guias_transferencia_check1;

drop trigger if exists trg_separacion_funciones on public.solicitudes_aprobacion;
create trigger trg_separacion_funciones before insert or update of aprobado_por, registrado_por
  on public.solicitudes_aprobacion for each row execute function app.separacion_funciones();
drop trigger if exists trg_separacion_funciones on public.compras;
create trigger trg_separacion_funciones before insert or update of aprobado_por, registrado_por
  on public.compras for each row execute function app.separacion_funciones();
drop trigger if exists trg_separacion_funciones on public.guias_transferencia;
create trigger trg_separacion_funciones before insert or update of recibido_por, emitido_por
  on public.guias_transferencia for each row execute function app.separacion_funciones();

-- Nadie se otorga el rol superadministrador desde la aplicación salvo otro superadministrador.
create or replace function app.proteger_superadmin() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.rol_id = 6 and (tg_op = 'INSERT' or old.rol_id is distinct from 6)
     and (select auth.uid()) is not null and app.rol() is distinct from 'superadmin' then
    raise exception 'Solo un superadministrador asigna el rol de superadministrador.' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists trg_proteger_superadmin on public.usuarios;
create trigger trg_proteger_superadmin before insert or update of rol_id on public.usuarios
  for each row execute function app.proteger_superadmin();
