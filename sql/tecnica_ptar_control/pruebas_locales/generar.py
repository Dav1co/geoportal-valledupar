#!/usr/bin/env python3
"""Arma el paquete SQL de PTAR-3 («Sistema de Control PTAR»: Caracterización, puntos de la PTAR y parámetros en la ficha) y lo prueba en la base local del Code C
(clúster PROPIO 55452). Plantilla: ptar_p1 = producción a las 17:15 del 21-nov + PTAR-1 + el doble de captura de la Torre B (pruebas_locales/doble_captura_torre_b.sql).
En copias de la plantilla: ensayo (ERROR esperado SIN FALLAS), migración + verificación, carga del mapa (la de tecnica_ptar/carga, que va DESPUÉS de PTAR-3) + su
verificación, el arnés con un año de Caracterización y la reversa (se detiene con datos; en limpio deja las funciones como estaban).
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
NOMBRE = 'tecnica_ptar_control'
PSQL = os.environ.get('PSQL_C', '/private/tmp/claude-502/-Users-ddiaz-geoportal-emdupar/4b3cafc3-afed-4be6-93b6-658ef5e49814/scratchpad/psql_c')
BASE = 'ptar_p1'
MD5_REDES = '1ba192724c2fddcf321104700829f3cc'
CARGA = os.path.join(RAIZ, '..', 'tecnica_ptar', 'carga')
HUELLA_REDES = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
                "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
REEMPLAZADAS = ['tecnica.f_formularios()', 'tecnica.f_tipo_punto_texto(text)', 'tecnica.f_autorizar_captura(text,text)',
                'public.geoportal_tec_ptar_mapa(text,text)', 'public.geoportal_tec_ptar_elemento(text,text)']
NUEVAS = ['tecnica.f_parametros_punto(bigint,integer)', 'tecnica.f_estado_parametros(jsonb)']
MIG = ['10_esquema.sql', '20_funciones.sql', '26_rpc.sql', '40_permisos.sql']


def q(sql, db):
    return subprocess.run([PSQL, '-d', db, '-AtX', '-c', sql], check=True, capture_output=True, text=True).stdout.strip()


def corre(db, archivo):
    return subprocess.run([PSQL, '-d', db, '-X', '-v', 'ON_ERROR_STOP=1', '-f', archivo], capture_output=True, text=True)


def copia(db):
    subprocess.run([PSQL, '-qX', '-d', 'postgres', '-c', f'drop database if exists {db}', '-c', f'create database {db} template {BASE}'], check=True, capture_output=True)


leer = lambda r: open(r, encoding='utf-8').read()


def escribir(ruta, texto):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    open(ruta, 'w', encoding='utf-8').write(texto)


def plantilla(nombre, val):
    t = leer(os.path.join(AQUI, 'plantillas', nombre))
    for k, v in val.items():
        t = t.replace(k, v)
    assert '{{' not in t, (nombre, re.findall(r'\{\{[A-Z_]+\}\}', t))
    return t


md5 = lambda f, db: q(f"select md5(pg_get_functiondef('{f}'::regprocedure))", db)
assert q('show port', 'postgres') == '55452', 'no es el clúster del Code C'
assert q(HUELLA_REDES, BASE) == MD5_REDES, 'la plantilla no tiene la huella de redes de producción'
antes = {f: md5(f, BASE) for f in REEMPLAZADAS + ['tecnica.f_autorizar_supervision(text)']}
defs_antes = {f: q(f"select pg_get_functiondef('{f}'::regprocedure)", BASE) for f in REEMPLAZADAS}
v = {'{{MD5_REDES}}': MD5_REDES, '{{MD5_AUT_SUP}}': antes['tecnica.f_autorizar_supervision(text)'], '{{MD5_PTAR_MAPA}}': antes['public.geoportal_tec_ptar_mapa(text,text)'],
     '{{MD5_PTAR_ELEMENTO}}': antes['public.geoportal_tec_ptar_elemento(text,text)'], '{{MD5_FORMULARIOS}}': antes['tecnica.f_formularios()'],
     '{{MD5_CAPTURA}}': antes['tecnica.f_autorizar_captura(text,text)'], '{{MD5_TIPO_PUNTO}}': antes['tecnica.f_tipo_punto_texto(text)']}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'sql', '70_pruebas.sql'), plantilla('70_pruebas.sql', v))
cuerpo = ''.join(leer(os.path.join(RAIZ, 'sql', n)) for n in MIG)
escribir(os.path.join(RAIZ, f'migracion_{NOMBRE}_editor.sql'), 'begin;\n' + cuerpo + 'commit;\n')
escribir(os.path.join(RAIZ, f'ensayo_en_transaccion_{NOMBRE}_editor.sql'), 'begin;\n' + cuerpo + leer(os.path.join(RAIZ, 'sql', '70_pruebas.sql')) + 'rollback;\n')

copia('ptar_g3')
p = corre('ptar_g3', os.path.join(RAIZ, f'migracion_{NOMBRE}_editor.sql'))
if p.returncode != 0:
    raise SystemExit('La migración falló:\n' + p.stderr[-3000:])
assert q(HUELLA_REDES, 'ptar_g3') == MD5_REDES, 'PTAR-3 no debe cambiar la huella de redes'
firmas = [q(f"select '{f}'::regprocedure::text", 'ptar_g3') for f in REEMPLAZADAS + NUEVAS]
despues = {f: md5(f, 'ptar_g3') for f in firmas}
restaurar = '\n'.join(d.rstrip() + ';' for d in defs_antes.values())
comprobar = ' or '.join(f"md5(pg_get_functiondef('{f}'::regprocedure)) <> '{antes[f]}'" for f in REEMPLAZADAS)
v.update({'{{FIRMAS}}': ', '.join(f"'{f}'" for f in firmas), '{{CASOS}}': ' '.join(f"when '{f}' then '{m}'" for f, m in despues.items()), '{{N_FUNC}}': str(len(firmas)),
          '{{RESTAURAR}}': restaurar, '{{COMPROBAR}}': comprobar, '{{MD5_FORMULARIOS_DESPUES}}': despues['tecnica.f_formularios()'],
          '{{MD5_CAPTURA_DESPUES}}': despues['tecnica.f_autorizar_captura(text,text)']})
for n, archivo in (('05_huellas_solo_lectura.sql', f'huellas_solo_lectura_{NOMBRE}_editor.sql'), ('80_verificacion.sql', f'verificacion_{NOMBRE}_editor.sql')):
    t = plantilla(n, v); escribir(os.path.join(RAIZ, 'sql', n), t); escribir(os.path.join(RAIZ, archivo), t)
t = plantilla('90_reversa.sql', v); escribir(os.path.join(RAIZ, 'sql', '90_reversa.sql'), t)
escribir(os.path.join(RAIZ, f'reversa_{NOMBRE}_editor.sql'), 'begin;\n' + t + 'commit;\n')

informe = []
p = corre('ptar_g3', os.path.join(RAIZ, f'verificacion_{NOMBRE}_editor.sql'))
informe += ['== verificación tras la migración', p.stdout.strip()]
assert p.returncode == 0 and 'REVISAR' not in p.stdout, p.stdout + p.stderr
p = corre('ptar_g3', os.path.join(CARGA, 'carga_ptar_el_salguero_editor.sql'))
assert p.returncode == 0, p.stderr
informe += ['== carga del mapa (después de PTAR-3)', p.stderr.strip()]
p = corre('ptar_g3', os.path.join(CARGA, 'verificacion_carga_ptar_el_salguero_editor.sql'))
informe += ['== verificación de la carga', p.stdout.strip()]
assert p.returncode == 0 and 'REVISAR' not in p.stdout, p.stdout
p = corre('ptar_g3', os.path.join(AQUI, 'arnes_control.sql'))
informe += ['== arnés del Sistema de Control (un año de Caracterización; service_role, 30 s y 8 s)', (p.stderr or '').strip()]
assert p.returncode != 0 and 'SIN FALLAS' in p.stderr, p.stdout + p.stderr
# reversa: con registros se detiene; en limpio deja las funciones como estaban
copia('ptar_g3')
assert corre('ptar_g3', os.path.join(RAIZ, f'migracion_{NOMBRE}_editor.sql')).returncode == 0
q("insert into tecnica.registros (lote_id, formulario, variable_id, punto_id, valor, fecha_muestra, hora_muestra, autor) select gen_random_uuid(), 'ptar_caracterizacion', v.id, p.id, 1, "
  "(clock_timestamp() at time zone 'America/Bogota')::date, '00:00', 'prueba.reversa@emdupar.gov.co' from tecnica.variables v, tecnica.puntos p where v.codigo = 'ar_caudal' and p.codigo = 'PTAR-AFL'", 'ptar_g3')
p = corre('ptar_g3', os.path.join(RAIZ, f'reversa_{NOMBRE}_editor.sql'))
assert p.returncode != 0 and 'ya tiene registros' in p.stderr, p.stderr
informe += ['== reversa con registros: se detiene (esperado)']
copia('ptar_g3')
assert corre('ptar_g3', os.path.join(RAIZ, f'migracion_{NOMBRE}_editor.sql')).returncode == 0
p = corre('ptar_g3', os.path.join(RAIZ, f'reversa_{NOMBRE}_editor.sql'))
assert p.returncode == 0, p.stderr
assert all(md5(f, 'ptar_g3') == antes[f] for f in REEMPLAZADAS) and q(HUELLA_REDES, 'ptar_g3') == MD5_REDES
assert q("select count(*) from tecnica.puntos where tipo = 'ptar' and activo", 'ptar_g3') == '0' and q("select count(*) from tecnica.f_formularios()", 'ptar_g3') == '9'
informe += ['== reversa en limpio: las 5 funciones vuelven a su md5, las 2 nuevas se quitan, puntos y variables quedan inactivos; redes sin cambio']
copia('ptar_g3')
p = corre('ptar_g3', os.path.join(RAIZ, f'ensayo_en_transaccion_{NOMBRE}_editor.sql'))
res = (p.stderr or '').strip()
informe += ['== ensayo', res]
assert p.returncode != 0 and 'SIN FALLAS' in res, res
assert q("select count(*) from tecnica.puntos where codigo like 'PTAR-%'", 'ptar_g3') == '0', 'el ensayo dejó algo'
subprocess.run([PSQL, '-qX', '-d', 'postgres', '-c', 'drop database if exists ptar_g3'], check=True, capture_output=True)
resumen = f"redes {MD5_REDES} (no cambia) · f_formularios {antes['tecnica.f_formularios()']} → {despues['tecnica.f_formularios()']} · f_autorizar_captura {antes['tecnica.f_autorizar_captura(text,text)']} → {despues['tecnica.f_autorizar_captura(text,text)']} · {len(firmas)} funciones"
informe.insert(0, resumen)
escribir(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), '\n'.join(informe) + '\n')
print(resumen)
print(re.search(r'RESULTADO: .*', res).group(0))
