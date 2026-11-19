-- Migración 20261118113824 «controles_bitacora_y_pesajes», copiada del historial de Supabase (supabase_migrations.schema_migrations).
-- Peso ajustado por humedad (fórmula de la tesis, caso CP-08)
create or replace function app.calcular_peso_ajustado() returns trigger
language plpgsql set search_path = '' as $$
declare v_std numeric;
begin
  select humedad_estandar into v_std from public.granos where id = new.grano_id;
  new.peso_ajustado := round((new.peso_bruto - new.tara) * (100 - new.humedad) / (100 - v_std), 2);
  return new;
end $$;
create trigger trg_peso_ajustado before insert on pesajes
  for each row execute function app.calcular_peso_ajustado();

-- Pesaje confirmado inmutable (control 1 del Anexo C): solo cambia mediante una corrección aprobada,
-- que la función de aprobación marca con app.via_aprobacion = 'si' dentro de su transacción.
create or replace function app.proteger_pesaje() returns trigger
language plpgsql set search_path = '' as $$
begin
  if coalesce(current_setting('app.via_aprobacion', true), '') <> 'si' then
    raise exception 'Un pesaje confirmado no se modifica: solicite la corrección con motivo para que la apruebe el gerente.'
      using errcode = '42501';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
create trigger trg_pesaje_inmutable before update or delete on pesajes
  for each row execute function app.proteger_pesaje();

-- Bitácora inalterable (control 10, NIST AU-9)
create or replace function app.bitacora_inalterable() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'La bitácora de eventos no admite cambios ni borrados.' using errcode = '42501';
end $$;
create trigger trg_bitacora_inalterable before update or delete on bitacora_eventos
  for each row execute function app.bitacora_inalterable();

-- Registro automático en la bitácora de toda alta, cambio o baja en tablas sensibles
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
    v_antes, v_despues, inet_client_addr(), v_fecha_disp);
  return coalesce(new, old);
end $$;

do $$ declare t text; begin
  foreach t in array array['usuarios','solicitudes_aprobacion','pesajes','ordenes_ensilado','consumos_insumo',
    'lotes','revisiones_fermentacion','productos','guias_transferencia','mermas','clientes','proveedores',
    'compras','pagos','pedidos','notas_venta','cobros','despachos','granos'] loop
    execute format('create trigger trg_bitacora after insert or update or delete on public.%I
      for each row execute function app.registrar_bitacora()', t);
  end loop;
end $$;

revoke all on function app.calcular_peso_ajustado(), app.proteger_pesaje(), app.bitacora_inalterable(),
  app.registrar_bitacora() from public, anon, authenticated;;
