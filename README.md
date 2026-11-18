# Anis · La Casa de la Huminta — Sistema de ventas e inventario

Proyecto final de **Base de Datos II (UPDS)**. Base de datos PostgreSQL (Supabase) + aplicación web Angular.

## Contenido

| Carpeta / archivo | Qué es |
|---|---|
| `documentos/Informe_Proyecto_Anis.docx` (y `.pdf`) | Informe: portada, caso, problema, objetivos y anexos con todas las evidencias |
| `documentos/Entrevista_completada.pdf` | Entrevista de 29 preguntas completada |
| `documentos/Modelo_ER_Anis.png` | Diagrama entidad–relación (20 tablas, 29 relaciones) |
| `documentos/capturas/` | 36 capturas: 20 de SQL y 16 de la app |
| `documentos/evidencias/` | Fotos de la visita al local |
| `base_de_datos/` | Scripts SQL (ver orden abajo) |
| `app-anis/` | Aplicación web Angular 22 |
| `servidor-local/` | Imitación local de la API de Supabase (para trabajar sin internet) |

## 1. Base de datos en Supabase

En **Supabase → SQL Editor**, ejecutar en este orden (cada archivo completo):

1. `01_esquema.sql` — 20 tablas, restricciones, funciones, procedimientos, disparadores y vistas
2. `02_datos_prueba.sql` — catálogos reales del local y ~10 semanas de operación simulada hasta HOY
3. `03_consultas_negocio.sql` — las 10 consultas (se pueden ejecutar una por una)
4. `04_plan_indices.sql` — índices con medición antes/después (`EXPLAIN ANALYZE`)
5. `05_transacciones.sql` — COMMIT, ROLLBACK y SAVEPOINT (ejecutar bloque por bloque)
6. `06_supabase_seguridad.sql` — Row Level Security (solo en Supabase)

Antes del paso 6, crear la usuaria en **Authentication → Users** con el email `admin@anis.bo`
(o cambiar el email: `UPDATE usuario SET email = 'otro@correo.com' WHERE id_usuario = 1;`).

## 2. Aplicación Angular

En `app-anis/src/environments/environment.ts` poner la **Project URL** y la **anon key** de Supabase
(Project Settings → API). Luego:

```bash
cd app-anis
```

```bash
npm install
```

```bash
npm start
```

Abrir http://localhost:4200 e ingresar con el usuario creado en Supabase.

## 3. Modo local (sin internet, opcional)

Requiere PostgreSQL instalado. Crear la base `anis_huminta`, ejecutar los scripts 01, 02 y 04, compilar la app
y levantar el servidor local:

```bash
cd app-anis && npm run build
```

```bash
cd servidor-local && npm install && npm start
```

Abrir http://localhost:54321 · usuario `admin@anis.bo` · contraseña `anis2026`.
(Si PostgreSQL pide usuario y clave: `DATABASE_URL=postgres://usuario:clave@localhost:5432/anis_huminta npm start`.)
