# Fiapé

Plataforma de reputación para Perú: los usuarios **verificados con su DNI** califican a personas de **1 a 10 estrellas** (1 = nada recomendable, 10 = lo recomiendo totalmente). Se muestra públicamente el **promedio** de cada persona y un **Top 100 de las personas más confiables por departamento**.

| Carpeta / archivo | Qué es |
|---|---|
| `index.html` | Página web pública (cómo funciona, ranking, preguntas y descarga del APK) |
| `app/` | La app para usuarios y administradores. Se instala en el celular (PWA) |
| `app/config.js` | **Tus datos de Supabase** (URL y clave pública) — ya configurado |
| `supabase/schema.sql` | La base de datos completa: tablas, reglas, seguridad y fotos privadas del DNI |
| `supabase/tests/` | Pruebas automáticas de la base de datos (57 comprobaciones) |
| `android/` | App Android (abre la app web y da permiso de cámara para las fotos del DNI; sin acceso a la galería) |
| `.github/workflows/` | GitHub corre las pruebas y compila el APK solo |
| `tests/` | Servidor y prueba de navegador usados en desarrollo (53 comprobaciones; no se usan en producción) |

---

## Lo que debes hacer tú

### 1. Supabase ✅ (ya hecho)
- Proyecto `fiape` en São Paulo, `supabase/schema.sql` ejecutado y Site URL / Redirect URLs = `https://neissermichel.github.io/fiape/app/`.
- Revisa en **Authentication → Sign In / Providers → Email** que **Confirm email** esté activado.
- Antes de abrir al público configura un SMTP propio en **Authentication → Emails → SMTP Settings** (Brevo o Resend tienen planes gratis): el correo gratuito de Supabase solo envía unos pocos correos por hora.
- No crees usuarios con el botón **Add user** del panel: ese formulario no envía DNI ni nombres y el registro será rechazado.

### 2. Publicar la web y la app (GitHub Pages)
1. El repositorio debe ser **público** para usar GitHub Pages gratis. Es seguro: el código no tiene claves secretas; toda la protección de los datos está en Supabase.
   **Settings → General →** (abajo) **Danger Zone → Change visibility → Make public**.
2. **Settings → Pages → Source: Deploy from a branch → main / (root)** → Save.
3. En 1–2 minutos queda en `https://neissermichel.github.io/fiape/` y la app en `/app/`.

### 3. App Android (APK)
1. Guarda la llave de firma como secretos del repo (te la entregué en un archivo aparte, **nunca la subas al repositorio**):
   **Settings → Secrets and variables → Actions → New repository secret**, con los nombres `ANDROID_KEYSTORE_PASS` y `ANDROID_KEYSTORE_B64`.
2. **Actions → Compilar APK → Run workflow**.
3. Al terminar, el APK queda en la rama `apk-build` (`fiape.apk`) y el botón **Descargar app Android** de la web ya funciona.
4. **Actualización obligatoria:** cada vez que se compila un APK nuevo, GitHub actualiza `app/version.json` y las apps instaladas más antiguas muestran una pantalla que obliga a descargar la nueva versión. Los cambios de la web y de la app (pantallas, reglas) llegan solos, sin reinstalar.

### 4. Convertirte en administrador
1. Abre la app y **regístrate** con tu DNI, como cualquier usuario, y confirma tu correo.
2. En Supabase → SQL Editor, ejecuta (con tu correo):
   ```sql
   update public.perfiles set es_admin = true, estado = 'verificado'
    where id = (select id from auth.users where email = 'tucorreo@gmail.com');
   ```
3. Cierra sesión y vuelve a entrar. Verás la pestaña **Admin**: verificaciones pendientes (con las 3 fotos) y cuentas bloqueadas.

### Cuando haya una actualización de la base de datos
Vuelve a pegar TODO `supabase/schema.sql` en **SQL Editor → New query → Run**. Se puede ejecutar las veces que quieras: actualiza las reglas y no borra datos.

### 5. Antes de abrir al público
- [ ] **Legal (Ley 29733):** el DNI completo es visible en las búsquedas y aún no hay términos de uso, política de privacidad, formulario de eliminación de datos ni reportes de calificaciones. Revísalo con un abogado y registra el banco de datos personales ante la Autoridad Nacional de Protección de Datos Personales.
- [ ] **Supabase Pro (US$25/mes):** activa copias de seguridad diarias y evita que el proyecto se pause tras 1 semana sin uso. El plan gratis no tiene copias de seguridad.
- [ ] **Soporte:** pon tu número de WhatsApp en `WHATSAPP_SOPORTE` de `app/config.js` para que las cuentas bloqueadas puedan escribirte.

---

## Cómo funciona por dentro

- **Registro:** DNI (8 dígitos), nombres, apellidos y departamento obligatorios. Los nombres se escriben en MAYÚSCULAS, como en el DNI. Un DNI no puede tener dos cuentas.
- **Todo usuario entra a la base consultable.** Si otra persona ya había registrado ese DNI, la nueva cuenta lo reclama y **conserva sus calificaciones**.
- **Verificación:** foto del DNI por ambos lados + selfie con el DNI bajo el mentón, **tomadas en el momento con la cámara dentro de la app** (con recuadro guía); no se pueden subir fotos guardadas en el teléfono. Se comprimen en el celular y se guardan en almacenamiento **privado** (solo el dueño y los administradores las ven). El administrador aprueba o rechaza con motivo. Máximo **3 intentos**; luego la cuenta queda bloqueada hasta que el administrador habilite un intento extra.
- **Sin verificar** se puede entrar y ver el ranking, pero no buscar, registrar ni calificar.
- **Búsqueda obligatoria:** solo se registra a una persona si el usuario buscó su DNI en los últimos 30 minutos y no existía; solo se califica a quien apareció en una búsqueda del usuario (últimas 2 horas). Máximo 20 personas registradas por usuario al día.
- **Calificaciones anónimas:** una por persona, editable. Nadie ve quién calificó; el promedio se recalcula solo. Nadie puede calificarse a sí mismo.
- **Ranking:** Top 100 por departamento con mínimo 5 calificaciones (no muestra el DNI). Tocar a alguien lo busca para poder calificarlo.
- **Ninguna pantalla escribe directo en las tablas.** La app solo llama funciones de la base de datos (`buscar_personas`, `registrar_persona`, `calificar`, `enviar_verificacion`, `ranking_departamento`, `admin_revisar_verificacion`, etc.), que validan quién eres y qué te toca. **Cada quien ve solo lo suyo** (seguridad por filas).

## Probar en tu computadora (para desarrolladores)
Requiere PostgreSQL 16 con un servidor en `/tmp/pg`, puerto 5544:
- `sh supabase/tests/correr.sh` carga `schema.sql` dos veces y corre los 57 casos de la base de datos. GitHub también los corre solo en cada cambio de `supabase/` (**Actions → Pruebas de la base de datos**).
- `sh tests/correr_e2e.sh` (requiere Python, `psycopg2` y Playwright) abre la app en un navegador y prueba registro, verificación, rechazo, bloqueo, búsqueda, calificación, ranking, panel de administrador y actualización obligatoria del APK (53 casos).
