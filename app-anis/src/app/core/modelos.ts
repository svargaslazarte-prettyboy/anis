export interface ProductoVenta {
  id_producto: number; codigo: string; nombre: string; categoria: string;
  tipo: 'ELABORADO' | 'AL_MOMENTO' | 'REVENTA'; precio_venta: number; stock_listo: number; unidades_disponibles: number;
}
export interface Cliente { id_cliente: number; nombre: string; ci_nit: string | null; telefono: string | null; }
export interface MetodoPago { id_metodo_pago: number; nombre: string; }
export interface VentaResumen {
  id_venta: number; fecha_hora: string; fecha: string; cliente: string; metodo_pago: string; tipo_pedido: string;
  nro_mesa: number | null; tipo_comprobante: string; descuento: number; total: number; estado: string; detalle: string;
  motivo_anulacion: string | null;
}
export interface StockInsumo {
  id_insumo: number; codigo: string; nombre: string; categoria: string; unidad: string; stock_actual: number;
  stock_vencido: number; stock_minimo: number; estado: 'OK' | 'BAJO' | 'AGOTADO'; valor_inventario: number;
  proximo_vencimiento: string | null;
}
export interface Lote {
  id_lote: number; codigo_insumo: string; insumo: string; unidad: string; proveedor: string; fecha_recepcion: string;
  fecha_vencimiento: string | null; dias_para_vencer: number | null; cantidad_recibida: number; cantidad_disponible: number;
  costo_unitario: number; valor_en_riesgo: number; estado_vencimiento: string;
}
export interface Kardex {
  id_movimiento: number; fecha_hora: string; codigo_insumo: string; insumo: string; unidad: string; id_lote: number;
  tipo: string; cantidad: number; valor: number; referencia: string;
}
export interface Proveedor {
  id_proveedor: number; razon_social: string; nit: string | null; nombre_contacto: string | null; telefono: string;
  direccion: string | null; dias_entrega: string | null; activo: boolean;
}
export interface ProveedorInsumo {
  id_proveedor: number; proveedor: string; id_insumo: number; codigo: string; insumo: string; unidad: string;
  precio_referencia: number; es_principal: boolean; es_perecedero: boolean; vida_util_dias: number | null;
}
export interface CompraResumen {
  id_compra: number; fecha_recepcion: string; fecha: string; proveedor: string; tipo_documento: string;
  nro_documento: string | null; total: number; estado_pago: string; detalle: string;
}
export interface Produccion {
  id_produccion: number; fecha_hora: string; fecha: string; id_producto: number; producto: string; cantidad: number;
  costo_total: number; costo_unitario: number; observacion: string | null;
}
export interface Merma {
  id_merma: number; fecha_hora: string; fecha: string; origen: 'INSUMO' | 'PRODUCTO'; item: string; unidad: string;
  cantidad: number; motivo: string; costo_estimado: number; observacion: string | null;
}
export interface VentaDiaria { fecha: string; nro_ventas: number; total_vendido: number; total_efectivo: number; total_qr: number; ticket_promedio: number; }
export interface ReporteProducto {
  producto: string; categoria: string; unidades: number; ingresos: number; costo: number; ganancia: number;
  margen_pct: number; participacion_pct: number;
}
export interface Tablero {
  fecha: string; ventas_hoy: number; nro_ventas_hoy: number; ticket_promedio_hoy: number; efectivo_hoy: number; qr_hoy: number;
  ventas_mes: number; mermas_mes: number; insumos_stock_bajo: number; lotes_por_vencer: number; humintas_listas: number;
  caja_cerrada: boolean;
}
export interface CierreCaja {
  id_cierre_caja: number; fecha: string; monto_apertura: number; cantidad_ventas: number; total_efectivo: number;
  total_qr: number; efectivo_contado: number; diferencia: number; observacion: string | null;
}
