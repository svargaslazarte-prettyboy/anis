-- =====================================================================
--  ANIS · LA CASA DE LA HUMINTA
--  Script 02 · Datos de prueba realistas
-- ---------------------------------------------------------------------
--  1) Catálogos reales del local: menú y precios (fotografía del menú),
--     insumos, recetas, proveedores que entregan en el local, clientes.
--  2) Simulación de ~10 semanas de operación (martes a domingo) que
--     termina HOY: entregas de proveedores, producción por tandas,
--     ventas, mermas, vencimientos y cierres de caja.
--     Todo pasa por las funciones y disparadores del script 01, así que
--     el inventario, los lotes y el kárdex quedan consistentes.
--  Requiere: 01_esquema.sql
--  SUPABASE: si aparece el aviso "Potential issues detected", elegir
--  "Run without RLS" (este script solo crea tablas auxiliares que borra
--  al final; la seguridad real se activa con 06_supabase_seguridad.sql).
-- =====================================================================

SET client_min_messages = notice;

TRUNCATE cierre_caja, historial_precio, movimiento_inventario, merma, produccion,
         detalle_venta, venta, metodo_pago, cliente, lote, compra, proveedor_insumo,
         proveedor, receta, insumo, categoria_insumo, unidad_medida, producto,
         categoria_producto, usuario
RESTART IDENTITY CASCADE;

-- ---------------------------------------------------------------------
-- 1. CATÁLOGOS
-- ---------------------------------------------------------------------
INSERT INTO usuario (nombre_completo, email, rol)
VALUES ('Administradora Anis', 'admin@anis.bo', 'ADMINISTRADOR');

INSERT INTO metodo_pago (nombre) VALUES ('EFECTIVO'), ('QR');

INSERT INTO unidad_medida (codigo, nombre) VALUES
  ('UND', 'Unidad'),
  ('KG',  'Kilogramo'),
  ('L',   'Litro');

INSERT INTO categoria_producto (nombre, descripcion) VALUES
  ('Humintas',          'Humintas a la olla y al horno, simples y doble queso'),
  ('Pasteles',          'Pastel de choclo por porción'),
  ('Bebidas calientes', 'Café, té, mate, chocolate y refill'),
  ('Bebidas frías',     'Gaseosas y jugos de reventa'),
  ('Extras',            'Agregados al pedido');

INSERT INTO categoria_insumo (nombre, descripcion) VALUES
  ('Materia prima',           'Choclo para humintas y pastel'),
  ('Lácteos y huevos',        'Queso, leche, mantequilla y huevo'),
  ('Condimentos y abarrotes', 'Anís, manteca, azúcar y sal'),
  ('Insumos de bebidas',      'Café, té, mate y chocolate'),
  ('Bebidas de reventa',      'Gaseosas y jugos embotellados'),
  ('Empaques',                'Bolsas para pedidos para llevar');

-- codigo, nombre, categoría, unidad, stock mínimo, perecedero, vida útil (días), días de alerta
INSERT INTO insumo (id_categoria_insumo, id_unidad_medida, codigo, nombre, stock_minimo,
                    es_perecedero, vida_util_dias, dias_alerta_vencimiento)
SELECT ci.id_categoria_insumo, um.id_unidad_medida, x.codigo, x.nombre, x.minimo, x.perecedero, x.vida, x.alerta
FROM (VALUES
  ('INS-CHO', 'Choclo (mazorca)',          'Materia prima',           'UND', 120.000, TRUE,  4,    1),
  ('INS-QUE', 'Queso fresco criollo',      'Lácteos y huevos',        'KG',    4.000, TRUE,  10,   2),
  ('INS-LEC', 'Leche fresca',              'Lácteos y huevos',        'L',     4.000, TRUE,  5,    1),
  ('INS-MTQ', 'Mantequilla',               'Lácteos y huevos',        'KG',    1.000, TRUE,  30,   5),
  ('INS-HUE', 'Huevo',                     'Lácteos y huevos',        'UND',  30.000, TRUE,  21,   3),
  ('INS-ANI', 'Anís en grano',             'Condimentos y abarrotes', 'KG',    0.150, TRUE,  180, 15),
  ('INS-MAN', 'Manteca de cerdo',          'Condimentos y abarrotes', 'KG',    1.500, TRUE,  45,   5),
  ('INS-AZU', 'Azúcar',                    'Condimentos y abarrotes', 'KG',    5.000, FALSE, NULL, 0),
  ('INS-SAL', 'Sal fina',                  'Condimentos y abarrotes', 'KG',    1.000, FALSE, NULL, 0),
  ('INS-CAF', 'Café molido',               'Insumos de bebidas',      'KG',    0.500, TRUE,  90,  10),
  ('INS-TE',  'Té en sobres',              'Insumos de bebidas',      'UND',  25.000, TRUE,  365, 30),
  ('INS-MAT', 'Mate en sobres',            'Insumos de bebidas',      'UND',  25.000, TRUE,  365, 30),
  ('INS-CHC', 'Chocolate en polvo',        'Insumos de bebidas',      'KG',    0.500, TRUE,  180, 15),
  ('REV-GAS', 'Gaseosa 500 ml',            'Bebidas de reventa',      'UND',  12.000, TRUE,  120, 10),
  ('REV-JUG', 'Jugo del Sol 620 ml',       'Bebidas de reventa',      'UND',  12.000, TRUE,  90,  10),
  ('EMP-BOL', 'Bolsa de papel para llevar','Empaques',                'UND', 100.000, FALSE, NULL, 0)
) AS x (codigo, nombre, categoria, unidad, minimo, perecedero, vida, alerta)
JOIN categoria_insumo ci ON ci.nombre = x.categoria
JOIN unidad_medida um    ON um.codigo = x.unidad;

