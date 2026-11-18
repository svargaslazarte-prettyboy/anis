import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../core/api.service';
import { AvisoService } from '../core/aviso.service';
import { BsPipe, FechaPipe, hoy } from '../core/formato';
import { Produccion, ProductoVenta, VentaResumen } from '../core/modelos';

@Component({
  selector: 'app-produccion',
  imports: [FormsModule, BsPipe, FechaPipe],
  template: `
  <div class="encabezado">
    <div><h1>Producción por tandas</h1><p>Registre cuántas humintas y pasteles se prepararon; los insumos se descuentan solos según la receta</p></div>
  </div>
  <div class="grid g-pos">
    <div>
      <div class="grid g3">
        @for (p of elaborados(); track p.id_producto) {
          <div class="tarjeta stock-listo" [class.sin]="!p.stock_listo">
            <div class="muted peq">{{ p.categoria }}</div>
            <b>{{ p.nombre }}</b>
            <div class="total-grande">{{ p.stock_listo }}</div>
            <div class="peq">listas para vender · hoy se hicieron {{ producidoHoy(p.id_producto) }}</div>
          </div>
        }
      </div>
      <div class="tarjeta mt">
        <h2>Tandas de hoy</h2>
        <div class="tabla-wrap"><table>
          <thead><tr><th>Hora</th><th>Producto</th><th class="num">Cantidad</th><th class="num">Costo insumos</th><th class="num">Costo c/u</th><th>Observación</th></tr></thead>
          <tbody>
            @for (t of tandas(); track t.id_produccion) {
              <tr><td>{{ t.fecha_hora | fecha: 'hora' }}</td><td>{{ t.producto }}</td><td class="num">{{ t.cantidad }}</td>
                <td class="num">{{ t.costo_total | bs }}</td><td class="num">{{ t.costo_unitario | bs }}</td><td>{{ t.observacion }}</td></tr>
            } @empty { <tr><td colspan="6" class="vacio">Aún no se registró producción hoy</td></tr> }
          </tbody>
        </table></div>
      </div>
    </div>
    <div class="tarjeta">
      <h2>Nueva tanda</h2>
      <div class="grid mt-s">
        <label class="campo">Producto
          <select [(ngModel)]="idProducto">
            @for (p of elaborados(); track p.id_producto) { <option [ngValue]="p.id_producto">{{ p.nombre }}</option> }
          </select>
        </label>
        <label class="campo">Cantidad preparada<input type="number" min="1" [(ngModel)]="cantidad"></label>
        <label class="campo">Observación<input [(ngModel)]="observacion" placeholder="Ej.: tanda de la mañana"></label>
        <button class="btn amarillo grande" [disabled]="guardando() || !cantidad" (click)="registrar()">🌽 Registrar tanda</button>
        <p class="muted peq">Si falta algún insumo (choclo, queso…), el sistema no deja registrar la tanda y avisa cuánto hay.</p>
      </div>
    </div>
  </div>`,
  styles: `.stock-listo { display: grid; gap: 2px; } .stock-listo.sin .total-grande { color: var(--error); }`,
})
export class ProduccionPage implements OnInit {
  private api = inject(ApiService);
  private aviso = inject(AvisoService);
  readonly productos = signal<ProductoVenta[]>([]);
  readonly tandas = signal<Produccion[]>([]);
  readonly elaborados = computed(() => this.productos().filter(p => p.tipo === 'ELABORADO'));
  readonly guardando = signal(false);
  idProducto = 0;
  cantidad = 20;
  observacion = '';

  async ngOnInit() {
    await this.recargar();
    this.idProducto = this.elaborados()[0]?.id_producto ?? 0;
  }

  async recargar() {
    try {
      const [p, t] = await Promise.all([
        this.api.lista<ProductoVenta>('v_productos_venta', { orden: 'id_producto' }),
        this.api.lista<Produccion>('v_produccion', { filtros: [['fecha', 'eq', hoy()]], orden: 'id_produccion', asc: false }),
      ]);
      this.productos.set(p);
      this.tandas.set(t);
    } catch (e) { this.aviso.error(e); }
  }

  producidoHoy(id: number) {
    return this.tandas().filter(t => t.id_producto === id).reduce((s, t) => s + t.cantidad, 0);
  }

  async registrar() {
    this.guardando.set(true);
    try {
      await this.api.rpc('fn_registrar_produccion', {
        p_id_producto: Number(this.idProducto), p_cantidad: Number(this.cantidad), p_observacion: this.observacion || null,
      });
      this.aviso.ok('Tanda registrada; insumos descontados del inventario');
      this.observacion = '';
      await this.recargar();
    } catch (e) { this.aviso.error(e); } finally { this.guardando.set(false); }
  }
}
