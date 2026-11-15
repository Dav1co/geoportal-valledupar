#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 2 con las huellas reales de la base local:
  1) rehace redes_local solo con el 1a, toma la huella del 1a y el texto de su v_epicrisis;
  2) escribe sql/10_esquema.sql (guardia con la huella del 1a) y los _editor de migración y ensayo;
  3) aplica la migración, toma las huellas del Corte 2 y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py   (PostGIS local en localhost:55432)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
NUEVAS = ['geoportal_redes_formulario_dano', 'geoportal_redes_preparar_dano', 'geoportal_redes_crear_dano', 'geoportal_redes_activo_buscar',
          'geoportal_redes_tramo_nodos', 'geoportal_redes_mvt', 'geoportal_redes_reporte_convertir', 'geoportal_redes_reporte_descartar']
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


subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_1a'], env=ENV, check=True, capture_output=True)
md5_1a = q(CONJ)
vista_1a = q("select pg_get_viewdef('redes.v_epicrisis'::regclass, true)").rstrip().rstrip(';')
md5_vista_1a = q("select md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true))")
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', {'{{MD5_CORTE_1A}}': md5_1a}))
escribir(os.path.join(RAIZ, 'migracion_redes_corte2_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte2_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
subprocess.run([PSQL, '-d', 'redes_local', '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte2_editor.sql')], env=ENV, check=True, capture_output=True)
md5_2 = q(CONJ)
rpc = [l.split('|') for l in q("select proname || '|' || md5(pg_get_functiondef(oid)) from pg_proc where pronamespace = 'public'::regnamespace and proname in ("
                                + ', '.join(f"'{n}'" for n in NUEVAS) + ") order by 1").splitlines()]
assert len(rpc) == 8, rpc
val = {'{{RPC_PARES}}': ', '.join(f"('{n}', '{m}')" for n, m in rpc), '{{RPC_FILAS}}': ', '.join(f"('{n}', '{m}')" for n, m in rpc),
       '{{MD5_CORTE_1A}}': md5_1a, '{{MD5_CORTE_2}}': md5_2, '{{VISTA_EPICRISIS_1A}}': vista_1a, '{{MD5_VISTA_1A}}': md5_vista_1a}
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, val))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte2_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte2_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte2_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella 1a', md5_1a, '· huella corte 2', md5_2)
