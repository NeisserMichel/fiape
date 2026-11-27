/* Fiapé · app para usuarios y administradores.
   Todas las reglas viven en Supabase (supabase/schema.sql); aquí solo se muestra y se llama a esas funciones. */
{
const C = window.FIAPE_CONFIG || {};
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const nota = n => n == null ? '—' : Number(n).toLocaleString('es-PE', {minimumFractionDigits: 0, maximumFractionDigits: 2});
const when = t => t ? new Date(t).toLocaleString('es-PE', {day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit'}) : '';
const plural = (n, a, b) => `${n} ${n === 1 ? a : b}`;
const DEPTS = ['Amazonas','Áncash','Apurímac','Arequipa','Ayacucho','Cajamarca','Callao','Cusco','Huancavelica','Huánuco','Ica','Junín','La Libertad','Lambayeque','Lima','Loreto','Madre de Dios','Moquegua','Pasco','Piura','Puno','San Martín','Tacna','Tumbes','Ucayali'];
const deptOpts = (sel, empty) => (empty ? `<option value="">${empty}</option>` : '') +
  DEPTS.map((d, i) => `<option value="${i + 1}"${+sel === i + 1 ? ' selected' : ''}>${d}</option>`).join('');
const NAME_RE = /^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ' .-]{2,60}$/;
const ESTADO = {
  pendiente_envio: ['Sin verificar', 'warn'], en_revision: ['En revisión', 'info'],
  verificado: ['Verificado', 'ok'], rechazado: ['Rechazado', 'bad'], bloqueado: ['Bloqueado', 'bad']
};
const IC = {
  search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
  trophy: '<path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0z"/><path d="M17 5h3v2a3 3 0 0 1-3 3M7 5H4v2a3 3 0 0 0 3 3"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21c1-4 4.5-6 8-6s7 2 8 6"/>',
  shield: '<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M9 12l2 2 4-4"/>',
  star: '<path d="M12 2.5l2.9 6.2 6.6.8-4.9 4.6 1.3 6.6L12 17.4l-5.9 3.3 1.3-6.6-4.9-4.6 6.6-.8z" fill="currentColor" stroke="none"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  camera: '<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>',
  card: '<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="8.5" cy="11" r="2"/><path d="M5.5 16c.6-1.5 1.7-2.2 3-2.2s2.4.7 3 2.2M14 10h4M14 13.5h3"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  eyeoff: '<path d="M3 3l18 18M10.6 5.1A10 10 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.2 4.2M6.6 6.6C3.9 8.4 2 12 2 12s3.5 7 10 7a9.6 9.6 0 0 0 4.4-1"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>',
  refresh: '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7"/>'
};
const ic = n => `<svg class="ic" viewBox="0 0 24 24" aria-hidden="true">${IC[n]}</svg>`;

/* ======================= CONEXIÓN A SUPABASE ======================= */
let sb = null;
const api = window.FIAPE_TEST_API || {
  async init() {
    await new Promise((res, rej) => {
      const s = document.createElement('script');
      s.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.49.4/dist/umd/supabase.js';
      s.onload = res; s.onerror = () => rej(new Error('No se pudo cargar Fiapé. Revisa tu conexión.'));
      document.head.appendChild(s);
    });
    sb = window.supabase.createClient(C.SUPABASE_URL, C.SUPABASE_ANON_KEY);
  },
  async session() { const { data } = await sb.auth.getSession(); return data.session?.user || null; },
  async signUp(v) {
    const { data, error } = await sb.auth.signUp({ email: v.email, password: v.password,
      options: { data: { dni: v.dni, nombres: v.nombres, apellido_paterno: v.apellido_paterno,
        apellido_materno: v.apellido_materno, departamento_id: v.departamento_id }, emailRedirectTo: location.href.split('#')[0] } });
    if (error) throw error; return !!data.session;
  },
  async signIn(e, p) { const { error } = await sb.auth.signInWithPassword({ email: e, password: p }); if (error) throw error; },
  async signOut() { await sb.auth.signOut(); },
  async reset(e) { const { error } = await sb.auth.resetPasswordForEmail(e, { redirectTo: location.href.split('#')[0] }); if (error) throw error; },
  async newPassword(p) { const { error } = await sb.auth.updateUser({ password: p }); if (error) throw error; },
  onRecovery(cb) { sb.auth.onAuthStateChange(ev => { if (ev === 'PASSWORD_RECOVERY') cb(); }); },
  async rpc(fn, args = {}) { const { data, error } = await sb.rpc(fn, args); if (error) throw error; return data; },
  async select(table, build) { let q = sb.from(table).select('*'); if (build) q = build(q); const { data, error } = await q; if (error) throw error; return data; },
  async upload(bucket, path, blob) { const { error } = await sb.storage.from(bucket).upload(path, blob, { contentType: 'image/jpeg', upsert: false }); if (error) throw error; return path; },
  async signed(bucket, path) { const { data, error } = await sb.storage.from(bucket).createSignedUrl(path, 600); if (error) throw error; return data.signedUrl; }
};

const ERR = {
  DNI_INVALIDO: 'El DNI debe tener 8 dígitos.',
  NOMBRES_INVALIDOS: 'Revisa los nombres: solo letras, igual que en el DNI.',
  APELLIDO_PATERNO_INVALIDO: 'Revisa el apellido paterno: solo letras, igual que en el DNI.',
  APELLIDO_MATERNO_INVALIDO: 'Revisa el apellido materno: solo letras, igual que en el DNI.',
  DEPARTAMENTO_OBLIGATORIO: 'Elige el departamento donde vives.',
  DEPARTAMENTO_INVALIDO: 'Elige un departamento de la lista.',
  DNI_YA_REGISTRADO: 'Este DNI ya tiene una cuenta. Inicia sesión.',
  NO_AUTENTICADO: 'Tu sesión terminó. Vuelve a iniciar sesión.',
  CUENTA_NO_VERIFICADA: 'Primero verifica tu identidad en "Mi cuenta".',
  PERFIL_NO_EXISTE: 'No encontramos tu perfil. Cierra sesión y vuelve a entrar.',
  YA_VERIFICADO: 'Tu cuenta ya está verificada.',
  VERIFICACION_EN_REVISION: 'Tus fotos ya están en revisión.',
  LIMITE_INTENTOS_ALCANZADO: 'Usaste tus 3 intentos. Contacta a soporte.',
  FOTOS_DEBEN_SER_DISTINTAS: 'Sube tres fotos distintas.',
  RUTA_FOTO_INVALIDA: 'No se pudo subir una foto. Inténtalo de nuevo.',
  FOTO_NO_ENCONTRADA: 'No se pudo subir una foto. Inténtalo de nuevo.',
  CONSULTA_MUY_CORTA: 'Escribe al menos 3 letras del nombre.',
  PERSONA_YA_EXISTE: 'Esa persona ya está registrada. Búscala por su DNI.',
  BUSQUEDA_PREVIA_REQUERIDA: 'Primero busca a la persona por su DNI o nombre.',
  LIMITE_REGISTROS_DIARIO: 'Llegaste al límite de 20 personas registradas hoy.',
  ESTRELLAS_FUERA_DE_RANGO: 'Elige de 1 a 10 estrellas.',
  PERSONA_NO_EXISTE: 'Esa persona ya no existe.',
  NO_PUEDES_CALIFICARTE: 'No puedes calificarte a ti mismo.',
  SOLO_ADMIN: 'Solo para administradores.',
  VERIFICACION_NO_EXISTE: 'Esa solicitud ya no existe.',
  VERIFICACION_YA_REVISADA: 'Otro administrador ya revisó esta solicitud.',
  NO_PUEDES_REVISARTE: 'No puedes aprobar tu propia verificación.',
  MOTIVO_REQUERIDO: 'Escribe el motivo del rechazo.',
  USUARIO_NO_BLOQUEADO: 'Esa cuenta ya no está bloqueada.'
};
function msg(e) {
  const m = String(e?.message || e || 'Error');
  for (const k in ERR) if (m.includes(k)) return ERR[k];
  if (/Invalid login credentials/i.test(m)) return 'Correo o contraseña incorrectos.';
  if (/Email not confirmed/i.test(m)) return 'Primero confirma tu correo: abre el enlace que te enviamos (revisa también spam).';
  if (/already registered|already been registered/i.test(m)) return 'Este correo ya tiene una cuenta. Inicia sesión.';
  if (/Database error saving new user/i.test(m)) return 'No se pudo crear la cuenta. Revisa que tus datos estén igual que en tu DNI.';
  if (/Password should be at least/i.test(m)) return 'La contraseña debe tener al menos 8 caracteres.';
  if (/rate limit|too many/i.test(m)) return 'Demasiados intentos. Espera unos minutos y vuelve a intentar.';
  if (/Failed to fetch|NetworkError|network/i.test(m)) return 'Sin conexión. Revisa tu internet.';
  return m;
}

/* ======================= ESTADO Y UTILIDADES ======================= */
const S = { user: null, me: null, tab: 'buscar', q: '', res: null, tipo: null, rankDep: null, rank: null, admin: null, kyc: {}, busy: false };
const verified = () => S.me?.estado === 'verificado';
const root = $('#app');

let toastT;
function toast(t) {
  $('.toast')?.remove(); clearTimeout(toastT);
  const d = document.createElement('div'); d.className = 'toast'; d.setAttribute('role', 'status'); d.textContent = t;
  document.body.appendChild(d); toastT = setTimeout(() => d.remove(), 4200);
}
function sheet(html) {
  closeSheet();
  const ov = document.createElement('div'); ov.className = 'ov';
  ov.innerHTML = `<div class="sheet" role="dialog" aria-modal="true">${html}</div>`;
  ov.addEventListener('click', e => { if (e.target === ov) closeSheet(); });
  document.body.appendChild(ov);
  setTimeout(() => $('.sheet input:not([readonly]), .sheet button', ov)?.focus(), 30);
  return $('.sheet', ov);
}
function closeSheet() { $('.ov')?.remove(); }
async function busy(btn, fn) {
  if (S.busy) return; S.busy = true;
  const t = btn?.innerHTML; if (btn) { btn.disabled = true; btn.textContent = 'Un momento…'; }
  try { return await fn(); }
  catch (e) { toast(msg(e)); }
  finally { S.busy = false; if (btn && btn.isConnected) { btn.disabled = false; btn.innerHTML = t; } }
}
async function compress(file) {
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = () => rej(new Error('Ese archivo no es una foto válida.')); i.src = url; });
    const k = Math.min(1, 1600 / Math.max(img.width, img.height));
    const cv = document.createElement('canvas'); cv.width = Math.round(img.width * k); cv.height = Math.round(img.height * k);
    cv.getContext('2d').drawImage(img, 0, 0, cv.width, cv.height);
    return await new Promise(r => cv.toBlob(r, 'image/jpeg', 0.82));
  } finally { URL.revokeObjectURL(url); }
}
const pw = (id, ph, auto) => `<div class="pw"><input id="${id}" type="password" autocomplete="${auto}" placeholder="${ph}" required minlength="8">
  <button type="button" class="eye" data-act="eye" data-for="${id}" aria-label="Mostrar contraseña" aria-pressed="false">${ic('eye')}</button></div>`;
