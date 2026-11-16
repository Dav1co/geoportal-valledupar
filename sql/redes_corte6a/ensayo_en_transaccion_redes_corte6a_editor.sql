begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 10 — GUARDIA, COLUMNA NUEVA DE LAS CAPAS DEL CARGUE, CATÁLOGO DEL GEOVISOR, CAPAS POR PERFIL Y PARÁMETROS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: plan 02 (Corte 6), 01 sección D, N-11, N-13 y N-14; respuesta de David del 16-nov 01:30 (quién carga cada capa, al final de la bitácora).
-- · Presupone el 5c aplicado (huella del conjunto de funciones de redes).
-- · ⚠ Se reemplazan 10 RPC (las 5 del motor del 1a que abren el paso a la carga, las 4 de la pantalla del 5c y geoportal_redes_mi_perfil del 4a),
--   con su texto exacto en la reversa. El cambio es solo QUIÉN puede (redes.f_autorizar_carga en vez de redes.f_autorizar_admin) y el dato «geovisor».
-- · ⚠ redes.capas (viva, del 1a): se le AGREGA la columna carga_supervisor (por omisión false). No se cambia ninguna otra columna ni regla.
-- =====================================================================
do $$
begin
  if to_regclass('redes.ficha_campo_devoluciones') is null then
    raise exception 'Falta el Corte 5c: aplíquelo antes';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'a5ce1ff8c5659de3b853e30f4d3025e6' then
    raise exception 'Las funciones de redes no son las del Corte 5c (o el Corte 6a ya está aplicado): deténgase y avise';
  end if;
  if to_regclass('redes.geovisor_capas') is not null or to_regclass('redes.capas_por_perfil') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name = 'capas' and column_name = 'carga_supervisor') then
    raise exception 'Lo del 6a ya existe: el Corte 6a parece aplicado';
  end if;
  if (select count(*) from redes.capas where codigo in ('acueducto', 'alc_conductos', 'alc_pozos', 'alc_descargas', 'muestreo', 'acometidas', 'captaciones', 'aduccion',
        'desarenadores', 'bombeo_ap', 'sumideros', 'interceptores', 'bombeo_ar', 'ptar', 'sectores', 'sensores', 'scada')) <> 17 then
    raise exception 'Faltan capas del Cargue (1a, 5a o 5c): deténgase y avise';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'redes.capas'::regclass and tgname = 't_no_borrar' and not tgisinternal) then
    raise exception 'redes.capas no tiene su candado: deténgase y avise';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. QUIÉN CARGA CADA CAPA (David, 16-nov 01:30): las capas de la red que vienen del MODELO hidráulico (acueducto, conductos, pozos y descargas de
--    alcantarillado: topología, enlace de contratos y simulación de cierre) solo el administrador; las demás también el supervisor de distribución.
--    Es un dato de la capa (no una lista escrita en las funciones), para que una capa nueva se pueda abrir o cerrar al supervisor sin otra migración.
-- ---------------------------------------------------------------------
alter table redes.capas add column carga_supervisor boolean not null default false;
comment on column redes.capas.carga_supervisor is 'Corte 6a: el supervisor de distribución también carga esta capa. Las del modelo (acueducto, conductos, pozos y descargas) solo el administrador.';
update redes.capas set carga_supervisor = true
 where fuente = 'carga' and codigo not in ('acueducto', 'alc_conductos', 'alc_pozos', 'alc_descargas');

-- ---------------------------------------------------------------------
-- 2. CATÁLOGO DE CAPAS DEL GEOVISOR (01 sección D). Distinto de redes.capas (que es lo que se CARGA): aquí está lo que se VE.
--    fuente: «tesela» (activos vigentes, por prefijo, en la tesela del geovisor), «geojson» (daños, intervenciones, muestreo y reportes del bot, por fecha)
--    o «preparada» (sin datos todavía: queda apagada y con su nota). solo_completo: el operador con el geovisor activado (N-13) no la ve.
-- ---------------------------------------------------------------------
create table redes.geovisor_capas (
  codigo        text primary key check (codigo ~ '^[a-z][a-z0-9_]{2,39}$'),
  nombre        text not null check (length(btrim(nombre)) between 2 and 80),
  grupo         text not null check (grupo in ('acueducto', 'alcantarillado', 'tecnologia', 'actividades', 'calidad', 'reportes', 'comercial', 'analisis')),
  fuente        text not null check (fuente in ('tesela', 'geojson', 'preparada')),
  estado        text not null default 'activa' check (estado in ('activa', 'por_conectar', 'espera_dato')),
  prefijos      text[] not null default '{}',
  por_fecha     boolean not null default false,
  solo_completo boolean not null default false,
  nota          text check (nota is null or length(nota) <= 300),
  orden         integer not null,
  activa        boolean not null default true,
  check ((fuente = 'tesela') = (cardinality(prefijos) > 0)),
  check (not por_fecha or fuente = 'geojson')
);
comment on table redes.geovisor_capas is 'Corte 6a: las capas del geovisor técnico (interruptores). No se borran: se desactivan.';

create table redes.capas_por_perfil (
  perfil         text not null check (perfil in ('supervisor_distribucion', 'supervisor_planta', 'operador_distribucion')),
  capa           text not null references redes.geovisor_capas (codigo),
  encendida      boolean not null,
  actualizado_en timestamptz not null default clock_timestamp(),
  actualizado_por text not null,
  primary key (perfil, capa)
);
comment on table redes.capas_por_perfil is 'Corte 6a (N-11): capas encendidas al abrir el geovisor, por perfil. El administrador abre con las de los dos supervisores; una persona con varios perfiles, con la unión. Las edita el administrador, con motivo (capas_por_perfil_eventos).';

create table redes.capas_por_perfil_eventos (
  id         bigint generated always as identity primary key,
  perfil     text not null,
  capa       text not null references redes.geovisor_capas (codigo),
  antes      boolean,
  despues    boolean not null,
  motivo     text not null check (length(btrim(motivo)) between 10 and 1000),
  autor      text not null,
  creado_en  timestamptz not null default clock_timestamp()
);
comment on table redes.capas_por_perfil_eventos is 'Corte 6a: historial de las capas por omisión del geovisor. Solo inserción.';

do $$
begin
  execute 'create trigger t_no_borrar before delete on redes.geovisor_capas for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_no_vaciar before truncate on redes.geovisor_capas for each statement execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_no_borrar before delete on redes.capas_por_perfil for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_no_vaciar before truncate on redes.capas_por_perfil for each statement execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar before update or delete on redes.capas_por_perfil_eventos for each row execute function tecnica.f_solo_agregar()';
  execute 'create trigger t_solo_agregar_trunc before truncate on redes.capas_por_perfil_eventos for each statement execute function tecnica.f_solo_agregar()';
  execute 'alter table redes.geovisor_capas enable row level security';
  execute 'alter table redes.capas_por_perfil enable row level security';
  execute 'alter table redes.capas_por_perfil_eventos enable row level security';
end $$;

insert into redes.geovisor_capas (codigo, nombre, grupo, fuente, estado, prefijos, por_fecha, solo_completo, nota, orden) values
  ('acu_tramos',        'Tramos de acueducto',                                     'acueducto',      'tesela',    'activa',       '{RED,CON,ADU,ACO}',         false, false, null, 10),
  ('acu_nodos',         'Válvulas, torres, hidrantes y accesorios',                'acueducto',      'tesela',    'activa',       '{VAL,TOR,HID,ACC,MAC}',     false, false, null, 11),
  ('acu_instalaciones', 'Tanques, plantas, captaciones y bombeo',                  'acueducto',      'tesela',    'activa',       '{TAN,PTA,CAP,DES,EBA}',     false, false, null, 12),
  ('alc_conductos',     'Conductos de alcantarillado',                             'alcantarillado', 'tesela',    'activa',       '{COL,INT}',                 false, false, null, 20),
  ('alc_pozos',         'Pozos, sumideros y descargas',                            'alcantarillado', 'tesela',    'activa',       '{POZ,SUM,VER,EBR,PTR}',     false, false, null, 21),
  ('sectores',          'Sectores hidráulicos',                                    'tecnologia',     'tesela',    'activa',       '{SEC}',                     false, false, 'Se ven cuando se carguen los polígonos (Cargue de capas)', 30),
  ('sensores',          'Sensores y SCADA',                                        'tecnologia',     'tesela',    'por_conectar', '{SEN,SCA}',                 false, false, 'Se ve la ubicación; las lecturas se conectan con el SCADA (Corte 9 y siguientes)', 31),
  ('danos',             'Daños y fallas',                                          'actividades',    'geojson',   'activa',       '{}',                        true,  false, null, 40),
  ('intervenciones',    'Intervenciones',                                          'actividades',    'geojson',   'activa',       '{}',                        true,  false, null, 41),
  ('muestreo',          'Puntos de muestreo',                                      'calidad',        'geojson',   'activa',       '{}',                        false, true,  'El último cloro y la turbiedad llegan con los rangos del jefe de planta', 50),
  ('pqr_116',           'PQR técnicas y línea 116',                                'calidad',        'preparada', 'espera_dato',  '{}',                        false, true,  'Espera el archivo (Corte 5d)', 51),
  ('reportes_bot',      'Reportes del bot (Telegram)',                             'reportes',       'geojson',   'activa',       '{}',                        true,  true,  'Se llena cuando se conecte el bot (n8n)', 60),
  ('reportes_comercial','Reportes de Comercial (anomalías y revisiones)',          'reportes',       'preparada', 'espera_dato',  '{}',                        false, true,  'Azul con contrato, rojo posibles clandestinos (Corte 8)', 61),
  ('reporte_ciudadano', 'Reporte ciudadano (contratista)',                         'reportes',       'preparada', 'espera_dato',  '{}',                        false, true,  'Espera la interfaz con el contratista', 62),
  ('contratos',         'Contratos (consumo y edad del medidor)',                  'comercial',      'preparada', 'espera_dato',  '{}',                        false, true,  'Llega en el Corte 6b', 70),
  ('presion',           'Presión en la red (alertas)',                             'analisis',       'preparada', 'espera_dato',  '{}',                        false, true,  'Espera el modelo hidráulico (Corte 9)', 80),
  ('cuadrillas',        'Cuadrillas por GPS',                                      'analisis',       'preparada', 'espera_dato',  '{}',                        false, true,  'Espera la unificación con Acuo', 81),
  ('cortes',            'Cortes programados vigentes',                             'analisis',       'preparada', 'espera_dato',  '{}',                        false, true,  null, 82),
  ('mapa_calor',        'Mapa de calor de reportes',                               'analisis',       'preparada', 'espera_dato',  '{}',                        false, true,  null, 83);

-- Capas encendidas al abrir (01 sección D): supervisor de distribución, redes y las actividades; supervisor de planta, muestreo y tanques;
-- operador con el geovisor activado, redes y las actividades del día. El administrador abre con la unión de los dos supervisores.
insert into redes.capas_por_perfil (perfil, capa, encendida, actualizado_por)
select p, c, true, 'migracion@redes_corte6a'
  from (values ('supervisor_distribucion', 'acu_tramos'), ('supervisor_distribucion', 'acu_nodos'), ('supervisor_distribucion', 'acu_instalaciones'),
               ('supervisor_distribucion', 'alc_conductos'), ('supervisor_distribucion', 'alc_pozos'), ('supervisor_distribucion', 'danos'),
               ('supervisor_distribucion', 'intervenciones'),
               ('supervisor_planta', 'acu_instalaciones'), ('supervisor_planta', 'muestreo'),
               ('operador_distribucion', 'acu_tramos'), ('operador_distribucion', 'acu_nodos'), ('operador_distribucion', 'alc_conductos'),
               ('operador_distribucion', 'alc_pozos'), ('operador_distribucion', 'danos'), ('operador_distribucion', 'intervenciones')) x(p, c);

