"""Prueba de punta a punta en navegador: registro, verificación (rechazo y aprobación), búsqueda,
registro de persona, calificación, ranking, panel de administrador y actualización obligatoria del APK.
Uso: sh tests/correr_e2e.sh"""
import os, json, psycopg2
from PIL import Image, ImageDraw
from playwright.sync_api import sync_playwright, expect

BASE = 'http://127.0.0.1:8787/app/'
OUT = '/tmp/e2e'; os.makedirs(OUT, exist_ok=True)
for n, col in [('anverso', (230, 230, 210)), ('reverso', (210, 225, 230)), ('selfie', (200, 220, 240))]:
    im = Image.new('RGB', (900, 1200), col); ImageDraw.Draw(im).text((40, 40), n.upper(), fill=(0, 0, 0)); im.save(f'{OUT}/{n}.jpg')

db = psycopg2.connect(host='/tmp/pg', port=5544, user='postgres', dbname=os.environ.get('FIAPE_DB', 'e2e')); db.autocommit = True
def sqlx(q, a=()):
    c = db.cursor(); c.execute(q, a); return c.fetchall() if c.description else None

errs, ok = [], [0]
def check(cond, what):
    assert cond, what; ok[0] += 1; print('OK ', what)
def page(ctx, who):
    p = ctx.new_page()
    p.on('pageerror', lambda e: errs.append(f'{who}: {e}'))
    p.on('console', lambda m: errs.append(f'{who} console: {m.text}') if m.type == 'error' and 'fonts' not in m.text and 'ERR_' not in m.text else None)
    p.goto(BASE); p.wait_for_timeout(500); return p
def shot(p, name): p.screenshot(path=f'{OUT}/{name}.png', full_page=True)
def click(p, text): p.get_by_role('button', name=text).first.click(); p.wait_for_timeout(450)
def tab(p, name): p.locator('.nav button', has_text=name).click(); p.wait_for_timeout(450)
def toast(p): return p.locator('.toast').last.inner_text() if p.locator('.toast').count() else ''

def register(p, dni, nom, ap, am, dep, email):
    p.get_by_role('tab', name='Crear cuenta').click(); p.wait_for_timeout(200)
    p.fill('#r-dni', dni); p.fill('#r-nom', ''); p.fill('#r-ap', ''); p.fill('#r-am', ''); p.type('#r-nom', nom); p.type('#r-ap', ap); p.type('#r-am', am)
    p.select_option('#r-dep', label=dep); p.fill('#r-email', email); p.fill('#r-pass', 'clave-segura-1')
    p.locator('[data-act=eye][data-for=r-pass]').click()
    p.locator('[data-act=register]').click(); p.wait_for_timeout(900)

def kyc(p):
    for k, f in [('anv', 'anverso'), ('rev', 'reverso'), ('sel', 'selfie')]:
        p.set_input_files(f'input[data-kyc={k}]', f'{OUT}/{f}.jpg'); p.wait_for_timeout(250)
    click(p, 'Enviar para verificación'); p.wait_for_timeout(900)

