import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../core/api.service';
import { AvisoService } from '../core/aviso.service';
import { BsPipe, FechaPipe, hoy } from '../core/formato';
import { Cliente, MetodoPago, ProductoVenta, VentaResumen } from '../core/modelos';

interface LineaCarrito { producto: ProductoVenta; cantidad: number; }

@Component({
  selector: 'app-ventas',
  imports: [FormsModule, BsPipe, FechaPipe],
  templateUrl: './ventas.html',
})
export class Ventas implements OnInit {
  private api = inject(ApiService);
  private aviso = inject(AvisoService);

  readonly productos = signal<ProductoVenta[]>([]);
  readonly clientes = signal<Cliente[]>([]);
  readonly metodos = signal<MetodoPago[]>([]);
  readonly ventasHoy = signal<VentaResumen[]>([]);
  readonly carrito = signal<LineaCarrito[]>([]);
  readonly tipoPedido = signal<'MESA' | 'PARA_LLEVAR'>('MESA');
  readonly metodo = signal<number>(0);
  readonly guardando = signal(false);
  readonly mesas = [1, 2, 3, 4, 5, 6, 7, 8];
  mesa = 1;
  idCliente = 1;
  comprobante: 'NOTA_VENTA' | 'FACTURA' = 'NOTA_VENTA';
  descuento = 0;
  recibido: number | null = null;
  nuevoCliente: { nombre: string; ci_nit: string; telefono: string } | null = null;

  readonly categorias = computed(() => {
    const mapa = new Map<string, ProductoVenta[]>();
    for (const p of this.productos()) mapa.set(p.categoria, [...(mapa.get(p.categoria) ?? []), p]);
    return [...mapa.entries()].map(([nombre, items]) => ({ nombre, items: [...items].sort((a, b) => a.nombre.localeCompare(b.nombre)) }));
  });
  readonly subtotal = computed(() => this.carrito().reduce((s, l) => s + l.cantidad * Number(l.producto.precio_venta), 0));
  readonly nombreMetodo = computed(() => this.metodos().find(m => m.id_metodo_pago === this.metodo())?.nombre ?? '');
  readonly totalDia = computed(() => this.ventasHoy().filter(v => v.estado === 'PAGADA').reduce((s, v) => s + Number(v.total), 0));

  get total(): number { return Math.max(0, this.subtotal() - (Number(this.descuento) || 0)); }
  get cambio(): number | null { return this.recibido ? Number(this.recibido) - this.total : null; }

  async ngOnInit() {
    try {
      const [metodos, clientes] = await Promise.all([
        this.api.lista<MetodoPago>('metodo_pago', { filtros: [['activo', 'eq', true]], orden: 'id_metodo_pago' }),
        this.api.lista<Cliente>('cliente', { filtros: [['activo', 'eq', true]], orden: 'nombre' }),
      ]);
      this.metodos.set(metodos);
      this.metodo.set(metodos.find(m => m.nombre === 'QR')?.id_metodo_pago ?? metodos[0]?.id_metodo_pago);
      this.clientes.set([...clientes.filter(c => c.id_cliente === 1), ...clientes.filter(c => c.id_cliente !== 1)]);
      await this.recargar();
    } catch (e) {
      this.aviso.error(e);
    }
  }

  async recargar() {
    const [productos, ventas] = await Promise.all([
      this.api.lista<ProductoVenta>('v_productos_venta', { orden: 'id_producto' }),
      this.api.lista<VentaResumen>('v_ventas', { filtros: [['fecha', 'eq', hoy()]], orden: 'id_venta', asc: false }),
    ]);
    this.productos.set(productos);
    this.ventasHoy.set(ventas);
  }

  enCarrito(p: ProductoVenta): number {
    return this.carrito().find(l => l.producto.id_producto === p.id_producto)?.cantidad ?? 0;
  }

  agregar(p: ProductoVenta) {
    if (this.enCarrito(p) >= p.unidades_disponibles) {
      this.aviso.error(`No hay más "${p.nombre}" disponible`);
      return;
    }
    this.carrito.update(l => l.some(x => x.producto.id_producto === p.id_producto)
      ? l.map(x => x.producto.id_producto === p.id_producto ? { ...x, cantidad: x.cantidad + 1 } : x)
      : [...l, { producto: p, cantidad: 1 }]);
  }

  cambiar(linea: LineaCarrito, delta: number) {
    if (delta > 0) return this.agregar(linea.producto);
    this.carrito.update(l => l.map(x => x === linea ? { ...x, cantidad: x.cantidad - 1 } : x).filter(x => x.cantidad > 0));
  }

  async cobrar() {
    if (!this.carrito().length) return;
    this.guardando.set(true);
    try {
      const id = await this.api.rpc<number>('fn_registrar_venta', {
        p_items: this.carrito().map(l => ({ id_producto: l.producto.id_producto, cantidad: l.cantidad })),
        p_id_metodo_pago: this.metodo(),
        p_tipo_pedido: this.tipoPedido(),
        p_nro_mesa: this.tipoPedido() === 'MESA' ? this.mesa : null,
        p_id_cliente: Number(this.idCliente),
        p_descuento: Number(this.descuento) || 0,
        p_tipo_comprobante: this.comprobante,
      });
      this.aviso.ok(`Venta #${id} registrada por ${this.totalTexto()}`);
      this.carrito.set([]);
      this.descuento = 0;
      this.recibido = null;
      this.idCliente = 1;
      this.comprobante = 'NOTA_VENTA';
      await this.recargar();
    } catch (e) {
      this.aviso.error(e);
    } finally {
      this.guardando.set(false);
    }
  }

  private totalTexto() { return 'Bs ' + this.total.toFixed(2).replace('.', ','); }

  async guardarCliente() {
    const c = this.nuevoCliente!;
    if (!c.nombre.trim()) return;
    try {
      const nuevo = await this.api.insertar<Cliente>('cliente', {
        nombre: c.nombre.trim(), ci_nit: c.ci_nit.trim() || null, telefono: c.telefono.trim() || null,
      });
      this.clientes.update(l => [...l, nuevo]);
      this.idCliente = nuevo.id_cliente;
      this.nuevoCliente = null;
      this.aviso.ok('Cliente registrado');
    } catch (e) {
      this.aviso.error(e);
    }
  }

  async anular(v: VentaResumen) {
    const motivo = prompt(`¿Por qué se anula la venta #${v.id_venta}?`, 'Error de registro');
    if (!motivo) return;
    try {
      await this.api.rpc('fn_anular_venta', { p_id_venta: v.id_venta, p_motivo: motivo });
      this.aviso.ok(`Venta #${v.id_venta} anulada; el inventario fue devuelto`);
      await this.recargar();
    } catch (e) {
      this.aviso.error(e);
    }
  }
}
