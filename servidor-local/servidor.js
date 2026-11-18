// =====================================================================
//  Anis · Servidor local (modo sin internet)
//  Imita la parte de la API de Supabase que usa la app Angular:
//    - /auth/v1/token, /auth/v1/user, /auth/v1/logout   (inicio de sesión)
//    - /rest/v1/<tabla|vista>   GET / POST / PATCH       (PostgREST)
//    - /rest/v1/rpc/<funcion>   POST                     (funciones SQL)
//  y además sirve la app ya compilada (app-anis/dist).
//
//  Uso:  npm install  &&  npm start      ->  http://localhost:54321
//  Variables opcionales: DATABASE_URL (o PGHOST, PGUSER, PGPASSWORD, PGDATABASE),
//                        PUERTO (54321), CLAVE_LOCAL (contraseña de ingreso: anis2026)
// =====================================================================
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Pool, types } = require('pg');

types.setTypeParser(1700, v => (v === null ? null : parseFloat(v)));   // numeric -> número
types.setTypeParser(20, v => (v === null ? null : parseInt(v, 10)));    // bigint  -> número
types.setTypeParser(1082, v => v);                                      // date    -> 'YYYY-MM-DD'

const PUERTO = Number(process.env.PUERTO || 54321);
const CLAVE = process.env.CLAVE_LOCAL || 'anis2026';
const SECRETO = crypto.randomBytes(32);
const pool = new Pool(process.env.DATABASE_URL
  ? { connectionString: process.env.DATABASE_URL }
  : { host: process.env.PGHOST || (fs.existsSync('/var/run/postgresql') ? '/var/run/postgresql' : 'localhost'),
      database: process.env.PGDATABASE || 'anis_huminta' });
const DIST = path.resolve(__dirname, '../app-anis/dist/app-anis/browser');
const IDENT = /^[a-z_][a-z0-9_]*$/;

// ---------- utilidades ----------
const b64 = o => Buffer.from(JSON.stringify(o)).toString('base64url');
function jwt(payload) {
  const cuerpo = b64({ alg: 'HS256', typ: 'JWT' }) + '.' + b64(payload);
  return cuerpo + '.' + crypto.createHmac('sha256', SECRETO).update(cuerpo).digest('base64url');
}
function leerJwt(token) {
  const [h, p, f] = (token || '').split('.');
  if (!f || crypto.createHmac('sha256', SECRETO).update(h + '.' + p).digest('base64url') !== f) return null;
  const datos = JSON.parse(Buffer.from(p, 'base64url').toString());
  return datos.exp * 1000 > Date.now() ? datos : null;
}
function responder(res, estado, cuerpo, extra = {}) {
  res.writeHead(estado, { 'Content-Type': 'application/json; charset=utf-8', ...extra });
  res.end(cuerpo === undefined ? '' : JSON.stringify(cuerpo));
}
function errorPg(res, e, estado = 400) {
  responder(res, estado, { code: e.code || 'PGRST', message: e.message, details: e.detail || null, hint: e.hint || null });
}
function leerCuerpo(req) {
  return new Promise((ok, mal) => {
    let datos = '';
    req.on('data', c => (datos += c));
    req.on('end', () => { try { ok(datos ? JSON.parse(datos) : {}); } catch (e) { mal(e); } });
  });
}
const valorParam = v => (v !== null && typeof v === 'object' ? JSON.stringify(v) : v);

function sesionPara(usuario) {
  const ahora = Math.floor(Date.now() / 1000);
  const user = { id: usuario.uid, aud: 'authenticated', role: 'authenticated', email: usuario.email,
                 app_metadata: { provider: 'email' }, user_metadata: { nombre: usuario.nombre_completo },
                 created_at: new Date().toISOString() };
  const access_token = jwt({ sub: user.id, email: user.email, role: 'authenticated', aud: 'authenticated', iat: ahora, exp: ahora + 8 * 3600 });
  return { access_token, token_type: 'bearer', expires_in: 8 * 3600, expires_at: ahora + 8 * 3600,
           refresh_token: jwt({ sub: user.id, email: user.email, tipo: 'refresh', exp: ahora + 30 * 86400 }), user };
}
async function buscarUsuario(email) {
  const { rows } = await pool.query(
    `SELECT id_usuario, nombre_completo, email,
            COALESCE(auth_uid::text, '00000000-0000-4000-8000-' || lpad(id_usuario::text, 12, '0')) AS uid
     FROM usuario WHERE activo AND lower(email) = lower($1)`, [email]);
  return rows[0];
}

