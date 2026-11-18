import { Component, OnInit, inject, signal } from '@angular/core';
import { RouterLink } from '@angular/router';
import { ApiService } from '../core/api.service';
import { AvisoService } from '../core/aviso.service';
import { BsPipe, CantidadPipe, hoy, inicioMes, sumarDias } from '../core/formato';
import { Lote, ReporteProducto, StockInsumo, Tablero, VentaDiaria } from '../core/modelos';
import { Barra, GraficoBarras } from '../shared/grafico-barras';
import { Mascota } from '../shared/mascota';

@Component({
  selector: 'app-inicio',
  imports: [BsPipe, CantidadPipe, GraficoBarras, Mascota, RouterLink],
  templateUrl: './inicio.html',
})
export class Inicio implements OnInit {
  private api = inject(ApiService);
  private aviso = inject(AvisoService);

  readonly t = signal<Tablero | null>(null);
  readonly alertasStock = signal<StockInsumo[]>([]);
  readonly porVencer = signal<Lote[]>([]);
  readonly barras = signal<Barra[]>([]);
  readonly top = signal<ReporteProducto[]>([]);

  async ngOnInit() {
    const h = hoy();
    try {
      const [t, stock, lotes, dias, top] = await Promise.all([
        this.api.rpc<Tablero>('fn_resumen_tablero'),
        this.api.lista<StockInsumo>('v_stock_insumo', { filtros: [['estado', 'neq', 'OK']], orden: 'stock_actual' }),
        this.api.lista<Lote>('v_lotes_vigentes', { filtros: [['dias_para_vencer', 'lte', 3]], orden: 'fecha_vencimiento' }),
        this.api.lista<VentaDiaria>('v_ventas_diarias', { filtros: [['fecha', 'gte', sumarDias(h, -20)]], orden: 'fecha' }),
        this.api.rpc<ReporteProducto[]>('fn_reporte_productos', { p_desde: inicioMes(h), p_hasta: h }),
      ]);
      this.t.set(t);
      this.alertasStock.set(stock);
      this.porVencer.set(lotes);
      this.barras.set(dias.map(d => ({ etiqueta: d.fecha.slice(8) + '/' + d.fecha.slice(5, 7), valor: Number(d.total_vendido), detalle: d.nro_ventas + ' ventas' })));
      this.top.set(top.slice(0, 6));
    } catch (e) {
      this.aviso.error(e);
    }
  }

  ancho(p: ReporteProducto): number {
    const max = Math.max(...this.top().map(x => Number(x.ingresos)));
    return (100 * Number(p.ingresos)) / max;
  }
}
