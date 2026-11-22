-- =====================================================================
-- TÉCNICA · PTAR (Code C) · PTAR-3 «Sistema de Control PTAR» · 10 — GUARDIA Y ESQUEMA. Va DESPUÉS de PTAR-1 (tecnica_ptar) y ANTES de la carga del mapa.
-- Pedido de David (21-nov, noche): la Caracterización se adelanta de PTAR-4.
--   · La clave de formulario ptar_caracterizacion (dominio y f_formularios, que se reescribe IGUAL a la publicada del Corte 8 + una fila).
--   · El tipo de punto «ptar» (CHECK de puntos y de formulario_variables) y cuatro puntos: PTAR-AFL, PTAR-EFL, PTAR-RIO-ARR y PTAR-RIO-ABJ.
--   · Variables: las de la Caracterización (caudal, DBO5, DQO, SST, nitrógeno y fósforo totales) y las de la sonda multiparámetro (pH, temperatura y OD; sin formulario
--     todavía: la ficha las muestra con «sin registros»). Referencias: ninguna («por definir»).
--   · Caracterización: por punto (tipo ptar), 7 días hacia atrás, ninguna obligatoria (el caudal es diario; los de laboratorio llegan después).
-- NO toca ninguna función ni tabla de redes. Afluente, Entre lagunas, Efluente y los puntos de laguna siguen en PTAR-4.
-- =====================================================================
do $$
declare v_redes text;
begin
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v_redes from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');
  if v_redes is distinct from '{{MD5_REDES}}' then
    raise exception 'GUARDIA PTAR-3: la huella de redes es % y se esperaba {{MD5_REDES}}. Deténgase y avise', v_redes;
  end if;
  if to_regclass('tecnica.elementos_planta') is null or to_regprocedure('public.geoportal_tec_ptar_mapa(text,text)') is null then
    raise exception 'GUARDIA PTAR-3: falta PTAR-1 (tecnica_ptar): aplíquelo antes';
  end if;
  if md5(pg_get_functiondef('tecnica.f_autorizar_supervision(text)'::regprocedure)) <> '{{MD5_AUT_SUP}}'
     or md5(pg_get_functiondef('public.geoportal_tec_ptar_mapa(text,text)'::regprocedure)) <> '{{MD5_PTAR_MAPA}}'
     or md5(pg_get_functiondef('public.geoportal_tec_ptar_elemento(text,text)'::regprocedure)) <> '{{MD5_PTAR_ELEMENTO}}' then
    raise exception 'GUARDIA PTAR-3: las funciones de PTAR-1 no son las esperadas. Deténgase y avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_formularios()'::regprocedure)) <> '{{MD5_FORMULARIOS}}' then
    raise exception 'GUARDIA PTAR-3: tecnica.f_formularios no es la publicada del Corte 8 (9 claves). Deténgase y avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_autorizar_captura(text,text)'::regprocedure)) <> '{{MD5_CAPTURA}}' then
    raise exception 'GUARDIA PTAR-3: tecnica.f_autorizar_captura no es la publicada. Deténgase y avise';
  end if;
  if md5(pg_get_functiondef('tecnica.f_tipo_punto_texto(text)'::regprocedure)) <> '{{MD5_TIPO_PUNTO}}' then
    raise exception 'GUARDIA PTAR-3: tecnica.f_tipo_punto_texto no es la publicada (Corte 3). Deténgase y avise';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck')
     <> 'CHECK ((VALUE = ANY (ARRAY[''entrada''::text, ''salida''::text, ''muestreo''::text, ''danos_fallas''::text, ''mantenimiento''::text, ''uso_quimicos''::text, ''entrada_quimicos''::text, ''anomalia_compartida''::text, ''revision_compartida''::text, ''activo_campo''::text])))' then
    raise exception 'GUARDIA PTAR-3: el dominio tecnica.formulario_clave no tiene las 10 claves esperadas (Corte 14). Deténgase y avise';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'tecnica.puntos'::regclass and c.conname = 'puntos_tipo_check')
       <> 'CHECK ((tipo = ANY (ARRAY[''macromedicion''::text, ''muestreo''::text, ''tanque''::text, ''distribucion''::text])))'
     or (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'tecnica.formulario_variables'::regclass and c.conname = 'formulario_variables_tipo_punto_check')
       <> 'CHECK ((tipo_punto = ANY (ARRAY[''macromedicion''::text, ''muestreo''::text, ''tanque''::text, ''distribucion''::text])))'
     or (select count(*) from pg_constraint c where c.conrelid = 'tecnica.puntos'::regclass and c.contype = 'c' and pg_get_constraintdef(c.oid) like '%tipo = ANY%') <> 1 then
    raise exception 'GUARDIA PTAR-3: los CHECK del tipo de punto no son los esperados (Corte 3). Deténgase y avise';
  end if;
  if exists (select 1 from tecnica.variables where codigo like 'ar\_%') or exists (select 1 from tecnica.puntos where codigo like 'PTAR-%')
     or exists (select 1 from tecnica.formularios_config where formulario::text = 'ptar_caracterizacion') then
    raise exception 'GUARDIA PTAR-3: ya hay variables ar_*, puntos PTAR-* o la Caracterización: el paquete parece aplicado';
  end if;
