-- =====================================================================
--  ANIS · LA CASA DE LA HUMINTA
--  Sistema de control de ventas e inventario
--  Script 01 · Esquema completo (tablas, restricciones, funciones,
--              procedimientos almacenados, disparadores y vistas)
--  Gestor: PostgreSQL 15+ (Supabase)
--  Materia: Base de Datos II · UPDS
-- ---------------------------------------------------------------------
--  Orden de ejecución:
--    01_esquema.sql  ->  02_datos_prueba.sql  ->  03_consultas.sql
--    04_indices_y_transacciones.sql  ->  05_supabase_seguridad.sql
--  El script se puede ejecutar varias veces: borra y vuelve a crear
--  todos los objetos del sistema (implementación "desde cero").
-- =====================================================================

SET client_min_messages = warning;

-- ---------------------------------------------------------------------
-- 0. LIMPIEZA (permite reejecutar el script desde cero)
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS firma, p.prokind
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname ~ '^(fn_|sp_|tg_)'
  LOOP
    EXECUTE format('DROP %s IF EXISTS %s CASCADE',
                   CASE r.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END,
                   r.firma);
  END LOOP;
END $$;

DROP TABLE IF EXISTS
  cierre_caja, historial_precio, movimiento_inventario, merma, produccion,
  detalle_venta, venta, metodo_pago, cliente, lote, compra,
  proveedor_insumo, proveedor, receta, insumo, categoria_insumo,
  unidad_medida, producto, categoria_producto, usuario
CASCADE;

-- =====================================================================
-- 1. TABLAS
-- =====================================================================

