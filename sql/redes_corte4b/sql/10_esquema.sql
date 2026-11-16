-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4b · 10 — GUARDIA Y TABLAS NUEVAS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: 02 fila 4b, D-18, D-19, N-12, N-13 y §27 de la bitácora.
-- · Presupone el 4a aplicado (huella del conjunto de funciones de redes, de v_dano y de v_epicrisis, y de las 4 funciones de permisos del 4a).
-- · NO toca ninguna función viva ni de permisos: solo agrega tablas, una vista, funciones internas y RPC nuevas (ningún create or replace de lo existente).
-- · Tablas nuevas: tecnica.personal_ficha_eventos (D-18: área, cargo, cuadrilla y geovisor; solo inserción) y redes.cuadrillas (catálogo).
--   No se toca el CHECK de tecnica.personal_tecnico_eventos, que sigue filtrando la captura.
-- =====================================================================
do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'geoportal_lista_blanca' and column_name = 'ver_dashboard_redes') then
    raise exception 'Falta el Corte 4a (ver_dashboard_redes): aplíquelo antes';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '1a2be013019c9a59f1c1e0f2241661f0' then
    raise exception 'Las funciones de redes no son las del Corte 4a (o el Corte 4b ya está aplicado): deténgase y avise';
  end if;
  if md5(pg_get_viewdef('redes.v_dano'::regclass, true)) <> 'bee1b39d753fc55ae7cb85a3952896fb' or md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> 'a1e45ec72cb5b254a67698111994746a' then
    raise exception 'Las vistas v_dano o v_epicrisis no son las del 4a: deténgase y avise';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in (('geoportal_puede', '32f174a55b95788d3f8187b507303c2f'), ('geoportal_mis_permisos', '83166fe17be58da67bbdedaae429bedb'), ('geoportal_admin_permisos', 'e5a90103b4a83440fd826f03266b7245'), ('geoportal_admin_listar', 'd7311a32ea03cccd6c83691e63ba10bc'))) <> 4 then
    raise exception 'Las 4 funciones de permisos no son las del Corte 4a: deténgase y avise';
  end if;
  if to_regclass('tecnica.personal_ficha_eventos') is not null or to_regclass('redes.cuadrillas') is not null then
    raise exception 'tecnica.personal_ficha_eventos o redes.cuadrillas ya existen: el Corte 4b parece aplicado';
  end if;
  if to_regprocedure('tecnica.f_solo_agregar()') is null or to_regprocedure('tecnica.f_tecnica_activa(text)') is null or to_regprocedure('tecnica.f_formulario_asignado(text,text)') is null then
    raise exception 'Faltan tecnica.f_solo_agregar, f_tecnica_activa o f_formulario_asignado';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. CUADRILLAS (catálogo de redes, D-18). Solo el administrador las crea, les cambia el nombre o las desactiva (nada se borra).
-- ---------------------------------------------------------------------
create table redes.cuadrillas (
  id         bigint generated always as identity primary key,
  nombre     text not null check (length(btrim(nombre)) between 2 and 60),
  activa     boolean not null default true,
  orden      integer not null default 0,
  autor      text not null,
  creado_en  timestamptz not null default clock_timestamp()
);
create unique index ux_cuadrillas_nombre on redes.cuadrillas (lower(btrim(nombre)));
comment on table redes.cuadrillas is 'Cuadrillas de distribución (D-18). Las crea y edita el administrador desde Catálogo, con motivo en la auditoría. Nada se borra: se desactiva.';
create trigger t_no_borrar before delete on redes.cuadrillas for each row execute function tecnica.f_solo_agregar();
create trigger t_no_vaciar before truncate on redes.cuadrillas for each statement execute function tecnica.f_solo_agregar();
alter table redes.cuadrillas enable row level security;

-- ---------------------------------------------------------------------
-- 2. FICHA DEL PERSONAL DE TÉCNICA (D-18 y N-13). Solo inserción: lo vigente es el último evento por persona y tipo.
--    · fijar_area: planta | distribucion | ambas (decide en qué dashboard sale la persona; §16);
--    · fijar_cargo: texto de 2 a 80, o nulo para quitarlo;
--    · fijar_cuadrilla: id de redes.cuadrillas, o nulo para quitarla;
--    · fijar_geovisor: si | no (geovisor principal en solo lectura del operador de distribución; Corte 6). Una sola casilla, en Personal del
--      Dashboard distribución (§27.3): Administración la muestra sin editarla.
-- ---------------------------------------------------------------------
create table tecnica.personal_ficha_eventos (
  id          bigint generated always as identity primary key,
  persona     text not null check (persona = lower(btrim(persona)) and position('@' in persona) > 1),
  tipo_evento text not null check (tipo_evento in ('fijar_area', 'fijar_cargo', 'fijar_cuadrilla', 'fijar_geovisor')),
  valor       text,
  motivo      text not null check (length(btrim(motivo)) between 10 and 500),
  autor       text not null,
  creado_en   timestamptz not null default clock_timestamp(),
  check (case tipo_evento
           when 'fijar_area' then valor in ('planta', 'distribucion', 'ambas')
           when 'fijar_geovisor' then valor in ('si', 'no')
           when 'fijar_cargo' then valor is null or length(btrim(valor)) between 2 and 80
           when 'fijar_cuadrilla' then valor is null or valor ~ '^[0-9]{1,18}$' end)
);
create index ix_pfe_persona on tecnica.personal_ficha_eventos (persona, tipo_evento, id desc);
comment on table tecnica.personal_ficha_eventos is 'Área, cargo, cuadrilla y geovisor del personal de Técnica (D-18, N-13). Solo inserción. La pone el supervisor de distribución o el administrador desde Personal del Dashboard distribución, siempre con motivo.';
create trigger t_solo_agregar before update or delete on tecnica.personal_ficha_eventos for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.personal_ficha_eventos for each statement execute function tecnica.f_solo_agregar();
alter table tecnica.personal_ficha_eventos enable row level security;
