#!/usr/bin/env python3
"""Arma el paquete SQL del corte de EVENTOS (origen obligatorio y sectores por tubo de salida) con las huellas reales de la base local de Code A
(redes_local, 55432: producción al 20-nov 21:08, huella de redes 3f3c89e6…). Uso: python3 -I generar.py   (-h: este uso; local, no consulta Supabase)"""
import os
import subprocess
import sys

for _a in sys.argv[1:]:
    if _a in ('-h', '--help'):
        print(__doc__); sys.exit(0)
    print(f'Opción desconocida: {_a} (no lleva opciones; -h para el uso)', file=sys.stderr); sys.exit(2)

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = 'redes_local'
NOMBRE = 'redes_eventos_origen_tubos'
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
CONJ_TEC = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
            "where p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_tec\\_%')")
MD5_BASE = os.environ.get('MD5_BASE', '3f3c89e603629d92e1cc5065de33d0c1')      # reportes del PTAP y descargas de Distribución, publicados el 20-nov 21:08
# lo que se REEMPLAZA (la reversa deja su texto de antes)
REEMPLAZADAS = ['redes.f_evento_zona(jsonb)', 'public.geoportal_redes_evento_declarar(text,jsonb)', 'public.geoportal_redes_evento_catalogo(text)',
                'redes.f_evento_json(bigint,boolean)', 'public.geoportal_redes_planta_sectores_fijar(text,text,text[],text)',
                'redes.f_rep_columnas(text)', 'redes.f_rep_eventos(jsonb,boolean,timestamp with time zone,text,integer,boolean)', 'redes.f_rep_leame(text,jsonb,boolean,text,timestamp with time zone)',
                'tecnica.f_rep_columnas(text,jsonb)', 'tecnica.f_rep_eventos_planta(jsonb,boolean,timestamp with time zone,text,integer)',
                'tecnica.f_rep_leame(text,jsonb,boolean,text,timestamp with time zone)']
TEC = [f for f in REEMPLAZADAS if f.startswith('tecnica.')]
# lo NUEVO (por nombre exacto)
NUEVAS = ['redes.f_evento_origen(bigint)', 'redes.f_tubo_zona(text[])', 'redes.f_tubo_es_distribucion()',
          'public.geoportal_redes_evento_causal_fijar(text,text,text,boolean,text)', 'public.geoportal_redes_tubo_sectores_fijar(text,text,text[],text)']
# lo publicado que decide quién está en un evento, los avisos, el bot y las demás rutas de eventos: NO se toca (la verificación guarda sus md5)
NO_TOCAR_NOMBRES = ['geoportal_redes_evento_contrato', 'geoportal_redes_evento_vista_previa', 'geoportal_redes_evento_regreso', 'geoportal_redes_evento_cerrar',
                    'geoportal_redes_evento_anular', 'geoportal_redes_evento_asociar', 'geoportal_redes_evento_desasociar', 'geoportal_redes_evento',
                    'geoportal_redes_eventos', 'geoportal_redes_eventos_vigentes', 'geoportal_redes_evento_tipo_fijar',
                    'f_evento_contratos', 'f_evento_candidatos', 'f_eventos_abiertos', 'f_eventos_para_avisos', 'f_sin_agua_para_avisos', 'f_evento_tg_bot',
                    'f_evento_tg_l116', 'f_evento_tg_dano', 'f_evento_tg_campo', 'f_reporte_externo_recibir_evento', 'f_evento_abierto', 'f_evento_autorizar',
                    'f_evento_franja', 'f_evento_reportes', 'f_evento_marcar', 'f_sector_de', 'geoportal_redes_reporte_sectores', 'geoportal_redes_reporte_iniciar',
                    'geoportal_redes_reporte_pagina', 'f_avisos']
MIG = ['10_esquema.sql', '20_funciones.sql', '25_reemplazos.sql', '26_rpc.sql', '40_permisos.sql']


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
    assert '{{' not in t, (nombre, t[t.index('{{'):t.index('{{') + 40])
    return t


def md5f(f):
    return q(f"select md5(pg_get_functiondef('{f}'::regprocedure))")


def pares(firmas):
    return ', '.join("('%s', '%s')" % (f, md5f(f)) for f in firmas)


subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=ENV, check=True, capture_output=True)
assert q(CONJ) == MD5_BASE, q(CONJ)
assert q("select count(*) from redes.planta_sectores where activo") != '0', 'el doble de los sectores por planta no está'
for f in NUEVAS:
    assert q(f"select to_regprocedure('{f}') is null") == 't', f
NO_TOCAR = q("select string_agg(p.oid::regprocedure::text, '|' order by p.oid::regprocedure::text) from pg_proc p where p.pronamespace in ('redes'::regnamespace, 'public'::regnamespace, 'tecnica'::regnamespace) "
             f"and p.proname = any (array{NO_TOCAR_NOMBRES})").split('|')
assert len(NO_TOCAR) >= len(NO_TOCAR_NOMBRES), NO_TOCAR
ORIGINALES = '\n'.join(q(f"select pg_get_functiondef('{f}'::regprocedure)") + ';' for f in REEMPLAZADAS)
v = {'{{MD5_BASE}}': MD5_BASE, '{{TEC_ANTES}}': pares(TEC), '{{N_TEC_ANTES}}': str(len(TEC)), '{{REEMPLAZADAS_ANTES}}': pares(REEMPLAZADAS),
     '{{N_REEMPLAZADAS}}': str(len(REEMPLAZADAS)), '{{NO_TOCAR}}': pares(NO_TOCAR), '{{N_NO_TOCAR}}': str(len(NO_TOCAR)), '{{NUEVAS_LISTA}}': ', '.join(f"'{f}'" for f in NUEVAS),
     '{{N_NUEVAS}}': str(len(NUEVAS)), '{{MD5_TEC_ANTES_LOCAL}}': q(CONJ_TEC)}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, f'migracion_{NOMBRE}_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'sql', '70_pruebas.sql'), plantilla('70_pruebas.sql', v))
escribir(os.path.join(RAIZ, f'ensayo_en_transaccion_{NOMBRE}_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
p = subprocess.run([PSQL, '-d', BASE, '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, f'migracion_{NOMBRE}_editor.sql')], env=ENV, capture_output=True, text=True)
if p.returncode != 0:
    raise SystemExit(p.stderr[-3000:])
md5_despues = q(CONJ)
v.update({'{{MD5_DESPUES}}': md5_despues, '{{REEMPLAZADAS_DESPUES}}': pares(REEMPLAZADAS), '{{NUEVAS}}': pares(NUEVAS), '{{ORIGINALES}}': ORIGINALES,
          '{{DROPS}}': '\n'.join(f'drop function {f};' for f in NUEVAS if f not in ('redes.f_tubo_es_distribucion()',)), '{{MD5_TEC_DESPUES_LOCAL}}': q(CONJ_TEC)})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, f'huellas_solo_lectura_{NOMBRE}_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, f'verificacion_{NOMBRE}_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, f'reversa_{NOMBRE}_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
escribir(os.path.join(AQUI, 'huella_despues.txt'), md5_despues + '\n')
subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=ENV, check=True, capture_output=True)
print('huella de redes antes', MD5_BASE, '· después', md5_despues, '·', len(REEMPLAZADAS), 'reemplazadas ·', len(NUEVAS), 'nuevas ·', len(NO_TOCAR), 'que no se tocan')
