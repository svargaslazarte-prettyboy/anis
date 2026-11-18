import { Injectable } from '@angular/core';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { environment } from '../../environments/environment';

type Operador = 'eq' | 'neq' | 'gt' | 'gte' | 'lt' | 'lte' | 'in';
export type Filtro = [columna: string, operador: Operador, valor: unknown];

export interface OpcionesLista {
  filtros?: Filtro[];
  orden?: string;
  asc?: boolean;
  limite?: number;
}

/** Acceso a la base de datos (Supabase / PostgREST). Toda la lógica de negocio vive en PostgreSQL. */
@Injectable({ providedIn: 'root' })
export class ApiService {
  readonly sb: SupabaseClient = createClient(environment.supabaseUrl, environment.supabaseAnonKey, {
    auth: { persistSession: true, autoRefreshToken: true, storageKey: 'anis-sesion' },
  });

  private async resolver<T>(consulta: PromiseLike<{ data: unknown; error: { message: string } | null }>): Promise<T> {
    const { data, error } = await consulta;
    if (error) throw new Error(error.message);
    return data as T;
  }

  /** Llama a una función de PostgreSQL (fn_registrar_venta, fn_cerrar_dia, ...) */
  rpc<T>(funcion: string, parametros: Record<string, unknown> = {}): Promise<T> {
    return this.resolver<T>(this.sb.rpc(funcion, parametros));
  }

  /** Lee filas de una tabla o vista */
  lista<T>(tabla: string, op: OpcionesLista = {}): Promise<T[]> {
    let q: any = this.sb.from(tabla).select('*');
    for (const [col, oper, valor] of op.filtros ?? []) {
      q = oper === 'in' ? q.in(col, valor as unknown[]) : q[oper](col, valor);
    }
    if (op.orden) q = q.order(op.orden, { ascending: op.asc ?? true });
    if (op.limite) q = q.limit(op.limite);
    return this.resolver<T[]>(q);
  }

  insertar<T>(tabla: string, fila: Record<string, unknown>): Promise<T> {
    return this.resolver<T>(this.sb.from(tabla).insert(fila).select().single());
  }

  actualizar<T>(tabla: string, cambios: Record<string, unknown>, columnaId: string, id: unknown): Promise<T> {
    return this.resolver<T>(this.sb.from(tabla).update(cambios).eq(columnaId, id).select().single());
  }
}
