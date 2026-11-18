-- =====================================================================
--  ANIS · LA CASA DE LA HUMINTA
--  Script 03 · 10 consultas avanzadas de negocio
-- ---------------------------------------------------------------------
--  Cada consulta responde una pregunta real de la administradora.
--  Las fechas son relativas a HOY, así que funcionan el día de la defensa.
--  Requiere: 01_esquema.sql y 02_datos_prueba.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- CONSULTA 1 · VENTAS
-- Pregunta: ¿Qué días y en qué horario vendemos más? (para planificar
--           cuántas humintas preparar y en qué tanda)
-- Técnicas: CTE, EXTRACT, CASE, agregación, función de ventana SUM() OVER()
-- ---------------------------------------------------------------------
WITH ventas AS (
  SELECT fn_fecha_local(v.fecha_hora)                                          AS fecha,
         EXTRACT(ISODOW FROM v.fecha_hora AT TIME ZONE 'America/La_Paz')::INT  AS dia_semana,
         CASE WHEN EXTRACT(HOUR FROM v.fecha_hora AT TIME ZONE 'America/La_Paz') < 14
              THEN '1 Mañana' ELSE '2 Tarde' END                                AS franja,
         v.total
  FROM venta v
  WHERE v.estado = 'PAGADA'
    AND fn_fecha_local(v.fecha_hora) BETWEEN fn_fecha_local(now()) - 56 AND fn_fecha_local(now()) - 1
)
SELECT (ARRAY['Lunes','Martes','Miércoles','Jueves','Viernes','Sábado','Domingo'])[dia_semana] AS dia,
       substr(franja, 3)                                          AS franja,
       COUNT(DISTINCT fecha)                                      AS dias,
       ROUND(COUNT(*)::NUMERIC / COUNT(DISTINCT fecha), 1)         AS ventas_por_dia,
       ROUND(SUM(total) / COUNT(DISTINCT fecha), 2)                AS bs_por_dia,
       ROUND(100 * SUM(total) / SUM(SUM(total)) OVER (), 1)        AS pct_ingresos
FROM ventas
GROUP BY dia_semana, franja
ORDER BY dia_semana, franja;

-- ---------------------------------------------------------------------
-- CONSULTA 2 · VENTAS / PRODUCTOS
-- Pregunta: ¿Cuáles son los productos estrella de los últimos 30 días y
--           qué productos generan el 80 % de los ingresos? (Pareto)
-- Técnicas: RANK(), SUM() OVER() con marco acumulado, porcentajes
-- ---------------------------------------------------------------------
SELECT RANK() OVER (ORDER BY SUM(d.subtotal) DESC)                         AS puesto,
       p.nombre                                                            AS producto,
       cp.nombre                                                           AS categoria,
       SUM(d.cantidad)                                                     AS unidades,
       SUM(d.subtotal)                                                     AS ingresos_bs,
       ROUND(100 * SUM(d.subtotal) / SUM(SUM(d.subtotal)) OVER (), 1)      AS pct,
       ROUND(100 * SUM(SUM(d.subtotal)) OVER (ORDER BY SUM(d.subtotal) DESC ROWS UNBOUNDED PRECEDING)
                 / SUM(SUM(d.subtotal)) OVER (), 1)                         AS pct_acumulado,
       CASE WHEN SUM(SUM(d.subtotal)) OVER (ORDER BY SUM(d.subtotal) DESC ROWS UNBOUNDED PRECEDING)
                 - SUM(d.subtotal) < 0.8 * SUM(SUM(d.subtotal)) OVER ()
            THEN 'A (80 %)' ELSE 'B' END                                    AS clase
FROM detalle_venta d
JOIN venta v               USING (id_venta)
JOIN producto p            USING (id_producto)
JOIN categoria_producto cp USING (id_categoria_producto)
WHERE v.estado = 'PAGADA'
  AND fn_fecha_local(v.fecha_hora) BETWEEN fn_fecha_local(now()) - 30 AND fn_fecha_local(now()) - 1
GROUP BY p.nombre, cp.nombre
ORDER BY puesto;

