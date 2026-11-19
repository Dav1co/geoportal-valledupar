#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 15 («Evento de suspensión») con las huellas reales de la base local de Code A (redes_local, 55432):
  1) deja redes_local como producción al 18-nov (huella 63d91763…) y toma el texto vivo de tecnica.f_avisos;
  2) escribe sql/25_reemplazos.sql (el texto vivo con UN cambio exacto), sql/10_esquema.sql y los _editor;
  3) aplica la migración, toma las huellas del 15 y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py     Sobre otra huella: MD5_BASE=<huella> python3 -I generar.py"""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = 'redes_local'
NOMBRE = 'redes_corte15'
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_BASE = os.environ.get('MD5_BASE', '63d917635b33e3696f28a3b0e579c002')      # la corrección del 9b, publicada el 18-nov
AVISOS = 'tecnica.f_avisos(boolean,boolean,timestamptz)'
TABLAS = ['redes.evento_suspension_reportes', 'redes.evento_suspension_eventos', 'redes.eventos_suspension', 'redes.evento_tipo_eventos', 'redes.evento_tipos_asociables',
          'redes.planta_sector_eventos', 'redes.planta_sectores']
PARAMETROS = ['evento_radio_min_m', 'evento_radio_max_m', 'evento_sectores_max', 'evento_horas_atras_max', 'evento_lista_max']
# lo publicado que este corte NO reemplaza (reciben un disparador sus tablas, no ellas): las huellas y la verificación lo comprueban
PUBLICADAS = ['redes.f_reporte_externo_recibir(jsonb)', 'redes.f_publicar_l116(bigint,text,text)', 'public.geoportal_redes_crear_dano(text,uuid,jsonb,text)',
              'public.geoportal_redes_cortes_vigentes(text)', 'redes.f_sector_de(geometry)']
MIG = ['10_esquema.sql', '20_funciones.sql', '26_rpc.sql', '25_reemplazos.sql', '40_permisos.sql']
NUEVAS_SQL = ("select string_agg(p.oid::regprocedure::text, '|' order by p.pronamespace::regnamespace::text, p.proname) from pg_proc p where "
              "(p.pronamespace = 'redes'::regnamespace and (p.proname like 'f\\_evento%' or p.proname in ('f_sin_agua_para_avisos', 'f_reporte_externo_recibir_evento'))) "
              "or (p.pronamespace = 'public'::regnamespace and (p.proname like 'geoportal\\_redes\\_evento%' or p.proname = 'geoportal_redes_planta_sectores_fijar'))")

# ---- el único reemplazo: tecnica.f_avisos gana dos bloques, justo antes del de Personal
VIEJO = """  -- ===================== PERSONAL (los dos supervisores y el administrador) =====================
"""
NUEVO = """  -- D15 (Corte 15). Eventos de suspensión: UN aviso por evento abierto (no uno por reporte); rojo si ya pasó la hora estimada de regreso.
  -- Al supervisor de distribución, todos; al de planta, los eventos totales.
  if p_distribucion or p_planta then
    for r in select x.codigo, x.alcance, x.nivel, x.titulo, x.detalle, x.n, x.desde from redes.f_eventos_para_avisos(v_ahora) x
              where p_distribucion or x.alcance = 'total' order by x.desde loop
      v_av := v_av || jsonb_build_object('clave', 'evento_suspension_' || lower(r.codigo), 'area', case when p_distribucion then 'distribucion' else 'planta' end,
                'nivel', r.nivel, 'orden', 100, 'titulo', r.titulo, 'detalle', r.detalle, 'n', r.n, 'items', '[]'::jsonb,
                'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', null, 'evento', r.codigo), 'desde', r.desde);
    end loop;
  end if;
  -- D15b. Reportes de falta de agua o baja presión (bot y línea 116) de las últimas horas que NO están en ningún evento: un solo aviso
  if p_distribucion then
    select x.n, x.desde, x.items into v_n, v_desde, v_items from redes.f_sin_agua_para_avisos(v_ahora, coalesce(tecnica.f_aparam('sin_agua_ventana_h'), 24)) x;
    if v_n > 0 then
      v_av := v_av || jsonb_build_object('clave', 'sin_agua_sin_evento', 'area', 'distribucion', 'nivel', 'naranja', 'orden', 101,
                'titulo', format('%s de falta de agua sin evento', tecnica.f_cuantos(v_n, 'reporte', 'reportes')),
                'detalle', format('Llegaron en las últimas %s horas y no están en ningún evento de suspensión: revise si hay que declarar uno.', coalesce(tecnica.f_aparam('sin_agua_ventana_h'), 24)),
                'n', v_n, 'items', v_items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', null), 'desde', v_desde);
    end if;
  end if;

  -- ===================== PERSONAL (los dos supervisores y el administrador) =====================
"""


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


def fmd5(f):
    return q(f"select md5(pg_get_functiondef('{f}'::regprocedure))")


def pares(firmas):
    return ', '.join("('%s', '%s')" % (f, fmd5(f)) for f in firmas)


subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=ENV, check=True, capture_output=True)
assert q(CONJ) == MD5_BASE, q(CONJ)
antes = q(f"select pg_get_functiondef('{AVISOS}'::regprocedure)").rstrip()
md5_avisos = fmd5(AVISOS)
assert antes.count(VIEJO) == 1, antes.count(VIEJO)
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), """-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 15 · «EVENTO DE SUSPENSIÓN» · 25 — REEMPLAZO (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- es el texto vivo de tecnica.f_avisos (el del Corte 14) con UN cambio exacto: dos bloques nuevos antes del de Personal.
--   · D15: un aviso por evento de suspensión abierto (rojo si ya pasó la hora estimada de regreso);
--   · D15b: un aviso con los reportes de falta de agua (bot y línea 116) que no están en ningún evento.
-- =====================================================================

-- """ + AVISOS + "\n" + antes.replace(VIEJO, NUEVO) + ";\n")
v = {'{{MD5_BASE}}': MD5_BASE, '{{MD5_AVISOS}}': md5_avisos, '{{PUBLICADAS}}': pares(PUBLICADAS), '{{N_PUBLICADAS}}': str(len(PUBLICADAS))}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, f'migracion_{NOMBRE}_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, f'ensayo_en_transaccion_{NOMBRE}_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
p = subprocess.run([PSQL, '-d', BASE, '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, f'migracion_{NOMBRE}_editor.sql')], env=ENV, capture_output=True, text=True)
if p.returncode != 0:
    raise SystemExit(p.stderr[-3000:])
md5_15 = q(CONJ)
NUEVAS = [n if '.' in n.split('(')[0] else 'public.' + n for n in q(NUEVAS_SQL).split('|')]
v.update({'{{MD5_15}}': md5_15, '{{MD5_AVISOS_15}}': fmd5(AVISOS), '{{NUEVAS}}': pares(NUEVAS), '{{N_NUEVAS}}': str(len(NUEVAS)),
          '{{N_RPC}}': str(sum(1 for f in NUEVAS if f.startswith('public.'))),
          '{{PARAMETROS}}': ', '.join(f"'{x}'" for x in PARAMETROS),
          '{{DROPS}}': '\n'.join(f'drop function {f};' for f in sorted(NUEVAS, key=lambda x: (x.startswith('redes.'), x))),
          '{{DROP_TABLAS}}': 'drop table ' + ', '.join(TABLAS) + ';',
          '{{TEXTO_AVISOS_ANTES}}': antes + ';'})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, f'huellas_solo_lectura_{NOMBRE}_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, f'verificacion_{NOMBRE}_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, f'reversa_{NOMBRE}_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=ENV, check=True, capture_output=True)
print('huella antes (corrección del 9b)', MD5_BASE, '· huella con el Corte 15', md5_15, '·', len(NUEVAS), 'funciones nuevas')
