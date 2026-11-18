import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../core/api.service';
import { AvisoService } from '../core/aviso.service';
import { BsPipe, FechaPipe, hoy, sumarDias } from '../core/formato';
import { CompraResumen, Proveedor, ProveedorInsumo } from '../core/modelos';

interface Renglon { pi: ProveedorInsumo; cantidad: number | null; costo: number; vence: string; }

@Component({
  selector: 'app-entregas',
  imports: [FormsModule, BsPipe, FechaPipe],
  template: `
  <div class="encabezado">
    <div><h1>Entregas de proveedores</h1><p>Todo llega al local: registre lo que recibe y el inventario se actualiza por lote con su vencimiento</p></div>
  </div>
  <div class="grid g-pos">
    <div class="tarjeta">
      <h2>Registrar entrega</h2>
      <div class="fila-form mt-s">
        <label class="campo">Proveedor
          <select [ngModel]="idProveedor()" (ngModelChange)="elegirProveedor($event)">
            <option [ngValue]="0" disabled>Seleccione…</option>
            @for (p of proveedores(); track p.id_proveedor) { <option [ngValue]="p.id_proveedor">{{ p.razon_social }}</option> }
          </select>
        </label>
        <label class="campo">Documento
          <select [(ngModel)]="tipoDoc">
            <option value="FACTURA">Factura</option><option value="NOTA_REMISION">Nota de remisión</option>
            <option value="RECIBO">Recibo</option><option value="SIN_DOCUMENTO">Sin documento</option>
          </select>
        </label>
        <label class="campo">N.º documento<input [(ngModel)]="nroDoc" placeholder="Opcional"></label>
        <label class="campo">Pago
          <select [(ngModel)]="estadoPago"><option value="PAGADO">Pagado</option><option value="PENDIENTE">Pendiente (crédito)</option></select>
        </label>
      </div>
      @if (proveedorSel(); as p) { <p class="muted peq">📅 Días de entrega: {{ p.dias_entrega }} · ☎ {{ p.telefono }} · {{ p.nombre_contacto }}</p> }
      @if (renglones().length) {
        <div class="tabla-wrap"><table>
          <thead><tr><th>Insumo</th><th style="width:130px">Cantidad</th><th style="width:130px">Costo unit. (Bs)</th><th style="width:160px">Vence</th><th class="num">Subtotal</th></tr></thead>
          <tbody>
            @for (r of renglones(); track r.pi.id_insumo) {
              <tr>
                <td><b>{{ r.pi.insumo }}</b><div class="muted peq">en {{ r.pi.unidad }}</div></td>
                <td><input type="number" min="0" step="any" [(ngModel)]="r.cantidad" [placeholder]="r.pi.unidad"></td>
                <td><input type="number" min="0" step="0.01" [(ngModel)]="r.costo"></td>
                <td>@if (r.pi.es_perecedero) { <input type="date" [(ngModel)]="r.vence"> } @else { <span class="muted">No vence</span> }</td>
                <td class="num">{{ (r.cantidad || 0) * r.costo | bs }}</td>
              </tr>
            }
          </tbody>
        </table></div>
        <div class="total-fila mt"><span>Total de la entrega</span><span class="total-grande">{{ totalEntrega | bs }}</span></div>
        <button class="btn amarillo grande" [disabled]="guardando() || !totalEntrega" (click)="registrar()">🚚 Registrar entrega</button>
      } @else { <div class="vacio">Elija un proveedor para ver los insumos que entrega</div> }
    </div>
    <div class="tarjeta">
      <h2>Últimas entregas</h2>
      @for (c of compras(); track c.id_compra) {
        <div class="alerta-fila">
          <div><b>{{ c.proveedor }}</b><div class="muted peq">{{ c.fecha_recepcion | fecha: 'completa' }} · {{ c.detalle }}</div></div>
          <div class="der"><b>{{ c.total | bs }}</b><span class="chip" [class.ok]="c.estado_pago === 'PAGADO'" [class.bajo]="c.estado_pago === 'PENDIENTE'">{{ c.estado_pago }}</span></div>
        </div>
      }
    </div>
  </div>`,
})
export class Entregas implements OnInit {
  private api = inject(ApiService);
  private aviso = inject(AvisoService);
  readonly proveedores = signal<Proveedor[]>([]);
  readonly compras = signal<CompraResumen[]>([]);
  readonly renglones = signal<Renglon[]>([]);
  readonly idProveedor = signal(0);
  readonly proveedorSel = computed(() => this.proveedores().find(p => p.id_proveedor === this.idProveedor()));
  readonly guardando = signal(false);
  tipoDoc = 'NOTA_REMISION';
  nroDoc = '';
  estadoPago = 'PAGADO';

  get totalEntrega() { return this.renglones().reduce((s, r) => s + (Number(r.cantidad) || 0) * Number(r.costo), 0); }

  async ngOnInit() {
    try {
      this.proveedores.set(await this.api.lista<Proveedor>('proveedor', { filtros: [['activo', 'eq', true]], orden: 'razon_social' }));
      await this.cargarCompras();
    } catch (e) { this.aviso.error(e); }
  }

  async cargarCompras() {
    this.compras.set(await this.api.lista<CompraResumen>('v_compras', { orden: 'id_compra', asc: false, limite: 12 }));
  }

  async elegirProveedor(id: number) {
    this.idProveedor.set(id);
    const items = await this.api.lista<ProveedorInsumo>('v_proveedor_insumo', { filtros: [['id_proveedor', 'eq', id]], orden: 'insumo' });
    this.renglones.set(items.map(pi => ({
      pi, cantidad: null, costo: Number(pi.precio_referencia),
      vence: pi.vida_util_dias ? sumarDias(hoy(), pi.vida_util_dias) : '',
    })));
  }

  async registrar() {
    const items = this.renglones().filter(r => Number(r.cantidad) > 0).map(r => ({
      id_insumo: r.pi.id_insumo, cantidad: Number(r.cantidad), costo_unitario: Number(r.costo),
      fecha_vencimiento: r.pi.es_perecedero ? r.vence || null : null,
    }));
    this.guardando.set(true);
    try {
      const id = await this.api.rpc<number>('fn_registrar_compra', {
        p_id_proveedor: this.idProveedor(), p_items: items, p_tipo_documento: this.tipoDoc,
        p_nro_documento: this.nroDoc || null, p_estado_pago: this.estadoPago,
      });
      this.aviso.ok(`Entrega #${id} registrada; ${items.length} lote(s) ingresaron al inventario`);
      this.nroDoc = '';
      await this.elegirProveedor(this.idProveedor());
      await this.cargarCompras();
    } catch (e) { this.aviso.error(e); } finally { this.guardando.set(false); }
  }
}