-- Menú real del local (precios en Bs). Pastel y jugo tenían precio anterior; se actualiza en la simulación.
INSERT INTO producto (id_categoria_producto, codigo, nombre, tipo, precio_venta)
SELECT cp.id_categoria_producto, x.codigo, x.nombre, x.tipo, x.precio
FROM (VALUES
  ('HUM-OS',  'Huminta a la olla simple',      'Humintas',          'ELABORADO',  12.00),
  ('HUM-OD',  'Huminta a la olla doble queso', 'Humintas',          'ELABORADO',  14.00),
  ('HUM-HS',  'Huminta al horno simple',       'Humintas',          'ELABORADO',  12.00),
  ('HUM-HD',  'Huminta al horno doble queso',  'Humintas',          'ELABORADO',  14.00),
  ('PAS-CH',  'Pastel de choclo',              'Pasteles',          'ELABORADO',  14.00),
  ('BEB-CAF', 'Café',                          'Bebidas calientes', 'AL_MOMENTO',  8.00),
  ('BEB-TE',  'Té',                            'Bebidas calientes', 'AL_MOMENTO',  8.00),
  ('BEB-MAT', 'Mate',                          'Bebidas calientes', 'AL_MOMENTO',  8.00),
  ('BEB-CHO', 'Chocolate',                     'Bebidas calientes', 'AL_MOMENTO',  8.00),
  ('BEB-REF', 'Refill de bebida caliente',     'Bebidas calientes', 'AL_MOMENTO',  5.00),
  ('BEB-GAS', 'Gaseosa 500 ml',                'Bebidas frías',     'REVENTA',     8.00),
  ('BEB-JUG', 'Jugo del Sol 620 ml',           'Bebidas frías',     'REVENTA',     8.00),
  ('EXT-QUE', 'Extra queso',                   'Extras',            'AL_MOMENTO',  3.00)
) AS x (codigo, nombre, categoria, tipo, precio)
JOIN categoria_producto cp ON cp.nombre = x.categoria;

-- Recetas: cantidad de insumo por 1 unidad de producto
INSERT INTO receta (id_producto, id_insumo, cantidad)
SELECT p.id_producto, i.id_insumo, x.cantidad
FROM (VALUES
  ('HUM-OS','INS-CHO',2.0000), ('HUM-OS','INS-QUE',0.0400), ('HUM-OS','INS-ANI',0.0010),
  ('HUM-OS','INS-MAN',0.0120), ('HUM-OS','INS-AZU',0.0120), ('HUM-OS','INS-SAL',0.0020),
  ('HUM-OD','INS-CHO',2.0000), ('HUM-OD','INS-QUE',0.0800), ('HUM-OD','INS-ANI',0.0010),
  ('HUM-OD','INS-MAN',0.0120), ('HUM-OD','INS-AZU',0.0120), ('HUM-OD','INS-SAL',0.0020),
  ('HUM-HS','INS-CHO',2.0000), ('HUM-HS','INS-QUE',0.0400), ('HUM-HS','INS-ANI',0.0010),
  ('HUM-HS','INS-MTQ',0.0120), ('HUM-HS','INS-AZU',0.0150), ('HUM-HS','INS-SAL',0.0020),
  ('HUM-HS','INS-HUE',0.2500), ('HUM-HS','INS-LEC',0.0200),
  ('HUM-HD','INS-CHO',2.0000), ('HUM-HD','INS-QUE',0.0800), ('HUM-HD','INS-ANI',0.0010),
  ('HUM-HD','INS-MTQ',0.0120), ('HUM-HD','INS-AZU',0.0150), ('HUM-HD','INS-SAL',0.0020),
  ('HUM-HD','INS-HUE',0.2500), ('HUM-HD','INS-LEC',0.0200),
  ('PAS-CH','INS-CHO',2.5000), ('PAS-CH','INS-QUE',0.0600), ('PAS-CH','INS-HUE',0.5000),
  ('PAS-CH','INS-MTQ',0.0200), ('PAS-CH','INS-AZU',0.0200), ('PAS-CH','INS-LEC',0.0400),
  ('PAS-CH','INS-ANI',0.0010), ('PAS-CH','INS-SAL',0.0020),
  ('BEB-CAF','INS-CAF',0.0100), ('BEB-CAF','INS-AZU',0.0100),
  ('BEB-TE', 'INS-TE', 1.0000), ('BEB-TE', 'INS-AZU',0.0100),
  ('BEB-MAT','INS-MAT',1.0000), ('BEB-MAT','INS-AZU',0.0100),
  ('BEB-CHO','INS-CHC',0.0250), ('BEB-CHO','INS-LEC',0.2000), ('BEB-CHO','INS-AZU',0.0120),
  ('BEB-REF','INS-CAF',0.0080), ('BEB-REF','INS-AZU',0.0080),
  ('BEB-GAS','REV-GAS',1.0000),
  ('BEB-JUG','REV-JUG',1.0000),
  ('EXT-QUE','INS-QUE',0.0400)
) AS x (producto, insumo, cantidad)
JOIN producto p ON p.codigo = x.producto
JOIN insumo i   ON i.codigo = x.insumo;