-- 1.1 Usuario del sistema (la administradora es la única usuaria)
CREATE TABLE usuario (
  id_usuario       SMALLINT     GENERATED ALWAYS AS IDENTITY,
  nombre_completo  VARCHAR(100) NOT NULL,
  email            VARCHAR(120) NOT NULL,
  rol              VARCHAR(20)  NOT NULL DEFAULT 'ADMINISTRADOR',
  auth_uid         UUID,
  activo           BOOLEAN      NOT NULL DEFAULT TRUE,
  creado_en        TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT pk_usuario          PRIMARY KEY (id_usuario),
  CONSTRAINT uq_usuario_email    UNIQUE (email),
  CONSTRAINT uq_usuario_auth     UNIQUE (auth_uid),
  CONSTRAINT ck_usuario_rol      CHECK (rol IN ('ADMINISTRADOR')),
  CONSTRAINT ck_usuario_email    CHECK (email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
);
COMMENT ON TABLE usuario IS 'Personas que operan el sistema. Hoy solo la administradora registra ventas e inventario.';

-- 1.2 Categoría de producto del menú
CREATE TABLE categoria_producto (
  id_categoria_producto SMALLINT    GENERATED ALWAYS AS IDENTITY,
  nombre                VARCHAR(40) NOT NULL,
  descripcion           VARCHAR(150),
  CONSTRAINT pk_categoria_producto        PRIMARY KEY (id_categoria_producto),
  CONSTRAINT uq_categoria_producto_nombre UNIQUE (nombre)
);

-- 1.3 Producto del menú (especialización por tipo: ELABORADO / AL_MOMENTO / REVENTA)
CREATE TABLE producto (
  id_producto            INTEGER       GENERATED ALWAYS AS IDENTITY,
  id_categoria_producto  SMALLINT      NOT NULL,
  codigo                 VARCHAR(10)   NOT NULL,
  nombre                 VARCHAR(80)   NOT NULL,
  tipo                   VARCHAR(12)   NOT NULL,
  precio_venta           NUMERIC(10,2) NOT NULL,
  stock_listo            INTEGER       NOT NULL DEFAULT 0,
  activo                 BOOLEAN       NOT NULL DEFAULT TRUE,
  creado_en              TIMESTAMPTZ   NOT NULL DEFAULT now(),
  CONSTRAINT pk_producto           PRIMARY KEY (id_producto),
  CONSTRAINT fk_producto_categoria FOREIGN KEY (id_categoria_producto)
             REFERENCES categoria_producto (id_categoria_producto) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT uq_producto_codigo    UNIQUE (codigo),
  CONSTRAINT uq_producto_nombre    UNIQUE (nombre),
  CONSTRAINT ck_producto_tipo      CHECK (tipo IN ('ELABORADO','AL_MOMENTO','REVENTA')),
  CONSTRAINT ck_producto_precio    CHECK (precio_venta > 0),
  CONSTRAINT ck_producto_stock     CHECK (stock_listo >= 0),
  CONSTRAINT ck_producto_stock_tipo CHECK (tipo = 'ELABORADO' OR stock_listo = 0)
);
COMMENT ON COLUMN producto.tipo IS 'ELABORADO: se produce por tandas (humintas, pastel). AL_MOMENTO: se prepara al pedir (café, té). REVENTA: se vende tal cual (gaseosas, jugos).';
COMMENT ON COLUMN producto.stock_listo IS 'Unidades ya preparadas disponibles para la venta (solo productos ELABORADOS).';

-- 1.4 Unidad de medida
CREATE TABLE unidad_medida (
  id_unidad_medida SMALLINT    GENERATED ALWAYS AS IDENTITY,
  codigo           VARCHAR(5)  NOT NULL,
  nombre           VARCHAR(30) NOT NULL,
  CONSTRAINT pk_unidad_medida        PRIMARY KEY (id_unidad_medida),
  CONSTRAINT uq_unidad_medida_codigo UNIQUE (codigo),
  CONSTRAINT uq_unidad_medida_nombre UNIQUE (nombre)
);

-- 1.5 Categoría de insumo
CREATE TABLE categoria_insumo (
  id_categoria_insumo SMALLINT    GENERATED ALWAYS AS IDENTITY,
  nombre              VARCHAR(40) NOT NULL,
  descripcion         VARCHAR(150),
  CONSTRAINT pk_categoria_insumo        PRIMARY KEY (id_categoria_insumo),
  CONSTRAINT uq_categoria_insumo_nombre UNIQUE (nombre)
);

-- 1.6 Insumo (materia prima, bebidas de reventa y empaques)
CREATE TABLE insumo (
  id_insumo               INTEGER       GENERATED ALWAYS AS IDENTITY,
  id_categoria_insumo     SMALLINT      NOT NULL,
  id_unidad_medida        SMALLINT      NOT NULL,
  codigo                  VARCHAR(10)   NOT NULL,
  nombre                  VARCHAR(80)   NOT NULL,
  stock_minimo            NUMERIC(12,3) NOT NULL DEFAULT 0,
  es_perecedero           BOOLEAN       NOT NULL DEFAULT TRUE,
  vida_util_dias          SMALLINT,
  dias_alerta_vencimiento SMALLINT      NOT NULL DEFAULT 2,
  activo                  BOOLEAN       NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_insumo            PRIMARY KEY (id_insumo),
  CONSTRAINT fk_insumo_categoria  FOREIGN KEY (id_categoria_insumo)
             REFERENCES categoria_insumo (id_categoria_insumo) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_insumo_unidad     FOREIGN KEY (id_unidad_medida)
             REFERENCES unidad_medida (id_unidad_medida) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT uq_insumo_codigo     UNIQUE (codigo),
  CONSTRAINT uq_insumo_nombre     UNIQUE (nombre),
  CONSTRAINT ck_insumo_stock_min  CHECK (stock_minimo >= 0),
  CONSTRAINT ck_insumo_vida_util  CHECK (vida_util_dias IS NULL OR vida_util_dias > 0),
  CONSTRAINT ck_insumo_perecedero CHECK (NOT es_perecedero OR vida_util_dias IS NOT NULL),
  CONSTRAINT ck_insumo_alerta     CHECK (dias_alerta_vencimiento >= 0)
);

-- 1.7 Receta: cantidad de cada insumo para 1 unidad de producto (N:M)
CREATE TABLE receta (
  id_producto INTEGER       NOT NULL,
  id_insumo   INTEGER       NOT NULL,
  cantidad    NUMERIC(12,4) NOT NULL,
  CONSTRAINT pk_receta          PRIMARY KEY (id_producto, id_insumo),
  CONSTRAINT fk_receta_producto FOREIGN KEY (id_producto) REFERENCES producto (id_producto) ON DELETE CASCADE,
  CONSTRAINT fk_receta_insumo   FOREIGN KEY (id_insumo)   REFERENCES insumo (id_insumo)     ON DELETE RESTRICT,
  CONSTRAINT ck_receta_cantidad CHECK (cantidad > 0)
);

-- 1.8 Proveedor (todos entregan la mercadería en el local)
CREATE TABLE proveedor (
  id_proveedor    INTEGER      GENERATED ALWAYS AS IDENTITY,
  razon_social    VARCHAR(100) NOT NULL,
  nit             VARCHAR(20),
  nombre_contacto VARCHAR(80),
  telefono        VARCHAR(15)  NOT NULL,
  direccion       VARCHAR(150),
  dias_entrega    VARCHAR(60),
  activo          BOOLEAN      NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_proveedor          PRIMARY KEY (id_proveedor),
  CONSTRAINT uq_proveedor_razon    UNIQUE (razon_social),
  CONSTRAINT uq_proveedor_nit      UNIQUE (nit),
  CONSTRAINT ck_proveedor_telefono CHECK (telefono ~ '^[0-9+ ]{7,15}$')
);

-- 1.9 Qué insumo entrega cada proveedor (N:M) y a qué precio de referencia
CREATE TABLE proveedor_insumo (
  id_proveedor      INTEGER       NOT NULL,
  id_insumo         INTEGER       NOT NULL,
  precio_referencia NUMERIC(10,2) NOT NULL,
  es_principal      BOOLEAN       NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_proveedor_insumo  PRIMARY KEY (id_proveedor, id_insumo),
  CONSTRAINT fk_prov_ins_prov     FOREIGN KEY (id_proveedor) REFERENCES proveedor (id_proveedor) ON DELETE CASCADE,
  CONSTRAINT fk_prov_ins_insumo   FOREIGN KEY (id_insumo)    REFERENCES insumo (id_insumo)       ON DELETE CASCADE,
  CONSTRAINT ck_prov_ins_precio   CHECK (precio_referencia >= 0)
);
-- Regla de negocio: un solo proveedor principal por insumo
CREATE UNIQUE INDEX ux_proveedor_insumo_principal ON proveedor_insumo (id_insumo) WHERE es_principal;

-- 1.10 Compra = recepción de mercadería entregada por el proveedor
CREATE TABLE compra (
  id_compra       INTEGER       GENERATED ALWAYS AS IDENTITY,
  id_proveedor    INTEGER       NOT NULL,
  id_usuario      SMALLINT      NOT NULL,
  fecha_recepcion TIMESTAMPTZ   NOT NULL DEFAULT now(),
  tipo_documento  VARCHAR(15)   NOT NULL DEFAULT 'NOTA_REMISION',
  nro_documento   VARCHAR(20),
  total           NUMERIC(12,2) NOT NULL DEFAULT 0,
  estado_pago     VARCHAR(10)   NOT NULL DEFAULT 'PAGADO',
  observacion     VARCHAR(200),
  CONSTRAINT pk_compra            PRIMARY KEY (id_compra),
  CONSTRAINT fk_compra_proveedor  FOREIGN KEY (id_proveedor) REFERENCES proveedor (id_proveedor) ON DELETE RESTRICT,
  CONSTRAINT fk_compra_usuario    FOREIGN KEY (id_usuario)   REFERENCES usuario (id_usuario)     ON DELETE RESTRICT,
  CONSTRAINT uq_compra_documento  UNIQUE (id_proveedor, tipo_documento, nro_documento),
  CONSTRAINT ck_compra_tipo_doc   CHECK (tipo_documento IN ('FACTURA','NOTA_REMISION','RECIBO','SIN_DOCUMENTO')),
  CONSTRAINT ck_compra_total      CHECK (total >= 0),
  CONSTRAINT ck_compra_estado     CHECK (estado_pago IN ('PAGADO','PENDIENTE'))
);

-- 1.11 Lote = cada línea (detalle) de una compra. Controla cantidad disponible y vencimiento.
CREATE TABLE lote (
  id_lote             INTEGER       GENERATED ALWAYS AS IDENTITY,
  id_compra           INTEGER       NOT NULL,
  id_insumo           INTEGER       NOT NULL,
  cantidad_recibida   NUMERIC(12,3) NOT NULL,
  costo_unitario      NUMERIC(10,4) NOT NULL,
  fecha_vencimiento   DATE,
  cantidad_disponible NUMERIC(12,3) NOT NULL DEFAULT 0,
  subtotal            NUMERIC(12,2) GENERATED ALWAYS AS (round(cantidad_recibida * costo_unitario, 2)) STORED,
  CONSTRAINT pk_lote              PRIMARY KEY (id_lote),
  CONSTRAINT fk_lote_compra       FOREIGN KEY (id_compra) REFERENCES compra (id_compra) ON DELETE CASCADE,
  CONSTRAINT fk_lote_insumo       FOREIGN KEY (id_insumo) REFERENCES insumo (id_insumo) ON DELETE RESTRICT,
  CONSTRAINT uq_lote_compra_insumo UNIQUE (id_compra, id_insumo),
  CONSTRAINT ck_lote_cantidad     CHECK (cantidad_recibida > 0),
  CONSTRAINT ck_lote_costo        CHECK (costo_unitario >= 0),
  CONSTRAINT ck_lote_disponible   CHECK (cantidad_disponible >= 0 AND cantidad_disponible <= cantidad_recibida)
);
COMMENT ON TABLE lote IS 'Detalle de compra. Cada insumo recibido forma un lote con su fecha de vencimiento; las salidas se descuentan por FEFO (primero en vencer, primero en salir).';

-- 1.12 Cliente (opcional; por defecto "CLIENTE GENERAL")
CREATE TABLE cliente (
  id_cliente     INTEGER      GENERATED ALWAYS AS IDENTITY,
  nombre         VARCHAR(100) NOT NULL,
  ci_nit         VARCHAR(20),
  telefono       VARCHAR(15),
  email          VARCHAR(120),
  fecha_registro DATE         NOT NULL DEFAULT current_date,
  activo         BOOLEAN      NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_cliente          PRIMARY KEY (id_cliente),
  CONSTRAINT uq_cliente_ci_nit   UNIQUE (ci_nit),
  CONSTRAINT ck_cliente_telefono CHECK (telefono IS NULL OR telefono ~ '^[0-9+ ]{7,15}$'),
  CONSTRAINT ck_cliente_email    CHECK (email IS NULL OR email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')
);

-- 1.13 Método de pago (efectivo, QR)
CREATE TABLE metodo_pago (
  id_metodo_pago SMALLINT    GENERATED ALWAYS AS IDENTITY,
  nombre         VARCHAR(20) NOT NULL,
  activo         BOOLEAN     NOT NULL DEFAULT TRUE,
  CONSTRAINT pk_metodo_pago        PRIMARY KEY (id_metodo_pago),
  CONSTRAINT uq_metodo_pago_nombre UNIQUE (nombre)
);

-- 1.14 Venta (cabecera)
CREATE TABLE venta (
  id_venta         INTEGER       GENERATED ALWAYS AS IDENTITY,
  id_cliente       INTEGER       NOT NULL DEFAULT 1,
  id_usuario       SMALLINT      NOT NULL,
  id_metodo_pago   SMALLINT      NOT NULL,
  fecha_hora       TIMESTAMPTZ   NOT NULL DEFAULT now(),
  tipo_pedido      VARCHAR(12)   NOT NULL DEFAULT 'MESA',
  nro_mesa         SMALLINT,
  tipo_comprobante VARCHAR(10)   NOT NULL DEFAULT 'NOTA_VENTA',
  descuento        NUMERIC(10,2) NOT NULL DEFAULT 0,
  total            NUMERIC(12,2) NOT NULL DEFAULT 0,
  estado           VARCHAR(10)   NOT NULL DEFAULT 'PAGADA',
  motivo_anulacion VARCHAR(150),
  CONSTRAINT pk_venta              PRIMARY KEY (id_venta),
  CONSTRAINT fk_venta_cliente      FOREIGN KEY (id_cliente)     REFERENCES cliente (id_cliente)         ON DELETE RESTRICT,
  CONSTRAINT fk_venta_usuario      FOREIGN KEY (id_usuario)     REFERENCES usuario (id_usuario)         ON DELETE RESTRICT,
  CONSTRAINT fk_venta_metodo_pago  FOREIGN KEY (id_metodo_pago) REFERENCES metodo_pago (id_metodo_pago) ON DELETE RESTRICT,
  CONSTRAINT ck_venta_tipo_pedido  CHECK (tipo_pedido IN ('MESA','PARA_LLEVAR')),
  CONSTRAINT ck_venta_mesa         CHECK ((tipo_pedido = 'MESA' AND nro_mesa BETWEEN 1 AND 20)
                                       OR (tipo_pedido = 'PARA_LLEVAR' AND nro_mesa IS NULL)),
  CONSTRAINT ck_venta_comprobante  CHECK (tipo_comprobante IN ('NOTA_VENTA','FACTURA')),
  CONSTRAINT ck_venta_descuento    CHECK (descuento >= 0),
  CONSTRAINT ck_venta_total        CHECK (total >= 0),
  CONSTRAINT ck_venta_estado       CHECK (estado IN ('PAGADA','ANULADA')),
  CONSTRAINT ck_venta_anulacion    CHECK (estado <> 'ANULADA' OR motivo_anulacion IS NOT NULL)
);

-- 1.15 Detalle de venta
CREATE TABLE detalle_venta (
  id_detalle_venta INTEGER       GENERATED ALWAYS AS IDENTITY,
  id_venta         INTEGER       NOT NULL,
  id_producto      INTEGER       NOT NULL,
  cantidad         SMALLINT      NOT NULL,
  precio_unitario  NUMERIC(10,2) NOT NULL,
  costo_unitario   NUMERIC(10,4) NOT NULL DEFAULT 0,
  subtotal         NUMERIC(12,2) GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
  CONSTRAINT pk_detalle_venta          PRIMARY KEY (id_detalle_venta),
  CONSTRAINT fk_detalle_venta_venta    FOREIGN KEY (id_venta)    REFERENCES venta (id_venta)       ON DELETE CASCADE,
  CONSTRAINT fk_detalle_venta_producto FOREIGN KEY (id_producto) REFERENCES producto (id_producto) ON DELETE RESTRICT,
  CONSTRAINT uq_detalle_venta_producto UNIQUE (id_venta, id_producto),
  CONSTRAINT ck_detalle_venta_cantidad CHECK (cantidad > 0),
  CONSTRAINT ck_detalle_venta_precio   CHECK (precio_unitario > 0),
  CONSTRAINT ck_detalle_venta_costo    CHECK (costo_unitario >= 0)
);
COMMENT ON COLUMN detalle_venta.costo_unitario IS 'Costo de insumos al momento de la venta (para calcular rentabilidad real).';

-- 1.16 Producción diaria por tandas (solo productos ELABORADOS)
CREATE TABLE produccion (
  id_produccion INTEGER       GENERATED ALWAYS AS IDENTITY,
  id_producto   INTEGER       NOT NULL,
  id_usuario    SMALLINT      NOT NULL,
  fecha_hora    TIMESTAMPTZ   NOT NULL DEFAULT now(),
  cantidad      SMALLINT      NOT NULL,
  costo_total   NUMERIC(12,2) NOT NULL DEFAULT 0,
  observacion   VARCHAR(200),
  CONSTRAINT pk_produccion          PRIMARY KEY (id_produccion),
  CONSTRAINT fk_produccion_producto FOREIGN KEY (id_producto) REFERENCES producto (id_producto) ON DELETE RESTRICT,
  CONSTRAINT fk_produccion_usuario  FOREIGN KEY (id_usuario)  REFERENCES usuario (id_usuario)   ON DELETE RESTRICT,
  CONSTRAINT ck_produccion_cantidad CHECK (cantidad > 0),
  CONSTRAINT ck_produccion_costo    CHECK (costo_total >= 0)
);

-- 1.17 Merma (desperdicio). Especialización disjunta: de insumo (lote) o de producto preparado
CREATE TABLE merma (
  id_merma       INTEGER       GENERATED ALWAYS AS IDENTITY,
  id_usuario     SMALLINT      NOT NULL,
  fecha_hora     TIMESTAMPTZ   NOT NULL DEFAULT now(),
  id_lote        INTEGER,
  id_producto    INTEGER,
  cantidad       NUMERIC(12,3) NOT NULL,
  motivo         VARCHAR(20)   NOT NULL,
  costo_estimado NUMERIC(12,2) NOT NULL DEFAULT 0,
  observacion    VARCHAR(200),
  CONSTRAINT pk_merma           PRIMARY KEY (id_merma),
  CONSTRAINT fk_merma_usuario   FOREIGN KEY (id_usuario)  REFERENCES usuario (id_usuario)   ON DELETE RESTRICT,
  CONSTRAINT fk_merma_lote      FOREIGN KEY (id_lote)     REFERENCES lote (id_lote)         ON DELETE RESTRICT,
  CONSTRAINT fk_merma_producto  FOREIGN KEY (id_producto) REFERENCES producto (id_producto) ON DELETE RESTRICT,
  CONSTRAINT ck_merma_origen    CHECK (num_nonnulls(id_lote, id_producto) = 1),
  CONSTRAINT ck_merma_cantidad  CHECK (cantidad > 0),
  CONSTRAINT ck_merma_motivo    CHECK (motivo IN ('VENCIMIENTO','DETERIORO','SOBRANTE_DIA','ERROR_PREPARACION','AJUSTE_CONTEO')),
  CONSTRAINT ck_merma_costo     CHECK (costo_estimado >= 0)
);

-- 1.18 Kárdex: todo movimiento de inventario por lote (+ entrada / - salida)
CREATE TABLE movimiento_inventario (
  id_movimiento BIGINT        GENERATED ALWAYS AS IDENTITY,
  id_lote       INTEGER       NOT NULL,
  tipo          VARCHAR(20)   NOT NULL,
  cantidad      NUMERIC(12,3) NOT NULL,
  fecha_hora    TIMESTAMPTZ   NOT NULL DEFAULT now(),
  id_usuario    SMALLINT      NOT NULL,
  id_venta      INTEGER,
  id_produccion INTEGER,
  id_merma      INTEGER,
  CONSTRAINT pk_movimiento_inventario PRIMARY KEY (id_movimiento),
  CONSTRAINT fk_mov_lote       FOREIGN KEY (id_lote)       REFERENCES lote (id_lote)             ON DELETE CASCADE,
  CONSTRAINT fk_mov_usuario    FOREIGN KEY (id_usuario)    REFERENCES usuario (id_usuario)       ON DELETE RESTRICT,
  CONSTRAINT fk_mov_venta      FOREIGN KEY (id_venta)      REFERENCES venta (id_venta)           ON DELETE CASCADE,
  CONSTRAINT fk_mov_produccion FOREIGN KEY (id_produccion) REFERENCES produccion (id_produccion) ON DELETE CASCADE,
  CONSTRAINT fk_mov_merma      FOREIGN KEY (id_merma)      REFERENCES merma (id_merma)           ON DELETE CASCADE,
  CONSTRAINT ck_mov_tipo       CHECK (tipo IN ('ENTRADA_COMPRA','SALIDA_VENTA','SALIDA_PRODUCCION','SALIDA_MERMA','REVERSION_VENTA')),
  CONSTRAINT ck_mov_cantidad   CHECK (cantidad <> 0),
  CONSTRAINT ck_mov_signo      CHECK ((tipo IN ('ENTRADA_COMPRA','REVERSION_VENTA')) = (cantidad > 0)),
  CONSTRAINT ck_mov_referencia CHECK (num_nonnulls(id_venta, id_produccion, id_merma) <= 1)
);

-- 1.19 Historial de precios de venta (auditoría)
CREATE TABLE historial_precio (
  id_historial_precio INTEGER       GENERATED ALWAYS AS IDENTITY,
  id_producto         INTEGER       NOT NULL,
  precio_anterior     NUMERIC(10,2) NOT NULL,
  precio_nuevo        NUMERIC(10,2) NOT NULL,
  fecha_cambio        TIMESTAMPTZ   NOT NULL DEFAULT now(),
  id_usuario          SMALLINT      NOT NULL,
  CONSTRAINT pk_historial_precio PRIMARY KEY (id_historial_precio),
  CONSTRAINT fk_hist_producto    FOREIGN KEY (id_producto) REFERENCES producto (id_producto) ON DELETE CASCADE,
  CONSTRAINT fk_hist_usuario     FOREIGN KEY (id_usuario)  REFERENCES usuario (id_usuario)   ON DELETE RESTRICT,
  CONSTRAINT ck_hist_precios     CHECK (precio_anterior > 0 AND precio_nuevo > 0 AND precio_anterior <> precio_nuevo)
);

-- 1.20 Cierre de caja diario
CREATE TABLE cierre_caja (
  id_cierre_caja   INTEGER       GENERATED ALWAYS AS IDENTITY,
  fecha            DATE          NOT NULL,
  id_usuario       SMALLINT      NOT NULL,
  monto_apertura   NUMERIC(10,2) NOT NULL DEFAULT 0,
  cantidad_ventas  INTEGER       NOT NULL DEFAULT 0,
  total_efectivo   NUMERIC(12,2) NOT NULL DEFAULT 0,
  total_qr         NUMERIC(12,2) NOT NULL DEFAULT 0,
  efectivo_contado NUMERIC(12,2) NOT NULL,
  diferencia       NUMERIC(12,2) GENERATED ALWAYS AS (efectivo_contado - (monto_apertura + total_efectivo)) STORED,
  observacion      VARCHAR(200),
  creado_en        TIMESTAMPTZ   NOT NULL DEFAULT now(),
  CONSTRAINT pk_cierre_caja       PRIMARY KEY (id_cierre_caja),
  CONSTRAINT fk_cierre_usuario    FOREIGN KEY (id_usuario) REFERENCES usuario (id_usuario) ON DELETE RESTRICT,
  CONSTRAINT uq_cierre_fecha      UNIQUE (fecha),
  CONSTRAINT ck_cierre_montos     CHECK (monto_apertura >= 0 AND total_efectivo >= 0 AND total_qr >= 0 AND efectivo_contado >= 0),
  CONSTRAINT ck_cierre_cantidad   CHECK (cantidad_ventas >= 0)
);

-- =====================================================================
-- 2. FUNCIONES DE APOYO
-- =====================================================================

-- 2.1 Fecha local de Bolivia (inmutable: sirve para índices por día)
CREATE FUNCTION fn_fecha_local(p_momento TIMESTAMPTZ)
RETURNS DATE LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT (p_momento AT TIME ZONE 'America/La_Paz')::date
$$;

-- 2.2 Usuario que opera (Supabase: por el email del JWT; si no, la administradora)
CREATE FUNCTION fn_usuario_actual()
RETURNS SMALLINT LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_claims JSONB;
  v_id     SMALLINT;
BEGIN
  v_claims := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  IF v_claims IS NOT NULL THEN
    SELECT id_usuario INTO v_id
    FROM usuario
    WHERE activo
      AND (auth_uid::text = v_claims ->> 'sub' OR lower(email) = lower(v_claims ->> 'email'))
    LIMIT 1;
  END IF;
  IF v_id IS NULL THEN
    SELECT id_usuario INTO v_id FROM usuario
    WHERE activo AND rol = 'ADMINISTRADOR' ORDER BY id_usuario LIMIT 1;
  END IF;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'No existe un usuario administrador activo';
  END IF;
  RETURN v_id;
END $$;

-- 2.3 Stock utilizable (no vencido) de un insumo a una fecha
CREATE FUNCTION fn_stock_insumo(p_id_insumo INTEGER, p_fecha DATE DEFAULT NULL)
RETURNS NUMERIC LANGUAGE sql STABLE AS $$
  SELECT COALESCE(SUM(l.cantidad_disponible), 0)
  FROM lote l
  WHERE l.id_insumo = p_id_insumo
    AND l.cantidad_disponible > 0
    AND (l.fecha_vencimiento IS NULL
         OR l.fecha_vencimiento >= COALESCE(p_fecha, fn_fecha_local(now())))
$$;

-- 2.4 Costo promedio ponderado de un insumo (lotes con saldo; si no hay, último costo; si no, precio de referencia)
CREATE FUNCTION fn_costo_promedio_insumo(p_id_insumo INTEGER)
RETURNS NUMERIC LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    (SELECT SUM(cantidad_disponible * costo_unitario) / NULLIF(SUM(cantidad_disponible), 0)
       FROM lote WHERE id_insumo = p_id_insumo AND cantidad_disponible > 0),
    (SELECT l.costo_unitario FROM lote l JOIN compra c USING (id_compra)
       WHERE l.id_insumo = p_id_insumo ORDER BY c.fecha_recepcion DESC, l.id_lote DESC LIMIT 1),
    (SELECT precio_referencia FROM proveedor_insumo
       WHERE id_insumo = p_id_insumo ORDER BY es_principal DESC LIMIT 1),
    0)
$$;

-- 2.5 Costo de receta de un producto (costo de insumos de 1 unidad)
CREATE FUNCTION fn_costo_receta(p_id_producto INTEGER)
RETURNS NUMERIC LANGUAGE sql STABLE AS $$
  SELECT COALESCE(ROUND(SUM(r.cantidad * fn_costo_promedio_insumo(r.id_insumo)), 4), 0)
  FROM receta r WHERE r.id_producto = p_id_producto
$$;

-- 2.6 Descuenta un insumo por FEFO (primero en vencer, primero en salir)
--     Registra el kárdex y devuelve el costo total consumido.
CREATE FUNCTION fn_consumir_insumo(
  p_id_insumo     INTEGER,
  p_cantidad      NUMERIC,
  p_fecha         TIMESTAMPTZ,
  p_tipo          VARCHAR,
  p_id_usuario    SMALLINT,
  p_id_venta      INTEGER DEFAULT NULL,
  p_id_produccion INTEGER DEFAULT NULL)
RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE
  v_dia        DATE    := fn_fecha_local(p_fecha);
  v_pendiente  NUMERIC := p_cantidad;
  v_costo      NUMERIC := 0;
  v_tomar      NUMERIC;
  r            RECORD;
BEGIN
  IF p_cantidad IS NULL OR p_cantidad <= 0 THEN
    RETURN 0;
  END IF;

  FOR r IN
    SELECT id_lote, cantidad_disponible, costo_unitario
    FROM lote
    WHERE id_insumo = p_id_insumo
      AND cantidad_disponible > 0
      AND (fecha_vencimiento IS NULL OR fecha_vencimiento >= v_dia)
    ORDER BY fecha_vencimiento NULLS LAST, id_lote
    FOR UPDATE
  LOOP
    v_tomar := LEAST(r.cantidad_disponible, v_pendiente);

    UPDATE lote SET cantidad_disponible = cantidad_disponible - v_tomar
    WHERE id_lote = r.id_lote;

    INSERT INTO movimiento_inventario (id_lote, tipo, cantidad, fecha_hora, id_usuario, id_venta, id_produccion)
    VALUES (r.id_lote, p_tipo, -v_tomar, p_fecha, p_id_usuario, p_id_venta, p_id_produccion);

    v_costo     := v_costo + v_tomar * r.costo_unitario;
    v_pendiente := v_pendiente - v_tomar;
    EXIT WHEN v_pendiente <= 0;
  END LOOP;

  -- Si no alcanzó, se cancela todo (la excepción deshace los descuentos ya hechos)
  IF v_pendiente > 0 THEN
    RAISE EXCEPTION 'Stock insuficiente de "%": disponible %, requerido %',
      (SELECT nombre FROM insumo WHERE id_insumo = p_id_insumo),
      round(p_cantidad - v_pendiente, 3), round(p_cantidad, 3)
      USING ERRCODE = 'P0001', HINT = 'Registre la entrega del proveedor antes de vender o producir.';
  END IF;

  RETURN v_costo;
END $$;

-- =====================================================================
-- 3. DISPARADORES (TRIGGERS)
-- =====================================================================

-- 3.1 Lote: completa vencimiento y cantidad disponible al recibir
CREATE FUNCTION tg_lote_antes_insertar()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_perecedero BOOLEAN;
  v_vida       SMALLINT;
  v_recepcion  DATE;
BEGIN
  SELECT es_perecedero, vida_util_dias INTO v_perecedero, v_vida
  FROM insumo WHERE id_insumo = NEW.id_insumo AND activo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'El insumo % no existe o está inactivo', NEW.id_insumo;
  END IF;

  SELECT fn_fecha_local(fecha_recepcion) INTO v_recepcion FROM compra WHERE id_compra = NEW.id_compra;

  IF NEW.fecha_vencimiento IS NULL AND v_perecedero THEN
    NEW.fecha_vencimiento := v_recepcion + v_vida;
  END IF;
  IF NEW.fecha_vencimiento IS NOT NULL AND NEW.fecha_vencimiento < v_recepcion THEN
    RAISE EXCEPTION 'No se puede recibir un lote ya vencido (vence %, recibido %)', NEW.fecha_vencimiento, v_recepcion;
  END IF;

  NEW.cantidad_disponible := NEW.cantidad_recibida;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_lote_antes_insertar
BEFORE INSERT ON lote
FOR EACH ROW EXECUTE FUNCTION tg_lote_antes_insertar();

-- 3.2 Lote: registra la entrada en kárdex y actualiza el total de la compra
CREATE FUNCTION tg_lote_despues_insertar()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_compra compra%ROWTYPE;
BEGIN
  SELECT * INTO v_compra FROM compra WHERE id_compra = NEW.id_compra;

  INSERT INTO movimiento_inventario (id_lote, tipo, cantidad, fecha_hora, id_usuario)
  VALUES (NEW.id_lote, 'ENTRADA_COMPRA', NEW.cantidad_recibida, v_compra.fecha_recepcion, v_compra.id_usuario);

  UPDATE compra SET total = total + NEW.subtotal WHERE id_compra = NEW.id_compra;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_lote_despues_insertar
AFTER INSERT ON lote
FOR EACH ROW EXECUTE FUNCTION tg_lote_despues_insertar();

-- 3.3 Venta: valida la cabecera (factura exige CI/NIT del cliente)
CREATE FUNCTION tg_venta_antes_insertar()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.tipo_comprobante = 'FACTURA'
     AND (SELECT ci_nit FROM cliente WHERE id_cliente = NEW.id_cliente) IS NULL THEN
    RAISE EXCEPTION 'Para emitir factura el cliente debe tener CI/NIT registrado';
  END IF;
  NEW.total := 0;   -- el total se calcula a partir del detalle
  RETURN NEW;
END $$;

CREATE TRIGGER trg_venta_antes_insertar
BEFORE INSERT ON venta
FOR EACH ROW EXECUTE FUNCTION tg_venta_antes_insertar();

-- 3.4 Detalle de venta: valida, descuenta inventario y guarda el costo
CREATE FUNCTION tg_detalle_venta_antes_insertar()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_venta    venta%ROWTYPE;
  v_producto producto%ROWTYPE;
  v_costo    NUMERIC := 0;
  r          RECORD;
BEGIN
  SELECT * INTO v_venta FROM venta WHERE id_venta = NEW.id_venta;
  IF v_venta.estado <> 'PAGADA' THEN
    RAISE EXCEPTION 'No se puede agregar productos a una venta anulada';
  END IF;

  SELECT * INTO v_producto FROM producto WHERE id_producto = NEW.id_producto FOR UPDATE;
  IF NOT FOUND OR NOT v_producto.activo THEN
    RAISE EXCEPTION 'El producto % no existe o no está a la venta', NEW.id_producto;
  END IF;

  NEW.precio_unitario := COALESCE(NEW.precio_unitario, v_producto.precio_venta);

  IF v_producto.tipo = 'ELABORADO' THEN
    -- Se vende de lo ya producido en el día
    IF v_producto.stock_listo < NEW.cantidad THEN
      RAISE EXCEPTION 'Solo quedan % unidad(es) de "%"', v_producto.stock_listo, v_producto.nombre
        USING ERRCODE = 'P0001', HINT = 'Registre una nueva tanda de producción.';
    END IF;
    UPDATE producto SET stock_listo = stock_listo - NEW.cantidad WHERE id_producto = NEW.id_producto;
    -- costo = costo unitario de la última tanda producida (o receta)
    SELECT COALESCE(
             (SELECT costo_total / cantidad FROM produccion
               WHERE id_producto = NEW.id_producto
               ORDER BY fecha_hora DESC, id_produccion DESC LIMIT 1),
             fn_costo_receta(NEW.id_producto))
      INTO v_costo;
    NEW.costo_unitario := round(v_costo, 4);
  ELSE
    -- Se prepara al momento o es reventa: descuenta los insumos de la receta
    FOR r IN SELECT id_insumo, cantidad FROM receta WHERE id_producto = NEW.id_producto LOOP
      v_costo := v_costo + fn_consumir_insumo(r.id_insumo, r.cantidad * NEW.cantidad,
                                              v_venta.fecha_hora, 'SALIDA_VENTA',
                                              v_venta.id_usuario, NEW.id_venta, NULL);
    END LOOP;
    NEW.costo_unitario := round(v_costo / NEW.cantidad, 4);
  END IF;

  RETURN NEW;
END $$;

CREATE TRIGGER trg_detalle_venta_antes_insertar
BEFORE INSERT ON detalle_venta
FOR EACH ROW EXECUTE FUNCTION tg_detalle_venta_antes_insertar();

-- 3.5 Detalle de venta: recalcula el total de la venta
CREATE FUNCTION tg_detalle_venta_total()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_id INTEGER := COALESCE(NEW.id_venta, OLD.id_venta);
BEGIN
  UPDATE venta v
     SET total = (SELECT COALESCE(SUM(subtotal), 0) FROM detalle_venta WHERE id_venta = v_id) - v.descuento
   WHERE v.id_venta = v_id;
  RETURN NULL;
END $$;

CREATE TRIGGER trg_detalle_venta_total
AFTER INSERT OR DELETE ON detalle_venta
FOR EACH ROW EXECUTE FUNCTION tg_detalle_venta_total();

-- 3.6 Venta: anulación (devuelve inventario) y control de cambios
CREATE FUNCTION tg_venta_antes_actualizar()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  r RECORD;
BEGIN
  IF OLD.estado = 'ANULADA' AND NEW.estado = 'PAGADA' THEN
    RAISE EXCEPTION 'Una venta anulada no puede reactivarse';
  END IF;

  IF OLD.estado = 'PAGADA' AND NEW.estado = 'ANULADA' THEN
    -- Devuelve insumos consumidos al mismo lote
    FOR r IN SELECT id_lote, cantidad FROM movimiento_inventario
             WHERE id_venta = OLD.id_venta AND tipo = 'SALIDA_VENTA' LOOP
      UPDATE lote SET cantidad_disponible = cantidad_disponible - r.cantidad WHERE id_lote = r.id_lote;
      INSERT INTO movimiento_inventario (id_lote, tipo, cantidad, fecha_hora, id_usuario, id_venta)
      VALUES (r.id_lote, 'REVERSION_VENTA', -r.cantidad, now(), fn_usuario_actual(), OLD.id_venta);
    END LOOP;
    -- Devuelve humintas/pasteles al stock listo
    UPDATE producto p SET stock_listo = p.stock_listo + d.cantidad
    FROM detalle_venta d
    WHERE d.id_venta = OLD.id_venta AND d.id_producto = p.id_producto AND p.tipo = 'ELABORADO';
  END IF;

  IF NEW.descuento <> OLD.descuento THEN
    NEW.total := (SELECT COALESCE(SUM(subtotal), 0) FROM detalle_venta WHERE id_venta = NEW.id_venta) - NEW.descuento;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_venta_antes_actualizar
BEFORE UPDATE ON venta
FOR EACH ROW EXECUTE FUNCTION tg_venta_antes_actualizar();

-- 3.7 Producción: valida que sea ELABORADO
CREATE FUNCTION tg_produccion_antes_insertar()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT tipo FROM producto WHERE id_producto = NEW.id_producto) IS DISTINCT FROM 'ELABORADO' THEN
    RAISE EXCEPTION 'Solo se registra producción de productos ELABORADOS (humintas, pastel)';
  END IF;
  NEW.costo_total := 0;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_produccion_antes_insertar
