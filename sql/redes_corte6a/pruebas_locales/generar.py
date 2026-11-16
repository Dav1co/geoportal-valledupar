#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 6a con las huellas reales de la base local:
  1) rehace redes_local con lo del 5c; toma sus huellas y el texto vivo de las funciones que cambian;
  2) escribe sql/25_reemplazos.sql (texto vivo con cambios exactos, cada uno una sola vez), sql/10_esquema.sql (guardia) y los _editor de migración y ensayo;
  3) aplica la migración, toma las huellas del 6a y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py   (PostGIS local en localhost:55432)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
NUEVAS_RPC = ['geoportal_redes_geovisor', 'geoportal_redes_geovisor_mvt', 'geoportal_redes_geovisor_capa', 'geoportal_redes_geovisor_capas_fijar']
NUEVAS_INTERNAS = ['redes.f_autorizar_carga(text,text)', 'redes.f_autorizar_carga_id(text,bigint)', 'redes.f_geovisor_acceso(text)', 'redes.f_puede_formulario(text,text)']
MIG = ['10_esquema.sql', '26_rpc.sql', '25_reemplazos.sql', '40_permisos.sql']      # 26 antes que 25: los reemplazos llaman a f_autorizar_carga
MD5_5C = 'a5ce1ff8c5659de3b853e30f4d3025e6'

ADMIN = 'redes.f_autorizar_admin(p_solicitante)'
POR_CARGA = 'redes.f_autorizar_carga_id(p_solicitante, p_carga)'
POR_CAPA = 'redes.f_autorizar_carga(p_solicitante, p_capa)'
T = {}
# ---- 1. quién carga (David, 16-nov 01:30): el administrador todas; el supervisor de distribución las que no vienen del modelo (redes.capas.carga_supervisor)
for f in ['public.geoportal_redes_carga_lote(text,bigint,jsonb)', 'public.geoportal_redes_carga_resumen(text,bigint)',
          'public.geoportal_redes_carga_publicar(text,bigint,text)', 'public.geoportal_redes_carga_anular(text,bigint,text)',
          'public.geoportal_redes_carga_muestra(text,bigint)']:
    T[f] = [(ADMIN, POR_CARGA)]
T['public.geoportal_redes_carga_revertir(text,text,text)'] = [(ADMIN, POR_CAPA)]
T['public.geoportal_redes_cargue_iniciar(text,text,text,text,integer,text,integer,text,text)'] = [(ADMIN, POR_CAPA)]
T['public.geoportal_redes_carga_devolver_campo(text,bigint,text,text,text)'] = [
    (ADMIN, POR_CARGA),
    ("""  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres): por ejemplo, «Técnica corrigió el modelo»'); end if;""",
     """  if length(v_mot) < 10 or length(v_mot) > 1000 then perform tecnica.f_error('Escriba el motivo (10 a 1.000 caracteres): por ejemplo, «Técnica corrigió el modelo»'); end if;
  if v_campo = 'origen' and not public.geoportal_es_admin(v_email) then raise exception 'El origen del activo lo cambia solo el administrador' using errcode = '42501'; end if;      -- Corte 6a (§26.2)""")]
T['public.geoportal_redes_cargue_capas(text)'] = [
    ("""    'puede_cargar', v.perfil = 'admin',""",
     """    'puede_cargar', v.perfil = 'admin' or exists (select 1 from redes.capas x where x.activa and x.carga_supervisor),      -- Corte 6a: el supervisor carga las que no son del modelo"""),
    ("""               'codigo', c.codigo, 'nombre', c.nombre,""",
     """               'codigo', c.codigo, 'nombre', c.nombre, 'puede_cargar', v.perfil = 'admin' or c.carga_supervisor, 'solo_admin', not c.carga_supervisor,""")]
