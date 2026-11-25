-- En una base creada desde cero, 20261118113851 corre antes de que existan las vistas y no les quita el acceso
-- anónimo. En la base en línea ya no lo tienen; esto lo deja igual en cualquier base nueva.
revoke all on public.v_reporte_rendimiento_ensilado, public.v_reporte_existencias_rotacion,
  public.v_reporte_ventas_producto, public.v_reporte_historico_mermas from anon;