const scoreBar = p => `<div class="bar" aria-hidden="true"><i style="width:${p == null ? 0 : Math.max(2, p * 10)}%"></i></div>`;

/* ======================= INGRESO Y REGISTRO ======================= */
function viewAuth(mode = 'login', notice = '') {
  document.body.classList.remove('wide');
  root.innerHTML = `
  <header class="hero"><img src="icon-192.png" alt=""><h1>Fiapé</h1><p>Consulta la reputación de una persona antes de confiar.</p></header>
  <main class="wrap">
    <section class="card">
      <div class="seg" role="tablist">
        <button role="tab" data-act="mode" data-m="login" aria-selected="${mode === 'login'}">Iniciar sesión</button>
        <button role="tab" data-act="mode" data-m="register" aria-selected="${mode === 'register'}">Crear cuenta</button>
      </div>
      ${notice}
      ${mode === 'login' ? `
      <form data-form="login">
        <label>Correo<input id="l-email" type="email" autocomplete="email" required></label>
        <label>Contraseña${pw('l-pass', '', 'current-password')}</label>
        <button class="btn" data-act="login" type="submit">Entrar</button>
        <button class="link" type="button" data-act="forgot">Olvidé mi contraseña</button>
      </form>` : `
      <form data-form="register">
        <p class="small mute">Escribe tus datos <b>exactamente como aparecen en tu DNI</b>. Luego verificaremos tu identidad con fotos.</p>
        <label>DNI<input id="r-dni" inputmode="numeric" maxlength="8" pattern="[0-9]{8}" autocomplete="off" required placeholder="8 dígitos"></label>
        <label>Nombres<input id="r-nom" data-upper autocomplete="given-name" required></label>
        <div class="row2">
          <label>Apellido paterno<input id="r-ap" data-upper autocomplete="family-name" required></label>
          <label>Apellido materno<input id="r-am" data-upper autocomplete="off"></label>
        </div>
        <label>Departamento donde vives<select id="r-dep" required>${deptOpts(null, 'Elige tu departamento')}</select></label>
        <label>Correo<input id="r-email" type="email" autocomplete="email" required></label>
        <label>Contraseña <small>(mínimo 8 caracteres)</small>${pw('r-pass', '', 'new-password')}</label>
        <p class="small mute">Al crear tu cuenta, tu nombre, DNI y departamento podrán ser consultados por usuarios verificados de Fiapé, y otras personas podrán calificarte.</p>
        <button class="btn" data-act="register" type="submit">Crear cuenta</button>
      </form>`}
    </section>
    ${C.APK_URL ? `<p class="small mute" style="text-align:center;margin-top:18px">¿Usas Android? <a href="${esc(C.APK_URL)}">Descarga la app</a></p>` : ''}
  </main>`;
}

