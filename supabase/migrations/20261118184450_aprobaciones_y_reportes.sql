-- Migración 20261118184450 «aprobaciones_y_reportes», copiada del historial de Supabase (supabase_migrations.schema_migrations).
create or replace function app.aplicar_solicitud(s public.solicitudes_aprobacion) returns void
language plpgsql security definer set search_path = '' as $$
declare
  d jsonb := s.datos_propuestos; v_old public.pesajes%rowtype; v_disp numeric; v_prod uuid; it jsonb;
begin
  case s.tipo
  when 'rol_privilegiado' then
    update public.usuarios set rol_id = (d ->> 'rol_id')::smallint, estado = 'activo' where id = s.entidad_id;
    update auth.users set banned_until = null where id = s.entidad_id;
  when 'correccion_pesaje' then
    select * into v_old from public.pesajes where id = s.entidad_id for update;
    if v_old.estado <> 'confirmado' then raise exception 'El pesaje ya no está confirmado.'; end if;
    if exists (select 1 from public.compra_detalle where pesaje_id = v_old.id) then
      raise exception 'El pesaje ya forma parte de una compra y no puede corregirse.';
    end if;
    perform set_config('app.via_aprobacion', 'si', true);
    update public.pesajes set estado = 'corregido' where id = v_old.id;
    perform set_config('app.via_aprobacion', '', true);
    insert into public.pesajes (sede_id, origen, proveedor_id, grano_id, placa, peso_bruto, tara, humedad, impurezas,
      orden_id, estado, fecha_dispositivo, registrado_por)
    values (v_old.sede_id, v_old.origen, v_old.proveedor_id, v_old.grano_id, v_old.placa,
      coalesce((d #>> '{nuevo,peso_bruto}')::numeric, v_old.peso_bruto), coalesce((d #>> '{nuevo,tara}')::numeric, v_old.tara),
      coalesce((d #>> '{nuevo,humedad}')::numeric, v_old.humedad), coalesce((d #>> '{nuevo,impurezas}')::numeric, v_old.impurezas),
      v_old.orden_id, 'confirmado', v_old.fecha_dispositivo, v_old.registrado_por);
  when 'merma' then
    select producto_id into v_prod from public.lotes where id = (d ->> 'lote_id')::uuid;
    if coalesce((d ->> 'descontar')::boolean, true) then
      select disponible into v_disp from public.existencias
       where sede_id = (d ->> 'sede_id')::uuid and lote_id = (d ->> 'lote_id')::uuid;
      if coalesce(v_disp, 0) < (d ->> 'cantidad')::numeric then
        raise exception 'El lote ya no tiene saldo suficiente para esta baja.';
      end if;
      perform app.ajustar_existencia((d ->> 'sede_id')::uuid, v_prod, (d ->> 'lote_id')::uuid, -(d ->> 'cantidad')::numeric, 0, 0);
      perform app.movimiento('merma', (d ->> 'sede_id')::uuid, v_prod, (d ->> 'lote_id')::uuid,
                             -(d ->> 'cantidad')::numeric, 'solicitudes_aprobacion', s.id, s.registrado_por);
      perform app.revisar_agotado((d ->> 'lote_id')::uuid);
    end if;
    insert into public.mermas (lote_id, sede_id, cantidad, causa, descripcion, solicitud_id)
    values ((d ->> 'lote_id')::uuid, (d ->> 'sede_id')::uuid, (d ->> 'cantidad')::int, d ->> 'causa', d ->> 'descripcion', s.id);
  when 'ajuste' then
    perform app.ajustar_existencia((d ->> 'sede_id')::uuid, (d ->> 'producto_id')::uuid, nullif(d ->> 'lote_id', '')::uuid,
                                   (d ->> 'cantidad')::numeric, 0, 0);
    perform app.movimiento('ajuste', (d ->> 'sede_id')::uuid, (d ->> 'producto_id')::uuid, nullif(d ->> 'lote_id', '')::uuid,
                           (d ->> 'cantidad')::numeric, 'solicitudes_aprobacion', s.id, s.registrado_por);
    if nullif(d ->> 'lote_id', '') is not null and (d ->> 'cantidad')::numeric < 0 then
      insert into public.mermas (lote_id, sede_id, cantidad, causa, descripcion, solicitud_id)
      values ((d ->> 'lote_id')::uuid, (d ->> 'sede_id')::uuid, -(d ->> 'cantidad')::int, 'conteo', d ->> 'descripcion', s.id);
      perform app.revisar_agotado((d ->> 'lote_id')::uuid);
    end if;
  when 'cambio_precio' then
    update public.productos set precio_tonelada = (d #>> '{nuevo,precio_tonelada}')::numeric,
           precio_rollo = (d #>> '{nuevo,precio_rollo}')::numeric where id = s.entidad_id;
  when 'producto_nuevo' then
    update public.productos set activo = true where id = s.entidad_id;
  when 'activar_proveedor' then
    update public.proveedores set estado = 'activo' where id = s.entidad_id;
  when 'limite_credito' then
    update public.clientes set limite_credito = (d ->> 'nuevo')::numeric where id = s.entidad_id;
  when 'compra' then
    update public.compras set estado = 'aprobada', aprobado_por = (select auth.uid()) where id = s.entidad_id;
    for it in select * from jsonb_array_elements(coalesce(d -> 'ingresos', '[]'::jsonb)) loop
      perform app.ajustar_existencia((it ->> 'sede_id')::uuid, (it ->> 'producto_id')::uuid, null, (it ->> 'cantidad')::numeric, 0, 0);
      perform app.movimiento('ingreso', (it ->> 'sede_id')::uuid, (it ->> 'producto_id')::uuid, null,
                             (it ->> 'cantidad')::numeric, 'compras', s.entidad_id, s.registrado_por);
    end loop;
  when 'nota_venta' then
    update public.notas_venta set estado = 'emitida' where id = s.entidad_id and estado = 'pendiente';
  when 'anulacion_venta' then
    perform app.anular_nota(s.entidad_id);
  when 'anulacion_cobro' then
    update public.cobros set estado = 'anulado' where id = s.entidad_id and estado = 'vigente';
    if found then
      update public.notas_venta n set saldo = n.saldo + c.monto from public.cobros c
       where c.id = s.entidad_id and n.id = c.nota_venta_id;
    end if;
  when 'despacho_exceso' then
    perform app.ejecutar_despacho(d, s.registrado_por);
  when 'restauracion' then
    perform app.evento('restauracion', 'respaldos', s.id,
      jsonb_build_object('respaldo', d ->> 'respaldo', 'estado', 'aprobada; la ejecuta el flujo de restauración'));
  else
    raise exception 'Tipo de solicitud desconocido.';
  end case;
end $$;

create or replace function app.rechazar_solicitud(s public.solicitudes_aprobacion) returns void
language plpgsql security definer set search_path = '' as $$
begin
  case s.tipo
  when 'compra' then update public.compras set estado = 'anulada' where id = s.entidad_id and estado = 'pendiente';
  when 'nota_venta' then perform app.anular_nota(s.entidad_id);
  else null;
  end case;
end $$;

create or replace function public.resolver_solicitud(p_solicitud uuid, p_aprobar boolean, p_motivo text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.solicitudes_aprobacion%rowtype;
begin
  if not app.es('gerente_general') then
    return app.denegar('solicitudes_aprobacion', 'Solo el gerente general aprueba o rechaza solicitudes.');
  end if;
  select * into s from public.solicitudes_aprobacion where id = p_solicitud for update;
  if not found then raise exception 'La solicitud no existe.'; end if;
  if s.estado <> 'pendiente' then raise exception 'La solicitud ya fue resuelta.'; end if;
  if not p_aprobar and coalesce(btrim(p_motivo), '') = '' then
    raise exception 'Indique el motivo del rechazo.';
  end if;
  update public.solicitudes_aprobacion
     set estado = case when p_aprobar then 'aprobada' else 'rechazada' end,
         aprobado_por = (select auth.uid()), fecha_decision = now(),
         datos_propuestos = datos_propuestos || jsonb_build_object('motivo_decision', nullif(btrim(p_motivo), ''))
   where id = p_solicitud;
  if p_aprobar then perform app.aplicar_solicitud(s); else perform app.rechazar_solicitud(s); end if;
  return jsonb_build_object('ok', true, 'estado', case when p_aprobar then 'aprobada' else 'rechazada' end);
end $$;

create or replace function public.bandeja_aprobaciones(p_estado text default 'pendiente') returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('gerente_general') then
    return app.denegar('solicitudes_aprobacion', 'Solo el gerente general ve la bandeja de aprobaciones.');
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'tipo', s.tipo, 'entidad', s.entidad,
      'entidad_id', s.entidad_id, 'datos', s.datos_propuestos, 'motivo', s.motivo, 'estado', s.estado,
      'fecha_registro', s.fecha_registro, 'fecha_decision', s.fecha_decision,
      'registrado_por', u.nombre_completo, 'rol', r.nombre, 'sede', se.nombre, 'aprobado_por', a.nombre_completo,
      'propia', s.registrado_por = (select auth.uid()))
      order by case when s.estado = 'pendiente' then s.fecha_registro end asc nulls last, s.fecha_decision desc)
    from public.solicitudes_aprobacion s
    join public.usuarios u on u.id = s.registrado_por
    join public.roles r on r.id = u.rol_id
    join public.sedes se on se.id = u.sede_id
    left join public.usuarios a on a.id = s.aprobado_por
    where p_estado = 'todas' or s.estado = p_estado), '[]'::jsonb);
end $$;

create or replace function public.mis_solicitudes() returns jsonb
language sql security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'tipo', s.tipo, 'datos', s.datos_propuestos, 'motivo', s.motivo,
     'estado', s.estado, 'fecha_registro', s.fecha_registro, 'fecha_decision', s.fecha_decision,
     'aprobado_por', a.nombre_completo) order by s.fecha_registro desc), '[]'::jsonb)
  from public.solicitudes_aprobacion s left join public.usuarios a on a.id = s.aprobado_por
  where s.registrado_por = (select auth.uid())
