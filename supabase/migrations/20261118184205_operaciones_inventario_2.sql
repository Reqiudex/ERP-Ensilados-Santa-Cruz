-- Migración 20261118184205 «operaciones_inventario_2», copiada del historial de Supabase (supabase_migrations.schema_migrations).
create or replace function public.solicitar_merma(p_lote uuid, p_cantidad integer, p_causa text, p_descripcion text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_disp numeric; v_sol uuid; v_codigo text;
begin
  if not app.es('operador_centro') then
    return app.denegar('mermas', 'Solo el operador del centro solicita bajas de rollos.');
  end if;
  if p_causa not in ('film_roto', 'fermentacion', 'manipuleo', 'traslado', 'conteo') then
    raise exception 'Seleccione una causa válida.';
  end if;
  if coalesce(length(btrim(p_descripcion)), 0) < 10 then
    raise exception 'Describa la baja (al menos 10 caracteres).';
  end if;
  select e.disponible, l.codigo into v_disp, v_codigo from public.existencias e join public.lotes l on l.id = e.lote_id
   where e.lote_id = p_lote and e.sede_id = app.sede();
  if v_disp is null then raise exception 'El lote no tiene stock en su centro.'; end if;
  if coalesce(p_cantidad, 0) <= 0 or p_cantidad > v_disp then
    raise exception 'La cantidad debe estar entre 1 y el saldo disponible (% rollos).', v_disp;
  end if;
  v_sol := app.solicitud('merma', 'lotes', p_lote,
    jsonb_build_object('lote_id', p_lote, 'codigo', v_codigo, 'sede_id', app.sede(), 'cantidad', p_cantidad,
                       'causa', p_causa, 'descripcion', btrim(p_descripcion), 'descontar', true),
    btrim(p_descripcion));
  return jsonb_build_object('ok', true, 'solicitud_id', v_sol, 'estado', 'pendiente');
end $$;

create or replace function public.solicitar_ajuste(p_producto uuid, p_lote uuid, p_cantidad numeric, p_descripcion text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_disp numeric; v_sol uuid;
begin
  if not app.es('operador_centro') then
    return app.denegar('existencias', 'Solo el operador del centro solicita ajustes por conteo.');
  end if;
  if coalesce(p_cantidad, 0) = 0 then raise exception 'Indique la diferencia del conteo.'; end if;
  if coalesce(length(btrim(p_descripcion)), 0) < 10 then
    raise exception 'Describa el ajuste (al menos 10 caracteres).';
  end if;
  select disponible into v_disp from public.existencias
   where sede_id = app.sede() and producto_id = p_producto and lote_id is not distinct from p_lote;
  if p_cantidad < 0 and coalesce(v_disp, 0) < -p_cantidad then
    raise exception 'El ajuste negativo supera el saldo disponible (%).', coalesce(v_disp, 0);
  end if;
  v_sol := app.solicitud('ajuste', 'existencias', coalesce(p_lote, p_producto),
    jsonb_build_object('producto_id', p_producto, 'lote_id', p_lote, 'sede_id', app.sede(), 'cantidad', p_cantidad,
                       'descripcion', btrim(p_descripcion)), btrim(p_descripcion));
  return jsonb_build_object('ok', true, 'solicitud_id', v_sol, 'estado', 'pendiente');
end $$;

create or replace function public.emitir_guia(p_destino uuid, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_guia uuid; v_num int; it jsonb; v_lote uuid; v_cant int; v_disp numeric; v_prod uuid; v_codigo text;
begin
  if not app.es('operador_centro') then
    return app.denegar('guias_transferencia', 'Solo el operador del centro de origen emite guías.');
  end if;
  if p_destino = app.sede() then raise exception 'El destino debe ser otro centro de acopio.'; end if;
  if not exists (select 1 from public.sedes where id = p_destino and tipo = 'centro_acopio' and activa) then
    raise exception 'Seleccione un centro de acopio de destino válido.';
  end if;
  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then raise exception 'Agregue al menos un lote.'; end if;
  insert into public.guias_transferencia (sede_origen, sede_destino, estado, emitido_por, fecha_emision)
  values (app.sede(), p_destino, 'en_transito', (select auth.uid()), now()) returning id, numero into v_guia, v_num;
  for it in select * from jsonb_array_elements(p_items) loop
    v_lote := (it ->> 'lote_id')::uuid; v_cant := (it ->> 'cantidad')::int;
    select e.disponible, e.producto_id, l.codigo into v_disp, v_prod, v_codigo
      from public.existencias e join public.lotes l on l.id = e.lote_id
     where e.lote_id = v_lote and e.sede_id = app.sede() for update of e;
    if v_disp is null then raise exception 'El lote no tiene stock en su centro.'; end if;
    if coalesce(v_cant, 0) <= 0 or v_cant > v_disp then
      raise exception 'La cantidad del lote % debe estar entre 1 y % rollos.', v_codigo, v_disp;
    end if;
    perform app.ajustar_existencia(app.sede(), v_prod, v_lote, -v_cant, 0, v_cant);
    perform app.movimiento('envio', app.sede(), v_prod, v_lote, -v_cant, 'guias_transferencia', v_guia);
    insert into public.guia_detalle (guia_id, lote_id, cantidad_enviada) values (v_guia, v_lote, v_cant);
  end loop;
  return jsonb_build_object('ok', true, 'guia_id', v_guia, 'numero', v_num, 'estado', 'en_transito');
end $$;

create or replace function public.recibir_guia(p_guia uuid, p_items jsonb default '[]'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare g public.guias_transferencia%rowtype; d record; v_rec int; v_dif int := 0; v_sol uuid[] := '{}';
begin
  if not app.es('operador_centro') then
    return app.denegar('guias_transferencia', 'Solo el operador del centro de destino recibe guías.');
  end if;
  select * into g from public.guias_transferencia where id = p_guia for update;
  if not found then raise exception 'La guía no existe.'; end if;
  if g.estado <> 'en_transito' then raise exception 'La guía ya fue recibida.'; end if;
  update public.guias_transferencia set recibido_por = (select auth.uid()) where id = p_guia;
  if g.sede_destino <> app.sede() then
    raise exception 'Solo un operador del centro de destino confirma la recepción.' using errcode = '42501';
  end if;
  for d in select gd.*, l.producto_id, l.codigo from public.guia_detalle gd join public.lotes l on l.id = gd.lote_id
            where gd.guia_id = p_guia loop
    v_rec := null;
    select (x ->> 'cantidad_recibida')::int into v_rec from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) x
     where (x ->> 'lote_id')::uuid = d.lote_id;
    v_rec := coalesce(v_rec, d.cantidad_enviada);
    if v_rec < 0 or v_rec > d.cantidad_enviada then
      raise exception 'Lo recibido del lote % debe estar entre 0 y % rollos.', d.codigo, d.cantidad_enviada;
    end if;
    update public.guia_detalle set cantidad_recibida = v_rec where guia_id = p_guia and lote_id = d.lote_id;
    perform app.ajustar_existencia(g.sede_origen, d.producto_id, d.lote_id, 0, 0, -d.cantidad_enviada);
    if v_rec > 0 then
      perform app.ajustar_existencia(g.sede_destino, d.producto_id, d.lote_id, v_rec, 0, 0);
      perform app.movimiento('recepcion', g.sede_destino, d.producto_id, d.lote_id, v_rec, 'guias_transferencia', p_guia);
    end if;
    if v_rec < d.cantidad_enviada then
      v_dif := v_dif + (d.cantidad_enviada - v_rec);
      v_sol := v_sol || app.solicitud('merma', 'lotes', d.lote_id,
        jsonb_build_object('lote_id', d.lote_id, 'codigo', d.codigo, 'sede_id', g.sede_origen,
          'cantidad', d.cantidad_enviada - v_rec, 'causa', 'traslado', 'descontar', false, 'guia', g.numero,
          'descripcion', format('Diferencia en la guía N.º %s: enviados %s, recibidos %s.', g.numero, d.cantidad_enviada, v_rec)),
        format('Merma de traslado generada al recibir la guía N.º %s', g.numero));
    end if;
    perform app.revisar_agotado(d.lote_id);
  end loop;
  update public.guias_transferencia set estado = 'recibida', fecha_recepcion = now() where id = p_guia;
  return jsonb_build_object('ok', true, 'diferencia', v_dif, 'solicitudes_merma', to_jsonb(v_sol));
end $$;

create or replace function public.solicitar_producto(p_sku text, p_nombre text, p_tipo text, p_grano smallint,
  p_unidad text, p_precio_tonelada numeric, p_precio_rollo numeric, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_sol uuid;
begin
  if not app.es('ejecutivo_comercial') then
    return app.denegar('productos', 'Solo el ejecutivo comercial propone productos.');
  end if;
  p_sku := upper(btrim(coalesce(p_sku, '')));
  if p_sku !~ '^[A-Z0-9-]{3,20}$' then raise exception 'El SKU admite letras, números y guiones (3 a 20).'; end if;
  if exists (select 1 from public.productos where sku = p_sku) then
    raise exception 'Ya existe un producto con el SKU %.', p_sku;
  end if;
  if p_tipo not in ('rollo', 'insumo') then raise exception 'Seleccione un tipo válido.'; end if;
  if p_tipo = 'rollo' and p_grano is null then raise exception 'Un rollo debe indicar el grano.'; end if;
  insert into public.productos (sku, nombre, tipo, grano_id, unidad, precio_tonelada, precio_rollo, activo)
  values (p_sku, btrim(p_nombre), p_tipo, p_grano, p_unidad, coalesce(p_precio_tonelada, 0), coalesce(p_precio_rollo, 0), false)
  returning id into v_id;
  v_sol := app.solicitud('producto_nuevo', 'productos', v_id,
    jsonb_build_object('sku', p_sku, 'nombre', btrim(p_nombre), 'precio_tonelada', p_precio_tonelada,
                       'precio_rollo', p_precio_rollo), coalesce(p_motivo, 'Alta de producto ' || p_sku));
  return jsonb_build_object('ok', true, 'producto_id', v_id, 'solicitud_id', v_sol, 'estado', 'pendiente');
end $$;

create or replace function public.solicitar_cambio_precio(p_producto uuid, p_precio_tonelada numeric,
  p_precio_rollo numeric, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v public.productos%rowtype; v_sol uuid;
begin
  if not app.es('ejecutivo_comercial') then
    return app.denegar('productos', 'Solo el ejecutivo comercial propone precios.');
  end if;
  select * into v from public.productos where id = p_producto;
  if not found then raise exception 'El producto no existe.'; end if;
  if coalesce(p_precio_tonelada, 0) < 0 or coalesce(p_precio_rollo, 0) < 0 then
    raise exception 'Los precios no pueden ser negativos.';
  end if;
  v_sol := app.solicitud('cambio_precio', 'productos', p_producto,
    jsonb_build_object('sku', v.sku, 'antes', jsonb_build_object('precio_tonelada', v.precio_tonelada, 'precio_rollo', v.precio_rollo),
                       'nuevo', jsonb_build_object('precio_tonelada', p_precio_tonelada, 'precio_rollo', p_precio_rollo)),
    p_motivo);
  return jsonb_build_object('ok', true, 'solicitud_id', v_sol, 'estado', 'pendiente');
end $$;

create or replace function public.catalogo_precios() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.es('ejecutivo_comercial', 'cajero_contador', 'gerente_general') then
    return app.denegar('productos', 'Su rol no consulta precios.');
  end if;
  return coalesce((select jsonb_agg(to_jsonb(p) || jsonb_build_object('grano', g.nombre,
      'pendiente', exists (select 1 from public.solicitudes_aprobacion s where s.entidad_id = p.id and s.estado = 'pendiente'))
      order by p.tipo desc, p.sku)
    from public.productos p left join public.granos g on g.id = p.grano_id), '[]'::jsonb);
end $$;
