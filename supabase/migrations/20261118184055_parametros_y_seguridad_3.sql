-- Migración 20261118184055 «parametros_y_seguridad_3», copiada del historial de Supabase (supabase_migrations.schema_migrations).
create or replace function app.validar_datos_usuario(p_nombre text, p_ci text, p_correo text, p_excluir uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
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
  if exists (select 1 from public.usuarios where ci = p_ci and id is distinct from p_excluir) then
    raise exception 'Ya existe una cuenta registrada con ese CI.';
  end if;
  if exists (select 1 from public.usuarios where correo = p_correo and id is distinct from p_excluir)
     or exists (select 1 from auth.users where email = p_correo and id is distinct from p_excluir) then
    raise exception 'Ya existe una cuenta registrada con ese correo.';
  end if;
end $$;

create or replace function public.crear_usuario(p_nombre text, p_ci text, p_correo text, p_rol text,
  p_sede uuid, p_clave text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid := gen_random_uuid();
  v_rol public.roles%rowtype;
begin
  if not app.es('admin_sistema') then
    return app.denegar('usuarios', 'Solo el administrador del sistema crea cuentas.');
  end if;
  p_nombre := btrim(regexp_replace(coalesce(p_nombre, ''), '\s+', ' ', 'g'));
  p_ci := btrim(coalesce(p_ci, ''));
  p_correo := lower(btrim(coalesce(p_correo, '')));
  perform app.validar_datos_usuario(p_nombre, p_ci, p_correo, null);
  select * into v_rol from public.roles where codigo = p_rol;
  if not found then raise exception 'Seleccione un rol válido.'; end if;
  if not exists (select 1 from public.sedes where id = p_sede and activa) then
    raise exception 'Seleccione una sede válida.';
  end if;
  if v_rol.codigo = 'operador_centro' and (select tipo from public.sedes where id = p_sede) <> 'centro_acopio' then
    raise exception 'El operador debe pertenecer a un centro de acopio.';
  end if;
  perform app.exigir_clave(p_clave);

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
    email_change_token_new, email_change, email_change_token_current, phone_change, phone_change_token,
    reauthentication_token, banned_until)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', p_correo,
    extensions.crypt(p_clave, extensions.gen_salt('bf')), now(),
    jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email'), 'debe_cambiar_clave', true),
    jsonb_build_object('nombre', p_nombre), now(), now(), '', '', '', '', '', '', '', '',
    case when v_rol.privilegiado then 'infinity'::timestamptz end);
  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (v_id::text, v_id, jsonb_build_object('sub', v_id::text, 'email', p_correo, 'email_verified', true),
          'email', null, now(), now());

  insert into public.usuarios (id, nombre_completo, ci, correo, rol_id, sede_id, estado)
  values (v_id, p_nombre, p_ci, p_correo, v_rol.id, p_sede,
          case when v_rol.privilegiado then 'suspendido' else 'activo' end);

  if v_rol.privilegiado then
    perform app.solicitud('rol_privilegiado', 'usuarios', v_id,
      jsonb_build_object('rol_id', v_rol.id, 'rol', v_rol.codigo, 'usuario', p_nombre, 'activar', true),
      'Alta de cuenta con rol privilegiado: ' || v_rol.nombre);
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'pendiente_aprobacion', v_rol.privilegiado);
end $$;

