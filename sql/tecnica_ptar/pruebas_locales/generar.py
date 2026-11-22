#!/usr/bin/env python3
"""Arma el paquete SQL de PTAR-1 y lo prueba en la base local del Code C (clúster PROPIO 55452, base ptar_base = producción a las 17:15 del 21-nov).
Escribe las versiones _editor (producción: guardia con la huella de técnica PUBLICADA, 3e9b0121…) y las locales en pruebas_locales/local/
(la misma guardia con la huella de técnica de la base local, que trae dobles de planta y no es igual a la de producción). La huella de redes es la misma en las dos.
Luego, en copias de ptar_base: ensayo (debe terminar en el ERROR esperado SIN FALLAS), migración + verificación y reversa. La carga del mapa la prueba tecnica_ptar_control (va después de PTAR-3).
Uso: python3 -I generar.py [-h]   ·   PSQL_C=<ruta de psql_c> (por omisión, la del scratchpad de esta sesión). No consulta Supabase."""
import os
import re
import subprocess
import sys

for _a in sys.argv[1:]:
    if _a in ('-h', '--help'):
        print(__doc__); sys.exit(0)
    print(f'Opción desconocida: {_a} (no lleva opciones; -h para el uso)', file=sys.stderr); sys.exit(2)

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
NOMBRE = 'tecnica_ptar'
PSQL = os.environ.get('PSQL_C', '/private/tmp/claude-502/-Users-ddiaz-geoportal-emdupar/4b3cafc3-afed-4be6-93b6-658ef5e49814/scratchpad/psql_c')
BASE = 'ptar_base'
MD5_REDES = '1ba192724c2fddcf321104700829f3cc'          # producción desde las 17:15 del 21-nov (corte de eventos publicado)
MD5_TECNICA_PROD = '3e9b0121e2b8beb313fad05de9e50f15'   # producción desde las 17:15 del 21-nov
HUELLA_REDES = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
                "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
HUELLA_TEC = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
              "where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_tec\\_%'))")
INTERNAS = ['f_elemento_coherente', 'f_elemento_protegido', 'f_tiene_alcance', 'f_autorizar_ptar', 'f_autorizar_instalacion', 'f_alias_vigente', 'f_tipo_elemento_texto', 'f_instalacion']
RPC = ['geoportal_tec_ptar_perfil', 'geoportal_tec_ptar_mapa', 'geoportal_tec_ptar_elemento', 'geoportal_tec_ptar_alias_fijar', 'geoportal_tec_ptar_alcances', 'geoportal_tec_ptar_alcance_fijar']
MIG = ['10_esquema.sql', '20_funciones.sql', '26_rpc.sql', '40_permisos.sql']
LOCAL = os.path.join(AQUI, 'local')
RES = os.path.join(RAIZ, 'resultados')


def q(sql, db):
    return subprocess.run([PSQL, '-d', db, '-AtX', '-c', sql], check=True, capture_output=True, text=True).stdout.strip()


def corre(db, archivo):
    return subprocess.run([PSQL, '-d', db, '-X', '-v', 'ON_ERROR_STOP=1', '-f', archivo], capture_output=True, text=True)


def copia(db):
    subprocess.run([PSQL, '-qX', '-d', 'postgres', '-c', f'drop database if exists {db}', '-c', f'create database {db} template {BASE}'], check=True, capture_output=True)


def leer(ruta):
    return open(ruta, encoding='utf-8').read()


def escribir(ruta, texto):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    open(ruta, 'w', encoding='utf-8').write(texto)


def plantilla(nombre, val):
    t = leer(os.path.join(AQUI, 'plantillas', nombre))
    for k, v in val.items():
        t = t.replace(k, v)
    assert '{{' not in t, (nombre, re.findall(r'\{\{[A-Z_]+\}\}', t))
    return t


puerto = q('show port', 'postgres')
assert puerto == '55452', f'no es el clúster del Code C (puerto {puerto})'
assert q(HUELLA_REDES, BASE) == MD5_REDES, 'ptar_base no tiene la huella de redes de producción'
md5_tec_local = q(HUELLA_TEC, BASE)
md5_sup = q("select md5(pg_get_functiondef('tecnica.f_autorizar_supervision(text)'::regprocedure))", BASE)
assert q(f"select count(*) from pg_proc where proname = any (array{INTERNAS + RPC})", BASE) == '0', 'ya hay funciones con los nombres nuevos'

