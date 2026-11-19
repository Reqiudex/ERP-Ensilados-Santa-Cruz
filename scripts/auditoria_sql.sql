-- Auditoría por SQL directo: cada intento se ejecuta con el rol «authenticated» y la identidad de la cuenta
-- de demostración (igual que una sesión real), dentro de una transacción que se revierte.
-- Devuelve una fila por prueba: control, rol, intento y resultado (error de la base o filas afectadas).
create temporary table if not exists resultado_auditoria (n int, control text, rol text, intento text, resultado text);
truncate resultado_auditoria;

create or replace function pg_temp.intentar(p_n int, p_control text, p_rol text, p_uid uuid, p_sql text) returns void
language plpgsql as $$
declare v_filas int; v_res text;
begin
  begin
    perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', p_uid::text, true);
    execute 'set local role authenticated';
    execute p_sql;
    get diagnostics v_filas = row_count;
    v_res := format('ejecutado: %s filas afectadas', v_filas);
    raise exception using errcode = 'P9999', message = v_res;  -- revierte el intento
  exception when others then
    v_res := case when sqlstate = 'P9999' then sqlerrm else format('%s %s', sqlstate, sqlerrm) end;
  end;
  execute 'reset role';
  insert into resultado_auditoria values (p_n, p_control, p_rol, p_sql, v_res);
end $$;

do $$
declare
  r record;
  roles constant jsonb := '{"admin": "a1000000-0000-4000-8000-000000000001", "operador": "a1000000-0000-4000-8000-000000000021",
    "ejecutivo": "a1000000-0000-4000-8000-000000000002", "cajero": "a1000000-0000-4000-8000-000000000003",
    "gerente": "a1000000-0000-4000-8000-000000000004"}';
  v_pesaje uuid := (select id from public.pesajes where estado = 'confirmado' order by fecha_registro limit 1);
  v_nota uuid := (select id from public.notas_venta where estado = 'emitida' and saldo > 0 limit 1);
  v_sol uuid := (select id from public.solicitudes_aprobacion where estado = 'pendiente'
                   and registrado_por = 'a1000000-0000-4000-8000-000000000004' limit 1);
begin
  for r in select key, value #>> '{}' as uid from jsonb_each(roles) loop
    perform pg_temp.intentar(1, 'Pesaje confirmado inmutable', r.key, r.uid::uuid,
      format('update public.pesajes set peso_bruto = 99999 where id = %L', v_pesaje));
    perform pg_temp.intentar(7, 'Sin edición directa del stock', r.key, r.uid::uuid,
      'update public.existencias set disponible = disponible + 100');
    perform pg_temp.intentar(10, 'Bitácora inalterable (UPDATE)', r.key, r.uid::uuid,
      'update public.bitacora_eventos set accion = ''alterado''');
    perform pg_temp.intentar(10, 'Bitácora inalterable (DELETE)', r.key, r.uid::uuid,
      'delete from public.bitacora_eventos');
  end loop;
  perform pg_temp.intentar(2, 'Doble control registro–aprobación', 'gerente', (roles ->> 'gerente')::uuid,
    format('select public.resolver_solicitud(%L, true, null)', v_sol));
  perform pg_temp.intentar(3, 'Quien vende no cobra', 'ejecutivo', (roles ->> 'ejecutivo')::uuid,
    format('insert into public.cobros (nota_venta_id, monto, metodo, estado, registrado_por) values (%L, 1, ''qr'', ''vigente'', %L)',
           v_nota, roles ->> 'ejecutivo'));
  perform pg_temp.intentar(8, 'Administrador sin permisos de negocio', 'admin', (roles ->> 'admin')::uuid,
    'select count(*) from public.notas_venta having count(*) > 0');
  perform pg_temp.intentar(8, 'Administrador sin permisos de negocio', 'admin', (roles ->> 'admin')::uuid,
    'update public.usuarios set rol_id = 5 where id = ''a1000000-0000-4000-8000-000000000001''');
  perform pg_temp.intentar(9, 'Aislamiento por sede', 'operador', (roles ->> 'operador')::uuid,
    'select 1 from public.existencias where sede_id = ''33333333-3333-3333-3333-333333333333''');
end $$;

select n, control, rol, resultado from resultado_auditoria order by n, control, rol;
