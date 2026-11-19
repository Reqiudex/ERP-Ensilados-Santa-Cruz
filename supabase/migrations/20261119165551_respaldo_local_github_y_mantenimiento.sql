-- Respaldo local (PC del administrador), copia externa en GitHub (token cifrado en Vault), programación con pg_cron
-- y mantenimiento automático diario.
create extension if not exists pg_net schema extensions;
create extension if not exists pg_cron;

-- Datos completos de la base en JSON (tablas del esquema public y parámetros). Excluye filas de cuentas ocultas.
create or replace function app.exportar_datos() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t record; v_tablas jsonb := '{}'; v_filas jsonb; v_ocultos text[];
begin
  select coalesce(array_agg(u.id::text), '{}') into v_ocultos
    from public.usuarios u join public.roles r on r.id = u.rol_id where r.codigo = 'superadmin';
  for t in select tablename from pg_tables where schemaname = 'public' order by tablename loop
    execute format($q$select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.%I x
                      where not (to_jsonb(x)::text ilike '%%superadmin%%'
                                 or exists (select 1 from unnest($1) o where position(o in to_jsonb(x)::text) > 0))$q$,
                   t.tablename)
      into v_filas using v_ocultos;
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

-- Respaldo local: el administrador descarga los datos y los guarda en la carpeta que elija.
create or replace function public.exportar_respaldo() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb;
begin
  if not app.es('admin_sistema') then
    return app.denegar('respaldos', 'Solo el administrador genera respaldos.');
  end if;
  v := app.exportar_datos();
  perform app.evento('respaldo', 'respaldos', null, jsonb_build_object('destino', 'local',
    'archivo', 'respaldo_local_' || to_char(now() at time zone 'America/La_Paz', 'YYYY-MM-DD_HH24MI') || '.json',
    'bytes', length(v::text), 'sha256', encode(extensions.digest(v::text, 'sha256'), 'hex')));
  return v;
end $$;
revoke all on function public.exportar_respaldo() from public, anon;
grant execute on function public.exportar_respaldo() to authenticated;

-- Destino externo: repositorio de GitHub del administrador. El token se guarda cifrado en Vault y nunca se devuelve.
create table if not exists app.destino_github (
  id boolean primary key default true check (id),
  repositorio text not null,
  cuenta text not null,
  rama text not null default 'main',
  vinculado_por uuid,
  vinculado_en timestamptz not null default now()
);
alter table app.destino_github enable row level security;

create or replace function public.vincular_github(p_repositorio text, p_cuenta text, p_token text, p_rama text default 'main')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not app.es('admin_sistema') then
    return app.denegar('respaldos', 'Solo el administrador vincula la cuenta de GitHub.');
  end if;
  if p_repositorio !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' then raise exception 'Repositorio no válido (use usuario/repositorio).'; end if;
  if coalesce(length(p_token), 0) < 20 then raise exception 'Token de GitHub no válido.'; end if;
  select id into v_id from vault.secrets where name = 'github_respaldo_token';
  if v_id is null then
    perform vault.create_secret(p_token, 'github_respaldo_token', 'Token de GitHub para respaldos externos');
  else
    perform vault.update_secret(v_id, p_token);
  end if;
  insert into app.destino_github (id, repositorio, cuenta, rama, vinculado_por, vinculado_en)
  values (true, p_repositorio, p_cuenta, coalesce(nullif(p_rama, ''), 'main'), (select auth.uid()), now())
  on conflict (id) do update set repositorio = excluded.repositorio, cuenta = excluded.cuenta, rama = excluded.rama,
    vinculado_por = excluded.vinculado_por, vinculado_en = excluded.vinculado_en;
  perform app.evento('github_vinculado', 'respaldos', null, jsonb_build_object('repositorio', p_repositorio, 'cuenta', p_cuenta));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.desvincular_github() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('admin_sistema') then
    return app.denegar('respaldos', 'Solo el administrador desvincula la cuenta de GitHub.');
  end if;
  delete from vault.secrets where name = 'github_respaldo_token';
  delete from app.destino_github;
  perform app.evento('github_desvinculado', 'respaldos', null, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.estado_github() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('admin_sistema', 'gerente_general') then
    return app.denegar('respaldos', 'Solo el administrador y el gerente consultan los respaldos.');
  end if;
  return coalesce((select jsonb_build_object('vinculado', true, 'repositorio', d.repositorio, 'cuenta', d.cuenta,
                    'rama', d.rama, 'vinculado_en', d.vinculado_en) from app.destino_github d),
                  jsonb_build_object('vinculado', false));
end $$;

-- Pedido de copia a GitHub hecho por el administrador desde la app (lo verifica la función del servidor).
create or replace function public.autorizar_respaldo_github() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('admin_sistema') then
    return app.denegar('respaldos', 'Solo el administrador envía respaldos a GitHub.');
  end if;
  return jsonb_build_object('ok', true, 'usuario', (select auth.uid()));
end $$;

-- Solo para la función del servidor (service_role): token, destino y datos.
create or replace function public.preparar_respaldo_github() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare d app.destino_github;
begin
  select * into d from app.destino_github;
  if d.repositorio is null then return jsonb_build_object('vinculado', false); end if;
  return jsonb_build_object('vinculado', true, 'repositorio', d.repositorio, 'rama', d.rama,
    'token', (select decrypted_secret from vault.decrypted_secrets where name = 'github_respaldo_token'),
    'retencion_dias', (app.parametro('respaldo_retencion_dias'))::text::int,
    'datos', app.exportar_datos());
end $$;

create or replace function public.registrar_respaldo_github(p_usuario uuid, p_datos jsonb) returns jsonb
language sql security definer set search_path = '' as $$
  insert into public.bitacora_eventos (usuario_id, accion, tabla, registro_id, datos_despues, ip)
  values ((select u.id from public.usuarios u where u.id = p_usuario),
          case when p_datos ? 'error' then 'respaldo_fallido' else 'respaldo' end, 'respaldos', null, p_datos, null)
  returning jsonb_build_object('ok', true);
$$;

create or replace function public.clave_cron_valida(p_clave text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from vault.decrypted_secrets where name = 'respaldo_cron_clave' and decrypted_secret = p_clave)
$$;

revoke all on function public.vincular_github(text, text, text, text), public.desvincular_github(), public.estado_github(),
  public.autorizar_respaldo_github() from public, anon;
grant execute on function public.vincular_github(text, text, text, text), public.desvincular_github(), public.estado_github(),
  public.autorizar_respaldo_github() to authenticated;
revoke all on function public.preparar_respaldo_github(), public.registrar_respaldo_github(uuid, jsonb),
  public.clave_cron_valida(text) from public, anon, authenticated;
grant execute on function public.preparar_respaldo_github(), public.registrar_respaldo_github(uuid, jsonb),
  public.clave_cron_valida(text) to service_role;

-- Clave interna con la que la tarea programada llama a la función de respaldo.
do $$ begin
  if not exists (select 1 from vault.secrets where name = 'respaldo_cron_clave') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'respaldo_cron_clave', 'Clave interna de la tarea de respaldo');
  end if;