async function doLogin(btn) {
  const email = $('#l-email').value.trim(), pass = $('#l-pass').value;
  if (!email || !pass) return toast('Escribe tu correo y contraseña.');
  await busy(btn, async () => { await api.signIn(email, pass); await boot(); });
}
async function doRegister(btn) {
  const v = {
    dni: $('#r-dni').value.trim(), nombres: $('#r-nom').value.trim(), apellido_paterno: $('#r-ap').value.trim(),
    apellido_materno: $('#r-am').value.trim(), departamento_id: +$('#r-dep').value || null,
    email: $('#r-email').value.trim(), password: $('#r-pass').value
  };
  if (!/^\d{8}$/.test(v.dni)) return toast(ERR.DNI_INVALIDO);
  if (!NAME_RE.test(v.nombres)) return toast(ERR.NOMBRES_INVALIDOS);
  if (!NAME_RE.test(v.apellido_paterno)) return toast(ERR.APELLIDO_PATERNO_INVALIDO);
  if (v.apellido_materno && !NAME_RE.test(v.apellido_materno)) return toast(ERR.APELLIDO_MATERNO_INVALIDO);
  if (!v.departamento_id) return toast(ERR.DEPARTAMENTO_OBLIGATORIO);
  if (!/^\S+@\S+\.\S+$/.test(v.email)) return toast('Escribe un correo válido.');
  if (v.password.length < 8) return toast('La contraseña debe tener al menos 8 caracteres.');
  await busy(btn, async () => {
    if (await api.rpc('dni_tiene_cuenta', { p_dni: v.dni })) throw new Error('DNI_YA_REGISTRADO');
    const logged = await api.signUp(v);
    if (logged) return boot();
    viewAuth('login', `<div class="note ok"><b>¡Cuenta creada!</b> Te enviamos un correo a <b>${esc(v.email)}</b>. Abre el enlace para activarla y luego inicia sesión aquí. Si no lo ves, revisa la carpeta de spam.</div>`);
  });
}
function forgotSheet() {
  sheet(`<h2>Recuperar contraseña</h2><p class="mute">Te enviaremos un enlace a tu correo para crear una nueva.</p>
    <form data-form="reset"><label>Correo<input id="f-email" type="email" required value="${esc($('#l-email')?.value || '')}"></label>
    <button class="btn" data-act="reset" type="submit">Enviar enlace</button></form>`);
}
function newPassSheet() {
  sheet(`<h2>Nueva contraseña</h2><form data-form="newpass"><label>Contraseña nueva <small>(mínimo 8)</small>${pw('n-pass', '', 'new-password')}</label>
    <button class="btn" data-act="newpass" type="submit">Guardar</button></form>`);
}

