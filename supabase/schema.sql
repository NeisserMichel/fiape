-- =====================================================================
--  FIAPÉ · Base de datos (Supabase / PostgreSQL)
--  Plataforma de reputación: calificación de personas de 1 a 10 estrellas
--
--  Pegar TODO este archivo en Supabase > SQL Editor > New query > Run.
--  Se puede volver a ejecutar: no borra datos.
-- =====================================================================
--  Contenido:
--    1. Extensiones
--    2. Tipos
--    3. Tablas (departamentos, personas, perfiles, verificaciones,
--       calificaciones, busquedas)
--    4. Funciones auxiliares y triggers
--    5. Registro automático de usuarios (trigger sobre auth.users)
--    6. Funciones (RPC) que usará la web/app
--    7. Funciones de administrador
--    8. Almacenamiento privado de fotos del DNI
--    9. Seguridad: RLS y permisos
--
--  Códigos de error: todas las funciones lanzan errores con un código
--  en MAYÚSCULAS (p. ej. CUENTA_NO_VERIFICADA) que la web/app traduce
--  a un mensaje amigable.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. EXTENSIONES
-- ---------------------------------------------------------------------
create extension if not exists unaccent with schema extensions;
create extension if not exists pg_trgm  with schema extensions;


-- ---------------------------------------------------------------------
-- 2. TIPOS
-- ---------------------------------------------------------------------
-- Estado de la cuenta del usuario
do $$ begin
create type public.estado_verificacion as enum (
  'pendiente_envio',  -- registrado, aún no envía sus fotos
  'en_revision',      -- envió fotos, espera revisión del administrador
  'verificado',       -- aprobado: puede buscar, registrar y calificar
  'rechazado',        -- rechazado, puede reintentar (si le quedan intentos)
  'bloqueado'         -- agotó sus 3 intentos: debe contactar a soporte
);
exception when duplicate_object then null;
end $$;

-- Estado de cada solicitud de verificación (cada envío de fotos)
do $$ begin
  create type public.estado_solicitud as enum ('en_revision', 'aprobada', 'rechazada');
exception when duplicate_object then null;
end $$;


-- ---------------------------------------------------------------------
-- 3. TABLAS
-- ---------------------------------------------------------------------

-- 3.1 Departamentos del Perú (24 departamentos + Callao)
create table if not exists public.departamentos (
  id     smallint primary key,
  nombre text not null unique
);

insert into public.departamentos (id, nombre) values
  (1,  'Amazonas'),     (2,  'Áncash'),        (3,  'Apurímac'),
  (4,  'Arequipa'),     (5,  'Ayacucho'),      (6,  'Cajamarca'),
  (7,  'Callao'),       (8,  'Cusco'),         (9,  'Huancavelica'),
  (10, 'Huánuco'),      (11, 'Ica'),           (12, 'Junín'),
  (13, 'La Libertad'),  (14, 'Lambayeque'),    (15, 'Lima'),
  (16, 'Loreto'),       (17, 'Madre de Dios'), (18, 'Moquegua'),
  (19, 'Pasco'),        (20, 'Piura'),         (21, 'Puno'),
  (22, 'San Martín'),   (23, 'Tacna'),         (24, 'Tumbes'),
  (25, 'Ucayali')
on conflict (id) do nothing;

