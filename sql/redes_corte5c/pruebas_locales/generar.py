#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 5c con las huellas reales de la base local:
  1) rehace redes_local con lo del 5b; toma sus huellas y el texto vivo de las funciones que cambian;
  2) escribe sql/25_reemplazos.sql (texto vivo con cambios exactos, cada uno una sola vez), sql/10_esquema.sql (guardia) y los _editor de migración y ensayo;
  3) aplica la migración, toma las huellas del 5c y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py   (PostGIS local en localhost:55432)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
NUEVAS_RPC = ['geoportal_redes_cargue_capas', 'geoportal_redes_cargue_historial', 'geoportal_redes_cargue_iniciar', 'geoportal_redes_carga_muestra',
              'geoportal_redes_carga_devolver_campo', 'geoportal_tec_punto_ubicacion_corregir']
NUEVAS_INTERNAS = ['redes.f_cruzar_por_geometria(bigint)']
MIG = ['10_esquema.sql', '25_reemplazos.sql', '26_rpc.sql', '40_permisos.sql']

T = {}
# ---- 1. reproyección: EPSG 9377 (MAGNA-SIRGAS Origen Nacional) no viene en todos los PostGIS (el local no lo trae); el punto suelto como multipunto
T['redes.f_geo_desde_wkt(text,integer)'] = [(
    """    if p_srid <> 4326 then g := ST_Transform(g, 4326); end if;""",
    """    if p_srid = 9377 and not exists (select 1 from spatial_ref_sys where srid = 9377) then
      -- Corte 5c: MAGNA-SIRGAS Origen Nacional (EPSG 9377, Resolución IGAC 471 de 2020) no viene en todos los PostGIS: se reproyecta con su definición
      g := ST_Transform(ST_SetSRID(g, 0), '+proj=tmerc +lat_0=4 +lon_0=-73 +k=0.9992 +x_0=5000000 +y_0=2000000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs', 4326);
    elsif p_srid <> 4326 then g := ST_Transform(g, 4326); end if;"""), (
    """  if ST_IsEmpty(g) then error := 'La geometría está vacía'; return; end if;""",
    """  if ST_IsEmpty(g) then error := 'La geometría está vacía'; return; end if;
  if GeometryType(g) = 'MULTIPOINT' and ST_NumGeometries(g) = 1 then g := ST_GeometryN(g, 1); end if;      -- Corte 5c: SHP y GeoPackage guardan a veces el punto así""")]

