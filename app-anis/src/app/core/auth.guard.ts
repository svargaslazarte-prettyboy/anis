import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from './auth.service';

export const authGuard: CanActivateFn = async () => {
  // inject() debe llamarse antes de cualquier await (contexto de inyección)
  const auth = inject(AuthService);
  const router = inject(Router);
  await auth.lista;
  return auth.sesion() ? true : router.createUrlTree(['/login']);
};