# ---- 2. «Geovisor técnico» en el menú (N-13): quién lo abre lo dice redes.f_geovisor_lectura (Corte 4b), sin tocarla
T['public.geoportal_redes_mi_perfil(text)'] = [(
    """'dashboard_ptap', public.geoportal_puede(p.email, 'dashboard_tecnico'));""",
    """'dashboard_ptap', public.geoportal_puede(p.email, 'dashboard_tecnico'),
                            'geovisor', redes.f_geovisor_lectura(p.email));      -- Corte 6a""")]

CAMBIADAS = list(T)


def q(sql):
    return subprocess.run([PSQL, '-d', 'redes_local', '-AtX', '-c', sql], env=ENV, check=True, capture_output=True, text=True).stdout.strip()


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

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_5c'], env=ENV, check=True, capture_output=True)
md5_5c = q(CONJ)
assert md5_5c == MD5_5C, md5_5c          # la huella del 5c que dice la bitácora
textos_5c = {f: fdef(f) for f in CAMBIADAS}
md5_cam_5c = {f: fmd5(f) for f in CAMBIADAS}

partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6a · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto del 5c con cambios exactos, aplicados una sola vez:
--   · geoportal_redes_carga_lote, _resumen, _publicar, _anular, _muestra, _revertir, _devolver_campo y geoportal_redes_cargue_iniciar: quién puede deja de ser
--     solo el administrador (redes.f_autorizar_admin) y pasa a redes.f_autorizar_carga: el supervisor de distribución también, en las capas que no vienen
--     del modelo (David, 16-nov 01:30). El origen del activo sigue siendo solo del administrador al devolver un campo;
--   · geoportal_redes_cargue_capas: «puede_cargar» por capa (y «solo_admin» en las del modelo);
--   · geoportal_redes_mi_perfil: el dato «geovisor» para el menú (N-13).
-- La RPC de psql del 1a (geoportal_redes_carga_iniciar) NO cambia: la carga por psql sigue siendo del administrador.
-- =====================================================================
"""]
for f in CAMBIADAS:
    t = textos_5c[f]
    for viejo, nuevo in T[f]:
        assert t.count(viejo) == 1, (f, viejo[:90], t.count(viejo))
        t = t.replace(viejo, nuevo)
    partes.append(f'\n-- {f}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))

v = {'{{MD5_CORTE_5C}}': md5_5c}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte6a_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte6a_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
subprocess.run([PSQL, '-d', 'redes_local', '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte6a_editor.sql')], env=ENV, check=True, capture_output=True)
md5_6a = q(CONJ)
md5_cam_6a = {f: fmd5(f) for f in CAMBIADAS}
nue = {n: q(f"select md5(pg_get_functiondef(oid)) from pg_proc where pronamespace = 'public'::regnamespace and proname = '{n}'") for n in NUEVAS_RPC}
firma_nueva = {n: q(f"select oid::regprocedure from pg_proc where pronamespace = 'public'::regnamespace and proname = '{n}'") for n in NUEVAS_RPC}
v.update({'{{MD5_CORTE_6A}}': md5_6a,
          '{{RPC_NUEVAS}}': ', '.join(f"('{n}', '{m}')" for n, m in sorted(nue.items())),
          '{{N_RPC}}': str(len(NUEVAS_RPC)),
          '{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_cam_5c[f]}', '{md5_cam_6a[f]}')" for f in CAMBIADAS),
          '{{CAMBIADAS_6A}}': ', '.join(f"('{f}', '{md5_cam_6a[f]}')" for f in CAMBIADAS),
          '{{N_CAMBIADAS}}': str(len(CAMBIADAS)),
          '{{TEXTOS_5C}}': '\n'.join(f'{textos_5c[f]};\nrevoke all on function {f} from public, anon, authenticated, service_role;\n'
                                     + (f'grant execute on function {f} to service_role;\n' if f.startswith('public.') else '') for f in CAMBIADAS),
          '{{DROPS}}': '\n'.join([f'drop function {firma_nueva[n]};' for n in NUEVAS_RPC] + [f'drop function {f};' for f in NUEVAS_INTERNAS])})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte6a_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte6a_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte6a_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella 5c', md5_5c, '· huella 6a', md5_6a)
