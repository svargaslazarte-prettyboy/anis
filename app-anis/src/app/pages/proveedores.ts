import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ApiService } from '../core/api.service';
import { AvisoService } from '../core/aviso.service';
import { BsPipe } from '../core/formato';
import { Proveedor, ProveedorInsumo } from '../core/modelos';

type Edicion = Omit<Proveedor, 'id_proveedor' | 'activo'> & { id_proveedor?: number };

@Component({
  selector: 'app-proveedores',
  imports: [FormsModule, BsPipe],
  template: `
  <div class="encabezado">
    <div><h1>Proveedores</h1><p>Quién entrega cada insumo, en qué días y a qué precio de referencia</p></div>
    <button class="btn amarillo" (click)="nuevo()">＋ Nuevo proveedor</button>
  </div>
  @if (edicion) {
    <div class="tarjeta">
      <h2>{{ edicion.id_proveedor ? 'Editar proveedor' : 'Nuevo proveedor' }}</h2>
      <div class="fila-form mt-s">
        <label class="campo">Razón social<input [(ngModel)]="edicion.razon_social"></label>
        <label class="campo">NIT<input [(ngModel)]="edicion.nit"></label>
        <label class="campo">Contacto<input [(ngModel)]="edicion.nombre_contacto"></label>
        <label class="campo">Teléfono<input [(ngModel)]="edicion.telefono"></label>
        <label class="campo">Días de entrega<input [(ngModel)]="edicion.dias_entrega" placeholder="Ej.: Martes y viernes"></label>
        <label class="campo">Dirección<input [(ngModel)]="edicion.direccion"></label>
      </div>
      <button class="btn" (click)="guardar()">Guardar</button> <button class="btn claro" (click)="edicion = null">Cancelar</button>
    </div>
  }
  <div class="grid g2 mt">
    @for (p of proveedores(); track p.id_proveedor) {
      <div class="tarjeta">
        <div class="tarjeta-cab">
          <div><h3>{{ p.razon_social }}</h3><div class="muted peq">{{ p.nombre_contacto }} · ☎ {{ p.telefono }} · NIT {{ p.nit || 's/n' }}</div></div>
          <button class="btn claro chico" (click)="editar(p)">Editar</button>
        </div>
        <span class="chip amarillo">🚚 {{ p.dias_entrega }}</span>
        <table class="mt-s">
          @for (i of insumosDe(p.id_proveedor); track i.id_insumo) {
            <tr><td>{{ i.insumo }} @if (!i.es_principal) { <span class="chip info">alternativo</span> }</td>
              <td class="num">{{ i.precio_referencia | bs }} / {{ i.unidad }}</td></tr>
          }
        </table>
      </div>
    }
  </div>`,
})
export class Proveedores implements OnInit {
  private api = inject(ApiService);
  private aviso = inject(AvisoService);
  readonly proveedores = signal<Proveedor[]>([]);
  readonly insumos = signal<ProveedorInsumo[]>([]);
  edicion: Edicion | null = null;

  async ngOnInit() { await this.recargar(); }

  async recargar() {
    try {
      const [p, i] = await Promise.all([
        this.api.lista<Proveedor>('proveedor', { orden: 'razon_social' }),
        this.api.lista<ProveedorInsumo>('v_proveedor_insumo', { orden: 'insumo' }),
      ]);
      this.proveedores.set(p); this.insumos.set(i);
    } catch (e) { this.aviso.error(e); }
  }

  insumosDe(id: number) { return this.insumos().filter(i => i.id_proveedor === id); }

  nuevo() { this.edicion = { razon_social: '', nit: '', nombre_contacto: '', telefono: '', direccion: '', dias_entrega: '' }; }

  editar(p: Proveedor) { const { activo, ...resto } = p; this.edicion = { ...resto }; }

  async guardar() {
    const { id_proveedor, ...datos } = this.edicion!;
    const limpio = Object.fromEntries(Object.entries(datos).map(([k, v]) => [k, typeof v === 'string' && !v.trim() && k !== 'razon_social' ? null : v]));
    try {
      if (id_proveedor) await this.api.actualizar('proveedor', limpio, 'id_proveedor', id_proveedor);
      else await this.api.insertar('proveedor', limpio);
      this.aviso.ok('Proveedor guardado');
      this.edicion = null;
      await this.recargar();
    } catch (e) { this.aviso.error(e); }
  }
}