/* ======================= ESTRUCTURA PRINCIPAL ======================= */
function tabs() {
  const t = [['buscar', 'Buscar', 'search'], ['ranking', 'Ranking', 'trophy'], ['cuenta', 'Mi cuenta', 'user']];
  if (S.me?.es_admin) t.push(['admin', 'Admin', 'shield']);
  return t;
}
function render() {
  if (!S.me) return;
  document.body.classList.toggle('wide', S.tab === 'admin');
  const [txt, cls] = ESTADO[S.me.estado] || ['', 'mute'];
  root.innerHTML = `
  <header class="top"><div class="in">
    <a class="brand" href="#" data-act="tab" data-t="buscar"><img src="icon-192.png" alt="">Fiapé</a>
    <div class="who">${esc(S.me.nombres.split(' ')[0])}<br><span class="tag ${cls}">${txt}</span></div>
  </div></header>
  <main class="wrap" id="main">${({ buscar: vBuscar, ranking: vRanking, cuenta: vCuenta, admin: vAdmin })[S.tab]()}</main>
  <nav class="nav" aria-label="Secciones"><div class="in">
    ${tabs().map(([k, l, i]) => `<button data-act="tab" data-t="${k}" aria-current="${S.tab === k}">${ic(i)}${l}</button>`).join('')}
  </div></nav>`;
  $$('img[data-sign]').forEach(async im => {
    try { const u = await api.signed('verificaciones', im.dataset.sign); im.src = u; im.closest('a').href = u; } catch { im.alt = 'No se pudo cargar'; }
  });
}
function go(tab) {
  S.tab = tab; render(); scrollTo(0, 0);
  if (tab === 'ranking' && !S.rank) loadRanking();
  if (tab === 'admin') loadAdmin();
}

/* ----------------------- Buscar ----------------------- */
function personCard(p) {
  const rated = p.mi_calificacion != null;
  return `<article class="card person" data-id="${p.id}">
    <div><h3>${esc(p.nombre_completo)}</h3></div>
    <div class="score">${p.promedio == null ? '<b>—</b>' : `<b>${nota(p.promedio)}<small>/10</small></b>`}</div>
    ${scoreBar(p.promedio)}
    <div class="meta"><span>DNI ${esc(p.dni)}</span>${p.departamento ? `<span>${esc(p.departamento)}</span>` : ''}
      <span>${p.total_calificaciones ? plural(p.total_calificaciones, 'calificación', 'calificaciones') : 'Sin calificaciones'}</span>
      ${p.tiene_cuenta ? '<span class="tag info">Tiene cuenta</span>' : ''}</div>
    <div style="grid-column:1/-1">${p.soy_yo ? '<p class="small mute">Eres tú: no puedes calificarte.</p>'
      : `<button class="btn ${rated ? 'sec' : ''}" data-act="rate" data-id="${p.id}">${ic('star')}${rated ? `Tu nota: ${p.mi_calificacion}/10 · Cambiar` : 'Calificar'}</button>`}</div>
  </article>`;
}
function vBuscar() {
  if (!verified()) return `<section class="card"><h2>Verifica tu identidad</h2>
    <p>Para buscar, registrar y calificar personas primero debemos confirmar que eres tú.</p>
    <button class="btn" data-act="tab" data-t="cuenta">${ic('card')}Verificar mi identidad</button></section>
    <section class="card"><h3>Mientras tanto</h3><p class="mute">Puedes ver el ranking de las personas más confiables de cada departamento.</p>
    <button class="btn sec" data-act="tab" data-t="ranking">${ic('trophy')}Ver ranking</button></section>`;
  let out = `<section class="card"><h2>Buscar a una persona</h2>
    <p class="mute">Antes de calificar, búscala por su <b>DNI</b> (8 dígitos) o por sus <b>nombres y apellidos</b>.</p>
    <form data-form="search" class="search" style="margin-top:12px">
      <input id="q" type="search" value="${esc(S.q)}" placeholder="DNI o nombre" autocomplete="off" aria-label="DNI o nombre">
      <button type="submit" data-act="search" aria-label="Buscar">${ic('search')}</button>
    </form></section>`;
  if (S.res) {
    if (S.res.length) out += `<p class="small mute" style="margin:14px 4px 0">${plural(S.res.length, 'resultado', 'resultados')}</p>` + S.res.map(personCard).join('');
    else if (S.tipo === 'dni') out += `<section class="card"><h3>No hay nadie con el DNI ${esc(S.q)}</h3>
      <p class="mute">Si conoces a esta persona, puedes registrarla con su DNI, nombres y apellidos completos para calificarla.</p>
      <button class="btn" data-act="newp">${ic('plus')}Registrar a esta persona</button></section>`;
    else out += `<section class="card"><h3>No encontramos a nadie con ese nombre</h3>
      <p class="mute">Para registrar a una persona nueva, búscala primero por su <b>DNI</b>.</p></section>`;
  }
  return out;
}
async function doSearch(btn, q) {
  q = (q ?? $('#q').value).trim(); S.q = q;
  if (/^\d+$/.test(q) && q.length !== 8) return toast(ERR.DNI_INVALIDO);
  if (!q) return toast('Escribe un DNI o un nombre.');
  await busy(btn, async () => {
    S.res = await api.rpc('buscar_personas', { p_consulta: q }) || [];
    S.tipo = /^\d{8}$/.test(q) ? 'dni' : 'nombre';
    render();
  });
}
function newPersonSheet() {
  sheet(`<h2>Registrar persona</h2><p class="mute">Escribe sus datos <b>exactamente como en su DNI</b>.</p>
    <form data-form="newp">
      <label>DNI<input id="p-dni" value="${esc(S.q)}" readonly></label>
      <label>Nombres<input id="p-nom" data-upper required></label>
      <div class="row2"><label>Apellido paterno<input id="p-ap" data-upper required></label>
      <label>Apellido materno<input id="p-am" data-upper></label></div>
      <label>Departamento <small>(opcional: necesario para el ranking)</small><select id="p-dep">${deptOpts(null, 'No sé')}</select></label>
      <button class="btn" data-act="savep" type="submit">Registrar y calificar</button>
    </form>`);
}
async function savePerson(btn) {
  const v = { p_dni: $('#p-dni').value, p_nombres: $('#p-nom').value.trim(), p_apellido_paterno: $('#p-ap').value.trim(),
    p_apellido_materno: $('#p-am').value.trim() || null, p_departamento_id: +$('#p-dep').value || null };
  if (!NAME_RE.test(v.p_nombres)) return toast(ERR.NOMBRES_INVALIDOS);
  if (!NAME_RE.test(v.p_apellido_paterno)) return toast(ERR.APELLIDO_PATERNO_INVALIDO);
  if (v.p_apellido_materno && !NAME_RE.test(v.p_apellido_materno)) return toast(ERR.APELLIDO_MATERNO_INVALIDO);
  await busy(btn, async () => {
    const id = await api.rpc('registrar_persona', v);
    closeSheet(); toast('Persona registrada. Ahora califícala.');
    S.busy = false; await doSearch(null, v.p_dni);
    rateSheet(id);
  });
}

