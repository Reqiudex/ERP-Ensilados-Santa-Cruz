-- Migración 20261118113733 «alinear_con_tesis_y_funciones_base», copiada del historial de Supabase (supabase_migrations.schema_migrations).
-- Alinea la base con el diccionario de datos de la tesis (28 tablas) y la matriz de permisos.

-- 1. Quitar políticas previas fuera de la matriz
do $$ declare r record; begin
  for r in select tablename, policyname from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- 2. Quitar disparadores y funciones previas (referían columnas inexistentes y no validaban el rol)
drop trigger if exists trg_calcular_peso_ajustado on pesajes;
drop trigger if exists trg_audit_solicitudes on solicitudes_aprobacion;
drop trigger if exists trg_audit_pesajes on pesajes;
drop trigger if exists trg_audit_lotes on lotes;
drop trigger if exists trg_audit_compras on compras;
drop trigger if exists trg_audit_notas_venta on notas_venta;
drop trigger if exists trg_audit_cobros on cobros;
drop trigger if exists trg_proteger_bitacora on bitacora_eventos;
drop function if exists public.fn_calcular_peso_ajustado();
drop function if exists public.fn_cerrar_orden_ensilado(uuid, integer);
drop function if exists public.fn_registrar_cobro_caja(uuid, numeric, character varying, character varying);
drop function if exists public.fn_registrar_despacho_operativo(uuid, uuid, uuid, numeric[]);
drop function if exists public.fn_trg_bitacora_inmutable();
drop function if exists public.fn_impedir_mutacion_bitacora();
drop function if exists public.fn_current_user_profile();
drop function if exists public.fn_current_user_id();

-- 3. Columnas que no figuran en el diccionario de datos de la tesis
alter table clientes drop column if exists direccion_finca, drop column if exists credito_usado, drop column if exists activo;
alter table proveedores drop column if exists finca_localidad;

-- 4. Catálogos según la tesis
update roles set privilegiado = true where codigo in ('admin_sistema', 'gerente_general');
update roles set privilegiado = false where codigo not in ('admin_sistema', 'gerente_general');
update granos set humedad_estandar = 14.0, dias_fermentacion = 21;

-- 5. Numeración correlativa de documentos
create sequence if not exists seq_nota_venta;
create sequence if not exists seq_recibo_cobro;
create sequence if not exists seq_guia;
alter table notas_venta alter column numero set default nextval('seq_nota_venta');
alter table cobros alter column recibo set default nextval('seq_recibo_cobro');
alter table guias_transferencia alter column numero set default nextval('seq_guia');

-- 6. Sin acceso anónimo
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

-- 7. Funciones auxiliares: rol y sede del usuario autenticado
create schema if not exists app;
grant usage on schema app to authenticated;

create or replace function app.rol() returns text
language sql stable security definer set search_path = '' as $$
  select r.codigo::text from public.usuarios u join public.roles r on r.id = u.rol_id
  where u.id = (select auth.uid()) and u.estado = 'activo'
$$;

create or replace function app.sede() returns uuid
language sql stable security definer set search_path = '' as $$
  select u.sede_id from public.usuarios u where u.id = (select auth.uid()) and u.estado = 'activo'
$$;

create or replace function app.es(variadic roles_permitidos text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(app.rol() = any(roles_permitidos), false)
$$;

revoke all on function app.rol(), app.sede(), app.es(text[]) from public, anon;
grant execute on function app.rol(), app.sede(), app.es(text[]) to authenticated;;
