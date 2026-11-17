#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 9b, Fase 3 (capa «Flujo del agua (modelo)») con las huellas reales de la base local de Code A
(redes_local, 55432). Solo agrega: no hay reemplazos. Parte de la Fase 2 aplicada (huella 7f9c0157…).
Uso: python3 -I generar.py     Sobre otra huella: MD5_BASE=<huella> python3 -I generar.py"""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = 'redes_local'
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_BASE = os.environ.get('MD5_BASE', '7f9c0157c47e371e1d3d87ef6bda847b')      # la Fase 2 del 9b, que se publica antes
NUEVAS = ['redes.f_flujo_clase(numeric)', 'public.geoportal_redes_geovisor_mvt_flujo(text,text,integer,integer,integer)',
          'public.geoportal_redes_flujo_modelo(text)', 'public.geoportal_redes_flujo_tramo(text,text)']
MIG = ['10_esquema.sql', '20_funciones.sql', '40_permisos.sql']


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


subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=ENV, check=True, capture_output=True)
assert q(CONJ) == MD5_BASE, q(CONJ)
v = {'{{MD5_BASE}}': MD5_BASE}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte9b_f3_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte9b_f3_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
p = subprocess.run([PSQL, '-d', BASE, '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte9b_f3_editor.sql')], env=ENV, capture_output=True, text=True)
if p.returncode != 0:
    raise SystemExit(p.stderr[-3000:])
md5_f3 = q(CONJ)
v.update({'{{MD5_F3}}': md5_f3,
          '{{NUEVAS}}': ', '.join("('%s', '%s')" % (f, q(f"select md5(pg_get_functiondef('{f}'::regprocedure))")) for f in NUEVAS),
          '{{N_NUEVAS}}': str(len(NUEVAS)),
          '{{DROPS}}': '\n'.join(f'drop function {f};' for f in reversed(NUEVAS))})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte9b_f3_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte9b_f3_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte9b_f3_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella antes (Fase 2)', MD5_BASE, '· huella Fase 3', md5_f3)