// ---------- filtros estilo PostgREST: columna=operador.valor ----------
const OPERADORES = { eq: '=', neq: '<>', gt: '>', gte: '>=', lt: '<', lte: '<=', like: 'LIKE', ilike: 'ILIKE' };
function construirWhere(params, valores) {
  const condiciones = [];
  for (const [col, expr] of params) {
    if (['select', 'order', 'limit', 'offset', 'columns'].includes(col)) continue;
    if (!IDENT.test(col)) throw new Error('Columna inválida: ' + col);
    const punto = expr.indexOf('.');
    const op = expr.slice(0, punto), valor = expr.slice(punto + 1);
    if (op === 'is') {
      condiciones.push(`"${col}" IS ${({ null: 'NULL', true: 'TRUE', false: 'FALSE' })[valor] || 'NULL'}`);
    } else if (op === 'in') {
      const lista = valor.replace(/^\(|\)$/g, '').split(',').map(x => x.replace(/^"|"$/g, ''));
      valores.push(lista);
      condiciones.push(`"${col}"::text = ANY($${valores.length})`);
    } else if (OPERADORES[op]) {
      valores.push(op.endsWith('like') ? valor.replace(/\*/g, '%') : valor);
      condiciones.push(`"${col}" ${OPERADORES[op]} $${valores.length}`);
    } else throw new Error('Operador no soportado: ' + op);
  }
  return condiciones.length ? ' WHERE ' + condiciones.join(' AND ') : '';
}
function construirOrden(orden) {
  if (!orden) return '';
  return ' ORDER BY ' + orden.split(',').map(p => {
    const [col, dir, nulos] = p.split('.');
    if (!IDENT.test(col)) throw new Error('Orden inválido');
    return `"${col}" ${dir === 'desc' ? 'DESC' : 'ASC'}${nulos === 'nullsfirst' ? ' NULLS FIRST' : nulos === 'nullslast' ? ' NULLS LAST' : ''}`;
  }).join(', ');
}

// ---------- API REST ----------
async function rest(req, res, url, recurso) {
  const params = [...url.searchParams.entries()];
  const objeto = (req.headers.accept || '').includes('vnd.pgrst.object');
  const devolver = (filas, estado = 200) => {
    if (!objeto) return responder(res, estado, filas);
    if (filas.length !== 1) return responder(res, 406, { code: 'PGRST116', message: 'Se esperaba una sola fila' });
    responder(res, estado, filas[0]);
  };

  if (recurso.startsWith('rpc/')) {
    const fn = recurso.slice(4);
    if (!IDENT.test(fn)) throw new Error('Función inválida');
    const { rows: info } = await pool.query(
      `SELECT proretset, prorettype = 'void'::regtype AS es_void,
              (SELECT typtype = 'c' FROM pg_type WHERE oid = prorettype) AS compuesto
       FROM pg_proc WHERE proname = $1 AND pronamespace = 'public'::regnamespace LIMIT 1`, [fn]);
    if (!info.length) return responder(res, 404, { code: 'PGRST202', message: `No existe la función ${fn}` });
    const cuerpo = await leerCuerpo(req);
    const nombres = Object.keys(cuerpo).filter(k => IDENT.test(k));
    const args = nombres.map((k, i) => `"${k}" => $${i + 1}`).join(', ');
    const valores = nombres.map(k => valorParam(cuerpo[k]));
    const { proretset, es_void, compuesto } = info[0];
    if (proretset || compuesto) {
      const { rows } = await pool.query(`SELECT * FROM public."${fn}"(${args})`, valores);
      return devolver(rows);
    }
    const { rows } = await pool.query(`SELECT public."${fn}"(${args}) AS r`, valores);
    return es_void ? responder(res, 204) : responder(res, 200, rows[0].r);
  }

  if (!IDENT.test(recurso)) throw new Error('Recurso inválido');
  const valores = [];
  if (req.method === 'GET') {
    const select = url.searchParams.get('select') || '*';
    const cols = select === '*' ? '*' : select.split(',').map(c => { if (!IDENT.test(c)) throw new Error('select inválido'); return `"${c}"`; }).join(', ');
    let sql = `SELECT ${cols} FROM public."${recurso}"` + construirWhere(params, valores) + construirOrden(url.searchParams.get('order'));
    if (url.searchParams.get('limit')) sql += ` LIMIT ${parseInt(url.searchParams.get('limit'), 10)}`;
    if (url.searchParams.get('offset')) sql += ` OFFSET ${parseInt(url.searchParams.get('offset'), 10)}`;
    const { rows } = await pool.query(sql, valores);
    return devolver(rows);
  }
  if (req.method === 'POST') {
    const cuerpo = await leerCuerpo(req);
    const filas = Array.isArray(cuerpo) ? cuerpo : [cuerpo];
    const cols = Object.keys(filas[0]).filter(c => IDENT.test(c));
    const tuplas = filas.map(f => '(' + cols.map(c => { valores.push(valorParam(f[c])); return '$' + valores.length; }).join(', ') + ')');
    const { rows } = await pool.query(
      `INSERT INTO public."${recurso}" (${cols.map(c => `"${c}"`).join(', ')}) VALUES ${tuplas.join(', ')} RETURNING *`, valores);
    return (req.headers.prefer || '').includes('return=representation') ? devolver(rows, 201) : responder(res, 201);
  }
  if (req.method === 'PATCH') {
    const cuerpo = await leerCuerpo(req);
    const sets = Object.keys(cuerpo).filter(c => IDENT.test(c)).map(c => { valores.push(valorParam(cuerpo[c])); return `"${c}" = $${valores.length}`; });
    const where = construirWhere(params, valores);
    if (!where) throw new Error('UPDATE sin filtro no permitido');
    const { rows } = await pool.query(`UPDATE public."${recurso}" SET ${sets.join(', ')}${where} RETURNING *`, valores);
    return (req.headers.prefer || '').includes('return=representation') ? devolver(rows) : responder(res, 204);
  }
  responder(res, 405, { message: 'Método no soportado' });
}