-- Proveedores: todos entregan en el local (la administradora no sale a comprar)
INSERT INTO proveedor (razon_social, nit, nombre_contacto, telefono, direccion, dias_entrega) VALUES
  ('Choclos del Valle',               NULL,         'Juana Quispe',     '71234567', 'Productora del valle, entrega en el local', 'Martes, jueves y sábado'),
  ('Lácteos San Isidro',              '4587120017', 'Mario Flores',     '72345678', 'Planta lechera, entrega en el local',       'Martes y viernes'),
  ('Avícola La Granja',               '3021457015', 'Pedro Mendoza',    '73456789', 'Granja avícola, entrega en el local',       'Miércoles'),
  ('Especias La Cosecha',             '5120338010', 'Elena Gutiérrez',  '74561234', 'Mercado central, entrega en el local',      'Miércoles'),
  ('Abarrotes Doña Carmen',           '6234781019', 'Carmen Rojas',     '74567890', 'Mercado central, entrega en el local',      'Martes'),
  ('Distribuidora de Bebidas El Sol', '1028745026', 'Jorge Arancibia',  '75678901', 'Distribuidora, entrega en el local',        'Jueves'),
  ('Bolsas y Empaques Andinos',       '7345120014', 'Rosa Huanca',      '76789012', 'Fábrica de bolsas, entrega en el local',    'Martes');

INSERT INTO proveedor_insumo (id_proveedor, id_insumo, precio_referencia, es_principal)
SELECT pr.id_proveedor, i.id_insumo, x.precio, TRUE
FROM (VALUES
  ('Choclos del Valle',               'INS-CHO',   1.10),
  ('Lácteos San Isidro',              'INS-QUE',  42.00),
  ('Lácteos San Isidro',              'INS-LEC',   7.50),
  ('Lácteos San Isidro',              'INS-MTQ',  48.00),
  ('Avícola La Granja',               'INS-HUE',   1.10),
  ('Especias La Cosecha',             'INS-ANI',  65.00),
  ('Abarrotes Doña Carmen',           'INS-MAN',  28.00),
  ('Abarrotes Doña Carmen',           'INS-AZU',   7.00),
  ('Abarrotes Doña Carmen',           'INS-SAL',   3.50),
  ('Abarrotes Doña Carmen',           'INS-CAF', 130.00),
  ('Abarrotes Doña Carmen',           'INS-TE',    0.35),
  ('Abarrotes Doña Carmen',           'INS-MAT',   0.35),
  ('Abarrotes Doña Carmen',           'INS-CHC',  55.00),
  ('Distribuidora de Bebidas El Sol', 'REV-GAS',   4.60),
  ('Distribuidora de Bebidas El Sol', 'REV-JUG',   5.80),
  ('Bolsas y Empaques Andinos',       'EMP-BOL',   0.25)
) AS x (proveedor, insumo, precio)
JOIN proveedor pr ON pr.razon_social = x.proveedor
JOIN insumo i     ON i.codigo = x.insumo;
-- Proveedor alternativo (no principal) de queso, por si el principal no entrega
INSERT INTO proveedor_insumo (id_proveedor, id_insumo, precio_referencia, es_principal)
SELECT pr.id_proveedor, i.id_insumo, 44.00, FALSE
FROM proveedor pr, insumo i WHERE pr.razon_social = 'Abarrotes Doña Carmen' AND i.codigo = 'INS-QUE';

-- Clientes: el 1 es el cliente general; 40 clientes registrados (datos ficticios)
INSERT INTO cliente (nombre, ci_nit, telefono, email, fecha_registro)
VALUES ('CLIENTE GENERAL', NULL, NULL, NULL, current_date - 120);

