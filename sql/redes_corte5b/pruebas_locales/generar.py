#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 5b con las huellas reales de la base local:
  1) rehace redes_local con lo del 5a y el doble de planta del 5b; toma sus huellas y el texto vivo de la función que cambia;
  2) escribe sql/25_reemplazos.sql (texto vivo con el cambio exacto, una sola vez), sql/10_esquema.sql (guardia) y los _editor de migración y ensayo;
  3) aplica la migración, toma las huellas del 5b y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py   (PostGIS local en localhost:55432)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
NUEVAS_RPC = ['geoportal_tec_puntos_mapa', 'geoportal_tec_punto_ubicacion_proponer', 'geoportal_tec_punto_ubicaciones', 'geoportal_tec_punto_ubicacion_revisar']
MIG = ['10_esquema.sql', '25_reemplazos.sql', '26_rpc.sql', '40_permisos.sql']

T = {}
# ---- capa MUE del 5a: una ubicación VERIFICADA (David o GPS del operador aprobado) no la pisa un archivo que la trae APROXIMADA
T['redes.f_candidatos_muestreo(bigint)'] = [(
    """                                else 'igual' end;""",
    """                                else 'igual' end;
  -- Corte 5b: una ubicación verificada (David o el GPS del operador aprobado en el Dashboard PTAP) no la pisa un archivo que la trae aproximada:
  -- se conserva la vigente («conserva_verificada» en el resumen). Un archivo con la ubicación verificada sí la cambia (es una corrección explícita).
  update _mue set lat = lat_vigente, lon = lon_vigente, exactitud = 'verificada',
                  accion = case when accion = 'ubicacion' then 'conserva_verificada' else accion end
   where exactitud_vigente = 'verificada' and exactitud = 'aproximada' and lat is not null and error is null;""")]
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

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_5a'], env=ENV, check=True, capture_output=True)
md5_5a = q(CONJ)
assert md5_5a == '5d104bb916ca0b055659c1b14902f519', md5_5a          # la huella del 5a que dice la bitácora
textos_5a = {f: fdef(f) for f in CAMBIADAS}
md5_cam_5a = {f: fmd5(f) for f in CAMBIADAS}

partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5b · 25 — REEMPLAZO (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- es el texto del 5a con un cambio exacto, aplicado una sola vez:
--   · redes.f_candidatos_muestreo (capa MUE): una ubicación verificada no la pisa un archivo que la trae aproximada («conserva_verificada»).
-- =====================================================================
"""]
for f in CAMBIADAS:
    t = textos_5a[f]
    for viejo, nuevo in T[f]:
        assert t.count(viejo) == 1, (f, viejo[:90], t.count(viejo))
        t = t.replace(viejo, nuevo)
    partes.append(f'\n-- {f}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))

v = {'{{MD5_CORTE_5A}}': md5_5a}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte5b_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte5b_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
subprocess.run([PSQL, '-d', 'redes_local', '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte5b_editor.sql')], env=ENV, check=True, capture_output=True)
md5_5b = q(CONJ)
md5_cam_5b = {f: fmd5(f) for f in CAMBIADAS}
nue = {n: q(f"select md5(pg_get_functiondef(oid)) from pg_proc where pronamespace = 'public'::regnamespace and proname = '{n}'") for n in NUEVAS_RPC}
firma_nueva = {n: q(f"select oid::regprocedure from pg_proc where pronamespace = 'public'::regnamespace and proname = '{n}'") for n in NUEVAS_RPC}
v.update({'{{MD5_CORTE_5B}}': md5_5b,
          '{{RPC_NUEVAS}}': ', '.join(f"('{n}', '{m}')" for n, m in sorted(nue.items())),
          '{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_cam_5a[f]}', '{md5_cam_5b[f]}')" for f in CAMBIADAS),
          '{{CAMBIADAS_5B}}': ', '.join(f"('{f}', '{md5_cam_5b[f]}')" for f in CAMBIADAS),
          '{{N_CAMBIADAS}}': str(len(CAMBIADAS)),
          '{{TEXTOS_5A}}': '\n'.join(f'{textos_5a[f]};\n' for f in CAMBIADAS),
          '{{DROPS}}': '\n'.join(f'drop function {firma_nueva[n]};' for n in NUEVAS_RPC)})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte5b_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte5b_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte5b_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella 5a', md5_5a, '· huella 5b', md5_5b)
