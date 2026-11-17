#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 12 con las huellas de la base local (redes_local en localhost:55432, como producción: 7a + 9a + 9a-bis + 7c):
guardia (md5 de las 2 funciones de redes que se llaman), migración y ensayo; aplica y escribe huellas, verificación y reversa.
Uso: python3 -I generar.py"""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
MIG = ['10_esquema.sql', '20_funciones.sql', '30_rpc.sql', '40_permisos.sql']
REDES_USADAS = ['redes.f_param(text)', 'redes.f_muestreo_calidad(bigint)']
NUEVAS = ['tecnica.f_aparam(text)', 'tecnica.f_cuantos(bigint,text,text)', 'tecnica.f_texto_horas(numeric)', 'tecnica.f_texto_num(numeric)', 'tecnica.f_avisos_perfil(text)',
          'tecnica.f_avisos(boolean,boolean,timestamp with time zone)', 'tecnica.f_nivel_rango(text)', 'tecnica.f_avisos_encolar(timestamp with time zone)',
          'tecnica.avisos_tomar(integer,integer)', 'tecnica.avisos_marcar(uuid,uuid,text,jsonb,boolean)', 'tecnica.avisos_liberar(uuid,uuid)',
          'public.geoportal_tec_avisos(text)', 'public.geoportal_tec_avisos_parametros(text)', 'public.geoportal_tec_aviso_parametro_fijar(text,text,numeric,text)',
          'public.geoportal_tec_quimico_minimos(text)', 'public.geoportal_tec_quimico_minimo_fijar(text,text,numeric,text)']
TABLAS = ['tecnica.aviso_parametros', 'tecnica.aviso_parametro_eventos', 'tecnica.quimico_minimo_eventos', 'tecnica.avisos_salida', 'tecnica.aviso_salida_eventos', 'tecnica.v_avisos_salida']
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")


def q(sql):
    return subprocess.run([PSQL, '-d', 'redes_local', '-AtX', '-c', sql], env=ENV, check=True, capture_output=True, text=True).stdout.strip()


def leer(n):
    return open(os.path.join(RAIZ, 'sql', n), encoding='utf-8').read()


def escribir(ruta, texto):
    open(ruta, 'w', encoding='utf-8').write(texto)


def plantilla(texto, val):
    for k, v in val.items():
        texto = texto.replace(k, v)
    assert '{{' not in texto, texto[texto.index('{{'):][:60]
    return texto


fmd5 = lambda f: q(f"select md5(pg_get_functiondef('{f}'::regprocedure))")  # noqa: E731

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'sin_12'], env=ENV, check=True, capture_output=True)
conj_antes = q(CONJ)
md5_redes = {f: fmd5(f) for f in REDES_USADAS}
v = {'{{REDES_USADAS}}': ', '.join(f"('{f}', '{md5_redes[f]}')" for f in REDES_USADAS), '{{N_REDES_USADAS}}': str(len(REDES_USADAS))}
mig = ''.join(plantilla(leer(n), v) for n in MIG)
escribir(os.path.join(RAIZ, 'migracion_tecnica_corte12_editor.sql'), 'begin;\n' + mig + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_tecnica_corte12_editor.sql'), 'begin;\n' + mig + leer('70_pruebas.sql') + 'rollback;\n')
subprocess.run([PSQL, '-d', 'redes_local', '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_tecnica_corte12_editor.sql')], env=ENV, check=True, capture_output=True)
md5_nuevas = {f: fmd5(f) for f in NUEVAS}
assert q(CONJ) == conj_antes, 'la huella de redes cambió'
v.update({'{{NUEVAS}}': ', '.join(f"('{f}', '{md5_nuevas[f]}')" for f in NUEVAS), '{{N_NUEVAS}}': str(len(NUEVAS)),
          '{{TABLAS}}': ', '.join(f"'{t}'" for t in TABLAS), '{{CONJ}}': conj_antes})
pl = lambda n: plantilla(open(os.path.join(AQUI, 'plantillas', n), encoding='utf-8').read(), v)  # noqa: E731
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_tecnica_corte12_editor.sql'), pl('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_tecnica_corte12_editor.sql'), pl('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_tecnica_corte12_editor.sql'), 'begin;\n' + pl('90_reversa.sql') + 'commit;\n')
print('redes', conj_antes, '(sin cambio) ·', ' · '.join(f"{f} {m[:8]}" for f, m in md5_redes.items()))
