#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 4b con las huellas reales de la base local:
  1) rehace redes_local con lo del 4a (1a, 2, 3a, 3b, el doble de las 4 funciones de permisos y la migración del 4a); toma sus huellas;
  2) escribe sql/10_esquema.sql (guardia) y los _editor de migración y ensayo;
  3) aplica la migración, toma las huellas del 4b y escribe 05, 80 y 90 (y sus _editor).
El 4b no reemplaza ninguna función: solo agrega. Uso: python3 -I generar.py   (PostGIS local en localhost:55432)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
VIVAS = ['geoportal_puede', 'geoportal_mis_permisos', 'geoportal_admin_permisos', 'geoportal_admin_listar']
NUEVAS = ['geoportal_redes_personal', 'geoportal_redes_personal_fijar', 'geoportal_redes_personal_historial', 'geoportal_redes_catalogo',
          'geoportal_redes_alias_historial', 'geoportal_redes_cuadrilla_fijar', 'geoportal_redes_parametros', 'geoportal_redes_parametro_fijar',
          'geoportal_redes_graficas', 'geoportal_redes_descarga', 'geoportal_redes_nodos_por_clasificar', 'geoportal_redes_nodo_crear_activo']
INTERNAS = ['redes.f_area(text)', 'redes.f_geovisor_lectura(text)', 'redes.f_persona_tecnica(text)', 'redes.f_param_entero(text)']
MIG = ['10_esquema.sql', '20_vistas_funciones.sql', '26_rpc.sql', '40_permisos.sql']
FUNCS = ("select string_agg(format('(%L, %L)', p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))), ', ' order by p.oid::regprocedure::text), count(*) from pg_proc p "
         "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")


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


def md5s(nombres):
    filas = [l.split('|') for l in q("select proname || '|' || md5(pg_get_functiondef(oid)) from pg_proc where pronamespace = 'public'::regnamespace and proname in ("
                                     + ', '.join(f"'{n}'" for n in nombres) + ") order by 1").splitlines()]
    assert len(filas) == len(nombres), filas
    return dict(filas)


subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_4a'], env=ENV, check=True, capture_output=True)
md5_4a = q(CONJ)
assert md5_4a == '1a2be013019c9a59f1c1e0f2241661f0', md5_4a          # la huella del 4a que dice la bitácora
viv = md5s(VIVAS)
funcs_4a, n_funcs_4a = q(FUNCS).split('|')
v = {'{{MD5_CORTE_4A}}': md5_4a, '{{MD5_V_DANO}}': q("select md5(pg_get_viewdef('redes.v_dano'::regclass, true))"),
     '{{MD5_V_EPICRISIS}}': q("select md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true))"),
     '{{VIVAS_4A}}': ', '.join(f"('{n}', '{viv[n]}')" for n in VIVAS), '{{FUNCIONES_4A}}': funcs_4a, '{{N_FUNCIONES_4A}}': n_funcs_4a}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte4b_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte4b_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
subprocess.run([PSQL, '-d', 'redes_local', '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte4b_editor.sql')], env=ENV, check=True, capture_output=True)
md5_4b = q(CONJ)
nue = md5s(NUEVAS)
firmas = [q(f"select oid::regprocedure from pg_proc where pronamespace = 'public'::regnamespace and proname = '{n}'") for n in NUEVAS]
v.update({'{{MD5_CORTE_4B}}': md5_4b,
          '{{RPC_NUEVAS}}': ', '.join(f"('{n}', '{m}')" for n, m in sorted(nue.items())),
          '{{DROPS}}': '\n'.join(f'drop function {f};' for f in firmas + INTERNAS)})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte4b_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte4b_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte4b_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella 4a', md5_4a, '· huella 4b', md5_4b, '· funciones del 4a', n_funcs_4a)
