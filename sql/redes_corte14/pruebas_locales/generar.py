#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 14 («Encontrar o reportar activo») con las huellas reales de la base local de Code B (emdupar_b14, puerto 55442):
  1) deja emdupar_b14 como producción al publicar (el 9b completo); comprueba la huella y toma el texto vivo de las funciones que cambian;
  2) escribe sql/25_reemplazos.sql (texto vivo con cambios exactos, cada uno una sola vez), sql/10_esquema.sql y los _editor;
  3) aplica la migración, toma las huellas del 14 y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py     Sobre otra huella de producción (la final del 9b): MD5_BASE=<huella> python3 -I generar.py (con la plantilla rehecha)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = os.environ.get('BASE_B', 'emdupar_b14')
ENV = dict(os.environ, PGHOST='localhost', PGPORT=os.environ.get('PGPORT_B', '55442'), PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning', BASE_B=BASE)
assert ENV['PGPORT'] != '55432', 'El puerto 55432 es de Code A'
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_BASE = os.environ.get('MD5_BASE', 'a327aa51f43bb5cc2112a6db089718ed')      # HUELLA FINAL del 9b (después de la Fase 3), la que dio el Code A el 17-nov (ORDEN_DE_PUBLICACION.md, 41d086c)
TABLAS = ['redes.levantar_fotos', 'redes.levantar_eventos', 'redes.levantar_preparaciones', 'redes.levantar_puntos']
PARAMETROS = ['levantar_radio_min_m', 'levantar_radio_max_m', 'levantar_duplicado_m', 'levantar_lista_max']
MIG = ['10_esquema.sql', '20_funciones.sql', '26_rpc.sql', '25_reemplazos.sql', '40_permisos.sql']
DOM = "select pg_get_constraintdef(c.oid) from pg_constraint c where c.contypid = 'tecnica.formulario_clave'::regtype and c.conname = 'formulario_clave_ck'"
CHK = "select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'campo.personal_eventos'::regclass and c.conname = 'personal_eventos_formulario_check'"

T = {}
# ---- el perfil de redes dice si la persona tiene «Encontrar o reportar activo» (la tarjeta del inicio de Técnica)
T['public.geoportal_redes_mi_perfil(text)'] = [(
    """                            'ficha_buscar', p.perfil in ('admin', 'supervisor') or redes.f_operador_redes(p.email));""",
    """                            'ficha_buscar', p.perfil in ('admin', 'supervisor') or redes.f_operador_redes(p.email),
                            'activo_campo', redes.f_levantar_puede(p.email));      -- Corte 14: «Encontrar o reportar activo»""")]
# ---- Comercial: el formulario en la lista de Personal (la asignación solo se registra, como las demás de Comercial)
T['campo.f_formularios_personal()'] = [(
    """  union all
  select 'acta', 'Reportar posible pérdida', 'Reportar posible pérdida', 2000000000
""",
    """  union all
  select 'acta', 'Reportar posible pérdida', 'Reportar posible pérdida', 2000000000
  union all      -- Corte 14 de Técnica: «Encontrar o reportar activo» (lo usa quien tiene Formularios de campo; aquí solo se registra a quién se le asigna)
  select 'activo_campo', 'Encontrar o reportar activo', 'Activos de la red', 2000000001
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
    assert '{{' not in t, (nombre, t[t.index('{{'):t.index('{{') + 40])
    return t


fdef = lambda f: q(f"select pg_get_functiondef('{f}'::regprocedure)").rstrip()  # noqa: E731
fmd5 = lambda f: q(f"select md5(pg_get_functiondef('{f}'::regprocedure))")  # noqa: E731
lit = lambda s: s.replace("'", "''")  # noqa: E731

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=ENV, check=True, capture_output=True)
assert q(CONJ) == MD5_BASE, q(CONJ)
antes = {f: fdef(f) for f in CAMBIADAS}
md5_antes = {f: fmd5(f) for f in CAMBIADAS}
dom_antes, chk_antes = q(DOM), q(CHK)

partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el de producción al publicar) con cambios exactos, aplicados una sola vez.
--   · geoportal_redes_mi_perfil: «activo_campo» (la persona tiene «Encontrar o reportar activo»), para la tarjeta del inicio de Técnica;
--   · campo.f_formularios_personal: una fila más, «Encontrar o reportar activo», en la lista de Personal de Comercial.
-- ====================================================================="""]
for f in CAMBIADAS:
    t = antes[f]
    for viejo, nuevo in T[f]:
        assert t.count(viejo) == 1, (f, viejo[:90], t.count(viejo))
        t = t.replace(viejo, nuevo)
    partes.append(f'\n-- {f}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))

v = {'{{MD5_BASE}}': MD5_BASE, '{{DEF_DOMINIO}}': lit(dom_antes), '{{DEF_CHECK_CAMPO}}': lit(chk_antes), '{{MD5_CAMPO_FORM}}': md5_antes['campo.f_formularios_personal()'],
     '{{DEF_DOMINIO_14}}': lit(dom_antes.replace("'revision_compartida'::text]", "'revision_compartida'::text, 'activo_campo'::text]"))}
assert v['{{DEF_DOMINIO_14}}'] != v['{{DEF_DOMINIO}}']
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte14_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte14_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
p = subprocess.run([PSQL, '-d', BASE, '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte14_editor.sql')], env=ENV, capture_output=True, text=True)
if p.returncode != 0:
    raise SystemExit(p.stderr[-3000:])
assert q(DOM) == v['{{DEF_DOMINIO_14}}'].replace("''", "'"), q(DOM)
md5_14 = q(CONJ)
NUEVAS = q("select string_agg(p.oid::regprocedure::text, '|' order by p.pronamespace::regnamespace::text, p.proname) from pg_proc p where (p.pronamespace = 'redes'::regnamespace "
           "and p.proname like 'f\\_levantar\\_%') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_levantar\\_%')").split('|')
NUEVAS = [n if '.' in n.split('(')[0] else 'public.' + n for n in NUEVAS]
md5_despues = {f: fmd5(f) for f in CAMBIADAS}
md5_nuevas = {f: fmd5(f) for f in NUEVAS}
n_rpc = sum(1 for f in NUEVAS if f.startswith('public.')) + 1
v.update({'{{MD5_14}}': md5_14,
          '{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_antes[f]}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{CAMBIADAS_14}}': ', '.join(f"('{f}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{N_CAMBIADAS}}': str(len(CAMBIADAS)),
          '{{NUEVAS}}': ', '.join(f"('{f}', '{md5_nuevas[f]}')" for f in NUEVAS),
          '{{N_NUEVAS}}': str(len(NUEVAS)), '{{N_RPC}}': str(n_rpc),
          '{{PARAMETROS}}': ', '.join(f"'{x}'" for x in PARAMETROS), '{{N_PARAMETROS}}': str(len(PARAMETROS)),
          '{{DEF_CHECK_CAMPO_14}}': lit(q(CHK)), '{{DEF_CHECK_CAMPO_SQL}}': chk_antes,
          '{{DROPS}}': '\n'.join(f'drop function {f};' for f in sorted(NUEVAS, key=lambda x: (x.startswith('redes.'), x))),
          '{{DROP_TABLAS}}': 'drop table ' + ', '.join(TABLAS) + ';',
          '{{TEXTOS_ANTES}}': '\n'.join(f'{antes[f]};\n' + (f'revoke all on function {f} from public, anon, authenticated, service_role;\ngrant execute on function {f} to service_role;\n'
                                                           if f.startswith('public.') else '') for f in CAMBIADAS)})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte14_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte14_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte14_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella antes (9b completo)', MD5_BASE, '· huella 14', md5_14, '·', len(NUEVAS), 'nuevas')
