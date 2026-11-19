-- Migración 20261118183959 «parametros_y_seguridad_2», copiada del historial de Supabase (supabase_migrations.schema_migrations).
create or replace function app.ip_cliente() returns inet
language plpgsql stable set search_path = '' as $$
declare v text;
begin
  v := btrim(split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1));
  if v <> '' then return v::inet; end if;
  return inet_client_addr();
exception when others then
  return inet_client_addr();
end $$;

create or replace function app.registrar_bitacora() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_antes jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_despues jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_usuario uuid;
  v_fecha_disp timestamptz;
begin
  select u.id into v_usuario from public.usuarios u where u.id = (select auth.uid());
  v_fecha_disp := nullif(coalesce(v_despues, v_antes) ->> 'fecha_dispositivo', '')::timestamptz;
  insert into public.bitacora_eventos (usuario_id, aprobador_id, accion, tabla, registro_id,
    datos_antes, datos_despues, ip, fecha_dispositivo)
  values (v_usuario,
    nullif(coalesce(v_despues, v_antes) ->> 'aprobado_por', '')::uuid,
    lower(tg_op), tg_table_name,
    nullif(coalesce(v_despues, v_antes) ->> 'id', '')::uuid,
    v_antes, v_despues, app.ip_cliente(), v_fecha_disp);
  return coalesce(new, old);
end $$;

create or replace function app.evento(p_accion text, p_tabla text, p_registro uuid, p_datos jsonb) returns void
language sql security definer set search_path = '' as $$
  insert into public.bitacora_eventos (usuario_id, accion, tabla, registro_id, datos_despues, ip)
  values ((select u.id from public.usuarios u where u.id = (select auth.uid())), p_accion, p_tabla, p_registro,
          p_datos, app.ip_cliente());
$$;

