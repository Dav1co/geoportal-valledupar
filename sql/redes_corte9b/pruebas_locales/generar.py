#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 9b, Fase 1 (simulación de cierre, §17) con las huellas reales de la base local de Code A (redes_local, puerto 55432):
  1) deja redes_local como producción (Corte 10 publicado, huella aad5952c…); comprueba la huella y toma el texto vivo de la función que cambia;
  2) escribe sql/25_reemplazos.sql (texto vivo con cambios exactos, cada uno una sola vez), sql/10_esquema.sql y los _editor;
  3) aplica la migración, toma las huellas del 9b y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py     Sobre otra huella de producción: MD5_BASE=<huella> python3 -I generar.py (con la plantilla rehecha: rehacer_base.sh plantilla)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = 'redes_local'
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_BASE = os.environ.get('MD5_BASE', 'aad5952c27e13cc3ad45623279ba7085')      # producción desde la publicación del Corte 10 (16-nov, 20:59)
NUEVAS = ['redes.f_sim_grafo()', 'redes.f_sim_llenar_agua()', 'redes.f_sim_escenario(bigint[],bigint,boolean,bigint[],geometry,integer)',
          'redes.f_simular_cierre(bigint)', 'redes.f_sim_tramo_cercano(numeric,numeric)', 'redes.f_sim_autorizar(text)',
          'public.geoportal_redes_simulacion_cierre(text,text,numeric,numeric)', 'public.geoportal_redes_simulacion_guardar(text,text,text)',
          'public.geoportal_redes_simulaciones(text,text)',
          # Fase 1b: el cierre real
          'redes.f_cierres_vigentes()', 'redes.f_cierre_regreso(bigint)', 'redes.f_cortes_foto(bigint,text,text)',
          'redes.f_cortes_para_avisos(timestamp with time zone,numeric,numeric)',
          'public.geoportal_redes_valvula_maniobra(text,text,text,text,text,text,text)', 'public.geoportal_redes_corte_regreso(text,text,text,text)',
          'public.geoportal_redes_cortes_vigentes(text)', 'public.geoportal_redes_cortes_recalcular(text,text)',
          'public.geoportal_redes_geovisor_mvt_cortes(text,integer,integer,integer)']
TABLAS = ['redes.simulaciones_cierre', 'redes.corte_foto_valvulas', 'redes.corte_foto_tramos', 'redes.corte_foto_zonas', 'redes.corte_fotos', 'redes.valvula_maniobras']
PARAMS = ['sim_segmento_grande_tramos', 'sim_segmento_grande_contratos', 'sim_no_cierra_max', 'sim_valvulas_lista_max', 'sim_contratos_guardar_max', 'sim_guardadas_max',
          'corte_horas_atras_max']
AVISOS = 'tecnica.f_avisos(boolean,boolean,timestamp with time zone)'
MIG = ['10_esquema.sql', '20_funciones.sql', '21_cortes.sql', '25_reemplazos.sql', '26_rpc.sql', '40_permisos.sql']

T = {}
# ---- las unidades de los parámetros nuevos son números enteros
T['redes.f_param_entero(text)'] = [(
    """'filas', 'bytes', 'zoom', 'hoja')""", """'filas', 'bytes', 'zoom', 'hoja', 'tramos', 'contratos', 'válvulas', 'simulaciones')""")]