-- ---------------------------------------------------------------------
-- CONSULTA 3 · RENTABILIDAD
-- Pregunta: ¿Cuánto gano realmente con cada producto en el mes, si descuento
--           el costo de insumos y lo que se pierde por sobrantes?
-- Técnicas: varias CTE, LEFT JOIN, costo histórico guardado en cada venta,
--           comparación margen real vs. margen teórico (vista)
-- ---------------------------------------------------------------------
WITH periodo AS (
  SELECT fn_fecha_local(now()) - 30 AS desde, fn_fecha_local(now()) - 1 AS hasta
), vendido AS (
  SELECT d.id_producto,
         SUM(d.cantidad)                    AS unidades,
         SUM(d.subtotal)                    AS ingresos,
         SUM(d.cantidad * d.costo_unitario) AS costo_insumos
  FROM detalle_venta d
  JOIN venta v USING (id_venta), periodo
  WHERE v.estado = 'PAGADA' AND fn_fecha_local(v.fecha_hora) BETWEEN periodo.desde AND periodo.hasta
  GROUP BY d.id_producto
), perdido AS (
  SELECT m.id_producto, SUM(m.costo_estimado) AS costo_mermas
  FROM merma m, periodo
  WHERE m.id_producto IS NOT NULL AND fn_fecha_local(m.fecha_hora) BETWEEN periodo.desde AND periodo.hasta
  GROUP BY m.id_producto
)
SELECT p.nombre                                                                      AS producto,
       ve.unidades,
       ve.ingresos                                                                   AS ingresos_bs,
       ROUND(ve.costo_insumos, 2)                                                    AS costo_insumos_bs,
       COALESCE(pe.costo_mermas, 0)                                                  AS costo_sobrantes_bs,
       ROUND(ve.ingresos - ve.costo_insumos - COALESCE(pe.costo_mermas, 0), 2)       AS ganancia_bruta_bs,
       ROUND(100 * (ve.ingresos - ve.costo_insumos - COALESCE(pe.costo_mermas, 0)) / ve.ingresos, 1) AS margen_real_pct,
       r.margen_pct                                                                  AS margen_teorico_pct
FROM vendido ve
JOIN producto p                  USING (id_producto)
JOIN v_rentabilidad_producto r   USING (id_producto)
LEFT JOIN perdido pe             USING (id_producto)
ORDER BY ganancia_bruta_bs DESC;

-- ---------------------------------------------------------------------
-- CONSULTA 4 · INVENTARIO / STOCK BAJO
-- Pregunta: ¿Qué insumos están por acabarse, para cuántos días me alcanzan
--           y cuánto debo pedir a cada proveedor?
-- Técnicas: CTE sobre el kárdex, consumo promedio real, división segura
--           NULLIF, cálculo de reposición, LEFT JOIN a proveedor principal
-- ---------------------------------------------------------------------
WITH dias_abiertos AS (
  SELECT COUNT(DISTINCT fn_fecha_local(fecha_hora)) AS n
  FROM venta WHERE fecha_hora >= now() - INTERVAL '14 days'
), consumo AS (
  SELECT l.id_insumo, -SUM(m.cantidad) / (SELECT n FROM dias_abiertos) AS diario
  FROM movimiento_inventario m
  JOIN lote l USING (id_lote)
  WHERE m.tipo IN ('SALIDA_VENTA', 'SALIDA_PRODUCCION')
    AND m.fecha_hora >= now() - INTERVAL '14 days'
  GROUP BY l.id_insumo
)
SELECT s.nombre                                                   AS insumo,
       s.unidad,
       s.stock_actual,
       s.stock_minimo,
       ROUND(c.diario, 3)                                         AS consumo_diario,
       ROUND(s.stock_actual / NULLIF(c.diario, 0), 1)             AS dias_cobertura,
       GREATEST(0, ROUND(c.diario * 7 + s.stock_minimo - s.stock_actual, 1)) AS pedir_para_7_dias,
       pr.razon_social                                            AS proveedor,
       pr.telefono,
       pr.dias_entrega,
       s.estado
