// Solo para pruebas locales con tests/servidor_prueba.py. La app real usa Supabase.
window.FIAPE_TEST_API = (() => {
  const K = 'fiape_test_user';
  const U = () => sessionStorage.getItem(K);
  const post = async (p, b) => { const r = await fetch(p, { method: 'POST', body: JSON.stringify(b) }); const j = await r.json(); if (j.error) throw new Error(j.error); return j.data; };
  class Q { constructor() { this.ops = []; } eq(c, v) { this.ops.push(['eq', c, v]); return this; } in(c, a) { this.ops.push(['in', c, a]); return this; } }
  const b64 = blob => new Promise(r => { const f = new FileReader(); f.onload = () => r(String(f.result).split(',')[1]); f.readAsDataURL(blob); });
  return {
    async init() {}, async session() { return U() ? { id: U() } : null; },
    async signIn(e) { sessionStorage.setItem(K, await post('/login', { email: e })); },
    async signUp(v) { sessionStorage.setItem(K, await post('/signup', v)); return true; },
    async signOut() { sessionStorage.removeItem(K); }, async reset() {}, async newPassword() {}, onRecovery() {},
    rpc: (fn, args = {}) => post('/rpc', { u: U(), fn, args }),
    select: (t, build) => { const q = new Q(); if (build) build(q); return post('/select', { u: U(), t, ops: q.ops }); },
    async upload(bucket, path, blob) { await post('/upload', { u: U(), bucket, path, b64: await b64(blob) }); return path; },
    async signed(b, p) { return `/file?b=${encodeURIComponent(b)}&p=${encodeURIComponent(p)}&u=${U()}`; }
  };
})();
