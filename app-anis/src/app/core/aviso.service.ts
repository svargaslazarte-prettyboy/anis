import { Injectable, signal } from '@angular/core';

export interface Aviso { id: number; texto: string; tipo: 'ok' | 'error'; }

/** Mensajes breves (toasts) en la esquina de la pantalla */
@Injectable({ providedIn: 'root' })
export class AvisoService {
  readonly avisos = signal<Aviso[]>([]);
  private n = 0;

  ok(texto: string) { this.mostrar(texto, 'ok'); }
  error(e: unknown) { this.mostrar(e instanceof Error ? e.message : String(e), 'error'); }

  private mostrar(texto: string, tipo: Aviso['tipo']) {
    const id = ++this.n;
    this.avisos.update(l => [...l, { id, texto, tipo }]);
    setTimeout(() => this.avisos.update(l => l.filter(a => a.id !== id)), tipo === 'error' ? 6500 : 3500);
  }
}