end $$;

-- Tarea programada: cada hora revisa la programación (activo, frecuencia, hora de Bolivia) y, si corresponde,
-- pide la copia a GitHub.
create or replace function app.respaldo_programado() returns void
language plpgsql security definer set search_path = '' as $$
declare v_hora text := to_char(now() at time zone 'UTC', 'HH24') || ':00'; v_frec text;
begin
  if coalesce((app.parametro('respaldo_activo'))::text::boolean, false) is not true then return; end if;
  if not exists (select 1 from app.destino_github) then return; end if;
  if v_hora <> app.parametro('respaldo_hora_utc') #>> '{}' then return; end if;
  v_frec := app.parametro('respaldo_frecuencia') #>> '{}';
  if v_frec = 'semanal' and extract(isodow from now() at time zone 'America/La_Paz') <> 1 then return; end if;
  if v_frec = 'mensual' and extract(day from now() at time zone 'America/La_Paz') <> 1 then return; end if;
  perform net.http_post(
    url := 'https://gklicbxcfomgesljhtyq.supabase.co/functions/v1/respaldo-github',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-clave-cron',
                 (select decrypted_secret from vault.decrypted_secrets where name = 'respaldo_cron_clave')),
    body := jsonb_build_object('origen', 'programado'),
    timeout_milliseconds := 60000);
end $$;

-- Mantenimiento automático diario: actualiza las estadísticas de todas las tablas y lo registra en la bitácora.
create or replace function app.mantenimiento_automatico() returns void
language plpgsql security definer set search_path = '' as $$
declare t record; n int := 0;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('analyze public.%I', t.tablename);
    n := n + 1;
  end loop;
  insert into public.bitacora_eventos (usuario_id, accion, tabla, registro_id, datos_despues, ip)
  values (null, 'optimizacion', 'respaldos', null, jsonb_build_object('tablas', n, 'automatico', true), null);
end $$;
revoke all on function app.respaldo_programado(), app.mantenimiento_automatico() from public, anon, authenticated;

select cron.unschedule(jobname) from cron.job where jobname in ('respaldo-programado', 'mantenimiento-automatico');
select cron.schedule('respaldo-programado', '5 * * * *', 'select app.respaldo_programado()');
select cron.schedule('mantenimiento-automatico', '0 8 * * *', 'select app.mantenimiento_automatico()');

-- Estado del mantenimiento automático para la pantalla.
create or replace function public.estado_mantenimiento() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('admin_sistema', 'gerente_general') then
    return app.denegar('respaldos', 'Solo el administrador y el gerente consultan el mantenimiento.');
  end if;
  return jsonb_build_object(
    'ultima', (select max(fecha_servidor) from public.bitacora_eventos where accion = 'optimizacion'),
    'programacion', 'Todos los días a las 04:00 (Bolivia)');
end $$;
revoke all on function public.estado_mantenimiento() from public, anon;
grant execute on function public.estado_mantenimiento() to authenticated;
