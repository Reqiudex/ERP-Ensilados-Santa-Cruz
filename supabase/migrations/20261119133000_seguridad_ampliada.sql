-- Ampliación del módulo de Seguridad y Accesos (RF-01 a RF-06) sin cambiar los 5 roles ni las bajas lógicas:
-- historial de contraseñas, límite de sesiones simultáneas, bloqueo por IP, revocación inmediata de sesiones,
-- duplicados por nombre, programación de respaldos y optimización de la base.

insert into app.parametros (clave, valor, descripcion) values
  ('clave_historial', '3', 'Cantidad de contraseñas anteriores que no se pueden reutilizar'),
  ('sesiones_max', '0', 'Sesiones simultáneas por usuario (0 = ilimitado)'),
  ('intentos_ip_max', '20', 'Intentos fallidos desde una misma IP antes de bloquearla temporalmente'),
  ('respaldo_activo', 'true', 'Respaldo automático activado'),
  ('respaldo_frecuencia', '"diaria"', 'Frecuencia del respaldo automático: diaria, semanal o mensual'),
  ('respaldo_retencion_dias', '30', 'Días que se conservan los respaldos'),
  ('respaldo_estrategia', '"completo"', 'Estrategia del respaldo (pg_dump completo)')
on conflict (clave) do nothing;

