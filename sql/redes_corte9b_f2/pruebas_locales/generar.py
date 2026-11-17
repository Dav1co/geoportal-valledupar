#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 9b, Fase 2 (presiones y alertas, usuarios sensibles, afectación, sensores) con las huellas reales de la base local de Code A
(redes_local, 55432). Agrega todo y reemplaza UNA función: tecnica.f_avisos (el aviso informativo de presiones, D11). Parte del paquete del 9b (1a + 1b) aplicado (huella 895517fb…).
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
MD5_BASE = os.environ.get('MD5_BASE', '895517fb68f74d6d6c20079c83bdf7c4')      # el paquete del 9b (1a + 1b), que se publica antes
NUEVAS = ['redes.f_presion_nivel(numeric,numeric)', 'redes.f_presion_nodos(text)', 'redes.f_alertas_presion(text)', 'redes.f_presion_para_avisos()', 'redes.f_sensible_tipo(text)', 'redes.f_sensibles_proponer(text)',
          'redes.f_sensibles_en(text[])', 'redes.f_sensor_estado(bigint)',
          'public.geoportal_redes_alertas_presion(text,text)', 'public.geoportal_redes_sensibles(text,text,text,integer)',
          'public.geoportal_redes_sensible_fijar(text,text,text,text,text)', 'public.geoportal_redes_afectacion(text,text)', 'public.geoportal_redes_sensores(text)',
          'public.geoportal_redes_afectaciones_danos(text)']
MIG = ['10_esquema.sql', '20_funciones.sql', '25_reemplazos.sql', '26_rpc.sql', '40_permisos.sql']
AVISOS = 'tecnica.f_avisos(boolean,boolean,timestamp with time zone)'
# ---- Avisos del 12 (David, 17-nov): UN aviso informativo «N nodos fuera de rango según el modelo» (ni rojo ni naranja). Sobre el texto publicado con la 1b.
# Decisión de David (17-nov, tarde): APAGADO por omisión (parámetro de Avisos «presion_modelo_aviso», 0 o 1) y solo con las horas confiables (redes.f_presion_nodos).
T_AVISOS = [(
    """  -- ===================== PERSONAL (los dos supervisores y el administrador) =====================""",
    """  -- D11 (Corte 9b, Fase 2). Presión de MODELO fuera de rango (Res. 0330 de 2017): un solo aviso informativo. APAGADO por omisión: solo sale si el
  -- parámetro «presion_modelo_aviso» vale 1 (lo enciende Técnica). Solo con las horas confiables del modelo (redes.f_presion_nodos). Los umbrales se leen una vez
  if p_distribucion and coalesce(tecnica.f_aparam('presion_modelo_aviso'), 0) >= 1 then
    v_x := redes.f_param('presion_baja_naranja_mca'); v_y := redes.f_param('presion_alta_naranja_mca');
    select count(*) into v_n from redes.f_presion_nodos('existente') x where x.p_min < v_x or x.p_max > v_y;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'presion_modelo', 'area', 'distribucion', 'nivel', 'info', 'orden', 175,
                'titulo', format('%s %s fuera de rango según el modelo', tecnica.f_texto_num(v_n), case when v_n = 1 then 'nodo' else 'nodos' end),      -- con punto de miles
                'detalle', format('Presión de modelo, no medida (Plan Maestro 2014): mínima bajo %s o máxima sobre %s m.c.a., sin las horas en que el modelo no es confiable.', v_x, v_y),
                'n', v_n, 'items', '[]'::jsonb, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', null), 'desde', null);
    end if;
  end if;

  -- ===================== PERSONAL (los dos supervisores y el administrador) =====================""")]


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
antes = q(f"select pg_get_functiondef('{AVISOS}'::regprocedure)").rstrip()
md5_av = q(f"select md5(pg_get_functiondef('{AVISOS}'::regprocedure))")
t = antes
for viejo, nuevo in T_AVISOS:
    assert t.count(viejo) == 1, (viejo[:80], t.count(viejo))
    t = t.replace(viejo, nuevo)
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), f"""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b · FASE 2 · 25 — REEMPLAZO (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- tecnica.f_avisos, con su texto vivo (el publicado con el 9b 1a + 1b, md5 {md5_av}) más UN bloque: D11, el aviso informativo
-- «N nodos fuera de rango según el modelo» (David, 17-nov: ni rojo ni naranja; APAGADO por omisión, parámetro «presion_modelo_aviso»; solo horas confiables).
-- Lo demás queda igual. AVISADO al Code B en la entrada de bitácora.
-- =====================================================================

-- {AVISOS}
{t};
""")
v = {'{{MD5_BASE}}': MD5_BASE, '{{MD5_AVISOS}}': md5_av}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte9b_f2_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte9b_f2_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
p = subprocess.run([PSQL, '-d', BASE, '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte9b_f2_editor.sql')], env=ENV, capture_output=True, text=True)
if p.returncode != 0:
    raise SystemExit(p.stderr[-3000:])
md5_f2 = q(CONJ)
v.update({'{{MD5_F2}}': md5_f2, '{{MD5_AVISOS_F2}}': q(f"select md5(pg_get_functiondef('{AVISOS}'::regprocedure))"),
          '{{TEXTO_AVISOS_ANTES}}': antes + ';',
          '{{NUEVAS}}': ', '.join("('%s', '%s')" % (f, q(f"select md5(pg_get_functiondef('{f}'::regprocedure))")) for f in NUEVAS),
          '{{N_NUEVAS}}': str(len(NUEVAS)),
          '{{DROPS}}': '\n'.join(f'drop function {f};' for f in reversed(NUEVAS))})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte9b_f2_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte9b_f2_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte9b_f2_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella antes (9b 1a + 1b)', MD5_BASE, '· huella Fase 2', md5_f2)