create or replace function public.editar_usuario(p_usuario uuid, p_nombre text, p_ci text, p_correo text,
  p_rol text, p_sede uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_u public.usuarios%rowtype;
  v_rol public.roles%rowtype;
  v_pendiente boolean := false;
begin
  if not app.es('admin_sistema') then
    return app.denegar('usuarios', 'Solo el administrador del sistema edita cuentas.');
  end if;
  select * into v_u from public.usuarios where id = p_usuario for update;
  if not found then raise exception 'La cuenta no existe.'; end if;
  select * into v_rol from public.roles where codigo = p_rol;
  if not found then raise exception 'Seleccione un rol válido.'; end if;
  if p_usuario = (select auth.uid()) and v_rol.id <> v_u.rol_id then
    return app.denegar('usuarios', 'El administrador no puede asignarse roles.');
  end if;
  p_nombre := btrim(regexp_replace(coalesce(p_nombre, ''), '\s+', ' ', 'g'));
  p_ci := btrim(coalesce(p_ci, ''));
  p_correo := lower(btrim(coalesce(p_correo, '')));
  perform app.validar_datos_usuario(p_nombre, p_ci, p_correo, p_usuario);
  if not exists (select 1 from public.sedes where id = p_sede and activa) then
    raise exception 'Seleccione una sede válida.';
  end if;

  update public.usuarios set nombre_completo = p_nombre, ci = p_ci, correo = p_correo, sede_id = p_sede,
         rol_id = case when v_rol.privilegiado then rol_id else v_rol.id end
   where id = p_usuario;
  if p_correo <> v_u.correo then
    update auth.users set email = p_correo, updated_at = now() where id = p_usuario;
    update auth.identities set identity_data = identity_data || jsonb_build_object('email', p_correo)
     where user_id = p_usuario and provider = 'email';
  end if;
  if v_rol.privilegiado and v_rol.id <> v_u.rol_id then
    perform app.solicitud('rol_privilegiado', 'usuarios', p_usuario,
      jsonb_build_object('rol_id', v_rol.id, 'rol', v_rol.codigo, 'usuario', p_nombre),
      'Asignación de rol privilegiado: ' || v_rol.nombre);
    v_pendiente := true;
  end if;
  return jsonb_build_object('ok', true, 'pendiente_aprobacion', v_pendiente);
end $$;

create or replace function public.cambiar_estado_usuario(p_usuario uuid, p_accion text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_estado text;
begin
  if not app.es('admin_sistema') then
    return app.denegar('usuarios', 'Solo el administrador del sistema cambia el estado de las cuentas.');
  end if;
  if p_usuario = (select auth.uid()) then
    raise exception 'No puede cambiar el estado de su propia cuenta.';
  end if;
  select estado into v_estado from public.usuarios where id = p_usuario for update;
  if v_estado is null then raise exception 'La cuenta no existe.'; end if;
  if p_accion = 'suspender' then
    update public.usuarios set estado = 'suspendido' where id = p_usuario;
    update auth.users set banned_until = 'infinity' where id = p_usuario;
    delete from auth.sessions where user_id = p_usuario;
  elsif p_accion in ('activar', 'desbloquear') then
    if exists (select 1 from public.solicitudes_aprobacion where entidad_id = p_usuario
               and tipo = 'rol_privilegiado' and estado = 'pendiente') then
      raise exception 'La cuenta espera la aprobación del gerente para su rol privilegiado.';
    end if;
    update public.usuarios set estado = 'activo' where id = p_usuario;
    update auth.users set banned_until = null where id = p_usuario;
    perform app.evento('desbloqueo', 'usuarios', p_usuario, jsonb_build_object('accion', p_accion));
  else
    raise exception 'Acción no válida.';
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.restablecer_clave(p_usuario uuid, p_clave text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('admin_sistema') then
    return app.denegar('usuarios', 'Solo el administrador del sistema restablece contraseñas.');
  end if;
  if not exists (select 1 from public.usuarios where id = p_usuario) then
    raise exception 'La cuenta no existe.';
  end if;
  perform app.exigir_clave(p_clave);
  update auth.users
     set encrypted_password = extensions.crypt(p_clave, extensions.gen_salt('bf')),
         raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"debe_cambiar_clave": true}'::jsonb,
         updated_at = now()
   where id = p_usuario;
  delete from auth.sessions where user_id = p_usuario;
  perform app.evento('restablecer_clave', 'usuarios', p_usuario, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.sesiones_activas() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.es('admin_sistema', 'gerente_general') then
    return app.denegar('sesiones', 'Solo el administrador consulta las sesiones.');
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', s.id, 'usuario_id', s.user_id, 'usuario', u.nombre_completo, 'rol', r.nombre,
      'agente', s.user_agent, 'ip', host(s.ip), 'inicio', s.created_at,
      'ultima_actividad', coalesce(s.refreshed_at::timestamptz, s.updated_at),
      'actual', s.id::text = (select auth.jwt() ->> 'session_id')) order by s.created_at desc)
    from auth.sessions s
    join public.usuarios u on u.id = s.user_id
    join public.roles r on r.id = u.rol_id
    where s.not_after is null or s.not_after > now()), '[]'::jsonb);
