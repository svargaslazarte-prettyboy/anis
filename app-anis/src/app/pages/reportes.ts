import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../core/api.service';
import { AvisoService } from '../core/aviso.service';
import { BsPipe, FechaPipe, hoy, sumarDias } from '../core/formato';
import { ReporteProducto, VentaDiaria } from '../core/modelos';
import { Barra, GraficoBarras } from '../shared/grafico-barras';

interface VentaHora { hora: number; nro_ventas: number; total: number; }
interface ResumenMerma { motivo: string; origen: string; registros: number; costo: number; }

@Component({
  selector: 'app-reportes',
  imports: [FormsModule, BsPipe, FechaPipe, GraficoBarras],
  template: `
  <div class="encabezado">
    <div><h1>Reportes</h1><p>Información para decidir: qué se vende, cuánto se gana y cuánto se pierde</p></div>
    <div class="fila-form no-imprimir" style="min-width:420px;margin:0">
      <label class="campo">Desde<input type="date" [(ngModel)]="desde" (change)="cargar()"></label>
      <label class="campo">Hasta<input type="date" [(ngModel)]="hasta" (change)="cargar()"></label>
      <button class="btn claro" style="align-self:end" (click)="imprimir()">🖨️ Imprimir</button>
    </div>
  </div>
  <div class="grid g4">
    <div class="tarjeta kpi"><div class="icono">💵</div><div><div class="valor">{{ ingresos() | bs }}</div><div class="etiqueta">Ventas del periodo</div></div></div>
    <div class="tarjeta kpi amarillo"><div class="icono">📈</div><div><div class="valor">{{ ganancia() | bs }}</div><div class="etiqueta">Ganancia bruta (sin insumos)</div></div></div>
    <div class="tarjeta kpi"><div class="icono">🧾</div><div><div class="valor">{{ nroVentas() }}</div><div class="etiqueta">Ventas · promedio {{ ingresos() / (dias().length || 1) | bs }}/día</div></div></div>
    <div class="tarjeta kpi amarillo"><div class="icono">♻️</div><div><div class="valor">{{ totalMermas() | bs }}</div><div class="etiqueta">Pérdida por mermas ({{ pctMerma() }} % de lo vendido)</div></div></div>
  </div>
  <div class="grid g2 mt">
    <div class="tarjeta"><h2>Ventas por día</h2><app-grafico-barras [barras]="barrasDias()" /></div>
    <div class="tarjeta"><h2>Ventas por hora</h2><app-grafico-barras [barras]="barrasHoras()" /></div>
  </div>
  <div class="tarjeta mt">
    <h2>Rentabilidad por producto</h2>
    <div class="tabla-wrap"><table>
      <thead><tr><th>Producto</th><th>Categoría</th><th class="num">Unidades</th><th class="num">Ingresos</th><th class="num">Costo insumos</th><th class="num">Ganancia</th><th class="num">Margen</th><th class="num">% ventas</th></tr></thead>
      <tbody>
        @for (p of productos(); track p.producto) {
          <tr><td><b>{{ p.producto }}</b></td><td>{{ p.categoria }}</td><td class="num">{{ p.unidades }}</td><td class="num">{{ p.ingresos | bs }}</td>
            <td class="num">{{ p.costo | bs }}</td><td class="num"><b>{{ p.ganancia | bs }}</b></td>
            <td class="num"><span class="chip" [class.ok]="p.margen_pct >= 50" [class.bajo]="p.margen_pct < 50">{{ p.margen_pct }} %</span></td>
            <td class="num">{{ p.participacion_pct }} %</td></tr>
        }
      </tbody>
    </table></div>
  </div>
  <div class="tarjeta mt">
    <h2>Mermas por motivo</h2>
    <div class="tabla-wrap"><table>
      <thead><tr><th>Motivo</th><th>Origen</th><th class="num">Registros</th><th class="num">Costo perdido</th></tr></thead>
      <tbody>
        @for (m of mermas(); track m.motivo + m.origen) {
          <tr><td>{{ m.motivo }}</td><td>{{ m.origen }}</td><td class="num">{{ m.registros }}</td><td class="num">{{ m.costo | bs }}</td></tr>
        }
      </tbody>
    </table></div>
    <p class="muted peq">Periodo: {{ desde | fecha }} al {{ hasta | fecha }}</p>
  </div>`,
})
export class Reportes implements OnInit {
  private api = inject(ApiService);
  private aviso = inject(AvisoService);
  desde = sumarDias(hoy(), -30);
  hasta = hoy();
  readonly dias = signal<VentaDiaria[]>([]);
  readonly horas = signal<VentaHora[]>([]);
  readonly productos = signal<ReporteProducto[]>([]);
  readonly mermas = signal<ResumenMerma[]>([]);
  readonly ingresos = computed(() => this.dias().reduce((s, d) => s + Number(d.total_vendido), 0));
  readonly nroVentas = computed(() => this.dias().reduce((s, d) => s + Number(d.nro_ventas), 0));
  readonly ganancia = computed(() => this.productos().reduce((s, p) => s + Number(p.ganancia), 0));
  readonly totalMermas = computed(() => this.mermas().reduce((s, m) => s + Number(m.costo), 0));
  readonly pctMerma = computed(() => this.ingresos() ? (100 * this.totalMermas() / this.ingresos()).toFixed(1) : '0');
  readonly barrasDias = computed<Barra[]>(() => this.dias().map(d => ({ etiqueta: d.fecha.slice(8) + '/' + d.fecha.slice(5, 7), valor: Number(d.total_vendido) })));
  readonly barrasHoras = computed<Barra[]>(() => this.horas().map(h => ({ etiqueta: h.hora + 'h', valor: Number(h.total), detalle: h.nro_ventas + ' ventas' })));

  async ngOnInit() { await this.cargar(); }

  async cargar() {
    try {
      const r = { p_desde: this.desde, p_hasta: this.hasta };
      const [d, h, p, m] = await Promise.all([
        this.api.lista<VentaDiaria>('v_ventas_diarias', { filtros: [['fecha', 'gte', this.desde], ['fecha', 'lte', this.hasta]], orden: 'fecha' }),
        this.api.rpc<VentaHora[]>('fn_reporte_ventas_hora', r),
        this.api.rpc<ReporteProducto[]>('fn_reporte_productos', r),
        this.api.rpc<ResumenMerma[]>('fn_reporte_mermas', r),
      ]);
      this.dias.set(d); this.horas.set(h); this.productos.set(p); this.mermas.set(m);
    } catch (e) { this.aviso.error(e); }
  }

  imprimir() { window.print(); }
}
