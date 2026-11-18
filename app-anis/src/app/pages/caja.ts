import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../core/api.service';
import { AvisoService } from '../core/aviso.service';
import { BsPipe, FechaPipe, hoy } from '../core/formato';
import { CierreCaja } from '../core/modelos';

interface ResumenCaja { fecha: string; cantidad_ventas: number; total_efectivo: number; total_qr: number; total: number; cerrada: boolean; }

@Component({
  selector: 'app-caja',
  imports: [FormsModule, BsPipe, FechaPipe],
  template: `
  <div class="encabezado">
    <div><h1>Cierre de caja</h1><p>Compare el efectivo contado con lo que registró el sistema</p></div>
  </div>
  @if (r(); as r) {
    <div class="grid g2">
      <div class="tarjeta">
        <h2>Caja de hoy · {{ r.fecha | fecha }}</h2>
        <div class="grid g3 mt-s">
          <div><div class="muted">Ventas</div><div class="total-grande">{{ r.cantidad_ventas }}</div></div>
          <div><div class="muted">💵 Efectivo</div><div class="total-grande">{{ r.total_efectivo | bs }}</div></div>
          <div><div class="muted">📱 QR</div><div class="total-grande">{{ r.total_qr | bs }}</div></div>
        </div>
        <hr class="separador">
        @if (r.cerrada) {
          <div class="ok-box">✅ La caja de hoy ya fue cerrada.</div>
        } @else {
          <div class="fila-form">
            <label class="campo">Monto de apertura (cambio)<input type="number" min="0" [(ngModel)]="apertura"></label>
            <label class="campo">Efectivo contado<input type="number" min="0" [(ngModel)]="contado" placeholder="Cuente la caja"></label>
          </div>
          @if (contado !== null) {
            <p>Debería haber <b>{{ esperado | bs }}</b> en caja. Diferencia:
              <b [style.color]="diferencia === 0 ? 'var(--ok)' : 'var(--error)'">{{ diferencia | bs }}</b>
              {{ diferencia === 0 ? '✔ cuadra' : diferencia < 0 ? '(falta dinero)' : '(sobra dinero)' }}</p>
          }
          <label class="campo">Observación<input [(ngModel)]="observacion"></label>
          <button class="btn amarillo grande mt" [disabled]="contado === null" (click)="cerrar()">💰 Cerrar el día</button>
          <p class="muted peq">Al cerrar, las humintas y pasteles que quedaron sin vender se registran como merma (sobrante del día).</p>
        }
      </div>
      <div class="tarjeta">
        <h2>Cierres anteriores</h2>
        <div class="tabla-wrap"><table>
          <thead><tr><th>Fecha</th><th class="num">Ventas</th><th class="num">Efectivo</th><th class="num">QR</th><th class="num">Diferencia</th></tr></thead>
          <tbody>
            @for (c of historial(); track c.id_cierre_caja) {
              <tr><td style="white-space:nowrap">{{ c.fecha | fecha }}</td><td class="num">{{ c.cantidad_ventas }}</td><td class="num">{{ c.total_efectivo | bs }}</td>
                <td class="num">{{ c.total_qr | bs }}</td>
                <td class="num"><span class="chip" [class.ok]="+c.diferencia === 0" [class.agotado]="+c.diferencia !== 0">{{ c.diferencia | bs }}</span></td></tr>
            }
          </tbody>
        </table></div>
      </div>
    </div>
  }`,
})
export class Caja implements OnInit {
  private api = inject(ApiService);
  private aviso = inject(AvisoService);
  readonly r = signal<ResumenCaja | null>(null);
  readonly historial = signal<CierreCaja[]>([]);
  apertura = 100;
  contado: number | null = null;
  observacion = '';

  get esperado() { return Number(this.apertura) + Number(this.r()?.total_efectivo ?? 0); }
  get diferencia() { return Math.round((Number(this.contado) - this.esperado) * 100) / 100; }

  async ngOnInit() { await this.recargar(); }

  async recargar() {
    try {
      const [r, h] = await Promise.all([
        this.api.rpc<ResumenCaja>('fn_resumen_caja', { p_fecha: hoy() }),
        this.api.lista<CierreCaja>('cierre_caja', { orden: 'fecha', asc: false, limite: 14 }),
      ]);
      this.r.set(r); this.historial.set(h);
    } catch (e) { this.aviso.error(e); }
  }

  async cerrar() {
    try {
      const res = await this.api.rpc<CierreCaja & { sobrantes_registrados: number }>('fn_cerrar_dia', {
        p_fecha: hoy(), p_efectivo_contado: Number(this.contado), p_monto_apertura: Number(this.apertura),
        p_observacion: this.observacion || null,
      });
      this.aviso.ok(`Caja cerrada. Diferencia: Bs ${res.diferencia}. Sobrantes registrados: ${res.sobrantes_registrados}`);
      this.contado = null;
      await this.recargar();
    } catch (e) { this.aviso.error(e); }
  }
}
