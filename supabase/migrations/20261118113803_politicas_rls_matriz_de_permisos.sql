-- Migración 20261118113803 «politicas_rls_matriz_de_permisos», copiada del historial de Supabase (supabase_migrations.schema_migrations).
-- Políticas RLS según la matriz de permisos por operación y por rol (Tabla 11 de la tesis).
-- Lectura: lo que la matriz marca con C (consulta). Escritura directa: solo los registros simples que la matriz marca con R.
-- Toda operación que cambia stock, saldos o estados (aprobar, cerrar orden, guía, merma, venta, cobro, pago, despacho)
-- se hace con funciones transaccionales SECURITY DEFINER que validan el rol.

-- Catálogos visibles para todo usuario activo
create policy sedes_lectura on sedes for select to authenticated using (app.rol() is not null);
create policy roles_lectura on roles for select to authenticated using (app.rol() is not null);
create policy granos_lectura on granos for select to authenticated using (app.rol() is not null);
create policy productos_lectura on productos for select to authenticated using (app.rol() is not null);

-- Seguridad
create policy usuarios_lectura on usuarios for select to authenticated
  using (id = (select auth.uid()) or app.es('admin_sistema', 'gerente_general'));
create policy solicitudes_lectura on solicitudes_aprobacion for select to authenticated
  using (registrado_por = (select auth.uid()) or app.es('gerente_general'));
create policy solicitudes_registro on solicitudes_aprobacion for insert to authenticated
  with check (registrado_por = (select auth.uid()) and estado = 'pendiente' and aprobado_por is null and app.rol() is not null);
create policy bitacora_lectura on bitacora_eventos for select to authenticated
  using (app.es('admin_sistema', 'gerente_general'));

-- Operaciones (operador: solo su sede; gerente: consulta todo)
create policy pesajes_lectura on pesajes for select to authenticated
  using (app.es('gerente_general')
      or (app.es('operador_centro') and sede_id = app.sede())
      or (app.es('ejecutivo_comercial') and origen = 'productor'));
create policy pesajes_registro on pesajes for insert to authenticated
  with check (app.es('operador_centro') and sede_id = app.sede()
      and registrado_por = (select auth.uid()) and estado = 'confirmado');

create policy ordenes_lectura on ordenes_ensilado for select to authenticated
  using (app.es('gerente_general') or (app.es('operador_centro') and sede_id = app.sede()));
create policy ordenes_registro on ordenes_ensilado for insert to authenticated
  with check (app.es('operador_centro') and sede_id = app.sede()
      and registrado_por = (select auth.uid()) and estado = 'abierta');

create policy consumos_lectura on consumos_insumo for select to authenticated
  using (app.es('gerente_general') or (app.es('operador_centro') and exists (
    select 1 from ordenes_ensilado o where o.id = orden_id and o.sede_id = app.sede())));
create policy consumos_registro on consumos_insumo for insert to authenticated
  with check (app.es('operador_centro') and exists (
    select 1 from ordenes_ensilado o where o.id = orden_id and o.sede_id = app.sede() and o.estado = 'abierta'));

create policy revisiones_lectura on revisiones_fermentacion for select to authenticated
  using (app.es('gerente_general') or (app.es('operador_centro') and exists (
    select 1 from lotes l where l.id = lote_id and l.sede_id = app.sede())));
create policy revisiones_registro on revisiones_fermentacion for insert to authenticated
  with check (app.es('operador_centro') and registrado_por = (select auth.uid()) and exists (
    select 1 from lotes l where l.id = lote_id and l.sede_id = app.sede()));

-- Inventario (stock: operador su sede, ejecutivo y gerente todo; nadie lo escribe directamente)
create policy lotes_lectura on lotes for select to authenticated
  using (app.es('ejecutivo_comercial', 'gerente_general') or (app.es('operador_centro') and sede_id = app.sede()));
create policy existencias_lectura on existencias for select to authenticated
  using (app.es('ejecutivo_comercial', 'gerente_general') or (app.es('operador_centro') and sede_id = app.sede()));
create policy movimientos_lectura on movimientos_inventario for select to authenticated
  using (app.es('ejecutivo_comercial', 'gerente_general') or (app.es('operador_centro') and sede_id = app.sede()));
create policy guias_lectura on guias_transferencia for select to authenticated
  using (app.es('ejecutivo_comercial', 'gerente_general')
      or (app.es('operador_centro') and app.sede() in (sede_origen, sede_destino)));
create policy guia_detalle_lectura on guia_detalle for select to authenticated
  using (exists (select 1 from guias_transferencia g where g.id = guia_id));
create policy mermas_lectura on mermas for select to authenticated
  using (app.es('gerente_general') or (app.es('operador_centro') and sede_id = app.sede()));

-- Comercial y abastecimiento
create policy clientes_lectura on clientes for select to authenticated
  using (app.es('ejecutivo_comercial', 'cajero_contador', 'gerente_general'));
create policy clientes_registro on clientes for insert to authenticated
  with check (app.es('ejecutivo_comercial') and limite_credito = 0);
create policy proveedores_lectura on proveedores for select to authenticated
  using (app.es('ejecutivo_comercial', 'cajero_contador', 'gerente_general'));
create policy proveedores_registro on proveedores for insert to authenticated
  with check (app.es('ejecutivo_comercial') and estado = 'inactivo');

create policy compras_lectura on compras for select to authenticated
  using (app.es('ejecutivo_comercial', 'cajero_contador', 'gerente_general'));
create policy compra_detalle_lectura on compra_detalle for select to authenticated
  using (app.es('ejecutivo_comercial', 'cajero_contador', 'gerente_general'));
create policy pagos_lectura on pagos for select to authenticated
  using (app.es('ejecutivo_comercial', 'cajero_contador', 'gerente_general'));

create policy pedidos_lectura on pedidos for select to authenticated
  using (app.es('ejecutivo_comercial', 'gerente_general'));
create policy pedidos_registro on pedidos for insert to authenticated
  with check (app.es('ejecutivo_comercial') and registrado_por = (select auth.uid())
      and estado in ('cotizacion', 'pedido'));
create policy pedido_detalle_lectura on pedido_detalle for select to authenticated
  using (app.es('ejecutivo_comercial', 'gerente_general'));
create policy pedido_detalle_registro on pedido_detalle for insert to authenticated
  with check (app.es('ejecutivo_comercial') and exists (
    select 1 from pedidos p where p.id = pedido_id and p.estado in ('cotizacion', 'pedido')));

create policy notas_venta_lectura on notas_venta for select to authenticated
  using (app.es('ejecutivo_comercial', 'cajero_contador', 'gerente_general'));
create policy cobros_lectura on cobros for select to authenticated
  using (app.es('ejecutivo_comercial', 'cajero_contador', 'gerente_general'));

create policy despachos_lectura on despachos for select to authenticated
  using (app.es('ejecutivo_comercial', 'gerente_general') or (app.es('operador_centro') and sede_id = app.sede()));
create policy despacho_rollos_lectura on despacho_rollos for select to authenticated
  using (exists (select 1 from despachos d where d.id = despacho_id));

-- Nadie edita ni borra directamente: los cambios de estado van por funciones
revoke update, delete on all tables in schema public from authenticated;
revoke insert on existencias, movimientos_inventario, lotes, guias_transferencia, guia_detalle, mermas,
  compras, compra_detalle, pagos, notas_venta, cobros, despachos, despacho_rollos, bitacora_eventos,
  usuarios, roles, sedes, granos, productos from authenticated;;