INSERT INTO cliente (nombre, ci_nit, telefono, email, fecha_registro)
SELECT n.nombre || ' ' || a1.apellido || ' ' || a2.apellido,
       (4100000 + g * 73157)::TEXT,
       (CASE WHEN g % 2 = 0 THEN '7' ELSE '6' END) || lpad(((g * 7919 + 1234567) % 10000000)::TEXT, 7, '0'),
       CASE WHEN g % 3 = 0
            THEN lower(translate(n.nombre || '.' || a1.apellido, 'áéíóúñÁÉÍÓÚÑ ', 'aeiounAEIOUN')) || g || '@example.com' END,
       current_date - 110 + (g * 2)
FROM generate_series(1, 40) AS g
JOIN LATERAL (SELECT (ARRAY['María','Juan Carlos','Lucía','Carlos','Ana Belén','Jorge','Patricia','Rodrigo',
                            'Daniela','Miguel','Gabriela','Fernando','Valeria','Álvaro','Camila','Sergio',
                            'Paola','Diego','Verónica','Marcelo'])[1 + (g - 1) % 20] AS nombre) n ON TRUE
JOIN LATERAL (SELECT (ARRAY['Mamani','Rojas','Flores','Quispe','Gutiérrez','Vargas','Choque','Céspedes',
                            'Ortiz','Fernández','Torrez','Mendoza','Aguilar','Romero','Cruz','Limachi',
                            'Soliz','Zambrana','Ríos','Paredes','Villca','Herrera','Salazar'])[1 + (g * 7) % 23] AS apellido) a1 ON TRUE
JOIN LATERAL (SELECT (ARRAY['Mamani','Rojas','Flores','Quispe','Gutiérrez','Vargas','Choque','Céspedes',
                            'Ortiz','Fernández','Torrez','Mendoza','Aguilar','Romero','Cruz','Limachi',
                            'Soliz','Zambrana','Ríos','Paredes','Villca','Herrera','Salazar'])[1 + (g * 11 + 5) % 23] AS apellido) a2 ON TRUE;

-- ---------------------------------------------------------------------
-- 2. SIMULACIÓN DE OPERACIÓN DIARIA
-- ---------------------------------------------------------------------

-- Plan base de producción (unidades por día normal) y peso en la demanda
-- Tablas auxiliares de la simulación (esquema temporal que se borra al final)
DROP SCHEMA IF EXISTS carga_tmp CASCADE;
CREATE SCHEMA carga_tmp;
CREATE TABLE carga_tmp.comida (codigo VARCHAR PRIMARY KEY, produccion_base INT, peso NUMERIC);
INSERT INTO carga_tmp.comida VALUES
  ('HUM-OS', 24, 0.28), ('HUM-OD', 20, 0.22), ('HUM-HS', 16, 0.16), ('HUM-HD', 18, 0.21), ('PAS-CH', 10, 0.13);

-- Bebidas y extras: peso en la demanda y unidades estimadas por día normal
CREATE TABLE carga_tmp.bebida (codigo VARCHAR PRIMARY KEY, peso NUMERIC, por_dia NUMERIC, caliente BOOLEAN);
INSERT INTO carga_tmp.bebida VALUES
  ('BEB-CAF', 0.30, 11, TRUE), ('BEB-TE', 0.12, 5, TRUE), ('BEB-MAT', 0.14, 6, TRUE),
  ('BEB-CHO', 0.18, 7, TRUE),  ('BEB-GAS', 0.16, 7, FALSE), ('BEB-JUG', 0.10, 5, FALSE),
  ('BEB-REF', 0.00, 3, TRUE),  ('EXT-QUE', 0.00, 4, FALSE);

-- Días de entrega por proveedor (ISO: 1=lunes ... 7=domingo), documento y presentación
CREATE TABLE carga_tmp.entrega (razon_social VARCHAR PRIMARY KEY, dias INT[], documento VARCHAR);
INSERT INTO carga_tmp.entrega VALUES
  ('Choclos del Valle',               ARRAY[2,4,6], 'RECIBO'),
  ('Lácteos San Isidro',              ARRAY[2,5],   'FACTURA'),
  ('Avícola La Granja',               ARRAY[3],     'NOTA_REMISION'),
  ('Especias La Cosecha',             ARRAY[3],     'NOTA_REMISION'),
  ('Abarrotes Doña Carmen',           ARRAY[2],     'NOTA_REMISION'),
  ('Distribuidora de Bebidas El Sol', ARRAY[4],     'FACTURA'),
  ('Bolsas y Empaques Andinos',       ARRAY[2],     'RECIBO');

