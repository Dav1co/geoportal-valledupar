#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 10 (inventario regulatorio) con las huellas reales de la base local de Code B (emdupar_b, puerto 55442):
  1) deja emdupar_b como producción (5d publicado); comprueba la huella y toma el texto vivo de las funciones que cambian;
  2) escribe sql/25_reemplazos.sql (texto vivo con cambios exactos, cada uno una sola vez), sql/10_esquema.sql y los _editor;
  3) aplica la migración, toma las huellas del 10 y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py     Sobre otra huella de producción: MD5_BASE=<huella> python3 -I generar.py (con la plantilla rehecha)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = os.environ.get('BASE_B', 'emdupar_b')
ENV = dict(os.environ, PGHOST='localhost', PGPORT=os.environ.get('PGPORT_B', '55442'), PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
assert ENV['PGPORT'] != '55432', 'El puerto 55432 es de Code A'
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_BASE = os.environ.get('MD5_BASE', '5fd6d00efdaa1a798e2628a2cde23c61')      # producción desde la publicación del 5d (16-nov)
NUEVAS = ['redes.f_val_hoja_alc()', 'redes.f_val_prefijos()', 'redes.f_ficha_regulatorio(bigint,text)', 'public.geoportal_redes_valoracion(text)']
TABLAS = ['redes.val_amarre', 'redes.val_filas', 'redes.val_hojas']
MIG = ['10_esquema.sql', '20_funciones.sql', '26_rpc.sql', '25_reemplazos.sql', '40_permisos.sql']

T = {}
# ---- la ficha: la sección «Inventario regulatorio», solo para supervisor y administrador
T['redes.f_ficha(bigint,text)'] = [(
    """    'referencia', case when v_super then nullif(redes.f_ficha_referencia(p_activo), '[]'::jsonb) end,
""",
    """    'referencia', case when v_super then nullif(redes.f_ficha_referencia(p_activo), '[]'::jsonb) end,
    -- Corte 10: inventario regulatorio (la fila de la Valoración Técnica 2019 a la que está amarrado). Solo supervisor y administrador
    'regulatorio', case when v_super then redes.f_ficha_regulatorio(p_activo, v.prefijo) end,
""")]
# ---- el parámetro de la hoja vigente es un número entero (1 o 2)
T['redes.f_param_entero(text)'] = [(
    """'filas', 'bytes', 'zoom')""", """'filas', 'bytes', 'zoom', 'hoja')""")]
# ---- la tesela del geovisor: si el activo no tiene fecha de instalación, la edad sale de la fecha de entrada en operación de su fila (marcada «edad_reg»).
#      Solo para quien ve el geovisor completo (supervisores y administrador): el operador sigue viendo «sin fecha de instalación».
T['public.geoportal_redes_geovisor_mvt(text,integer,integer,integer)'] = [
    ("""declare a record; v_env geometry;""", """declare a record; v_am bigint; v_val bigint; v_hoja text; v_env geometry;"""),
    ("""  select * into a from redes.f_geovisor_acceso(p_solicitante);
""",
     """  select * into a from redes.f_geovisor_acceso(p_solicitante);
  if a.completo then v_val := redes.f_ref_vigente('valoracion'); v_am := redes.f_ref_vigente('val_amarre'); v_hoja := redes.f_val_hoja_alc(); end if;      -- Corte 10
"""),
    ("""           case when m.fecha_instalacion is not null then greatest(0, extract(year from age(v_hoy, m.fecha_instalacion)))::integer end as edad,
""",
     """           case when m.fecha_instalacion is not null then greatest(0, extract(year from age(v_hoy, m.fecha_instalacion)))::integer
                when r.fecha is not null then greatest(0, extract(year from age(v_hoy, r.fecha)))::integer end as edad,
           case when m.fecha_instalacion is null and r.fecha is not null then true end as edad_reg,      -- Corte 10: fecha regulatoria, no de instalación
"""),
    ("""      from redes.activo_vigente_mat m
     where not m.retirado and not m.oculto and m.prefijo = any (v_pref)
""",
     """      from redes.activo_vigente_mat m
      left join lateral (select min(f.fecha_operacion) as fecha
                           from redes.val_amarre am join redes.val_filas f on f.carga_id = am.val_carga_id and f.hoja = am.hoja and f.n = am.n
                          where v_am is not null and m.fecha_instalacion is null and am.activo_id = m.activo_id and am.carga_id = v_am and am.val_carga_id = v_val
                            and am.hoja in ('acueducto', v_hoja) and am.n is not null) r on true
     where not m.retirado and not m.oculto and m.prefijo = any (v_pref)
""")]
# ---- la configuración del geovisor dice si hay edad regulatoria («edad_ref», para la nota de la leyenda), solo a quien ve el geovisor completo (al operador le llega nula)
T['public.geoportal_redes_geovisor(text)'] = [(
    """    'ficha', a.completo, 'compartir', a.completo,
""",
    """    'ficha', a.completo, 'compartir', a.completo,
    'edad_ref', case when a.completo and redes.f_ref_vigente('val_amarre') is not null then true end,      -- Corte 10: hay amarre con la valoración
""")]
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
-- TÉCNICA · FASE 1 · CORTE 10 · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el del 5d publicado) con cambios exactos, aplicados una sola vez.
--   · redes.f_ficha: la sección «regulatorio» (solo supervisor y administrador);
--   · redes.f_param_entero: la unidad «hoja» es un número entero;
--   · geoportal_redes_geovisor: «edad_ref» (hay amarre vigente), para la nota de la leyenda, solo a quien ve el geovisor completo;
--   · geoportal_redes_geovisor_mvt: sin fecha de instalación, la edad sale de la fecha regulatoria de la fila (propiedad «edad_reg»), para quien ve el geovisor completo.
-- ====================================================================="""]
for f in CAMBIADAS:
    t = antes[f]
    for viejo, nuevo in T[f]:
        assert t.count(viejo) == 1, (f, viejo[:90], t.count(viejo))
        t = t.replace(viejo, nuevo)
    partes.append(f'\n-- {f}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))

v = {'{{MD5_BASE}}': MD5_BASE}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte10_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte10_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
p = subprocess.run([PSQL, '-d', BASE, '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte10_editor.sql')], env=ENV, capture_output=True, text=True)
if p.returncode != 0:
    raise SystemExit(p.stderr[-3000:])
md5_10 = q(CONJ)
md5_despues = {f: fmd5(f) for f in CAMBIADAS}
md5_nuevas = {f: fmd5(f) for f in NUEVAS}
lit = lambda s: "'" + s.replace("'", "''") + "'"  # noqa: E731
v.update({'{{MD5_10}}': md5_10,
          '{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_antes[f]}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{CAMBIADAS_10}}': ', '.join(f"('{f}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{N_CAMBIADAS}}': str(len(CAMBIADAS)),
          '{{NUEVAS}}': ', '.join(f"('{f}', '{md5_nuevas[f]}')" for f in NUEVAS),
          '{{N_NUEVAS}}': str(len(NUEVAS)),
          '{{DROPS}}': '\n'.join(f'drop function {f};' for f in reversed(NUEVAS)),
          '{{DROP_TABLAS}}': 'drop table ' + ', '.join(TABLAS) + ';',
          '{{TEXTOS_ANTES}}': '\n'.join(f'{antes[f]};\nrevoke all on function {f} from public, anon, authenticated, service_role;\n'
                                        + (f'grant execute on function {f} to service_role;\n' if f.startswith('public.') else '') for f in CAMBIADAS)})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte10_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte10_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte10_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella antes (5d, producción)', MD5_BASE, '· huella 10', md5_10)
