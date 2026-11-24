-- Correcciones de la auditoría del 24 de noviembre de 2026.
--  1. Nadie escribe directamente solicitudes, pedidos ni su detalle: solo por las funciones que validan (C1, C2).
--  2. Pesajes y órdenes registrados por la API se validan contra la orden, la sede y la fecha del dispositivo (A3, A4).
--  3. cerrar_orden acepta el id del lote generado en el teléfono (sincronización sin conexión), acota la fecha y el
--     rendimiento (A3, A4).
--  4. Despacho: solo lo reservado para ESE pedido, nota emitida y, al contado, cobrada (C2, A5, M4).
--  5. Ingreso: la contraseña y el bloqueo se verifican en el servidor; el CI ya no revela el correo (A1).
--  6. Cuentas privilegiadas: el administrador no les restablece la clave ni les cambia el correo o el rol sin el
--     gerente (A2).
--  7. Respaldo JSON completo: solo se omite la fila de usuarios de la cuenta oculta (M1).
--  8. Sincronización idempotente de la cola del teléfono: una operación enviada dos veces se aplica una sola vez.

-- ---------------------------------------------------------------- Parámetros nuevos
insert into app.parametros (clave, valor, descripcion) values
  ('dias_registro_atrasado', '30', 'Días máximos de atraso de la fecha del dispositivo en registros sin conexión'),
  ('despacho_contado_exige_cobro', 'true', 'Una venta al contado se despacha solo cuando está cobrada por completo')
on conflict (clave) do nothing;

-- ---------------------------------------------------------------- 1. Sin inserciones directas que salten las funciones
drop policy if exists solicitudes_registro on public.solicitudes_aprobacion;
drop policy if exists pedidos_registro on public.pedidos;
drop policy if exists pedido_detalle_registro on public.pedido_detalle;
revoke insert on public.solicitudes_aprobacion, public.pedidos, public.pedido_detalle from authenticated, anon;