CREATE TABLE carga_tmp.presentacion (codigo VARCHAR PRIMARY KEY, paquete NUMERIC);
INSERT INTO carga_tmp.presentacion VALUES
  ('INS-CHO', 10), ('INS-QUE', 0.5), ('INS-LEC', 1), ('INS-MTQ', 0.5), ('INS-HUE', 30),
  ('INS-ANI', 0.25), ('INS-MAN', 1), ('INS-AZU', 5), ('INS-SAL', 1), ('INS-CAF', 0.5),
  ('INS-TE', 25), ('INS-MAT', 25), ('INS-CHC', 0.5), ('REV-GAS', 12), ('REV-JUG', 12), ('EMP-BOL', 100);

-- Consumo estimado de cada insumo en un día normal (según recetas y demanda esperada)
CREATE TABLE carga_tmp.consumo AS
SELECT r.id_insumo, SUM(r.cantidad * x.unidades) AS por_dia
FROM (SELECT codigo, produccion_base::NUMERIC AS unidades FROM carga_tmp.comida
      UNION ALL SELECT codigo, por_dia FROM carga_tmp.bebida) x
JOIN producto p USING (codigo)
JOIN receta r   USING (id_producto)
GROUP BY r.id_insumo;
INSERT INTO carga_tmp.consumo SELECT id_insumo, 16 FROM insumo WHERE codigo = 'EMP-BOL';

-- Factor de demanda por día de la semana (lunes cerrado)
CREATE OR REPLACE FUNCTION carga_tmp.factor_dia(p_dia DATE) RETURNS NUMERIC LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE EXTRACT(ISODOW FROM p_dia)::INT
           WHEN 1 THEN 0 WHEN 5 THEN 1.15 WHEN 6 THEN 1.5 WHEN 7 THEN 1.5 ELSE 1 END::NUMERIC
$$;

CREATE OR REPLACE FUNCTION carga_tmp.momento(p_dia DATE, p_hora TIME) RETURNS TIMESTAMPTZ LANGUAGE sql IMMUTABLE AS $$
  SELECT (p_dia + p_hora) AT TIME ZONE 'America/La_Paz'
$$;

DO $$
DECLARE
  v_hoy        DATE := fn_fecha_local(now());
  v_ini        DATE := fn_fecha_local(now()) - 70;
  v_ahora      TIMESTAMPTZ := clock_timestamp();
  v_efectivo   SMALLINT := (SELECT id_metodo_pago FROM metodo_pago WHERE nombre = 'EFECTIVO');
  v_qr         SMALLINT := (SELECT id_metodo_pago FROM metodo_pago WHERE nombre = 'QR');
  d            DATE;
  v_factor     NUMERIC;
  v_ts         TIMESTAMPTZ;
  v_items      JSONB;
  v_comida     JSONB;
  v_tipo       VARCHAR;
  v_cliente    INTEGER;
  v_prod       INTEGER;
  v_stock      INTEGER;
  v_cod        VARCHAR;
  v_cant       NUMERIC;
  v_n          INTEGER;
  v_id         INTEGER;
  v_tarde_hecha BOOLEAN;
  v_cubre      NUMERIC;
  v_dia_sig    DATE;
  v_dif        NUMERIC;
  v_tot_ef     NUMERIC;
  v_fallas     INTEGER := 0;
  v_ventas     INTEGER := 0;
  r            RECORD;
  p            RECORD;