FROM v_stock_insumo s
LEFT JOIN consumo c           USING (id_insumo)
LEFT JOIN proveedor_insumo pi ON pi.id_insumo = s.id_insumo AND pi.es_principal
LEFT JOIN proveedor pr        ON pr.id_proveedor = pi.id_proveedor
WHERE s.estado <> 'OK' OR s.stock_actual / NULLIF(c.diario, 0) < 3
ORDER BY dias_cobertura NULLS FIRST;

-- ---------------------------------------------------------------------
-- CONSULTA 5 · VENCIMIENTOS
-- Pregunta: ¿Qué lotes vencen en los próximos 5 días, cuánto dinero está en
--           riesgo y qué debo hacer con cada uno?
-- Técnicas: vista con cálculo de días, CASE de acción, SUM() OVER() para
--           acumulado del dinero en riesgo
-- ---------------------------------------------------------------------
SELECT l.id_lote,
       l.insumo,
       l.proveedor,
       l.fecha_recepcion,
       l.fecha_vencimiento,
       l.dias_para_vencer,
       l.cantidad_disponible || ' ' || l.unidad                  AS queda,
       l.valor_en_riesgo                                         AS en_riesgo_bs,
       SUM(l.valor_en_riesgo) OVER (ORDER BY l.fecha_vencimiento, l.id_lote) AS riesgo_acumulado_bs,
       CASE WHEN l.dias_para_vencer < 0  THEN 'Dar de baja (vencido)'
            WHEN l.dias_para_vencer <= 1 THEN 'Usar HOY en la primera tanda'
            ELSE 'Usar primero (FEFO)' END                       AS accion
FROM v_lotes_vigentes l
WHERE l.dias_para_vencer <= 5
ORDER BY l.fecha_vencimiento, l.id_lote;

-- ---------------------------------------------------------------------
-- CONSULTA 6 · MERMAS (ODS 12)
-- Pregunta: ¿Cuánto dinero se pierde cada mes por desperdicio, por qué
--           motivo, y qué porcentaje de lo comprado representa?
-- Técnicas: CTE, tabla dinámica con FILTER, JOIN entre agregados,
--           indicador porcentual
-- ---------------------------------------------------------------------
WITH mermas AS (
  SELECT date_trunc('month', fecha)::DATE AS mes, motivo, costo_estimado
  FROM v_mermas
), compras AS (
  SELECT date_trunc('month', fn_fecha_local(fecha_recepcion))::DATE AS mes, SUM(total) AS total_compras
  FROM compra GROUP BY 1
)
SELECT to_char(m.mes, 'YYYY-MM')                                                AS mes,
       COALESCE(SUM(m.costo_estimado) FILTER (WHERE m.motivo = 'SOBRANTE_DIA'), 0)      AS sobrantes_bs,
       COALESCE(SUM(m.costo_estimado) FILTER (WHERE m.motivo = 'VENCIMIENTO'), 0)       AS vencidos_bs,
       COALESCE(SUM(m.costo_estimado) FILTER (WHERE m.motivo = 'DETERIORO'), 0)         AS deterioro_bs,
       COALESCE(SUM(m.costo_estimado) FILTER (WHERE m.motivo IN ('ERROR_PREPARACION','AJUSTE_CONTEO')), 0) AS otros_bs,
       SUM(m.costo_estimado)                                                    AS total_merma_bs,
       c.total_compras                                                          AS compras_bs,
       ROUND(100 * SUM(m.costo_estimado) / c.total_compras, 2)                  AS pct_sobre_compras
FROM mermas m
JOIN compras c USING (mes)
GROUP BY m.mes, c.total_compras
ORDER BY m.mes;