$$;

create or replace function public.reporte_rendimiento(p_desde date default null, p_hasta date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('operador_centro', 'gerente_general') then
    return app.denegar('reportes', 'Su rol no consulta el reporte de producción y rendimiento.');
  end if;
  return coalesce((select jsonb_agg(to_jsonb(v) order by v.fecha_sellado desc)
    from public.v_reporte_rendimiento_ensilado v join public.lotes l on l.id = v.lote_id
    where (app.es('gerente_general') or l.sede_id = app.sede())
      and (p_desde is null or v.fecha_sellado >= p_desde) and (p_hasta is null or v.fecha_sellado <= p_hasta)), '[]'::jsonb);
end $$;

create or replace function public.reporte_existencias() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('operador_centro', 'ejecutivo_comercial', 'cajero_contador', 'gerente_general') then
    return app.denegar('reportes', 'Su rol no consulta existencias.');
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('sede_id', e.sede_id, 'sede', s.nombre, 'producto', p.nombre,
      'sku', p.sku, 'tipo', p.tipo, 'lote_id', l.id, 'lote', l.codigo, 'estado_lote', l.estado,
      'fecha_sellado', l.fecha_sellado, 'dias', current_date - l.fecha_sellado,
      'disponible', e.disponible, 'reservado', e.reservado, 'en_transito', e.en_transito,
      'toneladas', round(e.disponible * coalesce(l.peso_promedio_rollo, 0) / 1000.0, 2))
      order by s.nombre, p.tipo desc, l.fecha_sellado nulls first)
    from public.existencias e join public.sedes s on s.id = e.sede_id join public.productos p on p.id = e.producto_id
    left join public.lotes l on l.id = e.lote_id
    where (e.disponible + e.reservado + e.en_transito) > 0
      and (not app.es('operador_centro') or e.sede_id = app.sede())), '[]'::jsonb);
