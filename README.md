# Fiapé · Base de datos (Supabase)

Plataforma de reputación para Perú: los usuarios verificados califican a personas de **1 a 10 estrellas**, se muestra el **promedio** y un **Top 100 por departamento**.

```
fiape/
├── supabase/migrations/20261126000000_esquema_inicial.sql   ← la base de datos completa
└── test/                                                    ← pruebas automáticas (opcional)
```

---

## Paso 1 · Crear el repositorio en GitHub

1. Entra a <https://github.com/new>.
2. Nombre: `fiape` · Visibilidad: **Private** · Crear.
3. Sube esta carpeta (desde tu computadora, dentro de `fiape/`):
   ```bash
   git init
   git add .
   git commit -m "Base de datos inicial de Fiapé"
   git branch -M main
   git remote add origin https://github.com/TU_USUARIO/fiape.git
   git push -u origin main
   ```

## Paso 2 · Crear el proyecto en Supabase

1. Entra a <https://supabase.com/dashboard> → **New project**.
2. Nombre: `fiape` · Región: **South America (São Paulo)** (la más cercana a Perú).
3. Guarda bien la contraseña de la base de datos.

## Paso 3 · Ejecutar la base de datos

**Opción fácil (recomendada):**
1. En Supabase abre **SQL Editor** → **New query**.
2. Copia todo el contenido de `supabase/migrations/20261126000000_esquema_inicial.sql`, pégalo y pulsa **Run**.
3. Debe decir *Success*. En **Table Editor** verás: `departamentos`, `personas`, `perfiles`, `verificaciones`, `calificaciones`, `busquedas`. En **Storage** verás el bucket privado `verificaciones`.

**Opción con la CLI de Supabase** (si prefieres automatizar):
```bash
npx supabase login
npx supabase link --project-ref TU_PROJECT_REF
npx supabase db push
```

## Paso 4 · Configurar el registro (Authentication)

En **Authentication → Providers → Email**:
- Activado: **Email**.
- Activado: **Confirm email** (recomendado, evita cuentas falsas).

> ⚠️ No crees usuarios con el botón "Add user" del panel de Supabase: ese formulario no envía DNI ni nombres y el registro será rechazado. Todos los usuarios se registran desde la web/app.

## Paso 5 · Nombrar al primer administrador

Cuando la web esté lista, regístrate normalmente con tu DNI. Luego, en **SQL Editor**, ejecuta (cambia el correo):

```sql
update public.perfiles
   set es_admin = true, estado = 'verificado'
 where id = (select id from auth.users where email = 'tu-correo@ejemplo.com');
```

Desde ahí, ese administrador aprueba o rechaza las verificaciones de los demás (un admin no puede aprobarse a sí mismo).

---

## Cómo funciona

| Regla del negocio | Cómo se cumple en la base de datos |
|---|---|
| Registro con DNI, nombres, apellidos y departamento obligatorios | El registro se rechaza si falta alguno o el DNI no tiene 8 dígitos |
| Todo usuario entra a la base consultable | Al registrarse se crea su ficha en `personas` |
| Si alguien ya registró ese DNI, la nueva cuenta lo reclama | Se une a la ficha existente y **conserva sus calificaciones** |
| Un DNI no puede tener dos cuentas | Error `DNI_YA_REGISTRADO` |
| Sin verificar no puede buscar ni registrar ni calificar | Error `CUENTA_NO_VERIFICADA` |
| 3 fotos: DNI anverso, reverso y selfie con el DNI | Se guardan en un bucket **privado**; solo el dueño y los admins las ven |
| Máximo 3 intentos de verificación | Al 3.er rechazo queda `bloqueado`; soporte puede dar un intento extra |
| Búsqueda obligatoria antes de registrar | Solo se registra un DNI si el usuario lo buscó en los últimos 30 min y no existía |
| Búsqueda obligatoria antes de calificar | Solo se califica a quien apareció en una búsqueda del usuario (últimas 2 h) |
| 1 a 10 estrellas, una por persona, editable | Calificar de nuevo reemplaza la anterior |
| Calificaciones anónimas, promedio público | Nadie ve quién calificó; el promedio se recalcula solo |
| No calificarse a uno mismo | Error `NO_PUEDES_CALIFICARTE` |
| Top 100 por departamento (mín. 5 calificaciones) | Función `ranking_departamento` (no muestra DNI) |
| Anti-spam | Máximo 20 personas registradas por usuario al día |