# ---- Fase 1b: Avisos del 12 (distribución): «válvula cerrada hace más de X horas» (6 h naranja, 12 h rojo; parámetros). Lee la tabla de maniobras (no recalcula nada)
T[AVISOS] = [(
    """  -- ===================== PERSONAL (los dos supervisores y el administrador) =====================""",
    """  -- D10 (Corte 9b, Fase 1b). Válvulas cerradas (sin «abrir») hace más de X horas: naranja desde valvula_cerrada_naranja_h, rojo desde valvula_cerrada_rojo_h
  if p_distribucion then
    for r in select c.nivel, count(*) as n, min(c.hecho_en) as desde,
                    (array_to_json((array_agg(c.codigo || coalesce(' · ' || c.registro, '') || ' · hace ' || tecnica.f_texto_horas(c.horas) order by c.hecho_en))[1:5]))::jsonb as items
               from redes.f_cortes_para_avisos(v_ahora, tecnica.f_aparam('valvula_cerrada_naranja_h'), tecnica.f_aparam('valvula_cerrada_rojo_h')) c
              group by c.nivel loop
      v_av := v_av || jsonb_build_object('clave', 'valvulas_cerradas_' || r.nivel, 'area', 'distribucion', 'nivel', r.nivel, 'orden', case r.nivel when 'rojo' then 102 else 103 end,
                'titulo', format('%s hace más de %s', tecnica.f_cuantos(r.n, 'válvula cerrada', 'válvulas cerradas'),
                                 tecnica.f_texto_horas(tecnica.f_aparam(case r.nivel when 'rojo' then 'valvula_cerrada_rojo_h' else 'valvula_cerrada_naranja_h' end))),
                'detalle', 'Abra la válvula cuando vuelva el servicio, o ajuste la hora estimada de regreso.',
                'n', r.n, 'items', r.items, 'bandeja', jsonb_build_object('tablero', 'distribucion', 'pestana', null), 'desde', r.desde);
    end loop;
  end if;

  -- ===================== PERSONAL (los dos supervisores y el administrador) =====================""")]
CAMBIADAS = list(T)


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


fdef = lambda f: q(f"select pg_get_functiondef('{f}'::regprocedure)").rstrip()  # noqa: E731
fmd5 = lambda f: q(f"select md5(pg_get_functiondef('{f}'::regprocedure))")  # noqa: E731

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=ENV, check=True, capture_output=True)
assert q(CONJ) == MD5_BASE, q(CONJ)
antes = {f: fdef(f) for f in CAMBIADAS}
md5_antes = {f: fmd5(f) for f in CAMBIADAS}

partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9b (Fase 1) · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el del Corte 10 publicado) con cambios exactos, aplicados una sola vez.
--   · redes.f_param_entero: las unidades «tramos», «contratos», «válvulas» y «simulaciones» son números enteros (parámetros de la simulación);
--   · tecnica.f_avisos (Corte 12): el aviso D10 «válvula cerrada hace más de X horas» (Fase 1b). Solo agrega el bloque; lo demás queda igual.
-- ====================================================================="""]
for f in CAMBIADAS:
    t = antes[f]
    for viejo, nuevo in T[f]:
        assert t.count(viejo) == 1, (f, viejo[:90], t.count(viejo))
        t = t.replace(viejo, nuevo)
    partes.append(f'\n-- {f}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))

v = {'{{MD5_BASE}}': MD5_BASE, '{{MD5_AVISOS}}': md5_antes[AVISOS]}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte9b_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte9b_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
p = subprocess.run([PSQL, '-d', BASE, '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte9b_editor.sql')], env=ENV, capture_output=True, text=True)
if p.returncode != 0:
    raise SystemExit(p.stderr[-3000:])
md5_9b = q(CONJ)
md5_despues = {f: fmd5(f) for f in CAMBIADAS}
md5_nuevas = {f: fmd5(f) for f in NUEVAS}
v.update({'{{MD5_9B}}': md5_9b,
          '{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_antes[f]}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{CAMBIADAS_9B}}': ', '.join(f"('{f}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{N_CAMBIADAS}}': str(len(CAMBIADAS)),
          '{{NUEVAS}}': ', '.join(f"('{f}', '{md5_nuevas[f]}')" for f in NUEVAS),
          '{{N_NUEVAS}}': str(len(NUEVAS)),
          '{{PARAMS}}': ', '.join(f"'{p}'" for p in PARAMS),
          '{{N_PARAMS}}': str(len(PARAMS)),
          '{{DROPS}}': '\n'.join(f'drop function {f};' for f in reversed(NUEVAS)),
          '{{DROP_TABLAS}}': 'drop table ' + ', '.join(TABLAS) + ';',
          '{{TEXTOS_ANTES}}': '\n'.join(f'{antes[f]};\nrevoke all on function {f} from public, anon, authenticated, service_role;\n'
                                        + (f'grant execute on function {f} to service_role;\n' if f.startswith('public.') else '') for f in CAMBIADAS)})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte9b_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte9b_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte9b_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella antes (10, producción)', MD5_BASE, '· huella 9b', md5_9b)