-- ---------------------------------------------------------------- 2. Validación de registros que llegan por la API
-- Solo aplica a lo que inserta directamente un usuario de la API: la función NO es SECURITY DEFINER, así que
-- current_user es «authenticated» en una inserción por PostgREST y el propietario cuando inserta una función del
-- servidor (por ejemplo, la corrección de pesaje aprobada), el seed o el mantenimiento, que no pasan por aquí.
create or replace function app.orden_de_pesaje(p_orden uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select to_jsonb(o) from public.ordenes_ensilado o where o.id = p_orden
$$;
create or replace function app.productor_activo(p_proveedor uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.proveedores where id = p_proveedor and tipo = 'productor' and estado = 'activo')
$$;
revoke all on function app.orden_de_pesaje(uuid), app.productor_activo(uuid) from public, anon;
grant execute on function app.orden_de_pesaje(uuid), app.productor_activo(uuid) to authenticated;
-- El disparador corre con el rol del usuario y lee el parámetro de días de atraso (los parámetros no son secretos:
-- obtener_parametros ya los muestra a cualquier usuario activo).
grant execute on function app.parametro(text) to authenticated;

create or replace function app.validar_registro_campo() returns trigger
language plpgsql set search_path = '' as $$
declare
  v jsonb := to_jsonb(new);
  o jsonb;
  v_dias int := coalesce((app.parametro('dias_registro_atrasado'))::text::int, 30);
  v_fecha timestamptz;
begin
  if current_user::text <> 'authenticated' then
    return new;
  end if;
  if tg_table_name = 'pesajes' then
    v_fecha := (v ->> 'fecha_dispositivo')::timestamptz;
  else
    v_fecha := (v ->> 'fecha_apertura')::timestamptz;
  end if;
  if v_fecha > now() + interval '10 minutes' then
    raise exception 'La fecha del teléfono está adelantada: corrija la hora del dispositivo y vuelva a registrar.';
  end if;
  if v_fecha < now() - make_interval(days => v_dias) then
    raise exception 'El registro tiene más de % días de atraso: debe registrarlo la oficina con una solicitud.', v_dias;
  end if;
  if tg_table_name <> 'pesajes' then
    return new;
  end if;
  if v ->> 'orden_id' is not null then
    o := app.orden_de_pesaje((v ->> 'orden_id')::uuid);
    if o is null or o ->> 'sede_id' <> v ->> 'sede_id' then
      raise exception 'La orden de ensilado no existe en su centro.';
    end if;
    if o ->> 'estado' <> 'abierta' then raise exception 'La orden de ensilado ya está cerrada.'; end if;
    if o ->> 'grano_id' <> v ->> 'grano_id' then
      raise exception 'El grano del pesaje no coincide con el de la orden.';
    end if;
    if v_fecha < (o ->> 'fecha_apertura')::timestamptz - interval '1 hour' then
      raise exception 'El pesaje es anterior a la apertura de la orden.';
    end if;
  end if;
  if v ->> 'origen' = 'productor' and not app.productor_activo((v ->> 'proveedor_id')::uuid) then
    raise exception 'El productor no está activo.';
  end if;
  return new;
end $$;

drop trigger if exists trg_validar_registro on public.pesajes;
create trigger trg_validar_registro before insert on public.pesajes
  for each row execute function app.validar_registro_campo();
drop trigger if exists trg_validar_registro on public.ordenes_ensilado;
create trigger trg_validar_registro before insert on public.ordenes_ensilado
  for each row execute function app.validar_registro_campo();

-- ---------------------------------------------------------------- 3. Cierre de orden (con id de lote del teléfono)
drop function if exists public.cerrar_orden(uuid, integer, timestamptz);
create or replace function public.cerrar_orden(p_orden uuid, p_rollos integer, p_fecha_dispositivo timestamptz default null,
  p_lote_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  o public.ordenes_ensilado%rowtype;
  g public.granos%rowtype;
  v_n int; v_kg numeric; v_prod uuid; v_lote uuid; v_codigo text; v_falta text[] := '{}';
  c record; v_disp numeric; v_rend numeric; v_alerta text;
  v_dias int := coalesce((app.parametro('dias_registro_atrasado'))::text::int, 30);
  v_fecha timestamptz := coalesce(p_fecha_dispositivo, now());
begin
  if not app.es('operador_centro') then
    return app.denegar('ordenes_ensilado', 'Solo el operador del centro cierra órdenes de ensilado.');
  end if;
  select * into o from public.ordenes_ensilado where id = p_orden for update;
  if not found or o.sede_id <> app.sede() then raise exception 'La orden no existe en su centro.'; end if;
  if o.estado <> 'abierta' then raise exception 'La orden ya está cerrada.'; end if;
  if coalesce(p_rollos, 0) <= 0 then raise exception 'Indique la cantidad de rollos obtenidos.'; end if;
  -- La fecha de sellado decide cuándo el lote queda apto: no puede ser futura, anterior a la apertura ni muy atrasada.
  if v_fecha > now() + interval '10 minutes' then
    raise exception 'La fecha del teléfono está adelantada: corrija la hora del dispositivo.';
  end if;
  -- El límite de atraso vale para lo que llega por la API; el seed y el mantenimiento cargan historia.
  if v_fecha < o.fecha_apertura
     or (coalesce(current_setting('role', true), 'none') in ('authenticated', 'anon')
         and v_fecha < now() - make_interval(days => v_dias)) then
    raise exception 'La fecha de cierre no puede ser anterior a la apertura de la orden ni tener más de % días.', v_dias;
  end if;
  if p_lote_id is not null and exists (select 1 from public.lotes where id = p_lote_id) then
    raise exception 'El identificador del lote ya está en uso.';
  end if;
  select * into g from public.granos where id = o.grano_id;
  select count(*), coalesce(sum(peso_ajustado), 0) into v_n, v_kg
    from public.pesajes where orden_id = p_orden and estado = 'confirmado';
  if v_n = 0 then raise exception 'La orden no tiene pesajes confirmados.'; end if;

  v_rend := round(p_rollos / (v_kg / 1000.0), 2);
  if v_rend > 2 * coalesce(g.rollos_ton_max, v_rend) then
    raise exception 'Rendimiento imposible: % rollos/t (el máximo normal es %). Revise los rollos o los pesajes.',
      v_rend, g.rollos_ton_max;
  end if;

  for c in select ci.producto_id, sum(ci.cantidad) as cant, p.nombre
             from public.consumos_insumo ci join public.productos p on p.id = ci.producto_id
            where ci.orden_id = p_orden group by ci.producto_id, p.nombre loop
    select coalesce(sum(disponible), 0) into v_disp from public.existencias
     where sede_id = o.sede_id and producto_id = c.producto_id and lote_id is null;
    if v_disp < c.cant then
      v_falta := v_falta || format('%s: requiere %s, disponible %s, faltan %s', c.nombre, c.cant, v_disp, c.cant - v_disp);
    end if;
  end loop;
  if cardinality(v_falta) > 0 then
    raise exception 'No se puede cerrar la orden por insumos insuficientes. %', array_to_string(v_falta, '; ');
  end if;

  for c in select producto_id, sum(cantidad) as cant from public.consumos_insumo where orden_id = p_orden
            group by producto_id loop
    perform app.ajustar_existencia(o.sede_id, c.producto_id, null, -c.cant, 0, 0);
    perform app.movimiento('consumo', o.sede_id, c.producto_id, null, -c.cant, 'ordenes_ensilado', p_orden);
  end loop;

  select id into v_prod from public.productos where tipo = 'rollo' and grano_id = o.grano_id and activo
   order by sku limit 1;
  if v_prod is null then raise exception 'No hay un producto rollo activo para el grano %.', g.nombre; end if;

  v_codigo := 'L-' || upper(left(translate(g.nombre, 'áéíóúÁÉÍÓÚ', 'aeiouAEIOU'), 3)) || '-'
              || to_char(v_fecha, 'YYMMDD') || '-' || lpad(nextval('app.seq_lote')::text, 4, '0');
  insert into public.lotes (id, codigo, orden_id, producto_id, sede_id, fecha_sellado, rollos_producidos,
    peso_promedio_rollo, estado)
  values (coalesce(p_lote_id, gen_random_uuid()), v_codigo, p_orden, v_prod, o.sede_id, v_fecha::date, p_rollos,
    round(v_kg / p_rollos, 2), 'fermentacion')
  returning id into v_lote;
  perform app.ajustar_existencia(o.sede_id, v_prod, v_lote, p_rollos, 0, 0);
  perform app.movimiento('ingreso', o.sede_id, v_prod, v_lote, p_rollos, 'lotes', v_lote);

  update public.ordenes_ensilado set estado = 'cerrada', fecha_cierre = v_fecha, rollos_obtenidos = p_rollos
   where id = p_orden;

  if v_rend < g.rollos_ton_min or v_rend > g.rollos_ton_max then
    v_alerta := format('Rendimiento de %s rollos/t fuera del rango normal (%s a %s).', v_rend, g.rollos_ton_min, g.rollos_ton_max);
  end if;
  return jsonb_build_object('ok', true, 'lote_id', v_lote, 'codigo', v_codigo, 'estado', 'fermentacion',
    'toneladas', round(v_kg / 1000.0, 3), 'rendimiento', v_rend, 'alerta', v_alerta);
end $$;
revoke all on function public.cerrar_orden(uuid, integer, timestamptz, uuid) from public, anon;
grant execute on function public.cerrar_orden(uuid, integer, timestamptz, uuid) to authenticated;

-- ---------------------------------------------------------------- 4. Despachos
-- Rollos reservados para un pedido en una sede y lote, menos lo ya despachado de ese pedido.
create or replace function app.reservado_pedido(p_pedido uuid, p_sede uuid, p_lote uuid) returns numeric
language sql stable security definer set search_path = '' as $$
  select coalesce((select sum(m.cantidad) from public.movimientos_inventario m
                    where m.documento_tipo = 'pedidos' and m.documento_id = p_pedido and m.tipo = 'reserva'
                      and m.sede_id = p_sede and m.lote_id = p_lote), 0)
       - coalesce((select sum(d.cantidad) from public.despachos d join public.notas_venta n on n.id = d.nota_venta_id
                    where n.pedido_id = p_pedido and d.sede_id = p_sede and d.lote_id = p_lote), 0)
$$;
revoke all on function app.reservado_pedido(uuid, uuid, uuid) from public, anon, authenticated;

-- Validaciones comunes del despacho directo y del aprobado por exceso de peso.
create or replace function app.validar_despacho(p_nota uuid, p_sede uuid, p_lote uuid, p_n int) returns void
language plpgsql security definer set search_path = '' as $$
declare n public.notas_venta%rowtype; d public.pedido_detalle%rowtype; v_res numeric; v_ya int;
begin
  select * into n from public.notas_venta where id = p_nota;
  if not found or n.estado <> 'emitida' then
    raise exception 'El despacho exige una nota de venta emitida por el ejecutivo comercial.';
  end if;
  if n.condicion_pago = 'contado' and n.saldo > 0
     and coalesce((app.parametro('despacho_contado_exige_cobro'))::text::boolean, true) then
    raise exception 'La nota N.º % es al contado y tiene un saldo de Bs %: el cajero debe cobrarla antes del despacho.',
      n.numero, n.saldo;
  end if;
  select * into d from public.pedido_detalle where pedido_id = n.pedido_id and lote_id = p_lote;
  if not found then raise exception 'El lote no corresponde a la nota de venta.'; end if;
  select coalesce(sum(cantidad), 0) into v_ya from public.despachos where nota_venta_id = p_nota and lote_id = p_lote;
  v_res := app.reservado_pedido(n.pedido_id, p_sede, p_lote);
  if p_n > v_res or p_n > d.rollos_equivalentes - v_ya then
    raise exception 'El despacho de % rollos supera lo reservado para esta venta en su centro (% rollos).',
      p_n, greatest(least(v_res, d.rollos_equivalentes - v_ya), 0);
  end if;
end $$;
revoke all on function app.validar_despacho(uuid, uuid, uuid, int) from public, anon, authenticated;

create or replace function app.ejecutar_despacho(p jsonb, p_usuario uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_prod uuid; v_pesos numeric[]; i int; v_n int;
begin
  select array_agg(x::numeric order by o) into v_pesos
    from jsonb_array_elements_text(p -> 'pesos') with ordinality as t(x, o);
  v_n := coalesce(cardinality(v_pesos), 0);
  if v_n = 0 then raise exception 'Registre el peso de cada rollo.'; end if;
  perform 1 from public.notas_venta where id = (p ->> 'nota_id')::uuid for update;
  perform app.validar_despacho((p ->> 'nota_id')::uuid, (p ->> 'sede_id')::uuid, (p ->> 'lote_id')::uuid, v_n);
  select producto_id into v_prod from public.lotes where id = (p ->> 'lote_id')::uuid;
  insert into public.despachos (nota_venta_id, sede_id, lote_id, cantidad, peso_vendido, tolerancia_pct,
    peso_despachado, peso_bascula_publica, placa, receptor, registrado_por)
  values ((p ->> 'nota_id')::uuid, (p ->> 'sede_id')::uuid, (p ->> 'lote_id')::uuid, v_n,
    (p ->> 'peso_vendido')::numeric, (p ->> 'tolerancia')::numeric, (p ->> 'peso_despachado')::numeric,
    nullif(p ->> 'peso_bascula', '')::numeric, p ->> 'placa', p ->> 'receptor', p_usuario)
  returning id into v_id;
  for i in 1 .. v_n loop
    insert into public.despacho_rollos (despacho_id, numero_rollo, peso) values (v_id, i, v_pesos[i]);
  end loop;
  perform app.ajustar_existencia((p ->> 'sede_id')::uuid, v_prod, (p ->> 'lote_id')::uuid, 0, -v_n, 0);
  perform app.movimiento('salida', (p ->> 'sede_id')::uuid, v_prod, (p ->> 'lote_id')::uuid, -v_n, 'despachos', v_id, p_usuario);
  perform app.revisar_agotado((p ->> 'lote_id')::uuid);
  return v_id;
end $$;

create or replace function public.registrar_despacho(p_nota uuid, p_lote uuid, p_pesos numeric[], p_placa text,
  p_receptor text, p_peso_bascula numeric default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  n public.notas_venta%rowtype; ped public.pedidos%rowtype; d public.pedido_detalle%rowtype;
  v_n int := coalesce(cardinality(p_pesos), 0); v_peso numeric;
  v_vendido numeric; v_tol numeric := (app.parametro('tolerancia_despacho_pct'))::text::numeric;
  v_max numeric; v_payload jsonb; v_id uuid; v_sol uuid; v_prom numeric;
begin
  if not app.es('operador_centro') then
    return app.denegar('despachos', 'Solo el operador del centro registra despachos.');
  end if;
  select * into n from public.notas_venta where id = p_nota for update;
  if not found or n.estado <> 'emitida' then
    raise exception 'El despacho exige una nota de venta emitida por el ejecutivo comercial.';
  end if;
  select * into ped from public.pedidos where id = n.pedido_id;
  select * into d from public.pedido_detalle where pedido_id = n.pedido_id and lote_id = p_lote;
  if not found then raise exception 'El lote no corresponde a la nota de venta.'; end if;
  if v_n = 0 then raise exception 'Registre el peso de cada rollo.'; end if;
  if exists (select 1 from unnest(p_pesos) x where x is null or x <= 0 or x > 2000) then
    raise exception 'Cada rollo debe pesar entre 1 y 2.000 kg.';
  end if;
  if coalesce(btrim(p_placa), '') !~ '^[0-9A-Za-z-]{4,10}$' then raise exception 'Indique la placa del vehículo.'; end if;
  if coalesce(length(btrim(p_receptor)), 0) < 3 then raise exception 'Indique quién recibe la carga.'; end if;
  perform app.validar_despacho(p_nota, app.sede(), p_lote, v_n);
  v_peso := (select sum(x) from unnest(p_pesos) x);
  select peso_promedio_rollo into v_prom from public.lotes where id = p_lote;
  v_vendido := case when ped.unidad_venta = 'tonelada'
                    then round(d.cantidad * 1000.0 * v_n / d.rollos_equivalentes, 2)
                    else round(v_n * v_prom, 2) end;
  v_max := round(v_vendido * (1 + v_tol / 100.0), 2);
  v_payload := jsonb_build_object('nota_id', p_nota, 'sede_id', app.sede(), 'lote_id', p_lote, 'pesos', to_jsonb(p_pesos),
    'peso_vendido', v_vendido, 'tolerancia', v_tol, 'peso_despachado', v_peso, 'peso_bascula', p_peso_bascula,
    'placa', upper(btrim(p_placa)), 'receptor', btrim(p_receptor), 'nota', n.numero);
  if ped.unidad_venta = 'tonelada' and v_peso > v_max then
    v_sol := app.solicitud('despacho_exceso', 'notas_venta', p_nota, v_payload,
      format('Despacho de %s kg supera el %s%% sobre %s kg vendidos (máximo %s kg).', v_peso, v_tol, v_vendido, v_max));
    return jsonb_build_object('ok', true, 'estado', 'pendiente', 'solicitud_id', v_sol, 'peso_despachado', v_peso,
                              'peso_maximo', v_max);
  end if;
  v_id := app.ejecutar_despacho(v_payload, (select auth.uid()));
  return jsonb_build_object('ok', true, 'estado', 'despachado', 'despacho_id', v_id, 'peso_despachado', v_peso,
    'peso_vendido', v_vendido, 'peso_maximo', v_max);
end $$;

-- ---------------------------------------------------------------- 5. Ingreso verificado en el servidor
-- Verifica la contraseña contra Supabase Auth, cuenta los fallos y bloquea, todo en una sola llamada. Solo devuelve
-- el correo cuando la contraseña es correcta, así el CI no revela qué cuentas existen.
create or replace function public.preparar_ingreso(p_identificador text, p_clave text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id text := lower(btrim(coalesce(p_identificador, '')));
  v_u record;
  v_ip inet := app.ip_cliente();
  v_min int := coalesce((app.parametro('bloqueo_minutos'))::text::int, 15);
  c_generico constant text := 'Credenciales incorrectas o cuenta bloqueada temporalmente.';
begin
  if v_id = '' or coalesce(p_clave, '') = '' then
    return jsonb_build_object('ok', false, 'mensaje', 'Escriba su CI o correo y su contraseña.');
  end if;
  if v_ip is not null and (select count(*) from public.bitacora_eventos
        where accion = 'login_fallido' and ip = v_ip and fecha_servidor > now() - make_interval(mins => v_min))
     >= coalesce((app.parametro('intentos_ip_max'))::text::int, 20) then
    return jsonb_build_object('ok', false,
      'mensaje', format('Demasiados intentos fallidos desde esta red. Espere %s minutos.', v_min));
  end if;
  select u.id, u.correo, u.estado, a.encrypted_password, a.banned_until into v_u
    from public.usuarios u join auth.users a on a.id = u.id
   where (position('@' in v_id) > 0 and u.correo = v_id) or (position('@' in v_id) = 0 and u.ci = v_id and u.rol_id <> 6);
  if v_u.id is null then
    perform public.registrar_intento_fallido(v_id);
    return jsonb_build_object('ok', false, 'mensaje', c_generico);
  end if;
  if v_u.banned_until is not null and v_u.banned_until > now() then
    return jsonb_build_object('ok', false, 'mensaje', c_generico);
  end if;
  if v_u.encrypted_password is null or v_u.encrypted_password <> extensions.crypt(p_clave, v_u.encrypted_password) then
    perform public.registrar_intento_fallido(v_u.correo);
    return jsonb_build_object('ok', false, 'mensaje', c_generico);
  end if;
  return jsonb_build_object('ok', true, 'correo', v_u.correo);
end $$;
revoke all on function public.preparar_ingreso(text, text) from public;
grant execute on function public.preparar_ingreso(text, text) to anon, authenticated;

-- Las dos funciones anteriores dejan de estar abiertas a visitantes anónimos.
revoke all on function public.correo_para_ingreso(text), public.registrar_intento_fallido(text) from public, anon, authenticated;
grant execute on function public.correo_para_ingreso(text), public.registrar_intento_fallido(text) to service_role;

-- ---------------------------------------------------------------- 6. Cuentas privilegiadas
create or replace function app.privilegiada_protegida(p_usuario uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_usuario is distinct from (select auth.uid()) and app.rol() is distinct from 'superadmin'
     and exists (select 1 from public.usuarios u join public.roles r on r.id = u.rol_id
                  where u.id = p_usuario and r.privilegiado)
$$;
revoke all on function app.privilegiada_protegida(uuid) from public, anon, authenticated;

create or replace function public.restablecer_clave(p_usuario uuid, p_clave text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if app.oculto(p_usuario) then raise exception 'El usuario no existe.'; end if;
  if not app.es('admin_sistema') then
    return app.denegar('usuarios', 'Solo el administrador del sistema restablece contraseñas.');
  end if;
  if not exists (select 1 from public.usuarios where id = p_usuario) then
    raise exception 'La cuenta no existe.';
  end if;
  if app.privilegiada_protegida(p_usuario) then
    return app.denegar('usuarios', 'La contraseña de una cuenta privilegiada (administrador o gerente) solo la cambia su '
      || 'titular o el superadministrador.');
  end if;
  perform app.exigir_clave(p_clave);
  perform app.exigir_historial(p_usuario, p_clave);
  insert into app.historial_claves (usuario_id, hash) select id, encrypted_password from auth.users where id = p_usuario;
  update auth.users
     set encrypted_password = extensions.crypt(p_clave, extensions.gen_salt('bf')),
         raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"debe_cambiar_clave": true}'::jsonb,
         updated_at = now()
   where id = p_usuario;
  delete from auth.sessions where user_id = p_usuario;
  perform app.evento('restablecer_clave', 'usuarios', p_usuario, '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.editar_usuario(p_usuario uuid, p_nombre text, p_ci text, p_correo text,
  p_rol text, p_sede uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_u public.usuarios%rowtype;
  v_rol public.roles%rowtype;
  v_actual public.roles%rowtype;
  v_pendiente boolean := false;
  v_protegida boolean;
begin
  if app.oculto(p_usuario) then raise exception 'El usuario no existe.'; end if;
  if not app.es('admin_sistema') then
    return app.denegar('usuarios', 'Solo el administrador del sistema edita cuentas.');
  end if;
  select * into v_u from public.usuarios where id = p_usuario for update;
  if not found then raise exception 'La cuenta no existe.'; end if;
  select * into v_actual from public.roles where id = v_u.rol_id;
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
  v_protegida := app.privilegiada_protegida(p_usuario);
  -- Cambiar el correo de una cuenta privilegiada permitiría tomarla con «olvidé mi contraseña».
  if v_protegida and p_correo <> v_u.correo then
    return app.denegar('usuarios', 'El correo de una cuenta privilegiada solo lo cambia su titular o el superadministrador.');
  end if;

  update public.usuarios set nombre_completo = p_nombre, ci = p_ci, correo = p_correo, sede_id = p_sede,
         rol_id = case when v_rol.privilegiado or v_actual.privilegiado then rol_id else v_rol.id end
   where id = p_usuario;
  if p_correo <> v_u.correo then
    update auth.users set email = p_correo, updated_at = now() where id = p_usuario;
    update auth.identities set identity_data = identity_data || jsonb_build_object('email', p_correo)
     where user_id = p_usuario and provider = 'email';
  end if;
  -- Dar o quitar un rol privilegiado pasa por la aprobación del gerente.
  if (v_rol.privilegiado or v_actual.privilegiado) and v_rol.id <> v_u.rol_id then
    perform app.solicitud('rol_privilegiado', 'usuarios', p_usuario,
      jsonb_build_object('rol_id', v_rol.id, 'rol', v_rol.codigo, 'usuario', p_nombre, 'rol_anterior', v_actual.codigo),
      case when v_rol.privilegiado then 'Asignación de rol privilegiado: ' || v_rol.nombre
           else 'Retiro de rol privilegiado (' || v_actual.nombre || ' → ' || v_rol.nombre || ')' end);
    v_pendiente := true;
  end if;
  return jsonb_build_object('ok', true, 'pendiente_aprobacion', v_pendiente);
end $$;

-- ---------------------------------------------------------------- 7. Respaldo JSON completo
create or replace function app.exportar_datos() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare t record; v_tablas jsonb := '{}'; v_filas jsonb;
begin
  for t in select tablename from pg_tables where schemaname = 'public' order by tablename loop
    if t.tablename = 'usuarios' then
      -- La única fila que no viaja es la de la cuenta oculta del superadministrador.
      select coalesce(jsonb_agg(to_jsonb(u)), '[]') into v_filas from public.usuarios u where u.rol_id <> 6;
    else
      execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]'') from public.%I x', t.tablename) into v_filas;
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

-- ---------------------------------------------------------------- 8. Sincronización idempotente del teléfono
create table if not exists app.operaciones_dispositivo (
  id uuid primary key,
  usuario_id uuid not null references public.usuarios (id),
  operacion varchar(40) not null,
  resultado jsonb not null,
  fecha timestamptz not null default now()
);
alter table app.operaciones_dispositivo enable row level security;
revoke all on app.operaciones_dispositivo from public, anon, authenticated;

create or replace function public.sincronizar_operacion(p_id uuid, p_operacion text, p_datos jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_prev app.operaciones_dispositivo%rowtype;
  d jsonb := coalesce(p_datos, '{}'::jsonb);
  r jsonb;
begin
  if app.rol() is null then
    raise exception 'Su sesión venció. Vuelva a iniciar sesión.' using errcode = '42501';
  end if;
  select * into v_prev from app.operaciones_dispositivo where id = p_id;
  if found then
    if v_prev.usuario_id <> (select auth.uid()) then
      raise exception 'La operación pertenece a otra cuenta.' using errcode = '42501';
    end if;
    return v_prev.resultado || jsonb_build_object('repetida', true);
  end if;
  r := case p_operacion
    when 'cerrar_orden' then public.cerrar_orden((d ->> 'orden_id')::uuid, (d ->> 'rollos')::int,
                               nullif(d ->> 'fecha_dispositivo', '')::timestamptz, nullif(d ->> 'lote_id', '')::uuid)
    when 'solicitar_correccion_pesaje' then public.solicitar_correccion_pesaje((d ->> 'pesaje_id')::uuid,
                               (d ->> 'peso_bruto')::numeric, (d ->> 'tara')::numeric, (d ->> 'humedad')::numeric,
                               (d ->> 'impurezas')::numeric, d ->> 'motivo')
    when 'solicitar_merma' then public.solicitar_merma((d ->> 'lote_id')::uuid, (d ->> 'cantidad')::numeric::int,
                               d ->> 'causa', d ->> 'descripcion')
    when 'solicitar_ajuste' then public.solicitar_ajuste((d ->> 'producto_id')::uuid, nullif(d ->> 'lote_id', '')::uuid,
                               (d ->> 'cantidad')::numeric, d ->> 'descripcion')
    when 'emitir_guia' then public.emitir_guia((d ->> 'destino')::uuid, d -> 'items')
    when 'recibir_guia' then public.recibir_guia((d ->> 'guia_id')::uuid, coalesce(d -> 'items', '[]'::jsonb))
    when 'registrar_despacho' then public.registrar_despacho((d ->> 'nota_id')::uuid, (d ->> 'lote_id')::uuid,
                               (select array_agg(x::numeric order by o) from jsonb_array_elements_text(d -> 'pesos')
                                  with ordinality as t(x, o)),
                               d ->> 'placa', d ->> 'receptor', nullif(d ->> 'peso_bascula', '')::numeric)
    when 'registrar_peso_bascula' then public.registrar_peso_bascula((d ->> 'despacho_id')::uuid, (d ->> 'peso')::numeric)
  end;
  if r is null then raise exception 'Operación sin conexión desconocida: %.', p_operacion; end if;
  if r ->> 'code' = '42501' then
    raise exception '%', r ->> 'message' using errcode = '42501';
  end if;
  insert into app.operaciones_dispositivo (id, usuario_id, operacion, resultado)
  values (p_id, (select auth.uid()), p_operacion, r);
  return r;
end $$;
revoke all on function public.sincronizar_operacion(uuid, text, jsonb) from public, anon;
grant execute on function public.sincronizar_operacion(uuid, text, jsonb) to authenticated;

-- ---------------------------------------------------------------- 9. Despachos pendientes visibles para el ejecutivo
-- La matriz da al ejecutivo comercial consulta (C) de «Despacho y entrega», pero la función se lo negaba y su
-- pantalla de despachos quedaba sin datos.
do $$
declare d text;
begin
  d := pg_get_functiondef('public.despachos_pendientes()'::regprocedure);
  if position('''ejecutivo_comercial''' in d) = 0 then
    if position('app.es(''operador_centro'', ''gerente_general'')' in d) = 0
       or position('(app.es(''gerente_general'') or e.sede_id = app.sede())' in d) = 0 then
      raise exception 'despachos_pendientes no tiene el texto esperado';
    end if;
    d := replace(d, 'app.es(''operador_centro'', ''gerente_general'')',
                    'app.es(''operador_centro'', ''ejecutivo_comercial'', ''gerente_general'')');
    d := replace(d, '(app.es(''gerente_general'') or e.sede_id = app.sede())',
                    '(app.es(''ejecutivo_comercial'', ''gerente_general'') or e.sede_id = app.sede())');
    execute d;
  end if;
end $$;
