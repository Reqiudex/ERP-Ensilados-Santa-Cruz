-- Restablece los datos de demostración entre ensayos: borra lo simulado y deja los catálogos como en el seed.
-- Después ejecute supabase/seed.sql. Lo corre el flujo «Reiniciar datos de demostración» (psql con SUPABASE_DB_URL)
-- o un administrador de la base. La bitácora NO se borra (es inalterable); las cuentas de demostración se conservan.
begin;
-- Permite borrar pesajes confirmados solo dentro de esta transacción de mantenimiento.
select set_config('app.via_aprobacion', 'si', true);

delete from public.despacho_rollos;
delete from public.despachos;
delete from public.cobros;
delete from public.notas_venta;
delete from public.pedido_detalle;
delete from public.pedidos;
delete from public.pagos;
delete from public.compra_detalle;
delete from public.compras;
delete from public.mermas;
delete from public.solicitudes_aprobacion;
delete from public.guia_detalle;
delete from public.guias_transferencia;
delete from public.movimientos_inventario;
delete from public.existencias;
delete from public.revisiones_fermentacion;
delete from public.consumos_insumo;
delete from public.lotes;
delete from public.pesajes;
delete from public.ordenes_ensilado;
-- Operaciones del teléfono ya aplicadas (idempotencia de la cola): sin los datos, un reenvío debe volver a aplicarse.
delete from app.operaciones_dispositivo;

-- Catálogos: solo los del seed
delete from public.productos where id not in (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'cccccccc-cccc-cccc-cccc-cccccccccccc',
  'dddddddd-dddd-dddd-dddd-dddddddddddd', 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'ffffffff-ffff-ffff-ffff-ffffffffffff');
update public.productos set activo = true;
update public.productos set precio_tonelada = 480, precio_rollo = 420 where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
update public.productos set precio_tonelada = 440, precio_rollo = 370 where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
update public.productos set precio_tonelada = 560, precio_rollo = 480 where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
delete from public.proveedores where id::text not like '77777777-7777-7777-7777-77777777777_';
update public.proveedores set estado = 'activo';
delete from public.clientes where id::text not like '88888888-8888-8888-8888-88888888888_';
update public.clientes set limite_credito = case id
  when '88888888-8888-8888-8888-888888888881' then 80000 when '88888888-8888-8888-8888-888888888882' then 120000
  when '88888888-8888-8888-8888-888888888883' then 25000 when '88888888-8888-8888-8888-888888888884' then 15000
  else 60000 end;
update public.granos set humedad_estandar = 14, dias_fermentacion = 21;

-- Cuentas: las de demostración activas con su rol original; el resto queda suspendido (no se borran: la bitácora las referencia)
update public.usuarios set estado = 'activo' where id::text like 'a1000000-0000-4000-8000-0000000000__';
update public.usuarios set estado = 'suspendido' where id::text not like 'a1000000-0000-4000-8000-0000000000__';
update auth.users set banned_until = null,
       encrypted_password = extensions.crypt('Ensilados2026!', extensions.gen_salt('bf')),
       raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) - 'debe_cambiar_clave'
 where id::text like 'a1000000-0000-4000-8000-0000000000__' and id::text not like '%99';
update auth.users set banned_until = 'infinity' where id::text not like 'a1000000-0000-4000-8000-0000000000__'
   and id in (select id from public.usuarios);
delete from auth.sessions where user_id::text not like '%99';
delete from app.historial_claves where usuario_id::text like 'a1000000-0000-4000-8000-0000000000__' and usuario_id::text not like '%99';

update app.parametros set valor = v.valor from (values
  ('tolerancia_despacho_pct', '5'::jsonb), ('peso_promedio_rollo_kg', '850'), ('inactividad_minutos', '15'), ('clave_longitud_min', '8'),
  ('clave_mayusculas', 'true'), ('clave_minusculas', 'true'), ('clave_numeros', 'true'), ('clave_simbolos', 'true'),
  ('clave_vigencia_dias', '90'), ('intentos_max', '3'), ('bloqueo_minutos', '15'), ('pin_min', '4'), ('pin_max', '6'),
  ('pin_intentos', '3'), ('horas_sin_sincronizar', '12')) v(clave, valor)
 where parametros.clave = v.clave;
commit;
