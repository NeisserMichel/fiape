\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

-- ===== utilidades de prueba =====
create schema test;
grant usage on schema test to anon, authenticated;
create function test.expect_error(p_sql text, p_msg text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm like '%' || p_msg || '%' then
      raise notice 'OK  error esperado: %', p_msg;
      return;
    end if;
    raise exception 'FALLO: esperaba "%" pero obtuvo "%"', p_msg, sqlerrm;
  end;
  raise exception 'FALLO: esperaba error "%" pero no hubo error', p_msg;
end $$;
create function test.ok(c boolean, msg text) returns void language plpgsql as $$
begin
  if c is not true then raise exception 'FALLO: %', msg; end if;
  raise notice 'OK  %', msg;
end $$;
grant execute on all functions in schema test to anon, authenticated;

-- ids fijos de usuarios de prueba
create function test.u(n int) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid $$;
grant execute on function test.u(int) to anon, authenticated;

create function test.signup(n int, meta jsonb) returns void language sql as $$
  insert into auth.users (id, email, raw_user_meta_data)
  values (test.u(n), 'u' || n || '@test.pe', meta) $$;

-- crea un usuario ya verificado (atajo para pruebas)
create function test.usuario_verificado(n int, dni text, dep int) returns void language plpgsql as $$
begin
  perform test.signup(n, jsonb_build_object('dni', dni, 'nombres', 'Usuario', 'apellido_paterno', 'Prueba' || chr(64+n),
                                             'apellido_materno', 'Test', 'departamento_id', dep));
  update public.perfiles set estado = 'verificado' where id = test.u(n);
end $$;

-- ===== 1. Registro =====
\echo '--- 1. Registro de usuarios'
select test.expect_error($$select test.signup(2, '{"dni":"1234","nombres":"Ana","apellido_paterno":"Ríos","departamento_id":15}')$$, 'DNI_INVALIDO');
select test.expect_error($$select test.signup(2, '{"dni":"22222222","nombres":"Ana","apellido_paterno":"Ríos"}')$$, 'DEPARTAMENTO_OBLIGATORIO');
select test.expect_error($$select test.signup(2, '{"dni":"22222222","nombres":"A","apellido_paterno":"Ríos","departamento_id":15}')$$, 'NOMBRES_INVALIDOS');
select test.expect_error($$select test.signup(2, '{"dni":"22222222","nombres":"Ana1","apellido_paterno":"Ríos","departamento_id":15}')$$, 'NOMBRES_INVALIDOS');

-- Admin (usuario 1)
select test.signup(1, '{"dni":"11111111","nombres":"Admin","apellido_paterno":"Fiapé","departamento_id":15}');
update public.perfiles set es_admin = true, estado = 'verificado' where id = test.u(1);

-- Usuario B (2)
select test.signup(2, '{"dni":"22222222","nombres":"  ana   lucía ","apellido_paterno":"ríos","apellido_materno":"Quispe","departamento_id":4}');
select test.ok((select nombres = 'ANA LUCÍA' and apellido_paterno = 'RÍOS' from public.personas where dni = '22222222'),
               'nombres normalizados en MAYÚSCULAS');
select test.ok((select estado = 'pendiente_envio' from public.perfiles where id = test.u(2)), 'nuevo usuario queda pendiente_envio');
select test.expect_error($$select test.signup(9, '{"dni":"22222222","nombres":"Otra","apellido_paterno":"Persona","departamento_id":4}')$$, 'DNI_YA_REGISTRADO');

-- ===== 2. Usuario sin verificar =====
\echo '--- 2. Usuario sin verificar'
select set_config('request.jwt.claim.sub', test.u(2)::text, false);
set role authenticated;
select test.ok((select estado = 'pendiente_envio' and intentos_restantes = 3 from public.mi_perfil()), 'mi_perfil muestra estado y 3 intentos');
select test.expect_error($$select * from public.buscar_personas('33333333')$$, 'CUENTA_NO_VERIFICADA');
select test.expect_error($$select public.registrar_persona('33333333','Juan','Pérez')$$, 'CUENTA_NO_VERIFICADA');
select test.expect_error($$select * from public.calificar(gen_random_uuid(), 5::smallint)$$, 'CUENTA_NO_VERIFICADA');

-- ===== 3. Verificación =====
\echo '--- 3. Verificación con fotos'
select test.expect_error($$insert into storage.objects (bucket_id, name) values ('verificaciones', test.u(1)::text || '/x.jpg')$$, 'row-level security');
insert into storage.objects (bucket_id, name) values
  ('verificaciones', test.u(2)::text || '/1-anverso.jpg'),
  ('verificaciones', test.u(2)::text || '/1-reverso.jpg'),
  ('verificaciones', test.u(2)::text || '/1-selfie.jpg');
select test.ok((select count(*) = 3 from storage.objects), 'usuario ve solo sus 3 fotos');
select test.expect_error($$select public.enviar_verificacion(test.u(2)::text||'/1-anverso.jpg', test.u(2)::text||'/1-anverso.jpg', test.u(2)::text||'/1-selfie.jpg')$$, 'FOTOS_DEBEN_SER_DISTINTAS');
select test.expect_error($$select public.enviar_verificacion(test.u(2)::text||'/1-anverso.jpg', test.u(2)::text||'/1-reverso.jpg', test.u(2)::text||'/no-existe.jpg')$$, 'FOTO_NO_ENCONTRADA');
select test.expect_error($$select public.enviar_verificacion(test.u(1)::text||'/1-anverso.jpg', test.u(2)::text||'/1-reverso.jpg', test.u(2)::text||'/1-selfie.jpg')$$, 'RUTA_FOTO_INVALIDA');
select public.enviar_verificacion(test.u(2)::text||'/1-anverso.jpg', test.u(2)::text||'/1-reverso.jpg', test.u(2)::text||'/1-selfie.jpg');
select test.expect_error($$select public.enviar_verificacion(test.u(2)::text||'/1-anverso.jpg', test.u(2)::text||'/1-reverso.jpg', test.u(2)::text||'/1-selfie.jpg')$$, 'VERIFICACION_EN_REVISION');
select test.expect_error($$select * from public.admin_listar_verificaciones()$$, 'SOLO_ADMIN');
reset role;

-- Admin rechaza 3 veces → bloqueado
select set_config('request.jwt.claim.sub', test.u(1)::text, false);
set role authenticated;
select test.ok((select count(*) = 1 from public.admin_listar_verificaciones()), 'admin ve 1 solicitud pendiente');
select test.ok((select count(*) = 3 from storage.objects), 'admin puede ver las fotos del usuario');
select test.expect_error($$select public.admin_revisar_verificacion((select verificacion_id from public.admin_listar_verificaciones()), false)$$, 'MOTIVO_REQUERIDO');
select test.ok(public.admin_revisar_verificacion((select verificacion_id from public.admin_listar_verificaciones()), false, 'Foto borrosa') = 'rechazado', 'rechazo 1 → rechazado');
reset role;

do $$
declare i int;
begin
  for i in 2..3 loop
    perform set_config('request.jwt.claim.sub', test.u(2)::text, false);
    set local role authenticated;
    insert into storage.objects (bucket_id, name) values
      ('verificaciones', test.u(2)::text || '/' || i || '-a.jpg'),
      ('verificaciones', test.u(2)::text || '/' || i || '-r.jpg'),
      ('verificaciones', test.u(2)::text || '/' || i || '-s.jpg');
    perform public.enviar_verificacion(test.u(2)::text||'/'||i||'-a.jpg', test.u(2)::text||'/'||i||'-r.jpg', test.u(2)::text||'/'||i||'-s.jpg');
    perform set_config('request.jwt.claim.sub', test.u(1)::text, false);
    perform public.admin_revisar_verificacion((select verificacion_id from public.admin_listar_verificaciones()), false, 'No coincide');
    reset role;
  end loop;
end $$;

select set_config('request.jwt.claim.sub', test.u(2)::text, false);
set role authenticated;
select test.ok((select estado = 'bloqueado' and intentos_restantes = 0 and ultimo_motivo_rechazo = 'No coincide' from public.mi_perfil()), 'tras 3 rechazos queda bloqueado');
select test.expect_error($$select public.enviar_verificacion(test.u(2)::text||'/3-a.jpg', test.u(2)::text||'/3-r.jpg', test.u(2)::text||'/3-s.jpg')$$, 'LIMITE_INTENTOS_ALCANZADO');
reset role;

-- Soporte habilita un intento extra y el admin aprueba
select set_config('request.jwt.claim.sub', test.u(1)::text, false);
set role authenticated;
select public.admin_habilitar_reintento(test.u(2));
reset role;
select set_config('request.jwt.claim.sub', test.u(2)::text, false);
set role authenticated;
insert into storage.objects (bucket_id, name) values
  ('verificaciones', test.u(2)::text || '/4-a.jpg'),
  ('verificaciones', test.u(2)::text || '/4-r.jpg'),
  ('verificaciones', test.u(2)::text || '/4-s.jpg');
select public.enviar_verificacion(test.u(2)::text||'/4-a.jpg', test.u(2)::text||'/4-r.jpg', test.u(2)::text||'/4-s.jpg');
reset role;
select set_config('request.jwt.claim.sub', test.u(1)::text, false);
set role authenticated;
select test.ok(public.admin_revisar_verificacion((select verificacion_id from public.admin_listar_verificaciones()), true) = 'verificado', 'admin aprueba → verificado');
reset role;

-- ===== 4. Búsqueda y registro de personas =====
\echo '--- 4. Búsqueda obligatoria y registro de personas'
select set_config('request.jwt.claim.sub', test.u(2)::text, false);
set role authenticated;
select test.expect_error($$select * from public.buscar_personas('1234')$$, 'DNI_INVALIDO');
select test.expect_error($$select * from public.buscar_personas('ab')$$, 'CONSULTA_MUY_CORTA');
select test.expect_error($$select public.registrar_persona('33333333','Juan','Pérez','Soto',4::smallint)$$, 'BUSQUEDA_PREVIA_REQUERIDA');
select test.ok((select count(*) = 0 from public.buscar_personas('33333333')), 'búsqueda por DNI inexistente → 0 resultados');
select public.registrar_persona('33333333', 'juan carlos', 'pérez', 'soto', 4::smallint);
select test.expect_error($$select public.registrar_persona('33333333','Juan','Pérez')$$, 'PERSONA_YA_EXISTE');
select test.ok((select count(*) = 1 from public.buscar_personas('perez juan')), 'búsqueda por nombre sin tildes encuentra a JUAN CARLOS PÉREZ SOTO');
select test.ok((select nombre_completo = 'JUAN CARLOS PÉREZ SOTO' and dni = '33333333' and departamento = 'Arequipa'
                  from public.buscar_personas('33333333')), 'resultado muestra DNI completo, nombre y departamento');

-- ===== 5. Calificaciones =====
\echo '--- 5. Calificaciones'
select test.expect_error($$select * from public.calificar((select id from public.buscar_personas('33333333')), 11::smallint)$$, 'ESTRELLAS_FUERA_DE_RANGO');
select test.expect_error($$select * from public.calificar((select id from public.buscar_personas('33333333')), 0::smallint)$$, 'ESTRELLAS_FUERA_DE_RANGO');
select test.ok((select promedio = 8 from public.calificar((select id from public.buscar_personas('33333333')), 8::smallint)), 'calificación 8 → promedio 8');
select test.ok((select promedio = 6 and total_calificaciones = 1 from public.calificar((select id from public.buscar_personas('33333333')), 6::smallint)), 'editar a 6 → sigue 1 calificación, promedio 6');
select test.ok((select mi_calificacion = 6 from public.buscar_personas('33333333')), 'la búsqueda muestra mi calificación');
select test.expect_error($$select * from public.calificar((select id from public.buscar_personas('22222222')), 10::smallint)$$, 'NO_PUEDES_CALIFICARTE');
reset role;

-- Calificar sin búsqueda previa
select test.usuario_verificado(3, '44444444', 4);
select id as pid from public.personas where dni = '33333333' \gset
select set_config('request.jwt.claim.sub', test.u(3)::text, false);
set role authenticated;
select test.expect_error(format('select * from public.calificar(%L::uuid, 9::smallint)', :'pid'), 'BUSQUEDA_PREVIA_REQUERIDA');
reset role;

-- 5 usuarios más califican con 10
do $$
declare i int;
begin
  for i in 3..7 loop
    if i > 3 then perform test.usuario_verificado(i, lpad((50000000 + i)::text, 8, '0'), 15); end if;
    perform set_config('request.jwt.claim.sub', test.u(i)::text, false);
    set local role authenticated;
    perform public.buscar_personas('33333333');
    perform public.calificar((select id from public.buscar_personas('33333333')), 10::smallint);
    reset role;
  end loop;
end $$;
select test.ok((select total_calificaciones = 6 and promedio = 9.33 from public.personas where dni = '33333333'), '6 calificaciones (6,10,10,10,10,10) → promedio 9.33');

-- ===== 6. Ranking =====
\echo '--- 6. Ranking por departamento'
select set_config('request.jwt.claim.sub', test.u(2)::text, false);
set role authenticated;
select test.ok((select count(*) = 1 and min(puesto) = 1 and min(nombre_completo) = 'JUAN CARLOS PÉREZ SOTO'
                  from public.ranking_departamento(4::smallint)), 'Arequipa: puesto 1 con 6 calificaciones');
select test.ok((select count(*) = 0 from public.ranking_departamento(15::smallint)), 'Lima: nadie con 5+ calificaciones');
reset role;

-- ===== 7. La persona registrada por otro crea su cuenta =====
\echo '--- 7. Reclamar perfil existente'
select test.signup(8, '{"dni":"33333333","nombres":"Juan Carlos","apellido_paterno":"Pérez","apellido_materno":"Soto","departamento_id":4}');
select test.ok((select user_id = test.u(8) and total_calificaciones = 6 from public.personas where dni = '33333333'),
               'la nueva cuenta se une a la persona y conserva sus 6 calificaciones');
select set_config('request.jwt.claim.sub', test.u(8)::text, false);
set role authenticated;
select test.ok((select promedio = 9.33 and estado = 'pendiente_envio' from public.mi_perfil()), 'el dueño ve su promedio en mi_perfil');
reset role;

-- ===== 8. Seguridad (RLS y permisos) =====
\echo '--- 8. Seguridad'
select set_config('request.jwt.claim.sub', test.u(2)::text, false);
set role authenticated;
select test.ok((select count(*) = 1 from public.calificaciones), 'un usuario ve solo SUS calificaciones');
select test.ok((select count(*) = 0 from public.personas), 'no puede leer la tabla personas directamente');
select test.ok((select count(*) = 1 from public.perfiles), 've solo su propio perfil');
select test.ok((select count(*) = 25 from public.departamentos), '25 departamentos visibles');
select test.expect_error($$insert into public.calificaciones (persona_id, autor_id, estrellas) select id, auth.uid(), 10 from public.personas$$, 'permission denied');
select test.expect_error($$update public.perfiles set es_admin = true$$, 'permission denied');
select test.expect_error($$update public.perfiles set estado = 'verificado'$$, 'permission denied');
select test.expect_error($$select * from public.busquedas$$, 'permission denied');
select test.expect_error($$select public.admin_habilitar_reintento(test.u(2))$$, 'SOLO_ADMIN');
reset role;

select set_config('request.jwt.claim.sub', '', false);
set role anon;
select test.expect_error($$select * from public.buscar_personas('33333333')$$, 'permission denied');
select test.expect_error($$select * from public.ranking_departamento(4::smallint)$$, 'permission denied');
select test.ok(public.dni_tiene_cuenta('33333333') and not public.dni_tiene_cuenta('99999999'), 'anon puede consultar si un DNI ya tiene cuenta');
reset role;

-- Admin no puede aprobarse a sí mismo
update public.perfiles set estado = 'rechazado', es_admin = true where id = test.u(3);
select set_config('request.jwt.claim.sub', test.u(3)::text, false);
set role authenticated;
insert into storage.objects (bucket_id, name) values
  ('verificaciones', test.u(3)::text || '/a.jpg'), ('verificaciones', test.u(3)::text || '/r.jpg'), ('verificaciones', test.u(3)::text || '/s.jpg');
select public.enviar_verificacion(test.u(3)::text||'/a.jpg', test.u(3)::text||'/r.jpg', test.u(3)::text||'/s.jpg');
select test.expect_error($$select public.admin_revisar_verificacion((select verificacion_id from public.admin_listar_verificaciones() where user_id = auth.uid()), true)$$, 'NO_PUEDES_REVISARTE');
reset role;

\echo ''
\echo '=== TODAS LAS PRUEBAS PASARON ==='