### Funciones para la web/app (`supabase.rpc(...)`)

| Función | Quién | Para qué |
|---|---|---|
| `dni_tiene_cuenta(p_dni)` | Cualquiera | Avisar en el formulario de registro si el DNI ya tiene cuenta |
| `mi_perfil()` | Usuario | Datos, estado de verificación, intentos restantes, motivo del último rechazo y su promedio |
| `enviar_verificacion(anverso, reverso, selfie)` | Usuario | Enviar las 3 fotos (antes se suben a `verificaciones/<user_id>/...`) |
| `buscar_personas(p_consulta)` | Verificado | Por DNI (8 dígitos) o por nombre (sin importar tildes); máx. 20 resultados |
| `registrar_persona(dni, nombres, ap_paterno, ap_materno, departamento_id)` | Verificado | Registrar a alguien que no apareció en la búsqueda |
| `calificar(persona_id, estrellas)` | Verificado | Calificar o cambiar la calificación; devuelve el nuevo promedio |
| `ranking_departamento(departamento_id)` | Usuario | Top 100 del departamento |
| `admin_listar_verificaciones(estado)` | Admin | Solicitudes pendientes con datos declarados y rutas de fotos |
| `admin_revisar_verificacion(id, aprobar, motivo)` | Admin | Aprobar o rechazar (rechazo exige motivo) |
| `admin_habilitar_reintento(user_id)` | Admin | Dar un intento extra a un usuario bloqueado |

Ejemplo de registro desde la web:
```js
await supabase.auth.signUp({
  email, password,
  options: { data: {
    dni: '12345678', nombres: 'Juan Carlos',
    apellido_paterno: 'Pérez', apellido_materno: 'Soto',
    departamento_id: 15   // Lima
  }}
})
```

### Códigos de error (para traducir a mensajes en la web/app)

`DNI_INVALIDO` · `NOMBRES_INVALIDOS` · `APELLIDO_PATERNO_INVALIDO` · `APELLIDO_MATERNO_INVALIDO` · `DEPARTAMENTO_OBLIGATORIO` · `DEPARTAMENTO_INVALIDO` · `DNI_YA_REGISTRADO` · `NO_AUTENTICADO` · `CUENTA_NO_VERIFICADA` · `YA_VERIFICADO` · `VERIFICACION_EN_REVISION` · `LIMITE_INTENTOS_ALCANZADO` · `FOTOS_DEBEN_SER_DISTINTAS` · `RUTA_FOTO_INVALIDA` · `FOTO_NO_ENCONTRADA` · `CONSULTA_MUY_CORTA` · `PERSONA_YA_EXISTE` · `BUSQUEDA_PREVIA_REQUERIDA` · `LIMITE_REGISTROS_DIARIO` · `ESTRELLAS_FUERA_DE_RANGO` · `PERSONA_NO_EXISTE` · `NO_PUEDES_CALIFICARTE` · `SOLO_ADMIN` · `VERIFICACION_NO_EXISTE` · `VERIFICACION_YA_REVISADA` · `NO_PUEDES_REVISARTE` · `MOTIVO_REQUERIDO` · `USUARIO_NO_BLOQUEADO`

---

## Pruebas (opcional, para desarrolladores)

`test/` contiene una simulación de Supabase y 57 comprobaciones del flujo completo (registro, verificación, bloqueo, búsqueda, calificación, ranking, reclamo de perfil y seguridad). Con PostgreSQL 15+ instalado:

```bash
createdb fiape_test
psql -d fiape_test -f test/supabase_stub.sql
psql -d fiape_test -f supabase/migrations/20261126000000_esquema_inicial.sql
psql -d fiape_test -f test/pruebas.sql      # termina con "TODAS LAS PRUEBAS PASARON"
```

## Pendiente antes del lanzamiento

- El DNI completo es visible en las búsquedas y no hay términos de uso, formulario de eliminación ni reportes. Bajo la **Ley 29733** esto es un riesgo legal; conviene revisarlo con un abogado antes de lanzar.
