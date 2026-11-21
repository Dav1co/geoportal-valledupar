#!/usr/bin/env python3
"""Arma el paquete SQL de los reportes del PTAP con las huellas reales de la base local de Code A (redes_local, 55432).
Parte del aviso por contrato publicado (huella de redes b474fbbe…); acepta también la huella con las descargas de Distribución aplicadas.
Uso: python3 -I generar.py   (antes: python3 -I ../../redes_reportes_distribucion/pruebas_locales/generar.py, que deja huella_despues.txt)"""
import os
import subprocess
import sys

# Pasada de herramientas (20-nov): -h/--help imprime el uso y sale antes de tocar la base; no lleva opciones. Es local (55432): no consulta Supabase.
for _a in sys.argv[1:]:
    if _a in ('-h', '--help'):
        print(__doc__); sys.exit(0)
    print(f'Opción desconocida: {_a} (no lleva opciones; -h para el uso)', file=sys.stderr); sys.exit(2)

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = 'redes_local'
NOMBRE = 'tecnica_reportes_ptap'
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_BASE = os.environ.get('MD5_BASE', 'b474fbbe3e0f7a3a7e6dbc04c53e02e7')
MD5_REDES_DESPUES = open(os.path.join(RAIZ, '..', 'redes_reportes_distribucion', 'pruebas_locales', 'huella_despues.txt')).read().strip()
NOMBRES = ['f_rep_catalogo', 'f_rep_max_filas', 'f_rep_max_pagina', 'f_rep_ts', 'f_rep_col', 'f_rep_filtros', 'f_rep_cols_variables', 'f_rep_columnas', 'f_rep_valores', 'f_rep_envios_llaves', 'f_rep_envios_pagina', 'f_rep_envios',
           'f_rep_quimicos', 'f_rep_kardex', 'f_rep_eventos_planta', 'f_rep_fuera_referencia', 'f_rep_filas', 'f_rep_leame']
RPC = ['geoportal_tec_reporte_iniciar', 'geoportal_tec_reporte_pagina', 'geoportal_tec_reporte_cerrar', 'geoportal_tec_reporte_remision_foto']
NUEVAS_Q = ("select string_agg(p.oid::regprocedure::text, '|' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text) from pg_proc p "
            f"where (p.pronamespace = 'tecnica'::regnamespace and p.proname = any (array{NOMBRES})) or (p.pronamespace = 'public'::regnamespace and p.proname = any (array{RPC}))")
# la huella de técnica (informativa: no hay una publicada) — todo el esquema tecnica y las RPC geoportal_tec_*
CONJ_TEC = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
            "where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_tec\\_%'))")
MIG = ['10_esquema.sql', '20_funciones.sql', '26_rpc.sql', '40_permisos.sql']


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


def pares(firmas):
    return ', '.join("('%s', '%s')" % (f, q(f"select md5(pg_get_functiondef('{f}'::regprocedure))")) for f in firmas)


subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=ENV, check=True, capture_output=True)
assert q(CONJ) == MD5_BASE, q(CONJ)
assert q(NUEVAS_Q) == '', 'ya hay funciones con los nombres nuevos: ' + q(NUEVAS_Q)
v = {'{{MD5_BASE}}': MD5_BASE, '{{MD5_REDES_DESPUES}}': MD5_REDES_DESPUES}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, f'migracion_{NOMBRE}_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'sql', '70_pruebas.sql'), plantilla('70_pruebas.sql', v))
escribir(os.path.join(RAIZ, f'ensayo_en_transaccion_{NOMBRE}_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
tec_antes = q(CONJ_TEC)
p = subprocess.run([PSQL, '-d', BASE, '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, f'migracion_{NOMBRE}_editor.sql')], env=ENV, capture_output=True, text=True)
if p.returncode != 0:
    raise SystemExit(p.stderr[-3000:])
assert q(CONJ) == MD5_BASE, 'los reportes del PTAP no deben cambiar la huella de redes'
nuevas = q(NUEVAS_Q).split('|')
assert len(nuevas) == len(NOMBRES) + len(RPC), nuevas
v.update({'{{NUEVAS}}': pares(nuevas), '{{N_NUEVAS}}': str(len(nuevas)), '{{DROPS}}': '\n'.join(f'drop function {f};' for f in reversed(nuevas))})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, f'huellas_solo_lectura_{NOMBRE}_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, f'verificacion_{NOMBRE}_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, f'reversa_{NOMBRE}_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
tec_despues = q(CONJ_TEC)
subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=ENV, check=True, capture_output=True)
print('huella de redes (no cambia)', MD5_BASE, '· técnica local antes', tec_antes, 'después', tec_despues, '·', len(nuevas), 'funciones nuevas')
