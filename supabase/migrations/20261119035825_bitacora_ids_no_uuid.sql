-- La bitácora acepta tablas cuyo identificador no es UUID (granos usa smallint): registro_id queda nulo y el id va en los datos.
create or replace function app.registrar_bitacora()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_antes jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_despues jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_usuario uuid;
  v_fecha_disp timestamptz;
  v_id text;
  v_aprob text;
  c_uuid constant text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
begin
  select u.id into v_usuario from public.usuarios u where u.id = (select auth.uid());
  v_fecha_disp := nullif(coalesce(v_despues, v_antes) ->> 'fecha_dispositivo', '')::timestamptz;
  v_id := coalesce(v_despues, v_antes) ->> 'id';
  v_aprob := coalesce(v_despues, v_antes) ->> 'aprobado_por';
  insert into public.bitacora_eventos (usuario_id, aprobador_id, accion, tabla, registro_id,
    datos_antes, datos_despues, ip, fecha_dispositivo)
  values (v_usuario,
    case when v_aprob ~ c_uuid then v_aprob::uuid end,
    lower(tg_op), tg_table_name,
    case when v_id ~ c_uuid then v_id::uuid end,
    v_antes, v_despues, app.ip_cliente(), v_fecha_disp);
  return coalesce(new, old);
end $function$;
