-- =============================================================================================
-- Datos simulados de demostración (agosto a noviembre de 2026).
-- Reutiliza los catálogos ya cargados (roles, sedes, granos, productos) y genera el resto pasando
-- por las mismas funciones del servidor que usa la aplicación, con la cuenta del rol que corresponde.
-- Es idempotente: los usuarios y catálogos usan ON CONFLICT y los datos de negocio solo se cargan si no hay lotes.
-- Contraseña de todas las cuentas de demostración: Ensilados2026!
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- Cuentas de demostración (una por rol y un operador por centro de acopio)
-- ---------------------------------------------------------------------------------------------
do $$
declare
  u record;
begin
  for u in select * from (values
    ('a1000000-0000-4000-8000-000000000001'::uuid, 'Carla Méndez Rojas', '6543210', 'admin@ensilados.demo', 1, '11111111-1111-1111-1111-111111111111'::uuid),
    ('a1000000-0000-4000-8000-000000000002'::uuid, 'David Zabala Mercado', '7654321', 'ventas@ensilados.demo', 3, '11111111-1111-1111-1111-111111111111'::uuid),
    ('a1000000-0000-4000-8000-000000000003'::uuid, 'Melvi Pedraza', '8765432', 'caja@ensilados.demo', 4, '11111111-1111-1111-1111-111111111111'::uuid),
    ('a1000000-0000-4000-8000-000000000004'::uuid, 'Gabriel Zabala Mercado', '5432109', 'gerencia@ensilados.demo', 5, '11111111-1111-1111-1111-111111111111'::uuid),
    ('a1000000-0000-4000-8000-000000000021'::uuid, 'Juan Carlos Rivero', '9876543', 'sanramon@ensilados.demo', 2, '22222222-2222-2222-2222-222222222222'::uuid),
    ('a1000000-0000-4000-8000-000000000022'::uuid, 'Rosa Elena Quispe', '9988776', 'sanjulian@ensilados.demo', 2, '33333333-3333-3333-3333-333333333333'::uuid),
    ('a1000000-0000-4000-8000-000000000023'::uuid, 'Hugo Chávez Taborga', '9123456', 'sanrafael@ensilados.demo', 2, '44444444-4444-4444-4444-444444444444'::uuid)
  ) as t(id, nombre, ci, correo, rol_id, sede_id) loop
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
      email_change_token_new, email_change, email_change_token_current, phone_change, phone_change_token,
      reauthentication_token)
    values ('00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.correo,
      extensions.crypt('Ensilados2026!', extensions.gen_salt('bf')), now(),
      '{"provider": "email", "providers": ["email"]}'::jsonb, jsonb_build_object('nombre', u.nombre),
      now(), now(), '', '', '', '', '', '', '', '')
    on conflict (id) do nothing;
    insert into auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
    values (u.id::text, u.id, jsonb_build_object('sub', u.id::text, 'email', u.correo, 'email_verified', true),
            'email', now(), now())
    on conflict (provider_id, provider) do nothing;
    insert into public.usuarios (id, nombre_completo, ci, correo, rol_id, sede_id, estado)
    values (u.id, u.nombre, u.ci, u.correo, u.rol_id, u.sede_id, 'activo')
    on conflict (id) do update set nombre_completo = excluded.nombre_completo;
    update auth.users set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('nombre', u.nombre)
     where id = u.id;
  end loop;
end $$;

-- Productores (5 en total) y clientes (5 en total: mayoristas por tonelada y minoristas por rollo)
insert into public.proveedores (id, nit_ci, razon_social, tipo, telefono, estado) values
  ('77777777-7777-7777-7777-777777777774', '2938471015', 'Productora Los Troncos', 'productor', '77651234', 'activo'),
  ('77777777-7777-7777-7777-777777777775', '4019283017', 'Granos del Norte Integrado', 'productor', '76543120', 'activo'),
  ('77777777-7777-7777-7777-777777777776', '5102938016', 'Agropecuaria Okinawa Uno', 'productor', '78123456', 'activo')
on conflict (id) do nothing;
insert into public.clientes (id, nit_ci, razon_social, tipo, telefono, limite_credito) values
  ('88888888-8888-8888-8888-888888888884', '6029384', 'Lechería El Bibosi', 'minorista', '75012345', 15000),
  ('88888888-8888-8888-8888-888888888885', '3049582014', 'Feedlot Guarayos SRL', 'mayorista', '77889900', 60000)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------------------------