-- ---------------------------------------------------------------- RF-01: duplicados por nombre completo
create or replace function app.validar_datos_usuario(p_nombre text, p_ci text, p_correo text, p_excluir uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_nombre !~ '^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ ]{3,120}$' then
    raise exception 'El nombre solo admite letras y espacios (mínimo 3).';
  end if;
  if p_ci !~ '^[0-9]{5,15}$' then
    raise exception 'El CI solo admite números (de 5 a 15 dígitos).';
  end if;
  if p_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'El correo no tiene un formato válido.';
  end if;
  if exists (select 1 from public.usuarios where upper(nombre_completo) = upper(p_nombre) and id is distinct from p_excluir) then
    raise exception 'Ya existe una cuenta registrada con ese nombre completo.';
  end if;
  if exists (select 1 from public.usuarios where ci = p_ci and id is distinct from p_excluir) then
    raise exception 'Ya existe una cuenta registrada con ese CI.';
  end if;
  if exists (select 1 from public.usuarios where correo = p_correo and id is distinct from p_excluir)
     or exists (select 1 from auth.users where email = p_correo and id is distinct from p_excluir) then
    raise exception 'Ya existe una cuenta registrada con ese correo.';
  end if;
end $$;

-- Consulta previa al guardado: indica qué campos ya existen (sin revelar la cuenta oculta del superadministrador).
create or replace function public.verificar_duplicados_usuario(p_nombre text, p_ci text, p_correo text, p_excluir uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := '[]'::jsonb;
begin
  if not app.es('admin_sistema') then
    return app.denegar('usuarios', 'Solo el administrador del sistema gestiona cuentas.');
  end if;
  if exists (select 1 from public.usuarios where upper(nombre_completo) = upper(btrim(p_nombre)) and id is distinct from p_excluir) then
    v := v || '["nombre"]'::jsonb; end if;
  if exists (select 1 from public.usuarios where ci = btrim(p_ci) and id is distinct from p_excluir) then
    v := v || '["ci"]'::jsonb; end if;
  if exists (select 1 from public.usuarios where correo = lower(btrim(p_correo)) and id is distinct from p_excluir)
     or exists (select 1 from auth.users where email = lower(btrim(p_correo)) and id is distinct from p_excluir) then
    v := v || '["correo"]'::jsonb; end if;
  return jsonb_build_object('duplicados', v);
end $$;
revoke all on function public.verificar_duplicados_usuario(text, text, text, uuid) from public, anon;
grant execute on function public.verificar_duplicados_usuario(text, text, text, uuid) to authenticated;

-- ---------------------------------------------------------------- RF-03: historial de contraseñas
create table if not exists app.historial_claves (
  id bigint generated always as identity primary key,
  usuario_id uuid not null references auth.users (id) on delete cascade,
  hash text not null,
  fecha timestamptz not null default now()
);
create index if not exists historial_claves_usuario_idx on app.historial_claves (usuario_id, fecha desc);
alter table app.historial_claves enable row level security;
revoke all on app.historial_claves from public, anon, authenticated;

create or replace function app.exigir_historial(p_usuario uuid, p_clave text) returns void
language plpgsql security definer set search_path = '' as $$
declare v_n int := coalesce((app.parametro('clave_historial'))::text::int, 0);
begin
  if v_n <= 0 then return; end if;
  if exists (
    select 1 from (
      select encrypted_password as hash from auth.users where id = p_usuario
      union all
      select hash from (select hash from app.historial_claves where usuario_id = p_usuario
                         order by fecha desc limit greatest(v_n - 1, 0)) h
    ) x where x.hash is not null and x.hash = extensions.crypt(p_clave, x.hash)) then
    raise exception 'No puede reutilizar ninguna de sus últimas % contraseñas.', v_n;
  end if;
end $$;

do $$
declare d text;
begin
  select pg_get_functiondef('public.cambiar_mi_clave(text, text)'::regprocedure) into d;
  if position('app.exigir_historial' in d) = 0 then
    d := replace(d, 'perform app.exigir_clave(p_nueva);',
      'perform app.exigir_clave(p_nueva);
  perform app.exigir_historial(v_id, p_nueva);
  insert into app.historial_claves (usuario_id, hash) values (v_id, v_hash);');
    execute d;
  end if;
  select pg_get_functiondef('public.restablecer_clave(uuid, text)'::regprocedure) into d;
  if position('app.exigir_historial' in d) = 0 then
    d := replace(d, 'perform app.exigir_clave(p_clave);',
      'perform app.exigir_clave(p_clave);
  perform app.exigir_historial(p_usuario, p_clave);
  insert into app.historial_claves (usuario_id, hash) select id, encrypted_password from auth.users where id = p_usuario;');
    execute d;
  end if;
end $$;

-- ---------------------------------------------------------------- RF-04: sesiones
-- Una sesión revocada (borrada de auth.sessions) deja de tener rol en el mismo instante: todas las políticas RLS y
-- funciones que pasan por app.rol() la rechazan aunque su token todavía no haya vencido.
create or replace function app.rol() returns text
language sql stable security definer set search_path = '' as $$
  select r.codigo::text from public.usuarios u join public.roles r on r.id = u.rol_id
  where u.id = (select auth.uid()) and u.estado = 'activo'
    and (nullif((select auth.jwt()) ->> 'session_id', '') is null
         or exists (select 1 from auth.sessions s where s.id = ((select auth.jwt()) ->> 'session_id')::uuid))
$$;

create or replace function public.sesion_vigente() returns boolean
language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null and app.rol() is not null
$$;
revoke all on function public.sesion_vigente() from public, anon;
grant execute on function public.sesion_vigente() to authenticated;

create or replace function public.cerrar_sesion(p_sesion uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_usuario uuid;
begin
  if not app.es('admin_sistema') then
    return app.denegar('sesiones', 'Solo el administrador cierra sesiones.');
  end if;
  select user_id into v_usuario from auth.sessions where id = p_sesion;
  if v_usuario is null or app.oculto(v_usuario) then raise exception 'La sesión no existe.'; end if;
  if p_sesion::text = (select auth.jwt()) ->> 'session_id' then
    raise exception 'No puede cerrar su propia sesión desde aquí; use «Salir».';
  end if;
  delete from auth.sessions where id = p_sesion;
  perform app.evento('cierre_sesiones', 'sesiones', v_usuario, jsonb_build_object('sesiones', 1, 'sesion', p_sesion));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.cerrar_sesion(uuid) from public, anon;
grant execute on function public.cerrar_sesion(uuid) to authenticated;

-- Límite de sesiones simultáneas: al ingresar se cierran las más antiguas que excedan el límite.
do $$
declare d text;
begin
  select pg_get_functiondef('public.registrar_ingreso()'::regprocedure) into d;
  if position('sesiones_max' in d) = 0 then
    d := replace(d, '  return app.perfil(v_id);',
      '  if coalesce((app.parametro(''sesiones_max''))::text::int, 0) > 0 then
    delete from auth.sessions where user_id = v_id and id in (
      select id from auth.sessions where user_id = v_id
       order by (id::text = coalesce((select auth.jwt()) ->> ''session_id'', '''')) desc, created_at desc
      offset (app.parametro(''sesiones_max''))::text::int);
  end if;
  return app.perfil(v_id);');
    execute d;
  end if;
end $$;

-- Bloqueo temporal por IP (fuerza bruta contra varias cuentas desde la misma red).
do $$
declare d text;
begin
  select pg_get_functiondef('public.correo_para_ingreso(text)'::regprocedure) into d;
  if position('intentos_ip_max' in d) = 0 then
    d := replace(d, '  p_identificador := lower(btrim(coalesce(p_identificador, '''')));',
      '  if app.ip_cliente() is not null and (select count(*) from public.bitacora_eventos
        where accion = ''login_fallido'' and ip = app.ip_cliente()
          and fecha_servidor > now() - make_interval(mins => (app.parametro(''bloqueo_minutos''))::text::int))
       >= coalesce((app.parametro(''intentos_ip_max''))::text::int, 20) then
    raise exception ''Demasiados intentos fallidos desde esta red. Espere % minutos.'',
      (app.parametro(''bloqueo_minutos''))::text using errcode = ''42501'';
  end if;
  p_identificador := lower(btrim(coalesce(p_identificador, '''')));');
    execute d;
  end if;
end $$;

-- Confirmación de acciones sensibles con la contraseña del usuario que las ejecuta (bcrypt de Supabase Auth).
create or replace function public.verificar_mi_clave(p_clave text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare v_hash text;
begin
  select encrypted_password into v_hash from auth.users where id = (select auth.uid());
  return v_hash is not null and v_hash = extensions.crypt(coalesce(p_clave, ''), v_hash);
end $$;
revoke all on function public.verificar_mi_clave(text) from public, anon;
grant execute on function public.verificar_mi_clave(text) to authenticated;

-- ---------------------------------------------------------------- RF-03 y RF-06: parámetros nuevos
create or replace function public.guardar_parametros(p_valores jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare k text; v jsonb;
begin
  if not app.es('admin_sistema') then
    return app.denegar('parametros', 'Solo el administrador cambia los parámetros.');
  end if;
  for k, v in select * from jsonb_each(p_valores) loop
    if not exists (select 1 from app.parametros where clave = k) then
      raise exception 'Parámetro desconocido: %.', k;
    end if;
    if k in ('clave_mayusculas', 'clave_minusculas', 'clave_numeros', 'clave_simbolos', 'respaldo_activo')
       and jsonb_typeof(v) <> 'boolean' then
      raise exception 'El parámetro % debe ser sí o no.', k;
    end if;
    if k in ('clave_longitud_min', 'clave_vigencia_dias', 'intentos_max', 'bloqueo_minutos', 'pin_min', 'pin_max',
             'pin_intentos', 'horas_sin_sincronizar', 'inactividad_minutos', 'peso_promedio_rollo_kg',
             'tolerancia_despacho_pct', 'clave_historial', 'intentos_ip_max', 'respaldo_retencion_dias')
       and (jsonb_typeof(v) <> 'number' or v::text::numeric <= 0) then
      raise exception 'El parámetro % debe ser un número mayor que cero.', k;
    end if;
    if k = 'sesiones_max' and (jsonb_typeof(v) <> 'number' or v::text::int not in (0, 1, 2, 3)) then
      raise exception 'Las sesiones simultáneas deben ser 1, 2, 3 o ilimitadas.';
    end if;
    if k = 'clave_longitud_min' and v::text::int not between 8 and 16 then
      raise exception 'La longitud mínima de la contraseña debe estar entre 8 y 16.';
    end if;
    if k = 'clave_historial' and v::text::int not in (3, 5, 10) then
      raise exception 'El historial de contraseñas debe ser 3, 5 o 10.';
    end if;
    if k = 'intentos_max' and v::text::int not in (3, 5, 10) then
      raise exception 'Los intentos antes del bloqueo deben ser 3, 5 o 10.';
    end if;
    if k = 'respaldo_frecuencia' and v #>> '{}' not in ('diaria', 'semanal', 'mensual') then
      raise exception 'La frecuencia del respaldo debe ser diaria, semanal o mensual.';
    end if;
    if k = 'respaldo_retencion_dias' and v::text::int not in (7, 15, 30) then
      raise exception 'La retención de respaldos debe ser 7, 15 o 30 días.';
    end if;
    if k = 'respaldo_estrategia' and v #>> '{}' <> 'completo' then
      raise exception 'Supabase (plan gratuito) solo permite respaldos completos con pg_dump.';
    end if;
    if k = 'respaldo_hora_utc' and (jsonb_typeof(v) <> 'string' or v #>> '{}' !~ '^([01][0-9]|2[0-3]):00$') then
      raise exception 'La hora del respaldo debe ser una hora exacta (HH:00).';
    end if;
    update app.parametros set valor = v, actualizado_por = (select auth.uid()), actualizado_en = now()
     where clave = k;
    perform app.evento('parametro', 'parametros', null, jsonb_build_object('clave', k, 'valor', v));
  end loop;
  if (app.parametro('pin_min'))::text::int > (app.parametro('pin_max'))::text::int
     or (app.parametro('pin_min'))::text::int < 4 or (app.parametro('pin_max'))::text::int > 6 then
    raise exception 'El PIN debe tener entre 4 y 6 dígitos.';
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- RF-06: optimización (estadísticas del planificador)
create or replace function public.optimizar_base() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t record; n int := 0;
begin
  if not app.es('admin_sistema') then
    return app.denegar('respaldos', 'Solo el administrador optimiza la base de datos.');
  end if;
  for t in select schemaname, tablename from pg_tables where schemaname = 'public' loop
    execute format('analyze %I.%I', t.schemaname, t.tablename);
    n := n + 1;
  end loop;
  perform app.evento('optimizacion', 'respaldos', null, jsonb_build_object('tablas', n));
  return jsonb_build_object('ok', true, 'tablas', n);
end $$;
revoke all on function public.optimizar_base() from public, anon;
grant execute on function public.optimizar_base() to authenticated;
