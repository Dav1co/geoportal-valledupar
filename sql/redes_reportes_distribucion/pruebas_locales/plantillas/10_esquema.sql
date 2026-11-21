-- =====================================================================
-- TÉCNICA · FASE 1 · DESCARGAS DE DISTRIBUCIÓN (pestaña «Descargas» del Dashboard distribución) · 10 — GUARDIA Y ESQUEMA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Encargo de David del 19-nov: cada formulario tiene su propia descarga. «Daños y fallas» e «Intervenciones» siguen con la ruta «descarga» de siempre
-- (no se toca); aquí van las siete nuevas: Encontrar o reportar activo, Válvulas cerradas, Eventos de suspensión, Línea 116, Reportes del bot,
-- Usuarios sensibles y Activos de la red.
-- · Presupone el aviso por contrato publicado: huella del conjunto de funciones de redes {{MD5_BASE}}.
-- · Solo AGREGA: 2 tablas (las descargas y sus cierres, solo inserción), funciones internas de lectura y 4 RPC (la cuarta, la lista del filtro de sector). No reemplaza nada.
-- =====================================================================
do $$
begin
  if to_regclass('redes.reporte_descargas') is not null or to_regprocedure('public.geoportal_redes_reporte_iniciar(text,text,jsonb,text,boolean,text)') is not null then
    raise exception 'Las descargas de Distribución ya están aplicadas: deténgase y avise';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_BASE}}' then
    raise exception 'Las funciones de redes no son las del aviso por contrato publicado (huella {{MD5_BASE}}): deténgase y avise';
  end if;
  if to_regclass('redes.v_levantar_punto') is null or to_regclass('redes.valvula_maniobras') is null or to_regclass('redes.v_evento_suspension') is null
     or to_regclass('redes.l116_vigente') is null or to_regclass('redes.v_reporte_externo') is null or to_regclass('redes.v_usuario_sensible') is null
     or to_regclass('redes.activo_vigente_mat') is null or to_regprocedure('redes.f_supervisor(text,text)') is null or to_regprocedure('redes.f_sector_de(geometry)') is null
     or to_regprocedure('redes.f_evento_reportes(bigint)') is null or to_regprocedure('tecnica.f_auditar(text,text,text,jsonb,text)') is null then
    raise exception 'Faltan tablas o funciones de los cortes publicados: deténgase y avise';
  end if;
end $$;

create table redes.reporte_descargas (
  id         bigint generated always as identity primary key,
  email      text not null check (email = lower(email) and position('@' in email) > 1),
  reporte    text not null check (reporte ~ '^[a-z0-9_]{3,30}$'),
  filtros    jsonb not null check (jsonb_typeof(filtros) = 'object'),
  incluir    boolean not null,
  formato    text not null check (formato in ('csv', 'xlsx')),
  total      integer not null check (total >= 0),
  corte_en   timestamptz not null,
  ip         text,
  creado_en  timestamptz not null default clock_timestamp()
);
create index ix_redes_rep_descargas_email on redes.reporte_descargas (email, id desc);
create table redes.reporte_descarga_cierres (
  descarga_id bigint primary key references redes.reporte_descargas (id),
  filas       integer not null check (filas >= 0),
  resultado   text not null check (resultado in ('completa', 'cancelada', 'error')),
  ip          text,
  creado_en   timestamptz not null default clock_timestamp()
);
create trigger t_solo_agregar before update or delete on redes.reporte_descargas for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on redes.reporte_descargas for each statement execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar before update or delete on redes.reporte_descarga_cierres for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on redes.reporte_descarga_cierres for each statement execute function tecnica.f_solo_agregar();
alter table redes.reporte_descargas enable row level security;
alter table redes.reporte_descarga_cierres enable row level security;
revoke all on redes.reporte_descargas, redes.reporte_descarga_cierres from public, anon, authenticated, service_role;
revoke all on sequence redes.reporte_descargas_id_seq from public, anon, authenticated, service_role;