/* ----------------------- Calificar ----------------------- */
function rateSheet(id) {
  const p = S.res?.find(x => x.id === id); if (!p) return;
  let sel = p.mi_calificacion || 0;
  const el = sheet(`<h2>Calificar</h2><p><b>${esc(p.nombre_completo)}</b><br><span class="mute small">DNI ${esc(p.dni)}</span></p>
    <p class="small mute">¿Qué tanto recomiendas a esta persona? Tu calificación es <b>anónima</b>.</p>
    <div class="stars" role="radiogroup" aria-label="Calificación de 1 a 10">${Array.from({ length: 10 }, (_, i) =>
      `<button type="button" role="radio" data-n="${i + 1}" aria-label="${i + 1} de 10">${ic('star')}<span>${i + 1}</span></button>`).join('')}</div>
    <div class="ends"><span>1 · Nada recomendable</span><span>10 · Lo recomiendo totalmente</span></div>
    <div class="big" id="r-big">—</div>
    <button class="btn" id="r-save" disabled>Guardar calificación</button>`);
  const paint = () => {
    $$('.stars button', el).forEach(b => { const n = +b.dataset.n; b.classList.toggle('on', n <= sel); b.setAttribute('aria-checked', n === sel); });
    $('#r-big', el).innerHTML = sel ? `${sel}<small>/10</small>` : '—';
    $('#r-save', el).disabled = !sel;
  };
  $$('.stars button', el).forEach(b => b.onclick = () => { sel = +b.dataset.n; paint(); });
  $('#r-save', el).onclick = e => busy(e.currentTarget, async () => {
    const r = (await api.rpc('calificar', { p_persona_id: id, p_estrellas: sel }))?.[0] || {};
    Object.assign(p, { promedio: r.promedio, total_calificaciones: r.total_calificaciones, mi_calificacion: sel });
    S.rank = null; closeSheet(); render();
    toast(`¡Gracias! Nuevo promedio de ${p.nombres || p.nombre_completo.split(' ')[0]}: ${nota(r.promedio)}/10`);
  });
  paint();
}

/* ----------------------- Ranking ----------------------- */
function vRanking() {
  const rows = S.rank;
  return `<section class="card"><h2>Las 100 personas más confiables</h2>
    <label>Departamento<select id="rk-dep" data-act="rankdep">${deptOpts(S.rankDep)}</select></label>
    <p class="small mute">Solo aparecen personas con 5 calificaciones o más.</p></section>
    <section class="card" id="rk">${rows == null ? '<div class="empty">Cargando…</div>' : rows.length ? rows.map(r => `
      <button class="rank" data-act="rankp" data-n="${esc(r.nombre_completo)}">
        <span class="pos ${r.puesto <= 3 ? 'p' + r.puesto : ''}">${r.puesto}</span>
        <span><b style="font:600 15px Inter;white-space:normal">${esc(r.nombre_completo)}</b><br><span class="small mute">${plural(r.total_calificaciones, 'calificación', 'calificaciones')}</span></span>
        <b>${nota(r.promedio)}</b>
      </button>`).join('') : `<div class="empty">Todavía nadie de ${esc(DEPTS[S.rankDep - 1])} tiene 5 calificaciones.</div>`}
    </section>`;
}
async function loadRanking() {
  S.rankDep = S.rankDep || S.me.departamento_id || 15;
  try { S.rank = await api.rpc('ranking_departamento', { p_departamento_id: +S.rankDep }) || []; }
  catch (e) { S.rank = []; toast(msg(e)); }
  if (S.tab === 'ranking') render();
}