-- Ayudantes de la carga (solo existen durante esta sesión)
-- ---------------------------------------------------------------------------------------------
create or replace function pg_temp.como(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coalesce(p::text, ''), true);
end $$;

create or replace function pg_temp.ok(r jsonb, paso text) returns jsonb language plpgsql as $$
begin
  if r ? 'code' then raise exception 'Seed: % rechazado: %', paso, r ->> 'message'; end if;
  return r;
end $$;

create or replace function pg_temp.fechar_solicitud(p_id uuid, p_reg timestamptz, p_dec timestamptz default null)
returns void language sql as $$
  update public.solicitudes_aprobacion set fecha_registro = p_reg,
         fecha_decision = case when fecha_decision is not null then coalesce(p_dec, fecha_decision) end
   where id = p_id;
$$;

create or replace function pg_temp.aprobar(p_id uuid, p_fecha timestamptz, p_motivo text default 'Revisado y aprobado')
returns void language plpgsql as $$
begin
  perform pg_temp.como('a1000000-0000-4000-8000-000000000004');
  perform pg_temp.ok(public.resolver_solicitud(p_id, true, p_motivo), 'aprobación');
  perform pg_temp.fechar_solicitud(p_id, p_fecha - interval '20 hours', p_fecha);
end $$;

-- Orden de ensilado completa: 3 pesajes, consumo de insumos y cierre (crea el lote)
create or replace function pg_temp.orden(p_sede uuid, p_op uuid, p_grano smallint, p_fecha date, p_kg numeric,
  p_humedad numeric, p_rollos int default null, p_prov uuid default null) returns jsonb