# ---- 2. lector GENÉRICO para las capas de un solo tipo (acometidas y las capas nuevas del Cargue)
T['redes.f_candidatos(bigint)'] = [(
    """  else
    perform tecnica.f_error(format('La capa %s no tiene todavía su lector en el motor (llega con el Cargue de capas, Corte 5)', v_capa));
  end if;""",
    """  elsif v_capa <> 'muestreo' and (select x.prefijo from redes.capas x where x.codigo = v_capa) is not null then
    -- Corte 5c: lector GENÉRICO de las capas de un solo tipo (acometidas y las del Cargue de capas). Columnas que reconoce, sin importar mayúsculas:
    -- NOMBRE, CLASE (si existe para el tipo), MATERIAL, DIAMETRO o DIAMETRO_MM (mm), ESTADO, PROFUNDIDAD o PROFUNDIDAD_M (m), CAPACIDAD y CODIGO_ANTERIOR.
    -- Lo demás va a atributos.modelo. Lo que no cabe en la ficha (clase que no existe, número fuera de rango) se guarda en atributos y no se inventa.
    return query
    with f as (select cf.orden, cf.llave, cf.geom, cf.atributos as crudo,
                      coalesce((select jsonb_object_agg(lower(e.key), e.value) from jsonb_each(cf.atributos) e), '{}'::jsonb) as a
                 from redes.carga_filas cf where cf.carga_id = p_carga and cf.error is null),
         t as (select x.prefijo from redes.capas x where x.codigo = v_capa),
         g as (select f.*, t.prefijo,
                      (select c.codigo from redes.clases_activo c where c.prefijo = t.prefijo and c.activo
                          and (c.codigo = redes.f_norm(f.a ->> 'clase') or redes.f_norm(c.nombre) = redes.f_norm(f.a ->> 'clase'))) as clase_ok,
                      redes.f_num(coalesce(f.a -> 'diametro_mm', f.a -> 'diametro')) as dia,
                      redes.f_num(coalesce(f.a -> 'profundidad_m', f.a -> 'profundidad')) as prof,
                      redes.f_num(f.a -> 'capacidad') as cap
                 from f cross join t)
    select v_capa, g.llave, g.orden, g.prefijo, g.geom,
           left(nullif(btrim(g.a ->> 'nombre'), ''), 120), g.clase_ok, null::text,
           (select e.material_codigo from redes.material_equivalencias e where e.texto_norm = redes.f_norm(g.a ->> 'material')),
           nullif(btrim(g.a ->> 'material'), ''),
           case when g.dia between 0 and 5000 then g.dia end,
           case when ST_Dimension(g.geom) = 1 then round(ST_Length(g.geom::geography)::numeric, 2) end,
           case when g.prof >= 0 then g.prof end, case when g.cap >= 0 then g.cap end,
           coalesce((select s.codigo from redes.estados_activo s where s.codigo = redes.f_norm(g.a ->> 'estado') or redes.f_norm(s.nombre) = redes.f_norm(g.a ->> 'estado')),
                    case when nullif(btrim(g.a ->> 'estado'), '') is null then 'en_operacion' else redes.f_estado_alcantarillado(g.a ->> 'estado') end),      -- «Existente», «Proyectado»…
           'emdupar'::text, null::text, left(coalesce(nullif(btrim(g.a ->> 'codigo_anterior'), ''), g.llave), 120),
           jsonb_strip_nulls(jsonb_build_object(
             'estado_capa', g.a ->> 'estado',
             'clase_capa', case when g.clase_ok is null then nullif(btrim(g.a ->> 'clase'), '') end,
             'diametro_capa', case when g.dia is not null and not (g.dia between 0 and 5000) then g.dia end,
             'modelo', nullif((select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) from jsonb_each(g.crudo) e
                                where lower(e.key) not in ('nombre', 'clase', 'material', 'diametro', 'diametro_mm', 'estado', 'profundidad', 'profundidad_m', 'capacidad', 'codigo_anterior')),
                             '{}'::jsonb))),
           null::integer, true, false, null::text, null::text, null::text, null::numeric, null::text, null::text, null::integer
      from g;
  else
    perform tecnica.f_error(format('La capa %s no tiene lector en el motor', v_capa));
  end if;""")]

# ---- 3. cruce por geometría (D-4) cuando la carga va «sin columna llave»
T['redes.f_preparar_candidatos(bigint)'] = [(
    """  -- cruce con lo vigente por (capa, llave) (D-2: nunca por el id de public.redes_*)""",
    """  -- Corte 5c (D-4): una carga «sin columna llave» se cruza por GEOMETRÍA con lo vigente de la misma capa y el mismo tipo (redes.f_cruzar_por_geometria):
  -- lo cruzado toma la llave del vigente y lo demás queda «nuevo», con una llave propia. Después sigue el cruce por llave de siempre.
  if (select x.columna_llave from redes.cargas x where x.id = p_carga) = '(geometria)' then perform redes.f_cruzar_por_geometria(p_carga); end if;
  -- cruce con lo vigente por (capa, llave) (D-2: nunca por el id de public.redes_*)""")]