/* ----------------------- Mi cuenta / verificación ----------------------- */
const SHOTS = [
  ['anv', 'DNI por delante', 'Que se lean bien tu foto, nombres, apellidos y número de DNI.', 'card'],
  ['rev', 'DNI por detrás', 'La parte de atrás completa, sin reflejos.', 'card'],
  ['sel', 'Tú con tu DNI', 'Una selfie sosteniendo tu DNI en la mano, debajo del mentón, con tu cara descubierta.', 'camera']
];
function vKyc() {
  const m = S.me;
  if (m.estado === 'verificado') return `<div class="note ok"><b>Tu identidad está verificada.</b> Ya puedes buscar, registrar y calificar.</div>`;
  if (m.estado === 'en_revision') return `<div class="note info"><b>Estamos revisando tus fotos.</b> Un administrador comparará tu DNI con los datos que registraste. Vuelve más tarde.</div>
    <button class="btn sec" data-act="reload">${ic('refresh')}Actualizar estado</button>`;
  if (m.estado === 'bloqueado') return `<div class="note bad"><b>Usaste tus 3 intentos de verificación.</b> Contacta a soporte para revisar tu caso.${m.ultimo_motivo_rechazo ? `<br>Último motivo: ${esc(m.ultimo_motivo_rechazo)}` : ''}</div>
    ${C.WHATSAPP_SOPORTE ? `<a class="btn" href="https://wa.me/${esc(C.WHATSAPP_SOPORTE)}?text=${encodeURIComponent('Hola, necesito ayuda con la verificación de mi cuenta Fiapé. DNI ' + m.dni)}">Contactar a soporte</a>` : ''}`;
  return `${m.estado === 'rechazado' ? `<div class="note bad"><b>No pudimos verificar tu identidad.</b>${m.ultimo_motivo_rechazo ? `<br>Motivo: ${esc(m.ultimo_motivo_rechazo)}` : ''}<br>Te ${m.intentos_restantes === 1 ? 'queda 1 intento' : `quedan ${m.intentos_restantes} intentos`}.</div>`
    : `<div class="note warn">Sube 3 fotos para verificar que eres tú. Tienes ${m.intentos_restantes} intentos.</div>`}
    <p class="small mute">Tus datos deben coincidir <b>exactamente</b> con tu DNI: ${esc(m.nombres)} ${esc(m.apellido_paterno)} ${esc(m.apellido_materno || '')} · DNI ${esc(m.dni)}. Las fotos son privadas: solo las ve el equipo de verificación.</p>
    ${SHOTS.map(([k, t, d, i]) => { const f = S.kyc[k]; return `
      <div class="shot ${f ? 'done' : ''}"><div class="th">${f ? `<img src="${f.url}" alt="">` : ic(i)}</div>
        <div><b>${t}</b><div class="small mute">${d}</div>
        <label class="pickb">${f ? 'Cambiar foto' : 'Elegir o tomar foto'}<input type="file" accept="image/*" data-kyc="${k}"></label></div></div>`; }).join('')}
    <button class="btn" data-act="kyc" ${SHOTS.every(([k]) => S.kyc[k]) ? '' : 'disabled'}>Enviar para verificación</button>`;
}
function vCuenta() {
  const m = S.me;
  return `<section class="card"><h2>Verificación</h2>${vKyc()}</section>
  <section class="card"><h2>Mis datos</h2><dl class="dl">
    <dt>Nombre</dt><dd>${esc(m.nombres)} ${esc(m.apellido_paterno)} ${esc(m.apellido_materno || '')}</dd>
    <dt>DNI</dt><dd>${esc(m.dni)}</dd><dt>Departamento</dt><dd>${esc(m.departamento)}</dd>
    <dt>Mi promedio</dt><dd>${m.total_calificaciones ? `${nota(m.promedio)}/10 · ${plural(m.total_calificaciones, 'calificación', 'calificaciones')}` : 'Aún nadie te calificó'}</dd>
  </dl></section>
  <button class="btn ghost" data-act="logout">Cerrar sesión</button>`;
}
async function sendKyc(btn) {
  await busy(btn, async () => {
    const t = Date.now(), uid = S.user.id, paths = [];
    for (const [k, name] of [['anv', 'anverso'], ['rev', 'reverso'], ['sel', 'selfie']])
      paths.push(await api.upload('verificaciones', `${uid}/${t}-${name}.jpg`, await compress(S.kyc[k].file)));
    await api.rpc('enviar_verificacion', { p_foto_dni_anverso: paths[0], p_foto_dni_reverso: paths[1], p_foto_selfie_dni: paths[2] });
    S.kyc = {}; await loadMe(); render(); toast('¡Fotos enviadas! Te avisaremos cuando revisemos tu identidad.');
  });
}

/* ----------------------- Administrador ----------------------- */
const MOTIVOS = ['La foto está borrosa o no se lee', 'Los nombres no coinciden con el DNI', 'El número de DNI no coincide',
  'Falta una foto o está cortada', 'La selfie no muestra el DNI bajo el mentón', 'La persona de la selfie no es la del DNI'];
