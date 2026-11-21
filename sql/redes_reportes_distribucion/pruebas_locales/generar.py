#!/usr/bin/env python3
"""Arma el paquete SQL de las descargas de Distribución con las huellas reales de la base local de Code A (redes_local, 55432).
Parte del aviso por contrato publicado (huella b474fbbe…). Uso: python3 -I generar.py"""
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
NOMBRE = 'redes_reportes_distribucion'
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_BASE = os.environ.get('MD5_BASE', 'b474fbbe3e0f7a3a7e6dbc04c53e02e7')      # aviso por contrato, publicado el 19-nov (23:40)
NOMBRES = ['f_rep_catalogo', 'f_rep_max_filas', 'f_rep_ts', 'f_rep_col', 'f_rep_rotulo', 'f_rep_sector_geom', 'f_rep_sectores', 'f_rep_punto', 'f_rep_filtros', 'f_rep_columnas', 'f_rep_levantamientos', 'f_rep_valvulas', 'f_rep_eventos', 'f_rep_l116', 'f_rep_bot', 'f_rep_sensibles', 'f_rep_activos', 'f_rep_filas', 'f_rep_contar', 'f_rep_leame']
RPC = ['geoportal_redes_reporte_iniciar', 'geoportal_redes_reporte_pagina', 'geoportal_redes_reporte_cerrar', 'geoportal_redes_reporte_sectores']
# por NOMBRE EXACTO (un patrón «geoportal_redes_reporte_%» abarcaría también las publicadas reporte_convertir y reporte_descartar)
NUEVAS_Q = ("select string_agg(p.oid::regprocedure::text, '|' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text) from pg_proc p "
            f"where (p.pronamespace = 'redes'::regnamespace and p.proname = any (array{NOMBRES})) or (p.pronamespace = 'public'::regnamespace and p.proname = any (array{RPC}))")
# lo publicado que este paquete lee y NO toca (las huellas y la verificación lo comprueban)
PUBLICADAS = ['redes.f_supervisor(text,text)', 'redes.f_perfil_lectura(text)', 'redes.f_sector_de(geometry)', 'redes.f_evento_reportes(bigint)',
              'public.geoportal_redes_descarga(text,text,date,date,boolean,text)',
              'public.geoportal_redes_reporte_convertir(text,uuid,jsonb)', 'public.geoportal_redes_reporte_descartar(text,uuid,text)']
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
v = {'{{MD5_BASE}}': MD5_BASE, '{{PUBLICADAS}}': pares(PUBLICADAS), '{{N_PUBLICADAS}}': str(len(PUBLICADAS))}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, f'migracion_{NOMBRE}_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'sql', '70_pruebas.sql'), plantilla('70_pruebas.sql', v))
escribir(os.path.join(RAIZ, f'ensayo_en_transaccion_{NOMBRE}_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
p = subprocess.run([PSQL, '-d', BASE, '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, f'migracion_{NOMBRE}_editor.sql')], env=ENV, capture_output=True, text=True)
if p.returncode != 0:
    raise SystemExit(p.stderr[-3000:])
md5_dist = q(CONJ)
nuevas = q(NUEVAS_Q).split('|')
assert len(nuevas) == len(NOMBRES) + len(RPC), nuevas
v.update({'{{MD5_DIST}}': md5_dist, '{{NUEVAS}}': pares(nuevas), '{{N_NUEVAS}}': str(len(nuevas)),
          '{{DROPS}}': '\n'.join(f'drop function {f};' for f in reversed(nuevas))})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, f'huellas_solo_lectura_{NOMBRE}_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, f'verificacion_{NOMBRE}_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, f'reversa_{NOMBRE}_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
escribir(os.path.join(AQUI, 'huella_despues.txt'), md5_dist + '\n')
subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=ENV, check=True, capture_output=True)
print('huella antes (aviso por contrato)', MD5_BASE, '· huella con las descargas de Distribución', md5_dist, '·', len(nuevas), 'funciones nuevas')