-- 3.2 Personas: la base de datos consultable.
--     Incluye a todos los usuarios registrados y a las personas que
--     los usuarios registran para calificarlas.
create table if not exists public.personas (
  id                    uuid primary key default gen_random_uuid(),
  dni                   text not null unique check (dni ~ '^[0-9]{8}$'),
  nombres               text not null,
  apellido_paterno      text not null,
  apellido_materno      text,
  departamento_id       smallint references public.departamentos (id),
  -- Cuenta de usuario dueña de este perfil (null si nadie la reclamó aún)
  user_id               uuid unique references auth.users (id) on delete set null,
  -- Usuario que registró a esta persona
  registrado_por        uuid references auth.users (id) on delete set null,
  -- Campos calculados automáticamente
  nombre_busqueda       text not null default '',
  total_calificaciones  integer not null default 0,
  suma_estrellas        integer not null default 0,
  promedio              numeric(4,2),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index if not exists personas_nombre_trgm_idx
  on public.personas using gin (nombre_busqueda extensions.gin_trgm_ops);
create index if not exists personas_ranking_idx
  on public.personas (departamento_id, promedio desc, total_calificaciones desc)
  where total_calificaciones >= 5;

-- 3.3 Perfiles: una fila por cada cuenta de usuario.
--     Guarda los datos tal como el usuario los declaró al registrarse
--     (se comparan con las fotos del DNI) y su estado de verificación.
create table if not exists public.perfiles (
  id                     uuid primary key references auth.users (id) on delete cascade,
  persona_id             uuid not null unique references public.personas (id),
  nombres                text not null,
  apellido_paterno       text not null,
  apellido_materno       text,
  departamento_id        smallint not null references public.departamentos (id),
  estado                 public.estado_verificacion not null default 'pendiente_envio',
  intentos_verificacion  smallint not null default 0,
  es_admin               boolean not null default false,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

-- 3.4 Verificaciones: cada envío de las 3 fotos
create table if not exists public.verificaciones (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.perfiles (id) on delete cascade,
  intento           smallint not null check (intento between 1 and 10),
  foto_dni_anverso  text not null,
  foto_dni_reverso  text not null,
  foto_selfie_dni   text not null,
  estado            public.estado_solicitud not null default 'en_revision',
  motivo_rechazo    text,
  revisado_por      uuid references auth.users (id) on delete set null,
  revisado_at       timestamptz,
  created_at        timestamptz not null default now()
);

-- Solo una solicitud en revisión a la vez por usuario
create unique index if not exists verificaciones_una_en_revision_idx
  on public.verificaciones (user_id) where estado = 'en_revision';
create index if not exists verificaciones_estado_idx on public.verificaciones (estado, created_at);

-- 3.5 Calificaciones: una por usuario y persona (editable)
create table if not exists public.calificaciones (
  id          uuid primary key default gen_random_uuid(),
  persona_id  uuid not null references public.personas (id) on delete cascade,
  autor_id    uuid not null references auth.users (id) on delete cascade,
  estrellas   smallint not null check (estrellas between 1 and 10),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (persona_id, autor_id)
);

create index if not exists calificaciones_autor_idx on public.calificaciones (autor_id);

-- 3.6 Búsquedas: registro de búsquedas.
--     Sirve para exigir que el usuario busque ANTES de registrar o
--     calificar a una persona.
create table if not exists public.busquedas (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  consulta    text not null,
  tipo        text not null check (tipo in ('dni', 'nombre')),
  resultados  integer not null,
  persona_ids uuid[] not null default '{}',
  created_at  timestamptz not null default now()
);

create index if not exists busquedas_usuario_idx on public.busquedas (user_id, created_at desc);


-- ---------------------------------------------------------------------
-- 4. FUNCIONES AUXILIARES Y TRIGGERS
-- ---------------------------------------------------------------------

-- Texto en minúsculas y sin tildes (para búsquedas)
create or replace function public.normalizar_texto(t text)
returns text
language sql immutable parallel safe
set search_path = ''
as $$
  select regexp_replace(
           trim(lower(extensions.unaccent('extensions.unaccent'::regdictionary, coalesce(t, '')))),
           '\s+', ' ', 'g')
$$;

-- Nombre limpio: sin espacios dobles y en MAYÚSCULAS (como en el DNI)
create or replace function public.limpiar_nombre(t text)
returns text
language sql immutable parallel safe
set search_path = ''
as $$
  select nullif(upper(regexp_replace(trim(coalesce(t, '')), '\s+', ' ', 'g')), '')
$$;

-- ¿Es un nombre/apellido válido? (letras, tildes, ñ, espacios, apóstrofo, guion)
create or replace function public.nombre_valido(t text)
returns boolean
language sql immutable parallel safe
set search_path = ''
as $$
  select t is not null
     and char_length(t) between 2 and 60
     and t ~ '^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ'' .-]+$'
$$;

-- Nombre completo de una persona
create or replace function public.nombre_completo(p public.personas)
returns text
language sql immutable
set search_path = ''
as $$
  select p.nombres || ' ' || p.apellido_paterno || coalesce(' ' || p.apellido_materno, '')
$$;

-- Trigger: normaliza nombres y prepara el campo de búsqueda
create or replace function public.tg_personas_normalizar()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.nombres          := public.limpiar_nombre(new.nombres);
  new.apellido_paterno := public.limpiar_nombre(new.apellido_paterno);
  new.apellido_materno := public.limpiar_nombre(new.apellido_materno);

  if not public.nombre_valido(new.nombres) then
    raise exception 'NOMBRES_INVALIDOS';
  end if;
  if not public.nombre_valido(new.apellido_paterno) then
    raise exception 'APELLIDO_PATERNO_INVALIDO';
  end if;
  if new.apellido_materno is not null and not public.nombre_valido(new.apellido_materno) then
    raise exception 'APELLIDO_MATERNO_INVALIDO';
  end if;

  new.nombre_busqueda := public.normalizar_texto(
    new.nombres || ' ' || new.apellido_paterno || ' ' || coalesce(new.apellido_materno, ''));
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists personas_normalizar on public.personas;
create trigger personas_normalizar
  before insert or update of nombres, apellido_paterno, apellido_materno on public.personas
  for each row execute function public.tg_personas_normalizar();

-- Trigger: recalcula el promedio cada vez que cambia una calificación
create or replace function public.tg_recalcular_promedio()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[];
begin
  if tg_op = 'DELETE' then
    v_ids := array[old.persona_id];
  elsif tg_op = 'UPDATE' then
    v_ids := array[old.persona_id, new.persona_id];
  else
    v_ids := array[new.persona_id];
  end if;

  update public.personas p
     set total_calificaciones = s.total,
         suma_estrellas       = s.suma,
         promedio             = case when s.total > 0
                                     then round(s.suma::numeric / s.total, 2) end
    from (
      select u.pid,
             count(c.id)::int                   as total,
             coalesce(sum(c.estrellas), 0)::int as suma
        from (select distinct x as pid from unnest(v_ids) as x) u
        left join public.calificaciones c on c.persona_id = u.pid
       group by u.pid
    ) s
   where p.id = s.pid;

  return null;
end;
$$;

drop trigger if exists calificaciones_recalcular on public.calificaciones;
create trigger calificaciones_recalcular
  after insert or update or delete on public.calificaciones
  for each row execute function public.tg_recalcular_promedio();

-- Trigger genérico: updated_at
create or replace function public.tg_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists perfiles_updated_at on public.perfiles;
create trigger perfiles_updated_at
  before update on public.perfiles
  for each row execute function public.tg_updated_at();

-- ¿El usuario actual es administrador?
create or replace function public.es_admin()
returns boolean
language sql stable
security definer
set search_path = ''
as $$
  select coalesce((select es_admin from public.perfiles where id = auth.uid()), false)
$$;

-- Exige sesión iniciada y cuenta verificada. Devuelve el id del usuario.
create or replace function public.requerir_verificado()
returns uuid
language plpgsql stable
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_estado public.estado_verificacion;
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO';
  end if;

  select estado into v_estado from public.perfiles where id = v_uid;

  if v_estado is distinct from 'verificado' then
    raise exception 'CUENTA_NO_VERIFICADA';
  end if;

  return v_uid;
end;
$$;


-- ---------------------------------------------------------------------
-- 5. REGISTRO AUTOMÁTICO DE USUARIOS
-- ---------------------------------------------------------------------
-- La web/app llama a supabase.auth.signUp({ email, password,
--   options: { data: { dni, nombres, apellido_paterno,
--                      apellido_materno, departamento_id } } })
-- y este trigger:
--   • valida los datos obligatorios,
--   • si el DNI ya fue registrado por otro usuario (sin cuenta),
--     lo une a la nueva cuenta (conserva sus calificaciones),
--   • si el DNI ya tiene cuenta, rechaza el registro,
--   • si no existe, crea a la persona (entra a la base consultable),
--   • crea su perfil en estado 'pendiente_envio'.
create or replace function public.tg_nuevo_usuario()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  m          jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_dni      text  := trim(m ->> 'dni');
  v_nombres  text  := public.limpiar_nombre(m ->> 'nombres');
  v_ap       text  := public.limpiar_nombre(m ->> 'apellido_paterno');
  v_am       text  := public.limpiar_nombre(m ->> 'apellido_materno');
  v_dep      smallint;
  v_persona  public.personas%rowtype;
begin
  if v_dni is null or v_dni !~ '^[0-9]{8}$' then
    raise exception 'DNI_INVALIDO';
  end if;
  if not public.nombre_valido(v_nombres) then
    raise exception 'NOMBRES_INVALIDOS';
  end if;
  if not public.nombre_valido(v_ap) then
    raise exception 'APELLIDO_PATERNO_INVALIDO';
  end if;
  if v_am is not null and not public.nombre_valido(v_am) then
    raise exception 'APELLIDO_MATERNO_INVALIDO';
  end if;

  begin
    v_dep := (m ->> 'departamento_id')::smallint;
  exception when others then
    v_dep := null;
  end;
  if v_dep is null or not exists (select 1 from public.departamentos where id = v_dep) then
    raise exception 'DEPARTAMENTO_OBLIGATORIO';
  end if;

  select * into v_persona from public.personas where dni = v_dni for update;

  if found then
    if v_persona.user_id is not null then
      raise exception 'DNI_YA_REGISTRADO';
    end if;
    -- La persona ya existía (la registró otro usuario): se une a esta cuenta.
    -- Sus nombres oficiales se actualizan cuando el admin aprueba el DNI.
    update public.personas
       set user_id         = new.id,
           departamento_id = coalesce(departamento_id, v_dep)
     where id = v_persona.id;
  else
    insert into public.personas
      (dni, nombres, apellido_paterno, apellido_materno, departamento_id, user_id, registrado_por)
    values
      (v_dni, v_nombres, v_ap, v_am, v_dep, new.id, new.id)
    returning * into v_persona;
  end if;

  insert into public.perfiles
    (id, persona_id, nombres, apellido_paterno, apellido_materno, departamento_id)
  values
    (new.id, v_persona.id, v_nombres, v_ap, v_am, v_dep);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.tg_nuevo_usuario();


-- ---------------------------------------------------------------------
-- 6. FUNCIONES (RPC) PARA LA WEB / APP
-- ---------------------------------------------------------------------

-- 6.1 Antes del registro: ¿este DNI ya tiene cuenta?
--     (para mostrar un mensaje claro en el formulario de registro)
create or replace function public.dni_tiene_cuenta(p_dni text)
returns boolean
language sql stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.personas
     where dni = trim(p_dni) and user_id is not null)
$$;

-- 6.2 Mi perfil: datos y estado de verificación del usuario actual
create or replace function public.mi_perfil()
returns table (
  dni                     text,
  nombres                 text,
  apellido_paterno        text,
  apellido_materno        text,
  departamento_id         smallint,
  departamento            text,
  estado                  public.estado_verificacion,
  intentos_usados         smallint,
  intentos_restantes      smallint,
  ultimo_motivo_rechazo   text,
  es_admin                boolean,
  promedio                numeric,
  total_calificaciones    integer
)
language sql stable
security definer
set search_path = ''
as $$
  select p.dni, f.nombres, f.apellido_paterno, f.apellido_materno,
         f.departamento_id, d.nombre, f.estado,
         f.intentos_verificacion,
         greatest(0, 3 - f.intentos_verificacion)::smallint,
         (select v.motivo_rechazo from public.verificaciones v
           where v.user_id = f.id and v.estado = 'rechazada'
           order by v.created_at desc limit 1),
         f.es_admin, p.promedio, p.total_calificaciones
    from public.perfiles f
    join public.personas p      on p.id = f.persona_id
    join public.departamentos d on d.id = f.departamento_id
   where f.id = auth.uid()
$$;

-- 6.3 Enviar las 3 fotos para verificación.
--     Antes, la web/app sube las fotos al bucket 'verificaciones' en la
--     carpeta del usuario: <user_id>/<archivo>.jpg
create or replace function public.enviar_verificacion(
  p_foto_dni_anverso text,
  p_foto_dni_reverso text,
  p_foto_selfie_dni  text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_perfil public.perfiles%rowtype;
  v_foto   text;
  v_id     uuid;
begin
  if v_uid is null then
    raise exception 'NO_AUTENTICADO';
  end if;

  select * into v_perfil from public.perfiles where id = v_uid for update;
  if not found then
    raise exception 'PERFIL_NO_EXISTE';
  end if;

  if v_perfil.estado = 'verificado' then
    raise exception 'YA_VERIFICADO';
  elsif v_perfil.estado = 'en_revision' then
    raise exception 'VERIFICACION_EN_REVISION';
  elsif v_perfil.estado = 'bloqueado' or v_perfil.intentos_verificacion >= 3 then
    raise exception 'LIMITE_INTENTOS_ALCANZADO';
  end if;

  if p_foto_dni_anverso = p_foto_dni_reverso
     or p_foto_dni_anverso = p_foto_selfie_dni
     or p_foto_dni_reverso = p_foto_selfie_dni then
    raise exception 'FOTOS_DEBEN_SER_DISTINTAS';
  end if;

  foreach v_foto in array array[p_foto_dni_anverso, p_foto_dni_reverso, p_foto_selfie_dni] loop
    if v_foto is null or split_part(v_foto, '/', 1) <> v_uid::text then
      raise exception 'RUTA_FOTO_INVALIDA';
    end if;
    if not exists (select 1 from storage.objects
                    where bucket_id = 'verificaciones' and name = v_foto) then
      raise exception 'FOTO_NO_ENCONTRADA';
    end if;
  end loop;

  insert into public.verificaciones
    (user_id, intento, foto_dni_anverso, foto_dni_reverso, foto_selfie_dni)
  values
    (v_uid, v_perfil.intentos_verificacion + 1,
     p_foto_dni_anverso, p_foto_dni_reverso, p_foto_selfie_dni)
  returning id into v_id;

  update public.perfiles
     set estado = 'en_revision',
         intentos_verificacion = intentos_verificacion + 1
   where id = v_uid;

  return v_id;
end;
$$;

-- 6.4 Buscar personas (OBLIGATORIO antes de registrar o calificar).
--     • 8 dígitos  → búsqueda exacta por DNI
--     • texto      → búsqueda por nombres y apellidos (sin importar tildes)
create or replace function public.buscar_personas(p_consulta text)
returns table (
  id                    uuid,
  dni                   text,
  nombre_completo       text,
  departamento          text,
  promedio              numeric,
  total_calificaciones  integer,
  tiene_cuenta          boolean,
  mi_calificacion       smallint,
  soy_yo                boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := public.requerir_verificado();
  v_q       text := trim(coalesce(p_consulta, ''));
  v_tipo    text;
  v_ids     uuid[];
  v_tokens  text[];
begin
  if v_q ~ '^[0-9]+$' then
    if v_q !~ '^[0-9]{8}$' then
      raise exception 'DNI_INVALIDO';
    end if;
    v_tipo := 'dni';
    select coalesce(array_agg(p.id), '{}') into v_ids
      from public.personas p where p.dni = v_q;
  else
    v_q := regexp_replace(public.normalizar_texto(v_q), '[^a-z'' -]', '', 'g');
    v_q := regexp_replace(trim(v_q), '\s+', ' ', 'g');
    if char_length(replace(v_q, ' ', '')) < 3 then
      raise exception 'CONSULTA_MUY_CORTA';
    end if;
    v_tipo   := 'nombre';
    v_tokens := array(select '%' || t || '%'
                        from unnest(string_to_array(v_q, ' ')) t
                       where t <> '');
    select coalesce(array_agg(s.id order by s.orden), '{}') into v_ids
      from (
        select p.id,
               row_number() over (
                 order by extensions.similarity(p.nombre_busqueda, v_q) desc,
                          p.total_calificaciones desc) as orden
          from public.personas p
         where p.nombre_busqueda like all (v_tokens)
         order by orden
         limit 20
      ) s;
  end if;

  insert into public.busquedas (user_id, consulta, tipo, resultados, persona_ids)
  values (v_uid, v_q, v_tipo, coalesce(array_length(v_ids, 1), 0), v_ids);

  return query
    select p.id, p.dni, public.nombre_completo(p), d.nombre,
           p.promedio, p.total_calificaciones,
           (p.user_id is not null),
           c.estrellas,
           (p.user_id = v_uid)
      from unnest(v_ids) with ordinality as u(pid, orden)
      join public.personas p           on p.id = u.pid
      left join public.departamentos d on d.id = p.departamento_id
      left join public.calificaciones c on c.persona_id = p.id and c.autor_id = v_uid
     order by u.orden;
end;
$$;

-- 6.5 Registrar a una persona nueva.
--     Solo se permite si el usuario buscó ese DNI en los últimos
--     30 minutos y la búsqueda no encontró a nadie.
create or replace function public.registrar_persona(
  p_dni              text,
  p_nombres          text,
  p_apellido_paterno text,
  p_apellido_materno text default null,
  p_departamento_id  smallint default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := public.requerir_verificado();
  v_dni text := trim(coalesce(p_dni, ''));
  v_id  uuid;
begin
  if v_dni !~ '^[0-9]{8}$' then
    raise exception 'DNI_INVALIDO';
  end if;

  if exists (select 1 from public.personas where dni = v_dni) then
    raise exception 'PERSONA_YA_EXISTE';
  end if;

  if not exists (
    select 1 from public.busquedas b
     where b.user_id = v_uid and b.tipo = 'dni' and b.consulta = v_dni
       and b.resultados = 0 and b.created_at > now() - interval '30 minutes'
  ) then
    raise exception 'BUSQUEDA_PREVIA_REQUERIDA';
  end if;

  -- Límite anti-spam: 20 personas registradas por día y usuario
  if (select count(*) from public.personas
       where registrado_por = v_uid and created_at > now() - interval '1 day') >= 20 then
    raise exception 'LIMITE_REGISTROS_DIARIO';
  end if;

  if p_departamento_id is not null
     and not exists (select 1 from public.departamentos where id = p_departamento_id) then
    raise exception 'DEPARTAMENTO_INVALIDO';
  end if;

  insert into public.personas
    (dni, nombres, apellido_paterno, apellido_materno, departamento_id, registrado_por)
  values
    (v_dni, p_nombres, p_apellido_paterno, nullif(trim(p_apellido_materno), ''),
     p_departamento_id, v_uid)
  returning id into v_id;

  return v_id;
end;
$$;

-- 6.6 Calificar (o cambiar la calificación) de 1 a 10 estrellas.
--     Exige que la persona haya aparecido en una búsqueda del usuario
--     en las últimas 2 horas (o que el propio usuario la haya registrado).
create or replace function public.calificar(p_persona_id uuid, p_estrellas smallint)
returns table (promedio numeric, total_calificaciones integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := public.requerir_verificado();
  v_persona public.personas%rowtype;
begin
  if p_estrellas is null or p_estrellas not between 1 and 10 then
    raise exception 'ESTRELLAS_FUERA_DE_RANGO';
  end if;

  select * into v_persona from public.personas where id = p_persona_id;
  if not found then
    raise exception 'PERSONA_NO_EXISTE';
  end if;

  if v_persona.user_id = v_uid then
    raise exception 'NO_PUEDES_CALIFICARTE';
  end if;

  if v_persona.registrado_por is distinct from v_uid and not exists (
    select 1 from public.busquedas b
     where b.user_id = v_uid and p_persona_id = any (b.persona_ids)
       and b.created_at > now() - interval '2 hours'
  ) then
    raise exception 'BUSQUEDA_PREVIA_REQUERIDA';
  end if;

  insert into public.calificaciones (persona_id, autor_id, estrellas)
  values (p_persona_id, v_uid, p_estrellas)
  on conflict (persona_id, autor_id)
  do update set estrellas = excluded.estrellas, updated_at = now();

  return query
    select p.promedio, p.total_calificaciones
      from public.personas p where p.id = p_persona_id;
end;
$$;

-- 6.7 Ranking: Top 100 personas más confiables de un departamento
--     (mínimo 5 calificaciones; no muestra el DNI)
create or replace function public.ranking_departamento(p_departamento_id smallint)
returns table (
  puesto                integer,
  persona_id            uuid,
  nombre_completo       text,
  promedio              numeric,
  total_calificaciones  integer
)
language sql stable
security definer
set search_path = ''
as $$
  select (row_number() over (
            order by p.promedio desc, p.total_calificaciones desc, p.created_at))::int,
         p.id, public.nombre_completo(p), p.promedio, p.total_calificaciones
    from public.personas p
   where p.departamento_id = p_departamento_id
     and p.total_calificaciones >= 5
   order by 1
   limit 100
$$;


-- ---------------------------------------------------------------------
-- 7. FUNCIONES DE ADMINISTRADOR
-- ---------------------------------------------------------------------

-- 7.1 Lista de solicitudes de verificación (por defecto, las pendientes)
create or replace function public.admin_listar_verificaciones(
  p_estado public.estado_solicitud default 'en_revision'
)
returns table (
  verificacion_id   uuid,
  user_id           uuid,
  dni               text,
  nombres           text,
  apellido_paterno  text,
  apellido_materno  text,
  departamento      text,
  intento           smallint,
  foto_dni_anverso  text,
  foto_dni_reverso  text,
  foto_selfie_dni   text,
  estado            public.estado_solicitud,
  motivo_rechazo    text,
  enviado_at        timestamptz
)
language plpgsql stable
security definer
set search_path = ''
as $$
begin
  if not public.es_admin() then
    raise exception 'SOLO_ADMIN';
  end if;

  return query
    select v.id, v.user_id, p.dni, f.nombres, f.apellido_paterno, f.apellido_materno,
           d.nombre, v.intento, v.foto_dni_anverso, v.foto_dni_reverso,
           v.foto_selfie_dni, v.estado, v.motivo_rechazo, v.created_at
      from public.verificaciones v
      join public.perfiles f      on f.id = v.user_id
      join public.personas p      on p.id = f.persona_id
      join public.departamentos d on d.id = f.departamento_id
     where v.estado = p_estado
     order by v.created_at;
end;
$$;

-- 7.2 Aprobar o rechazar una verificación
create or replace function public.admin_revisar_verificacion(
  p_verificacion_id uuid,
  p_aprobar         boolean,
  p_motivo          text default null
)
returns public.estado_verificacion
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin  uuid := auth.uid();
  v_ver    public.verificaciones%rowtype;
  v_perfil public.perfiles%rowtype;
  v_estado public.estado_verificacion;
begin
  if not public.es_admin() then
    raise exception 'SOLO_ADMIN';
  end if;

  select * into v_ver from public.verificaciones where id = p_verificacion_id for update;
  if not found then
    raise exception 'VERIFICACION_NO_EXISTE';
  end if;
  if v_ver.estado <> 'en_revision' then
    raise exception 'VERIFICACION_YA_REVISADA';
  end if;
  if v_ver.user_id = v_admin then
    raise exception 'NO_PUEDES_REVISARTE';
  end if;

  select * into v_perfil from public.perfiles where id = v_ver.user_id for update;

  if p_aprobar then
    update public.verificaciones
       set estado = 'aprobada', revisado_por = v_admin, revisado_at = now()
     where id = v_ver.id;

    v_estado := 'verificado';

    -- Los datos verificados pasan a ser los oficiales de la persona
    update public.personas
       set nombres          = v_perfil.nombres,
           apellido_paterno = v_perfil.apellido_paterno,
           apellido_materno = v_perfil.apellido_materno,
           departamento_id  = v_perfil.departamento_id
     where id = v_perfil.persona_id;
  else
    if coalesce(trim(p_motivo), '') = '' then
      raise exception 'MOTIVO_REQUERIDO';
    end if;

    update public.verificaciones
       set estado = 'rechazada', motivo_rechazo = trim(p_motivo),
           revisado_por = v_admin, revisado_at = now()
     where id = v_ver.id;

    v_estado := case when v_perfil.intentos_verificacion >= 3
                     then 'bloqueado' else 'rechazado' end;
  end if;

  update public.perfiles set estado = v_estado where id = v_perfil.id;

  return v_estado;
end;
$$;

-- 7.3 Dar un intento extra a un usuario bloqueado (atención de soporte)
create or replace function public.admin_habilitar_reintento(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.es_admin() then
    raise exception 'SOLO_ADMIN';
  end if;

  update public.perfiles
     set estado = 'rechazado', intentos_verificacion = 2
   where id = p_user_id and estado = 'bloqueado';

  if not found then
    raise exception 'USUARIO_NO_BLOQUEADO';
  end if;
end;
$$;


-- ---------------------------------------------------------------------
-- 8. ALMACENAMIENTO PRIVADO DE FOTOS DEL DNI
-- ---------------------------------------------------------------------
-- Bucket privado: máx. 5 MB por foto; solo JPG, PNG o WEBP.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('verificaciones', 'verificaciones', false, 5242880,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- Cada usuario sube fotos solo a su carpeta: <user_id>/...
drop policy if exists "verificaciones: subir en carpeta propia" on storage.objects;
create policy "verificaciones: subir en carpeta propia"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'verificaciones'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Cada usuario ve solo sus fotos; los administradores ven todas.
-- Nadie más puede verlas.
drop policy if exists "verificaciones: ver propias o admin" on storage.objects;
create policy "verificaciones: ver propias o admin"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'verificaciones'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.es_admin())
  );


-- ---------------------------------------------------------------------
-- 9. SEGURIDAD: RLS Y PERMISOS
-- ---------------------------------------------------------------------
alter table public.departamentos  enable row level security;
alter table public.personas       enable row level security;
alter table public.perfiles       enable row level security;
alter table public.verificaciones enable row level security;
alter table public.calificaciones enable row level security;
alter table public.busquedas      enable row level security;

-- Lectura directa permitida (todo lo demás pasa por las funciones RPC)
drop policy if exists "departamentos: lectura pública" on public.departamentos;
create policy "departamentos: lectura pública"
  on public.departamentos for select to anon, authenticated using (true);

drop policy if exists "perfiles: ver el propio o admin" on public.perfiles;
create policy "perfiles: ver el propio o admin"
  on public.perfiles for select to authenticated
  using (id = auth.uid() or public.es_admin());

drop policy if exists "personas: solo admin" on public.personas;
create policy "personas: solo admin"
  on public.personas for select to authenticated
  using (public.es_admin());

drop policy if exists "verificaciones: ver las propias o admin" on public.verificaciones;
create policy "verificaciones: ver las propias o admin"
  on public.verificaciones for select to authenticated
  using (user_id = auth.uid() or public.es_admin());

-- Las calificaciones son anónimas: cada uno ve solo las suyas
drop policy if exists "calificaciones: ver las propias o admin" on public.calificaciones;
create policy "calificaciones: ver las propias o admin"
  on public.calificaciones for select to authenticated
  using (autor_id = auth.uid() or public.es_admin());

-- Lectura: los proyectos nuevos de Supabase ya no dan permisos automáticos a las
-- tablas, así que se dan aquí. Las políticas RLS de arriba deciden qué filas ve cada uno.
grant usage on schema public to anon, authenticated;
grant select on public.departamentos to anon, authenticated;
grant select on public.personas, public.perfiles, public.verificaciones, public.calificaciones to authenticated;

-- Nadie escribe directo en las tablas: solo a través de las funciones
revoke insert, update, delete, truncate on all tables in schema public from anon, authenticated;
revoke all on public.busquedas from anon, authenticated;

-- Funciones: quitar permisos por defecto y dar solo los necesarios
revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.dni_tiene_cuenta(text)                      to anon, authenticated;
grant execute on function public.mi_perfil()                                 to authenticated;
grant execute on function public.enviar_verificacion(text, text, text)       to authenticated;
grant execute on function public.buscar_personas(text)                       to authenticated;
grant execute on function public.registrar_persona(text, text, text, text, smallint) to authenticated;
grant execute on function public.calificar(uuid, smallint)                   to authenticated;
grant execute on function public.ranking_departamento(smallint)              to authenticated;
grant execute on function public.admin_listar_verificaciones(public.estado_solicitud) to authenticated;
grant execute on function public.admin_revisar_verificacion(uuid, boolean, text) to authenticated;
grant execute on function public.admin_habilitar_reintento(uuid)             to authenticated;
-- Usadas dentro de las políticas RLS
grant execute on function public.es_admin()                                  to authenticated;
grant execute on function public.nombre_completo(public.personas)            to authenticated;
grant execute on function public.normalizar_texto(text)                      to authenticated;