end $$;

-- ---------- 1. La clave del formulario (dominio y f_formularios) ----------
alter domain tecnica.formulario_clave drop constraint formulario_clave_ck;
alter domain tecnica.formulario_clave add constraint formulario_clave_ck check (value in
  ('entrada', 'salida', 'muestreo', 'danos_fallas', 'mantenimiento', 'uso_quimicos', 'entrada_quimicos', 'anomalia_compartida', 'revision_compartida', 'activo_campo', 'ptar_caracterizacion'));

CREATE OR REPLACE FUNCTION tecnica.f_formularios()
 RETURNS TABLE(clave text, nombre text, descripcion text, orden integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  values ('entrada',          'Entrada',                           'Agua cruda que ingresa a las plantas.', 1),
         ('salida',           'Salida',                            'Agua tratada que sale de las plantas.', 2),
         ('muestreo',         'Muestreo',                          'Muestreo en los puntos de la red y los tanques.', 3),
         ('danos_fallas',     'Daños o fallas',                    'Daños o fallas en la planta.', 4),
         ('mantenimiento',    'Mantenimiento, reparación e inversión', 'Mantenimiento, reparación e inversión.', 5),
         ('uso_quimicos',     'Uso de químicos',                   'Químicos usados en el proceso.', 6),
         ('entrada_quimicos', 'Entrada de químicos',               'Químicos que ingresan al almacén.', 7),
         ('anomalia_compartida', 'Reportar anomalía',               'El mismo reporte de anomalías de Comercial, hecho desde Técnica.', 8),
         ('revision_compartida', 'Revisiones generales',            'La misma revisión general de Comercial, hecha desde Técnica.', 9),
         ('ptar_caracterizacion', 'Caracterización',                'Caracterización del agua residual de la PTAR y del río Cesar.', 10);
$function$;

-- ---------- 2. El tipo de punto «ptar» ----------
alter table tecnica.puntos drop constraint puntos_tipo_check;
alter table tecnica.puntos add constraint puntos_tipo_check check (tipo in ('macromedicion', 'muestreo', 'tanque', 'distribucion', 'ptar'));
alter table tecnica.formulario_variables drop constraint formulario_variables_tipo_punto_check;
alter table tecnica.formulario_variables add constraint formulario_variables_tipo_punto_check check (tipo_punto in ('macromedicion', 'muestreo', 'tanque', 'distribucion', 'ptar'));

-- ---------- 3. Los cuatro puntos de la Caracterización (sin planta de agua potable; su lugar en el mapa es el elemento PTAR-PM-* del GeoJSON) ----------
insert into tecnica.puntos (codigo, nombre, tipo, planta_id) values
  ('PTAR-AFL',     'Afluente — llegada del alcantarillado', 'ptar', null),
  ('PTAR-EFL',     'Efluente — salida al río Cesar', 'ptar', null),
  ('PTAR-RIO-ARR', 'Río Cesar aguas arriba del vertimiento', 'ptar', null),
  ('PTAR-RIO-ABJ', 'Río Cesar aguas abajo del vertimiento', 'ptar', null);

-- ---------- 4. Variables (códigos propios ar_*: no heredan las referencias del agua potable) ----------
insert into tecnica.variables (codigo, nombre, unidad, categoria, decimales) values
  ('ar_caudal',          'Caudal',                      'L/s',            'caudal',        1),
  ('ar_dbo5',            'DBO5',                        'mg/L O2',        'fisicoquimico', 1),
  ('ar_dqo',             'DQO',                         'mg/L O2',        'fisicoquimico', 1),
  ('ar_sst',             'Sólidos suspendidos totales', 'mg/L',           'fisicoquimico', 1),
  ('ar_nitrogeno_total', 'Nitrógeno total',             'mg/L N',         'fisicoquimico', 2),
  ('ar_fosforo_total',   'Fósforo total',               'mg/L P',         'fisicoquimico', 2),
  ('ar_ph',              'pH',                          'unidades de pH', 'fisicoquimico', 2),
  ('ar_temperatura',     'Temperatura',                 '°C',             'fisicoquimico', 1),
  ('ar_od',              'Oxígeno disuelto',            'mg/L',           'fisicoquimico', 2);

-- ---------- 5. El formulario Caracterización: por punto (tipo ptar), ninguna obligatoria, 7 días hacia atrás ----------
insert into tecnica.formulario_variables (formulario, variable_id, orden, obligatoria, alcance, tipo_punto)
select 'ptar_caracterizacion', v.id, x.o, false, 'por_punto', 'ptar'
  from unnest(array['ar_caudal', 'ar_dbo5', 'ar_dqo', 'ar_sst', 'ar_nitrogeno_total', 'ar_fosforo_total']) with ordinality x(c, o)
  join tecnica.variables v on v.codigo = x.c;
insert into tecnica.formularios_config (formulario, dias_atras_max) values ('ptar_caracterizacion', 7);