BEFORE INSERT ON produccion
FOR EACH ROW EXECUTE FUNCTION tg_produccion_antes_insertar();

-- 3.8 Producción: consume insumos por receta y aumenta el stock listo
CREATE FUNCTION tg_produccion_despues_insertar()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_costo NUMERIC := 0;
  r       RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM receta WHERE id_producto = NEW.id_producto) THEN
    RAISE EXCEPTION 'El producto % no tiene receta registrada', NEW.id_producto;
  END IF;

  FOR r IN SELECT id_insumo, cantidad FROM receta WHERE id_producto = NEW.id_producto LOOP
    v_costo := v_costo + fn_consumir_insumo(r.id_insumo, r.cantidad * NEW.cantidad, NEW.fecha_hora,
                                            'SALIDA_PRODUCCION', NEW.id_usuario, NULL, NEW.id_produccion);
  END LOOP;

  UPDATE produccion SET costo_total = round(v_costo, 2) WHERE id_produccion = NEW.id_produccion;
  UPDATE producto SET stock_listo = stock_listo + NEW.cantidad WHERE id_producto = NEW.id_producto;
  RETURN NULL;
END $$;

CREATE TRIGGER trg_produccion_despues_insertar
AFTER INSERT ON produccion
FOR EACH ROW EXECUTE FUNCTION tg_produccion_despues_insertar();

