#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 3b con las huellas reales de la base local:
  1) rehace redes_local con el 1a y el Corte 2 (lo publicado), toma la huella del Corte 2 y los textos de v_dano, v_epicrisis,
     preparar_dano y crear_dano (para la guardia y la reversa);
  2) escribe sql/10_esquema.sql (guardia) y los _editor de migración y ensayo;
  3) aplica la migración, toma las huellas del 3a y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py   (PostGIS local en localhost:55432)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
NUEVAS = ['geoportal_redes_perfil', 'geoportal_redes_galeria', 'geoportal_redes_ficha_editar', 'geoportal_redes_foto_perfil_preparar', 'geoportal_redes_foto_perfil_fijar']
CAMBIADAS = ['geoportal_redes_activo_buscar']
MIG = ['10_esquema.sql', '20_vistas.sql', '25_rpc.sql', '30_semilla.sql', '40_permisos.sql']


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


def md5s(nombres):
    filas = [l.split('|') for l in q("select proname || '|' || md5(pg_get_functiondef(oid)) from pg_proc where pronamespace = 'public'::regnamespace and proname in ("
                                     + ', '.join(f"'{n}'" for n in nombres) + ") order by 1").splitlines()]
    assert len(filas) == len(nombres), filas
    return dict(filas)


subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_3a'], env=ENV, check=True, capture_output=True)
md5_3a = q(CONJ)
vista = lambda v: q(f"select pg_get_viewdef('redes.{v}'::regclass, true)").rstrip().rstrip(';')  # noqa: E731
md5v = lambda v: q(f"select md5(pg_get_viewdef('redes.{v}'::regclass, true))")  # noqa: E731
v_epi_3a, m_epi_3a = vista('v_epicrisis'), md5v('v_epicrisis')
f_buscar_3a = q("select pg_get_functiondef('public.geoportal_redes_activo_buscar'::regproc)").rstrip()
cam_3a = md5s(CAMBIADAS)
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', {'{{MD5_CORTE_3A}}': md5_3a, '{{MD5_V_EPICRISIS_3A}}': m_epi_3a}))
escribir(os.path.join(RAIZ, 'migracion_redes_corte3b_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte3b_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
subprocess.run([PSQL, '-d', 'redes_local', '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte3b_editor.sql')], env=ENV, check=True, capture_output=True)
md5_3b = q(CONJ)
nue, cam_3b = md5s(NUEVAS), md5s(CAMBIADAS)
val = {'{{RPC_NUEVAS}}': ', '.join(f"('{n}', '{m}')" for n, m in sorted(nue.items())),
       '{{RPC_CAMBIADAS}}': ', '.join(f"('{n}', '{cam_3a[n]}', '{cam_3b[n]}')" for n in sorted(CAMBIADAS)),
       '{{RPC_TODAS_3B}}': ', '.join(f"('{n}', '{m}')" for n, m in sorted({**nue, **cam_3b}.items())),
       '{{MD5_CORTE_3A}}': md5_3a, '{{MD5_CORTE_3B}}': md5_3b, '{{MD5_V_EPICRISIS_3A}}': m_epi_3a, '{{MD5_V_EPICRISIS_3B}}': md5v('v_epicrisis'),
       '{{VISTA_EPICRISIS_3A}}': v_epi_3a, '{{FUNCION_ACTIVO_BUSCAR_3A}}': f_buscar_3a}
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, val))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte3b_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte3b_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte3b_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella corte 3a', md5_3a, '· huella corte 3b', md5_3b)