end $$;

create or replace function public.cerrar_sesiones(p_usuario uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_n int; v_actual text := (select auth.jwt() ->> 'session_id');
begin
  if not app.es('admin_sistema') then
    return app.denegar('sesiones', 'Solo el administrador cierra sesiones.');
  end if;
  if p_usuario is null then
    delete from auth.sessions where id::text <> coalesce(v_actual, '');
  else
    delete from auth.sessions where user_id = p_usuario and id::text <> coalesce(v_actual, '');
  end if;
  get diagnostics v_n = row_count;
  perform app.evento('cierre_sesiones', 'sesiones', p_usuario, jsonb_build_object('sesiones', v_n));
  return jsonb_build_object('ok', true, 'cerradas', v_n);
end $$;

create or replace function public.obtener_parametros() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if app.rol() is null then
    raise exception 'Sesión no válida.' using errcode = '42501';
  end if;
  return (select jsonb_object_agg(clave, jsonb_build_object('valor', valor, 'descripcion', descripcion,
            'actualizado_en', actualizado_en)) from app.parametros);
end $$;

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
    if k like 'clave\_%' escape '\' and k not in ('clave_longitud_min', 'clave_vigencia_dias')
       and jsonb_typeof(v) <> 'boolean' then
      raise exception 'El parámetro % debe ser sí o no.', k;
    end if;
    if k in ('clave_longitud_min', 'clave_vigencia_dias', 'intentos_max', 'bloqueo_minutos', 'pin_min', 'pin_max',
             'pin_intentos', 'horas_sin_sincronizar', 'inactividad_minutos', 'peso_promedio_rollo_kg',
             'tolerancia_despacho_pct')
       and (jsonb_typeof(v) <> 'number' or v::text::numeric <= 0) then
      raise exception 'El parámetro % debe ser un número mayor que cero.', k;
    end if;
    if k = 'clave_longitud_min' and v::text::int < 8 then
      raise exception 'La longitud mínima de la contraseña no puede ser menor que 8.';
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

create or replace function public.actualizar_grano(p_grano smallint, p_humedad numeric, p_dias smallint,
  p_rollos_min numeric, p_rollos_max numeric) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('admin_sistema') then
    return app.denegar('granos', 'Solo el administrador cambia los parámetros por grano.');
  end if;
  if p_rollos_min >= p_rollos_max then
    raise exception 'El mínimo de rollos por tonelada debe ser menor que el máximo.';
  end if;
  update public.granos set humedad_estandar = p_humedad, dias_fermentacion = p_dias,
         rollos_ton_min = p_rollos_min, rollos_ton_max = p_rollos_max where id = p_grano;
  if not found then raise exception 'El grano no existe.'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.respaldos() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.es('admin_sistema', 'gerente_general') then
    return app.denegar('respaldos', 'Solo el administrador y el gerente consultan los respaldos.');
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'accion', b.accion,
      'fecha', b.fecha_servidor, 'datos', b.datos_despues) order by b.fecha_servidor desc)
    from (select * from public.bitacora_eventos
           where accion in ('respaldo', 'respaldo_pedido', 'restauracion')
           order by fecha_servidor desc limit 60) b), '[]'::jsonb);
end $$;

create or replace function public.pedir_respaldo() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('admin_sistema') then
    return app.denegar('respaldos', 'Solo el administrador pide respaldos.');
  end if;
  perform app.evento('respaldo_pedido', 'respaldos', null, jsonb_build_object('estado', 'en cola'));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.solicitar_restauracion(p_respaldo text, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not app.es('admin_sistema') then
    return app.denegar('respaldos', 'Solo el administrador solicita restauraciones.');
  end if;
  v_id := app.solicitud('restauracion', 'respaldos', gen_random_uuid(),
    jsonb_build_object('respaldo', p_respaldo), p_motivo);
  return jsonb_build_object('ok', true, 'solicitud_id', v_id, 'estado', 'pendiente');
end $$;

create or replace function public.estado_conexion() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('ok', true, 'servidor', now(), 'version', current_setting('server_version'))
$$;
