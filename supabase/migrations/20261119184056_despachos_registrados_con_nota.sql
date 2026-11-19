-- Lista de despachos con el número de nota de venta. El operador no lee notas_venta (datos comerciales), pero sí
-- necesita ver a qué nota corresponde cada despacho de su centro. Respeta las mismas reglas que despachos_lectura.
create or replace function public.despachos_registrados() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not app.es('operador_centro', 'ejecutivo_comercial', 'gerente_general') then
    return app.denegar('despachos', 'Su rol no consulta los despachos.');
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', d.id, 'cantidad', d.cantidad, 'peso_vendido', d.peso_vendido, 'tolerancia_pct', d.tolerancia_pct,
      'peso_despachado', d.peso_despachado, 'peso_bascula_publica', d.peso_bascula_publica, 'placa', d.placa,
      'receptor', d.receptor, 'fecha_registro', d.fecha_registro,
      'lotes', jsonb_build_object('codigo', l.codigo), 'sedes', jsonb_build_object('nombre', s.nombre),
      'notas_venta', jsonb_build_object('numero', n.numero),
      'despacho_rollos', coalesce((select jsonb_agg(jsonb_build_object('numero_rollo', r.numero_rollo, 'peso', r.peso) order by r.numero_rollo)
                                   from public.despacho_rollos r where r.despacho_id = d.id), '[]'::jsonb))
      order by d.fecha_registro desc)
    from (select * from public.despachos x
           where app.es('ejecutivo_comercial', 'gerente_general') or x.sede_id = app.sede()
           order by x.fecha_registro desc limit 200) d
    join public.lotes l on l.id = d.lote_id join public.sedes s on s.id = d.sede_id
    left join public.notas_venta n on n.id = d.nota_id), '[]'::jsonb);
end $$;
revoke all on function public.despachos_registrados() from public, anon;
grant execute on function public.despachos_registrados() to authenticated;
