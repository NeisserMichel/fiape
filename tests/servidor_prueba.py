"""Servidor de PRUEBA local: imita lo justo de Supabase (rpc, select, storage) sobre un Postgres local
para probar la app en el navegador sin internet. No se usa en producción.
Uso: python3 tests/servidor_prueba.py   ->  http://localhost:8787/app/"""
import json, os, base64, decimal, datetime, mimetypes, sys, uuid
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import psycopg2, psycopg2.extras
from psycopg2 import sql

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILES = '/tmp/fiape-files'
DB = dict(host='/tmp/pg', port=5544, user='postgres', dbname=os.environ.get('FIAPE_DB', 'e2e'))
TABLES = {'perfiles', 'personas', 'departamentos', 'verificaciones', 'calificaciones'}

def conv(o):
    if isinstance(o, decimal.Decimal): return float(o)
    if isinstance(o, (datetime.datetime, datetime.date)): return o.isoformat()
    return str(o)

def as_user(cur, uid):
    cur.execute("set role authenticated; select set_config('request.jwt.claim.sub', %s, false)", (uid or '',))

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body, ctype='application/json'):
        b = body if isinstance(body, bytes) else json.dumps(body, default=conv).encode()
        self.send_response(code); self.send_header('Content-Type', ctype); self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == '/file':
            q = {k: v[0] for k, v in parse_qs(u.query).items()}
            with psycopg2.connect(**DB) as cx, cx.cursor() as cur:
                as_user(cur, q['u'])
                cur.execute("select 1 from storage.objects where bucket_id=%s and name=%s", (q['b'], q['p']))
                if not cur.fetchone(): return self.send(403, {'error': 'sin permiso'})
            return self.send(200, open(os.path.join(FILES, q['b'], q['p']), 'rb').read(), 'image/jpeg')
        p = os.path.normpath(os.path.join(ROOT, u.path.lstrip('/') or 'index.html'))
        if os.path.isdir(p): p = os.path.join(p, 'index.html')
        if not p.startswith(ROOT) or not os.path.isfile(p): return self.send(404, b'no', 'text/plain')
        data = open(p, 'rb').read()
        if p.endswith(os.path.join('app', 'index.html')):
            data = data.replace(b'<script src="config.js"></script>', b'<script src="/tests/test_api.js"></script><script src="config.js"></script>')
        if p.endswith('sw.js'): return self.send(404, b'', 'text/plain')
        self.send(200, data, mimetypes.guess_type(p)[0] or 'application/octet-stream')

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])) or b'{}')
        try:
            with psycopg2.connect(**DB) as cx:
                cx.autocommit = True
                cur = cx.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
                data = getattr(self, 'r_' + self.path.strip('/'))(cur, body)
                cur.execute('reset role')
            self.send(200, {'data': data})
        except psycopg2.Error as e:
            m = (e.diag.message_primary if getattr(e, 'diag', None) else None) or str(e)
            if self.path.strip('/') == 'signup': m = 'Database error saving new user'   # Supabase oculta el detalle
            self.send(200, {'error': m})

    def r_login(self, cur, b):
        cur.execute("select id from auth.users where lower(email)=lower(%s)", (b['email'],))
        r = cur.fetchone()
        if not r: raise psycopg2.Error('Invalid login credentials')
        return r['id']
    def r_signup(self, cur, b):
        cur.execute("select 1 from auth.users where lower(email)=lower(%s)", (b['email'],))
        if cur.fetchone(): raise psycopg2.Error('User already registered')
        meta = {k: b.get(k) for k in ('dni', 'nombres', 'apellido_paterno', 'apellido_materno', 'departamento_id')}
        cur.execute("insert into auth.users (email, raw_user_meta_data) values (%s, %s) returning id", (b['email'], json.dumps(meta)))
        return cur.fetchone()['id']
    def r_rpc(self, cur, b):
        fn = b['fn']
        # Como PostgREST: cada argumento se convierte al tipo declarado en la función
        cur.execute("""select p.proretset, p.prorettype::regtype::text rt, p.proargnames,
                              string_to_array(oidvectortypes(p.proargtypes), ', ') types
                         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                        where n.nspname = 'public' and p.proname = %s""", (fn,))
        meta = cur.fetchone()
        if not meta: raise psycopg2.Error('función no existe')
        types = dict(zip(meta['proargnames'] or [], meta['types'] or []))
        args = b.get('args') or {}
        call = sql.SQL('{}({})').format(sql.Identifier('public', fn), sql.SQL(', ').join(
            sql.SQL('{} => %s::' + types[k]).format(sql.Identifier(k)) for k in args))
        as_user(cur, b.get('u'))
        if meta['proretset']:
            cur.execute(sql.SQL('select * from ') + call, list(args.values())); return cur.fetchall()
        cur.execute(sql.SQL('select ') + call + sql.SQL(' as r'), list(args.values())); return cur.fetchone()['r']
    def r_select(self, cur, b):
        t = b['t']; assert t in TABLES
        where, params = [], []
        for op in b.get('ops', []):
            if op[0] == 'eq': where.append(sql.SQL('{}::text = %s').format(sql.Identifier(op[1]))); params.append(str(op[2]))
            elif op[0] == 'in': where.append(sql.SQL('{}::text = any(%s)').format(sql.Identifier(op[1]))); params.append([str(x) for x in op[2]])
        q = sql.SQL('select * from {}').format(sql.Identifier('public', t))
        if where: q += sql.SQL(' where ') + sql.SQL(' and ').join(where)
        as_user(cur, b.get('u')); cur.execute(q, params); return cur.fetchall()
    def r_upload(self, cur, b):
        as_user(cur, b['u'])
        cur.execute("insert into storage.objects (bucket_id, name) values (%s, %s)", (b['bucket'], b['path']))
        d = os.path.join(FILES, b['bucket'], os.path.dirname(b['path'])); os.makedirs(d, exist_ok=True)
        open(os.path.join(FILES, b['bucket'], b['path']), 'wb').write(base64.b64decode(b['b64']))
        return b['path']

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    print(f'Prueba en http://localhost:{port}/app/')
    ThreadingHTTPServer(('127.0.0.1', port), H).serve_forever()