-- ---------------------------------------------------------------------
-- CONSULTA 7 · CLIENTES
-- Pregunta: ¿Quiénes son mis clientes más fieles, cuánto gastan y a quiénes
--           estoy perdiendo? (segmentación tipo RFM)
-- Técnicas: CTE, agregados, NTILE(), CASE de segmentación, días desde la
--           última visita
-- ---------------------------------------------------------------------
WITH resumen AS (
  SELECT c.id_cliente,
         c.nombre,
         c.telefono,
         COUNT(*)                                          AS visitas,
         SUM(v.total)                                      AS gasto_total,
         ROUND(AVG(v.total), 2)                            AS ticket_promedio,
         MAX(fn_fecha_local(v.fecha_hora))                 AS ultima_visita,
         fn_fecha_local(now()) - MAX(fn_fecha_local(v.fecha_hora)) AS dias_sin_venir
  FROM venta v
  JOIN cliente c USING (id_cliente)
  WHERE v.estado = 'PAGADA' AND c.id_cliente <> 1
  GROUP BY c.id_cliente, c.nombre, c.telefono
)
SELECT nombre,
       telefono,
       visitas,
       gasto_total                                        AS gasto_total_bs,
       ticket_promedio                                    AS ticket_bs,
       ultima_visita,
       dias_sin_venir,
       NTILE(4) OVER (ORDER BY gasto_total DESC)          AS cuartil_gasto,
       CASE WHEN dias_sin_venir > 21                       THEN 'En riesgo (no vuelve)'
            WHEN visitas >= 20 AND dias_sin_venir <= 7     THEN 'VIP'
            WHEN visitas >= 8                              THEN 'Frecuente'
            ELSE 'Ocasional' END                           AS segmento
FROM resumen
ORDER BY gasto_total DESC
LIMIT 15;

-- ---------------------------------------------------------------------
-- CONSULTA 8 · VENTAS (tendencia)
-- Pregunta: ¿Estoy vendiendo más o menos que la semana pasada?
-- Técnicas: date_trunc por semana, LAG(), variación porcentual, AVG móvil
-- ---------------------------------------------------------------------
WITH semanal AS (
  SELECT date_trunc('week', fn_fecha_local(v.fecha_hora))::DATE AS semana,
         COUNT(*)                                               AS nro_ventas,
         SUM(v.total)                                           AS total
  FROM venta v
  WHERE v.estado = 'PAGADA'
    AND fn_fecha_local(v.fecha_hora) < date_trunc('week', fn_fecha_local(now()))::DATE
  GROUP BY 1
)
SELECT semana                                                                AS semana_del,
       semana + 6                                                            AS al,
       nro_ventas,
       total                                                                 AS total_bs,
       LAG(total) OVER (ORDER BY semana)                                     AS semana_anterior_bs,
       ROUND(100 * (total - LAG(total) OVER (ORDER BY semana))
                 / LAG(total) OVER (ORDER BY semana), 1)                     AS variacion_pct,
       ROUND(AVG(total) OVER (ORDER BY semana ROWS BETWEEN 3 PRECEDING AND CURRENT ROW), 2) AS promedio_4_semanas_bs
FROM semanal
ORDER BY semana;

-- ---------------------------------------------------------------------
-- CONSULTA 9 · PROVEEDORES / COSTOS
-- Pregunta: ¿Cuánto le compro a cada proveedor, quién me subió los precios
--           y cuánto pierdo por productos suyos que se vencen?
-- Técnicas: FIRST_VALUE / LAST_VALUE con ventana nombrada (WINDOW),
--           MIN/MAX/AVG, LEFT JOIN a mermas por vencimiento
-- ---------------------------------------------------------------------
WITH entregas AS (
  SELECT pr.id_proveedor, pr.razon_social, i.id_insumo, i.nombre AS insumo, um.codigo AS unidad,
         l.costo_unitario, l.cantidad_recibida, l.subtotal,
         FIRST_VALUE(l.costo_unitario) OVER w                                                 AS primer_precio,
         LAST_VALUE(l.costo_unitario)  OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS ultimo_precio
  FROM lote l
  JOIN compra c         USING (id_compra)
  JOIN proveedor pr     USING (id_proveedor)
  JOIN insumo i         USING (id_insumo)
  JOIN unidad_medida um USING (id_unidad_medida)
  WINDOW w AS (PARTITION BY pr.id_proveedor, i.id_insumo ORDER BY c.fecha_recepcion)
), vencidos AS (
  SELECT c.id_proveedor, l.id_insumo, SUM(m.costo_estimado) AS perdido
  FROM merma m
  JOIN lote l   USING (id_lote)
  JOIN compra c USING (id_compra)
  WHERE m.motivo IN ('VENCIMIENTO', 'DETERIORO')
  GROUP BY c.id_proveedor, l.id_insumo
)
SELECT e.razon_social                                                      AS proveedor,
       e.insumo,
       COUNT(*)                                                            AS entregas,
       SUM(e.cantidad_recibida) || ' ' || e.unidad                         AS cantidad_total,
       SUM(e.subtotal)                                                     AS comprado_bs,
       ROUND(MIN(e.costo_unitario), 2)                                     AS precio_min,
       ROUND(MAX(e.costo_unitario), 2)                                     AS precio_max,
       ROUND(100 * (MAX(e.ultimo_precio) - MAX(e.primer_precio)) / MAX(e.primer_precio), 1) AS variacion_precio_pct,
       COALESCE(MAX(v.perdido), 0)                                         AS perdido_por_vencimiento_bs
