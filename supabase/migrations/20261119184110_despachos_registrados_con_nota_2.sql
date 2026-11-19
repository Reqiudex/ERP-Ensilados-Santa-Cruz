-- Corrige el nombre de la columna de la nota de venta en la función anterior.
do $$ declare d text; begin
  d := replace(pg_get_functiondef('public.despachos_registrados()'::regprocedure), 'n.id = d.nota_id', 'n.id = d.nota_venta_id');
  execute d;
end $$;
