-- Migración 20261118184126 «operaciones_inventario_1», copiada del historial de Supabase (supabase_migrations.schema_migrations).
create sequence if not exists app.seq_lote;

create or replace function app.ajustar_existencia(p_sede uuid, p_producto uuid, p_lote uuid,
  p_disponible numeric, p_reservado numeric, p_transito numeric) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_disponible >= 0 and p_reservado >= 0 and p_transito >= 0 then
    insert into public.existencias as e (sede_id, producto_id, lote_id, disponible, reservado, en_transito)
    values (p_sede, p_producto, p_lote, p_disponible, p_reservado, p_transito)
    on conflict (sede_id, producto_id, lote_id) do update
       set disponible = e.disponible + p_disponible,
           reservado = e.reservado + p_reservado,
           en_transito = e.en_transito + p_transito;
  else
    update public.existencias
       set disponible = disponible + p_disponible,
           reservado = reservado + p_reservado,
           en_transito = en_transito + p_transito
     where sede_id = p_sede and producto_id = p_producto and lote_id is not distinct from p_lote;
    if not found then raise exception 'Saldo insuficiente para la operación.'; end if;
  end if;
exception when check_violation then
  raise exception 'Saldo insuficiente para la operación.';
end $$;

create or replace function app.movimiento(p_tipo text, p_sede uuid, p_producto uuid, p_lote uuid,
  p_cantidad numeric, p_doc_tipo text, p_doc_id uuid, p_usuario uuid default null) returns void
language sql security definer set search_path = '' as $$
  insert into public.movimientos_inventario (tipo, sede_id, producto_id, lote_id, cantidad, documento_tipo,
    documento_id, registrado_por)
  values (p_tipo, p_sede, p_producto, p_lote, p_cantidad, p_doc_tipo, p_doc_id,
          coalesce(p_usuario, (select auth.uid())));
$$;

create or replace function app.revisar_agotado(p_lote uuid) returns void
language sql security definer set search_path = '' as $$
  update public.lotes l set estado = 'agotado'
   where l.id = p_lote and l.estado <> 'agotado'
     and coalesce((select sum(disponible + reservado + en_transito) from public.existencias where lote_id = p_lote), 0) = 0;
$$;

create or replace function app.promover_lotes() returns int
language plpgsql security definer set search_path = '' as $$
declare v_n int;
begin
  update public.lotes l set estado = 'apto'
    from public.productos p, public.granos g
   where p.id = l.producto_id and g.id = p.grano_id and l.estado = 'fermentacion'
     and l.fecha_sellado + g.dias_fermentacion <= current_date
     and not exists (select 1 from public.revisiones_fermentacion r where r.lote_id = l.id and r.estado_film = 'danado');
  get diagnostics v_n = row_count;
  return v_n;
end $$;

create or replace function public.actualizar_lotes_aptos() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('operador_centro', 'gerente_general', 'ejecutivo_comercial') then
    return app.denegar('lotes', 'Sin permiso para actualizar la fermentación.');
  end if;
  return jsonb_build_object('ok', true, 'promovidos', app.promover_lotes());
end $$;

create or replace function app.revision_fermentacion() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.estado_film = 'danado' then
    update public.lotes set estado = 'observado' where id = new.lote_id and estado in ('fermentacion', 'apto');
  end if;
  return new;
end $$;
create trigger trg_revision_fermentacion after insert on public.revisiones_fermentacion
  for each row execute function app.revision_fermentacion();

create or replace function public.productores_activos() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.es('operador_centro', 'gerente_general') then
    return app.denegar('proveedores', 'Sin permiso.');
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'razon_social', razon_social, 'nit_ci', nit_ci)
           order by razon_social) from public.proveedores where tipo = 'productor' and estado = 'activo'), '[]'::jsonb);
end $$;

