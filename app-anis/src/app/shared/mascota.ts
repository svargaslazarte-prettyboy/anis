import { Component, input } from '@angular/core';

/** Humintita: mascota del sistema (dibujo propio en SVG) */
@Component({
  selector: 'app-mascota',
  template: `
  <svg [attr.width]="tam()" [attr.height]="tam()" viewBox="0 0 120 120" role="img" aria-label="Humintita">
    <ellipse cx="60" cy="110" rx="30" ry="5" fill="rgba(13,74,110,.15)"/>
    <path d="M40 22 L60 8 L80 22 Z" fill="#e9c35a" stroke="#b98a00" stroke-width="2.5" stroke-linejoin="round"/>
    <rect x="30" y="20" width="60" height="84" rx="14" fill="#f6d36b" stroke="#b98a00" stroke-width="3"/>
    <path d="M42 24 V100 M60 22 V102 M78 24 V100" stroke="#e8bc45" stroke-width="2.2" stroke-linecap="round"/>
    <rect x="28" y="72" width="64" height="8" rx="4" fill="#d9b26a" stroke="#a87d2b" stroke-width="1.5"/>
    <path d="M60 76 l-10 -7 v14 z M60 76 l10 -7 v14 z" fill="#d9b26a" stroke="#a87d2b" stroke-width="1.5" stroke-linejoin="round"/>
    <ellipse cx="47" cy="48" rx="5" ry="6.5" fill="#3b2a12"/>
    <ellipse cx="73" cy="48" rx="5" ry="6.5" fill="#3b2a12"/>
    <circle cx="49" cy="45.5" r="1.8" fill="#fff"/>
    <circle cx="75" cy="45.5" r="1.8" fill="#fff"/>
    <ellipse cx="40" cy="59" rx="5" ry="3" fill="#f59e8b" opacity=".75"/>
    <ellipse cx="80" cy="59" rx="5" ry="3" fill="#f59e8b" opacity=".75"/>
    <path d="M51 58 Q60 68 69 58" fill="#c2410c" stroke="#3b2a12" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="M30 60 Q20 56 17 46" fill="none" stroke="#b98a00" stroke-width="3.5" stroke-linecap="round"/>
    <path d="M90 60 Q100 56 103 46" fill="none" stroke="#b98a00" stroke-width="3.5" stroke-linecap="round"/>
  </svg>`,
})
export class Mascota {
  readonly tam = input(64);
}
