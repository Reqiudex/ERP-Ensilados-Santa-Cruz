-- Migración 20261118184304 «comercial_1», copiada del historial de Supabase (supabase_migrations.schema_migrations).
create or replace function app.proveedor_nuevo() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.estado = 'inactivo' and (select auth.uid()) is not null then
    perform app.solicitud('activar_proveedor', 'proveedores', new.id,
      jsonb_build_object('razon_social', new.razon_social, 'nit_ci', new.nit_ci, 'tipo', new.tipo),
      'Activación de proveedor nuevo');
  end if;
  return new;
end $$;
create trigger trg_proveedor_nuevo after insert on public.proveedores
  for each row execute function app.proveedor_nuevo();

create or replace function public.solicitar_limite_credito(p_cliente uuid, p_limite numeric, p_motivo text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.clientes%rowtype; v_sol uuid;
begin
  if not app.es('ejecutivo_comercial') then
    return app.denegar('clientes', 'Solo el ejecutivo comercial solicita límites de crédito.');
  end if;
  select * into v from public.clientes where id = p_cliente;
  if not found then raise exception 'El cliente no existe.'; end if;
  if coalesce(p_limite, -1) < 0 then raise exception 'El límite no puede ser negativo.'; end if;
  v_sol := app.solicitud('limite_credito', 'clientes', p_cliente,
    jsonb_build_object('cliente', v.razon_social, 'antes', v.limite_credito, 'nuevo', p_limite), p_motivo);
  return jsonb_build_object('ok', true, 'solicitud_id', v_sol, 'estado', 'pendiente');
end $$;

create or replace function public.registrar_compra(p_proveedor uuid, p_fecha date, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_prov public.proveedores%rowtype; it jsonb; v_total numeric := 0; v_compra uuid; v_pes public.pesajes%rowtype;
  v_cant numeric; v_precio numeric; v_ingresos jsonb := '[]'::jsonb; v_sol uuid;
begin
  if not app.es('ejecutivo_comercial') then
    return app.denegar('compras', 'Solo el ejecutivo comercial registra compras.');
  end if;
  select * into v_prov from public.proveedores where id = p_proveedor;
  if not found then raise exception 'El proveedor no existe.'; end if;
  if v_prov.estado <> 'activo' then
    raise exception 'El proveedor no está activo: su activación debe aprobarla el gerente.';
  end if;
  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then raise exception 'Agregue al menos un ítem.'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    v_precio := (it ->> 'precio_unitario')::numeric;
    if coalesce(v_precio, 0) <= 0 then raise exception 'Indique un precio unitario mayor que cero.'; end if;
    if v_prov.tipo = 'productor' then
      select * into v_pes from public.pesajes where id = (it ->> 'pesaje_id')::uuid;
      if not found or v_pes.estado <> 'confirmado' or v_pes.origen <> 'productor' or v_pes.proveedor_id <> p_proveedor then
        raise exception 'La compra de grano exige pesajes confirmados de ese productor.';
      end if;
      if exists (select 1 from public.compra_detalle where pesaje_id = v_pes.id) then
        raise exception 'El pesaje de la placa % ya está en otra compra.', v_pes.placa;
      end if;
      v_total := v_total + round(v_pes.peso_ajustado / 1000.0 * v_precio, 2);
    else
      v_cant := (it ->> 'cantidad')::numeric;
      if coalesce(v_cant, 0) <= 0 then raise exception 'Indique la cantidad de cada insumo.'; end if;
      if not exists (select 1 from public.productos where id = (it ->> 'producto_id')::uuid and tipo = 'insumo') then
        raise exception 'Seleccione un insumo válido.';
      end if;
      if not exists (select 1 from public.sedes where id = (it ->> 'sede_id')::uuid and tipo = 'centro_acopio') then
        raise exception 'Indique el centro de acopio que recibe el insumo.';
      end if;
      v_total := v_total + round(v_cant * v_precio, 2);
      v_ingresos := v_ingresos || jsonb_build_object('sede_id', it ->> 'sede_id', 'producto_id', it ->> 'producto_id',
                                                     'cantidad', v_cant);
    end if;
  end loop;
  insert into public.compras (proveedor_id, fecha, total, saldo, estado, registrado_por)
  values (p_proveedor, coalesce(p_fecha, current_date), v_total, v_total, 'pendiente', (select auth.uid()))
  returning id into v_compra;
  for it in select * from jsonb_array_elements(p_items) loop
    if v_prov.tipo = 'productor' then
      select * into v_pes from public.pesajes where id = (it ->> 'pesaje_id')::uuid;
      insert into public.compra_detalle (compra_id, pesaje_id, cantidad, precio_unitario)
      values (v_compra, v_pes.id, round(v_pes.peso_ajustado / 1000.0, 2), (it ->> 'precio_unitario')::numeric);
    else
      insert into public.compra_detalle (compra_id, producto_id, cantidad, precio_unitario)
      values (v_compra, (it ->> 'producto_id')::uuid, (it ->> 'cantidad')::numeric, (it ->> 'precio_unitario')::numeric);
    end if;
  end loop;
  v_sol := app.solicitud('compra', 'compras', v_compra,
    jsonb_build_object('proveedor', v_prov.razon_social, 'total', v_total, 'ingresos', v_ingresos),
    'Aprobación de compra a ' || v_prov.razon_social);
  return jsonb_build_object('ok', true, 'compra_id', v_compra, 'total', v_total, 'estado', 'pendiente',
                            'solicitud_id', v_sol);
end $$;

create or replace function public.registrar_pago(p_compra uuid, p_monto numeric, p_metodo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare c public.compras%rowtype; v_id uuid;
begin
  if not app.es('cajero_contador') then
    return app.denegar('pagos', 'Solo el cajero registra pagos a proveedores.');
  end if;
  select * into c from public.compras where id = p_compra for update;
  if not found then raise exception 'La compra no existe.'; end if;
  if c.estado <> 'aprobada' then
    raise exception 'Solo se pagan compras aprobadas por el gerente (estado actual: %).', c.estado;
  end if;
  if coalesce(p_monto, 0) <= 0 then raise exception 'El monto debe ser mayor que cero.'; end if;
  if p_monto > c.saldo then
    raise exception 'El pago de Bs % supera el saldo pendiente de Bs %.', p_monto, c.saldo;
  end if;
  if p_metodo not in ('efectivo', 'transferencia', 'qr') then raise exception 'Seleccione un método de pago válido.'; end if;
  insert into public.pagos (compra_id, monto, metodo, registrado_por) values (p_compra, p_monto, p_metodo, (select auth.uid()))
  returning id into v_id;
  update public.compras set saldo = saldo - p_monto,
         estado = case when saldo - p_monto = 0 then 'pagada' else estado end where id = p_compra;
  return jsonb_build_object('ok', true, 'pago_id', v_id, 'saldo', c.saldo - p_monto);
end $$;

create or replace function app.asignar_peps(p_pedido uuid, p_producto uuid, p_cantidad numeric, p_unidad text,
  p_reservar boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_prod public.productos%rowtype; v_precio numeric; v_rest numeric := p_cantidad; e record;
  v_r int; v_cant numeric; v_nec int;
begin
  select * into v_prod from public.productos where id = p_producto and tipo = 'rollo' and activo;
  if not found then raise exception 'Seleccione un producto rollo activo.'; end if;
  if coalesce(p_cantidad, 0) <= 0 then raise exception 'La cantidad debe ser mayor que cero.'; end if;
  if p_unidad = 'rollo' and p_cantidad <> trunc(p_cantidad) then
    raise exception 'La venta por rollo se expresa en rollos enteros.';
  end if;
  v_precio := case p_unidad when 'tonelada' then v_prod.precio_tonelada else v_prod.precio_rollo end;
  for e in select x.sede_id, x.lote_id, x.disponible, l.peso_promedio_rollo
             from public.existencias x join public.lotes l on l.id = x.lote_id
            where x.producto_id = p_producto and l.estado = 'apto' and x.disponible > 0
            order by l.fecha_sellado, l.codigo, x.sede_id
            for update of x loop
    exit when v_rest <= 0;
    if p_unidad = 'rollo' then
      v_r := least(e.disponible, v_rest)::int; v_cant := v_r; v_rest := v_rest - v_r;
    else
      v_nec := greatest(1, round(v_rest * 1000 / e.peso_promedio_rollo))::int;
      if v_nec <= e.disponible then
        v_r := v_nec; v_cant := v_rest; v_rest := 0;
      else
        v_r := e.disponible::int; v_cant := round(v_r * e.peso_promedio_rollo / 1000.0, 2); v_rest := v_rest - v_cant;
      end if;
    end if;
    insert into public.pedido_detalle as d (pedido_id, lote_id, cantidad, rollos_equivalentes, precio_unitario)
    values (p_pedido, e.lote_id, v_cant, v_r, v_precio)
    on conflict (pedido_id, lote_id) do update
       set cantidad = d.cantidad + excluded.cantidad, rollos_equivalentes = d.rollos_equivalentes + excluded.rollos_equivalentes;
    if p_reservar then
      perform app.ajustar_existencia(e.sede_id, p_producto, e.lote_id, -v_r, v_r, 0);
      perform app.movimiento('reserva', e.sede_id, p_producto, e.lote_id, v_r, 'pedidos', p_pedido);
    end if;
  end loop;
  if v_rest > 0 then
    raise exception 'Stock apto insuficiente de %: faltan % %.', v_prod.nombre, round(v_rest, 2),
      case p_unidad when 'tonelada' then 't' else 'rollos' end;
  end if;
end $$;

create or replace function public.registrar_pedido(p_cliente uuid, p_unidad text, p_items jsonb,
  p_estado text default 'pedido') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; it jsonb;
begin
  if not app.es('ejecutivo_comercial') then
    return app.denegar('pedidos', 'Solo el ejecutivo comercial registra cotizaciones y pedidos.');
  end if;
  if p_unidad not in ('tonelada', 'rollo') then raise exception 'Seleccione la unidad de venta.'; end if;
  if p_estado not in ('cotizacion', 'pedido') then raise exception 'Estado no válido.'; end if;
  if not exists (select 1 from public.clientes where id = p_cliente) then raise exception 'Seleccione un cliente.'; end if;
  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then raise exception 'Agregue al menos un producto.'; end if;
  perform app.promover_lotes();
  insert into public.pedidos (cliente_id, unidad_venta, estado, registrado_por)
  values (p_cliente, p_unidad, p_estado, (select auth.uid())) returning id into v_id;
  for it in select * from jsonb_array_elements(p_items) loop
    perform app.asignar_peps(v_id, (it ->> 'producto_id')::uuid, (it ->> 'cantidad')::numeric, p_unidad,
                             p_estado = 'pedido');
  end loop;
  return jsonb_build_object('ok', true, 'pedido_id', v_id, 'estado', p_estado,
    'detalle', (select jsonb_agg(jsonb_build_object('lote', l.codigo, 'fecha_sellado', l.fecha_sellado,
                 'cantidad', d.cantidad, 'rollos', d.rollos_equivalentes, 'precio_unitario', d.precio_unitario))
                from public.pedido_detalle d join public.lotes l on l.id = d.lote_id where d.pedido_id = v_id));
end $$;

create or replace function app.liberar_reservas(p_pedido uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare r record; v_res numeric;
begin
  for r in select m.sede_id, m.producto_id, m.lote_id, sum(m.cantidad) as reservado
             from public.movimientos_inventario m
            where m.documento_tipo = 'pedidos' and m.documento_id = p_pedido and m.tipo = 'reserva'
            group by m.sede_id, m.producto_id, m.lote_id loop
    v_res := r.reservado - coalesce((select sum(d.cantidad) from public.despachos d
        join public.notas_venta n on n.id = d.nota_venta_id
       where n.pedido_id = p_pedido and d.sede_id = r.sede_id and d.lote_id = r.lote_id), 0);
    if v_res > 0 then
      perform app.ajustar_existencia(r.sede_id, r.producto_id, r.lote_id, v_res, -v_res, 0);
      perform app.movimiento('reserva', r.sede_id, r.producto_id, r.lote_id, -v_res, 'pedidos', p_pedido);
    end if;
  end loop;
end $$;

create or replace function public.confirmar_pedido(p_pedido uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare p public.pedidos%rowtype; r record; v_lineas jsonb;
begin
  if not app.es('ejecutivo_comercial') then
    return app.denegar('pedidos', 'Solo el ejecutivo comercial confirma pedidos.');
  end if;
  select * into p from public.pedidos where id = p_pedido for update;
  if not found then raise exception 'La cotización no existe.'; end if;
  if p.estado <> 'cotizacion' then raise exception 'Solo se confirma una cotización.'; end if;
  perform app.promover_lotes();
  select jsonb_agg(jsonb_build_object('producto_id', t.producto_id, 'cantidad', t.cantidad)) into v_lineas
    from (select l2.producto_id, sum(d.cantidad) as cantidad from public.pedido_detalle d
            join public.lotes l2 on l2.id = d.lote_id where d.pedido_id = p_pedido group by l2.producto_id) t;
  delete from public.pedido_detalle where pedido_id = p_pedido;
  for r in select * from jsonb_array_elements(coalesce(v_lineas, '[]'::jsonb)) loop
    perform app.asignar_peps(p_pedido, (r.value ->> 'producto_id')::uuid, (r.value ->> 'cantidad')::numeric,
                             p.unidad_venta, true);
  end loop;
  update public.pedidos set estado = 'pedido' where id = p_pedido;
  return jsonb_build_object('ok', true, 'estado', 'pedido');
end $$;

create or replace function public.cancelar_pedido(p_pedido uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare p public.pedidos%rowtype;
begin
  if not app.es('ejecutivo_comercial') then
    return app.denegar('pedidos', 'Solo el ejecutivo comercial cancela pedidos.');
  end if;
  select * into p from public.pedidos where id = p_pedido for update;
  if not found then raise exception 'El pedido no existe.'; end if;
  if p.estado not in ('cotizacion', 'pedido') then
    raise exception 'Un pedido vendido se anula con una solicitud de anulación de la nota de venta.';
  end if;
  if p.estado = 'pedido' then perform app.liberar_reservas(p_pedido); end if;
  update public.pedidos set estado = 'cancelado' where id = p_pedido;
  return jsonb_build_object('ok', true);
end $$;