// ---------- autenticación ----------
async function auth(req, res, url, ruta) {
  if (ruta === 'token' && req.method === 'POST') {
    const cuerpo = await leerCuerpo(req);
    if (url.searchParams.get('grant_type') === 'refresh_token') {
      const datos = leerJwt(cuerpo.refresh_token);
      const u = datos && (await buscarUsuario(datos.email));
      return u ? responder(res, 200, sesionPara(u)) : responder(res, 400, { error: 'invalid_grant', error_description: 'Sesión expirada' });
    }
    const u = await buscarUsuario(cuerpo.email || '');
    if (!u || cuerpo.password !== CLAVE) {
      return responder(res, 400, { code: 400, error_code: 'invalid_credentials', msg: 'Invalid login credentials',
                                   error: 'invalid_grant', error_description: 'Invalid login credentials' });
    }
    return responder(res, 200, sesionPara(u));
  }
  if (ruta === 'user') {
    const datos = leerJwt((req.headers.authorization || '').replace(/^Bearer /i, ''));
    const u = datos && (await buscarUsuario(datos.email));
    return u ? responder(res, 200, sesionPara(u).user) : responder(res, 401, { code: 401, msg: 'Sesión no válida' });
  }
  if (ruta === 'logout') return responder(res, 204);
  responder(res, 404, { msg: 'No encontrado' });
}

// ---------- archivos de la app compilada ----------
const TIPOS = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
                '.png': 'image/png', '.json': 'application/json', '.txt': 'text/plain' };
function estatico(res, ruta) {
  if (!fs.existsSync(DIST)) return responder(res, 404, { message: 'Compile la app primero: cd app-anis && npm run build' });
  let archivo = path.join(DIST, path.normalize(ruta).replace(/^(\.\.[/\\])+/, ''));
  if (!archivo.startsWith(DIST) || !fs.existsSync(archivo) || fs.statSync(archivo).isDirectory()) archivo = path.join(DIST, 'index.html');
  res.writeHead(200, { 'Content-Type': (TIPOS[path.extname(archivo)] || 'application/octet-stream') + '; charset=utf-8' });
  fs.createReadStream(archivo).pipe(res);
}

http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'authorization, apikey, content-type, prefer, accept, accept-profile, content-profile, x-client-info, x-supabase-api-version, range');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') return responder(res, 204);
  const url = new URL(req.url, 'http://localhost');
  try {
    if (url.pathname.startsWith('/auth/v1/')) return await auth(req, res, url, url.pathname.slice(9));
    if (url.pathname.startsWith('/rest/v1/')) {
      if (!leerJwt((req.headers.authorization || '').replace(/^Bearer /i, ''))) {
        return responder(res, 401, { code: '42501', message: 'Debe iniciar sesión' });
      }
      return await rest(req, res, url, decodeURIComponent(url.pathname.slice(9)));
    }
    return estatico(res, url.pathname);
  } catch (e) {
    errorPg(res, e);
  }
}).listen(PUERTO, () => {
  console.log(`Anis · servidor local en http://localhost:${PUERTO}`);
  console.log(`Ingreso: email de la tabla usuario (admin@anis.bo) · contraseña: ${CLAVE}`);
});