-- 3.9 Merma: valida existencia y calcula el costo perdido
CREATE FUNCTION tg_merma_antes_insertar()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_disp  NUMERIC;
  v_costo NUMERIC;
BEGIN
  IF NEW.id_lote IS NOT NULL THEN
    SELECT cantidad_disponible, costo_unitario INTO v_disp, v_costo FROM lote WHERE id_lote = NEW.id_lote FOR UPDATE;
  ELSE
    IF NEW.cantidad <> trunc(NEW.cantidad) THEN
      RAISE EXCEPTION 'La merma de un producto preparado debe ser en unidades enteras';
    END IF;
    SELECT stock_listo,
           COALESCE((SELECT costo_total / cantidad FROM produccion WHERE id_producto = NEW.id_producto
                     ORDER BY fecha_hora DESC, id_produccion DESC LIMIT 1), fn_costo_receta(NEW.id_producto))
      INTO v_disp, v_costo
      FROM producto WHERE id_producto = NEW.id_producto AND tipo = 'ELABORADO' FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'La merma de producto solo aplica a productos ELABORADOS';
    END IF;
  END IF;

  IF v_disp < NEW.cantidad THEN
    RAISE EXCEPTION 'La merma (%) supera la existencia disponible (%)', NEW.cantidad, v_disp;
  END IF;
  NEW.costo_estimado := round(NEW.cantidad * v_costo, 2);
  RETURN NEW;