create or replace function app.denegar(p_tabla text, p_mensaje text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform app.evento('acceso_denegado', p_tabla, null,
    jsonb_build_object('motivo', p_mensaje, 'rol', app.rol()));
  perform set_config('response.status', '403', true);
  return jsonb_build_object('code', '42501', 'message', p_mensaje, 'details', null, 'hint', null);
end $$;

create or replace function app.solicitud(p_tipo text, p_entidad text, p_entidad_id uuid, p_datos jsonb, p_motivo text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if coalesce(btrim(p_motivo), '') = '' then
    raise exception 'Indique el motivo de la solicitud.';
  end if;
  insert into public.solicitudes_aprobacion (tipo, entidad, entidad_id, datos_propuestos, motivo, registrado_por, estado)
  values (p_tipo, p_entidad, p_entidad_id, coalesce(p_datos, '{}'::jsonb), btrim(p_motivo), (select auth.uid()), 'pendiente')
  returning id into v_id;
  return v_id;
end $$;

create or replace function app.evaluar_clave(p_clave text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_min int := coalesce((app.parametro('clave_longitud_min'))::text::int, 8);
  v_falta text[] := '{}';
  v_puntaje int := 0;
  v_len int := coalesce(length(p_clave), 0);
begin
  v_puntaje := least(40, (v_len * 40) / greatest(v_min, 1));
  if v_len < v_min then v_falta := v_falta || format('Al menos %s caracteres', v_min); end if;
  if p_clave ~ '[A-ZÁÉÍÓÚÑ]' then v_puntaje := v_puntaje + 15;
  elsif (app.parametro('clave_mayusculas'))::text::boolean then v_falta := v_falta || 'Una letra mayúscula'::text; end if;
  if p_clave ~ '[a-záéíóúñ]' then v_puntaje := v_puntaje + 15;
  elsif (app.parametro('clave_minusculas'))::text::boolean then v_falta := v_falta || 'Una letra minúscula'::text; end if;
  if p_clave ~ '[0-9]' then v_puntaje := v_puntaje + 15;
  elsif (app.parametro('clave_numeros'))::text::boolean then v_falta := v_falta || 'Un número'::text; end if;
  if p_clave ~ '[^A-Za-z0-9ÁÉÍÓÚÑáéíóúñ]' then v_puntaje := v_puntaje + 15;
  elsif (app.parametro('clave_simbolos'))::text::boolean then v_falta := v_falta || 'Un símbolo'::text; end if;
  return jsonb_build_object('puntaje', least(100, v_puntaje), 'faltantes', to_jsonb(v_falta),
                            'valida', cardinality(v_falta) = 0);
end $$;

create or replace function app.exigir_clave(p_clave text) returns void
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := app.evaluar_clave(p_clave);
begin
  if not (v ->> 'valida')::boolean then
    raise exception 'La contraseña no cumple la política: %.',
      (select string_agg(x, ', ') from jsonb_array_elements_text(v -> 'faltantes') x);
  end if;
end $$;

create or replace function public.correo_para_ingreso(p_identificador text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare v text;
begin
  p_identificador := lower(btrim(coalesce(p_identificador, '')));
  if position('@' in p_identificador) > 0 then return p_identificador; end if;
  select correo into v from public.usuarios where ci = p_identificador;
  return coalesce(v, 'sin-cuenta-' || md5(p_identificador) || '@ensilados.invalid');
end $$;

create or replace function public.registrar_intento_fallido(p_identificador text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_max int := (app.parametro('intentos_max'))::text::int;
  v_min int := (app.parametro('bloqueo_minutos'))::text::int;
  v_desde timestamptz;
  v_n int;
begin
  p_identificador := lower(btrim(coalesce(p_identificador, '')));
  select id into v_id from public.usuarios where ci = p_identificador or correo = p_identificador;
  insert into public.bitacora_eventos (usuario_id, accion, tabla, registro_id, datos_despues, ip)
  values (null, 'login_fallido', 'usuarios', v_id,
          jsonb_build_object('identificador', left(p_identificador, 2) || '*****'), app.ip_cliente());
  if v_id is null then return; end if;
  select greatest(now() - make_interval(mins => v_min),
                  coalesce(max(fecha_servidor), '-infinity'::timestamptz))
    into v_desde from public.bitacora_eventos where registro_id = v_id and accion in ('login', 'desbloqueo');
  select count(*) into v_n from public.bitacora_eventos
   where registro_id = v_id and accion = 'login_fallido' and fecha_servidor > v_desde;
  if v_n >= v_max then
    update public.usuarios set estado = 'bloqueado' where id = v_id and estado = 'activo';
    if found then
      update auth.users set banned_until = now() + make_interval(mins => v_min) where id = v_id;
      insert into public.bitacora_eventos (accion, tabla, registro_id, datos_despues, ip)
      values ('bloqueo', 'usuarios', v_id, jsonb_build_object('minutos', v_min, 'intentos', v_n), app.ip_cliente());
    end if;
  end if;
end $$;

create or replace function app.perfil(p_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', u.id, 'nombre', u.nombre_completo, 'ci', u.ci, 'correo', u.correo,
    'rol', r.codigo, 'rol_nombre', r.nombre, 'sede_id', s.id, 'sede', s.nombre, 'sede_tipo', s.tipo,
    'estado', u.estado,
    'debe_cambiar_clave', coalesce((a.raw_app_meta_data ->> 'debe_cambiar_clave')::boolean, false),
    'parametros', (select jsonb_object_agg(p.clave, p.valor) from app.parametros p
                    where p.clave in ('inactividad_minutos', 'tolerancia_despacho_pct', 'peso_promedio_rollo_kg',
                                      'pin_min', 'pin_max', 'pin_intentos', 'horas_sin_sincronizar',
                                      'clave_longitud_min', 'clave_mayusculas', 'clave_minusculas',
                                      'clave_numeros', 'clave_simbolos')))
  from public.usuarios u
  join public.roles r on r.id = u.rol_id
  join public.sedes s on s.id = u.sede_id
  join auth.users a on a.id = u.id
  where u.id = p_id
$$;

create or replace function public.registrar_ingreso() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := (select auth.uid()); v_estado text;
begin
  select estado into v_estado from public.usuarios where id = v_id;
  if v_estado is null then
    raise exception 'La cuenta no tiene acceso al sistema.' using errcode = '42501';
  end if;
  if v_estado = 'bloqueado' and coalesce((select banned_until from auth.users where id = v_id), '-infinity') <= now() then
    update public.usuarios set estado = 'activo' where id = v_id;
    v_estado := 'activo';
  end if;
  if v_estado <> 'activo' then
    raise exception 'La cuenta no está activa.' using errcode = '42501';
  end if;
  insert into public.bitacora_eventos (usuario_id, accion, tabla, registro_id, datos_despues, ip)
  values (v_id, 'login', 'usuarios', v_id,
          jsonb_build_object('agente', left(coalesce(current_setting('request.headers', true)::json ->> 'user-agent', ''), 200)),
          app.ip_cliente());
  return app.perfil(v_id);
end $$;

create or replace function public.mi_perfil() returns jsonb
language sql stable security definer set search_path = '' as $$
  select app.perfil((select auth.uid()))
$$;

create or replace function public.evaluar_clave(p_clave text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select app.evaluar_clave(p_clave)
$$;

create or replace function public.cambiar_mi_clave(p_actual text, p_nueva text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id uuid := (select auth.uid()); v_hash text;
begin
  select encrypted_password into v_hash from auth.users where id = v_id;
  if v_hash is null or v_hash <> extensions.crypt(p_actual, v_hash) then
    raise exception 'La contraseña actual no es correcta.';
  end if;
  if p_nueva = p_actual then
    raise exception 'La nueva contraseña debe ser distinta de la actual.';
  end if;
  perform app.exigir_clave(p_nueva);
  update auth.users
     set encrypted_password = extensions.crypt(p_nueva, extensions.gen_salt('bf')),
         raw_app_meta_data = (coalesce(raw_app_meta_data, '{}'::jsonb) - 'debe_cambiar_clave')
                             || jsonb_build_object('clave_cambiada', now()),
         updated_at = now()
   where id = v_id;
  perform app.evento('cambio_clave', 'usuarios', v_id, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;
