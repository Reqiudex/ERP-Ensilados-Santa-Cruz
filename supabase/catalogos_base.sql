-- Catálogos mínimos para levantar una base NUEVA desde cero (la base en línea ya los tiene).
-- Orden: migraciones → este archivo → seed.sql. Nombres y precios son de ejemplo: ajústelos a los reales.
-- Es idempotente (ON CONFLICT DO NOTHING) y no toca catálogos que ya existan.

insert into public.roles (id, codigo, nombre, privilegiado) values
  (1, 'admin_sistema', 'Administrador del sistema', true), (2, 'operador_centro', 'Operador de centro', false),
  (3, 'ejecutivo_comercial', 'Ejecutivo comercial', false), (4, 'cajero_contador', 'Cajero o contador', false),
  (5, 'gerente_general', 'Gerente general', true) on conflict do nothing;
insert into public.sedes (id, nombre, tipo, municipio, provincia, activa) values
  ('11111111-1111-1111-1111-111111111111', 'Oficina Central Santa Cruz', 'oficina', 'Santa Cruz', 'Andrés Ibáñez', true),
  ('22222222-2222-2222-2222-222222222222', 'Centro de Acopio San Ramón', 'centro_acopio', 'San Ramón', 'Ñuflo de Chávez', true),
  ('33333333-3333-3333-3333-333333333333', 'Centro de Acopio San Julián', 'centro_acopio', 'San Julián', 'Ñuflo de Chávez', true),
  ('44444444-4444-4444-4444-444444444444', 'Centro de Acopio San Rafael de Velasco', 'centro_acopio', 'San Rafael', 'Velasco', true)
on conflict do nothing;
insert into public.granos (id, nombre, humedad_estandar, dias_fermentacion, rollos_ton_min, rollos_ton_max) values
  (1, 'Maíz', 14, 21, 1.0, 1.4), (2, 'Sorgo', 14, 21, 1.0, 1.4), (3, 'Soya', 14, 21, 0.95, 1.35)
on conflict do nothing;
insert into public.productos (id, sku, nombre, tipo, grano_id, unidad, precio_tonelada, precio_rollo, activo) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'ROL-MAI-001', 'Rollo ensilado de maíz', 'rollo', 1, 'rollo', 480, 420, true),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'ROL-SOR-001', 'Rollo ensilado de sorgo', 'rollo', 2, 'rollo', 440, 370, true),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'ROL-SOY-001', 'Rollo ensilado de soya', 'rollo', 3, 'rollo', 560, 480, true),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'INS-FLM-001', 'Film estirable', 'insumo', null, 'unidad', 0, 0, true),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'INS-MLL-001', 'Malla tubular', 'insumo', null, 'unidad', 0, 0, true),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'INS-INC-001', 'Inoculante', 'insumo', null, 'unidad', 0, 0, true)
on conflict do nothing;
insert into public.proveedores (id, nit_ci, razon_social, tipo, telefono, estado) values
  ('77777777-7777-7777-7777-777777777771', '1000000011', 'Productor Uno', 'productor', '70000001', 'activo'),
  ('77777777-7777-7777-7777-777777777772', '1000000012', 'Productor Dos', 'productor', '70000002', 'activo'),
  ('77777777-7777-7777-7777-777777777773', '1000000013', 'Insumos del Oriente', 'insumos', '70000003', 'activo')
on conflict do nothing;
insert into public.clientes (id, nit_ci, razon_social, tipo, telefono, limite_credito) values
  ('88888888-8888-8888-8888-888888888881', '2000000011', 'Cliente Mayorista Uno', 'mayorista', '71000001', 80000),
  ('88888888-8888-8888-8888-888888888882', '2000000012', 'Cliente Mayorista Dos', 'mayorista', '71000002', 120000),
  ('88888888-8888-8888-8888-888888888883', '2000000013', 'Cliente Minorista Uno', 'minorista', '71000003', 25000)
on conflict do nothing;
-- Stock inicial de insumos en los centros (solo si el centro aún no tiene ese insumo)
insert into public.existencias (sede_id, producto_id, lote_id, disponible, reservado, en_transito)
select s, p, null, 5000, 0, 0 from unnest(array['22222222-2222-2222-2222-222222222222','33333333-3333-3333-3333-333333333333',
  '44444444-4444-4444-4444-444444444444']::uuid[]) s,
  unnest(array['dddddddd-dddd-dddd-dddd-dddddddddddd','eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee','ffffffff-ffff-ffff-ffff-ffffffffffff']::uuid[]) p
on conflict do nothing;