-- ---------------------------------------------------------------------
-- 3. PARÁMETROS DEL GEOVISOR (medidos con la red real en el PostGIS local: a zoom 12 la tesela completa del centro pesa 1,2 MB; a zoom 13 con la red
--    principal, unos 160 KB; a zoom 14 con todos los tramos, 115 KB; a zoom 15 con los nodos, 60 KB).
-- ---------------------------------------------------------------------
insert into redes.parametros (clave, valor, unidad, minimo, maximo, descripcion) values
  ('geovisor_zoom_min', 13, 'zoom', 10, 16, 'Geovisor (Corte 6a): desde este zoom se ve la red principal (más lejos, solo el mapa base)'),
  ('geovisor_zoom_red_completa', 14, 'zoom', 10, 18, 'Geovisor: desde este zoom se ven todos los tramos (antes, solo la red principal)'),
  ('geovisor_zoom_nodos', 15, 'zoom', 10, 19, 'Geovisor: desde este zoom se ven válvulas, pozos y demás puntos (tanques y plantas, desde el zoom mínimo)'),
  ('geovisor_zoom_acc', 17, 'zoom', 12, 20, 'Geovisor: desde este zoom se ven los accesorios (tees, codos, tapones…)'),
  ('geovisor_diam_principal_acu_mm', 150, 'mm', 0, 2000, 'Geovisor: diámetro desde el que un tramo de acueducto es «red principal» (se ve desde el zoom mínimo)'),
  ('geovisor_diam_principal_alc_mm', 450, 'mm', 0, 3000, 'Geovisor: diámetro desde el que un conducto de alcantarillado es «red principal»'),
  ('geovisor_rango_meses', 12, 'meses', 1, 24, 'Geovisor: rango máximo de fechas de daños, intervenciones y reportes'),
  ('geovisor_max_elementos', 3000, 'elementos', 100, 20000, 'Geovisor: tope de elementos de una capa por fecha (si hay más, avisa que la lista está recortada)')
on conflict (clave) do nothing;      -- una reversa los deja (los parámetros no se borran)
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 26 — FUNCIONES NUEVAS
--   · redes.f_autorizar_carga y redes.f_autorizar_carga_id: quién carga cada capa (el administrador todas; el supervisor de distribución las que
--     tienen carga_supervisor). Las usan las RPC del Cargue reemplazadas en 25.
--   · redes.f_geovisor_acceso: quién abre el geovisor y con qué perfiles (N-11 y N-13). Se apoya en redes.f_geovisor_lectura (Corte 4b), sin tocarla.
--   · redes.f_puede_formulario: si la persona puede abrir un formulario de distribución (para los botones de la tarjeta), sin lanzar error.
--   · public.geoportal_redes_geovisor: la configuración del geovisor (capas que puede ver, encendidas al abrir, zooms, rango de fechas, materiales…).
--   · public.geoportal_redes_geovisor_mvt: la tesela de los activos vigentes, con material, diámetro, edad y estado.
--   · public.geoportal_redes_geovisor_capa: las capas por fecha (daños, intervenciones, reportes del bot) y los puntos de muestreo, en GeoJSON.
--   · public.geoportal_redes_geovisor_capas_fijar: el administrador cambia las capas que se encienden al abrir, por perfil, con motivo.
-- Nada de esto lleva datos de contratos, nombres, teléfonos, descripciones ni el tercero de un daño.
-- =====================================================================

-- ---------- Quién carga cada capa ----------
create function redes.f_autorizar_carga(p_solicitante text, p_capa text) returns text
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_email text := lower(btrim(coalesce(p_solicitante, ''))); c redes.capas%rowtype;
begin
  if v_email = '' or position('@' in v_email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if public.geoportal_estado_acceso(v_email) <> 'ok' then raise exception 'Acceso no disponible' using errcode = '42501'; end if;
  if public.geoportal_es_admin(v_email) then return v_email; end if;
  if not public.geoportal_puede(v_email, 'dashboard_redes') then raise exception 'Solo el administrador o el supervisor de distribución cargan capas' using errcode = '42501'; end if;
  if not tecnica.f_tecnica_activa(v_email) then raise exception 'Su acceso a Técnica está desactivado' using errcode = '42501'; end if;
  select * into c from redes.capas where codigo = p_capa;
  if not found then perform tecnica.f_error('No existe esa capa', 'P0002'); end if;
  if not c.carga_supervisor then raise exception 'La capa % viene del modelo hidráulico: la carga solo el administrador', c.nombre using errcode = '42501'; end if;
  return v_email;
end $$;
comment on function redes.f_autorizar_carga(text, text) is 'Corte 6a: el administrador carga todas las capas; el supervisor de distribución, las que tienen carga_supervisor (las del modelo, no).';

create function redes.f_autorizar_carga_id(p_solicitante text, p_carga bigint) returns text
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_capa text;
begin
  select capa_codigo into v_capa from redes.cargas where id = p_carga;
  if v_capa is null then
    perform redes.f_autorizar_admin(p_solicitante);      -- quien no es administrador no sabe si la carga existe
    perform tecnica.f_error('No existe esa carga', 'P0002');
  end if;
  return redes.f_autorizar_carga(p_solicitante, v_capa);
end $$;

-- ---------- Quién abre el geovisor y con qué perfiles ----------
-- completo = supervisor (de distribución o de planta) o administrador; el operador de distribución con la casilla activada (N-13) ve solo las capas
-- sin solo_completo y las actividades del día. El administrador abre con las capas de los dos supervisores (N-11).
create function redes.f_geovisor_acceso(p_solicitante text, out email text, out completo boolean, out admin boolean, out perfiles text[]) returns record
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
begin
  email := lower(btrim(coalesce(p_solicitante, '')));
  if email = '' or position('@' in email) < 2 then raise exception 'Solicitante no identificado' using errcode = '28000'; end if;
  if not redes.f_geovisor_lectura(email) then raise exception 'Sin el geovisor técnico' using errcode = '42501'; end if;
  admin := public.geoportal_es_admin(email);
  if admin then perfiles := array['supervisor_distribucion', 'supervisor_planta']; completo := true; return; end if;
  perfiles := array_remove(array[case when public.geoportal_puede(email, 'dashboard_redes') then 'supervisor_distribucion' end,
                                 case when public.geoportal_puede(email, 'dashboard_tecnico') then 'supervisor_planta' end], null);
  completo := cardinality(perfiles) > 0;
  if not completo then perfiles := array['operador_distribucion']; end if;
end $$;

create function redes.f_puede_formulario(p_email text, p_formulario text) returns boolean
language plpgsql stable security definer set search_path = public, redes, tecnica, pg_temp as $$
begin
  perform redes.f_autorizar_captura_redes(p_email, p_formulario);
  return true;
exception when others then
  return false;
end $$;

-- ---------- Configuración del geovisor ----------
create function public.geoportal_redes_geovisor(p_solicitante text) returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  return jsonb_build_object(
    'perfil', case when a.admin then 'admin' when a.completo then 'supervisor' else 'operador' end,
    'completo', a.completo, 'perfiles', to_jsonb(a.perfiles),
    'hoy', (clock_timestamp() at time zone 'America/Bogota')::date,
    'rango_meses', floor(redes.f_param('geovisor_rango_meses'))::integer,
    'max_elementos', floor(redes.f_param('geovisor_max_elementos'))::integer,
    'zoom', jsonb_build_object('min', redes.f_param('geovisor_zoom_min'), 'red_completa', redes.f_param('geovisor_zoom_red_completa'),
                               'nodos', redes.f_param('geovisor_zoom_nodos'), 'accesorios', redes.f_param('geovisor_zoom_acc')),
    'version', (select coalesce(sum(version), 0) from redes.tesela_version),
    'formularios', jsonb_build_object('danos_fallas', redes.f_puede_formulario(a.email, 'danos_fallas'),
                                      'mantenimiento', redes.f_puede_formulario(a.email, 'mantenimiento')),
    'ficha', a.completo,
    'capas', coalesce((
      select jsonb_agg(jsonb_build_object('codigo', g.codigo, 'nombre', g.nombre, 'grupo', g.grupo, 'fuente', g.fuente, 'estado', g.estado, 'nota', g.nota,
                                          'prefijos', to_jsonb(g.prefijos), 'por_fecha', g.por_fecha,
                                          'encendida', exists (select 1 from redes.capas_por_perfil c where c.capa = g.codigo and c.encendida and c.perfil = any (a.perfiles)))
             order by g.orden)
        from redes.geovisor_capas g where g.activa and (a.completo or not g.solo_completo)), '[]'::jsonb),
    'tipos', coalesce((select jsonb_object_agg(t.prefijo, t.nombre_visible) from redes.v_tipo_visible t), '{}'::jsonb),
    'estados', coalesce((select jsonb_object_agg(e.codigo, e.nombre) from redes.estados_activo e), '{}'::jsonb),
    'materiales', coalesce((select jsonb_agg(jsonb_build_object('codigo', m.codigo, 'nombre', m.nombre) order by m.codigo) from redes.materiales m), '[]'::jsonb),
    -- solo el administrador: la tabla de capas por omisión, para editarla (N-11)
    'por_perfil', case when a.admin then coalesce((
      select jsonb_agg(jsonb_build_object('perfil', c.perfil, 'capa', c.capa, 'encendida', c.encendida, 'actualizado_en', c.actualizado_en, 'actualizado_por', c.actualizado_por)
             order by c.perfil, c.capa) from redes.capas_por_perfil c), '[]'::jsonb) end);
end $$;

-- ---------- Tesela del geovisor (perfil completo): activos vigentes, con lo que hace falta para colorear por material o edad ----------
-- Por zoom (parámetros): menos de geovisor_zoom_min, vacía; hasta geovisor_zoom_red_completa, solo la red principal (por diámetro), las conducciones,
-- las aducciones, los interceptores, los sectores y las instalaciones; los demás puntos desde geovisor_zoom_nodos; los accesorios desde geovisor_zoom_acc.
-- Solo los prefijos de las capas que la persona puede ver.
create function public.geoportal_redes_geovisor_mvt(p_solicitante text, p_z integer, p_x integer, p_y integer) returns text
language plpgsql stable security definer set search_path = public, redes, extensions, pg_temp as $$
declare a record; v_env geometry; v_env4326 geometry; v bytea; v_pref text[]; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        z_min numeric := redes.f_param('geovisor_zoom_min'); z_red numeric := redes.f_param('geovisor_zoom_red_completa');
        z_nod numeric := redes.f_param('geovisor_zoom_nodos'); z_acc numeric := redes.f_param('geovisor_zoom_acc');
        d_acu numeric := redes.f_param('geovisor_diam_principal_acu_mm'); d_alc numeric := redes.f_param('geovisor_diam_principal_alc_mm');
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if p_z is null or p_x is null or p_y is null or p_z < 0 or p_z > 22 or p_x < 0 or p_y < 0 or p_x >= (1 << p_z) or p_y >= (1 << p_z) then perform tecnica.f_error('Tesela fuera de rango'); end if;
  if p_z < z_min then return ''; end if;
  select array_agg(distinct p) into v_pref from redes.geovisor_capas g cross join unnest(g.prefijos) p where g.activa and g.fuente = 'tesela' and (a.completo or not g.solo_completo);
  v_env := ST_TileEnvelope(p_z, p_x, p_y);
  v_env4326 := ST_Transform(v_env, 4326);
  select ST_AsMVT(t, 'activos', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(m.geom, 3857), v_env, 4096, 64, true) as geom, m.codigo, m.prefijo, m.sistema,
           case GeometryType(m.geom) when 'POINT' then 'nodo' when 'POLYGON' then 'area' when 'MULTIPOLYGON' then 'area' else 'tramo' end as forma,
           coalesce(m.clase, '') as clase, coalesce(m.material_codigo, '') as material, m.diametro_mm::real as diametro,
           case when m.fecha_instalacion is not null then greatest(0, extract(year from age(v_hoy, m.fecha_instalacion)))::integer end as edad,
           m.estado_codigo as estado, m.punteado
      from redes.activo_vigente_mat m
     where not m.retirado and not m.oculto and m.prefijo = any (v_pref)
       and m.geom && v_env4326
       and case
             when m.prefijo = 'ACC' then p_z >= z_acc
             when m.prefijo in ('TAN', 'PTA', 'CAP', 'DES', 'EBA', 'EBR', 'PTR', 'SEC') then true
             when GeometryType(m.geom) = 'POINT' then p_z >= z_nod
             when p_z >= z_red then true
             else m.prefijo in ('CON', 'ADU', 'INT')
                  or (m.sistema = 'acueducto' and m.diametro_mm >= d_acu) or (m.sistema = 'alcantarillado' and m.diametro_mm >= d_alc)
           end) t
   where t.geom is not null;
  return replace(encode(coalesce(v, ''::bytea), 'base64'), E'\n', '');
