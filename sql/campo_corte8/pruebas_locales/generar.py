#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 8 con las huellas de la base local (campo_local en localhost:55434; ver rehacer_base.sh):
  1) rehace la base (campo hasta la pasada del 14-nov, Corte 1 de Técnica y el doble de la vista del 6b) y toma el texto vivo de las 2 funciones que cambian;
  2) escribe sql/25_reemplazos.sql (texto vivo con cambios exactos), la guardia y los _editor de migración y ensayo;
  3) aplica la migración, toma las huellas del Corte 8 y escribe huellas, verificación y reversa.
Uso: python3 -I generar.py"""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55434', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
BD = 'campo_local'
MIG = ['10_guardia_y_estructura.sql', '20_funciones.sql', '25_reemplazos.sql', '30_vista_geovisor.sql', '40_permisos.sql']
NUEVAS = ['campo.f_tipo_general(text)', 'campo.f_tecnica_claves(text)', 'campo.f_tecnica_entrar(text,text)', 'public.geoportal_campo_tec_formulario(text)',
          'public.geoportal_campo_tec_preparar_subida(text,integer,text,text)',
          'public.geoportal_campo_tec_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,jsonb,text,jsonb,text,text,timestamp with time zone)']
T = {
    # la única condición nueva: la marca de la transacción que ponen las RPC de Técnica (sin la marca, igual que antes)
    'campo.f_autorizar_reporte(text)': [(
        """  if campo.f_perfil(v_email) is null then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;""",
        """  -- Corte 8 de Técnica: también pasa quien entra por las RPC geoportal_campo_tec_* (ya autorizado allá por su formulario de Técnica); la marca solo dura esa transacción
  if campo.f_perfil(v_email) is null and coalesce(current_setting('geoportal.via_tecnica', true), '') <> 'on' then raise exception 'Sin permiso para esta función' using errcode = '42501'; end if;""")],
    'tecnica.f_formularios()': [(
        """         ('entrada_quimicos', 'Entrada de químicos',               'Químicos que ingresan al almacén.', 7);""",
        """         ('entrada_quimicos', 'Entrada de químicos',               'Químicos que ingresan al almacén.', 7),
         ('anomalia_compartida', 'Reportar anomalía',               'El mismo reporte de anomalías de Comercial, hecho desde Técnica.', 8),
         ('revision_compartida', 'Revisiones generales',            'La misma revisión general de Comercial, hecha desde Técnica.', 9);""")],
}
CAMBIADAS = list(T)


def q(sql):
    return subprocess.run([PSQL, '-d', BD, '-AtX', '-c', sql], env=ENV, check=True, capture_output=True, text=True).stdout.strip()


def leer(n):
    return open(os.path.join(RAIZ, 'sql', n), encoding='utf-8').read()


def escribir(ruta, texto):
    open(ruta, 'w', encoding='utf-8').write(texto)


def plantilla(texto, val):
    for k, v in val.items():
        texto = texto.replace(k, v)
    assert '{{' not in texto, texto[texto.index('{{'):][:60]
    return texto


fdef = lambda f: q(f"select pg_get_functiondef('{f}'::regprocedure)").rstrip()  # noqa: E731
fmd5 = lambda f: q(f"select md5(pg_get_functiondef('{f}'::regprocedure))")  # noqa: E731
DOM = "select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck'"
sql_lit = lambda s: s.replace("'", "''")  # noqa: E731

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_base'], env=ENV, check=True, capture_output=True)
antes = {f: fdef(f) for f in CAMBIADAS}
md5_antes = {f: fmd5(f) for f in CAMBIADAS}
dom_antes = q(DOM)
partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 8 · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo con UN cambio exacto:
--   · campo.f_autorizar_reporte: también pasa quien entra por las RPC de Técnica (la marca de la transacción). Sin la marca, igual que antes;
--   · tecnica.f_formularios: los dos formularios compartidos («Reportar anomalía» y «Revisiones generales»).
-- ====================================================================="""]
for f in CAMBIADAS:
    t = antes[f]
    for viejo, nuevo in T[f]:
        assert t.count(viejo) == 1, (f, viejo[:80], t.count(viejo))
        t = t.replace(viejo, nuevo)
    partes.append(f'\n-- {f}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))

v = {'{{MD5_AUTORIZAR}}': md5_antes['campo.f_autorizar_reporte(text)'], '{{MD5_FORMULARIOS}}': md5_antes['tecnica.f_formularios()'], '{{DEF_DOMINIO}}': sql_lit(dom_antes)}
mig = ''.join(plantilla(leer(n), v) for n in MIG)
escribir(os.path.join(RAIZ, 'migracion_tecnica_corte8_editor.sql'), 'begin;\n' + mig + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_tecnica_corte8_editor.sql'), 'begin;\n' + mig + leer('70_pruebas.sql') + 'rollback;\n')
subprocess.run([PSQL, '-d', BD, '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_tecnica_corte8_editor.sql')], env=ENV, check=True, capture_output=True)
md5_despues = {f: fmd5(f) for f in CAMBIADAS}
md5_nuevas = {f: fmd5(f) for f in NUEVAS}
v.update({'{{DEF_DOMINIO_8}}': sql_lit(q(DOM)),
          '{{MD5_VISTA}}': q("select md5(pg_get_viewdef('redes.v_reportes_comercial'::regclass, true))"),
          '{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_antes[f]}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{CAMBIADAS_8}}': ', '.join(f"('{f}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{NUEVAS}}': ', '.join(f"('{f}', '{md5_nuevas[f]}')" for f in NUEVAS),
          '{{TEXTOS_ANTES}}': '\n'.join(f'{antes[f]};\nrevoke all on function {f} from public, anon, authenticated, service_role;\n' for f in CAMBIADAS)})
pl = lambda n: plantilla(open(os.path.join(AQUI, 'plantillas', n), encoding='utf-8').read(), v)  # noqa: E731
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_tecnica_corte8_editor.sql'), pl('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_tecnica_corte8_editor.sql'), pl('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_tecnica_corte8_editor.sql'), 'begin;\n' + pl('90_reversa.sql') + 'commit;\n')
print('f_autorizar_reporte', md5_antes['campo.f_autorizar_reporte(text)'], '→', md5_despues['campo.f_autorizar_reporte(text)'], '· f_formularios', md5_antes['tecnica.f_formularios()'], '→', md5_despues['tecnica.f_formularios()'])