END $$;

CREATE TRIGGER trg_merma_antes_insertar
BEFORE INSERT ON merma
FOR EACH ROW EXECUTE FUNCTION tg_merma_antes_insertar();

-- 3.10 Merma: descuenta la existencia y registra el kárdex
CREATE FUNCTION tg_merma_despues_insertar()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.id_lote IS NOT NULL THEN
    UPDATE lote SET cantidad_disponible = cantidad_disponible - NEW.cantidad WHERE id_lote = NEW.id_lote;
    INSERT INTO movimiento_inventario (id_lote, tipo, cantidad, fecha_hora, id_usuario, id_merma)
    VALUES (NEW.id_lote, 'SALIDA_MERMA', -NEW.cantidad, NEW.fecha_hora, NEW.id_usuario, NEW.id_merma);
  ELSE
    UPDATE producto SET stock_listo = stock_listo - NEW.cantidad::INTEGER WHERE id_producto = NEW.id_producto;
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER trg_merma_despues_insertar
AFTER INSERT ON merma
FOR EACH ROW EXECUTE FUNCTION tg_merma_despues_insertar();

-- 3.11 Producto: auditoría de cambios de precio
CREATE FUNCTION tg_producto_historial_precio()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO historial_precio (id_producto, precio_anterior, precio_nuevo, id_usuario)
  VALUES (NEW.id_producto, OLD.precio_venta, NEW.precio_venta, fn_usuario_actual());
  RETURN NULL;
END $$;

CREATE TRIGGER trg_producto_historial_precio
AFTER UPDATE OF precio_venta ON producto
FOR EACH ROW WHEN (OLD.precio_venta IS DISTINCT FROM NEW.precio_venta)
EXECUTE FUNCTION tg_producto_historial_precio();

-- =====================================================================
-- 4. FUNCIONES DE NEGOCIO (las usa la app Angular vía Supabase RPC)
-- =====================================================================

-- 4.1 Registrar venta completa
--     p_items: [{"id_producto": 1, "cantidad": 2}, ...]
CREATE FUNCTION fn_registrar_venta(
  p_items            JSONB,
  p_id_metodo_pago   SMALLINT,
  p_tipo_pedido      VARCHAR     DEFAULT 'MESA',
  p_nro_mesa         SMALLINT    DEFAULT NULL,
  p_id_cliente       INTEGER     DEFAULT 1,
  p_descuento        NUMERIC     DEFAULT 0,
  p_tipo_comprobante VARCHAR     DEFAULT 'NOTA_VENTA',
  p_fecha            TIMESTAMPTZ DEFAULT now())
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_id_venta INTEGER;
  v_usuario  SMALLINT := fn_usuario_actual();
  v_bolsa    INTEGER;
  v_total    NUMERIC;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'La venta debe tener al menos un producto';
  END IF;

  INSERT INTO venta (id_cliente, id_usuario, id_metodo_pago, fecha_hora, tipo_pedido, nro_mesa, tipo_comprobante)
  VALUES (COALESCE(p_id_cliente, 1), v_usuario, p_id_metodo_pago, p_fecha, p_tipo_pedido,
          CASE WHEN p_tipo_pedido = 'MESA' THEN p_nro_mesa END, p_tipo_comprobante)
  RETURNING id_venta INTO v_id_venta;

  INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario)
  SELECT v_id_venta, (i ->> 'id_producto')::INTEGER, SUM((i ->> 'cantidad')::SMALLINT), NULL
  FROM jsonb_array_elements(p_items) AS i
  GROUP BY (i ->> 'id_producto')::INTEGER;

  -- El descuento se aplica al final, cuando ya se conoce el importe completo
  IF COALESCE(p_descuento, 0) > 0 THEN
    SELECT total INTO v_total FROM venta WHERE id_venta = v_id_venta;
    IF p_descuento > v_total THEN
      RAISE EXCEPTION 'El descuento (Bs %) no puede ser mayor al importe de la venta (Bs %)', p_descuento, v_total;
    END IF;
    UPDATE venta SET descuento = p_descuento WHERE id_venta = v_id_venta;
  END IF;

  -- Pedido para llevar: usa una bolsa (si hay en stock)
  IF p_tipo_pedido = 'PARA_LLEVAR' THEN
    SELECT id_insumo INTO v_bolsa FROM insumo WHERE codigo = 'EMP-BOL';
    IF v_bolsa IS NOT NULL AND fn_stock_insumo(v_bolsa, fn_fecha_local(p_fecha)) >= 1 THEN
      PERFORM fn_consumir_insumo(v_bolsa, 1, p_fecha, 'SALIDA_VENTA', v_usuario, v_id_venta, NULL);
    END IF;
  END IF;

  RETURN v_id_venta;