function vAdmin() {
  const a = S.admin;
  if (!a) return '<div class="empty">Cargando…</div>';
  return `<section class="card"><div style="display:flex;justify-content:space-between;gap:10px;align-items:center">
      <h2>Verificaciones pendientes (${a.pend.length})</h2><button class="link" data-act="admreload">Actualizar</button></div>
    <p class="small mute">Compara cada foto con los datos: nombres, apellidos y DNI deben coincidir <b>exactamente</b>, y la persona debe sostener su DNI bajo el mentón.</p></section>
    ${a.pend.length ? `<div class="grid">${a.pend.map(v => `<article class="card">
      <h3>${esc(v.nombres)} ${esc(v.apellido_paterno)} ${esc(v.apellido_materno || '')}</h3>
      <dl class="dl"><dt>DNI</dt><dd>${esc(v.dni)}</dd><dt>Departamento</dt><dd>${esc(v.departamento)}</dd>
        <dt>Intento</dt><dd>${v.intento} de 3</dd><dt>Enviado</dt><dd>${when(v.enviado_at)}</dd></dl>
      <div class="ph">${[['foto_dni_anverso', 'DNI delante'], ['foto_dni_reverso', 'DNI detrás'], ['foto_selfie_dni', 'Selfie']].map(([k, l]) =>
        `<figure><a target="_blank" rel="noopener"><img data-sign="${esc(v[k])}" alt="${l}"></a><figcaption>${l}</figcaption></figure>`).join('')}</div>
      <div class="btns"><button class="btn ok" data-act="aprobar" data-id="${v.verificacion_id}">${ic('check')}Aprobar</button>
        <button class="btn bad" data-act="rechazar" data-id="${v.verificacion_id}">Rechazar</button></div>
    </article>`).join('')}</div>` : '<section class="card"><div class="empty">No hay verificaciones pendientes.</div></section>'}
    <section class="card"><h2>Esperando que envíen sus fotos (${a.espera.length})</h2>
      <p class="small mute">Se registraron pero aún no envían sus 3 fotos, o fueron rechazados y pueden volver a intentarlo. Aparecerán arriba cuando las envíen.</p>
      ${a.espera.length ? a.espera.map(u => `<div class="rank" style="cursor:default;grid-template-columns:1fr auto">
        <span><b style="font:600 15px Inter">${esc(u.nombres)} ${esc(u.apellido_paterno)} ${esc(u.apellido_materno || '')}</b><br>
        <span class="small mute">DNI ${esc(u.dni || '')} · ${esc(DEPTS[u.departamento_id - 1] || '')} · registrado ${when(u.created_at)}</span></span>
        <span class="tag ${u.estado === 'rechazado' ? 'bad' : 'warn'}">${u.estado === 'rechazado' ? `Rechazado · ${3 - u.intentos_verificacion} intento${3 - u.intentos_verificacion === 1 ? '' : 's'}` : 'Sin fotos'}</span></div>`).join('')
        : '<div class="empty">Nadie.</div>'}
    </section>
    <section class="card"><h2>Cuentas bloqueadas (${a.bloq.length})</h2>
      <p class="small mute">Usaron sus 3 intentos. Si soporte lo aprueba, puedes darles 1 intento más.</p>
      ${a.bloq.length ? a.bloq.map(b => `<div class="rank" style="cursor:default;grid-template-columns:1fr auto">
        <span><b style="font:600 15px Inter">${esc(b.nombres)} ${esc(b.apellido_paterno)}</b><br><span class="small mute">DNI ${esc(b.dni || '')}</span></span>
        <button class="btn sec" style="margin:0;min-height:44px;width:auto" data-act="reintento" data-id="${b.id}">Dar 1 intento</button></div>`).join('')
        : '<div class="empty">Ninguna.</div>'}
    </section>`;
}
async function loadAdmin() {
  // Cada lista se carga por separado: si una falla, las demás se muestran igual.
  const [pend, perf] = await Promise.allSettled([
    api.rpc('admin_listar_verificaciones', { p_estado: 'en_revision' }),
    api.select('perfiles', q => q.in('estado', ['pendiente_envio', 'rechazado', 'bloqueado']))
  ]);
  const fallo = [pend, perf].find(r => r.status === 'rejected');
  if (fallo) toast(msg(fallo.reason));
  const users = perf.status === 'fulfilled' ? perf.value || [] : [];
  if (users.length) {
    try {
      const pers = await api.select('personas', q => q.in('id', users.map(u => u.persona_id)));
      users.forEach(u => u.dni = pers.find(p => p.id === u.persona_id)?.dni);
    } catch (e) { toast(msg(e)); }
  }
  users.sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
  S.admin = {
    pend: pend.status === 'fulfilled' ? pend.value || [] : [],
    espera: users.filter(u => u.estado !== 'bloqueado'),
    bloq: users.filter(u => u.estado === 'bloqueado')
  };
  if (S.tab === 'admin') render();
}
function rejectSheet(id) {
  const el = sheet(`<h2>Rechazar verificación</h2><p class="mute">El usuario verá este motivo y podrá volver a intentarlo si le quedan intentos.</p>
    <div class="chips">${MOTIVOS.map(m => `<button type="button">${m}</button>`).join('')}</div>
    <label>Motivo<textarea id="mot" rows="3" required></textarea></label>
    <button class="btn bad" id="mot-ok">Rechazar</button>`);
  $$('.chips button', el).forEach(b => b.onclick = () => { $('#mot', el).value = b.textContent; });
  $('#mot-ok', el).onclick = e => busy(e.currentTarget, async () => {
    const mot = $('#mot', el).value.trim(); if (!mot) throw new Error('MOTIVO_REQUERIDO');
    const st = await api.rpc('admin_revisar_verificacion', { p_verificacion_id: id, p_aprobar: false, p_motivo: mot });
    closeSheet(); toast(st === 'bloqueado' ? 'Rechazada. Era su último intento: la cuenta quedó bloqueada.' : 'Verificación rechazada.');
    S.busy = false; await loadAdmin();
  });
}

