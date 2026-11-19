-- Filtros de los reportes: el período se ordena solo (si «desde» es posterior a «hasta» se intercambian), una fecha
-- vacía significa «sin límite» en los cuatro reportes, y la cartera respeta el cliente elegido.
do $$
declare f text; d text;
begin
  foreach f in array array['public.reporte_ventas(date,date,uuid)', 'public.reporte_rotacion(date,date)',
                           'public.reporte_rendimiento(date,date)', 'public.reporte_mermas(date,date)'] loop
    d := pg_get_functiondef(f::regprocedure);
    d := replace(d, E'AS $function$\nbegin\n', E'AS $function$\ndeclare v_tmp date;\nbegin\n  if p_desde > p_hasta then v_tmp := p_desde; p_desde := p_hasta; p_hasta := v_tmp; end if;\n  p_desde := coalesce(p_desde, date ''2000-01-01''); p_hasta := coalesce(p_hasta, date ''2999-12-31'');\n');
    if f like 'public.reporte_ventas%' then
      d := replace(d, $r$where n.estado = 'emitida' and n.saldo > 0$r$,
                      $r$where n.estado = 'emitida' and n.saldo > 0 and (p_cliente is null or p.cliente_id = p_cliente)$r$);
    end if;
    if position('declare v_tmp' in d) = 0 then raise exception 'No se pudo ajustar %', f; end if;
    execute d;
  end loop;
end $$;
