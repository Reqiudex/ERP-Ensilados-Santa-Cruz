-- Simula lo que la cola del teléfono envía al reconectar (con reenvíos) y otros flujos legítimos.
-- Úselo SOLO en una base local o de prueba con la migración 20261124120000 y el seed. Todo se revierte al final.
\set QUIET on
\pset tuples_only on
\pset format unaligned
\set ON_ERROR_STOP on
create or replace function pg_temp.como(p uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true),
         set_config('request.jwt.claim.sub', coalesce(p::text, ''), true);
$$;
grant execute on function pg_temp.como(uuid) to anon, authenticated;

begin;
select pg_temp.como('a1000000-0000-4000-8000-000000000021'); -- operador San Ramón
set local role authenticated;
\echo '--- 1. Orden, pesajes y consumo con ids del teléfono (cada uno enviado DOS veces, como tras una respuesta perdida)'
insert into public.ordenes_ensilado (id, sede_id, grano_id, fecha_apertura, estado, registrado_por)
values ('11110000-0000-4000-8000-000000000001', '22222222-2222-2222-2222-222222222222', 1, now() - interval '3 hours', 'abierta', auth.uid())
on conflict (id) do nothing;
insert into public.ordenes_ensilado (id, sede_id, grano_id, fecha_apertura, estado, registrado_por)
values ('11110000-0000-4000-8000-000000000001', '22222222-2222-2222-2222-222222222222', 1, now() - interval '3 hours', 'abierta', auth.uid())
on conflict (id) do nothing;
insert into public.pesajes (id, sede_id, origen, grano_id, placa, peso_bruto, tara, humedad, impurezas, orden_id, estado, fecha_dispositivo, registrado_por)
values ('11110000-0000-4000-8000-000000000002', '22222222-2222-2222-2222-222222222222', 'propio', 1, 'ABC-123', 21000, 12000, 20, 1,
        '11110000-0000-4000-8000-000000000001', 'confirmado', now() - interval '2 hours', auth.uid())
on conflict (id) do nothing;
insert into public.pesajes (id, sede_id, origen, grano_id, placa, peso_bruto, tara, humedad, impurezas, orden_id, estado, fecha_dispositivo, registrado_por)
values ('11110000-0000-4000-8000-000000000002', '22222222-2222-2222-2222-222222222222', 'propio', 1, 'ABC-123', 21000, 12000, 20, 1,
        '11110000-0000-4000-8000-000000000001', 'confirmado', now() - interval '2 hours', auth.uid())
on conflict (id) do nothing;
insert into public.consumos_insumo (id, orden_id, producto_id, cantidad)
values ('11110000-0000-4000-8000-000000000003', '11110000-0000-4000-8000-000000000001', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 2)
on conflict (id) do nothing;
reset role;
select 'pesajes de la orden = ' || count(*) from public.pesajes where orden_id = '11110000-0000-4000-8000-000000000001';

\echo '--- 2. Cierre sin conexión: el lote toma el id del teléfono; el reenvío no crea otro lote'
set local role authenticated;
select public.sincronizar_operacion('11110000-0000-4000-8000-000000000004', 'cerrar_orden',
  jsonb_build_object('orden_id', '11110000-0000-4000-8000-000000000001', 'rollos', 10,
                     'fecha_dispositivo', now() - interval '1 hour', 'lote_id', '11110000-0000-4000-8000-000000000004')) ->> 'codigo';
select 'reenvío: repetida = ' || (public.sincronizar_operacion('11110000-0000-4000-8000-000000000004', 'cerrar_orden',
  jsonb_build_object('orden_id', '11110000-0000-4000-8000-000000000001', 'rollos', 10)) ->> 'repetida');
reset role;
select 'lotes de la orden = ' || count(*) || ', id = ' || min(id::text) from public.lotes where orden_id = '11110000-0000-4000-8000-000000000001';

\echo '--- 3. Revisión y merma registradas sin conexión sobre ese lote'
set local role authenticated;
insert into public.revisiones_fermentacion (id, lote_id, estado_film, observacion, registrado_por)
values ('11110000-0000-4000-8000-000000000005', '11110000-0000-4000-8000-000000000004', 'integro', 'Film sin daños', auth.uid())
on conflict (id) do nothing;
select 'merma: ' || (public.sincronizar_operacion('11110000-0000-4000-8000-000000000006', 'solicitar_merma',
  jsonb_build_object('lote_id', '11110000-0000-4000-8000-000000000004', 'cantidad', 1, 'causa', 'manipuleo',
                     'descripcion', 'Rollo roto al apilar')) ->> 'estado');