end $$;

-- ---------- Capas en GeoJSON: daños, intervenciones y reportes del bot por fecha (día de Bogotá), y los puntos de muestreo ----------
-- El operador (N-13) solo ve las actividades del día. Nunca van la descripción, el tercero, la dirección ni las fotos: solo lo que se dibuja y la tarjeta.
create function public.geoportal_redes_geovisor_capa(p_solicitante text, p_capa text, p_desde date default null, p_hasta date default null) returns jsonb
language plpgsql stable security definer set search_path = public, redes, tecnica, extensions, pg_temp as $$
declare a record; g redes.geovisor_capas%rowtype; v_hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
        v_desde date := coalesce(p_desde, v_hoy); v_hasta date := coalesce(p_hasta, v_hoy); v_max integer := floor(redes.f_param('geovisor_max_elementos'))::integer;
        v_ini timestamptz; v_fin timestamptz; v_f jsonb; v_n integer;
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  select * into g from redes.geovisor_capas where codigo = p_capa and activa;
  if not found or g.fuente <> 'geojson' then perform tecnica.f_error('Esa capa no existe en el geovisor', 'P0002'); end if;
  if g.solo_completo and not a.completo then raise exception 'Capa solo para supervisores' using errcode = '42501'; end if;
  if g.por_fecha then
    if v_desde > v_hasta then perform tecnica.f_error('La fecha inicial es posterior a la final'); end if;
    if v_hasta > v_hoy then perform tecnica.f_error('La fecha final no puede ser futura'); end if;
    if v_desde < (v_hasta - make_interval(months => floor(redes.f_param('geovisor_rango_meses'))::integer))::date then
      perform tecnica.f_error(format('El rango de fechas es de máximo %s meses', floor(redes.f_param('geovisor_rango_meses'))::integer));
    end if;
    if not a.completo and (v_desde <> v_hoy or v_hasta <> v_hoy) then raise exception 'El geovisor en solo lectura muestra solo las actividades del día' using errcode = '42501'; end if;
  end if;
  v_ini := v_desde::timestamp at time zone 'America/Bogota';
  v_fin := (v_hasta + 1)::timestamp at time zone 'America/Bogota';

  if p_capa = 'danos' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(d.lon, d.lat)),
               'properties', jsonb_build_object('codigo', d.codigo, 'clase', d.clase, 'tipo', d.tipo_nombre, 'sistema', d.sistema, 'estado', d.estado,
                                                'activo', d.activo_codigo, 'cuando', d.t_detectado, 'riesgo', d.riesgo, 'origen', d.origen)) as f, d.t_detectado as o
        from redes.v_dano d
       where d.estado <> 'oculto' and d.t_detectado >= v_ini and d.t_detectado < v_fin and d.lat is not null
       order by d.t_detectado desc limit v_max + 1) x;
  elsif p_capa = 'intervenciones' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(i.lon, i.lat)),
               'properties', jsonb_build_object('codigo', i.codigo, 'tipo_codigo', i.tipo_codigo, 'tipo', i.tipo_nombre, 'sistema', i.sistema, 'estado', i.estado,
                                                'activo', i.activo_codigo, 'dano', i.dano_codigo, 'cuando', i.t_inicio, 'fin', i.t_fin, 'ejecutor', i.ejecutor)) as f, i.t_inicio as o
        from redes.v_intervencion i
       where i.estado not in ('oculta', 'anulada') and i.t_inicio >= v_ini and i.t_inicio < v_fin and i.lat is not null
       order by i.t_inicio desc limit v_max + 1) x;
  elsif p_capa = 'reportes_bot' then
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(r.lon, r.lat)),
               'properties', jsonb_build_object('codigo', r.radicado, 'canal', r.canal, 'tipo', r.tipo_bot, 'estado', r.estado_bot, 'dano', r.dano_codigo,
                                                'cuando', r.recibido_en)) as f, r.recibido_en as o
        from redes.v_reporte_externo r
       where r.recibido_en >= v_ini and r.recibido_en < v_fin and r.lat is not null
       order by r.recibido_en desc limit v_max + 1) x;
  elsif p_capa = 'muestreo' then
    select coalesce(jsonb_agg(f order by o), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(u.lon, u.lat)),
               'properties', jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre, 'zona', p.zona, 'exactitud', u.exactitud)) as f, p.codigo as o
        from tecnica.puntos p join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
       where p.tipo = 'muestreo' and p.activo
       order by p.codigo limit v_max + 1) x;
  else
    perform tecnica.f_error('Esa capa todavía no tiene datos', 'P0002');
  end if;

  if v_n > v_max then v_f := v_f - v_max; end if;      -- se quitó el elemento de más (el último de la lista)
  return jsonb_build_object('type', 'FeatureCollection', 'capa', p_capa, 'desde', case when g.por_fecha then v_desde end, 'hasta', case when g.por_fecha then v_hasta end,
                            'recortada', v_n > v_max, 'features', v_f);
end $$;

-- ---------- Capas por omisión del geovisor (N-11): las cambia el administrador, con motivo ----------
create function public.geoportal_redes_geovisor_capas_fijar(p_solicitante text, p_perfil text, p_capa text, p_encendida boolean, p_motivo text) returns jsonb
language plpgsql security definer set search_path = public, redes, tecnica, pg_temp as $$
declare v_email text := redes.f_autorizar_admin(p_solicitante); v_mot text := btrim(coalesce(p_motivo, '')); v_antes boolean; g redes.geovisor_capas%rowtype;
begin
  if p_perfil is null or p_perfil not in ('supervisor_distribucion', 'supervisor_planta', 'operador_distribucion') then perform tecnica.f_error('Ese perfil no existe'); end if;
  if p_encendida is null then perform tecnica.f_error('Diga si la capa se enciende o no'); end if;
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres)'); end if;
  select * into g from redes.geovisor_capas where codigo = p_capa and activa;
  if not found then perform tecnica.f_error('Esa capa no existe en el geovisor', 'P0002'); end if;
  if p_encendida and g.fuente = 'preparada' then perform tecnica.f_error(format('La capa «%s» todavía no tiene datos: no se puede encender al abrir', g.nombre)); end if;
  if p_encendida and p_perfil = 'operador_distribucion' and g.solo_completo then perform tecnica.f_error(format('El operador no ve la capa «%s»', g.nombre)); end if;
  perform pg_advisory_xact_lock(hashtext('redes.capas_por_perfil'));
  select encendida into v_antes from redes.capas_por_perfil where perfil = p_perfil and capa = p_capa;
  if v_antes is not distinct from p_encendida or (v_antes is null and not p_encendida) then
    return jsonb_build_object('perfil', p_perfil, 'capa', p_capa, 'encendida', p_encendida, 'cambio', false);
  end if;
  insert into redes.capas_por_perfil (perfil, capa, encendida, actualizado_por) values (p_perfil, p_capa, p_encendida, v_email)
  on conflict (perfil, capa) do update set encendida = excluded.encendida, actualizado_en = clock_timestamp(), actualizado_por = excluded.actualizado_por;
  insert into redes.capas_por_perfil_eventos (perfil, capa, antes, despues, motivo, autor) values (p_perfil, p_capa, v_antes, p_encendida, v_mot, v_email);
  perform tecnica.f_auditar(v_email, 'redes_geovisor_capas_fijar', p_perfil || '/' || p_capa, jsonb_build_object('antes', v_antes, 'despues', p_encendida, 'motivo', v_mot), null);
  return jsonb_build_object('perfil', p_perfil, 'capa', p_capa, 'encendida', p_encendida, 'cambio', true);
end $$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto del 5c con cambios exactos, aplicados una sola vez:
--   · geoportal_redes_carga_lote, _resumen, _publicar, _anular, _muestra, _revertir, _devolver_campo y geoportal_redes_cargue_iniciar: quién puede deja de ser
--     solo el administrador (redes.f_autorizar_admin) y pasa a redes.f_autorizar_carga: el supervisor de distribución también, en las capas que no vienen
--     del modelo (David, 16-nov 01:30). El origen del activo sigue siendo solo del administrador al devolver un campo;
--   · geoportal_redes_cargue_capas: «puede_cargar» por capa (y «solo_admin» en las del modelo);
--   · geoportal_redes_mi_perfil: el dato «geovisor» para el menú (N-13).
-- La RPC de psql del 1a (geoportal_redes_carga_iniciar) NO cambia: la carga por psql sigue siendo del administrador.
-- =====================================================================

