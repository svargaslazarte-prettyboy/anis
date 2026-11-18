-- =====================================================================
--  ANIS · LA CASA DE LA HUMINTA
--  Script 05 · Transacciones (COMMIT, ROLLBACK y SAVEPOINT)
-- ---------------------------------------------------------------------
--  Ejecutar en psql o por bloques en el SQL Editor de Supabase.
--  Requiere: 01_esquema.sql y 02_datos_prueba.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- T1 · COMMIT: llega una entrega de gaseosas de la distribuidora
--      La compra, el lote y el kárdex se guardan juntos o no se guarda nada.
-- ---------------------------------------------------------------------
SELECT codigo, nombre, stock_actual, estado FROM v_stock_insumo WHERE codigo = 'REV-GAS';

BEGIN;
  SELECT fn_registrar_compra(
           (SELECT id_proveedor FROM proveedor WHERE razon_social = 'Distribuidora de Bebidas El Sol'),
           jsonb_build_array(jsonb_build_object(
             'id_insumo', (SELECT id_insumo FROM insumo WHERE codigo = 'REV-GAS'),
             'cantidad', 48, 'costo_unitario', 4.60)),
           'FACTURA', 'F-' || to_char(now(), 'MMDDHH24MI')) AS id_compra_registrada;
  SELECT codigo, stock_actual, estado FROM v_stock_insumo WHERE codigo = 'REV-GAS';
COMMIT;

-- Después del COMMIT el cambio es permanente
SELECT codigo, nombre, stock_actual, estado FROM v_stock_insumo WHERE codigo = 'REV-GAS';

-- ---------------------------------------------------------------------
-- T2 · ROLLBACK por error: se intenta vender más humintas de las que hay.
--      El disparador lanza una excepción, la transacción queda abortada
--      y el ROLLBACK deshace TODO (también el pago y la bebida ya cargados).
-- ---------------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM venta) AS ventas_antes,
       (SELECT stock_listo FROM producto WHERE codigo = 'HUM-OS') AS humintas_olla_listas;

BEGIN;
  SELECT fn_registrar_venta(
           jsonb_build_array(
             jsonb_build_object('id_producto', (SELECT id_producto FROM producto WHERE codigo = 'BEB-CAF'), 'cantidad', 2),
             jsonb_build_object('id_producto', (SELECT id_producto FROM producto WHERE codigo = 'HUM-OS'),  'cantidad', 500)),
           (SELECT id_metodo_pago FROM metodo_pago WHERE nombre = 'QR'),
           'PARA_LLEVAR');
  -- Cualquier sentencia posterior falla: "current transaction is aborted"
  SELECT COUNT(*) FROM venta;
ROLLBACK;

SELECT (SELECT COUNT(*) FROM venta) AS ventas_despues,
       (SELECT stock_listo FROM producto WHERE codigo = 'HUM-OS') AS humintas_olla_listas;

-- ---------------------------------------------------------------------
-- T3 · ROLLBACK manual: error humano al actualizar precios sin WHERE
-- ---------------------------------------------------------------------
BEGIN;
  UPDATE producto SET precio_venta = precio_venta * 10;     -- ¡se olvidó el WHERE!
  SELECT codigo, nombre, precio_venta FROM producto WHERE tipo = 'ELABORADO' ORDER BY id_producto;
  SELECT COUNT(*) AS cambios_en_historial FROM historial_precio;
ROLLBACK;

-- Precios e historial vuelven a su estado original
SELECT codigo, nombre, precio_venta FROM producto WHERE tipo = 'ELABORADO' ORDER BY id_producto;
SELECT COUNT(*) AS cambios_en_historial FROM historial_precio;

-- ---------------------------------------------------------------------
-- T4 · SAVEPOINT: dos tandas de producción; la segunda tiene un error de
--      digitación (200 pasteles). Se deshace solo la segunda y se confirma
--      la primera.
-- ---------------------------------------------------------------------
BEGIN;
  SELECT fn_registrar_produccion((SELECT id_producto FROM producto WHERE codigo = 'HUM-OS'), 10::SMALLINT, 'Tanda extra') AS tanda_1;
  SAVEPOINT antes_segunda_tanda;
  SELECT fn_registrar_produccion((SELECT id_producto FROM producto WHERE codigo = 'PAS-CH'), 200::SMALLINT, 'Error de digitación') AS tanda_2;
  ROLLBACK TO SAVEPOINT antes_segunda_tanda;
COMMIT;

SELECT id_produccion, producto, cantidad, costo_total, observacion
FROM v_produccion ORDER BY id_produccion DESC LIMIT 2;