with sync_playwright() as pw:
    br = pw.chromium.launch(channel='chrome', args=['--no-sandbox'])
    mobile = dict(viewport={'width': 390, 'height': 844}, device_scale_factor=2)

    # ---------- 1. Registro del administrador ----------
    A = br.new_context(**mobile); pa = page(A, 'admin')
    shot(pa, '01-ingreso')
    register(pa, '11111111', 'Neisser', 'Admin', 'Fiape', 'Lima', 'admin@fiape.pe')
    check(pa.get_by_text('Sube 3 fotos para verificar que eres tú').is_visible(), 'usuario nuevo entra a "Mi cuenta" para verificarse')
    check(pa.locator('#r-pass').count() == 0, 'el formulario de registro se cerró')
    sqlx("update public.perfiles set es_admin = true, estado = 'verificado' where id = (select id from auth.users where email='admin@fiape.pe')")
    pa.reload(); pa.wait_for_timeout(700)
    check(pa.locator('.nav button', has_text='Admin').count() == 1, 'el administrador ve la pestaña Admin')

    # ---------- 2. Usuario B: registro y validaciones ----------
    B = br.new_context(**mobile); pb = page(B, 'B')
    pb.get_by_role('tab', name='Crear cuenta').click(); pb.wait_for_timeout(200)
    pb.type('#r-nom', 'ana lucía'); check(pb.input_value('#r-nom') == 'ANA LUCÍA', 'los nombres se escriben en MAYÚSCULAS')
    pb.fill('#r-dni', '12ab34'); check(pb.input_value('#r-dni') == '1234', 'el DNI solo acepta números')
    register(pb, '11111111', 'Otra', 'Persona', 'Xyz', 'Lima', 'otra@fiape.pe')
    check('ya tiene una cuenta' in toast(pb), 'no deja registrar un DNI que ya tiene cuenta')
    pb.goto(BASE); pb.wait_for_timeout(400)
    register(pb, '22222222', 'Ana Lucía', 'Ríos', 'Quispe', 'Arequipa', 'ana@fiape.pe')
    shot(pb, '02-verificacion')
    tab(pb, 'Buscar')
    check(pb.get_by_text('Verifica tu identidad', exact=True).is_visible(), 'sin verificar no puede buscar')
    tab(pb, 'Ranking'); check(pb.get_by_text('Las 100 personas más confiables').is_visible(), 'sin verificar sí ve el ranking')
    check(pb.input_value('#rk-dep') == '4', 'el ranking abre en su departamento (Arequipa)')
    tab(pb, 'Mi cuenta')
    check(pb.get_by_role('button', name='Enviar para verificación').is_disabled(), 'no se puede enviar sin las 3 fotos')
    kyc(pb)
    check(pb.get_by_text('Estamos revisando tus fotos').is_visible(), 'tras enviar queda en revisión')
    check(sqlx("select count(*) from storage.objects where bucket_id='verificaciones'")[0][0] == 3, 'las 3 fotos se guardan en el bucket privado')

    # ---------- 3. Admin rechaza y luego aprueba ----------
    tab(pa, 'Admin'); pa.wait_for_timeout(900)
    check(pa.get_by_text('Verificaciones pendientes (1)').is_visible(), 'admin ve 1 verificación pendiente')
    pa.wait_for_function("[...document.querySelectorAll('img[data-sign]')].every(i => i.complete && i.naturalWidth > 0)")
    check(True, 'admin ve las 3 fotos privadas')
    shot(pa, '03-admin')
    click(pa, 'Rechazar'); pa.get_by_role('button', name='La foto está borrosa o no se lee').click()
    pa.locator('#mot-ok').click(); pa.wait_for_timeout(900)
    check(pa.get_by_text('Verificaciones pendientes (0)').is_visible(), 'rechazo registrado')
    pb.reload(); pb.wait_for_timeout(700)
    check(pb.get_by_text('Motivo: La foto está borrosa o no se lee').is_visible(), 'el usuario ve el motivo del rechazo')
    check(pb.get_by_text('Te quedan 2 intentos').is_visible(), 'el usuario ve sus intentos restantes')
    kyc(pb)
    click(pa, 'Actualizar'); pa.wait_for_timeout(900)
    click(pa, 'Aprobar'); pa.wait_for_timeout(900)
    check(pa.get_by_text('Verificaciones pendientes (0)').is_visible(), 'aprobación registrada')
    click(pb, 'Actualizar estado'); pb.wait_for_timeout(500)
    check(pb.get_by_text('Tu identidad está verificada').is_visible(), 'el usuario queda verificado')

    # ---------- 4. Búsqueda, registro de persona y calificación ----------
    tab(pb, 'Buscar')
    pb.fill('#q', '1234'); pb.locator('[data-act=search]').click(); pb.wait_for_timeout(400)
    check('8 dígitos' in toast(pb), 'avisa si el DNI no tiene 8 dígitos')
    pb.fill('#q', '33333333'); pb.locator('[data-act=search]').click(); pb.wait_for_timeout(700)
    check(pb.get_by_text('No hay nadie con el DNI 33333333').is_visible(), 'DNI inexistente → ofrece registrar')
    click(pb, 'Registrar a esta persona')
    check(pb.input_value('#p-dni') == '33333333', 'el DNI buscado viene llenado y bloqueado')
    pb.type('#p-nom', 'juan carlos'); pb.type('#p-ap', 'pérez'); pb.type('#p-am', 'soto'); pb.select_option('#p-dep', label='Arequipa')
    click(pb, 'Registrar y calificar'); pb.wait_for_timeout(900)
    check(pb.locator('.stars').is_visible(), 'tras registrar se abre la calificación')
    check(pb.get_by_role('button', name='Guardar calificación').is_disabled(), 'no se guarda sin elegir estrellas')
    pb.locator('.stars button[data-n="8"]').click(); pb.wait_for_timeout(150)
    check(pb.locator('#r-big').inner_text().startswith('8'), 'muestra la nota elegida')
    shot(pb, '04-calificar')
    click(pb, 'Guardar calificación'); pb.wait_for_timeout(900)
    check(pb.get_by_text('Tu nota: 8/10 · Cambiar').is_visible(), 'la calificación queda guardada')
    check(pb.locator('.score b').first.inner_text().startswith('8'), 'el promedio público se actualiza (8)')
    pb.fill('#q', 'perez juan'); pb.locator('[data-act=search]').click(); pb.wait_for_timeout(700)
    check(pb.get_by_text('JUAN CARLOS PÉREZ SOTO').is_visible(), 'búsqueda por nombre sin tildes encuentra a la persona')
    click(pb, 'Tu nota: 8/10 · Cambiar'); pb.locator('.stars button[data-n="6"]').click(); click(pb, 'Guardar calificación'); pb.wait_for_timeout(800)
    check(pb.get_by_text('Tu nota: 6/10 · Cambiar').is_visible(), 'puede cambiar su calificación')
    check(sqlx("select total_calificaciones from public.personas where dni='33333333'")[0][0] == 1, 'cambiar no duplica la calificación')
    pb.fill('#q', '22222222'); pb.locator('[data-act=search]').click(); pb.wait_for_timeout(700)
    check(pb.get_by_text('Eres tú: no puedes calificarte.').is_visible(), 'no puede calificarse a sí mismo')
    pb.fill('#q', 'nadie xyz'); pb.locator('[data-act=search]').click(); pb.wait_for_timeout(700)
    check(pb.get_by_text('No encontramos a nadie con ese nombre').is_visible(), 'nombre inexistente → pide buscar por DNI')

    # ---------- 5. Ranking ----------
    pid = sqlx("select id from public.personas where dni='33333333'")[0][0]
    for i in range(4):
        uid = sqlx("insert into auth.users (email, raw_user_meta_data) values (%s, %s) returning id",
                   (f'r{i}@fiape.pe', json.dumps({'dni': str(40000000 + i), 'nombres': 'Votante', 'apellido_paterno': 'Prueba', 'departamento_id': 15})))[0][0]
        sqlx("insert into public.calificaciones (persona_id, autor_id, estrellas) values (%s, %s, 10)", (pid, uid))
    tab(pb, 'Ranking'); pb.wait_for_timeout(700)
    check(pb.locator('.rank').count() == 1 and pb.get_by_text('JUAN CARLOS PÉREZ SOTO').is_visible(), 'con 5 calificaciones aparece en el ranking de Arequipa')
    check(pb.locator('.rank b').last.inner_text() == '9.2', 'promedio del ranking (6+10+10+10+10)/5 = 9.2')
    shot(pb, '05-ranking')
    pb.select_option('#rk-dep', label='Lima'); pb.wait_for_timeout(700)
    check(pb.get_by_text('Todavía nadie de Lima tiene 5 calificaciones.').is_visible(), 'Lima vacío')
    pb.select_option('#rk-dep', label='Arequipa'); pb.wait_for_timeout(700)
    pb.locator('.rank').first.click(); pb.wait_for_timeout(900)
    check(pb.get_by_text('Tu nota: 6/10 · Cambiar').is_visible(), 'tocar a alguien del ranking lo busca para calificarlo')
    shot(pb, '06-buscar')

    # ---------- 6. Bloqueo tras 3 rechazos y reintento ----------
    Cc = br.new_context(**mobile); pc = page(Cc, 'C')
    register(pc, '55555555', 'Carlos', 'Vega', 'Luna', 'Cusco', 'carlos@fiape.pe')
    for n in range(3):
        kyc(pc)
        tab(pa, 'Admin'); pa.wait_for_timeout(700); click(pa, 'Rechazar')
        pa.fill('#mot', 'No coincide'); pa.locator('#mot-ok').click(); pa.wait_for_timeout(900)
        pc.reload(); pc.wait_for_timeout(700)
    check(pc.get_by_text('Usaste tus 3 intentos').is_visible(), 'tras 3 rechazos la cuenta queda bloqueada')
    click(pa, 'Actualizar'); pa.wait_for_timeout(800)
    check(pa.get_by_text('Cuentas bloqueadas (1)').is_visible() and pa.get_by_text('DNI 55555555').is_visible(), 'admin ve la cuenta bloqueada')
    click(pa, 'Dar 1 intento'); pa.wait_for_timeout(800)
    pc.reload(); pc.wait_for_timeout(700)
    check(pc.get_by_text('Te queda 1 intento').is_visible(), 'soporte le da 1 intento más')

    # ---------- 7. Actualización obligatoria del APK ----------
    D = br.new_context(**mobile, user_agent='Mozilla/5.0 (Linux; Android 14) Fiape/3')
    pd = D.new_page(); pd.route('**/version.json*', lambda r: r.fulfill(json={'apk': 5, 'url': 'https://example.com/fiape.apk'}))
    pd.goto(BASE); pd.wait_for_timeout(600)
    check(pd.get_by_text('Hay una nueva versión').is_visible(), 'APK antiguo → pantalla de actualización obligatoria')
    E = br.new_context(**mobile, user_agent='Mozilla/5.0 (Linux; Android 14) Fiape/5')
    pe = E.new_page(); pe.route('**/version.json*', lambda r: r.fulfill(json={'apk': 5}))
    pe.goto(BASE); pe.wait_for_timeout(600)
    check(pe.get_by_role('tab', name='Iniciar sesión').is_visible(), 'APK al día → abre normal')

    # ---------- 8. Escritorio ----------
    W = br.new_context(viewport={'width': 1280, 'height': 800}); pw_ = page(W, 'web')
    pw_.goto('http://127.0.0.1:8787/'); pw_.wait_for_timeout(500); shot(pw_, '07-web')
    check(pw_.get_by_role('link', name='Descargar app Android').count() >= 1, 'la web pública tiene el botón de descarga del APK')
    br.close()

print('\nErrores de consola:', errs or 'ninguno')
assert not errs, errs
print(f'=== PRUEBA DE NAVEGADOR: {ok[0]} comprobaciones OK ===')
