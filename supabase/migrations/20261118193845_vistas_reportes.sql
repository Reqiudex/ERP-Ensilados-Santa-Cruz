-- Definición de las vistas de reportes tal como existen en la base (no estaban en el historial).

create or replace view public.v_reporte_existencias_rotacion with (security_invoker=true) as
 SELECT s.nombre AS sede,
    p.nombre AS producto,
    p.sku,
    l.codigo AS codigo_lote,
    l.estado AS estado_lote,
    l.fecha_sellado,
    CURRENT_DATE - l.fecha_sellado AS dias_maduracion,
    e.disponible,
    e.reservado,
    e.en_transito,
    e.disponible + e.reservado + e.en_transito AS stock_total_rollos,
    round(e.disponible * l.peso_promedio_rollo / 1000.0, 2) AS stock_disponible_toneladas
   FROM public.existencias e
     JOIN public.sedes s ON s.id = e.sede_id
     JOIN public.productos p ON p.id = e.producto_id
     LEFT JOIN public.lotes l ON l.id = e.lote_id
  ORDER BY s.nombre, l.fecha_sellado;

create or replace view public.v_reporte_historico_mermas with (security_invoker=true) as
 SELECT m.id AS merma_id,
    s.nombre AS sede,
    l.codigo AS codigo_lote,
    g.nombre AS grano,
    m.cantidad AS rollos_merma,
    round(m.cantidad::numeric * l.peso_promedio_rollo / 1000.0, 2) AS toneladas_merma,
    m.causa,
    m.descripcion,
    sa.fecha_decision AS fecha_aprobacion,
    u_aprob.nombre_completo AS gerente_aprobador
   FROM public.mermas m
     JOIN public.sedes s ON s.id = m.sede_id
     JOIN public.lotes l ON l.id = m.lote_id
     JOIN public.productos p ON p.id = l.producto_id
     JOIN public.granos g ON g.id = p.grano_id
     JOIN public.solicitudes_aprobacion sa ON sa.id = m.solicitud_id
     JOIN public.usuarios u_aprob ON u_aprob.id = sa.aprobado_por;

create or replace view public.v_reporte_rendimiento_ensilado with (security_invoker=true) as
 SELECT l.id AS lote_id,
    l.codigo AS codigo_lote,
    s.nombre AS sede,
    g.nombre AS grano,
    l.fecha_sellado,
    l.rollos_producidos,
    l.peso_promedio_rollo,
    round(COALESCE(sum(p.peso_ajustado) / 1000.0, 0::numeric), 2) AS toneladas_grano_ajustadas,
        CASE
            WHEN COALESCE(sum(p.peso_ajustado), 0::numeric) > 0::numeric THEN round(l.rollos_producidos::numeric / (sum(p.peso_ajustado) / 1000.0), 2)
            ELSE 0.00
        END AS rollos_por_tonelada,
    g.rollos_ton_min,
    g.rollos_ton_max,
        CASE
            WHEN (l.rollos_producidos::numeric / NULLIF(sum(p.peso_ajustado) / 1000.0, 0::numeric)) < g.rollos_ton_min THEN 'Alerta: Bajo Rendimiento'::text
            WHEN (l.rollos_producidos::numeric / NULLIF(sum(p.peso_ajustado) / 1000.0, 0::numeric)) > g.rollos_ton_max THEN 'Alerta: Exceso / Densidad Baja'::text
            ELSE 'Óptimo'::text
        END AS dictamen_rendimiento
   FROM public.lotes l
     JOIN public.sedes s ON s.id = l.sede_id
     JOIN public.ordenes_ensilado o ON o.id = l.orden_id
     JOIN public.granos g ON g.id = o.grano_id
     LEFT JOIN public.pesajes p ON p.orden_id = o.id AND p.estado::text = 'confirmado'::text
  GROUP BY l.id, l.codigo, s.nombre, g.nombre, l.fecha_sellado, l.rollos_producidos, l.peso_promedio_rollo, g.rollos_ton_min, g.rollos_ton_max;

create or replace view public.v_reporte_ventas_producto with (security_invoker=true) as
 SELECT nv.numero AS nro_nota_venta,
    nv.fecha_registro,
    c.razon_social AS cliente,
    c.tipo AS tipo_cliente,
    nv.condicion_pago,
    nv.total,
    nv.saldo,
    nv.total - nv.saldo AS total_cobrado,
    nv.estado,
    u.nombre_completo AS ejecutivo_ventas
   FROM public.notas_venta nv
     JOIN public.pedidos ped ON ped.id = nv.pedido_id
     JOIN public.clientes c ON c.id = ped.cliente_id
     JOIN public.usuarios u ON u.id = nv.registrado_por;