END $$;

-- 4.2 Registrar compra (entrega del proveedor)
--     p_items: [{"id_insumo": 1, "cantidad": 300, "costo_unitario": 1.2, "fecha_vencimiento": "2026-11-20"}, ...]
CREATE FUNCTION fn_registrar_compra(
  p_id_proveedor   INTEGER,
  p_items          JSONB,
  p_tipo_documento VARCHAR     DEFAULT 'NOTA_REMISION',
  p_nro_documento  VARCHAR     DEFAULT NULL,
  p_estado_pago    VARCHAR     DEFAULT 'PAGADO',
  p_observacion    VARCHAR     DEFAULT NULL,
  p_fecha          TIMESTAMPTZ DEFAULT now())
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_id_compra INTEGER;
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'La compra debe tener al menos un insumo';
  END IF;

  INSERT INTO compra (id_proveedor, id_usuario, fecha_recepcion, tipo_documento, nro_documento, estado_pago, observacion)
  VALUES (p_id_proveedor, fn_usuario_actual(), p_fecha, p_tipo_documento, p_nro_documento, p_estado_pago, p_observacion)
  RETURNING id_compra INTO v_id_compra;

  INSERT INTO lote (id_compra, id_insumo, cantidad_recibida, costo_unitario, fecha_vencimiento)
  SELECT v_id_compra,
         (i ->> 'id_insumo')::INTEGER,
         (i ->> 'cantidad')::NUMERIC,
         (i ->> 'costo_unitario')::NUMERIC,
         NULLIF(i ->> 'fecha_vencimiento', '')::DATE
  FROM jsonb_array_elements(p_items) AS i;

  RETURN v_id_compra;
END $$;

-- 4.3 Registrar una tanda de producción
CREATE FUNCTION fn_registrar_produccion(
  p_id_producto INTEGER,
  p_cantidad    SMALLINT,
  p_observacion VARCHAR     DEFAULT NULL,
  p_fecha       TIMESTAMPTZ DEFAULT now())
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_id INTEGER;
BEGIN
  INSERT INTO produccion (id_producto, id_usuario, fecha_hora, cantidad, observacion)
  VALUES (p_id_producto, fn_usuario_actual(), p_fecha, p_cantidad, p_observacion)
  RETURNING id_produccion INTO v_id;
  RETURN v_id;
END $$;

-- 4.4 Registrar una merma (de un lote de insumo o de producto preparado)
CREATE FUNCTION fn_registrar_merma(
  p_motivo      VARCHAR,
  p_cantidad    NUMERIC,
  p_id_lote     INTEGER     DEFAULT NULL,
  p_id_producto INTEGER     DEFAULT NULL,
  p_observacion VARCHAR     DEFAULT NULL,
  p_fecha       TIMESTAMPTZ DEFAULT now())
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_id INTEGER;
BEGIN
  INSERT INTO merma (id_usuario, fecha_hora, id_lote, id_producto, cantidad, motivo, observacion)
  VALUES (fn_usuario_actual(), p_fecha, p_id_lote, p_id_producto, p_cantidad, p_motivo, p_observacion)
  RETURNING id_merma INTO v_id;
  RETURN v_id;
END $$;

-- 4.5 Dar de baja todos los lotes vencidos con saldo (control de desperdicio)
CREATE FUNCTION fn_procesar_vencidos(p_fecha TIMESTAMPTZ DEFAULT now())
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_n INTEGER := 0;
  r   RECORD;
BEGIN
  FOR r IN SELECT id_lote, cantidad_disponible FROM lote
           WHERE cantidad_disponible > 0 AND fecha_vencimiento < fn_fecha_local(p_fecha) LOOP
    PERFORM fn_registrar_merma('VENCIMIENTO', r.cantidad_disponible, r.id_lote, NULL,
                               'Baja automática por vencimiento', p_fecha);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;

-- 4.6 Registrar como merma lo preparado que no se vendió en el día
CREATE FUNCTION fn_registrar_sobrantes(p_fecha TIMESTAMPTZ DEFAULT now())
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_n INTEGER := 0;
  r   RECORD;
BEGIN
  FOR r IN SELECT id_producto, stock_listo FROM producto WHERE tipo = 'ELABORADO' AND stock_listo > 0 LOOP
    PERFORM fn_registrar_merma('SOBRANTE_DIA', r.stock_listo, NULL, r.id_producto,
                               'No vendido al cierre del día', p_fecha);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;

-- 4.7 Cierre de caja del día
CREATE FUNCTION fn_cierre_caja(
  p_fecha            DATE,
  p_efectivo_contado NUMERIC,
  p_monto_apertura   NUMERIC DEFAULT 0,
  p_observacion      VARCHAR DEFAULT NULL)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_id INTEGER;
BEGIN
  IF EXISTS (SELECT 1 FROM cierre_caja WHERE fecha = p_fecha) THEN
    RAISE EXCEPTION 'La caja del % ya fue cerrada', p_fecha;
  END IF;

  INSERT INTO cierre_caja (fecha, id_usuario, monto_apertura, cantidad_ventas, total_efectivo, total_qr,
                           efectivo_contado, observacion)
  SELECT p_fecha, fn_usuario_actual(), p_monto_apertura,
         COUNT(*),
         COALESCE(SUM(v.total) FILTER (WHERE mp.nombre = 'EFECTIVO'), 0),
         COALESCE(SUM(v.total) FILTER (WHERE mp.nombre = 'QR'), 0),
         p_efectivo_contado, p_observacion
  FROM venta v
  JOIN metodo_pago mp USING (id_metodo_pago)
  WHERE v.estado = 'PAGADA' AND fn_fecha_local(v.fecha_hora) = p_fecha
  RETURNING id_cierre_caja INTO v_id;
  RETURN v_id;
END $$;

-- 4.8 Cerrar el día: registra sobrantes como merma y cierra la caja
CREATE FUNCTION fn_cerrar_dia(
  p_fecha            DATE,
  p_efectivo_contado NUMERIC,
  p_monto_apertura   NUMERIC DEFAULT 0,
  p_observacion      VARCHAR DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
  v_momento TIMESTAMPTZ;
  v_sobr    INTEGER;
  v_id      INTEGER;
BEGIN
  v_momento := CASE WHEN p_fecha = fn_fecha_local(now()) THEN now()
                    ELSE (p_fecha + TIME '21:00') AT TIME ZONE 'America/La_Paz' END;
  v_sobr := fn_registrar_sobrantes(v_momento);
  v_id   := fn_cierre_caja(p_fecha, p_efectivo_contado, p_monto_apertura, p_observacion);
  RETURN (SELECT to_jsonb(c) || jsonb_build_object('sobrantes_registrados', v_sobr)
          FROM cierre_caja c WHERE c.id_cierre_caja = v_id);
END $$;

-- 4.9 Anular una venta
CREATE FUNCTION fn_anular_venta(p_id_venta INTEGER, p_motivo VARCHAR)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM cierre_caja c JOIN venta v ON c.fecha = fn_fecha_local(v.fecha_hora)
             WHERE v.id_venta = p_id_venta) THEN
    RAISE EXCEPTION 'No se puede anular: la caja de ese día ya fue cerrada';
  END IF;
  UPDATE venta SET estado = 'ANULADA', motivo_anulacion = p_motivo
  WHERE id_venta = p_id_venta AND estado = 'PAGADA';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La venta % no existe o ya está anulada', p_id_venta;
  END IF;
END $$;

-- =====================================================================
-- 5. PROCEDIMIENTOS ALMACENADOS (CALL ...)
-- =====================================================================