BEGIN
  PERFORM setseed(0.2026);

  FOR d IN SELECT generate_series(v_ini, v_hoy, INTERVAL '1 day')::DATE LOOP
    CONTINUE WHEN EXTRACT(ISODOW FROM d) = 1;           -- lunes: cerrado
    CONTINUE WHEN d = v_hoy AND v_ahora < carga_tmp.momento(d, TIME '07:00');
    v_factor := carga_tmp.factor_dia(d);

    -- 06:00 · Baja de lotes vencidos
    PERFORM fn_procesar_vencidos(carga_tmp.momento(d, TIME '06:00'));

    -- 06:30 · Entregas de proveedores (reponen hasta la siguiente entrega + stock mínimo)
    FOR p IN SELECT pr.id_proveedor, pr.razon_social, e.dias, e.documento
             FROM proveedor pr JOIN carga_tmp.entrega e USING (razon_social) ORDER BY pr.id_proveedor LOOP
      CONTINUE WHEN NOT (d = v_ini OR EXTRACT(ISODOW FROM d)::INT = ANY (p.dias));
      -- Próximo día de entrega de este proveedor
      SELECT MIN(x)::DATE INTO v_dia_sig
      FROM generate_series(d + 1, d + 8, INTERVAL '1 day') x
      WHERE EXTRACT(ISODOW FROM x)::INT = ANY (p.dias);
      v_items := '[]'::JSONB;
      FOR r IN SELECT i.id_insumo, i.codigo, i.stock_minimo, c.por_dia, pi.precio_referencia, t.paquete
               FROM proveedor_insumo pi
               JOIN insumo i USING (id_insumo)
               JOIN carga_tmp.consumo c USING (id_insumo)
               JOIN carga_tmp.presentacion t ON t.codigo = i.codigo
               WHERE pi.id_proveedor = p.id_proveedor AND pi.es_principal LOOP
        SELECT SUM(carga_tmp.factor_dia(x::DATE)) INTO v_cubre
        FROM generate_series(d, v_dia_sig - 1, INTERVAL '1 day') x;
        v_cant := r.por_dia * v_cubre * (1.04 + random() * 0.12) + r.stock_minimo - fn_stock_insumo(r.id_insumo, d);
        CONTINUE WHEN v_cant <= 0;
        -- Última semana: la distribuidora no tenía gaseosas y de jugos solo trajo un paquete
        CONTINUE WHEN d > v_hoy - 8 AND r.codigo = 'REV-GAS';
        v_cant := CASE WHEN d > v_hoy - 8 AND r.codigo = 'REV-JUG' THEN r.paquete
                       ELSE CEIL(v_cant / r.paquete) * r.paquete END;
        v_items := v_items || jsonb_build_object(
          'id_insumo', r.id_insumo,
          'cantidad', v_cant,
          'costo_unitario', ROUND(r.precio_referencia
                                  * (1 + (random()::NUMERIC - 0.5) * 0.06)
                                  * CASE r.codigo WHEN 'INS-CHO' THEN 1 + 0.15 * (d - v_ini) / 70.0
                                                  WHEN 'INS-QUE' THEN 1 + 0.05 * (d - v_ini) / 70.0
                                                  ELSE 1 END, 4));
      END LOOP;
      IF jsonb_array_length(v_items) > 0 THEN
        PERFORM fn_registrar_compra(
          p.id_proveedor, v_items, p.documento,
          (1000 + (SELECT COUNT(*) FROM compra WHERE id_proveedor = p.id_proveedor))::TEXT,
          CASE WHEN p.razon_social LIKE 'Distribuidora%' AND d > v_hoy - 8 THEN 'PENDIENTE' ELSE 'PAGADO' END,
          NULL,
          carga_tmp.momento(d, TIME '06:30') + (p.id_proveedor * INTERVAL '4 minutes'));
      END IF;
    END LOOP;

    -- Cambio de precios del menú (queda en historial_precio)
    IF d = v_ini + 30 THEN
      UPDATE producto SET precio_venta = 15.00 WHERE codigo = 'PAS-CH';
      UPDATE producto SET precio_venta = 9.00  WHERE codigo = 'BEB-JUG';
      UPDATE historial_precio SET fecha_cambio = carga_tmp.momento(d, TIME '06:45') WHERE fecha_cambio = now();
    END IF;

    -- 07:00 · Tanda de producción de la mañana (65 % del plan del día)
    FOR r IN SELECT p2.id_producto, t.produccion_base FROM carga_tmp.comida t JOIN producto p2 USING (codigo) LOOP
      v_cant := GREATEST(1, ROUND(r.produccion_base * v_factor * 0.65 * (0.9 + random() * 0.2)));
      BEGIN
        PERFORM fn_registrar_produccion(r.id_producto, v_cant::SMALLINT, 'Tanda de la mañana', carga_tmp.momento(d, TIME '07:00'));
      EXCEPTION WHEN raise_exception THEN
        v_fallas := v_fallas + 1;
      END;
    END LOOP;

    -- Humintas al horno que se quemaron (error de preparación, ocasional)
    IF random() < 0.05 THEN
      BEGIN
        PERFORM fn_registrar_merma('ERROR_PREPARACION', (2 + floor(random() * 3))::NUMERIC, NULL,
                                   (SELECT id_producto FROM producto WHERE codigo = 'HUM-HS'),
                                   'Se quemaron en el horno', carga_tmp.momento(d, TIME '07:40'));
      EXCEPTION WHEN raise_exception THEN NULL;
      END;
    END IF;

    -- Ventas del día: 60 % en la mañana (07:30-12:00) y 40 % en la tarde (16:00-20:30)
    v_tarde_hecha := FALSE;
    v_n := ROUND(38 * v_factor * (0.85 + random() * 0.30));
    FOR v_ts IN
      SELECT CASE WHEN random() < 0.6
                  THEN carga_tmp.momento(d, TIME '07:30') + random() * INTERVAL '270 minutes'
                  ELSE carga_tmp.momento(d, TIME '16:00') + random() * INTERVAL '270 minutes' END
      FROM generate_series(1, v_n)
      ORDER BY 1
    LOOP
      EXIT WHEN v_ts > v_ahora;                         -- hoy: solo hasta la hora actual

      -- 15:30 · Tanda de la tarde (35 % del plan)
      IF NOT v_tarde_hecha AND v_ts >= carga_tmp.momento(d, TIME '15:30') THEN
        v_tarde_hecha := TRUE;
        FOR r IN SELECT p2.id_producto, t.produccion_base FROM carga_tmp.comida t JOIN producto p2 USING (codigo) LOOP
          v_cant := GREATEST(1, ROUND(r.produccion_base * v_factor * 0.35 * (0.9 + random() * 0.2)));
          BEGIN
            PERFORM fn_registrar_produccion(r.id_producto, v_cant::SMALLINT, 'Tanda de la tarde', carga_tmp.momento(d, TIME '15:30'));
          EXCEPTION WHEN raise_exception THEN
            v_fallas := v_fallas + 1;
          END;
        END LOOP;
      END IF;

      v_tipo := CASE WHEN random() < 0.6 THEN 'MESA' ELSE 'PARA_LLEVAR' END;
      v_comida := '[]'::JSONB;

      -- Humintas / pastel (1 o 2 tipos distintos), elegidos según preferencia y disponibilidad
      FOR k IN 1 .. CASE WHEN random() < 0.7 THEN 1 ELSE 2 END LOOP
        SELECT p2.id_producto, p2.stock_listo INTO v_prod, v_stock
        FROM producto p2 JOIN carga_tmp.comida t USING (codigo)
        WHERE p2.stock_listo > 0
          AND NOT v_comida @> jsonb_build_array(jsonb_build_object('id_producto', p2.id_producto))
        ORDER BY -ln(1 - random()) / t.peso
        LIMIT 1;
        EXIT WHEN NOT FOUND;
        v_cant := LEAST(v_stock, CASE WHEN v_tipo = 'MESA' THEN 1 + (random() < 0.3)::INT
                                      ELSE 1 + floor(random() * 3) END);
        v_comida := v_comida || jsonb_build_object('id_producto', v_prod, 'cantidad', v_cant);
      END LOOP;

      v_items := v_comida;
      -- Bebida
      IF (v_tipo = 'MESA' AND random() < 0.75) OR (v_tipo = 'PARA_LLEVAR' AND random() < 0.2) THEN
        SELECT b.codigo INTO v_cod FROM carga_tmp.bebida b
        WHERE b.peso > 0 AND (v_tipo = 'MESA' OR NOT b.caliente)
        ORDER BY -ln(1 - random()) / b.peso LIMIT 1;
        v_items := v_items || jsonb_build_object(
          'id_producto', (SELECT id_producto FROM producto WHERE codigo = v_cod),
          'cantidad', CASE WHEN v_tipo = 'MESA' THEN 1 + (random() < 0.35)::INT ELSE 1 END);
        IF v_tipo = 'MESA' AND (SELECT caliente FROM carga_tmp.bebida WHERE codigo = v_cod) AND random() < 0.15 THEN
          v_items := v_items || jsonb_build_object('id_producto', (SELECT id_producto FROM producto WHERE codigo = 'BEB-REF'), 'cantidad', 1);
        END IF;
      END IF;
      -- Extra queso
      IF jsonb_array_length(v_comida) > 0 AND random() < 0.08 THEN
        v_items := v_items || jsonb_build_object('id_producto', (SELECT id_producto FROM producto WHERE codigo = 'EXT-QUE'), 'cantidad', 1);
      END IF;
      CONTINUE WHEN jsonb_array_length(v_items) = 0;

      -- 28 % de las ventas son de clientes registrados (algunos muy frecuentes)
      v_cliente := CASE WHEN random() < 0.28 THEN 2 + floor(40 * power(random(), 2))::INT ELSE 1 END;

      BEGIN
        v_id := fn_registrar_venta(
          v_items,
          CASE WHEN random() < 0.55 THEN v_qr ELSE v_efectivo END,
          v_tipo,
          CASE WHEN v_tipo = 'MESA' THEN (1 + floor(random() * 8))::SMALLINT END,
          v_cliente,
          CASE WHEN v_cliente > 1 AND random() < 0.05 THEN 2.00 ELSE 0 END,
          CASE WHEN v_cliente > 1 AND random() < 0.35 THEN 'FACTURA' ELSE 'NOTA_VENTA' END,
          v_ts);
        v_ventas := v_ventas + 1;
      EXCEPTION WHEN raise_exception THEN
        -- Si falta un insumo de bebida, se vende solo la comida
        IF jsonb_array_length(v_comida) > 0 THEN
          BEGIN
            v_id := fn_registrar_venta(v_comida, v_efectivo, v_tipo,
                      CASE WHEN v_tipo = 'MESA' THEN (1 + floor(random() * 8))::SMALLINT END, 1, 0, 'NOTA_VENTA', v_ts);
            v_ventas := v_ventas + 1;
          EXCEPTION WHEN raise_exception THEN
            v_fallas := v_fallas + 1;
          END;
        ELSE
          v_fallas := v_fallas + 1;
        END IF;
      END;
    END LOOP;

    CONTINUE WHEN d = v_hoy;                            -- el día de hoy sigue abierto

    -- Anulación ocasional por error de registro
    IF random() < 0.08 THEN
      SELECT id_venta, fecha_hora INTO v_id, v_ts FROM venta
      WHERE fn_fecha_local(fecha_hora) = d AND estado = 'PAGADA' ORDER BY random() LIMIT 1;
      IF FOUND THEN
        UPDATE venta SET estado = 'ANULADA', motivo_anulacion = 'Error de registro: producto equivocado'
        WHERE id_venta = v_id;
        UPDATE movimiento_inventario SET fecha_hora = v_ts + INTERVAL '3 minutes'
        WHERE id_venta = v_id AND tipo = 'REVERSION_VENTA';
      END IF;
    END IF;

    -- Queso en mal estado (deterioro, ocasional)
    IF random() < 0.04 THEN
      SELECT l.id_lote INTO v_id FROM lote l JOIN insumo i USING (id_insumo)
      WHERE i.codigo = 'INS-QUE' AND l.cantidad_disponible >= 0.5 ORDER BY l.id_lote DESC LIMIT 1;
      IF FOUND THEN
        PERFORM fn_registrar_merma('DETERIORO', 0.5, v_id, NULL, 'Queso con mal olor, se desechó', carga_tmp.momento(d, TIME '18:00'));
      END IF;
    END IF;

    -- Domingo: conteo físico de abarrotes (ajuste por diferencia)
    IF EXTRACT(ISODOW FROM d) = 7 AND random() < 0.5 THEN
      SELECT l.id_lote INTO v_id FROM lote l JOIN insumo i USING (id_insumo)
      WHERE i.codigo IN ('INS-AZU', 'INS-SAL') AND l.cantidad_disponible > 0.5 ORDER BY random() LIMIT 1;
      IF FOUND THEN
        PERFORM fn_registrar_merma('AJUSTE_CONTEO', ROUND((0.1 + random() * 0.3)::NUMERIC, 3), v_id, NULL,
                                   'Diferencia en conteo físico semanal', carga_tmp.momento(d, TIME '20:30'));
      END IF;
    END IF;

    -- 21:00 · Lo preparado que no se vendió se registra como merma
    PERFORM fn_registrar_sobrantes(carga_tmp.momento(d, TIME '21:00'));

    -- 21:15 · Cierre de caja (apertura con Bs 100 de cambio)
    SELECT COALESCE(SUM(total), 0) INTO v_tot_ef FROM venta
    WHERE estado = 'PAGADA' AND id_metodo_pago = v_efectivo AND fn_fecha_local(fecha_hora) = d;
    v_dif := CASE WHEN random() < 0.85 THEN 0 ELSE ROUND((random() * 12 - 8)::NUMERIC, 0) END;
    PERFORM fn_cierre_caja(d, 100 + v_tot_ef + v_dif, 100,
                           CASE WHEN v_dif <> 0 THEN 'Diferencia detectada en el arqueo' END);
    UPDATE cierre_caja SET creado_en = carga_tmp.momento(d, TIME '21:15') WHERE fecha = d;
  END LOOP;

  RAISE NOTICE 'Simulación terminada: % ventas registradas (% intentos rechazados por falta de stock)', v_ventas, v_fallas;
