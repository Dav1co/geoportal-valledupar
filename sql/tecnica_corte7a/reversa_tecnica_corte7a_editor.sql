begin;
-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las 2 funciones de redes como las dejó el 6b, quita las RPC y funciones nuevas, las tablas y las vistas de químicos (el bucket, vacío, se queda), el candado de identidad y
-- el rol «auxiliar»; los estados del contrato vuelven a los del 6b. El hipoclorito de calcio se DESACTIVA (los químicos no se borran) y los parámetros se quedan.
-- SE NIEGA si ya hay movimientos, eventos de ficha que no sean los de la migración, archivos en el bucket o químicos «auxiliar» distintos del hipoclorito.
-- =====================================================================
do $$
begin
  if to_regclass('tecnica.quimico_movimientos') is null then raise exception 'No hay nada que revertir: no existe tecnica.quimico_movimientos'; end if;
  if exists (select 1 from tecnica.quimico_movimientos) or exists (select 1 from tecnica.quimico_ficha_eventos where autor <> 'migracion@tecnica_corte7a')
     or exists (select 1 from storage.objects where bucket_id = 'tecnica-evidencias')
     or exists (select 1 from tecnica.quimicos where rol = 'auxiliar' and codigo <> 'hipoclorito_calcio') then
    raise exception 'Ya hay movimientos, fichas, archivos o químicos nuevos: la reversa se niega (nada se borra)';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'f6c14c268aaedb5ab243f87685b428dd'
     or (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname, md5(pg_get_functiondef(p.oid))) in (('geoportal_tec_quimico_ajuste', '4ff08adcd3140c1da41827af1811727a'), ('geoportal_tec_quimico_crear', '851c1a8e7ba351bc3fb5d7fd53a2e8e0'), ('geoportal_tec_quimico_entrada', '9daf6b0ef659b44d30a9260b003e0a31'), ('geoportal_tec_quimico_ficha_preparar', '1a28c7a420f0ad7a2f064ebc401fa369'), ('geoportal_tec_quimico_fijar', '2026b1ec6e6752b368063609e3b1a60c'), ('geoportal_tec_quimico_historial', '9112d90a773971bacfb9d69310b2da89'), ('geoportal_tec_quimico_inventario', 'dc9ecbbbc7ae91e6a5fdb5653ebc59cb'), ('geoportal_tec_quimico_uso', '146290c07b0befb3aca05fdf350b34db'), ('geoportal_tec_quimicos_catalogo', '27c5a7644b003c62f06bf478772d1e57'), ('geoportal_tec_quimicos_comparacion', 'edbc5521095974d4f289e1d4f395f2b6'), ('geoportal_tec_quimicos_formulario', '443e5fa3f77b76d618e7e09131da4185'))) <> 11 then
    raise exception 'Las funciones cambiaron después de la migración del Corte 7a: la reversa se niega a pisarlas; avise';
  end if;
end $$;

