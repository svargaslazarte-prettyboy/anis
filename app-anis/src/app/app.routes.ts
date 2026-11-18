import { Routes } from '@angular/router';
import { authGuard } from './core/auth.guard';
import { Shell } from './layout/shell';

export const routes: Routes = [
  { path: 'login', loadComponent: () => import('./pages/login').then(m => m.Login), title: 'Ingresar · Anis' },
  {
    path: '',
    component: Shell,
    canActivate: [authGuard],
    children: [
      { path: '', pathMatch: 'full', redirectTo: 'inicio' },
      { path: 'inicio', loadComponent: () => import('./pages/inicio').then(m => m.Inicio), title: 'Inicio · Anis' },
      { path: 'ventas', loadComponent: () => import('./pages/ventas').then(m => m.Ventas), title: 'Ventas · Anis' },
      { path: 'produccion', loadComponent: () => import('./pages/produccion').then(m => m.ProduccionPage), title: 'Producción · Anis' },
      { path: 'inventario', loadComponent: () => import('./pages/inventario').then(m => m.Inventario), title: 'Inventario · Anis' },
      { path: 'entregas', loadComponent: () => import('./pages/entregas').then(m => m.Entregas), title: 'Entregas · Anis' },
      { path: 'mermas', loadComponent: () => import('./pages/mermas').then(m => m.Mermas), title: 'Mermas · Anis' },
      { path: 'proveedores', loadComponent: () => import('./pages/proveedores').then(m => m.Proveedores), title: 'Proveedores · Anis' },
      { path: 'reportes', loadComponent: () => import('./pages/reportes').then(m => m.Reportes), title: 'Reportes · Anis' },
      { path: 'caja', loadComponent: () => import('./pages/caja').then(m => m.Caja), title: 'Cierre de caja · Anis' },
    ],
  },
  { path: '**', redirectTo: '' },
];
