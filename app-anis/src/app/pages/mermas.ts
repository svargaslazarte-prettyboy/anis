import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../core/api.service';
import { AvisoService } from '../core/aviso.service';
import { BsPipe, CantidadPipe, FechaPipe, hoy, inicioMes } from '../core/formato';
import { Lote, Merma, ProductoVenta } from '../core/modelos';

interface ResumenMerma { motivo: string; origen: string; registros: number; costo: number; }

@Component({
  selector: 'app-mermas',
  imports: [FormsModule, BsPipe, CantidadPipe, FechaPipe],
  template: `
  <div class="encabezado">
    <div><h1>Mermas y desperdicio</h1><p>Registrar lo que se bota permite medirlo y reducirlo (ODS 12)</p></div>
    <span class="chip bajo">Este mes: {{ totalMes() | bs }}</span>
  </div>
  <div class="grid g4">
    @for (r of resumen(); track r.motivo + r.origen) {
      <div class="tarjeta kpi" [class.amarillo]="r.origen === 'PRODUCTO'">
        <div class="icono">{{ iconos[r.motivo] || '🗑️' }}</div>
        <div><div class="valor">{{ r.costo | bs }}</div><div class="etiqueta">{{ nombres[r.motivo] }} · {{ r.registros }} registro(s)</div></div>
      </div>
    }
  </div>
  <div class="grid g-pos mt">
    <div class="tarjeta">
      <h2>Últimas mermas</h2>
      <div class="tabla-wrap"><table>
        <thead><tr><th>Fecha</th><th>Origen</th><th>Ítem</th><th class="num">Cantidad</th><th>Motivo</th><th class="num">Costo</th></tr></thead>
        <tbody>
          @for (m of mermas(); track m.id_merma) {
            <tr><td>{{ m.fecha_hora | fecha: 'completa' }}</td><td><span class="chip" [class.info]="m.origen === 'INSUMO'" [class.amarillo]="m.origen === 'PRODUCTO'">{{ m.origen }}</span></td>
              <td>{{ m.item }}</td><td class="num">{{ m.cantidad | cant: m.unidad }}</td><td>{{ nombres[m.motivo] }}</td><td class="num">{{ m.costo_estimado | bs }}</td></tr>
          }
        </tbody>
      </table></div>
    </div>
    <div class="tarjeta">
      <h2>Registrar merma</h2>
      <div class="segmento mt-s">
        <button [class.activo]="origen() === 'PRODUCTO'" (click)="origen.set('PRODUCTO')">🌽 Producto preparado</button>
        <button [class.activo]="origen() === 'INSUMO'" (click)="origen.set('INSUMO')">📦 Insumo (lote)</button>
      </div>
      <div class="grid mt">
        @if (origen() === 'PRODUCTO') {
          <label class="campo">Producto
            <select [(ngModel)]="idProducto">
              @for (p of elaborados(); track p.id_producto) { <option [ngValue]="p.id_producto">{{ p.nombre }} ({{ p.stock_listo }} listas)</option> }
            </select>
          </label>
        } @else {
          <label class="campo">Lote
            <select [(ngModel)]="idLote">
              @for (l of lotes(); track l.id_lote) { <option [ngValue]="l.id_lote">#{{ l.id_lote }} {{ l.insumo }} · quedan {{ l.cantidad_disponible | cant: l.unidad }}</option> }
            </select>
          </label>
        }
        <label class="campo">Cantidad<input type="number" min="0" step="any" [(ngModel)]="cantidad"></label>
        <label class="campo">Motivo
          <select [(ngModel)]="motivo">
            @for (m of motivos; track m) { <option [value]="m">{{ nombres[m] }}</option> }
          </select>
        </label>
        <label class="campo">Observación<input [(ngModel)]="observacion"></label>
        <button class="btn amarillo grande" [disabled]="!cantidad" (click)="registrar()">Registrar merma</button>
      </div>
    </div>
  </div>`,
})
export class Mermas implements OnInit {
  private api = inject(ApiService);
  private aviso = inject(AvisoService);
  readonly mermas = signal<Merma[]>([]);
  readonly resumen = signal<ResumenMerma[]>([]);
  readonly productos = signal<ProductoVenta[]>([]);
  readonly lotes = signal<Lote[]>([]);
  readonly origen = signal<'PRODUCTO' | 'INSUMO'>('PRODUCTO');
  readonly elaborados = computed(() => this.productos().filter(p => p.tipo === 'ELABORADO'));
  readonly totalMes = computed(() => this.resumen().reduce((s, r) => s + Number(r.costo), 0));
  readonly motivos = ['SOBRANTE_DIA', 'VENCIMIENTO', 'DETERIORO', 'ERROR_PREPARACION', 'AJUSTE_CONTEO'];
  readonly nombres: Record<string, string> = {
    SOBRANTE_DIA: 'Sobrante del día', VENCIMIENTO: 'Vencimiento', DETERIORO: 'Deterioro',
    ERROR_PREPARACION: 'Error de preparación', AJUSTE_CONTEO: 'Ajuste por conteo',
  };
  readonly iconos: Record<string, string> = { SOBRANTE_DIA: '🌽', VENCIMIENTO: '⏰', DETERIORO: '🧀', ERROR_PREPARACION: '🔥', AJUSTE_CONTEO: '📋' };
  idProducto = 0; idLote = 0; cantidad: number | null = null; motivo = 'SOBRANTE_DIA'; observacion = '';

  async ngOnInit() { await this.recargar(); }

  async recargar() {
    try {
      const [m, r, p, l] = await Promise.all([
        this.api.lista<Merma>('v_mermas', { orden: 'id_merma', asc: false, limite: 40 }),
        this.api.rpc<ResumenMerma[]>('fn_reporte_mermas', { p_desde: inicioMes(), p_hasta: hoy() }),
        this.api.lista<ProductoVenta>('v_productos_venta', { orden: 'id_producto' }),
        this.api.lista<Lote>('v_lotes_vigentes', { orden: 'fecha_vencimiento' }),
      ]);
      this.mermas.set(m); this.resumen.set(r); this.productos.set(p); this.lotes.set(l);
      this.idProducto ||= this.elaborados()[0]?.id_producto ?? 0;
      this.idLote ||= l[0]?.id_lote ?? 0;
    } catch (e) { this.aviso.error(e); }
  }

  async registrar() {
    try {
      await this.api.rpc('fn_registrar_merma', {
        p_motivo: this.motivo, p_cantidad: Number(this.cantidad),
        p_id_lote: this.origen() === 'INSUMO' ? this.idLote : null,
        p_id_producto: this.origen() === 'PRODUCTO' ? this.idProducto : null,
        p_observacion: this.observacion || null,
      });
      this.aviso.ok('Merma registrada y descontada del inventario');
      this.cantidad = null; this.observacion = '';
      await this.recargar();
    } catch (e) { this.aviso.error(e); }
  }
}