\echo '--- 4. Pesaje en una orden de OTRA sede con fecha de hoy (debe rechazarse)'
reset role;
select pg_temp.como('a1000000-0000-4000-8000-000000000022');
set local role authenticated;
insert into public.ordenes_ensilado (id, sede_id, grano_id, fecha_apertura, estado, registrado_por)
values ('11110000-0000-4000-8000-000000000009', '33333333-3333-3333-3333-333333333333', 2, now(), 'abierta', auth.uid());
reset role;
select pg_temp.como('a1000000-0000-4000-8000-000000000021');
set local role authenticated;
savepoint s1;
\set ON_ERROR_STOP off
insert into public.pesajes (sede_id, origen, grano_id, placa, peso_bruto, tara, humedad, impurezas, orden_id, estado, fecha_dispositivo, registrado_por)
select '22222222-2222-2222-2222-222222222222', 'propio', o.grano_id, 'ZZZ-002', 20000, 12000, 14, 1, o.id, 'confirmado', now(), auth.uid()
  from (select '11110000-0000-4000-8000-000000000009'::uuid as id, 2 as grano_id) o;
rollback to savepoint s1;
\set ON_ERROR_STOP on
reset role;

\echo '--- 5. Ingreso verificado en el servidor (visitante anónimo)'
set local role anon;
select 'clave correcta por CI: ' || (public.preparar_ingreso('9876543', 'Ensilados2026!'))::text;
select 'clave errónea: ' || (public.preparar_ingreso('9876543', 'otra') ->> 'mensaje');
select 'CI inexistente: ' || (public.preparar_ingreso('1111111', 'x') ->> 'mensaje');
reset role;
select 'estado tras 1 fallo: ' || estado from public.usuarios where ci = '9876543';

\echo '--- 6. Ejecutivo consulta despachos pendientes (antes se le negaba)'
select pg_temp.como('a1000000-0000-4000-8000-000000000002');
set local role authenticated;
select 'filas: ' || jsonb_array_length(public.despachos_pendientes());

\echo '--- 7. Venta legítima: pedido PEPS a crédito y despacho de lo reservado'
select 'nota: ' || (public.emitir_nota_venta((public.registrar_pedido('88888888-8888-8888-8888-888888888882', 'rollo',
   '[{"producto_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","cantidad":2}]') ->> 'pedido_id')::uuid, 'credito', 0) ->> 'estado');
reset role;
select n.id as nota, d.lote_id as lote, e.sede_id as sede from public.notas_venta n
  join public.pedido_detalle d on d.pedido_id = n.pedido_id
  join public.movimientos_inventario m on m.documento_id = n.pedido_id and m.tipo = 'reserva' and m.lote_id = d.lote_id
  join public.existencias e on e.lote_id = d.lote_id and e.sede_id = m.sede_id
 order by n.numero desc limit 1 \gset
select id as op from public.usuarios where sede_id = :'sede' and rol_id = 2 \gset
select pg_temp.como(:'op');
set local role authenticated;
select 'despacho por la cola: ' || (public.sincronizar_operacion('11110000-0000-4000-8000-000000000007', 'registrar_despacho',
  jsonb_build_object('nota_id', :'nota', 'lote_id', :'lote', 'pesos', jsonb_build_array(850, 860),
                     'placa', 'XYZ-123', 'receptor', 'Chofer Z')) ->> 'estado');
reset role;

\echo '--- 8. Corrección de pesaje aprobada sobre una orden ya cerrada (la función del servidor no pasa por la validación)'
select id as pes from public.pesajes p where p.estado = 'confirmado' and p.origen = 'propio'
   and not exists (select 1 from public.compra_detalle c where c.pesaje_id = p.id)
   and exists (select 1 from public.ordenes_ensilado o where o.id = p.orden_id and o.estado = 'cerrada') limit 1 \gset
select sede_id as sede_p from public.pesajes where id = :'pes' \gset
select id as op_p from public.usuarios where sede_id = :'sede_p' and rol_id = 2 \gset
select pg_temp.como(:'op_p');
set local role authenticated;
select public.solicitar_correccion_pesaje(:'pes', 30000, 12000, 15, 1, 'Error de digitación') ->> 'solicitud_id' as sol \gset
reset role;
select pg_temp.como('a1000000-0000-4000-8000-000000000004');
set local role authenticated;
select 'aprobación: ' || (public.resolver_solicitud(:'sol', true, 'ok') ->> 'estado');
reset role;
rollback;
