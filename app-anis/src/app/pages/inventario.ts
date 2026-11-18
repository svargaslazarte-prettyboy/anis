import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../core/api.service';
import { AvisoService } from '../core/aviso.service';
import { BsPipe, CantidadPipe, FechaPipe } from '../core/formato';
import { Kardex, Lote, StockInsumo } from '../core/modelos';

@Component({
  selector: 'app-inventario',
  imports: [FormsModule, BsPipe, CantidadPipe, FechaPipe],
  templateUrl: './inventario.html',
})
export class Inventario implements OnInit {
  private api = inject(ApiService);
  private aviso = inject(AvisoService);
  readonly pestana = signal<'stock' | 'lotes' | 'kardex'>('stock');
  readonly stock = signal<StockInsumo[]>([]);
  readonly lotes = signal<Lote[]>([]);
  readonly kardex = signal<Kardex[]>([]);
  readonly valorTotal = computed(() => this.stock().reduce((s, x) => s + Number(x.valor_inventario), 0));
  readonly alertas = computed(() => this.stock().filter(s => s.estado !== 'OK').length);
  insumoKardex = '';

  async ngOnInit() { await this.recargar(); }

  async recargar() {
    try {
      const [s, l] = await Promise.all([
        this.api.lista<StockInsumo>('v_stock_insumo', { orden: 'nombre' }),
        this.api.lista<Lote>('v_lotes_vigentes', { orden: 'fecha_vencimiento' }),
      ]);
      this.stock.set(s);
      this.lotes.set(l);
      await this.cargarKardex();
    } catch (e) { this.aviso.error(e); }
  }

  async cargarKardex() {
    const filtros = this.insumoKardex ? [['codigo_insumo', 'eq', this.insumoKardex] as [string, 'eq', string]] : [];
    this.kardex.set(await this.api.lista<Kardex>('v_kardex', { filtros, orden: 'id_movimiento', asc: false, limite: 80 }));
  }

  porcentaje(s: StockInsumo) {
    return Math.min(100, (100 * Number(s.stock_actual)) / Math.max(Number(s.stock_minimo) * 3, 0.001));
  }

  async darDeBajaVencidos() {
    try {
      const n = await this.api.rpc<number>('fn_procesar_vencidos');
      this.aviso.ok(n ? `${n} lote(s) vencido(s) registrados como merma` : 'No hay lotes vencidos con saldo');
      await this.recargar();
    } catch (e) { this.aviso.error(e); }
  }
}