comun = {'{{MD5_REDES}}': MD5_REDES, '{{MD5_AUT_SUP}}': md5_sup}
v_prod = dict(comun, **{'{{MD5_TECNICA}}': MD5_TECNICA_PROD})
v_local = dict(comun, **{'{{MD5_TECNICA}}': md5_tec_local})
sql = lambda n: leer(os.path.join(RAIZ, 'sql', n))


def armar(val, carpeta, sufijo):
    escribir(os.path.join(carpeta, '10_esquema.sql'), plantilla('10_esquema.sql', val))
    escribir(os.path.join(carpeta, '70_pruebas.sql'), plantilla('70_pruebas.sql', val))
    cuerpo = leer(os.path.join(carpeta, '10_esquema.sql')) + ''.join(sql(n) for n in MIG[1:])
    escribir(os.path.join(carpeta, f'migracion_{NOMBRE}{sufijo}.sql'), 'begin;\n' + cuerpo + 'commit;\n')
    escribir(os.path.join(carpeta, f'ensayo_en_transaccion_{NOMBRE}{sufijo}.sql'), 'begin;\n' + leer(os.path.join(AQUI, 'plantillas', '06_foto_columnas.sql')) + cuerpo + leer(os.path.join(carpeta, '70_pruebas.sql')) + 'rollback;\n')


armar(v_prod, os.path.join(RAIZ, 'sql'), '_editor')
for n in ('migracion', 'ensayo_en_transaccion'):         # las de producción van en la raíz del paquete
    os.replace(os.path.join(RAIZ, 'sql', f'{n}_{NOMBRE}_editor.sql'), os.path.join(RAIZ, f'{n}_{NOMBRE}_editor.sql'))
armar(v_local, LOCAL, '_local')

# migración local → firmas y md5 de lo nuevo, para la verificación y la reversa
copia('ptar_gen')
p = corre('ptar_gen', os.path.join(LOCAL, f'migracion_{NOMBRE}_local.sql'))
if p.returncode != 0:
    raise SystemExit('La migración local falló:\n' + p.stderr[-3000:])
assert q(HUELLA_REDES, 'ptar_gen') == MD5_REDES, 'PTAR-1 no debe cambiar la huella de redes'
firmas = q("select string_agg(p.oid::regprocedure::text, '|' order by p.pronamespace::regnamespace::text, p.proname) from pg_proc p "
           f"where (p.pronamespace = 'tecnica'::regnamespace and p.proname = any (array{INTERNAS + ['f_autorizar_supervision']})) "
           f"or (p.pronamespace = 'public'::regnamespace and p.proname = any (array{RPC}))", 'ptar_gen').split('|')
assert len(firmas) == len(INTERNAS) + len(RPC) + 1, firmas
md5s = {f: q(f"select md5(pg_get_functiondef('{f}'::regprocedure))", 'ptar_gen') for f in firmas}
md5_sup_d = md5s['tecnica.f_autorizar_supervision(text)']
tec_despues_local = q(HUELLA_TEC, 'ptar_gen')
lista = ', '.join(f"'{f}'" for f in firmas)
casos = ' '.join(f"when '{f}' then '{m}'" for f, m in md5s.items())
drops_rpc = '\n'.join(f'drop function {f};' for f in firmas if f.startswith('geoportal_tec_ptar'))
drops_int = '\n'.join(f'drop function {f};' for f in firmas if f.startswith('tecnica.') and 'f_autorizar_supervision' not in f and 'f_elemento_' not in f)
drops_disp = '\n'.join(f'drop function {f};' for f in firmas if 'f_elemento_' in f)
extra = {'{{MD5_AUT_SUP_DESPUES}}': md5_sup_d, '{{FIRMAS}}': lista, '{{CASOS}}': casos, '{{N_FUNC}}': str(len(firmas)), '{{DROPS_RPC}}': drops_rpc, '{{DROPS_INTERNAS}}': drops_int, '{{DROPS_DISPARADORES}}': drops_disp}
for val, carpeta, suf in ((v_prod, RAIZ, '_editor'), (v_local, LOCAL, '_local')):
    vv = dict(val, **extra)
    escribir(os.path.join(carpeta, f'huellas_solo_lectura_{NOMBRE}{suf}.sql'), plantilla('05_huellas_solo_lectura.sql', vv))
    escribir(os.path.join(carpeta, f'verificacion_{NOMBRE}{suf}.sql'), plantilla('80_verificacion.sql', vv))
    escribir(os.path.join(carpeta, f'reversa_{NOMBRE}{suf}.sql'), 'begin;\n' + plantilla('90_reversa.sql', vv) + 'commit;\n')
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, dict(v_prod, **extra)))