end $$;

create or replace function public.reporte_rotacion(p_desde date, p_hasta date) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('ejecutivo_comercial', 'cajero_contador', 'gerente_general') then
    return app.denegar('reportes', 'Su rol no consulta la rotación.');
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('sede', x.sede, 'producto', x.producto, 'salidas', x.salidas,
      'stock_inicial', x.stock_final - x.neto, 'stock_final', x.stock_final,
      'stock_promedio', round(((x.stock_final - x.neto) + x.stock_final) / 2.0, 2),
      'rotacion', case when ((x.stock_final - x.neto) + x.stock_final) > 0
                       then round(x.salidas / (((x.stock_final - x.neto) + x.stock_final) / 2.0), 2) else 0 end)
      order by x.sede, x.producto)
    from (select s.nombre as sede, p.nombre as producto,
            coalesce(sum(-m.cantidad) filter (where m.tipo = 'salida' and m.fecha_registro::date between p_desde and p_hasta), 0) as salidas,
            coalesce(sum(m.cantidad) filter (where m.tipo in ('ingreso', 'salida', 'envio', 'recepcion', 'merma', 'ajuste')
                     and m.fecha_registro::date between p_desde and p_hasta), 0) as neto,
            coalesce(sum(m.cantidad) filter (where m.tipo in ('ingreso', 'salida', 'envio', 'recepcion', 'merma', 'ajuste')
                     and m.fecha_registro::date <= p_hasta), 0) as stock_final
          from public.movimientos_inventario m join public.sedes s on s.id = m.sede_id
          join public.productos p on p.id = m.producto_id
          where p.tipo = 'rollo' group by s.nombre, p.nombre) x), '[]'::jsonb);
