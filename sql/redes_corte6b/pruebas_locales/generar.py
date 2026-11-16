#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 6b con las huellas reales de la base local:
  1) rehace redes_local con lo del 6a (y los dobles de lo vivo que lee el 6b); toma sus huellas y el texto vivo de las funciones que cambian;
  2) escribe sql/25_reemplazos.sql (texto vivo con cambios exactos, cada uno una sola vez), sql/10_esquema.sql (guardia) y los _editor de migración y ensayo;
  3) aplica la migración, toma las huellas del 6b y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py   (PostGIS local en localhost:55432)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
NUEVAS_RPC = ['geoportal_redes_geovisor_mvt_contratos', 'geoportal_redes_contrato_tarjeta', 'geoportal_redes_vista_compartir', 'geoportal_redes_vista_abrir']
NUEVAS_INTERNAS = ['redes.f_estado_contrato(text)', 'redes.f_refrescar_contratos_capa()', 'redes.f_contratos_capa_al_dia()', 'redes.f_muestreo_calidad(bigint)']
MIG = ['10_esquema.sql', '26_rpc.sql', '25_reemplazos.sql', '40_permisos.sql']      # 26 antes que 25: los reemplazos llaman a las funciones nuevas
MD5_5C = '91a4d3e6e1c3539d8a447cb00a52d735'      # (nombre heredado: es la huella del 6a)

T = {}
# ---- 1. configuración: la capa de contratos al día (supervisores), su zoom, «compartir» y el estado de la capa; deja de ser STABLE (puede rehacer la capa)
T['public.geoportal_redes_geovisor(text)'] = [
    (""" STABLE SECURITY DEFINER""", """ SECURITY DEFINER"""),
    ("""  select * into a from redes.f_geovisor_acceso(p_solicitante);
  return jsonb_build_object(""", """  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if a.completo then perform redes.f_contratos_capa_al_dia(); end if;      -- Corte 6b: la capa de contratos se rehace sola si cambió la ficha o tiene más de un día
  return jsonb_build_object("""),
    ("""'nodos', redes.f_param('geovisor_zoom_nodos'), 'accesorios', redes.f_param('geovisor_zoom_acc')),""",
     """'nodos', redes.f_param('geovisor_zoom_nodos'), 'accesorios', redes.f_param('geovisor_zoom_acc'),
                               'contratos', redes.f_param('geovisor_zoom_contratos')),"""),
    ("""    'ficha', a.completo,""", """    'ficha', a.completo, 'compartir', a.completo,
    'contratos_capa', case when a.completo then (select jsonb_build_object('filas', e.filas, 'calculado_en', e.calculado_en) from redes.contratos_capa_estado e where e.id = 1) end,""")]
# ---- 2. capas por fecha: el color del muestreo (último resultado frente a los rangos) y la capa de reportes de Comercial (vacía hasta el Corte 8)
T['public.geoportal_redes_geovisor_capa(text,text,date,date)'] = [
    ("""'zona', p.zona, 'exactitud', u.exactitud)) as f, p.codigo as o""",
     """'zona', p.zona, 'exactitud', u.exactitud) || redes.f_muestreo_calidad(p.id)) as f, p.codigo as o"""),
    ("""  else
    perform tecnica.f_error('Esa capa todavía no tiene datos', 'P0002');""",
     """  elsif p_capa = 'reportes_comercial' then      -- Corte 6b (§30.4): la vista la llena el Corte 8; azul con contrato, rojo posible clandestino
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(r.lon, r.lat)),
               'properties', jsonb_build_object('codigo', r.codigo, 'tipo', r.tipo, 'subtipo', r.subtipo, 'area', r.area, 'con_contrato', coalesce(r.con_contrato, false),
                                                'estado', r.estado, 'cuando', r.registrado_en)) as f, r.registrado_en as o
        from redes.v_reportes_comercial r
       where r.registrado_en >= v_ini and r.registrado_en < v_fin and r.lat is not null
       order by r.registrado_en desc limit v_max + 1) x;
  else
    perform tecnica.f_error('Esa capa todavía no tiene datos', 'P0002');""")]

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

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_6a'], env=ENV, check=True, capture_output=True)
md5_5c = q(CONJ)
assert md5_5c == MD5_5C, md5_5c          # la huella del 6a que dice la bitácora
textos_5c = {f: fdef(f) for f in CAMBIADAS}
md5_cam_5c = {f: fmd5(f) for f in CAMBIADAS}

partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6b · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto del 6a con cambios exactos, aplicados una sola vez:
--   · geoportal_redes_geovisor: rehace la capa de contratos si hace falta (deja de ser STABLE), el zoom de contratos, «compartir» y el estado de la capa;
--   · geoportal_redes_geovisor_capa: el color del muestreo (último resultado frente a los rangos) y la capa de reportes de Comercial (vacía hasta el Corte 8).
-- ====================================================================="""]
for f in CAMBIADAS:
    t = textos_5c[f]
    for viejo, nuevo in T[f]:
        assert t.count(viejo) == 1, (f, viejo[:90], t.count(viejo))
        t = t.replace(viejo, nuevo)
    partes.append(f'\n-- {f}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))

v = {'{{MD5_CORTE_6A}}': md5_5c}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte6b_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte6b_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
subprocess.run([PSQL, '-d', 'redes_local', '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte6b_editor.sql')], env=ENV, check=True, capture_output=True)
md5_6a = q(CONJ)
md5_cam_6a = {f: fmd5(f) for f in CAMBIADAS}
nue = {n: q(f"select md5(pg_get_functiondef(oid)) from pg_proc where pronamespace = 'public'::regnamespace and proname = '{n}'") for n in NUEVAS_RPC}
firma_nueva = {n: q(f"select oid::regprocedure from pg_proc where pronamespace = 'public'::regnamespace and proname = '{n}'") for n in NUEVAS_RPC}
v.update({'{{MD5_CORTE_6B}}': md5_6a,
          '{{RPC_NUEVAS}}': ', '.join(f"('{n}', '{m}')" for n, m in sorted(nue.items())),
          '{{N_RPC}}': str(len(NUEVAS_RPC)),
          '{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_cam_5c[f]}', '{md5_cam_6a[f]}')" for f in CAMBIADAS),
          '{{CAMBIADAS_6B}}': ', '.join(f"('{f}', '{md5_cam_6a[f]}')" for f in CAMBIADAS),
          '{{N_CAMBIADAS}}': str(len(CAMBIADAS)),
          '{{TEXTOS_6A}}': '\n'.join(f'{textos_5c[f]};\nrevoke all on function {f} from public, anon, authenticated, service_role;\n'
                                     + (f'grant execute on function {f} to service_role;\n' if f.startswith('public.') else '') for f in CAMBIADAS),
          '{{DROPS}}': '\n'.join([f'drop function {firma_nueva[n]};' for n in NUEVAS_RPC] + [f'drop function {f};' for f in NUEVAS_INTERNAS])})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte6b_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte6b_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte6b_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella 6a', md5_5c, '· huella 6b', md5_6a)
