import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../core/auth.service';
import { Mascota } from '../shared/mascota';

@Component({
  selector: 'app-login',
  imports: [FormsModule, Mascota],
  template: `
  <div class="fondo">
    <form class="caja tarjeta" (ngSubmit)="ingresar()">
      <div class="franja"></div>
      <app-mascota [tam]="110" />
      <h1>ANIS</h1>
      <p class="sub">La Casa de la Huminta · Control de ventas e inventario</p>
      <label class="campo">Correo
        <input type="email" name="email" [(ngModel)]="email" autocomplete="username" required>
      </label>
      <label class="campo">Contraseña
        <input type="password" name="password" [(ngModel)]="password" autocomplete="current-password" required>
      </label>
      @if (error()) { <div class="error-msg">{{ error() }}</div> }
      <button class="btn amarillo grande" [disabled]="cargando()">{{ cargando() ? 'Ingresando…' : 'Ingresar' }}</button>
      <p class="nota">Acceso exclusivo de la administradora del local.</p>
    </form>
  </div>`,
  styles: `
    .fondo { min-height: 100vh; display: grid; place-items: center; padding: 20px;
      background: radial-gradient(circle at 20% 20%, #2b8fbd, #0d4a6e 70%); }
    .caja { width: min(420px, 100%); display: grid; gap: 14px; justify-items: center; text-align: center; padding: 0 28px 26px; overflow: hidden; }
    .caja .franja { width: calc(100% + 56px); margin-bottom: 4px; }
    .caja label, .caja button, .caja .error-msg { width: 100%; text-align: left; }
    h1 { font-size: 46px; letter-spacing: 4px; color: #0d4a6e; margin-top: -6px; }
    .sub { margin: -10px 0 4px; color: var(--gris); font-weight: 700; }
    .nota { margin: 0; font-size: 12.5px; color: var(--gris); }`,
})
export class Login {
  private auth = inject(AuthService);
  private router = inject(Router);
  email = 'admin@anis.bo';
  password = '';
  readonly error = signal('');
  readonly cargando = signal(false);

  async ingresar() {
    this.error.set('');
    this.cargando.set(true);
    try {
      await this.auth.ingresar(this.email.trim(), this.password);
      this.router.navigateByUrl('/inicio');
    } catch (e) {
      this.error.set((e as Error).message);
    } finally {
      this.cargando.set(false);
    }
  }
}