/* ======================= EVENTOS ======================= */
document.addEventListener('click', async e => {
  const b = e.target.closest('[data-act]'); if (!b || b.tagName === 'SELECT') return;
  const a = b.dataset.act;
  if (b.type === 'submit' && b.form) return;
  e.preventDefault();
  if (a === 'mode') viewAuth(b.dataset.m);
  else if (a === 'forgot') forgotSheet();
  else if (a === 'eye') {
    const i = $('#' + b.dataset.for), show = i.type === 'password';
    i.type = show ? 'text' : 'password'; b.setAttribute('aria-pressed', show); b.innerHTML = ic(show ? 'eyeoff' : 'eye');
  }
  else if (a === 'tab') go(b.dataset.t);
  else if (a === 'rate') rateSheet(b.dataset.id);
  else if (a === 'newp') newPersonSheet();
  else if (a === 'rankp') {
    if (!verified()) return toast('Verifica tu identidad para calificar.');
    S.tab = 'buscar'; render(); await doSearch(null, b.dataset.n);
  }
  else if (a === 'kyc') sendKyc(b);
  else if (a === 'reload') busy(b, async () => { await loadMe(); render(); if (verified()) toast('¡Tu identidad fue verificada!'); });
  else if (a === 'logout') { await api.signOut(); Object.assign(S, { user: null, me: null, res: null, q: '', rank: null, admin: null, kyc: {}, tab: 'buscar' }); viewAuth(); }
  else if (a === 'admreload') { S.admin = null; render(); loadAdmin(); }
  else if (a === 'aprobar') busy(b, async () => {
    await api.rpc('admin_revisar_verificacion', { p_verificacion_id: b.dataset.id, p_aprobar: true });
    toast('Identidad aprobada.'); S.busy = false; await loadAdmin();
  });
  else if (a === 'rechazar') rejectSheet(b.dataset.id);
  else if (a === 'reintento') busy(b, async () => {
    await api.rpc('admin_habilitar_reintento', { p_user_id: b.dataset.id });
    toast('Listo: ahora tiene 1 intento más.'); S.busy = false; await loadAdmin();
  });
});
document.addEventListener('submit', e => {
  const f = e.target.closest('[data-form]'); if (!f) return;
  e.preventDefault();
  const btn = $('button[type=submit]', f), k = f.dataset.form;
  if (k === 'login') doLogin(btn);
  else if (k === 'register') doRegister(btn);
  else if (k === 'search') doSearch(btn);
  else if (k === 'newp') savePerson(btn);
  else if (k === 'reset') busy(btn, async () => { await api.reset($('#f-email').value.trim()); closeSheet(); toast('Te enviamos un enlace a tu correo.'); });
  else if (k === 'newpass') busy(btn, async () => {
    const p = $('#n-pass').value; if (p.length < 8) throw new Error('Password should be at least 8');
    await api.newPassword(p); closeSheet(); toast('Contraseña actualizada.'); await boot();
  });
});
document.addEventListener('input', e => {
  const t = e.target;
  if (t.matches('[data-upper]')) { const p = t.selectionStart; t.value = t.value.toUpperCase(); t.setSelectionRange(p, p); }
  if (t.id === 'r-dni' || t.id === 'q' && /^\d/.test(t.value)) t.value = t.value.replace(/\D/g, '').slice(0, 8);
});
document.addEventListener('change', e => {
  const t = e.target;
  if (t.id === 'rk-dep') { S.rankDep = +t.value; S.rank = null; render(); loadRanking(); }
  if (t.dataset.kyc) {
    const f = t.files?.[0]; if (!f) return;
    if (!f.type.startsWith('image/')) return toast('Elige una foto (JPG o PNG).');
    if (S.kyc[t.dataset.kyc]) URL.revokeObjectURL(S.kyc[t.dataset.kyc].url);
    S.kyc[t.dataset.kyc] = { file: f, url: URL.createObjectURL(f) }; render();
  }
});
document.addEventListener('visibilitychange', async () => {
  if (document.visibilityState === 'visible' && S.me?.estado === 'en_revision') {
    try { await loadMe(); if (S.tab !== 'admin') render(); } catch {}
  }
});

/* ======================= ARRANQUE ======================= */
async function loadMe() {
  const r = await api.rpc('mi_perfil');
  S.me = (Array.isArray(r) ? r[0] : r) || null;
  if (!S.me) throw new Error('PERFIL_NO_EXISTE');
}
async function boot() {
  S.user = await api.session();
  if (!S.user) return viewAuth();
  try { await loadMe(); }
  catch (e) { root.innerHTML = `<main class="wrap"><section class="card"><h2>No pudimos abrir tu cuenta</h2><p>${esc(msg(e))}</p><button class="btn" data-act="logout">Cerrar sesión</button></section></main>`; return; }
  S.rankDep = S.rankDep || S.me.departamento_id;
  S.tab = verified() ? 'buscar' : 'cuenta';
  render();
}
async function needsUpdate() {
  // La app Android agrega "Fiape/<versión>" a su navegador interno; si hay un APK más nuevo, se obliga a actualizar.
  const m = navigator.userAgent.match(/Fiape\/(\d+)/); if (!m) return false;
  try {
    const v = await (await fetch('version.json?t=' + Date.now(), { cache: 'no-store' })).json();
    if (+v.apk > +m[1]) {
      root.innerHTML = `<div class="upd"><div style="max-width:340px"><img src="icon-192.png" alt="" style="width:80px;border-radius:20px">
        <h1 style="margin-top:14px">Hay una nueva versión</h1><p>Para seguir usando Fiapé descarga e instala la actualización.</p>
        <a class="btn" href="${esc(v.url || C.APK_URL)}">Descargar actualización</a></div></div>`;
      return true;
    }
  } catch {}
  return false;
}
(async () => {
  try {
    await api.init();
    if (await needsUpdate()) return;
    api.onRecovery(newPassSheet);
    await boot();
  } catch (e) {
    root.innerHTML = `<main class="wrap"><section class="card"><h2>Sin conexión</h2><p>${esc(msg(e))}</p><button class="btn" onclick="location.reload()">Reintentar</button></section></main>`;
  }
  if ('serviceWorker' in navigator && !window.FIAPE_TEST_API) navigator.serviceWorker.register('sw.js').catch(() => {});
})();
}
