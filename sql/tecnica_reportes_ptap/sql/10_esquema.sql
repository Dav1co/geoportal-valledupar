-- =====================================================================
-- TÉCNICA · FASE 1 · REPORTES DEL PTAP (pestaña «Reportes» del Dashboard PTAP) · 10 — GUARDIA Y ESQUEMA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Encargo de David del 19-nov: cada formulario o ítem del PTAP tiene su propia descarga (Excel y CSV, el archivo lo arma el navegador).
-- · Solo AGREGA: 2 tablas (las descargas y sus cierres, solo inserción), funciones internas de lectura y 4 RPC. No reemplaza nada.
-- · Lee lo publicado: registros con su estado de exclusión (v_registros_estado), la referencia vigente (f_referencia_vigente) y la marca de rango
--   (f_marca_rango) de planta (Torre B), las revisiones, químicos (7a y 7c), la dosis de Entrada y los eventos de
--   suspensión de planta del Corte 15 (redes). Por eso exige la huella de redes publicada: b474fbbe3e0f7a3a7e6dbc04c53e02e7 (aviso por contrato) o, si ya se aplicaron las
--   descargas de Distribución, 3f3c89e603629d92e1cc5065de33d0c1. El esquema «tecnica» no tiene huella de conjunto publicada: se exige que exista lo que se lee
--   (tablas, columnas y funciones con su firma); el paso de huellas (05) imprime la huella de técnica para anotarla.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.reporte_descargas') is not null or to_regprocedure('public.geoportal_tec_reporte_iniciar(text,text,jsonb,text,boolean,text)') is not null then
    raise exception 'Los reportes del PTAP ya están aplicados: deténgase y avise';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
     not in ('b474fbbe3e0f7a3a7e6dbc04c53e02e7', '3f3c89e603629d92e1cc5065de33d0c1') then
    raise exception 'Las funciones de redes no son las publicadas (huella b474fbbe3e0f7a3a7e6dbc04c53e02e7): deténgase y avise';
  end if;
  if to_regclass('tecnica.v_registros_estado') is null or to_regclass('tecnica.revisiones_fuera_referencia') is null or to_regclass('tecnica.v_uso_quimicos_estado') is null
     or to_regclass('tecnica.quimico_movimientos') is null or to_regclass('tecnica.formulario_variables') is null or to_regclass('redes.v_evento_suspension') is null
     or to_regprocedure('tecnica.f_autorizar_supervision(text)') is null or to_regprocedure('tecnica.f_error(text,text)') is null
     or to_regprocedure('tecnica.f_auditar(text,text,text,jsonb,text)') is null or to_regprocedure('tecnica.f_formularios()') is null
     or to_regprocedure('tecnica.f_referencia_vigente(bigint,bigint,bigint)') is null or to_regprocedure('tecnica.f_marca_rango(numeric,numeric,numeric)') is null
     or to_regprocedure('tecnica.f_solo_agregar()') is null or to_regprocedure('redes.f_evento_reportes(bigint)') is null
     or to_regclass('redes.tipos_dano') is null or to_regclass('redes.causas') is null or to_regclass('redes.tipos_tercero') is null or to_regclass('redes.tipos_intervencion') is null then
    raise exception 'Faltan tablas o funciones de planta, de químicos, de los catálogos de daños o del Corte 15: deténgase y avise';
  end if;
  if (select count(*) from pg_attribute where not attisdropped and attnum > 0 and (
        (attrelid = 'tecnica.v_registros_estado'::regclass and attname in ('id', 'lote_id', 'formulario', 'variable_id', 'planta_id', 'punto_id', 'valor', 'fecha_muestra',
           'muestra_ts', 'registrado_en', 'autor', 'fuente', 'excluido'))
     or (attrelid = 'tecnica.quimico_movimientos'::regclass and attname in ('tipo', 'quimico_id', 'planta_id', 'para_que', 'cantidad', 'unidad', 'cantidad_kg', 'dia',
           'dosis_optima_ppm', 'proveedor', 'remision', 'lote_fabricante', 'vence', 'remision_foto', 'autor', 'registrado_en'))
     or (attrelid = 'tecnica.puntos'::regclass and attname in ('codigo', 'nombre', 'tipo', 'zona', 'numero_informe', 'planta_id'))
     or (attrelid = 'tecnica.variables'::regclass and attname in ('codigo', 'nombre', 'unidad', 'decimales', 'activa'))
     or (attrelid = 'redes.danos'::regclass and attname in ('id', 'codigo', 'tipo_codigo', 'causa_clase', 'causa_codigo', 'tercero_tipo'))
     or (attrelid = 'redes.intervenciones'::regclass and attname in ('id', 'codigo', 'dano_id', 'tipo_codigo')))) <> 13 + 16 + 6 + 5 + 6 + 4 then
    raise exception 'Las vistas o tablas de planta no tienen las columnas esperadas: deténgase y avise';
  end if;
end $$;

-- Una fila por descarga iniciada (quién, qué, con qué filtros y columnas, y el instante de la foto). Solo inserción.
create table tecnica.reporte_descargas (
  id         bigint generated always as identity primary key,
  email      text not null check (email = lower(email) and position('@' in email) > 1),
  reporte    text not null check (reporte ~ '^[a-z_]{3,30}$'),
  filtros    jsonb not null check (jsonb_typeof(filtros) = 'object'),
  incluir    boolean not null,
  formato    text not null check (formato in ('csv', 'xlsx')),
  columnas   jsonb not null check (jsonb_typeof(columnas) = 'array'),
  total      integer not null check (total >= 0),
  corte_en   timestamptz not null,
  ip         text,
  creado_en  timestamptz not null default clock_timestamp()
);
create index ix_tec_rep_descargas_email on tecnica.reporte_descargas (email, id desc);
-- El cierre de cada descarga (una sola vez). Solo inserción.
create table tecnica.reporte_descarga_cierres (
  descarga_id bigint primary key references tecnica.reporte_descargas (id),
  filas       integer not null check (filas >= 0),
  resultado   text not null check (resultado in ('completa', 'cancelada', 'error')),
  ip          text,
  creado_en   timestamptz not null default clock_timestamp()
);
create trigger t_solo_agregar before update or delete on tecnica.reporte_descargas for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.reporte_descargas for each statement execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar before update or delete on tecnica.reporte_descarga_cierres for each row execute function tecnica.f_solo_agregar();
create trigger t_solo_agregar_trunc before truncate on tecnica.reporte_descarga_cierres for each statement execute function tecnica.f_solo_agregar();
alter table tecnica.reporte_descargas enable row level security;
alter table tecnica.reporte_descarga_cierres enable row level security;
revoke all on tecnica.reporte_descargas, tecnica.reporte_descarga_cierres from public, anon, authenticated, service_role;
revoke all on sequence tecnica.reporte_descargas_id_seq from public, anon, authenticated, service_role;
