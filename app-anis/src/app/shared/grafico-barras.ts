import { Component, computed, input } from '@angular/core';
import { bs } from '../core/formato';

export interface Barra { etiqueta: string; valor: number; detalle?: string; }

/** Gráfico de barras simple en SVG (sin librerías) */
@Component({
  selector: 'app-grafico-barras',
  template: `
  @if (barras().length) {
    <svg [attr.viewBox]="'0 0 ' + ancho + ' ' + alto" class="grafico" preserveAspectRatio="none">
      @for (l of lineas(); track l.y) {
        <line [attr.x1]="40" [attr.x2]="ancho" [attr.y1]="l.y" [attr.y2]="l.y" stroke="#e6eef4"/>
        <text x="36" [attr.y]="l.y + 4" text-anchor="end" font-size="10" fill="#7b8a97">{{ l.texto }}</text>
      }
      @for (b of geometria(); track $index) {
        <rect [attr.x]="b.x" [attr.y]="b.y" [attr.width]="b.w" [attr.height]="b.h" rx="4" [attr.fill]="b.color">
          <title>{{ b.titulo }}</title>
        </rect>
        @if (b.mostrarEtiqueta) {
          <text [attr.x]="b.x + b.w / 2" [attr.y]="alto - 6" text-anchor="middle" font-size="10" fill="#5b6b78">{{ b.etiqueta }}</text>
        }
      }
    </svg>
  } @else {
    <div class="vacio">Sin datos para mostrar</div>
  }`,
  styles: `.grafico { width: 100%; height: 220px; display: block; }`,
})
export class GraficoBarras {
  readonly barras = input<Barra[]>([]);
  readonly moneda = input(true);
  readonly destacarUltima = input(false);
  readonly ancho = 640;
  readonly alto = 220;

  private readonly maximo = computed(() => Math.max(1, ...this.barras().map(b => b.valor)) * 1.1);

  readonly lineas = computed(() => {
    const max = this.maximo();
    return [0, 0.25, 0.5, 0.75, 1].map(f => ({
      y: 10 + (this.alto - 34) * (1 - f),
      texto: this.moneda() ? Math.round(max * f).toLocaleString('es-BO') : Math.round(max * f).toString(),
    }));
  });

  readonly geometria = computed(() => {
    const lista = this.barras();
    const n = lista.length;
    const area = this.ancho - 48;
    const paso = area / n;
    const w = Math.max(4, paso * 0.68);
    const cada = Math.ceil(n / 14);
    return lista.map((b, i) => {
      const h = ((this.alto - 34) * b.valor) / this.maximo();
      return {
        x: 46 + i * paso + (paso - w) / 2, y: this.alto - 24 - h, w, h,
        etiqueta: b.etiqueta, mostrarEtiqueta: i % cada === 0,
        color: this.destacarUltima() && i === n - 1 ? '#f5c518' : '#2b8fbd',
        titulo: `${b.etiqueta}: ${this.moneda() ? bs(b.valor) : b.valor}${b.detalle ? ' · ' + b.detalle : ''}`,
      };
    });
  });
}