CREATE PROCEDURE sp_registrar_venta(
  p_items          JSONB,
  p_id_metodo_pago SMALLINT,
  p_tipo_pedido    VARCHAR,
  p_nro_mesa       SMALLINT,
  p_id_cliente     INTEGER,
  INOUT p_id_venta INTEGER DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
  p_id_venta := fn_registrar_venta(p_items, p_id_metodo_pago, p_tipo_pedido, p_nro_mesa, p_id_cliente);
  RAISE NOTICE 'Venta % registrada. Total: Bs %', p_id_venta,
    (SELECT total FROM venta WHERE id_venta = p_id_venta);
END $$;

CREATE PROCEDURE sp_registrar_compra(
  p_id_proveedor    INTEGER,
  p_items           JSONB,
  p_tipo_documento  VARCHAR,
  p_nro_documento   VARCHAR,
  INOUT p_id_compra INTEGER DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
  p_id_compra := fn_registrar_compra(p_id_proveedor, p_items, p_tipo_documento, p_nro_documento);
  RAISE NOTICE 'Entrega % registrada. Total: Bs %', p_id_compra,
    (SELECT total FROM compra WHERE id_compra = p_id_compra);
END $$;

CREATE PROCEDURE sp_registrar_produccion(
  p_id_producto         INTEGER,
  p_cantidad            SMALLINT,
  INOUT p_id_produccion INTEGER DEFAULT NULL)
LANGUAGE plpgsql AS $$
BEGIN
  p_id_produccion := fn_registrar_produccion(p_id_producto, p_cantidad);
END $$;

CREATE PROCEDURE sp_cierre_del_dia(p_fecha DATE, p_efectivo_contado NUMERIC, p_monto_apertura NUMERIC DEFAULT 0)
LANGUAGE plpgsql AS $$
DECLARE
  v_res JSONB;
BEGIN
  v_res := fn_cerrar_dia(p_fecha, p_efectivo_contado, p_monto_apertura);
  RAISE NOTICE 'Cierre del %: % ventas, efectivo Bs %, QR Bs %, diferencia Bs %, sobrantes registrados: %',
    p_fecha, v_res ->> 'cantidad_ventas', v_res ->> 'total_efectivo', v_res ->> 'total_qr',
    v_res ->> 'diferencia', v_res ->> 'sobrantes_registrados';
END $$;

CREATE PROCEDURE sp_procesar_vencidos()
LANGUAGE plpgsql AS $$
BEGIN
  RAISE NOTICE '% lote(s) vencido(s) dados de baja como merma', fn_procesar_vencidos(now());
END $$;

CREATE PROCEDURE sp_anular_venta(p_id_venta INTEGER, p_motivo VARCHAR)
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM fn_anular_venta(p_id_venta, p_motivo);
END $$;

-- =====================================================================
-- 6. VISTAS (security_invoker: respetan RLS en Supabase)
-- =====================================================================

-- 6.1 Stock actual de insumos y alerta de stock bajo
CREATE VIEW v_stock_insumo WITH (security_invoker = true) AS
SELECT i.id_insumo,
       i.codigo,
       i.nombre,
       ci.nombre                                         AS categoria,
       um.codigo                                         AS unidad,
       COALESCE(s.stock_vigente, 0)                      AS stock_actual,
       COALESCE(s.stock_vencido, 0)                      AS stock_vencido,
       i.stock_minimo,
       CASE WHEN COALESCE(s.stock_vigente, 0) = 0             THEN 'AGOTADO'
            WHEN COALESCE(s.stock_vigente, 0) <= i.stock_minimo THEN 'BAJO'
            ELSE 'OK' END                                AS estado,
       ROUND(COALESCE(s.valor, 0), 2)                    AS valor_inventario,
       s.proximo_vencimiento
FROM insumo i
JOIN categoria_insumo ci USING (id_categoria_insumo)
JOIN unidad_medida um    USING (id_unidad_medida)
LEFT JOIN LATERAL (
  SELECT SUM(l.cantidad_disponible) FILTER (WHERE l.fecha_vencimiento IS NULL OR l.fecha_vencimiento >= fn_fecha_local(now())) AS stock_vigente,
         SUM(l.cantidad_disponible) FILTER (WHERE l.fecha_vencimiento <  fn_fecha_local(now()))                                AS stock_vencido,
         SUM(l.cantidad_disponible * l.costo_unitario)                                                                        AS valor,
         MIN(l.fecha_vencimiento)   FILTER (WHERE l.fecha_vencimiento >= fn_fecha_local(now()))                                AS proximo_vencimiento
  FROM lote l
  WHERE l.id_insumo = i.id_insumo AND l.cantidad_disponible > 0
) s ON TRUE
WHERE i.activo;

-- 6.2 Lotes con saldo y su situación de vencimiento
CREATE VIEW v_lotes_vigentes WITH (security_invoker = true) AS
SELECT l.id_lote,
       i.codigo                                        AS codigo_insumo,
       i.nombre                                        AS insumo,
       um.codigo                                       AS unidad,
       p.razon_social                                  AS proveedor,
       fn_fecha_local(c.fecha_recepcion)               AS fecha_recepcion,
       l.fecha_vencimiento,
       l.fecha_vencimiento - fn_fecha_local(now())     AS dias_para_vencer,
       l.cantidad_recibida,
       l.cantidad_disponible,
       l.costo_unitario,
       ROUND(l.cantidad_disponible * l.costo_unitario, 2) AS valor_en_riesgo,
       CASE WHEN l.fecha_vencimiento IS NULL                                          THEN 'NO PERECEDERO'
            WHEN l.fecha_vencimiento <  fn_fecha_local(now())                         THEN 'VENCIDO'
            WHEN l.fecha_vencimiento <= fn_fecha_local(now()) + i.dias_alerta_vencimiento THEN 'POR VENCER'
            ELSE 'VIGENTE' END                         AS estado_vencimiento
FROM lote l
JOIN insumo i        USING (id_insumo)
JOIN unidad_medida um USING (id_unidad_medida)
JOIN compra c        USING (id_compra)
JOIN proveedor p     USING (id_proveedor)
WHERE l.cantidad_disponible > 0;

-- 6.3 Resumen de ventas por día
CREATE VIEW v_ventas_diarias WITH (security_invoker = true) AS
SELECT fn_fecha_local(v.fecha_hora)                              AS fecha,
       COUNT(*)                                                  AS nro_ventas,
       SUM(v.total)                                              AS total_vendido,
       SUM(v.total) FILTER (WHERE mp.nombre = 'EFECTIVO')        AS total_efectivo,
       SUM(v.total) FILTER (WHERE mp.nombre = 'QR')              AS total_qr,
       ROUND(AVG(v.total), 2)                                    AS ticket_promedio
FROM venta v
JOIN metodo_pago mp USING (id_metodo_pago)
WHERE v.estado = 'PAGADA'
GROUP BY fn_fecha_local(v.fecha_hora);

-- 6.4 Rentabilidad teórica por producto (precio vs. costo de receta)
CREATE VIEW v_rentabilidad_producto WITH (security_invoker = true) AS
SELECT p.id_producto,
       p.codigo,
       p.nombre,
       cp.nombre                                                       AS categoria,
       p.tipo,
       p.precio_venta,
       fn_costo_receta(p.id_producto)                                  AS costo_insumos,
       ROUND(p.precio_venta - fn_costo_receta(p.id_producto), 2)       AS margen_unitario,
       ROUND(100 * (p.precio_venta - fn_costo_receta(p.id_producto)) / p.precio_venta, 1) AS margen_pct
FROM producto p
JOIN categoria_producto cp USING (id_categoria_producto)
WHERE p.activo;

-- 6.5 Productos para la pantalla de venta (con disponibilidad)
CREATE VIEW v_productos_venta WITH (security_invoker = true) AS
SELECT p.id_producto,
       p.codigo,
       p.nombre,
       cp.nombre AS categoria,
       p.tipo,
       p.precio_venta,
       p.stock_listo,
       CASE WHEN p.tipo = 'ELABORADO' THEN p.stock_listo
            ELSE COALESCE((SELECT FLOOR(MIN(fn_stock_insumo(r.id_insumo) / r.cantidad))
                           FROM receta r WHERE r.id_producto = p.id_producto), 0)
       END::INTEGER AS unidades_disponibles
FROM producto p
JOIN categoria_producto cp USING (id_categoria_producto)
WHERE p.activo;

-- 6.6 Kárdex legible
CREATE VIEW v_kardex WITH (security_invoker = true) AS
SELECT m.id_movimiento,
       m.fecha_hora,
       i.codigo  AS codigo_insumo,
       i.nombre  AS insumo,
       um.codigo AS unidad,
       m.id_lote,
       m.tipo,
       m.cantidad,
       ROUND(m.cantidad * l.costo_unitario, 2) AS valor,
       COALESCE('Venta #' || m.id_venta, 'Producción #' || m.id_produccion,
                'Merma #' || m.id_merma, 'Compra #' || l.id_compra) AS referencia
FROM movimiento_inventario m
JOIN lote l           USING (id_lote)
JOIN insumo i         ON i.id_insumo = l.id_insumo
JOIN unidad_medida um ON um.id_unidad_medida = i.id_unidad_medida;

-- 6.7 Mermas con su origen (insumo o producto)
CREATE VIEW v_mermas WITH (security_invoker = true) AS
SELECT m.id_merma,
       m.fecha_hora,
       fn_fecha_local(m.fecha_hora)                         AS fecha,
       CASE WHEN m.id_lote IS NOT NULL THEN 'INSUMO' ELSE 'PRODUCTO' END AS origen,
       COALESCE(i.nombre, p.nombre)                         AS item,
       COALESCE(um.codigo, 'UND')                           AS unidad,
       m.cantidad,
       m.motivo,
       m.costo_estimado,
       m.observacion
FROM merma m
LEFT JOIN lote l           ON l.id_lote = m.id_lote
LEFT JOIN insumo i         ON i.id_insumo = l.id_insumo
LEFT JOIN unidad_medida um ON um.id_unidad_medida = i.id_unidad_medida
LEFT JOIN producto p       ON p.id_producto = m.id_producto;

-- =====================================================================
-- 7. VISTAS Y FUNCIONES DE REPORTE PARA LA APLICACIÓN
-- =====================================================================

-- 7.1 Ventas con su detalle en texto
CREATE VIEW v_ventas WITH (security_invoker = true) AS
SELECT v.id_venta,
       v.fecha_hora,
       fn_fecha_local(v.fecha_hora) AS fecha,
       v.id_cliente,
       c.nombre                     AS cliente,
       mp.nombre                    AS metodo_pago,
       v.tipo_pedido,
       v.nro_mesa,
       v.tipo_comprobante,
       v.descuento,
       v.total,
       v.estado,
       v.motivo_anulacion,
       (SELECT string_agg(d.cantidad || ' x ' || p.nombre, ', ' ORDER BY d.id_detalle_venta)
          FROM detalle_venta d JOIN producto p USING (id_producto)
         WHERE d.id_venta = v.id_venta) AS detalle
FROM venta v
JOIN cliente c      USING (id_cliente)
JOIN metodo_pago mp USING (id_metodo_pago);

-- 7.2 Entregas de proveedores (compras) resumidas
CREATE VIEW v_compras WITH (security_invoker = true) AS
SELECT c.id_compra,
       c.fecha_recepcion,
       fn_fecha_local(c.fecha_recepcion) AS fecha,
       p.id_proveedor,
       p.razon_social                    AS proveedor,
       c.tipo_documento,
       c.nro_documento,
       c.total,
       c.estado_pago,
       (SELECT string_agg(i.nombre || ' ' || trim_scale(l.cantidad_recibida) || ' ' || um.codigo, ', ' ORDER BY l.id_lote)
          FROM lote l
          JOIN insumo i         USING (id_insumo)
          JOIN unidad_medida um USING (id_unidad_medida)
         WHERE l.id_compra = c.id_compra) AS detalle
FROM compra c
JOIN proveedor p USING (id_proveedor);

-- 7.3 Insumos que entrega cada proveedor
CREATE VIEW v_proveedor_insumo WITH (security_invoker = true) AS
SELECT pi.id_proveedor,
       p.razon_social AS proveedor,
       pi.id_insumo,
       i.codigo,
       i.nombre       AS insumo,
       um.codigo      AS unidad,
       pi.precio_referencia,
       pi.es_principal,
       i.es_perecedero,
       i.vida_util_dias
FROM proveedor_insumo pi
JOIN proveedor p      USING (id_proveedor)
JOIN insumo i         USING (id_insumo)
JOIN unidad_medida um USING (id_unidad_medida)
WHERE p.activo AND i.activo;

-- 7.4 Producción con nombre de producto
CREATE VIEW v_produccion WITH (security_invoker = true) AS
SELECT pr.id_produccion,
       pr.fecha_hora,
       fn_fecha_local(pr.fecha_hora)          AS fecha,
       p.id_producto,
       p.nombre                               AS producto,
       pr.cantidad,
       pr.costo_total,
       ROUND(pr.costo_total / pr.cantidad, 2) AS costo_unitario,
       pr.observacion
FROM produccion pr
JOIN producto p USING (id_producto);

-- 7.5 Resumen para el tablero de inicio
CREATE FUNCTION fn_resumen_tablero(p_fecha DATE DEFAULT NULL)
RETURNS JSONB LANGUAGE sql STABLE AS $$
  WITH f AS (SELECT COALESCE(p_fecha, fn_fecha_local(now())) AS hoy),
  vh AS (
    SELECT COUNT(*)                                                   AS nro,
           COALESCE(SUM(v.total), 0)                                  AS total,
           COALESCE(SUM(v.total) FILTER (WHERE mp.nombre = 'EFECTIVO'), 0) AS efectivo,
           COALESCE(SUM(v.total) FILTER (WHERE mp.nombre = 'QR'), 0)       AS qr
    FROM venta v JOIN metodo_pago mp USING (id_metodo_pago), f
    WHERE v.estado = 'PAGADA' AND fn_fecha_local(v.fecha_hora) = f.hoy),
  vm AS (
    SELECT COALESCE(SUM(v.total), 0) AS total
    FROM venta v, f
    WHERE v.estado = 'PAGADA'
      AND fn_fecha_local(v.fecha_hora) BETWEEN date_trunc('month', f.hoy)::date AND f.hoy),
  mm AS (
    SELECT COALESCE(SUM(m.costo_estimado), 0) AS total
    FROM merma m, f
    WHERE fn_fecha_local(m.fecha_hora) BETWEEN date_trunc('month', f.hoy)::date AND f.hoy)
  SELECT jsonb_build_object(
           'fecha',               f.hoy,
           'ventas_hoy',          vh.total,
           'nro_ventas_hoy',      vh.nro,
           'ticket_promedio_hoy', CASE WHEN vh.nro > 0 THEN round(vh.total / vh.nro, 2) ELSE 0 END,
           'efectivo_hoy',        vh.efectivo,
           'qr_hoy',              vh.qr,
           'ventas_mes',          vm.total,
           'mermas_mes',          mm.total,
           'insumos_stock_bajo',  (SELECT count(*) FROM v_stock_insumo WHERE estado <> 'OK'),
           'lotes_por_vencer',    (SELECT count(*) FROM v_lotes_vigentes WHERE estado_vencimiento IN ('POR VENCER','VENCIDO')),
           'humintas_listas',     (SELECT COALESCE(SUM(stock_listo), 0) FROM producto WHERE tipo = 'ELABORADO'),
           'caja_cerrada',        EXISTS (SELECT 1 FROM cierre_caja c WHERE c.fecha = f.hoy))
  FROM f, vh, vm, mm
$$;

-- 7.6 Ventas, costo y ganancia por producto en un rango de fechas
CREATE FUNCTION fn_reporte_productos(p_desde DATE, p_hasta DATE)
RETURNS TABLE (producto VARCHAR, categoria VARCHAR, unidades BIGINT, ingresos NUMERIC,
               costo NUMERIC, ganancia NUMERIC, margen_pct NUMERIC, participacion_pct NUMERIC)
LANGUAGE sql STABLE AS $$
  SELECT p.nombre,
         cp.nombre,
         SUM(d.cantidad),
         SUM(d.subtotal),
         ROUND(SUM(d.cantidad * d.costo_unitario), 2),
         ROUND(SUM(d.subtotal - d.cantidad * d.costo_unitario), 2),
         ROUND(100 * SUM(d.subtotal - d.cantidad * d.costo_unitario) / NULLIF(SUM(d.subtotal), 0), 1),
         ROUND(100 * SUM(d.subtotal) / NULLIF(SUM(SUM(d.subtotal)) OVER (), 0), 1)
  FROM detalle_venta d
  JOIN venta v               USING (id_venta)
  JOIN producto p            USING (id_producto)
  JOIN categoria_producto cp USING (id_categoria_producto)
  WHERE v.estado = 'PAGADA' AND fn_fecha_local(v.fecha_hora) BETWEEN p_desde AND p_hasta
  GROUP BY p.nombre, cp.nombre
  ORDER BY SUM(d.subtotal) DESC
$$;

-- 7.7 Ventas por hora del día en un rango de fechas
CREATE FUNCTION fn_reporte_ventas_hora(p_desde DATE, p_hasta DATE)
RETURNS TABLE (hora INTEGER, nro_ventas BIGINT, total NUMERIC)
LANGUAGE sql STABLE AS $$
  SELECT EXTRACT(HOUR FROM v.fecha_hora AT TIME ZONE 'America/La_Paz')::INTEGER,
         COUNT(*),
         SUM(v.total)
  FROM venta v
  WHERE v.estado = 'PAGADA' AND fn_fecha_local(v.fecha_hora) BETWEEN p_desde AND p_hasta
  GROUP BY 1
  ORDER BY 1
$$;

-- 7.8 Mermas por motivo en un rango de fechas
CREATE FUNCTION fn_reporte_mermas(p_desde DATE, p_hasta DATE)
RETURNS TABLE (motivo VARCHAR, origen TEXT, registros BIGINT, costo NUMERIC)
LANGUAGE sql STABLE AS $$
  SELECT m.motivo, m.origen, COUNT(*), SUM(m.costo_estimado)
  FROM v_mermas m
  WHERE m.fecha BETWEEN p_desde AND p_hasta
  GROUP BY m.motivo, m.origen
  ORDER BY 4 DESC
$$;

-- 7.9 Vista previa de la caja de un día (antes de cerrarla)
CREATE FUNCTION fn_resumen_caja(p_fecha DATE)
RETURNS JSONB LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
           'fecha',           p_fecha,
           'cantidad_ventas', COUNT(*),
           'total_efectivo',  COALESCE(SUM(v.total) FILTER (WHERE mp.nombre = 'EFECTIVO'), 0),
           'total_qr',        COALESCE(SUM(v.total) FILTER (WHERE mp.nombre = 'QR'), 0),
           'total',           COALESCE(SUM(v.total), 0),
           'cerrada',         EXISTS (SELECT 1 FROM cierre_caja c WHERE c.fecha = p_fecha))
  FROM venta v
  JOIN metodo_pago mp USING (id_metodo_pago)
  WHERE v.estado = 'PAGADA' AND fn_fecha_local(v.fecha_hora) = p_fecha
$$;

-- Fin del script 01
