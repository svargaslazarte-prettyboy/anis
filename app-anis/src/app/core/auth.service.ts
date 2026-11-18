import { Injectable, inject, signal } from '@angular/core';
import { Session } from '@supabase/supabase-js';
import { ApiService } from './api.service';

@Injectable({ providedIn: 'root' })
export class AuthService {
  private api = inject(ApiService);
  readonly sesion = signal<Session | null>(null);
  readonly lista: Promise<void>;

  constructor() {
    this.lista = this.api.sb.auth.getSession().then(({ data }) => this.sesion.set(data.session));
    this.api.sb.auth.onAuthStateChange((_evento, sesion) => this.sesion.set(sesion));
  }

  async ingresar(email: string, password: string): Promise<void> {
    const { error } = await this.api.sb.auth.signInWithPassword({ email, password });
    if (error) throw new Error(error.message === 'Invalid login credentials' ? 'Correo o contraseña incorrectos' : error.message);
  }

  async salir(): Promise<void> {
    await this.api.sb.auth.signOut();
  }
}
