-- Migración 20261118192703 «ajustes_lectura_y_fk_duplicada», copiada del historial de Supabase (supabase_migrations.schema_migrations).
-- Llave foránea duplicada de una versión anterior (la API no podía elegir la relación pesajes → órdenes)
alter table public.pesajes drop constraint if exists fk_pesaje_orden_ensilado;

-- El operador ve los lotes de las guías que salen o llegan a su centro
create policy lotes_lectura_por_guia on public.lotes for select to authenticated
  using (app.es('operador_centro') and exists (
    select 1 from public.guia_detalle d join public.guias_transferencia g on g.id = d.guia_id
     where d.lote_id = lotes.id and app.sede() in (g.sede_origen, g.sede_destino)));

-- Notas de venta con cliente para el cajero (consulta notas pero no pedidos, según la matriz)
create or replace function public.notas_venta_detalle() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not app.es('ejecutivo_comercial', 'cajero_contador', 'gerente_general') then
    return app.denegar('notas_venta', 'Su rol no consulta notas de venta.');
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', n.id, 'numero', n.numero, 'condicion_pago', n.condicion_pago, 'descuento', n.descuento, 'total', n.total,
      'saldo', n.saldo, 'nro_factura', n.nro_factura, 'estado', n.estado, 'fecha_registro', n.fecha_registro,
      'pedidos', jsonb_build_object('unidad_venta', p.unidad_venta,
                 'clientes', jsonb_build_object('razon_social', c.razon_social, 'tipo', c.tipo, 'limite_credito', c.limite_credito)),
      'cobros', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'recibo', x.recibo, 'monto', x.monto, 'metodo', x.metodo,
                  'estado', x.estado, 'fecha_registro', x.fecha_registro) order by x.recibo) from public.cobros x where x.nota_venta_id = n.id), '[]'::jsonb),
      'despachos', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'cantidad', d.cantidad, 'peso_despachado', d.peso_despachado,
                  'fecha_registro', d.fecha_registro)) from public.despachos d where d.nota_venta_id = n.id), '[]'::jsonb))
      order by n.numero desc)
    from public.notas_venta n join public.pedidos p on p.id = n.pedido_id join public.clientes c on c.id = p.cliente_id), '[]'::jsonb);
end $$;
revoke all on function public.notas_venta_detalle() from public, anon;
grant execute on function public.notas_venta_detalle() to authenticated;
