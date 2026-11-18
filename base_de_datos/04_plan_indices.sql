-- =====================================================================
--  ANIS · LA CASA DE LA HUMINTA
--  Script 04 · Plan de índices (con medición antes / después)
-- ---------------------------------------------------------------------
--  Paso 1: se borran los índices (si existían) y se miden 3 consultas
--          críticas SIN índice (EXPLAIN ANALYZE).
--  Paso 2: se crean los índices del plan.
--  Paso 3: se vuelven a medir las mismas consultas CON índice.
--  Requiere: 01_esquema.sql y 02_datos_prueba.sql
-- =====================================================================

DROP INDEX IF EXISTS idx_venta_fecha_local_pagada, idx_venta_cliente_fecha, idx_detalle_venta_producto,
                     idx_lote_fefo, idx_mov_lote_fecha, idx_mov_venta, idx_mov_fecha_brin,
                     idx_produccion_producto_fecha, idx_merma_fecha_cubriente, idx_compra_proveedor_fecha,
                     idx_cliente_nombre_trgm;
ANALYZE;

-- ---------------------------------------------------------------------
-- PASO 1 · MEDICIÓN SIN ÍNDICES
-- ---------------------------------------------------------------------
-- A) Ventas pagadas del último día cerrado (cierre de caja, tablero y reportes)
EXPLAIN (ANALYZE, COSTS OFF)
SELECT COUNT(*), SUM(total)
FROM venta
WHERE estado = 'PAGADA' AND fn_fecha_local(fecha_hora) = (SELECT MAX(fecha) FROM cierre_caja);

-- B) Kárdex de un lote (se ejecuta al anular ventas y al auditar inventario)
EXPLAIN (ANALYZE, COSTS OFF)
SELECT * FROM movimiento_inventario WHERE id_lote = 150 ORDER BY fecha_hora;

-- C) Costo de la última tanda (lo ejecuta el disparador en CADA venta de humintas)
EXPLAIN (ANALYZE, COSTS OFF)
SELECT costo_total / cantidad FROM produccion
WHERE id_producto = 1 ORDER BY fecha_hora DESC LIMIT 1;

-- ---------------------------------------------------------------------
-- PASO 2 · CREACIÓN DE ÍNDICES
-- ---------------------------------------------------------------------

-- 1. B-tree FUNCIONAL y PARCIAL: ventas pagadas por día local de Bolivia.
--    Lo usan el cierre de caja, el tablero y casi todos los reportes.
--    Parcial (solo PAGADA) porque las anuladas no se reportan.
CREATE INDEX idx_venta_fecha_local_pagada ON venta (fn_fecha_local(fecha_hora)) WHERE estado = 'PAGADA';

-- 2. B-tree COMPUESTO: historial de compras de cada cliente (consulta 7) y FK.
CREATE INDEX idx_venta_cliente_fecha ON venta (id_cliente, fecha_hora DESC);

-- 3. B-tree sobre FK: ranking y rentabilidad por producto (consultas 2, 3 y 10).
CREATE INDEX idx_detalle_venta_producto ON detalle_venta (id_producto);

-- 4. B-tree COMPUESTO y PARCIAL: lotes con saldo por insumo ordenados por vencimiento.
--    Es el recorrido FEFO de cada venta y producción, y la consulta de vencimientos.
CREATE INDEX idx_lote_fefo ON lote (id_insumo, fecha_vencimiento) WHERE cantidad_disponible > 0;

-- 5. B-tree COMPUESTO: kárdex por lote en orden cronológico (FK y auditoría).
CREATE INDEX idx_mov_lote_fecha ON movimiento_inventario (id_lote, fecha_hora);

-- 6. B-tree PARCIAL: movimientos de una venta (anulación); la mayoría de filas no tiene venta.
CREATE INDEX idx_mov_venta ON movimiento_inventario (id_venta) WHERE id_venta IS NOT NULL;

-- 7. BRIN: el kárdex crece en orden de fecha; un BRIN ocupa muy poco y sirve para rangos
--    de fechas (consumo de los últimos 14 días, consulta 4).
CREATE INDEX idx_mov_fecha_brin ON movimiento_inventario USING brin (fecha_hora);

-- 8. B-tree COMPUESTO descendente: última tanda de cada producto (disparador de ventas).
CREATE INDEX idx_produccion_producto_fecha ON produccion (id_producto, fecha_hora DESC);

-- 9. B-tree CUBRIENTE (INCLUDE): reporte de mermas por fecha sin leer la tabla (index-only scan).
CREATE INDEX idx_merma_fecha_cubriente ON merma (fecha_hora) INCLUDE (motivo, costo_estimado);

-- 10. B-tree COMPUESTO: entregas de cada proveedor por fecha (consulta 9 y FK).
CREATE INDEX idx_compra_proveedor_fecha ON compra (id_proveedor, fecha_recepcion DESC);

-- 11. GIN con trigramas: buscar clientes escribiendo parte del nombre (ILIKE '%rojas%').
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;
CREATE INDEX idx_cliente_nombre_trgm ON cliente USING gin (nombre extensions.gin_trgm_ops);

ANALYZE;

-- Columnas que NO se indexan (y por qué):
--  * Catálogos pequeños (unidad_medida, metodo_pago, categorías): caben en una página;
--    el recorrido secuencial es más rápido que un índice.
--  * venta.estado solo: tiene 2 valores (baja selectividad); se usa como condición parcial.
--  * Índices HASH: el B-tree ya resuelve igualdad, rangos y ordenamiento.
--  * Las PK y UNIQUE (codigo, nombre, email, ci_nit, nit) ya crean su propio B-tree.

-- ---------------------------------------------------------------------
-- PASO 3 · MEDICIÓN CON ÍNDICES
-- ---------------------------------------------------------------------
EXPLAIN (ANALYZE, COSTS OFF)
SELECT COUNT(*), SUM(total)
FROM venta
WHERE estado = 'PAGADA' AND fn_fecha_local(fecha_hora) = (SELECT MAX(fecha) FROM cierre_caja);

EXPLAIN (ANALYZE, COSTS OFF)
SELECT * FROM movimiento_inventario WHERE id_lote = 150 ORDER BY fecha_hora;

EXPLAIN (ANALYZE, COSTS OFF)
SELECT costo_total / cantidad FROM produccion
WHERE id_producto = 1 ORDER BY fecha_hora DESC LIMIT 1;

-- Índices del plan, tipo y tamaño
SELECT i.indexrelid::regclass                                  AS indice,
       t.relname                                               AS tabla,
       am.amname                                               AS tipo,
       pg_size_pretty(pg_relation_size(i.indexrelid))          AS tamano
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
JOIN pg_class t ON t.oid = i.indrelid
JOIN pg_am am   ON am.oid = c.relam
WHERE c.relname LIKE 'idx\_%'
ORDER BY t.relname, c.relname;