language plpgsql as $$
declare v_o uuid := gen_random_uuid(); i int; v_aj numeric; v_r int; v_ts timestamptz; v_res jsonb;
begin
  perform pg_temp.como(p_op);
  insert into public.ordenes_ensilado (id, sede_id, grano_id, fecha_apertura, estado, registrado_por, fecha_registro)
  values (v_o, p_sede, p_grano, (p_fecha - 2) + time '07:30', 'abierta', p_op, (p_fecha - 2) + time '07:30');
  for i in 1 .. 3 loop
    v_ts := (p_fecha - 2 + (i - 1) / 2) + make_time(8 + i * 2, 15 * i, 0);
    insert into public.pesajes (sede_id, origen, proveedor_id, grano_id, placa, peso_bruto, tara, humedad, impurezas,
      orden_id, estado, fecha_dispositivo, registrado_por, fecha_registro)
    values (p_sede, case when p_prov is null then 'propio' else 'productor' end, p_prov, p_grano,
      format('%s-%s', 2100 + (extract(doy from p_fecha)::int * 7 + i * 13) % 7000, (array['KLM','TRS','PQB','HJN','WXZ'])[1 + (i + extract(day from p_fecha)::int) % 5]),
      12000 + round(p_kg / 3), 12000, p_humedad, 1.0, v_o, 'confirmado', v_ts, p_op, v_ts + interval '3 minutes');
  end loop;
  select sum(peso_ajustado) into v_aj from public.pesajes where orden_id = v_o;
  v_r := coalesce(p_rollos, round(v_aj / 1000.0 * 1.18)::int);
  insert into public.consumos_insumo (orden_id, producto_id, cantidad) values
    (v_o, 'dddddddd-dddd-dddd-dddd-dddddddddddd', ceil(v_r / 20.0)),
    (v_o, 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', ceil(v_r / 30.0)),
    (v_o, 'ffffffff-ffff-ffff-ffff-ffffffffffff', ceil(v_r / 25.0));
  v_res := pg_temp.ok(public.cerrar_orden(v_o, v_r, p_fecha + time '17:00'), 'cierre de orden');
  update public.ordenes_ensilado set fecha_registro = (p_fecha - 2) + time '07:30' where id = v_o;
  return v_res || jsonb_build_object('orden_id', v_o);
end $$;

-- Venta: pedido (reserva PEPS) y nota de venta del ejecutivo
create or replace function pg_temp.venta(p_cliente uuid, p_unidad text, p_producto uuid, p_cantidad numeric,
  p_condicion text, p_descuento numeric, p_fecha timestamptz, p_factura text default null) returns jsonb
language plpgsql as $$
declare r jsonb; n jsonb;
begin
  perform pg_temp.como('a1000000-0000-4000-8000-000000000002');
  r := pg_temp.ok(public.registrar_pedido(p_cliente, p_unidad,
         jsonb_build_array(jsonb_build_object('producto_id', p_producto, 'cantidad', p_cantidad)), 'pedido'), 'pedido');
  n := pg_temp.ok(public.emitir_nota_venta((r ->> 'pedido_id')::uuid, p_condicion, p_descuento, p_factura), 'nota de venta');
  update public.pedidos set fecha_registro = p_fecha - interval '2 hours' where id = (r ->> 'pedido_id')::uuid;
  update public.notas_venta set fecha_registro = p_fecha where id = (n ->> 'nota_id')::uuid;
  if n ->> 'solicitud_id' is not null then
    perform pg_temp.fechar_solicitud((n ->> 'solicitud_id')::uuid, p_fecha);
  end if;
  return n || jsonb_build_object('pedido_id', r ->> 'pedido_id');
end $$;

create or replace function pg_temp.cobro(p_nota uuid, p_monto numeric, p_metodo text, p_fecha timestamptz)
returns void language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.como('a1000000-0000-4000-8000-000000000003');
  r := pg_temp.ok(public.registrar_cobro(p_nota, p_monto, p_metodo), 'cobro');
  update public.cobros set fecha_registro = p_fecha where id = (r ->> 'cobro_id')::uuid;
end $$;

-- Despacho de todos los rollos de la nota con peso individual por rollo
create or replace function pg_temp.despacho(p_nota uuid, p_op uuid, p_peso numeric, p_fecha timestamptz, p_placa text,
  p_receptor text) returns void language plpgsql as $$
declare d record; v_pesos numeric[]; r jsonb;
begin
  perform pg_temp.como(p_op);
  for d in select pd.lote_id, pd.rollos_equivalentes from public.pedido_detalle pd
             join public.notas_venta n on n.pedido_id = pd.pedido_id where n.id = p_nota loop
    select array_agg(p_peso + ((g % 5) - 2) * 4 order by g) into v_pesos from generate_series(1, d.rollos_equivalentes) g;
    r := pg_temp.ok(public.registrar_despacho(p_nota, d.lote_id, v_pesos, p_placa, p_receptor, null), 'despacho');
    update public.despachos set fecha_registro = p_fecha where id = (r ->> 'despacho_id')::uuid;
  end loop;
end $$;

-- ---------------------------------------------------------------------------------------------
-- Escenario de negocio (solo si todavía no hay lotes)
-- ---------------------------------------------------------------------------------------------
do $$
declare
  c_sr uuid := '22222222-2222-2222-2222-222222222222';
  c_sj uuid := '33333333-3333-3333-3333-333333333333';
  c_rv uuid := '44444444-4444-4444-4444-444444444444';
  op_sr uuid := 'a1000000-0000-4000-8000-000000000021';
  op_sj uuid := 'a1000000-0000-4000-8000-000000000022';
  op_rv uuid := 'a1000000-0000-4000-8000-000000000023';
  ejec uuid := 'a1000000-0000-4000-8000-000000000002';
  caja uuid := 'a1000000-0000-4000-8000-000000000003';
  admin uuid := 'a1000000-0000-4000-8000-000000000001';
  p_mai uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  p_sor uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  p_soy uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  r jsonb; l jsonb := '{}'::jsonb; v_id uuid; v_total numeric; v_items jsonb; s1 jsonb; s2 jsonb; s3 jsonb; s4 jsonb;
  s5 jsonb; s6 jsonb; g1 jsonb; g2 jsonb; v_sol uuid; v_pes uuid;
begin
  if exists (select 1 from public.lotes) then
    raise notice 'Seed: ya hay datos de negocio, no se vuelve a cargar.';
    return;
  end if;

  -- C1. Compra de insumos para los tres centros (aprobada y pagada)
  perform pg_temp.como(ejec);
  select jsonb_agg(x) into v_items from (
    select jsonb_build_object('producto_id', p, 'cantidad', q, 'precio_unitario', pr, 'sede_id', s) as x
      from (values ('dddddddd-dddd-dddd-dddd-dddddddddddd'::uuid, 60, 680), ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'::uuid, 40, 450),
                   ('ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid, 50, 185)) i(p, q, pr)
      cross join (values (c_sr), (c_sj), (c_rv)) s(s)) t;
  r := pg_temp.ok(public.registrar_compra('77777777-7777-7777-7777-777777777773', '2026-08-01', v_items), 'compra insumos');
  update public.compras set fecha_registro = '2026-08-01 09:00-04' where id = (r ->> 'compra_id')::uuid;
  perform pg_temp.aprobar((r ->> 'solicitud_id')::uuid, '2026-08-01 15:00-04');
  perform pg_temp.como(caja);
  perform pg_temp.ok(public.registrar_pago((r ->> 'compra_id')::uuid, (r ->> 'total')::numeric, 'transferencia'), 'pago insumos');
  update public.pagos set fecha_registro = '2026-08-05 10:00-04' where compra_id = (r ->> 'compra_id')::uuid;

  -- Producción por centro (lotes L1 a L13)
  l := l || jsonb_build_object('L1', pg_temp.orden(c_sr, op_sr, 2::smallint, '2026-08-05', 102000, 14, 120));  -- CP-22: 120 rollos, 102 t
  l := l || jsonb_build_object('L2', pg_temp.orden(c_sr, op_sr, 2::smallint, '2026-08-20', 85000, 16, null, '77777777-7777-7777-7777-777777777771'));
  l := l || jsonb_build_object('L3', pg_temp.orden(c_sr, op_sr, 1::smallint, '2026-09-01', 68000, 15));        -- CP-21: sellado el 1 de septiembre
  l := l || jsonb_build_object('L4', pg_temp.orden(c_sr, op_sr, 1::smallint, '2026-09-15', 69500, 14));        -- CP-21: sellado el 15 de septiembre
  l := l || jsonb_build_object('L5', pg_temp.orden(c_sr, op_sr, 3::smallint, '2026-10-10', 51000, 15));
  l := l || jsonb_build_object('L6', pg_temp.orden(c_sr, op_sr, 1::smallint, current_date - 21, 60000, 14));   -- CP-12: sellado hace 21 días
  l := l || jsonb_build_object('L7', pg_temp.orden(c_sj, op_sj, 2::smallint, '2026-08-12', 90000, 15, null, '77777777-7777-7777-7777-777777777772'));
  l := l || jsonb_build_object('L8', pg_temp.orden(c_sj, op_sj, 2::smallint, '2026-09-08', 76500, 14, 70));     -- alerta de rendimiento bajo
  l := l || jsonb_build_object('L9', pg_temp.orden(c_sj, op_sj, 3::smallint, '2026-10-02', 60000, 16));
  l := l || jsonb_build_object('L10', pg_temp.orden(c_sj, op_sj, 1::smallint, current_date - 15, 50000, 17));  -- CP-12: sellado hace 15 días
  l := l || jsonb_build_object('L11', pg_temp.orden(c_rv, op_rv, 3::smallint, '2026-08-25', 85000, 14, 100));
  l := l || jsonb_build_object('L12', pg_temp.orden(c_rv, op_rv, 2::smallint, '2026-09-20', 68000, 15));
  l := l || jsonb_build_object('L13', pg_temp.orden(c_rv, op_rv, 1::smallint, '2026-10-15', 51000, 15, null, '77777777-7777-7777-7777-777777777774'));
  perform app.promover_lotes();

  -- Revisiones de fermentación (film íntegro)
  insert into public.revisiones_fermentacion (lote_id, estado_film, observacion, registrado_por, fecha_registro)
  select (l -> k ->> 'lote_id')::uuid, 'integro', 'Film sin daños, sin olor anormal', op, f
    from (values ('L6', op_sr, current_date - 10 + time '10:00'), ('L10', op_sj, current_date - 5 + time '11:00'),
                 ('L5', op_sr, '2026-10-24 10:00'::timestamp), ('L13', op_rv, '2026-10-29 09:30'::timestamp)) v(k, op, f);

  -- C2 y C3. Compras de grano a productores con sus pesajes confirmados
  perform pg_temp.como(ejec);
  select jsonb_agg(jsonb_build_object('pesaje_id', id, 'precio_unitario', 950)) into v_items
    from public.pesajes where orden_id = (l -> 'L2' ->> 'orden_id')::uuid;
  r := pg_temp.ok(public.registrar_compra('77777777-7777-7777-7777-777777777771', '2026-08-21', v_items), 'compra L2');
  update public.compras set fecha_registro = '2026-08-21 09:30-04' where id = (r ->> 'compra_id')::uuid;
  perform pg_temp.aprobar((r ->> 'solicitud_id')::uuid, '2026-08-22 11:00-04');
  perform pg_temp.como(caja);
  perform pg_temp.ok(public.registrar_pago((r ->> 'compra_id')::uuid, (r ->> 'total')::numeric, 'transferencia'), 'pago L2');
  update public.pagos set fecha_registro = '2026-08-30 10:00-04' where compra_id = (r ->> 'compra_id')::uuid;

  perform pg_temp.como(ejec);
  select jsonb_agg(jsonb_build_object('pesaje_id', id, 'precio_unitario', 950)) into v_items
    from public.pesajes where orden_id = (l -> 'L7' ->> 'orden_id')::uuid;
  r := pg_temp.ok(public.registrar_compra('77777777-7777-7777-7777-777777777772', '2026-08-13', v_items), 'compra L7');
  update public.compras set fecha_registro = '2026-08-13 09:30-04' where id = (r ->> 'compra_id')::uuid;
  perform pg_temp.aprobar((r ->> 'solicitud_id')::uuid, '2026-08-14 16:00-04');
  perform pg_temp.como(caja);
  -- CP-18: compra aprobada con saldo de Bs 5.000
  perform pg_temp.ok(public.registrar_pago((r ->> 'compra_id')::uuid, (r ->> 'total')::numeric - 5000, 'qr'), 'pago L7');
  update public.pagos set fecha_registro = '2026-08-25 10:00-04' where compra_id = (r ->> 'compra_id')::uuid;

  -- Ventas, cobros y despachos (agosto a octubre)
  s1 := pg_temp.venta('88888888-8888-8888-8888-888888888881', 'tonelada', p_sor, 50, 'contado', 0, '2026-08-28 10:00-04', '000812');
  perform pg_temp.cobro((s1 ->> 'nota_id')::uuid, (s1 ->> 'total')::numeric, 'transferencia', '2026-08-28 15:00-04');
  perform pg_temp.despacho((s1 ->> 'nota_id')::uuid, op_sr, 884, '2026-08-29 09:00-04', '3456-KLM', 'Mario Arteaga (chofer)');

  s2 := pg_temp.venta('88888888-8888-8888-8888-888888888883', 'rollo', p_sor, 30, 'credito', 0, '2026-09-10 11:00-04', '000845');
  perform pg_temp.cobro((s2 ->> 'nota_id')::uuid, 6000, 'efectivo', '2026-09-12 09:30-04');
  perform pg_temp.despacho((s2 ->> 'nota_id')::uuid, op_sr, 852, '2026-09-11 08:30-04', '2211-TRS', 'Fernando Gamarra');

  s3 := pg_temp.venta('88888888-8888-8888-8888-888888888882', 'tonelada', p_soy, 40, 'contado', 0, '2026-09-25 10:30-04', '000871');
  perform pg_temp.cobro((s3 ->> 'nota_id')::uuid, (s3 ->> 'total')::numeric, 'qr', '2026-09-25 16:00-04');
  perform pg_temp.despacho((s3 ->> 'nota_id')::uuid, op_rv, 880, '2026-09-26 09:00-04', '4789-PQB', 'Luis Roca (chofer)');

  s4 := pg_temp.venta('88888888-8888-8888-8888-888888888881', 'tonelada', p_sor, 26, 'credito', 0, '2026-10-08 09:00-04', '000903');
  perform pg_temp.cobro((s4 ->> 'nota_id')::uuid, 8000, 'transferencia', '2026-10-15 10:00-04');
  perform pg_temp.despacho((s4 ->> 'nota_id')::uuid, op_sr, 872, '2026-10-09 08:00-04', '3456-KLM', 'Mario Arteaga (chofer)');

  -- CP-13: lote con saldo de 40 rollos reservado para una nota emitida, aún sin despachar
  s5 := pg_temp.venta('88888888-8888-8888-8888-888888888884', 'rollo', p_sor, 40, 'credito', 0, '2026-10-20 10:00-04', '000931');

  -- Venta con descuento: queda pendiente en la bandeja del gerente
  s6 := pg_temp.venta('88888888-8888-8888-8888-888888888885', 'tonelada', p_soy, 20, 'contado', 500, current_date - 2 + time '11:00');

  -- Guías de transferencia: una recibida con diferencia (merma de traslado) y otra en tránsito
  perform pg_temp.como(op_sr);
  g1 := pg_temp.ok(public.emitir_guia(c_sj, jsonb_build_array(jsonb_build_object('lote_id', l -> 'L2' ->> 'lote_id', 'cantidad', 20))), 'guía 1');
  update public.guias_transferencia set fecha_emision = '2026-09-30 08:00-04' where id = (g1 ->> 'guia_id')::uuid;
  perform pg_temp.como(op_sj);
  r := pg_temp.ok(public.recibir_guia((g1 ->> 'guia_id')::uuid,
         jsonb_build_array(jsonb_build_object('lote_id', l -> 'L2' ->> 'lote_id', 'cantidad_recibida', 19))), 'recepción guía 1');
  update public.guias_transferencia set fecha_recepcion = '2026-09-30 17:30-04' where id = (g1 ->> 'guia_id')::uuid;
  perform pg_temp.fechar_solicitud((r -> 'solicitudes_merma' ->> 0)::uuid, '2026-09-30 17:30-04');
  perform pg_temp.aprobar((r -> 'solicitudes_merma' ->> 0)::uuid, '2026-10-01 10:00-04', 'Rollo dañado en el camino; se acepta la baja');

  perform pg_temp.como(op_sj);
  g2 := pg_temp.ok(public.emitir_guia(c_rv, jsonb_build_array(jsonb_build_object('lote_id', l -> 'L9' ->> 'lote_id', 'cantidad', 10))), 'guía 2');
  update public.guias_transferencia set fecha_emision = current_date - 1 + time '08:00' where id = (g2 ->> 'guia_id')::uuid;

  -- Mermas aprobadas y una pendiente
  perform pg_temp.como(op_sr);
  r := pg_temp.ok(public.solicitar_merma((l -> 'L5' ->> 'lote_id')::uuid, 3, 'film_roto', 'Film roto por granizo en la playa de acopio'), 'merma L5');
  perform pg_temp.aprobar((r ->> 'solicitud_id')::uuid, '2026-10-22 09:00-04');
  perform pg_temp.como(op_sj);
  r := pg_temp.ok(public.solicitar_merma((l -> 'L8' ->> 'lote_id')::uuid, 2, 'fermentacion', 'Rollos con mala fermentación por ingreso de aire'), 'merma L8');
  perform pg_temp.aprobar((r ->> 'solicitud_id')::uuid, '2026-10-05 11:00-04');

  -- Solicitudes pendientes para la bandeja del gerente (de la más antigua a la más reciente)
  perform pg_temp.como(op_rv);
  r := pg_temp.ok(public.solicitar_merma((l -> 'L12' ->> 'lote_id')::uuid, 1, 'manipuleo', 'Rollo perforado por la pala cargadora'), 'merma L12');
  perform pg_temp.fechar_solicitud((r ->> 'solicitud_id')::uuid, current_date - 6 + time '16:20');

  perform pg_temp.como(ejec);
  r := pg_temp.ok(public.solicitar_cambio_precio(p_soy, 575, 490, 'Ajuste por mayor costo de la soya en la campaña de invierno'), 'precio');
  perform pg_temp.fechar_solicitud((r ->> 'solicitud_id')::uuid, current_date - 5 + time '09:10');

  select jsonb_agg(jsonb_build_object('pesaje_id', id, 'precio_unitario', 940)) into v_items
    from public.pesajes where orden_id = (l -> 'L13' ->> 'orden_id')::uuid;
  r := pg_temp.ok(public.registrar_compra('77777777-7777-7777-7777-777777777774', '2026-10-16', v_items), 'compra L13');
  update public.compras set fecha_registro = current_date - 4 + time '10:00' where id = (r ->> 'compra_id')::uuid;
  perform pg_temp.fechar_solicitud((r ->> 'solicitud_id')::uuid, current_date - 4 + time '10:00');

  insert into public.proveedores (nit_ci, razon_social, tipo, telefono, estado)
  values ('1020304019', 'Plásticos Agrícolas del Oriente', 'insumos', '33445566', 'inactivo') returning id into v_id;
  update public.solicitudes_aprobacion set fecha_registro = current_date - 3 + time '15:45' where entidad_id = v_id;

  r := pg_temp.ok(public.solicitar_limite_credito('88888888-8888-8888-8888-888888888884', 25000,
         'Cliente puntual; pide ampliar crédito para la época seca'), 'límite de crédito');
  perform pg_temp.fechar_solicitud((r ->> 'solicitud_id')::uuid, current_date - 3 + time '16:30');

  perform pg_temp.como(op_sj);
  select id into v_pes from public.pesajes where orden_id = (l -> 'L10' ->> 'orden_id')::uuid order by fecha_dispositivo limit 1;
  r := pg_temp.ok(public.solicitar_correccion_pesaje(v_pes, (select peso_bruto - 120 from public.pesajes where id = v_pes),
         12000, 17, 1, 'La báscula marcó 120 kg de más; se volvió a pesar el camión'), 'corrección');
  perform pg_temp.fechar_solicitud((r ->> 'solicitud_id')::uuid, current_date - 2 + time '08:40');

  perform pg_temp.como(admin);
  select id into v_id from public.usuarios where ci = '7012345';
  if v_id is null then
    r := pg_temp.ok(public.crear_usuario('Daniela Rocha Saucedo', '7012345', 'gerencia.suplente@ensilados.demo',
           'gerente_general', '11111111-1111-1111-1111-111111111111', 'Ensilados2026!'), 'usuario privilegiado');
    v_id := (r ->> 'id')::uuid;
  else
    perform app.solicitud('rol_privilegiado', 'usuarios', v_id,
      jsonb_build_object('rol_id', 5, 'rol', 'gerente_general', 'usuario', 'Daniela Rocha Saucedo', 'activar', true),
      'Alta de cuenta con rol privilegiado: Gerente General');
  end if;
  update public.solicitudes_aprobacion set fecha_registro = current_date - 1 + time '09:00' where entidad_id = v_id;
  r := pg_temp.ok(public.solicitar_restauracion('respaldo-2026-11-15', 'Ensayo de restauración trimestral en un entorno de prueba'), 'restauración');
  perform pg_temp.fechar_solicitud((r ->> 'solicitud_id')::uuid, current_date - 1 + time '11:00');

  -- Órdenes abiertas del día para la demostración de la báscula
  insert into public.ordenes_ensilado (sede_id, grano_id, fecha_apertura, estado, registrado_por)
  values (c_sr, 1, now() - interval '3 hours', 'abierta', op_sr), (c_sj, 2, now() - interval '2 hours', 'abierta', op_sj);
  insert into public.pesajes (sede_id, origen, grano_id, placa, peso_bruto, tara, humedad, impurezas, orden_id, estado, fecha_dispositivo, registrado_por)
  select o.sede_id, 'propio', o.grano_id, v.placa, v.bruto, 12000, v.h, 1, o.id, 'confirmado', now() - v.hace, o.registrado_por
    from public.ordenes_ensilado o
    cross join (values ('3456-KLM', 46000, 15.0, interval '150 minutes'), ('2871-TRS', 45200, 14.5, interval '90 minutes')) v(placa, bruto, h, hace)
   where o.estado = 'abierta' and o.sede_id = c_sr;

  -- Fechas de los movimientos según su documento de origen (para los reportes por período)
  update public.movimientos_inventario m set fecha_registro = l2.fecha_sellado + time '17:00'
    from public.lotes l2 where m.documento_tipo = 'lotes' and m.documento_id = l2.id;
  update public.movimientos_inventario m set fecha_registro = o.fecha_cierre
    from public.ordenes_ensilado o where m.documento_tipo = 'ordenes_ensilado' and m.documento_id = o.id;
  update public.movimientos_inventario m set fecha_registro = p.fecha_registro
    from public.pedidos p where m.documento_tipo = 'pedidos' and m.documento_id = p.id;
  update public.movimientos_inventario m set fecha_registro = d.fecha_registro
    from public.despachos d where m.documento_tipo = 'despachos' and m.documento_id = d.id;
  update public.movimientos_inventario m set fecha_registro = case when m.tipo = 'envio' then g.fecha_emision else g.fecha_recepcion end
    from public.guias_transferencia g where m.documento_tipo = 'guias_transferencia' and m.documento_id = g.id;
  update public.movimientos_inventario m set fecha_registro = s.fecha_decision
    from public.solicitudes_aprobacion s where m.documento_tipo = 'solicitud' and m.documento_id = s.id;
  update public.movimientos_inventario m set fecha_registro = c.fecha::timestamp + time '15:00'
    from public.compras c where m.documento_tipo = 'compras' and m.documento_id = c.id;

  perform pg_temp.como(null);
  raise notice 'Seed: carga completa (% lotes).', (select count(*) from public.lotes);
end $$;