end $$;

create or replace function public.reporte_ventas(p_desde date, p_hasta date, p_cliente uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('ejecutivo_comercial', 'cajero_contador', 'gerente_general') then
    return app.denegar('reportes', 'Su rol no consulta ventas ni cartera.');
  end if;
  return jsonb_build_object(
    'notas', coalesce((select jsonb_agg(jsonb_build_object('nota_id', n.id, 'numero', n.numero,
        'fecha', n.fecha_registro, 'cliente_id', c.id, 'cliente', c.razon_social, 'tipo_cliente', c.tipo,
        'unidad', p.unidad_venta, 'condicion', n.condicion_pago, 'descuento', n.descuento, 'total', n.total,
        'saldo', n.saldo, 'cobrado', n.total - n.saldo, 'estado', n.estado, 'factura', n.nro_factura,
        'ejecutivo', u.nombre_completo) order by n.numero)
      from public.notas_venta n join public.pedidos p on p.id = n.pedido_id join public.clientes c on c.id = p.cliente_id
      join public.usuarios u on u.id = n.registrado_por
      where n.estado <> 'anulada' and n.fecha_registro::date between p_desde and p_hasta
        and (p_cliente is null or c.id = p_cliente)), '[]'::jsonb),
    'productos', coalesce((select jsonb_agg(jsonb_build_object('producto', x.nombre, 'rollos', x.rollos,
        'toneladas', x.toneladas, 'importe', x.importe) order by x.importe desc)
      from (select pr.nombre, sum(d.rollos_equivalentes) as rollos,
                   round(sum(case when p.unidad_venta = 'tonelada' then d.cantidad
                                  else d.cantidad * l.peso_promedio_rollo / 1000.0 end), 2) as toneladas,
                   round(sum(d.cantidad * d.precio_unitario), 2) as importe
              from public.notas_venta n join public.pedidos p on p.id = n.pedido_id
              join public.pedido_detalle d on d.pedido_id = p.id join public.lotes l on l.id = d.lote_id
              join public.productos pr on pr.id = l.producto_id
             where n.estado <> 'anulada' and n.fecha_registro::date between p_desde and p_hasta
               and (p_cliente is null or p.cliente_id = p_cliente)
             group by pr.nombre) x), '[]'::jsonb),
    'cartera', coalesce((select jsonb_agg(jsonb_build_object('cliente', c.razon_social, 'saldo', sum_saldo,
        'limite_credito', c.limite_credito, 'notas', cnt) order by sum_saldo desc)
      from (select p.cliente_id, sum(n.saldo) as sum_saldo, count(*) as cnt from public.notas_venta n
              join public.pedidos p on p.id = n.pedido_id where n.estado = 'emitida' and n.saldo > 0
             group by p.cliente_id) k join public.clientes c on c.id = k.cliente_id), '[]'::jsonb));
end $$;

create or replace function public.reporte_mermas(p_desde date default null, p_hasta date default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('operador_centro', 'gerente_general') then
    return app.denegar('reportes', 'Su rol no consulta el histórico de merma.');
  end if;
  return jsonb_build_object(
    'bajas', coalesce((select jsonb_agg(jsonb_build_object('sede', s.nombre, 'lote', l.codigo, 'grano', g.nombre,
        'cantidad', m.cantidad, 'causa', m.causa, 'descripcion', m.descripcion, 'solicitado_por', ur.nombre_completo,
        'aprobado_por', ua.nombre_completo, 'fecha', sa.fecha_decision) order by sa.fecha_decision desc)
      from public.mermas m join public.sedes s on s.id = m.sede_id join public.lotes l on l.id = m.lote_id
      join public.productos p on p.id = l.producto_id join public.granos g on g.id = p.grano_id
      join public.solicitudes_aprobacion sa on sa.id = m.solicitud_id
      join public.usuarios ur on ur.id = sa.registrado_por left join public.usuarios ua on ua.id = sa.aprobado_por
      where (app.es('gerente_general') or m.sede_id = app.sede())
        and (p_desde is null or sa.fecha_decision::date >= p_desde) and (p_hasta is null or sa.fecha_decision::date <= p_hasta)), '[]'::jsonb),
    'por_sede', coalesce((select jsonb_agg(jsonb_build_object('sede', x.nombre, 'producidos', x.producidos,
        'bajas', x.bajas, 'porcentaje', case when x.producidos > 0 then round(x.bajas * 100.0 / x.producidos, 1) else 0 end))
      from (select s.nombre,
                   coalesce((select sum(l.rollos_producidos) from public.lotes l where l.sede_id = s.id), 0) as producidos,
                   coalesce((select sum(m.cantidad) from public.mermas m where m.sede_id = s.id), 0) as bajas
              from public.sedes s where s.tipo = 'centro_acopio'
               and (app.es('gerente_general') or s.id = app.sede())) x), '[]'::jsonb));
end $$;

create policy lotes_lectura_por_stock on public.lotes for select to authenticated
  using (app.es('operador_centro') and exists (
    select 1 from public.existencias e where e.lote_id = lotes.id and e.sede_id = app.sede()));

revoke select on public.productos from authenticated;
grant select (id, sku, nombre, tipo, grano_id, unidad, activo) on public.productos to authenticated;

create trigger trg_bitacora after insert or update or delete on app.parametros
  for each row execute function app.registrar_bitacora();

-- Funciones que pueden responder 403 (y registrar el intento) deben ser volátiles
alter function public.sesiones_activas() volatile;
alter function public.obtener_parametros() volatile;
alter function public.respaldos() volatile;
alter function public.productores_activos() volatile;
alter function public.catalogo_precios() volatile;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig, n.nspname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('public', 'app') and p.prokind = 'f' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    if f.nspname = 'public' then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;
grant execute on function app.rol(), app.sede(), app.es(text[]) to authenticated;
grant execute on function public.correo_para_ingreso(text), public.registrar_intento_fallido(text) to anon;

do $$ declare t text; begin
  foreach t in array array['existencias', 'lotes', 'solicitudes_aprobacion', 'guias_transferencia', 'pesajes',
                           'ordenes_ensilado', 'notas_venta', 'cobros', 'despachos', 'movimientos_inventario'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
                   and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