# ---- 4. resumen: «sin columna llave», el resultado del cruce y la geometría que no corresponde al tipo
T['redes.f_resumen(bigint)'] = [(
    """  if v_nulas > 0 then v_bloq := v_bloq || format('%s filas sin llave (%s)', v_nulas, c.columna_llave); end if;""",
    """  if v_nulas > 0 and c.columna_llave <> '(geometria)' then v_bloq := v_bloq || format('%s filas sin llave (%s)', v_nulas, c.columna_llave); end if;      -- Corte 5c: sin llave = por geometría"""), (
    """'%s llaves repetidas en %s: el cruce por geometría (D-4) llega con el Cargue de capas'""",
    """'%s llaves repetidas en %s: elija otra columna llave o cargue «sin columna llave» (cruce por geometría, D-4)'"""), (
    """    if v_sinmat > 0 then""",
    """    -- Corte 5c: el cruce por geometría (D-4) y la geometría que no corresponde al tipo de la capa
    if c.columna_llave = '(geometria)' then
      v_extra := v_extra || jsonb_build_object('cruce_por_geometria', jsonb_build_object('tolerancia_m', redes.f_param('cruce_geometria_tol_m'),
        'cruzados', (select count(*) from _cand where crea_activo and llave not like 'G' || p_carga || '-%'),
        'sin_par_nuevos', (select count(*) from _cand where crea_activo and llave like 'G' || p_carga || '-%')));
    end if;
    if exists (select 1 from _cand k join redes.tipos_activo t on t.prefijo = k.prefijo where k.crea_activo
                  and not ((t.geometria = 'punto' and GeometryType(k.geom) = 'POINT') or (t.geometria = 'linea' and GeometryType(k.geom) in ('LINESTRING', 'MULTILINESTRING'))
                           or (t.geometria = 'poligono' and GeometryType(k.geom) in ('POLYGON', 'MULTIPOLYGON')))) then
      v_bloq := v_bloq || format('%s filas con una geometría que no es la del tipo (%s): revise el archivo o la capa elegida',
        (select count(*) from _cand k join redes.tipos_activo t on t.prefijo = k.prefijo where k.crea_activo
            and not ((t.geometria = 'punto' and GeometryType(k.geom) = 'POINT') or (t.geometria = 'linea' and GeometryType(k.geom) in ('LINESTRING', 'MULTILINESTRING'))
                     or (t.geometria = 'poligono' and GeometryType(k.geom) in ('POLYGON', 'MULTIPOLYGON')))),
        (select string_agg(distinct t.geometria, ', ') from _cand k join redes.tipos_activo t on t.prefijo = k.prefijo where k.crea_activo));
    end if;
    if exists (select 1 from _cand where crea_activo and pg_column_size(atributos) > 16000) then
      v_bloq := v_bloq || format('%s filas con demasiados atributos (más de 16 KB): quite columnas del archivo', (select count(*) from _cand where crea_activo and pg_column_size(atributos) > 16000));
    end if;
    if v_sinmat > 0 then""")]

# ---- 5. «gana la ficha» (5a) con «Devolver este campo a la capa» (§31.1)
T['redes.f_fusionar_ficha()'] = [(
    """           where x ->> 'campo' not in ('alias', 'placa') group by e.activo_id) f""",
    """           where x ->> 'campo' not in ('alias', 'placa')
             -- Corte 5c (§31.1): un campo «devuelto a la capa» deja de ser de la ficha, hasta que alguien lo vuelva a editar en la ficha
             and not exists (select 1 from redes.ficha_campo_devoluciones d where d.activo_id = e.activo_id and d.campo = x ->> 'campo' and d.creado_en > e.creado_en)
           group by e.activo_id) f""")]

T['redes.f_fusionar_ficha()'].append((
    """  update _cand k set accion = case when k.huella_vigente = k.huella then case when k.retirado_vigente then 'reactivar' else 'igual' end else 'cambiado' end
   where k.accion in ('cambiado', 'igual', 'reactivar');""",
    """  -- Corte 5c: también es «igual» lo que trae los mismos valores escritos de otra forma (130 y 130.0, según el programa que exportó el archivo):
  -- la misma geometría (binaria) y los mismos campos por valor (igualdad de jsonb). Así una recarga desde la pantalla no crea versiones sin cambios.
  alter table _cand add column mismo_valor boolean not null default false;
  update _cand k set mismo_valor = true
    from redes.v_activo_vigente v
   where v.activo_id = k.activo_id and k.accion in ('cambiado', 'igual', 'reactivar') and k.huella is distinct from k.huella_vigente
     and ST_AsEWKB(v.geom) = ST_AsEWKB(k.geom)
     and jsonb_build_object('p', v.prefijo, 'n', v.nombre, 'c', v.clase, 'e', v.efecto, 'm', v.material_codigo, 'd', v.diametro_mm, 'l', v.longitud_m, 'pr', v.profundidad_m,
                            'ca', v.capacidad, 's', v.estado_codigo, 'ant', v.codigo_anterior, 'a', v.atributos)
       = jsonb_build_object('p', k.prefijo, 'n', k.nombre, 'c', k.clase, 'e', k.efecto, 'm', k.material_codigo, 'd', k.diametro_mm, 'l', k.longitud_m, 'pr', k.profundidad_m,
                            'ca', k.capacidad, 's', k.estado_codigo, 'ant', k.codigo_anterior, 'a', k.atributos);
  update _cand k set accion = case when k.huella_vigente = k.huella or k.mismo_valor then case when k.retirado_vigente then 'reactivar' else 'igual' end else 'cambiado' end
   where k.accion in ('cambiado', 'igual', 'reactivar');"""))