informe = []
# 1. verificación sobre la migración local
p = corre('ptar_gen', os.path.join(LOCAL, f'verificacion_{NOMBRE}_local.sql'))
informe += ['== verificación tras la migración (local)', p.stdout.strip()]
assert p.returncode == 0 and 'REVISAR' not in p.stdout, p.stdout + p.stderr
# 2. La carga del mapa va DESPUÉS de PTAR-3 (necesita los puntos de la PTAR): la prueba el generador de tecnica_ptar_control, con su arnés.
# 3. reversa: no se deja si hay datos (la carga) — en una copia limpia sí, y técnica vuelve a la de antes
q("insert into tecnica.elementos_planta (instalacion_id, codigo, tipo, nombre, geom, origen, creado_por) select id, 'PRUEBA-REV', 'pozo', 'Prueba reversa', "
  "st_setsrid(st_makepoint(-74.5, 4.5), 4326), 'dibujo', 'prueba.reversa@emdupar.gov.co' from tecnica.instalaciones where codigo = 'ptar'", 'ptar_gen')
p = corre('ptar_gen', os.path.join(LOCAL, f'reversa_{NOMBRE}_local.sql'))
assert p.returncode != 0 and 'ya tiene datos' in p.stderr, p.stderr
informe += ['== reversa con un elemento cargado: se detiene (esperado)']
copia('ptar_gen')
assert corre('ptar_gen', os.path.join(LOCAL, f'migracion_{NOMBRE}_local.sql')).returncode == 0
p = corre('ptar_gen', os.path.join(LOCAL, f'reversa_{NOMBRE}_local.sql'))
assert p.returncode == 0, p.stderr
assert q(HUELLA_TEC, 'ptar_gen') == md5_tec_local and q(HUELLA_REDES, 'ptar_gen') == MD5_REDES, 'la reversa no deja técnica y redes como antes'
informe += ['== reversa en limpio: técnica vuelve a ' + md5_tec_local + ' y redes sigue en ' + MD5_REDES]
# 4. ensayo (en una copia; termina en el ERROR esperado)
copia('ptar_gen')
p = corre('ptar_gen', os.path.join(LOCAL, f'ensayo_en_transaccion_{NOMBRE}_local.sql'))
res = (p.stderr or '').strip()
informe += ['== ensayo (local)', res]
assert p.returncode != 0 and 'SIN FALLAS' in res, res
assert q("select to_regclass('tecnica.instalaciones') is null", 'ptar_gen') == 't', 'el ensayo dejó algo'
subprocess.run([PSQL, '-qX', '-d', 'postgres', '-c', 'drop database if exists ptar_gen'], check=True, capture_output=True)
resumen = (f'huella de redes {MD5_REDES} (no cambia) · técnica PRODUCCIÓN {MD5_TECNICA_PROD} (guardia del _editor) · técnica local antes {md5_tec_local} → después {tec_despues_local} · '
           f'f_autorizar_supervision {md5_sup} → {md5_sup_d} · {len(firmas)} funciones nuevas o reemplazadas')
informe.insert(0, resumen)
escribir(os.path.join(RES, 'sql_local.txt'), '\n'.join(informe) + '\n')
print(resumen)
print(re.search(r'RESULTADO: .*', res).group(0))
