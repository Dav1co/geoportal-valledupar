#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 9a con las huellas reales de la base local de Code B (emdupar_b, puerto 55442):
  1) deja emdupar_b como producción (hasta el 7a); comprueba la huella y toma el texto vivo de las funciones que cambian y de la vista v_nodo_vigente;
  2) escribe sql/25_reemplazos.sql (texto vivo con cambios exactos, cada uno una sola vez; nodos_por_clasificar va entera), sql/10_esquema.sql y los _editor;
  3) aplica la migración, toma las huellas del 9a y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py     Para regenerar sobre otra huella de producción: MD5_BASE=<huella> python3 -I generar.py (con la plantilla rehecha)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = os.environ.get('BASE_B', 'emdupar_b')
ENV = dict(os.environ, PGHOST='localhost', PGPORT=os.environ.get('PGPORT_B', '55442'), PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
assert ENV['PGPORT'] != '55432', 'El puerto 55432 es de Code A'
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_BASE = os.environ.get('MD5_BASE', '79f184a4fe37ed2baa67dac7f3dd9b3c')      # producción desde la publicación del 7a (16-nov)
NUEVAS = ['redes.f_ref_vigente(text)', 'redes.f_sector_de(geometry)', 'redes.f_pm_nivel_presion(numeric)', 'redes.f_pm_sugerencia(text,text,text,text)', 'redes.f_nodo_modelo(text)',
          'redes.f_ficha_referencia(bigint)', 'redes.f_pm_marcar_por_verificar(text)',
          'public.geoportal_redes_geovisor_mvt_ref(text,text,integer,integer,integer)', 'public.geoportal_redes_referencia(text,text,text)',
          'public.geoportal_redes_nodo_preliminar(text,bigint)', 'public.geoportal_redes_nodo_clasificar(text,bigint,text,text)',
          'public.geoportal_redes_por_verificar(text,text,bigint,integer)', 'public.geoportal_redes_activo_verificar(text,text,text)']
MIG = ['10_esquema.sql', '20_funciones.sql', '26_rpc.sql', '25_reemplazos.sql', '40_permisos.sql']
SECTOR = "(select jsonb_build_object('sector', s.sector, 'subsector', s.subsector) from redes.f_sector_de(x.geom) s where s.sector is not null)"

T = {}
# ---- la ficha: el sector según el Plan (por geometría), los datos de referencia del Plan Maestro (tablas aparte) y el motivo de «por verificar»
T['redes.f_ficha(bigint,text)'] = [(
    """    'origen', v_origen,\n""",
    """    -- Corte 9a: nada de esto está en la ficha oficial; se lee de las tablas de referencia y de los polígonos vigentes de sectores
    'sector_plan', case when v.prefijo <> 'SEC' then (select jsonb_build_object('sector', s.sector, 'subsector', s.subsector, 'codigo', s.codigo, 'nombre', s.nombre)
                                                        from redes.f_sector_de(v.geom) s where s.sector is not null) end,
    'referencia', nullif(redes.f_ficha_referencia(p_activo), '[]'::jsonb),
    'por_verificar_motivo', case when v.por_verificar then (select e.motivo from redes.activo_eventos e where e.activo_id = p_activo and e.tipo = 'por_verificar' order by e.id desc limit 1) end,
    'origen', v_origen,\n""")]
# ---- la tesela del geovisor: el nombre de los sectores y de las instalaciones (pocos elementos), para su tarjeta
T['public.geoportal_redes_geovisor_mvt(text,integer,integer,integer)'] = [(
    """           m.estado_codigo as estado, m.punteado\n""",
    """           m.estado_codigo as estado, m.punteado,
           case when m.prefijo in ('SEC', 'TAN', 'PTA', 'CAP', 'DES', 'EBA', 'EBR', 'PTR') then m.nombre end as nombre\n""")]
# ---- el daño y la intervención: el «sector según Plan», calculado, al lado del sector que se escribe a mano (que se respeta)
T['public.geoportal_redes_danos(text,text,integer)'] = [(
    """'sector', x.sector_num, """, f"""'sector', x.sector_num, 'sector_plan', {SECTOR}, """)]
T['public.geoportal_redes_intervenciones(text,text,integer)'] = [(
    """             'recursos', x.recursos, """, f"""             'sector_plan', {SECTOR},
             'recursos', x.recursos, """)]
# ---- el contrato toma el sector de su tramo de acueducto
T['public.geoportal_redes_contrato_tarjeta(text,text,text)'] = [(
    """    'tramo', (select v.codigo from redes.contrato_tramo t join redes.activo_vigente_mat v on v.activo_id = t.activo_id where t.contrato = v_c),\n""",
    """    'tramo', (select v.codigo from redes.contrato_tramo t join redes.activo_vigente_mat v on v.activo_id = t.activo_id where t.contrato = v_c),
    'sector_plan', (select jsonb_build_object('sector', s.sector, 'subsector', s.subsector)      -- Corte 9a: el sector del contrato es el de su tramo (por geometría)
                      from redes.contrato_tramo t join redes.activo_vigente_mat v on v.activo_id = t.activo_id cross join lateral redes.f_sector_de(v.geom) s
                     where t.contrato = v_c and s.sector is not null),\n""")]
CAMBIADAS = list(T)
# ---- la bandeja de nodos por clasificar va ENTERA (misma firma): suma lo que dice el modelo y la sugerencia, y deja filtrar por ella
ENTERAS = {'public.geoportal_redes_nodos_por_clasificar(text,text,bigint,integer)': """CREATE OR REPLACE FUNCTION public.geoportal_redes_nodos_por_clasificar(p_solicitante text, p_buscar text DEFAULT NULL::text, p_despues_de bigint DEFAULT NULL::bigint, p_limite integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'redes', 'tecnica', 'extensions', 'pg_temp'
AS $function$
declare v_email text := redes.f_autorizar_admin(p_solicitante); v_q text := nullif(lower(btrim(coalesce(p_buscar, ''))), ''); v_lim integer := coalesce(p_limite, 50);
        v_acc text; v_r jsonb;
begin
  if v_lim < 1 or v_lim > 200 then perform tecnica.f_error('Se piden de 1 a 200'); end if;
  if v_q is not null and length(v_q) > 60 then perform tecnica.f_error('La búsqueda es demasiado larga'); end if;
  -- Corte 9a: «sugerencia:<acción>» en la búsqueda deja solo los nodos con esa sugerencia del modelo
  -- (los tramos que llegan a cada nodo se cuentan por los índices de tramo_nodos; la vista de tramos vigentes recorría todas las versiones en cada nodo)
  if v_q like 'sugerencia:%' then
    v_acc := substring(v_q from 12); v_q := null;
    if v_acc not in ('crear', 'no_crear', 'dejar_nodo', 'revisar', 'sin_modelo') then perform tecnica.f_error('Esa sugerencia no existe'); end if;
  end if;
  with base as (
    select n.nodo_id, n.sistema, n.llave_modelo, n.nombre_modelo, n.nombre_visible, n.geom, pm.tipo, pm.que_es,
           redes.f_pm_sugerencia(pm.tipo, pm.que_es, pm.nombre, pm.zona_modelo) as sug
      from redes.v_nodo_visible n
      left join redes.pm_nodos pm on n.sistema = 'acueducto' and pm.llave = n.llave_modelo and pm.carga_id = redes.f_ref_vigente('pm_nodos')
     where n.clase_nodo = 'por_clasificar'),
  fil as (
    select b.* from base b
     where (v_q is null or position(v_q in lower(coalesce(b.nombre_modelo, '') || ' ' || b.nombre_visible || ' ' || b.llave_modelo || ' ' || coalesce(b.que_es, ''))) > 0)
       and (v_acc is null or coalesce(b.sug ->> 'accion', 'sin_modelo') = v_acc)),
  pag as (select f.* from fil f where p_despues_de is null or f.nodo_id > p_despues_de order by f.nodo_id limit v_lim)
  select jsonb_build_object(
    'grupos', coalesce((select jsonb_agg(jsonb_build_object('grupo', g.grupo, 'n', g.n) order by g.n desc, g.grupo)
                          from (select coalesce(substring(b.nombre_modelo from '^[A-Za-zÁÉÍÓÚáéíóúñ]+'), '?') as grupo, count(*) as n from base b group by 1) g), '[]'::jsonb),
    'sugerencias', coalesce((select jsonb_agg(jsonb_build_object('accion', g.accion, 'n', g.n) order by g.n desc, g.accion)
                               from (select coalesce(b.sug ->> 'accion', 'sin_modelo') as accion, count(*) as n from base b group by 1) g), '[]'::jsonb),
    'total', (select count(*) from fil),
    'items', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('nodo_id', x.nodo_id, 'sistema', x.sistema, 'llave_modelo', x.llave_modelo, 'nombre_modelo', x.nombre_modelo,
                         'nombre_visible', x.nombre_visible, 'alias', case when x.nombre_visible is distinct from coalesce(x.nombre_modelo, x.llave_modelo) then x.nombre_visible end,
                         'lat', round(ST_Y(x.geom)::numeric, 6), 'lon', round(ST_X(x.geom)::numeric, 6),
                         'tramos', (select count(*) from redes.tramo_nodos t join redes.activo_vigente_mat m on m.activo_id = t.activo_id and m.version = t.version
                                    where t.nodo_ini = x.nodo_id or t.nodo_fin = x.nodo_id),
                         'tipo_modelo', x.tipo, 'que_es', nullif(x.que_es, 'otro'), 'sugerencia', x.sug)) order by x.nodo_id) from pag x), '[]'::jsonb),
    'tipos', coalesce((select jsonb_agg(jsonb_build_object('prefijo', t.prefijo, 'nombre', t.nombre_visible, 'sistema', t.sistema,
                         'pide_clase', exists (select 1 from jsonb_array_elements(t.campos) c where c ->> 'clave' = 'clase' and (c ->> 'obligatorio')::boolean),
                         'clases', coalesce((select jsonb_agg(jsonb_build_object('codigo', k.codigo, 'nombre', k.nombre) order by k.orden) from redes.clases_activo k where k.prefijo = t.prefijo and k.activo), '[]'::jsonb))
                         order by t.sistema, t.orden)
                         from redes.v_tipo_visible t where t.geometria = 'punto' and t.activo and t.sistema in ('acueducto', 'alcantarillado')), '[]'::jsonb)) into v_r;
  return v_r || jsonb_build_object('siguiente', case when jsonb_array_length(v_r -> 'items') = v_lim then (v_r -> 'items' -> (v_lim - 1) ->> 'nodo_id')::bigint end);
end $function$"""}
TODAS = CAMBIADAS + list(ENTERAS)


def q(sql):
    return subprocess.run([PSQL, '-d', BASE, '-AtX', '-c', sql], env=ENV, check=True, capture_output=True, text=True).stdout.strip()


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

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=ENV, check=True, capture_output=True)
assert q(CONJ) == MD5_BASE, q(CONJ)          # la huella de producción que dio Claude
antes = {f: fdef(f) for f in TODAS}
md5_antes = {f: fmd5(f) for f in TODAS}
vista_antes = q("select pg_get_viewdef('redes.v_nodo_vigente'::regclass)")
md5_vista = q("select md5(pg_get_viewdef('redes.v_nodo_vigente'::regclass))")

partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el del 7a publicado) con cambios exactos, aplicados una sola vez; nodos_por_clasificar va entera.
--   · redes.f_ficha: «sector_plan» (por geometría), «referencia» (lo del Plan Maestro, de sus tablas aparte) y «por_verificar_motivo»;
--   · geoportal_redes_geovisor_mvt: el nombre de los sectores y de las instalaciones, para su tarjeta;
--   · geoportal_redes_danos y geoportal_redes_intervenciones: «sector_plan», calculado, al lado del sector escrito a mano;
--   · geoportal_redes_contrato_tarjeta: «sector_plan», el del tramo del contrato;
--   · geoportal_redes_nodos_por_clasificar: lo que dice el modelo de cada nodo, la sugerencia y el filtro «sugerencia:<acción>».
-- ====================================================================="""]
for f in CAMBIADAS:
    t = antes[f]
    for viejo, nuevo in T[f]:
        assert t.count(viejo) == 1, (f, viejo[:90], t.count(viejo))
        t = t.replace(viejo, nuevo)
    partes.append(f'\n-- {f}\n{t};\n')
for f, t in ENTERAS.items():
    partes.append(f'\n-- {f}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))

v = {'{{MD5_BASE}}': MD5_BASE, '{{MD5_VISTA_NODO}}': md5_vista}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte9a_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte9a_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
p = subprocess.run([PSQL, '-d', BASE, '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte9a_editor.sql')], env=ENV, capture_output=True, text=True)
if p.returncode != 0:
    raise SystemExit(p.stderr[-3000:])
md5_9a = q(CONJ)
md5_despues = {f: fmd5(f) for f in TODAS}
md5_nuevas = {f: fmd5(f) for f in NUEVAS}
md5_vista_9a = q("select md5(pg_get_viewdef('redes.v_nodo_vigente'::regclass))")
v.update({'{{MD5_9A}}': md5_9a, '{{MD5_VISTA_NODO_9A}}': md5_vista_9a,
          '{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_antes[f]}', '{md5_despues[f]}')" for f in TODAS),
          '{{CAMBIADAS_9A}}': ', '.join(f"('{f}', '{md5_despues[f]}')" for f in TODAS),
          '{{N_CAMBIADAS}}': str(len(TODAS)),
          '{{NUEVAS}}': ', '.join(f"('{f}', '{md5_nuevas[f]}')" for f in NUEVAS),
          '{{N_NUEVAS}}': str(len(NUEVAS)),
          '{{DROPS}}': '\n'.join(f'drop function {f};' for f in reversed(NUEVAS)),
          '{{VISTA_NODO_ANTES}}': vista_antes.rstrip().rstrip(';'),
          '{{TEXTOS_ANTES}}': '\n'.join(f'{antes[f]};\nrevoke all on function {f} from public, anon, authenticated, service_role;\n'
                                        + (f'grant execute on function {f} to service_role;\n' if f.startswith('public.') else '') for f in TODAS)})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte9a_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte9a_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte9a_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella antes (7a, producción)', MD5_BASE, '· huella 9a', md5_9a)