# ---- 6. carga masiva: la marca su RPC en la transacción (como el envoltorio de D-14); psql no la pone
T['redes.f_iniciar(text,text,text,integer,text,integer,text,text)'] = [(
    """  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor)""",
    """  insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor, masiva_id)"""), (
    """  values (p_capa, p_sha256, p_formato, p_srid, btrim(p_columna_llave), p_filas, nullif(btrim(coalesce(p_nota, '')), ''), p_autor)""",
    """  values (p_capa, p_sha256, p_formato, p_srid, btrim(p_columna_llave), p_filas, nullif(btrim(coalesce(p_nota, '')), ''), p_autor,
          nullif(current_setting('redes.masiva_id', true), '')::uuid)      -- Corte 5c: la pone geoportal_redes_cargue_iniciar en una carga masiva""")]

# ---- 7. planta (5b): el administrador SÍ puede aprobar la ubicación que tomó (§32.1); el supervisor sigue sin poder
T['public.geoportal_tec_punto_ubicacion_revisar(text,bigint,text,text,text)'] = [(
    """  if x.autor = v_email then perform tecnica.f_error(""",
    """  if x.autor = v_email and not public.geoportal_es_admin(v_email) then perform tecnica.f_error(      -- Corte 5c (§32.1): el administrador sí puede
                                                                      """)]
T['public.geoportal_tec_punto_ubicaciones(text)'] = [(
    """declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); v_aviso numeric := redes.f_param('mue_gps_distancia_aviso_m');""",
    """declare v_email text := tecnica.f_autorizar_supervision(p_solicitante); v_aviso numeric := redes.f_param('mue_gps_distancia_aviso_m');
        v_admin boolean := public.geoportal_es_admin(v_email);      -- Corte 5c (§32.1)"""), (
    """    'precision_max_m', redes.f_param('mue_gps_precision_max_m'), 'distancia_aviso_m', v_aviso,""",
    """    'precision_max_m', redes.f_param('mue_gps_precision_max_m'), 'distancia_aviso_m', v_aviso, 'soy_admin', v_admin,"""), (
    """'creado_en', x.creado_en, 'propia', x.autor = v_email,""",
    """'creado_en', x.creado_en, 'propia', x.autor = v_email, 'puede_revisar', x.autor <> v_email or v_admin,"""), (
    """         where x.estado <> 'pendiente' order by x.revisada_en desc limit 50) z), '[]'::jsonb));""",
    """         where x.estado <> 'pendiente' order by x.revisada_en desc limit 50) z), '[]'::jsonb),
    -- Corte 5c (§32.2): las últimas correcciones de una ubicación verificada, con su motivo
    'correcciones', coalesce((
      select jsonb_agg(r order by (r ->> 'id')::bigint desc) from (
        select jsonb_build_object('id', c.id, 'punto', p.codigo, 'nombre', p.nombre, 'metodo', c.metodo, 'distancia_m', c.distancia_m, 'motivo', c.motivo,
                                  'autor', c.autor, 'creado_en', c.creado_en) as r
          from tecnica.punto_ubicacion_correcciones c join tecnica.puntos p on p.id = c.punto_id order by c.id desc limit 50) z), '[]'::jsonb));""")]
CAMBIADAS = list(T)


def q(sql):
    return subprocess.run([PSQL, '-d', 'redes_local', '-AtX', '-c', sql], env=ENV, check=True, capture_output=True, text=True).stdout.strip()


def leer(n):
    return open(os.path.join(RAIZ, 'sql', n), encoding='utf-8').read()


def escribir(ruta, texto):
    open(ruta, 'w', encoding='utf-8').write(texto)