create or replace function public.solicitar_correccion_pesaje(p_pesaje uuid, p_peso_bruto numeric, p_tara numeric,
  p_humedad numeric, p_impurezas numeric, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v public.pesajes%rowtype; v_sol uuid;
begin
  if not app.es('operador_centro') then
    return app.denegar('pesajes', 'Solo el operador del centro solicita correcciones de pesaje.');
  end if;
  select * into v from public.pesajes where id = p_pesaje;
  if not found or v.sede_id <> app.sede() then raise exception 'El pesaje no existe en su centro.'; end if;
  if v.estado <> 'confirmado' then raise exception 'Solo se corrige un pesaje confirmado.'; end if;
  if p_peso_bruto <= p_tara then raise exception 'El peso bruto debe ser mayor que la tara.'; end if;
  if exists (select 1 from public.solicitudes_aprobacion where entidad_id = p_pesaje and estado = 'pendiente') then
    raise exception 'Ya hay una corrección pendiente para este pesaje.';
  end if;
  v_sol := app.solicitud('correccion_pesaje', 'pesajes', p_pesaje,
    jsonb_build_object('antes', jsonb_build_object('peso_bruto', v.peso_bruto, 'tara', v.tara, 'humedad', v.humedad,
                         'impurezas', v.impurezas, 'placa', v.placa),
                       'nuevo', jsonb_build_object('peso_bruto', p_peso_bruto, 'tara', p_tara, 'humedad', p_humedad,
                         'impurezas', p_impurezas)), p_motivo);
  return jsonb_build_object('ok', true, 'solicitud_id', v_sol, 'estado', 'pendiente');
end $$;

create or replace function public.cerrar_orden(p_orden uuid, p_rollos integer, p_fecha_dispositivo timestamptz default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  o public.ordenes_ensilado%rowtype;
  g public.granos%rowtype;
  v_n int; v_kg numeric; v_prod uuid; v_lote uuid; v_codigo text; v_falta text[] := '{}';
  c record; v_disp numeric; v_rend numeric; v_alerta text;
  v_fecha timestamptz := coalesce(p_fecha_dispositivo, now());
begin
  if not app.es('operador_centro') then
    return app.denegar('ordenes_ensilado', 'Solo el operador del centro cierra órdenes de ensilado.');
  end if;
  select * into o from public.ordenes_ensilado where id = p_orden for update;
  if not found or o.sede_id <> app.sede() then raise exception 'La orden no existe en su centro.'; end if;
  if o.estado <> 'abierta' then raise exception 'La orden ya está cerrada.'; end if;
  if coalesce(p_rollos, 0) <= 0 then raise exception 'Indique la cantidad de rollos obtenidos.'; end if;
  select * into g from public.granos where id = o.grano_id;
  select count(*), coalesce(sum(peso_ajustado), 0) into v_n, v_kg
    from public.pesajes where orden_id = p_orden and estado = 'confirmado';
  if v_n = 0 then raise exception 'La orden no tiene pesajes confirmados.'; end if;

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
  insert into public.lotes (codigo, orden_id, producto_id, sede_id, fecha_sellado, rollos_producidos,
    peso_promedio_rollo, estado)
  values (v_codigo, p_orden, v_prod, o.sede_id, v_fecha::date, p_rollos, round(v_kg / p_rollos, 2), 'fermentacion')
  returning id into v_lote;
  perform app.ajustar_existencia(o.sede_id, v_prod, v_lote, p_rollos, 0, 0);
  perform app.movimiento('ingreso', o.sede_id, v_prod, v_lote, p_rollos, 'lotes', v_lote);

  update public.ordenes_ensilado set estado = 'cerrada', fecha_cierre = v_fecha, rollos_obtenidos = p_rollos
   where id = p_orden;

  v_rend := round(p_rollos / (v_kg / 1000.0), 2);
  if v_rend < g.rollos_ton_min or v_rend > g.rollos_ton_max then
    v_alerta := format('Rendimiento de %s rollos/t fuera del rango normal (%s a %s).', v_rend, g.rollos_ton_min, g.rollos_ton_max);
  end if;
  return jsonb_build_object('ok', true, 'lote_id', v_lote, 'codigo', v_codigo, 'estado', 'fermentacion',
    'toneladas', round(v_kg / 1000.0, 3), 'rendimiento', v_rend, 'alerta', v_alerta);
end $$;