FROM entregas e
LEFT JOIN vencidos v USING (id_proveedor, id_insumo)
GROUP BY e.razon_social, e.insumo, e.unidad
ORDER BY comprado_bs DESC;

-- ---------------------------------------------------------------------
-- CONSULTA 10 · PRODUCCIÓN vs VENTAS (ODS 12)
-- Pregunta: ¿Cuántas humintas debo preparar por día para no quedarme sin
--           stock ni botar sobrantes?
-- Técnicas: CTE encadenadas, FULL agregación por día, PERCENTILE_CONT
--           (percentil 90 de lo vendido), segmentación entre semana / fin de
--           semana, indicador de aprovechamiento
-- ---------------------------------------------------------------------
WITH periodo AS (
  SELECT fn_fecha_local(now()) - 28 AS desde, fn_fecha_local(now()) - 1 AS hasta
), producido AS (
  SELECT pr.id_producto, fn_fecha_local(pr.fecha_hora) AS fecha, SUM(pr.cantidad) AS producido
  FROM produccion pr, periodo
  WHERE fn_fecha_local(pr.fecha_hora) BETWEEN periodo.desde AND periodo.hasta
  GROUP BY 1, 2
), vendido AS (
  SELECT d.id_producto, fn_fecha_local(v.fecha_hora) AS fecha, SUM(d.cantidad) AS vendido
  FROM detalle_venta d JOIN venta v USING (id_venta), periodo
  WHERE v.estado = 'PAGADA' AND fn_fecha_local(v.fecha_hora) BETWEEN periodo.desde AND periodo.hasta
  GROUP BY 1, 2
), sobrante AS (
  SELECT m.id_producto, fn_fecha_local(m.fecha_hora) AS fecha, SUM(m.cantidad) AS sobrante, SUM(m.costo_estimado) AS costo
  FROM merma m, periodo
  WHERE m.id_producto IS NOT NULL AND fn_fecha_local(m.fecha_hora) BETWEEN periodo.desde AND periodo.hasta
  GROUP BY 1, 2
), diario AS (
  SELECT p.id_producto, p.fecha,
         CASE WHEN EXTRACT(ISODOW FROM p.fecha) IN (6, 7) THEN 'Fin de semana' ELSE 'Martes a viernes' END AS tipo_dia,
         p.producido, COALESCE(v.vendido, 0) AS vendido, COALESCE(s.sobrante, 0) AS sobrante, COALESCE(s.costo, 0) AS costo
  FROM producido p
  LEFT JOIN vendido v  USING (id_producto, fecha)
  LEFT JOIN sobrante s USING (id_producto, fecha)
)
SELECT pr.nombre                                                       AS producto,
       d.tipo_dia,
       COUNT(*)                                                        AS dias,
       ROUND(AVG(d.producido), 1)                                      AS produce_dia,
       ROUND(AVG(d.vendido), 1)                                        AS vende_dia,
       ROUND(AVG(d.sobrante), 1)                                       AS sobra_dia,
       ROUND(100 * SUM(d.vendido) / SUM(d.producido), 1)               AS aprovechamiento_pct,
       SUM(d.costo)                                                    AS costo_sobrantes_bs,
       CEIL(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY d.vendido))    AS produccion_sugerida
FROM diario d
JOIN producto pr USING (id_producto)
GROUP BY pr.nombre, d.tipo_dia
ORDER BY pr.nombre, d.tipo_dia DESC;
