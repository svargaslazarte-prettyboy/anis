import { Pipe, PipeTransform } from '@angular/core';

const ZONA = 'America/La_Paz';
const numero = new Intl.NumberFormat('es-BO', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/** Fecha de hoy en Bolivia en formato YYYY-MM-DD */
export function hoy(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: ZONA }).format(new Date());
}

/** Suma (o resta) días a una fecha YYYY-MM-DD */
export function sumarDias(fecha: string, dias: number): string {
  const d = new Date(fecha + 'T12:00:00Z');
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

export function inicioMes(fecha = hoy()): string {
  return fecha.slice(0, 8) + '01';
}

export function bs(valor: number | string | null | undefined): string {
  return 'Bs ' + numero.format(Number(valor ?? 0));
}

/** Formatea montos en bolivianos: 1234.5 -> "Bs 1.234,50" */
@Pipe({ name: 'bs' })
export class BsPipe implements PipeTransform {
  transform(valor: number | string | null | undefined): string {
    return bs(valor);
  }
}

/** Formatea fechas/horas en hora de Bolivia */
@Pipe({ name: 'fecha' })
export class FechaPipe implements PipeTransform {
  transform(valor: string | null | undefined, modo: 'fecha' | 'hora' | 'completa' | 'corta' = 'fecha'): string {
    if (!valor) return '—';
    const soloFecha = /^\d{4}-\d{2}-\d{2}$/.test(valor);
    const d = new Date(soloFecha ? valor + 'T12:00:00Z' : valor);
    const zona = soloFecha ? 'UTC' : ZONA;
    const op: Intl.DateTimeFormatOptions =
      modo === 'hora' ? { hour: '2-digit', minute: '2-digit', hour12: false }
      : modo === 'completa' ? { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false }
      : modo === 'corta' ? { day: '2-digit', month: 'short' }
      : { weekday: 'short', day: '2-digit', month: '2-digit', year: 'numeric' };
    return new Intl.DateTimeFormat('es-BO', { ...op, timeZone: zona }).format(d);
  }
}

/** Cantidades con unidad, sin ceros de más: 2.500 KG -> "2,5 KG" */
@Pipe({ name: 'cant' })
export class CantidadPipe implements PipeTransform {
  transform(valor: number | string | null | undefined, unidad = ''): string {
    const n = new Intl.NumberFormat('es-BO', { maximumFractionDigits: 3 }).format(Number(valor ?? 0));
    return unidad ? `${n} ${unidad}` : n;
  }
}
