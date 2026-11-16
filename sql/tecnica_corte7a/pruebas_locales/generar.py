#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 7a con las huellas reales de la base local:
  1) rehace redes_local con lo del 6b (y el doble de planta del 7a); toma sus huellas y el texto vivo de las funciones que cambian;
  2) escribe sql/25_reemplazos.sql (texto vivo con cambios exactos, cada uno una sola vez), sql/10_esquema.sql (guardia) y los _editor de migración y ensayo;
  3) aplica la migración, toma las huellas del 7a y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py   (PostGIS local en localhost:55432)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
NUEVAS_RPC = ['geoportal_tec_quimicos_catalogo', 'geoportal_tec_quimico_historial', 'geoportal_tec_quimico_ficha_preparar', 'geoportal_tec_quimico_crear', 'geoportal_tec_quimico_fijar',
              'geoportal_tec_quimico_inventario', 'geoportal_tec_quimico_ajuste', 'geoportal_tec_quimicos_formulario', 'geoportal_tec_quimico_entrada', 'geoportal_tec_quimico_uso',
              'geoportal_tec_quimicos_comparacion']
NUEVAS_INTERNAS = ['tecnica.f_qparam(text)', 'tecnica.f_quimico_por_codigo(text)', 'tecnica.f_ficha_subida(text,text)', 'tecnica.f_dosis_optima_en(bigint,timestamp with time zone)',
                   'tecnica.f_dia_movimiento(date,numeric)']      # f_quimico_identidad la borra la plantilla, después de su trigger
MIG = ['10_esquema.sql', '26_rpc.sql', '25_reemplazos.sql', '40_permisos.sql']      # 26 antes que 25: los reemplazos llaman a las funciones nuevas
MD5_5C = 'fca28bf695d1fcfa153f1113ce821528'      # (nombre heredado: es la huella del 6b)

T = {}
# ---- respuesta 2 de David al 6b: un color por estado del contrato (activo, suspendido, cortado, retirado, otro)
T['redes.f_estado_contrato(text)'] = [(
    """when upper(btrim(p)) like 'ACTIV%' then 'activo' else 'otro' end""",
    """when upper(btrim(p)) like 'ACTIV%' then 'activo'
              when upper(btrim(p)) like 'SUSP%' then 'suspendido' when upper(btrim(p)) like 'CORT%' then 'cortado' else 'otro' end""")]
# ---- respuesta 1 de David al 6b: nombre y dirección solo para el supervisor de distribución (Dashboard distribución, o área distribución o las dos en Personal)
#      y el administrador; el supervisor de planta ve la tarjeta sin ellos
T['public.geoportal_redes_contrato_tarjeta(text,text,text)'] = [
    ("""f record; v_c text := btrim(coalesce(p_contrato, ''));""", """f record; v_c text := btrim(coalesce(p_contrato, '')); v_personal boolean;"""),
    ("""  if not a.completo then raise exception 'La tarjeta del contrato es para supervisores' using errcode = '42501'; end if;""",
     """  if not a.completo then raise exception 'La tarjeta del contrato es para supervisores' using errcode = '42501'; end if;
  -- Corte 7a (respuesta 1 de David al 6b): nombre y dirección solo para el administrador y el supervisor de distribución (su permiso, o área distribución o las dos)
  v_personal := a.admin or public.geoportal_puede(a.email, 'dashboard_redes') or coalesce(redes.f_area(a.email) in ('distribucion', 'ambas'), false);"""),
    ("""jsonb_build_object('datos', 'nombre, dirección y barrio', 'desde', 'geovisor')""",
     """jsonb_build_object('datos', case when v_personal then 'nombre, dirección y barrio' else 'sin nombre ni dirección' end, 'desde', 'geovisor')"""),
    ("""      'nombre', nullif(btrim(cs.nombre), ''),
      'direccion', coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')),""",
     """      'nombre', case when v_personal then nullif(btrim(cs.nombre), '') end,
      'direccion', case when v_personal then coalesce(nullif(btrim(pr.direccion), ''), nullif(btrim(cs.direccion), '')) end,"""),
    ("""    'corte', cs.periodo_carga);""", """    'datos_personales', v_personal,
    'corte', cs.periodo_carga);""")]

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

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_6b'], env=ENV, check=True, capture_output=True)
md5_5c = q(CONJ)
assert md5_5c == MD5_5C, md5_5c          # la huella del 6b que dice la bitácora
textos_5c = {f: fdef(f) for f in CAMBIADAS}
md5_cam_5c = {f: fmd5(f) for f in CAMBIADAS}

partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7a · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto del 6b con cambios exactos, aplicados una sola vez (respuestas de David al 6b):
--   · redes.f_estado_contrato: suspendido y cortado como estados propios;
--   · geoportal_redes_contrato_tarjeta: nombre y dirección solo para el administrador y el supervisor de distribución; «datos_personales» en la respuesta.
-- ====================================================================="""]
for f in CAMBIADAS:
    t = textos_5c[f]
    for viejo, nuevo in T[f]:
        assert t.count(viejo) == 1, (f, viejo[:90], t.count(viejo))
        t = t.replace(viejo, nuevo)
    partes.append(f'\n-- {f}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))

v = {'{{MD5_CORTE_6B}}': md5_5c}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_tecnica_corte7a_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_tecnica_corte7a_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
subprocess.run([PSQL, '-d', 'redes_local', '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_tecnica_corte7a_editor.sql')], env=ENV, check=True, capture_output=True)
md5_6a = q(CONJ)
md5_cam_6a = {f: fmd5(f) for f in CAMBIADAS}
nue = {n: q(f"select md5(pg_get_functiondef(oid)) from pg_proc where pronamespace = 'public'::regnamespace and proname = '{n}'") for n in NUEVAS_RPC}
firma_nueva = {n: q(f"select oid::regprocedure from pg_proc where pronamespace = 'public'::regnamespace and proname = '{n}'") for n in NUEVAS_RPC}
v.update({'{{MD5_CORTE_7A}}': md5_6a,
          '{{RPC_NUEVAS}}': ', '.join(f"('{n}', '{m}')" for n, m in sorted(nue.items())),
          '{{N_RPC}}': str(len(NUEVAS_RPC)),
          '{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_cam_5c[f]}', '{md5_cam_6a[f]}')" for f in CAMBIADAS),
          '{{CAMBIADAS_7A}}': ', '.join(f"('{f}', '{md5_cam_6a[f]}')" for f in CAMBIADAS),
          '{{N_CAMBIADAS}}': str(len(CAMBIADAS)),
          '{{TEXTOS_6B}}': '\n'.join(f'{textos_5c[f]};\nrevoke all on function {f} from public, anon, authenticated, service_role;\n'
                                     + (f'grant execute on function {f} to service_role;\n' if f.startswith('public.') else '') for f in CAMBIADAS),
          '{{DROPS}}': '\n'.join([f'drop function {firma_nueva[n]};' for n in NUEVAS_RPC] + [f'drop function {f};' for f in NUEVAS_INTERNAS])})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_tecnica_corte7a_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_tecnica_corte7a_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_tecnica_corte7a_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella 6b', md5_5c, '· huella 7a', md5_6a)
