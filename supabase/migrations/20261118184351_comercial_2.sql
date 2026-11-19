-- Migración 20261118184351 «comercial_2», copiada del historial de Supabase (supabase_migrations.schema_migrations).
create or replace function public.emitir_nota_venta(p_pedido uuid, p_condicion text, p_descuento numeric default 0,
  p_nro_factura text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  p public.pedidos%rowtype; cli public.clientes%rowtype; v_sub numeric; v_total numeric; v_deuda numeric;
  v_excede boolean; v_estado text; v_id uuid; v_num int; v_sol uuid;
begin
  if not app.es('ejecutivo_comercial') then
    return app.denegar('notas_venta', 'Solo el ejecutivo comercial emite notas de venta.');
  end if;
  select * into p from public.pedidos where id = p_pedido for update;
  if not found then raise exception 'El pedido no existe.'; end if;
  if p.estado <> 'pedido' then raise exception 'Solo un pedido confirmado se convierte en nota de venta.'; end if;
  if p_condicion not in ('contado', 'credito') then raise exception 'Seleccione contado o crédito.'; end if;
  p_descuento := coalesce(p_descuento, 0);
  if p_descuento < 0 then raise exception 'El descuento no puede ser negativo.'; end if;
  select * into cli from public.clientes where id = p.cliente_id;
  select round(sum(cantidad * precio_unitario), 2) into v_sub from public.pedido_detalle where pedido_id = p_pedido;
  v_total := v_sub - p_descuento;
  if v_total <= 0 then raise exception 'El descuento no puede igualar ni superar el subtotal.'; end if;
  select coalesce(sum(n.saldo), 0) into v_deuda from public.notas_venta n join public.pedidos x on x.id = n.pedido_id
   where x.cliente_id = cli.id and n.condicion_pago = 'credito' and n.estado in ('emitida', 'pendiente');
  v_excede := p_condicion = 'credito' and v_deuda + v_total > cli.limite_credito;
  v_estado := case when p_descuento > 0 or v_excede then 'pendiente' else 'emitida' end;
  insert into public.notas_venta (pedido_id, condicion_pago, descuento, total, saldo, nro_factura, estado, registrado_por)
  values (p_pedido, p_condicion, p_descuento, v_total, v_total, nullif(btrim(p_nro_factura), ''), v_estado, (select auth.uid()))
  returning id, numero into v_id, v_num;
  update public.pedidos set estado = 'vendido' where id = p_pedido;
  if v_estado = 'pendiente' then
    v_sol := app.solicitud('nota_venta', 'notas_venta', v_id,
      jsonb_build_object('numero', v_num, 'cliente', cli.razon_social, 'subtotal', v_sub, 'descuento', p_descuento,
        'total', v_total, 'condicion', p_condicion, 'excede_credito', v_excede, 'deuda', v_deuda,
        'limite_credito', cli.limite_credito),
      case when v_excede and p_descuento > 0 then 'Descuento y venta sobre el límite de crédito'
           when v_excede then 'Venta sobre el límite de crédito' else 'Descuento sobre el precio de catálogo' end);
  end if;
  return jsonb_build_object('ok', true, 'nota_id', v_id, 'numero', v_num, 'total', v_total, 'estado', v_estado,
                            'solicitud_id', v_sol);
end $$;

create or replace function public.registrar_nro_factura(p_nota uuid, p_nro text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('ejecutivo_comercial') then
    return app.denegar('notas_venta', 'Solo el ejecutivo comercial registra el número de factura.');
  end if;
  if coalesce(btrim(p_nro), '') !~ '^[0-9A-Za-z-]{1,20}$' then raise exception 'Número de factura no válido.'; end if;
  update public.notas_venta set nro_factura = btrim(p_nro) where id = p_nota and nro_factura is null and estado <> 'anulada';
  if not found then raise exception 'La nota no existe, está anulada o ya tiene factura.'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.registrar_cobro(p_nota uuid, p_monto numeric, p_metodo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n public.notas_venta%rowtype; v_id uuid; v_recibo int;
begin
  if not app.es('cajero_contador') then
    return app.denegar('cobros', 'Quien vende no cobra: solo el cajero registra cobros.');
  end if;
  select * into n from public.notas_venta where id = p_nota for update;
  if not found then raise exception 'La nota de venta no existe.'; end if;
  if n.estado <> 'emitida' then
    raise exception 'La nota N.º % no está emitida (estado: %).', n.numero, n.estado;
  end if;
  if coalesce(p_monto, 0) <= 0 then raise exception 'El monto debe ser mayor que cero.'; end if;
  if p_monto > n.saldo then
    raise exception 'El cobro de Bs % supera el saldo de la nota (Bs %).', p_monto, n.saldo;
  end if;
  if p_metodo not in ('efectivo', 'transferencia', 'qr') then raise exception 'Seleccione un método de cobro válido.'; end if;
  insert into public.cobros (nota_venta_id, monto, metodo, estado, registrado_por)
  values (p_nota, p_monto, p_metodo, 'vigente', (select auth.uid())) returning id, recibo into v_id, v_recibo;
  update public.notas_venta set saldo = saldo - p_monto where id = p_nota;
  return jsonb_build_object('ok', true, 'cobro_id', v_id, 'recibo', v_recibo, 'saldo', n.saldo - p_monto);
end $$;

create or replace function public.solicitar_anulacion_venta(p_nota uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n public.notas_venta%rowtype; v_sol uuid;
begin
  if not app.es('ejecutivo_comercial') then
    return app.denegar('notas_venta', 'Solo el ejecutivo comercial solicita anular ventas.');
  end if;
  select * into n from public.notas_venta where id = p_nota;
  if not found or n.estado = 'anulada' then raise exception 'La nota no existe o ya está anulada.'; end if;
  v_sol := app.solicitud('anulacion_venta', 'notas_venta', p_nota,
    jsonb_build_object('numero', n.numero, 'total', n.total, 'saldo', n.saldo), p_motivo);
  return jsonb_build_object('ok', true, 'solicitud_id', v_sol, 'estado', 'pendiente');
end $$;

create or replace function public.solicitar_anulacion_cobro(p_cobro uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c public.cobros%rowtype; v_sol uuid;
begin
  if not app.es('cajero_contador') then
    return app.denegar('cobros', 'Solo el cajero solicita anular cobros.');
  end if;
  select * into c from public.cobros where id = p_cobro;
  if not found or c.estado <> 'vigente' then raise exception 'El cobro no existe o ya está anulado.'; end if;
  v_sol := app.solicitud('anulacion_cobro', 'cobros', p_cobro,
    jsonb_build_object('recibo', c.recibo, 'monto', c.monto), p_motivo);
  return jsonb_build_object('ok', true, 'solicitud_id', v_sol, 'estado', 'pendiente');
end $$;

create or replace function app.anular_nota(p_nota uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare n public.notas_venta%rowtype;
begin
  select * into n from public.notas_venta where id = p_nota for update;
  if exists (select 1 from public.cobros where nota_venta_id = p_nota and estado = 'vigente') then
    raise exception 'La nota tiene cobros vigentes: primero deben anularse los cobros.';
  end if;
  if exists (select 1 from public.despachos where nota_venta_id = p_nota) then
    raise exception 'La nota ya tiene despachos y no puede anularse.';
  end if;
  perform app.liberar_reservas(n.pedido_id);
  update public.notas_venta set estado = 'anulada', saldo = 0 where id = p_nota;
  update public.pedidos set estado = 'cancelado' where id = n.pedido_id;
end $$;

create or replace function app.ejecutar_despacho(p jsonb, p_usuario uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_prod uuid; v_pesos numeric[]; i int; v_n int;
begin
  select array_agg(x::numeric order by o) into v_pesos
    from jsonb_array_elements_text(p -> 'pesos') with ordinality as t(x, o);
  v_n := cardinality(v_pesos);
  select producto_id into v_prod from public.lotes where id = (p ->> 'lote_id')::uuid;
  if coalesce((select reservado from public.existencias where sede_id = (p ->> 'sede_id')::uuid
               and lote_id = (p ->> 'lote_id')::uuid), 0) < v_n then
    raise exception 'El despacho (% rollos) supera el saldo reservado del lote.', v_n;
  end if;
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
  v_n int := coalesce(cardinality(p_pesos), 0); v_res numeric; v_ya int; v_pend int; v_peso numeric;
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
  select reservado into v_res from public.existencias where sede_id = app.sede() and lote_id = p_lote;
  select coalesce(sum(cantidad), 0) into v_ya from public.despachos where nota_venta_id = p_nota and lote_id = p_lote;
  v_pend := d.rollos_equivalentes - v_ya;
  if v_n > coalesce(v_res, 0) or v_n > v_pend then
    raise exception 'El despacho de % rollos supera el saldo del lote (% rollos).', v_n, least(coalesce(v_res, 0), v_pend);
  end if;
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
    'peso_vendido', v_vendido, 'peso_minimo', v_max);
end $$;

create or replace function public.registrar_peso_bascula(p_despacho uuid, p_peso numeric) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('operador_centro', 'ejecutivo_comercial') then
    return app.denegar('despachos', 'Sin permiso para anotar el peso de la báscula pública.');
  end if;
  if coalesce(p_peso, 0) <= 0 then raise exception 'Indique el peso reportado.'; end if;
  update public.despachos set peso_bascula_publica = p_peso where id = p_despacho
     and (app.es('ejecutivo_comercial') or sede_id = app.sede());
  if not found then raise exception 'El despacho no existe.'; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.despachos_pendientes() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('operador_centro', 'gerente_general') then
    return app.denegar('despachos', 'Sin permiso.');
  end if;
  return coalesce((select jsonb_agg(x order by (x ->> 'numero')::int) from (
    select jsonb_build_object('nota_id', n.id, 'numero', n.numero, 'cliente', c.razon_social,
      'unidad', p.unidad_venta, 'lote_id', l.id, 'lote', l.codigo, 'producto', pr.nombre,
      'cantidad', d.cantidad, 'rollos', d.rollos_equivalentes, 'peso_promedio', l.peso_promedio_rollo,
      'despachados', coalesce((select sum(z.cantidad) from public.despachos z where z.nota_venta_id = n.id and z.lote_id = l.id), 0),
      'reservado_sede', e.reservado, 'sede_id', e.sede_id,
      'pendiente_aprobacion', exists (select 1 from public.solicitudes_aprobacion s where s.entidad_id = n.id
                                      and s.tipo = 'despacho_exceso' and s.estado = 'pendiente')) as x
      from public.notas_venta n
      join public.pedidos p on p.id = n.pedido_id
      join public.clientes c on c.id = p.cliente_id
      join public.pedido_detalle d on d.pedido_id = p.id
      join public.lotes l on l.id = d.lote_id
      join public.productos pr on pr.id = l.producto_id
      join public.existencias e on e.lote_id = l.id and e.reservado > 0
     where n.estado = 'emitida' and (app.es('gerente_general') or e.sede_id = app.sede())) q), '[]'::jsonb);
end $$;