def plantilla(nombre, val):
    t = open(os.path.join(AQUI, 'plantillas', nombre), encoding='utf-8').read()
    for k, v in val.items():
        t = t.replace(k, v)
    assert '{{' not in t, nombre
    return t


fdef = lambda f: q(f"select pg_get_functiondef('{f}'::regprocedure)").rstrip()  # noqa: E731
fmd5 = lambda f: q(f"select md5(pg_get_functiondef('{f}'::regprocedure))")  # noqa: E731

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_5b'], env=ENV, check=True, capture_output=True)
md5_5b = q(CONJ)
assert md5_5b == 'cbff4ee6e25826251d90496c833ac3de', md5_5b          # la huella del 5b que dice la bitácora
textos_5b = {f: fdef(f) for f in CAMBIADAS}
md5_cam_5b = {f: fmd5(f) for f in CAMBIADAS}
PLANTA = [f for f in CAMBIADAS if f.startswith('public.geoportal_tec_')]

partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5c · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto del 5b con cambios exactos, aplicados una sola vez:
--   · redes.f_geo_desde_wkt: EPSG 9377 con su definición cuando el PostGIS no lo trae; el punto suelto que viene como multipunto;
--   · redes.f_candidatos: lector genérico de las capas de un solo tipo (acometidas y las capas nuevas);
--   · redes.f_preparar_candidatos: cruce por geometría (D-4) de una carga sin columna llave;
--   · redes.f_resumen: «sin columna llave», el resultado del cruce, la geometría que no es la del tipo y los atributos demasiado grandes;
--   · redes.f_fusionar_ficha: «Devolver este campo a la capa» (§31.1);
--   · redes.f_iniciar: la marca de la carga masiva;
--   · public.geoportal_tec_punto_ubicacion_revisar y _ubicaciones (planta, 5b): el administrador aprueba lo suyo (§32.1) y la lista de correcciones (§32.2).
-- =====================================================================
"""]
for f in CAMBIADAS:
    t = textos_5b[f]
    for viejo, nuevo in T[f]:
        assert t.count(viejo) == 1, (f, viejo[:90], t.count(viejo))
        t = t.replace(viejo, nuevo)
    partes.append(f'\n-- {f}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))

v = {'{{MD5_CORTE_5B}}': md5_5b, '{{PLANTA_5B}}': ', '.join(f"('{f}', '{md5_cam_5b[f]}')" for f in PLANTA)}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte5c_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte5c_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
subprocess.run([PSQL, '-d', 'redes_local', '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte5c_editor.sql')], env=ENV, check=True, capture_output=True)
md5_5c = q(CONJ)
md5_cam_5c = {f: fmd5(f) for f in CAMBIADAS}
nue = {n: q(f"select md5(pg_get_functiondef(oid)) from pg_proc where pronamespace = 'public'::regnamespace and proname = '{n}'") for n in NUEVAS_RPC}
firma_nueva = {n: q(f"select oid::regprocedure from pg_proc where pronamespace = 'public'::regnamespace and proname = '{n}'") for n in NUEVAS_RPC}
v.update({'{{MD5_CORTE_5C}}': md5_5c,
          '{{RPC_NUEVAS}}': ', '.join(f"('{n}', '{m}')" for n, m in sorted(nue.items())),
          '{{N_RPC}}': str(len(NUEVAS_RPC)),
          '{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_cam_5b[f]}', '{md5_cam_5c[f]}')" for f in CAMBIADAS),
          '{{CAMBIADAS_5C}}': ', '.join(f"('{f}', '{md5_cam_5c[f]}')" for f in CAMBIADAS),
          '{{N_CAMBIADAS}}': str(len(CAMBIADAS)),
          '{{TEXTOS_5B}}': '\n'.join(f'{textos_5b[f]};\nrevoke all on function {f} from public, anon, authenticated, service_role;\n'
                                     + (f'grant execute on function {f} to service_role;\n' if f.startswith('public.') else '') for f in CAMBIADAS),
          '{{DROPS}}': '\n'.join([f'drop function {firma_nueva[n]};' for n in NUEVAS_RPC] + [f'drop function {f};' for f in NUEVAS_INTERNAS])})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte5c_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte5c_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte5c_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella 5b', md5_5b, '· huella 5c', md5_5c)