-- 1. las funciones de redes reemplazadas, con su texto del 6b
CREATE OR REPLACE FUNCTION redes.f_estado_contrato(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select case when nullif(btrim(coalesce(p, '')), '') is null then 'sin_dato' when upper(btrim(p)) like 'RETIR%' then 'retirado'
              when upper(btrim(p)) like 'ACTIV%' then 'activo' else 'otro' end $function$;
revoke all on function redes.f_estado_contrato(text) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.geoportal_redes_contrato_tarjeta(p_solicitante text, p_contrato text, p_ip text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'bi_interno', 'pg_temp'
AS $function$
declare a record; c redes.contratos_capa%rowtype; cs record; pr record; f record; v_c text := btrim(coalesce(p_contrato, ''));
begin
  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if not a.completo then raise exception 'La tarjeta del contrato es para supervisores' using errcode = '42501'; end if;
  if v_c !~ '^[0-9]{1,12}$' then perform tecnica.f_error('Escriba solo los números del contrato'); end if;
  select * into c from redes.contratos_capa where contrato = v_c;
  if not found then perform tecnica.f_error('Ese contrato no está en la capa de contratos', 'P0002'); end if;
  select s.nombre, s.estado, s.categoria, s.direccion, s.barrio, s.periodo_carga into cs
    from public.cartera_suscripcion s where s.contrato = v_c order by s.periodo_carga desc nulls last limit 1;
  select cv.direccion, cv.barrio into pr from public.catastro_valledupar cv where cv.cod_usuario = v_c order by cv.id limit 1;
  select fc.periodo_ultimo, fc.uso, fc.consumo_meses, fc.cons_prom, fc.meses_con_lectura, fc.medidor_anios into f from bi_interno.ficha_contrato fc where fc.contrato = v_c;
  -- la lectura queda registrada: quién, cuándo y qué contrato (NUNCA el nombre ni la dirección)
  perform tecnica.f_auditar(a.email, 'redes_contrato_tarjeta', v_c, jsonb_build_object('datos', 'nombre, dirección y barrio', 'desde', 'geovisor'), p_ip);
  return jsonb_build_object(
    'contrato', v_c,
    'estado', c.estado, 'estado_texto', nullif(btrim(cs.estado), ''),
    'uso', c.uso,
    'consumo', case when f.periodo_ultimo is not null then jsonb_build_object(
        'periodo_ultimo', f.periodo_ultimo, 'promedio', f.cons_prom, 'meses_con_lectura', f.meses_con_lectura,
        'meses', (select coalesce(jsonb_agg(jsonb_build_object('periodo', m ->> 'periodo', 'm3', m -> 'm3', 'sin_dato', coalesce((m ->> 'sin_dato')::boolean, false),
                                                               'lectura_real', coalesce((m ->> 'lectura_real')::boolean, false)) order by k), '[]'::jsonb)
                    from jsonb_array_elements(f.consumo_meses) with ordinality x(m, k))) end,
    'medidor_anios', f.medidor_anios,
    'tramo', (select v.codigo from redes.contrato_tramo t join redes.activo_vigente_mat v on v.activo_id = t.activo_id where t.contrato = v_c),
    'suscriptor', jsonb_build_object(                                  -- DATO PERSONAL: solo en pantalla
      'nombre', nullif(btrim(cs.nombre), ''),
      'direccion', coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')),
      'barrio', coalesce(nullif(btrim(cs.barrio), ''), nullif(btrim(pr.barrio), ''))),
    'corte', cs.periodo_carga);
end $function$;
revoke all on function public.geoportal_redes_contrato_tarjeta(text,text,text) from public, anon, authenticated, service_role;
grant execute on function public.geoportal_redes_contrato_tarjeta(text,text,text) to service_role;

-- 2. lo nuevo
drop function geoportal_tec_quimicos_catalogo(text);
drop function geoportal_tec_quimico_historial(text,text);
drop function geoportal_tec_quimico_ficha_preparar(text);
drop function geoportal_tec_quimico_crear(text,text,text,boolean,numeric,text,text);
drop function geoportal_tec_quimico_fijar(text,text,jsonb,text,text);
drop function geoportal_tec_quimico_inventario(text,text,numeric,text,date,text);
drop function geoportal_tec_quimico_ajuste(text,text,numeric,text);
drop function geoportal_tec_quimicos_formulario(text,text);
drop function geoportal_tec_quimico_entrada(text,jsonb,text);
drop function geoportal_tec_quimico_uso(text,jsonb,text);
drop function geoportal_tec_quimicos_comparacion(text,date,date);
drop function tecnica.f_qparam(text);
drop function tecnica.f_quimico_por_codigo(text);
drop function tecnica.f_ficha_subida(text,text);
drop function tecnica.f_dosis_optima_en(bigint,timestamp with time zone);
drop function tecnica.f_dia_movimiento(date,numeric);
drop view tecnica.v_quimico_saldo;
drop view tecnica.v_quimico_vigente;
drop table tecnica.quimico_movimientos;
drop table tecnica.quimico_ficha_preparaciones;
drop table tecnica.quimico_ficha_eventos;
drop table tecnica.quimico_parametros;
-- el bucket tecnica-evidencias se queda (vacío y privado): Storage no deja borrar buckets por SQL; si se vuelve a migrar, se reutiliza
drop trigger t_quimico_identidad on tecnica.quimicos;
drop function tecnica.f_quimico_identidad();
update tecnica.quimicos set activo = false, rol = 'desinfectante' where codigo = 'hipoclorito_calcio';
alter table tecnica.quimicos drop constraint quimicos_rol_check;
alter table tecnica.quimicos add constraint quimicos_rol_check check (rol = any (array['coagulante', 'desinfectante', 'otro']));
update redes.contratos_capa set estado = 'otro' where estado in ('suspendido', 'cortado');
alter table redes.contratos_capa drop constraint contratos_capa_estado_check;
alter table redes.contratos_capa add constraint contratos_capa_estado_check check (estado in ('activo', 'retirado', 'otro', 'sin_dato'));

do $$
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> 'fca28bf695d1fcfa153f1113ce821528' then
    raise exception 'La reversa no dejó la base como en el 6b';
  end if;
end $$;
commit;