END $$;

-- Resumen de lo cargado
ALTER TABLE carga_tmp.comida ENABLE ROW LEVEL SECURITY;
ALTER TABLE carga_tmp.bebida ENABLE ROW LEVEL SECURITY;
ALTER TABLE carga_tmp.entrega ENABLE ROW LEVEL SECURITY;
ALTER TABLE carga_tmp.presentacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE carga_tmp.consumo ENABLE ROW LEVEL SECURITY;
DROP SCHEMA carga_tmp CASCADE;

SELECT 'usuario' AS tabla, COUNT(*) AS filas FROM usuario
UNION ALL SELECT 'producto', COUNT(*) FROM producto
UNION ALL SELECT 'insumo', COUNT(*) FROM insumo
UNION ALL SELECT 'receta', COUNT(*) FROM receta
UNION ALL SELECT 'proveedor', COUNT(*) FROM proveedor
UNION ALL SELECT 'cliente', COUNT(*) FROM cliente
UNION ALL SELECT 'compra', COUNT(*) FROM compra
UNION ALL SELECT 'lote', COUNT(*) FROM lote
UNION ALL SELECT 'produccion', COUNT(*) FROM produccion
UNION ALL SELECT 'venta', COUNT(*) FROM venta
UNION ALL SELECT 'detalle_venta', COUNT(*) FROM detalle_venta
UNION ALL SELECT 'merma', COUNT(*) FROM merma
UNION ALL SELECT 'movimiento_inventario', COUNT(*) FROM movimiento_inventario
UNION ALL SELECT 'historial_precio', COUNT(*) FROM historial_precio
UNION ALL SELECT 'cierre_caja', COUNT(*) FROM cierre_caja;