-- public.geoportal_redes_carga_lote(text,bigint,jsonb)
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_lote(p_solicitante text, p_carga bigint, p_filas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
begin
  perform redes.f_autorizar_carga_id(p_solicitante, p_carga);
  return redes.f_lote(p_carga, p_filas);
end $function$;

-- public.geoportal_redes_carga_resumen(text,bigint)
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_resumen(p_solicitante text, p_carga bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
begin
  perform redes.f_autorizar_carga_id(p_solicitante, p_carga);
  return redes.f_resumen(p_carga);
end $function$;

-- public.geoportal_redes_carga_publicar(text,bigint,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_publicar(p_solicitante text, p_carga bigint, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_carga_id(p_solicitante, p_carga); r jsonb;
begin
  r := redes.f_publicar(p_carga, v_email, p_motivo);
  perform tecnica.f_auditar(v_email, 'redes_carga_publicar', p_carga::text, r, null);
  return r;
end $function$;

-- public.geoportal_redes_carga_anular(text,bigint,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_anular(p_solicitante text, p_carga bigint, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_carga_id(p_solicitante, p_carga); r jsonb;
begin
  r := redes.f_anular(p_carga, v_email, p_motivo);
  perform tecnica.f_auditar(v_email, 'redes_carga_anular', p_carga::text, jsonb_build_object('motivo', p_motivo), null);
  return r;
end $function$;

-- public.geoportal_redes_carga_muestra(text,bigint)
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_muestra(p_solicitante text, p_carga bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_carga_id(p_solicitante, p_carga); c redes.v_cargas_estado%rowtype; v_n integer; v_paso integer; v_caja jsonb;
begin
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga', 'P0002'); end if;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: ya no tiene vista previa', p_carga, c.estado), '55000'); end if;
  select count(*) into v_n from redes.carga_filas where carga_id = p_carga and geom is not null;
  v_paso := greatest(1, ceil(v_n / 400.0)::integer);
  select jsonb_build_array(round(ST_XMin(e)::numeric, 6), round(ST_YMin(e)::numeric, 6), round(ST_XMax(e)::numeric, 6), round(ST_YMax(e)::numeric, 6)) into v_caja
    from (select ST_Extent(geom)::geometry as e from redes.carga_filas where carga_id = p_carga and geom is not null) x where e is not null;
  return jsonb_build_object('carga_id', p_carga, 'capa', c.capa_codigo, 'esperadas', c.filas_esperadas,
    'recibidas', (select count(*) from redes.carga_filas where carga_id = p_carga), 'con_geometria', v_n,
    'con_error', (select count(*) from redes.carga_filas where carga_id = p_carga and error is not null),
    'errores', coalesce((select jsonb_agg(jsonb_build_object('orden', orden, 'llave', llave, 'error', error) order by orden)
                           from (select orden, llave, error from redes.carga_filas where carga_id = p_carga and error is not null order by orden limit 20) z), '[]'::jsonb),
    'caja', v_caja,
    'muestra', jsonb_build_object('type', 'FeatureCollection', 'features', coalesce((
      select jsonb_agg(jsonb_build_object('type', 'Feature', 'geometry', ST_AsGeoJSON(ST_SimplifyPreserveTopology(z.geom, 0.000005), 6)::jsonb,
                                          'properties', jsonb_build_object('orden', z.orden, 'llave', z.llave)) order by z.orden)
        from (select f.orden, f.llave, f.geom, row_number() over (order by f.orden) as rn from redes.carga_filas f where f.carga_id = p_carga and f.geom is not null) z
       where (z.rn - 1) % v_paso = 0), '[]'::jsonb)));
end $function$;

-- public.geoportal_redes_carga_revertir(text,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_revertir(p_solicitante text, p_capa text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_carga(p_solicitante, p_capa); r jsonb;
begin
  r := redes.f_revertir(p_capa, v_email, p_motivo);
  perform tecnica.f_auditar(v_email, 'redes_carga_revertir', r ->> 'carga_id', r || jsonb_build_object('motivo', p_motivo), null);
  return r;
end $function$;

-- public.geoportal_redes_cargue_iniciar(text,text,text,text,integer,text,integer,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_cargue_iniciar(p_solicitante text, p_capa text, p_sha256 text, p_formato text, p_srid integer, p_columna_llave text, p_filas integer, p_nota text DEFAULT NULL::text, p_masiva text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_carga(p_solicitante, p_capa); c redes.capas%rowtype; r jsonb; v_llave text := btrim(coalesce(p_columna_llave, ''));
begin
  select * into c from redes.capas where codigo = p_capa;
  if not found then perform tecnica.f_error('No existe esa capa', 'P0002'); end if;
  if p_srid is null or p_srid not in (4326, 4686, 3114, 3115, 3116, 3117, 3118, 9377) then
    perform tecnica.f_error('El sistema de coordenadas no es uno de los que se aceptan (WGS 84, MAGNA-SIRGAS geográficas, sus zonas planas o el Origen Nacional 9377)');
  end if;
  if p_formato is null or p_formato not in ('shp', 'gpkg', 'geojson', 'kml', 'csv', 'xlsx') then perform tecnica.f_error('Ese formato de archivo no se acepta'); end if;
  if not (p_formato = any (c.formatos)) and not (p_formato = 'xlsx' and 'csv' = any (c.formatos)) then
    perform tecnica.f_error(format('La capa %s no se carga con %s (acepta: %s)', c.nombre, p_formato, array_to_string(c.formatos, ', ')));
  end if;
  if v_llave = '' or length(v_llave) > 64 then perform tecnica.f_error('Elija la columna llave'); end if;
  if c.columna_llave is not null and v_llave <> c.columna_llave then
    perform tecnica.f_error(format('La capa %s se carga siempre con la columna llave %s (N-5)', c.nombre, c.columna_llave));
  end if;
  if v_llave = '(geometria)' and not (c.fuente = 'carga' and c.prefijo is not null and c.columna_llave is null) then
    perform tecnica.f_error('Esta capa no se puede cargar sin columna llave');
  end if;
  if p_masiva is not null then
    if p_masiva !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then perform tecnica.f_error('El identificador de la carga masiva no es válido'); end if;
    perform set_config('redes.masiva_id', p_masiva, true);
  end if;
  r := redes.f_iniciar(p_capa, lower(p_sha256), p_formato, p_srid, v_llave, p_filas, p_nota, v_email);
  perform set_config('redes.masiva_id', '', true);
  if (r ->> 'nueva')::boolean then
    perform tecnica.f_auditar(v_email, 'redes_carga_iniciar', r ->> 'carga_id', jsonb_build_object('capa', p_capa, 'filas', p_filas, 'formato', p_formato, 'srid', p_srid,
                                                                                                  'columna_llave', v_llave, 'masiva', p_masiva, 'desde', 'pantalla'), null);
  end if;
  return r;
end $function$;

-- public.geoportal_redes_carga_devolver_campo(text,bigint,text,text,text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_carga_devolver_campo(p_solicitante text, p_carga bigint, p_codigo text, p_campo text, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_carga_id(p_solicitante, p_carga); c redes.v_cargas_estado%rowtype; v redes.v_activo_vigente%rowtype; v_campo text := btrim(coalesce(p_campo, ''));
        v_mot text := btrim(coalesce(p_motivo, '')); v_ficha text; v_id bigint;
begin
  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres): por ejemplo, «Técnica corrigió el modelo»'); end if;
  if v_campo = 'origen' and not public.geoportal_es_admin(v_email) then raise exception 'El origen del activo lo cambia solo el administrador' using errcode = '42501'; end if;      -- Corte 6a (§26.2)
  select * into c from redes.v_cargas_estado where id = p_carga;
  if not found then perform tecnica.f_error('No existe esa carga', 'P0002'); end if;
  if c.estado <> 'abierta' then perform tecnica.f_error(format('La carga %s está %s: el campo se devuelve desde una carga abierta', p_carga, c.estado), '55000'); end if;
  if c.capa_codigo = 'muestreo' then perform tecnica.f_error('Los puntos de muestreo no tienen ficha de activo'); end if;
  select * into v from redes.v_activo_vigente where codigo = upper(btrim(coalesce(p_codigo, '')));
  if not found then perform tecnica.f_error('No existe ese activo', 'P0002'); end if;
  if not coalesce(v.capa_codigo = any (redes.f_capas_cubiertas(c.capa_codigo)), false) then
    perform tecnica.f_error(format('El activo %s no es de la capa de esta carga', v.codigo));
  end if;
  perform pg_advisory_xact_lock(hashtext('redes.carga.' || c.capa_codigo));
  if not exists (select 1 from redes.ficha_ediciones e cross join jsonb_array_elements(e.cambios) x
                  where e.activo_id = v.activo_id and x ->> 'campo' = v_campo
                    and not exists (select 1 from redes.ficha_campo_devoluciones d where d.activo_id = e.activo_id and d.campo = v_campo and d.creado_en > e.creado_en)) then
    perform tecnica.f_error(format('El campo %s de %s no está editado en la ficha: ya lo manda la capa', v_campo, v.codigo), '55000');
  end if;
  v_ficha := case when v_campo like 'atributos.%' then v.atributos ->> substr(v_campo, 11)
                  when v_campo = 'origen' then (select coalesce(o.origen, '') || coalesce(' · ' || o.aportante_codigo, '') from redes.v_activo_origen_vigente o where o.activo_id = v.activo_id)
                  else to_jsonb(v) ->> v_campo end;
  insert into redes.ficha_campo_devoluciones (activo_id, campo, carga_id, valor_ficha, motivo, autor)
  values (v.activo_id, v_campo, p_carga, left(v_ficha, 500), v_mot, v_email) returning id into v_id;
  perform tecnica.f_auditar(v_email, 'redes_ficha_campo_devolver', v.codigo, jsonb_build_object('campo', v_campo, 'carga_id', p_carga, 'valor_ficha', left(v_ficha, 500), 'motivo', v_mot), null);
  return jsonb_build_object('devolucion_id', v_id, 'carga_id', p_carga, 'codigo', v.codigo, 'campo', v_campo, 'valor_ficha', v_ficha);
end $function$;

-- public.geoportal_redes_cargue_capas(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_cargue_capas(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v record;
begin
  select * into v from redes.f_perfil_lectura(p_solicitante);
  if v.perfil not in ('admin', 'supervisor') then perform tecnica.f_error('Solo el supervisor de distribución o el administrador ven el Cargue de capas', '42501'); end if;
  return jsonb_build_object(
    'puede_cargar', v.perfil = 'admin' or exists (select 1 from redes.capas x where x.activa and x.carga_supervisor),      -- Corte 6a: el supervisor carga las que no son del modelo
    'max_filas', redes.f_param('carga_max_filas'), 'lote_max_filas', redes.f_param('lote_max_filas'), 'tolerancia_geometria_m', redes.f_param('cruce_geometria_tol_m'),
    'caja', jsonb_build_array(redes.f_param('caja_lon_min'), redes.f_param('caja_lat_min'), redes.f_param('caja_lon_max'), redes.f_param('caja_lat_max')),
    'capas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'codigo', c.codigo, 'nombre', c.nombre, 'puede_cargar', v.perfil = 'admin' or c.carga_supervisor, 'solo_admin', not c.carga_supervisor, 'grupo', c.grupo, 'sistema', c.sistema, 'geometria', c.geometria, 'prefijo', c.prefijo, 'fuente', c.fuente,
               'derivada_de', c.derivada_de, 'columna_llave', c.columna_llave, 'formatos', to_jsonb(c.formatos),
               'lector', case when c.codigo = 'muestreo' then 'muestreo' when c.codigo in ('acueducto', 'alc_conductos', 'alc_pozos', 'alc_descargas') then 'modelo'
                              when c.fuente = 'carga' and c.prefijo is not null then 'generico' end,
               'version', x.version, 'ultima', x.ultima, 'abierta', x.abierta, 'vigentes', x.vigentes,
               'estado', case when c.fuente = 'derivada' then 'derivada' when c.fuente <> 'carga' then 'otro_modulo' when x.version = 0 then 'sin_cargar'
                              when c.periodicidad_dias is not null and (x.ultima ->> 'publicada_en')::timestamptz < clock_timestamp() - make_interval(days => c.periodicidad_dias) then 'desactualizada'
                              else 'al_dia' end)
             order by c.orden, c.codigo)
        from redes.capas c
        cross join lateral (
          select (select count(*) from redes.v_cargas_estado e where e.capa_codigo = c.codigo and e.estado = 'publicada') as version,
                 (select jsonb_build_object('carga_id', e.id, 'publicada_en', e.publicada_en, 'autor', e.autor, 'formato', e.formato, 'filas', e.filas_esperadas, 'nota', e.nota,
                                            'motivo', (select ev.motivo from redes.carga_eventos ev where ev.carga_id = e.id and ev.tipo = 'publicar'))
                    from redes.v_cargas_estado e where e.capa_codigo = c.codigo and e.estado = 'publicada' order by e.publicada_en desc limit 1) as ultima,
                 (select jsonb_build_object('carga_id', e.id, 'creado_en', e.creado_en, 'autor', e.autor, 'formato', e.formato, 'filas', e.filas_esperadas, 'sha256', e.sha256,
                                            'columna_llave', e.columna_llave, 'srid', e.srid_origen, 'masiva', e.masiva_id is not null,
                                            'recibidas', (select count(*) from redes.carga_filas f where f.carga_id = e.id))
                    from redes.v_cargas_estado e where e.capa_codigo = c.codigo and e.estado = 'abierta' order by e.id desc limit 1) as abierta,
                 case when c.codigo = 'muestreo' then (select count(*) from tecnica.puntos p where p.tipo = 'muestreo' and p.activo)
                      else (select count(*) from redes.activo_vigente_mat m where m.capa_codigo = c.codigo and not m.retirado) end as vigentes
        ) x
       where c.activa), '[]'::jsonb));
end $function$;

-- public.geoportal_redes_mi_perfil(text)
CREATE OR REPLACE FUNCTION public.geoportal_redes_mi_perfil(p_solicitante text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'pg_temp'
AS $function$
declare p record;
begin
  select * into p from redes.f_perfil_lectura(p_solicitante);
  return jsonb_build_object('perfil', p.perfil, 'dashboard_redes', p.perfil in ('admin', 'supervisor'), 'dashboard_ptap', public.geoportal_puede(p.email, 'dashboard_tecnico'),
                            'geovisor', redes.f_geovisor_lectura(p.email));      -- Corte 6a
end $function$;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 40 — PERMISOS: revoke all a public, anon, authenticated y service_role ANTES de dar permisos.
-- Tablas nuevas: nadie de la API. Las 4 RPC nuevas: solo execute a service_role (la Edge geoportal-redes).
-- Las 4 funciones internas nuevas: nadie de la API. Las reemplazadas conservan sus permisos (create or replace).
-- =====================================================================
revoke all on table redes.geovisor_capas, redes.capas_por_perfil, redes.capas_por_perfil_eventos from public, anon, authenticated, service_role;
revoke all on sequence redes.capas_por_perfil_eventos_id_seq from public, anon, authenticated, service_role;
revoke all on function redes.f_autorizar_carga(text, text), redes.f_autorizar_carga_id(text, bigint), redes.f_geovisor_acceso(text), redes.f_puede_formulario(text, text)
  from public, anon, authenticated, service_role;
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as firma from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_geovisor_capa', 'geoportal_redes_geovisor_capas_fijar') loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);
    execute format('grant execute on function %s to service_role', f.firma);
  end loop;
end $$;

-- marca de la migración
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_corte6a', 'migracion_redes_corte6a', null, jsonb_build_object('tablas', jsonb_build_array('redes.geovisor_capas', 'redes.capas_por_perfil', 'redes.capas_por_perfil_eventos'),
        'rpc', jsonb_build_array('geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_geovisor_capa', 'geoportal_redes_geovisor_capas_fijar'),
        'reemplazadas', 10, 'columna', 'redes.capas.carga_supervisor'), null);
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 70 — PRUEBAS «N de N» (PROPUESTA). Se corre DESPUÉS de 10, 26, 25 y 40, en la misma transacción.
-- Como las de los cortes anteriores: corre después de la carga real y de los cortes publicados; NO supone códigos ni conteos de la base. Arma sus personas
-- (prueba.redes10.*), sus activos (creados con el motor, en un rincón de Valledupar), un daño, una intervención, un reporte del bot y sus puntos MUE-96nn.
-- Termina con un ERROR a propósito que deshace todo.
--   Resultado esperado:  ERROR: PRUEBAS DE REDES · CORTE 6a … RESULTADO: N de N pruebas correctas — SIN FALLAS
-- =====================================================================
create temp table _r (n serial, nombre text, ok boolean, detalle text);
create function pg_temp.reg(p_nombre text, p_ok boolean, p_detalle text default null) returns void language sql as
$$ insert into _r (nombre, ok, detalle) values (p_nombre, coalesce(p_ok, false), p_detalle) $$;
create function pg_temp.err(p_nombre text, p_sql text, p_estado text default null, p_texto text default null) returns void language plpgsql as $$
declare v_e text; v_m text;
begin
  begin
    execute p_sql;
    perform pg_temp.reg(p_nombre, false, 'No falló y debía fallar');
  exception when others then
    get stacked diagnostics v_e = returned_sqlstate, v_m = message_text;
    perform pg_temp.reg(p_nombre, (p_estado is null or v_e = p_estado) and (p_texto is null or position(p_texto in v_m) > 0), 'SQLSTATE ' || v_e || ': ' || left(v_m, 200));
  end;
end $$;
create function pg_temp.sha(p text) returns text language sql as $$ select encode(sha256(convert_to(p, 'UTF8')), 'hex') $$;
-- posición de prueba: x, y en metros aproximados desde un rincón de Valledupar, lejos de los datos reales
create function pg_temp.lat(y numeric) returns numeric language sql as $$ select round(10.4200 + y * 0.0000090, 6) $$;
create function pg_temp.lon(x numeric) returns numeric language sql as $$ select round(-73.3000 + x * 0.0000091, 6) $$;
create function pg_temp.pt(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakePoint(pg_temp.lon(x), pg_temp.lat(y)), 4326) $$;
create function pg_temp.ln(x numeric, y numeric) returns geometry language sql as $$ select ST_SetSRID(ST_MakeLine(pg_temp.pt(x, y), pg_temp.pt(x + 60, y)), 4326) $$;
create function pg_temp.activo(p_prefijo text, p_geom geometry, p_material text default null, p_diam numeric default null, p_fecha date default null, p_clase text default null) returns text language plpgsql as $$
declare v_id bigint := redes.f_activo_crear(p_prefijo, p_geom, p_clase, p_material, p_diam, 'ZT10 ' || p_prefijo, p_fecha, '{}'::jsonb, 'emdupar', null,
                                            'prueba.redes10.adm@emdupar.gov.co', 'Activo de prueba del Corte 6a');
begin
  return (select codigo from redes.activos where id = v_id);
end $$;
-- ¿la tesela (base64) trae este texto? (los códigos y los valores de texto viajan tal cual dentro del MVT)
create function pg_temp.trae(p_b64 text, p_txt text) returns boolean language sql as $$
  select coalesce(position(convert_to(p_txt, 'UTF8') in decode(nullif(p_b64, ''), 'base64')) > 0, false) $$;
-- la tesela del geovisor que contiene un punto de prueba, a un zoom
create function pg_temp.tesela(p_quien text, p_z integer, x numeric, y numeric) returns text language sql as $$
  select public.geoportal_redes_geovisor_mvt(p_quien, p_z, floor((pg_temp.lon(x) + 180) / 360 * (1 << p_z))::integer,
                                             floor((1 - ln(tan(radians(pg_temp.lat(y))) + 1 / cos(radians(pg_temp.lat(y)))) / pi()) / 2 * (1 << p_z))::integer) $$;
-- ¿la tesela que contiene el activo (a ese zoom) lo trae?
create function pg_temp.sale(p_quien text, p_z integer, p_codigo text) returns boolean language sql as $$
  select pg_temp.trae(public.geoportal_redes_geovisor_mvt(p_quien, p_z, floor((ST_X(c) + 180) / 360 * (1 << p_z))::integer,
                                                         floor((1 - ln(tan(radians(ST_Y(c))) + 1 / cos(radians(ST_Y(c)))) / pi()) / 2 * (1 << p_z))::integer), p_codigo)
    from (select ST_PointOnSurface(geom) as c from redes.activo_vigente_mat where codigo = p_codigo) x $$;
create function pg_temp.codigos(p jsonb) returns text[] language sql as $$ select coalesce(array_agg(f -> 'properties' ->> 'codigo'), '{}') from jsonb_array_elements(p -> 'features') f $$;
create function pg_temp.encendidas(p jsonb) returns text[] language sql as $$
  select coalesce(array_agg(c ->> 'codigo' order by c ->> 'codigo'), '{}') from jsonb_array_elements(p -> 'capas') c where (c ->> 'encendida')::boolean $$;
create function pg_temp.visibles(p jsonb) returns text[] language sql as $$ select coalesce(array_agg(c ->> 'codigo'), '{}') from jsonb_array_elements(p -> 'capas') c $$;
create function pg_temp.archivo(p_ruta text, p_bytes integer default 300000, p_mime text default 'image/jpeg') returns void language sql as $$
  insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', p_ruta, jsonb_build_object('size', p_bytes, 'mimetype', p_mime)) $$;
create function pg_temp.iso(p interval) returns text language sql as $$ select to_char(clock_timestamp() + p, 'YYYY-MM-DD"T"HH24:MI:SSOF') $$;
create function pg_temp.dia(p timestamptz) returns date language sql as $$ select (p at time zone 'America/Bogota')::date $$;

do $prueba$
declare
  a text := 'prueba.redes10.adm@emdupar.gov.co'; sd text := 'prueba.redes10.dist@emdupar.gov.co'; sv text := 'prueba.redes10.planta@emdupar.gov.co';
  dos text := 'prueba.redes10.dos@emdupar.gov.co'; op text := 'prueba.redes10.op@emdupar.gov.co'; op2 text := 'prueba.redes10.op2@emdupar.gov.co';
  na text := 'prueba.redes10.nada@emdupar.gov.co';
  hoy date := (clock_timestamp() at time zone 'America/Bogota')::date;
  v_r jsonb; v_x jsonb; v_c bigint; v_ca bigint; v_t text; v_n integer; v_v integer; v_p jsonb;
  r_chica text; r_grande text; v_val text; v_acc text; v_tan text; v_col_chico text; v_poz text; v_sen text; v_sec text; v_ret text;
  v_dano jsonb; v_itv jsonb; v_dia_dano date; v_dia_itv date;
  v_total integer; v_bien integer; v_fallas text;
begin
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (a, 'ZT10 Admin', 'admin', 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values (sd, 'ZT10 Supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values (sv, 'ZT10 Supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, ver_dashboard_redes, horario, dias) values (dos, 'ZT10 Los dos', 'consulta', true, true, true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values (op, 'ZT10 Operador uno', 'consulta', true, 'sin_restriccion', 'todos'),
    (op2, 'ZT10 Operador sin geovisor', 'consulta', true, 'sin_restriccion', 'todos');
  insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values (na, 'ZT10 Sin Técnica', 'consulta', 'sin_restriccion', 'todos');
  insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values (op, 'asignar_formulario', 'danos_fallas', a), (op2, 'asignar_formulario', 'mantenimiento', a);

  -- ===================== 01. Esquema =====================
  perform pg_temp.reg('01.01 quién carga: las 4 capas del modelo solo el administrador; las demás (13, con muestreo) también el supervisor de distribución',
     (select count(*) from redes.capas where not carga_supervisor and codigo in ('acueducto', 'alc_conductos', 'alc_pozos', 'alc_descargas')) = 4
     and (select count(*) from redes.capas where carga_supervisor) = 13 and (select carga_supervisor from redes.capas where codigo = 'muestreo'));
  perform pg_temp.reg('01.02 el catálogo del geovisor: 19 capas, 7 de tesela con prefijos que existen, 4 por GeoJSON y 8 preparadas',
     (select count(*) from redes.geovisor_capas) = 19 and (select count(*) from redes.geovisor_capas where fuente = 'tesela') = 7
     and (select count(*) from redes.geovisor_capas where fuente = 'geojson') = 4 and (select count(*) from redes.geovisor_capas where fuente = 'preparada') = 8
     and not exists (select 1 from redes.geovisor_capas g cross join unnest(g.prefijos) p where not exists (select 1 from redes.tipos_activo t where t.prefijo = p)));
  perform pg_temp.reg('01.03 ningún prefijo está en dos capas de tesela (un activo, un interruptor)',
     (select count(p) = count(distinct p) from redes.geovisor_capas g cross join unnest(g.prefijos) p));
  perform pg_temp.reg('01.04 capas al abrir: distribución 7, planta 2, operador 6; ninguna preparada, y el operador solo las que ve',
     (select count(*) from redes.capas_por_perfil where encendida and perfil = 'supervisor_distribucion') = 7
     and (select count(*) from redes.capas_por_perfil where encendida and perfil = 'supervisor_planta') = 2
     and (select count(*) from redes.capas_por_perfil where encendida and perfil = 'operador_distribucion') = 6
     and not exists (select 1 from redes.capas_por_perfil c join redes.geovisor_capas g on g.codigo = c.capa where c.encendida and (g.fuente = 'preparada' or (c.perfil = 'operador_distribucion' and g.solo_completo))));
  perform pg_temp.reg('01.05 los 8 parámetros del geovisor, con su valor dentro del rango',
     (select count(*) from redes.parametros where clave like 'geovisor\_%' and valor between minimo and maximo) = 8 and redes.f_param('geovisor_zoom_min') = 13);
  perform pg_temp.err('01.06 el catálogo no se borra', $$delete from redes.geovisor_capas where codigo = 'mapa_calor'$$, '42501');
  perform pg_temp.err('01.07 las capas por perfil no se borran', $$delete from redes.capas_por_perfil$$, '42501');
  perform pg_temp.err('01.08 una capa de tesela sin prefijos no se admite', $$insert into redes.geovisor_capas (codigo, nombre, grupo, fuente, orden) values ('zt_sin', 'Sin prefijos', 'acueducto', 'tesela', 1)$$, '23514');

  -- ===================== 02. Quién carga (David, 16-nov 01:30) =====================
  v_r := public.geoportal_redes_cargue_capas(sd);
  perform pg_temp.reg('02.01 el supervisor de distribución ve «puede cargar», por capa: sensores sí; acueducto, conductos, pozos y descargas no (solo el administrador)',
     (v_r ->> 'puede_cargar')::boolean
     and (select bool_and((x ->> 'puede_cargar')::boolean) from jsonb_array_elements(v_r -> 'capas') x where x ->> 'codigo' in ('sensores', 'acometidas', 'sumideros', 'muestreo', 'sectores', 'scada'))
     and (select bool_and(not (x ->> 'puede_cargar')::boolean and (x ->> 'solo_admin')::boolean) from jsonb_array_elements(v_r -> 'capas') x where x ->> 'codigo' in ('acueducto', 'alc_conductos', 'alc_pozos', 'alc_descargas')));
  v_r := public.geoportal_redes_cargue_capas(a);
  perform pg_temp.reg('02.02 el administrador puede cargar todas', (v_r ->> 'puede_cargar')::boolean
     and not exists (select 1 from jsonb_array_elements(v_r -> 'capas') x where x ->> 'lector' is not null and not (x ->> 'puede_cargar')::boolean));
  perform pg_temp.err('02.03 el supervisor de planta no ve el Cargue (como antes)', format($$select public.geoportal_redes_cargue_capas(%L)$$, sv), '42501');
  perform pg_temp.err('02.04 el supervisor de distribución no abre la red de acueducto', format($$select public.geoportal_redes_cargue_iniciar(%L, 'acueducto', %L, 'shp', 4326, 'ID', 1)$$, sd, pg_temp.sha('zt10-x')), '42501');
  perform pg_temp.err('02.05 … ni los conductos', format($$select public.geoportal_redes_cargue_iniciar(%L, 'alc_conductos', %L, 'shp', 4326, 'LABEL', 1)$$, sd, pg_temp.sha('zt10-x')), '42501');
  perform pg_temp.err('02.06 … ni los pozos', format($$select public.geoportal_redes_cargue_iniciar(%L, 'alc_pozos', %L, 'shp', 4326, 'LABEL', 1)$$, sd, pg_temp.sha('zt10-x')), '42501');
  perform pg_temp.err('02.07 … ni las descargas (también salen del modelo de alcantarillado)', format($$select public.geoportal_redes_cargue_iniciar(%L, 'alc_descargas', %L, 'shp', 4326, 'LABEL', 1)$$, sd, pg_temp.sha('zt10-x')), '42501');
  perform pg_temp.err('02.08 el supervisor de planta no carga', format($$select public.geoportal_redes_cargue_iniciar(%L, 'sensores', %L, 'geojson', 4326, 'ID', 1)$$, sv, pg_temp.sha('zt10-x')), '42501');
  perform pg_temp.err('02.09 el operador no carga', format($$select public.geoportal_redes_cargue_iniciar(%L, 'sensores', %L, 'geojson', 4326, 'ID', 1)$$, op, pg_temp.sha('zt10-x')), '42501');
  perform pg_temp.err('02.10 la carga por psql del 1a sigue siendo del administrador', format($$select public.geoportal_redes_carga_iniciar(%L, 'sensores', %L, 'geojson', 4326, 'ID', 1)$$, sd, pg_temp.sha('zt10-x')), '42501');
  -- el supervisor de distribución carga sensores de punta a punta (abrir, lote, resumen, vista previa y publicar)
  v_r := public.geoportal_redes_cargue_iniciar(sd, 'sensores', pg_temp.sha('zt10-sen'), 'geojson', 4326, 'ID', 2, 'ZT10 sensores del supervisor', '0b1e7d1c-2222-4222-8333-944455556666');
  v_c := (v_r ->> 'carga_id')::bigint;
  perform pg_temp.reg('02.11 el supervisor de distribución abre una carga de sensores (con la marca de la masiva y su auditoría)', (v_r ->> 'nueva')::boolean
     and (select autor from redes.cargas where id = v_c) = sd and exists (select 1 from public.geoportal_auditoria where accion = 'redes_carga_iniciar' and referencia = v_c::text and email = sd), v_r::text);
  v_r := public.geoportal_redes_carga_lote(sd, v_c, jsonb_build_array(
    jsonb_build_object('orden', 1, 'wkt', format('POINT(%s %s)', pg_temp.lon(500), pg_temp.lat(500)), 'atributos', '{"ID": "ZT10-S1", "NOMBRE": "ZT10 Sensor uno"}'::jsonb),
    jsonb_build_object('orden', 2, 'wkt', format('POINT(%s %s)', pg_temp.lon(520), pg_temp.lat(500)), 'atributos', '{"ID": "ZT10-S2", "NOMBRE": "ZT10 Sensor dos"}'::jsonb)));
  v_x := public.geoportal_redes_carga_resumen(sd, v_c);
  perform pg_temp.reg('02.12 … pasa el lote y ve el resumen (2 de tipo SEN, lista para publicar)', (v_x -> 'por_prefijo' ->> 'SEN')::integer = 2 and (v_x ->> 'lista_para_publicar')::boolean, left(v_x::text, 300));
  v_x := public.geoportal_redes_carga_muestra(sd, v_c);
  perform pg_temp.reg('02.13 … y la vista previa', (v_x ->> 'con_geometria')::integer = 2);
  v_x := public.geoportal_redes_carga_publicar(sd, v_c, 'ZT10 primera carga de sensores');
  perform pg_temp.reg('02.14 … y publica: 2 sensores vigentes, con la auditoría a su nombre',
     (select count(*) from redes.activo_vigente_mat where capa_codigo = 'sensores' and llave_capa like 'ZT10-S%' and not retirado) = 2
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_carga_publicar' and referencia = v_c::text and email = sd), left(v_x::text, 300));
  select codigo into v_sen from redes.activo_vigente_mat where capa_codigo = 'sensores' and llave_capa = 'ZT10-S1';
  -- una carga del acueducto abierta por el administrador: el supervisor no la toca
  v_ca := (public.geoportal_redes_cargue_iniciar(a, 'acueducto', pg_temp.sha('zt10-acu'), 'shp', 4326, 'ID', 1, 'ZT10 abierta por el administrador') ->> 'carga_id')::bigint;
  perform pg_temp.err('02.15 el supervisor no pasa lotes a una carga del acueducto', format($$select public.geoportal_redes_carga_lote(%L, %s, '[{"orden": 1, "wkt": null, "atributos": {}}]')$$, sd, v_ca), '42501');
  perform pg_temp.err('02.16 … ni ve su resumen', format($$select public.geoportal_redes_carga_resumen(%L, %s)$$, sd, v_ca), '42501');
  perform pg_temp.err('02.17 … ni su vista previa', format($$select public.geoportal_redes_carga_muestra(%L, %s)$$, sd, v_ca), '42501');
  perform pg_temp.err('02.18 … ni la publica', format($$select public.geoportal_redes_carga_publicar(%L, %s, 'ZT10 no debe')$$, sd, v_ca), '42501');
  perform pg_temp.err('02.19 … ni la anula', format($$select public.geoportal_redes_carga_anular(%L, %s, 'ZT10 no debe poder')$$, sd, v_ca), '42501');
  perform pg_temp.err('02.20 … ni devuelve campos en ella', format($$select public.geoportal_redes_carga_devolver_campo(%L, %s, 'RED-000001', 'nombre', 'ZT10 no debe poder')$$, sd, v_ca), '42501');
  perform pg_temp.err('02.21 … ni revierte el acueducto', format($$select public.geoportal_redes_carga_revertir(%L, 'acueducto', 'ZT10 no debe poder')$$, sd), '42501');
  perform public.geoportal_redes_carga_anular(a, v_ca, 'ZT10 era de prueba');
  perform pg_temp.reg('02.22 el administrador sí anula la suya', (select estado from redes.v_cargas_estado where id = v_ca) = 'anulada');
  perform pg_temp.err('02.23 una carga que no existe: al supervisor no se le dice si existe', format($$select public.geoportal_redes_carga_resumen(%L, -5)$$, sd), '42501');
  perform pg_temp.err('02.24 al administrador sí', format($$select public.geoportal_redes_carga_resumen(%L, -5)$$, a), 'P0002');
  -- el origen al devolver un campo sigue siendo solo del administrador (§26.2)
  v_c := (public.geoportal_redes_cargue_iniciar(sd, 'sensores', pg_temp.sha('zt10-sen-2'), 'geojson', 4326, 'ID', 1) ->> 'carga_id')::bigint;
  perform pg_temp.err('02.25 el supervisor no devuelve «origen» a la capa', format($$select public.geoportal_redes_carga_devolver_campo(%L, %s, %L, 'origen', 'ZT10 el origen no lo toca')$$, sd, v_c, v_sen), '42501');
  perform pg_temp.err('02.26 un campo no editado en la ficha sí llega a la regla de siempre (el supervisor pasó el permiso)',
     format($$select public.geoportal_redes_carga_devolver_campo(%L, %s, %L, 'nombre', 'ZT10 probar el permiso')$$, sd, v_c, v_sen), '55000', 'no está editado');
  perform public.geoportal_redes_carga_anular(sd, v_c, 'ZT10 era de prueba');
  perform pg_temp.reg('02.27 el supervisor anula la suya de sensores', (select estado from redes.v_cargas_estado where id = v_c) = 'anulada');
  v_x := public.geoportal_redes_carga_revertir(sd, 'sensores', 'ZT10 volver a la versión anterior');
  perform pg_temp.reg('02.28 … y revierte sensores a la versión anterior (sin los 2 de prueba)',
     (select count(*) from redes.activo_vigente_mat where capa_codigo = 'sensores' and llave_capa like 'ZT10-S%' and not retirado) = 0, left(v_x::text, 300));

  -- ===================== 03. Quién abre el geovisor y con qué capas (N-11 y N-13) =====================
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZT10 necesita ver la red en la calle');
  perform pg_temp.reg('03.01 «geovisor» en mi perfil: supervisores, administrador y el operador con la casilla sí; el que no la tiene, no',
     (public.geoportal_redes_mi_perfil(a) ->> 'geovisor')::boolean and (public.geoportal_redes_mi_perfil(sd) ->> 'geovisor')::boolean
     and (public.geoportal_redes_mi_perfil(sv) ->> 'geovisor')::boolean and (public.geoportal_redes_mi_perfil(op) ->> 'geovisor')::boolean
     and not (public.geoportal_redes_mi_perfil(op2) ->> 'geovisor')::boolean and (public.geoportal_redes_mi_perfil(sd) ->> 'dashboard_redes')::boolean);
  v_r := public.geoportal_redes_geovisor(a);
  perform pg_temp.reg('03.02 el administrador: completo, con los dos perfiles de supervisor y las capas encendidas de los dos (8)',
     v_r ->> 'perfil' = 'admin' and (v_r ->> 'completo')::boolean and v_r -> 'perfiles' = '["supervisor_distribucion", "supervisor_planta"]'::jsonb
     and pg_temp.encendidas(v_r) = array['acu_instalaciones', 'acu_nodos', 'acu_tramos', 'alc_conductos', 'alc_pozos', 'danos', 'intervenciones', 'muestreo']
     and cardinality(pg_temp.visibles(v_r)) = 19, pg_temp.encendidas(v_r)::text);
  perform pg_temp.reg('03.03 … y la tabla de capas por omisión para editarla', jsonb_array_length(v_r -> 'por_perfil') = 15);
  perform pg_temp.reg('03.04 … con zooms, rango, hoy, tipos con su alias y materiales', (v_r -> 'zoom' ->> 'min')::numeric = 13 and (v_r ->> 'rango_meses')::integer = 12
     and (v_r ->> 'hoy')::date = hoy and v_r -> 'tipos' ->> 'RED' is not null and v_r -> 'estados' ->> 'en_operacion' = 'En operación' and jsonb_array_length(v_r -> 'materiales') > 0 and (v_r ->> 'version')::integer >= 1);
  v_r := public.geoportal_redes_geovisor(sd);
  perform pg_temp.reg('03.05 el supervisor de distribución: redes y actividades encendidas; muestreo y reportes del bot los ve pero apagados; sin la tabla de omisión',
     v_r ->> 'perfil' = 'supervisor' and pg_temp.encendidas(v_r) = array['acu_instalaciones', 'acu_nodos', 'acu_tramos', 'alc_conductos', 'alc_pozos', 'danos', 'intervenciones']
     and 'muestreo' = any (pg_temp.visibles(v_r)) and 'reportes_bot' = any (pg_temp.visibles(v_r)) and v_r -> 'por_perfil' = 'null'::jsonb, pg_temp.encendidas(v_r)::text);
  perform pg_temp.reg('03.06 … y los dos formularios (por su permiso de supervisor)', (v_r -> 'formularios' ->> 'danos_fallas')::boolean and (v_r -> 'formularios' ->> 'mantenimiento')::boolean);
  v_r := public.geoportal_redes_geovisor(sv);
  perform pg_temp.reg('03.07 el supervisor de planta: muestreo y tanques encendidos; completo',
     pg_temp.encendidas(v_r) = array['acu_instalaciones', 'muestreo'] and (v_r ->> 'completo')::boolean and v_r -> 'perfiles' = '["supervisor_planta"]'::jsonb, pg_temp.encendidas(v_r)::text);
  v_r := public.geoportal_redes_geovisor(dos);
  perform pg_temp.reg('03.08 una persona de las dos áreas: la unión de las capas de sus perfiles',
     pg_temp.encendidas(v_r) = array['acu_instalaciones', 'acu_nodos', 'acu_tramos', 'alc_conductos', 'alc_pozos', 'danos', 'intervenciones', 'muestreo'], pg_temp.encendidas(v_r)::text);
  v_r := public.geoportal_redes_geovisor(op);
  perform pg_temp.reg('03.09 el operador con la casilla: solo lectura, sin muestreo, reportes ni capas preparadas; redes y actividades encendidas',
     v_r ->> 'perfil' = 'operador' and not (v_r ->> 'completo')::boolean and not (v_r ->> 'ficha')::boolean
     and not ('muestreo' = any (pg_temp.visibles(v_r))) and not ('reportes_bot' = any (pg_temp.visibles(v_r))) and not ('contratos' = any (pg_temp.visibles(v_r)))
     and pg_temp.encendidas(v_r) = array['acu_nodos', 'acu_tramos', 'alc_conductos', 'alc_pozos', 'danos', 'intervenciones'], pg_temp.visibles(v_r)::text);
  perform pg_temp.reg('03.10 … con «Reportar daño» (lo tiene asignado) y sin «Registrar intervención» (no lo tiene)',
     (v_r -> 'formularios' ->> 'danos_fallas')::boolean and not (v_r -> 'formularios' ->> 'mantenimiento')::boolean);
  perform pg_temp.err('03.11 el operador sin la casilla no abre el geovisor (aunque tenga formularios de distribución)', format($$select public.geoportal_redes_geovisor(%L)$$, op2), '42501');
  perform pg_temp.err('03.12 quien no es de Técnica no lo abre', format($$select public.geoportal_redes_geovisor(%L)$$, na), '42501');
  perform pg_temp.err('03.13 sin solicitante', $$select public.geoportal_redes_geovisor('')$$, '28000');
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'no', 'ZT10 ya no necesita el geovisor');
  perform pg_temp.err('03.14 al quitarle la casilla, el operador deja de abrirlo', format($$select public.geoportal_redes_geovisor(%L)$$, op), '42501');
  perform public.geoportal_redes_personal_fijar(sd, op, 'geovisor', 'si', 'ZT10 lo necesita otra vez');

  -- ===================== 04. Capas por omisión (las edita el administrador, con motivo) =====================
  perform pg_temp.err('04.01 el supervisor no las cambia', format($$select public.geoportal_redes_geovisor_capas_fijar(%L, 'supervisor_distribucion', 'muestreo', true, 'ZT10 no debe poder')$$, sd), '42501');
  perform pg_temp.err('04.02 sin motivo, no', format($$select public.geoportal_redes_geovisor_capas_fijar(%L, 'supervisor_distribucion', 'muestreo', true, 'corto')$$, a), '22023', 'motivo');
  perform pg_temp.err('04.03 una capa preparada no se enciende al abrir', format($$select public.geoportal_redes_geovisor_capas_fijar(%L, 'supervisor_distribucion', 'contratos', true, 'ZT10 todavía no tiene datos')$$, a), '22023', 'todavía no tiene datos');
  perform pg_temp.err('04.04 al operador no se le enciende lo que no ve', format($$select public.geoportal_redes_geovisor_capas_fijar(%L, 'operador_distribucion', 'muestreo', true, 'ZT10 el operador no la ve')$$, a), '22023', 'no ve');
  perform pg_temp.err('04.05 un perfil que no existe', format($$select public.geoportal_redes_geovisor_capas_fijar(%L, 'gerente', 'muestreo', true, 'ZT10 perfil que no existe')$$, a), '22023', 'perfil');
  v_x := public.geoportal_redes_geovisor_capas_fijar(a, 'supervisor_distribucion', 'muestreo', true, 'ZT10 el supervisor también mira el muestreo');
  perform pg_temp.reg('04.06 el administrador enciende muestreo para el supervisor de distribución: queda el evento con el antes y la auditoría',
     (v_x ->> 'cambio')::boolean and 'muestreo' = any (pg_temp.encendidas(public.geoportal_redes_geovisor(sd)))
     and exists (select 1 from redes.capas_por_perfil_eventos where perfil = 'supervisor_distribucion' and capa = 'muestreo' and antes is null and despues and autor = a)
     and exists (select 1 from public.geoportal_auditoria where accion = 'redes_geovisor_capas_fijar' and referencia = 'supervisor_distribucion/muestreo'));
  v_x := public.geoportal_redes_geovisor_capas_fijar(a, 'supervisor_distribucion', 'muestreo', true, 'ZT10 otra vez lo mismo');
  perform pg_temp.reg('04.07 lo mismo otra vez no deja otro evento', not (v_x ->> 'cambio')::boolean
     and (select count(*) from redes.capas_por_perfil_eventos where perfil = 'supervisor_distribucion' and capa = 'muestreo') = 1);
  perform public.geoportal_redes_geovisor_capas_fijar(a, 'supervisor_distribucion', 'danos', false, 'ZT10 los daños se prenden a mano');
  perform pg_temp.reg('04.08 apagar una: el supervisor ya no la abre encendida; el administrador tampoco (si nadie de sus perfiles la tiene)',
     not ('danos' = any (pg_temp.encendidas(public.geoportal_redes_geovisor(sd)))) and not ('danos' = any (pg_temp.encendidas(public.geoportal_redes_geovisor(a))))
     and (select antes and not despues from redes.capas_por_perfil_eventos where capa = 'danos'));
  perform pg_temp.err('04.09 los eventos no se cambian', $$update redes.capas_por_perfil_eventos set motivo = 'cambiado a mano'$$, '42501');

  -- ===================== 05. La tesela del geovisor =====================
  r_chica := pg_temp.activo('RED', pg_temp.ln(0, 0), 'PVC', 100, (hoy - interval '30 years')::date);
  r_grande := pg_temp.activo('RED', pg_temp.ln(0, 40), 'AC', 250, null);
  v_val := pg_temp.activo('VAL', pg_temp.pt(0, 80), null, 100, null, null);
  v_acc := pg_temp.activo('ACC', pg_temp.pt(20, 80));
  v_tan := pg_temp.activo('TAN', pg_temp.pt(40, 80));
  v_col_chico := pg_temp.activo('COL', pg_temp.ln(0, 120), 'CONCRETO', 200, null);
  v_poz := pg_temp.activo('POZ', pg_temp.pt(60, 80));
  v_sec := pg_temp.activo('SEC', ST_SetSRID(ST_MakeEnvelope(pg_temp.lon(-50), pg_temp.lat(-50), pg_temp.lon(150), pg_temp.lat(200)), 4326));
  v_ret := pg_temp.activo('VAL', pg_temp.pt(80, 80));
  update redes.activo_vigente_mat set retirado = true where codigo = v_ret;      -- un retirado (en la vida real lo deja así una recarga)
  perform pg_temp.reg('05.00 activos de prueba creados con el motor',
     (select count(*) from redes.activo_vigente_mat where codigo in (r_chica, r_grande, v_val, v_acc, v_tan, v_col_chico, v_poz, v_sec)) = 8,
     concat_ws(' ', r_chica, r_grande, v_val, v_acc, v_tan, v_col_chico, v_poz, v_sec));
  perform pg_temp.reg('05.01 a zoom 12 la tesela sale vacía (la red no se dibuja tan lejos)', pg_temp.tesela(a, 12, 0, 0) = '' and not pg_temp.sale(a, 12, r_grande));
  perform pg_temp.reg('05.02 a zoom 13: la red principal (250 mm), el tanque y el sector; no el tramo de 100 mm, ni el conducto de 200, ni la válvula ni el pozo',
     pg_temp.sale(a, 13, r_grande) and pg_temp.sale(a, 13, v_tan) and pg_temp.sale(a, 13, v_sec)
     and not pg_temp.sale(a, 13, r_chica) and not pg_temp.sale(a, 13, v_col_chico) and not pg_temp.sale(a, 13, v_val) and not pg_temp.sale(a, 13, v_poz));
  perform pg_temp.reg('05.03 a zoom 14: todos los tramos; todavía no los puntos', pg_temp.sale(a, 14, r_chica) and pg_temp.sale(a, 14, v_col_chico) and not pg_temp.sale(a, 14, v_val));
  perform pg_temp.reg('05.04 a zoom 15: válvulas y pozos; no los accesorios', pg_temp.sale(a, 15, v_val) and pg_temp.sale(a, 15, v_poz) and not pg_temp.sale(a, 15, v_acc) and not pg_temp.sale(a, 16, v_acc));
  perform pg_temp.reg('05.05 a zoom 17: los accesorios', pg_temp.sale(a, 17, v_acc));
  v_t := pg_temp.tesela(a, 16, 0, 0);
  perform pg_temp.reg('05.06 trae lo que colorea: material, estado y la forma', pg_temp.sale(a, 16, r_chica) and pg_temp.trae(v_t, 'PVC') and pg_temp.trae(v_t, 'AC') and pg_temp.trae(v_t, 'en_operacion')
     and pg_temp.trae(v_t, 'tramo') and pg_temp.trae(v_t, 'area'));
  perform pg_temp.reg('05.07 un activo retirado no sale', not pg_temp.sale(a, 17, v_ret) and pg_temp.sale(a, 17, v_val));
  perform pg_temp.reg('05.08 el operador con la casilla también recibe la tesela de la red', pg_temp.sale(op, 16, r_chica) and pg_temp.sale(op, 16, v_poz));
  perform pg_temp.err('05.09 el operador sin la casilla no', format($$select pg_temp.tesela(%L, 16, 0, 0)$$, op2), '42501');
  perform pg_temp.err('05.10 una tesela fuera de rango', format($$select public.geoportal_redes_geovisor_mvt(%L, 14, 99999, 1)$$, a), '22023', 'fuera de rango');
  update redes.geovisor_capas set activa = false where codigo = 'alc_pozos';
  perform pg_temp.reg('05.11 una capa desactivada del catálogo deja de verse en el geovisor (sin otra migración)', not ('alc_pozos' = any (pg_temp.visibles(public.geoportal_redes_geovisor(a)))));
  perform pg_temp.reg('05.12 … el pozo ya no sale en la tesela y el tramo sí', not pg_temp.sale(a, 16, v_poz) and pg_temp.sale(a, 16, r_chica));
  update redes.geovisor_capas set activa = true where codigo = 'alc_pozos';
  perform pg_temp.reg('05.13 la edad sale en años (30 para el de 30 años) y sin fecha va sin edad',
     (select extract(year from age(hoy, fecha_instalacion))::integer from redes.activo_vigente_mat where codigo = r_chica) = 30
     and (select fecha_instalacion is null from redes.activo_vigente_mat where codigo = r_grande));

  -- ===================== 06. Capas por fecha (daños, intervenciones y reportes del bot) y muestreo =====================
  v_p := public.geoportal_redes_preparar_dano(op, 1);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_dano := public.geoportal_redes_crear_dano(op, (v_p ->> 'dano_id')::uuid, jsonb_build_object('clase', 'dano', 'tipo', 'fuga', 'sistema', 'acueducto', 'activo', r_chica,
         'lat', pg_temp.lat(0), 'lon', pg_temp.lon(30), 'ubicacion_origen', 'gps', 't_detectado', pg_temp.iso('-20 minutes'), 'tipo_rotura', 'parcial', 'riesgo', 'medio',
         'causa_clase', 'terceros', 'tercero_tipo', 'vehiculo', 'tercero_nombre', 'ZT10 Placa ABC123', 'descripcion', 'ZT10 vecino Pedro 3001234567 avisó',
         'fotos', jsonb_build_array(jsonb_build_object('n', 1, 'momento', 'dano', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta'))));
  v_dia_dano := pg_temp.dia((select t_detectado from redes.danos where codigo = v_dano ->> 'codigo'));
  v_r := public.geoportal_redes_geovisor_capa(sd, 'danos', v_dia_dano, v_dia_dano);
  perform pg_temp.reg('06.01 la capa de daños del día trae el daño con su código, tipo, estado y activo', (v_dano ->> 'codigo') = any (pg_temp.codigos(v_r))
     and (select f -> 'properties' ->> 'activo' from jsonb_array_elements(v_r -> 'features') f where f -> 'properties' ->> 'codigo' = v_dano ->> 'codigo') = r_chica
     and not (v_r ->> 'recortada')::boolean, left(v_r::text, 300));
  perform pg_temp.reg('06.02 sin la descripción, el tercero, las fotos ni el autor', v_r::text not like '%Pedro%' and v_r::text not like '%3001234567%' and v_r::text not like '%ABC123%'
     and v_r::text not like '%' || op || '%' and v_r::text not like '%redes-evidencias%');
  v_r := public.geoportal_redes_geovisor_capa(sd, 'danos', v_dia_dano - 3, v_dia_dano - 1);
  perform pg_temp.reg('06.03 en otras fechas no sale', not ((v_dano ->> 'codigo') = any (pg_temp.codigos(v_r))));
  perform public.geoportal_redes_dano_evento(sd, v_dano ->> 'codigo', 'ocultar', 'ZT10 dato de prueba');
  perform pg_temp.reg('06.04 un daño oculto no sale', not ((v_dano ->> 'codigo') = any (pg_temp.codigos(public.geoportal_redes_geovisor_capa(sd, 'danos', v_dia_dano, v_dia_dano)))));
  perform public.geoportal_redes_dano_evento(sd, v_dano ->> 'codigo', 'reincluir', 'ZT10 volver a mostrarlo');
  -- intervención del supervisor sobre el tramo, con su foto
  v_p := public.geoportal_redes_preparar_intervencion(sd, 1, 0);
  perform pg_temp.archivo(v_p -> 'fotos' -> 0 ->> 'ruta');
  v_itv := public.geoportal_redes_crear_intervencion(sd, (v_p ->> 'intervencion_id')::uuid, jsonb_build_object('nace_de', 'programada', 'tipo', 'preventivo', 'sistema', 'acueducto',
         'activo', r_grande, 'lat', pg_temp.lat(40), 'lon', pg_temp.lon(10), 'precision_m', 5, 'ubicacion_origen', 'gps', 't_inicio', pg_temp.iso('-50 minutes'), 't_fin', pg_temp.iso('-10 minutes'),
         'descripcion', 'ZT10 limpieza, avisó la señora Marta', 'materiales', '[]'::jsonb, 'ejecutor', 'emdupar', 'fuentes', jsonb_build_array(jsonb_build_object('aportante', 'emdupar')),
         'archivos', jsonb_build_array(jsonb_build_object('n', 1, 'clase', 'despues', 'ruta', v_p -> 'fotos' -> 0 ->> 'ruta'))));
  v_dia_itv := pg_temp.dia((select t_inicio from redes.intervenciones where codigo = v_itv ->> 'codigo'));
  v_r := public.geoportal_redes_geovisor_capa(sd, 'intervenciones', v_dia_itv, v_dia_itv);
  perform pg_temp.reg('06.05 la capa de intervenciones trae la del día con su tipo y activo, sin la descripción',
     (v_itv ->> 'codigo') = any (pg_temp.codigos(v_r)) and v_r::text not like '%Marta%'
     and (select f -> 'properties' ->> 'tipo_codigo' from jsonb_array_elements(v_r -> 'features') f where f -> 'properties' ->> 'codigo' = v_itv ->> 'codigo') = 'preventivo', left(v_r::text, 300));
  perform public.geoportal_redes_intervencion_evento(sd, v_itv ->> 'codigo', 'anulada', 'ZT10 era de prueba');
  perform pg_temp.reg('06.06 una intervención anulada no sale', not ((v_itv ->> 'codigo') = any (pg_temp.codigos(public.geoportal_redes_geovisor_capa(sd, 'intervenciones', v_dia_itv, v_dia_itv)))));
  -- reporte del bot
  perform redes.f_reporte_externo_recibir(jsonb_build_object('radicado', 'ZT10-0001', 'canal', 'telegram', 'tipo', 'Fuga', 'lat', pg_temp.lat(10), 'lon', pg_temp.lon(10),
                                                            'direccion', 'ZT10 Calle 1 # 2-3', 'descripcion', 'ZT10 la vecina Rosa', 'recibido_en', pg_temp.iso('-30 minutes')));
  v_r := public.geoportal_redes_geovisor_capa(sd, 'reportes_bot', pg_temp.dia(clock_timestamp() - interval '30 minutes'), pg_temp.dia(clock_timestamp() - interval '30 minutes'));
  perform pg_temp.reg('06.07 la capa de reportes del bot trae el radicado y el estado, sin la dirección ni la descripción',
     'ZT10-0001' = any (pg_temp.codigos(v_r)) and v_r::text not like '%Rosa%' and v_r::text not like '%Calle 1%', left(v_r::text, 300));
  -- muestreo
  insert into tecnica.puntos (codigo, nombre, tipo, zona) values ('MUE-9601', 'ZT10 Uno', 'muestreo', 'norte'), ('MUE-9602', 'ZT10 Dos', 'muestreo', 'sur');
  insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, autor) select id, pg_temp.lat(300), pg_temp.lon(300), 'verificada', 'david', a from tecnica.puntos where codigo = 'MUE-9601';
  insert into tecnica.puntos_ubicacion (punto_id, lat, lon, exactitud, fuente, autor) select id, pg_temp.lat(320), pg_temp.lon(300), 'aproximada', 'barrio', a from tecnica.puntos where codigo = 'MUE-9602';
  v_r := public.geoportal_redes_geovisor_capa(sv, 'muestreo');
  perform pg_temp.reg('06.08 la capa de muestreo trae los puntos con su exactitud (verificada o aproximada)',
     (select f -> 'properties' ->> 'exactitud' from jsonb_array_elements(v_r -> 'features') f where f -> 'properties' ->> 'codigo' = 'MUE-9601') = 'verificada'
     and (select f -> 'properties' ->> 'exactitud' from jsonb_array_elements(v_r -> 'features') f where f -> 'properties' ->> 'codigo' = 'MUE-9602') = 'aproximada');
  -- reglas de las fechas y del operador
  perform pg_temp.err('06.09 más de 12 meses de rango', format($$select public.geoportal_redes_geovisor_capa(%L, 'danos', %L, %L)$$, sd, hoy - 400, hoy), '22023', '12 meses');
  perform pg_temp.err('06.10 la fecha final futura', format($$select public.geoportal_redes_geovisor_capa(%L, 'danos', %L, %L)$$, sd, hoy, hoy + 1), '22023', 'futura');
  perform pg_temp.err('06.11 las fechas al revés', format($$select public.geoportal_redes_geovisor_capa(%L, 'danos', %L, %L)$$, sd, hoy, hoy - 1), '22023', 'posterior');
  v_r := public.geoportal_redes_geovisor_capa(sd, 'danos', hoy - 365, hoy);
  perform pg_temp.reg('06.12 doce meses exactos sí', v_r ->> 'type' = 'FeatureCollection');
  v_r := public.geoportal_redes_geovisor_capa(op, 'danos');
  perform pg_temp.reg('06.13 el operador ve los daños del día (sin fechas = hoy)', (v_r ->> 'desde')::date = hoy and (v_r ->> 'hasta')::date = hoy
     and (v_dia_dano <> hoy or (v_dano ->> 'codigo') = any (pg_temp.codigos(v_r))));
  perform pg_temp.err('06.14 el operador no pide otros días', format($$select public.geoportal_redes_geovisor_capa(%L, 'danos', %L, %L)$$, op, hoy - 7, hoy), '42501');
  perform pg_temp.err('06.15 el operador no ve el muestreo', format($$select public.geoportal_redes_geovisor_capa(%L, 'muestreo')$$, op), '42501');
  perform pg_temp.err('06.16 … ni los reportes del bot', format($$select public.geoportal_redes_geovisor_capa(%L, 'reportes_bot')$$, op), '42501');
  perform pg_temp.err('06.17 una capa preparada no tiene datos', format($$select public.geoportal_redes_geovisor_capa(%L, 'contratos')$$, a), 'P0002');
  perform pg_temp.err('06.18 una capa de tesela no va por aquí', format($$select public.geoportal_redes_geovisor_capa(%L, 'acu_tramos')$$, a), 'P0002');
  perform pg_temp.err('06.19 el operador sin la casilla no ve las actividades', format($$select public.geoportal_redes_geovisor_capa(%L, 'danos')$$, op2), '42501');
  -- tope de elementos: con el parámetro en 100, un rango con más de 100 sale recortado (se arman 101 reportes del bot de prueba)
  for v_n in 1 .. 101 loop
    perform redes.f_reporte_externo_recibir(jsonb_build_object('radicado', 'ZT10-T' || lpad(v_n::text, 3, '0'), 'canal', 'telegram', 'tipo', 'Fuga',
                                                              'lat', pg_temp.lat(v_n), 'lon', pg_temp.lon(0), 'recibido_en', pg_temp.iso('-2 days')));
  end loop;
  update redes.parametros set valor = 100 where clave = 'geovisor_max_elementos';
  v_r := public.geoportal_redes_geovisor_capa(a, 'reportes_bot', pg_temp.dia(clock_timestamp() - interval '2 days'), pg_temp.dia(clock_timestamp() - interval '2 days'));
  perform pg_temp.reg('06.20 con más elementos que el tope: 100 y «recortada»', jsonb_array_length(v_r -> 'features') = 100 and (v_r ->> 'recortada')::boolean);

  -- ---------- Resultado ----------
  select count(*), count(*) filter (where ok), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by _r.n) filter (where not ok), '') into v_total, v_bien, v_fallas from _r;
  raise exception E'PRUEBAS DE REDES · CORTE 6a (esperado: este ERROR deshace todo lo de la prueba)\n%\nRESULTADO: % de % pruebas correctas — %', v_fallas, v_bien, v_total, case when v_bien = v_total then 'SIN FALLAS' else (v_total - v_bien) || ' FALLA(S)' end;
end
$prueba$;
rollback;
