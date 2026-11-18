import { Component, inject } from '@angular/core';
import { Router, RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { AvisoService } from '../core/aviso.service';
import { FechaPipe, hoy } from '../core/formato';
import { Mascota } from '../shared/mascota';

@Component({
  selector: 'app-shell',
  imports: [RouterOutlet, RouterLink, RouterLinkActive, Mascota, FechaPipe],
  templateUrl: './shell.html',
  styleUrl: './shell.scss',
})
export class Shell {
  protected auth = inject(AuthService);
  protected avisos = inject(AvisoService);
  private router = inject(Router);
  protected readonly hoy = hoy();

  protected readonly menu = [
    { ruta: '/inicio', icono: '🏠', texto: 'Inicio' },
    { ruta: '/ventas', icono: '🧾', texto: 'Ventas' },
    { ruta: '/produccion', icono: '🌽', texto: 'Producción' },
    { ruta: '/inventario', icono: '📦', texto: 'Inventario' },
    { ruta: '/entregas', icono: '🚚', texto: 'Entregas' },
    { ruta: '/mermas', icono: '♻️', texto: 'Mermas' },
    { ruta: '/proveedores', icono: '🤝', texto: 'Proveedores' },
    { ruta: '/reportes', icono: '📊', texto: 'Reportes' },
    { ruta: '/caja', icono: '💰', texto: 'Cierre de caja' },
  ];

  async salir() {
    await this.auth.salir();
    this.router.navigateByUrl('/login');
  }
}
