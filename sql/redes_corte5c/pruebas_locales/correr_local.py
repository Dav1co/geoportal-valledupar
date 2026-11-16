#!/usr/bin/env python3
"""Arnés local del Corte 5c (PostGIS de Homebrew, base redes_local en localhost:55432). Resultado «N de N».
Como en el despliegue (1a con la carga real, Cortes 2 a 5b y la primera carga MUE de los 27 puntos publicada):
huellas antes · ensayo (ERROR esperado y sin rastro) · migración · verificación · guardia · huellas después · reversa vacía (exacta al 5b) · migrar de nuevo ·
recarga del acueducto real con un tramo editado en la ficha y «Devolver este campo a la capa» · 8.753 pozos reales en EPSG 9377 a una capa sin llave y su
recarga en WGS 84 (cruce por geometría de puntos) · 9.064 conductos reales sin llave, dos veces (cruce por geometría de líneas) · la capa MUE desde la
pantalla · verificación con datos · reversa con datos (rechazo).
Uso: python3 -I correr_local.py   → escribe ../resultados/sql_local.txt
"""
import json
import os
import re
import subprocess
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
C1A = os.environ.get('C1A', os.path.expanduser('~/geoportal-emdupar-tec-c1a/sql/redes_corte1a'))
C5A = os.path.join(os.path.dirname(RAIZ), 'redes_corte5a')
C5B = os.path.join(os.path.dirname(RAIZ), 'redes_corte5b')
MUE = os.path.join(C5A, 'carga_mue', 'generado')
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
ADMIN = 'carga.local@emdupar.gov.co'
res = []


def archivo(nombre, extra=None, cwd=None):
    t = time.time()
    p = subprocess.run([PSQL, '-d', 'redes_local', '-X', '-v', 'ON_ERROR_STOP=1'] + (extra or []) + ['-f', nombre], env=ENV, capture_output=True, text=True, cwd=cwd)
    return p.returncode, p.stdout + p.stderr, time.time() - t


def q(sql):
    p = subprocess.run([PSQL, '-d', 'redes_local', '-AtX', '-c', sql], env=ENV, capture_output=True, text=True)
    return (p.stdout.strip() if p.returncode == 0 else 'ERROR: ' + p.stderr.strip())


def qj(sql):
    r = q(sql)
    return json.loads(r) if r.startswith('{') else {'_error': r}


def reg(nombre, ok, detalle=''):
    res.append((nombre, bool(ok), detalle))
    print(('OK   ' if ok else 'FALLA'), nombre, ('· ' + detalle if detalle else ''))


ED = lambda n: os.path.join(RAIZ, n)  # noqa: E731
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
CHECK = "select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'tecnica.puntos_ubicacion'::regclass and conname = 'puntos_ubicacion_fuente_check'"


def cargar_desde_sql(capa, huella, llave, srid, filas_sql):
    """Abre una carga con la RPC de la pantalla y le pasa los lotes de 200 filas armados en la base con filas_sql (orden, wkt, atributos)."""
    sql = f"""
create temp table _f as {filas_sql};
select count(*) as n from _f \\gset
select (public.geoportal_redes_cargue_iniciar('{ADMIN}', '{capa}', encode(sha256(convert_to('{huella}', 'UTF8')), 'hex'), 'shp', {srid}, '{llave}', :n, 'Arnés del Corte 5c') ->> 'carga_id') as c \\gset
select set_config('arnes.carga', :'c', false);
do $$ declare i integer; begin
  for i in 0 .. ((select count(*) from _f) - 1) / 200 loop
    perform public.geoportal_redes_carga_lote('{ADMIN}', current_setting('arnes.carga')::bigint, (select jsonb_agg(jsonb_build_object('orden', orden, 'wkt', wkt, 'atributos', atributos)) from _f where orden > i * 200 and orden <= (i + 1) * 200));
  end loop; end $$;
select :c;
"""
    t = time.time()
    p = subprocess.run([PSQL, '-d', 'redes_local', '-AtX', '-v', 'ON_ERROR_STOP=1'], input=sql, env=ENV, capture_output=True, text=True)
    return (p.stdout.strip().splitlines() or ['ERROR'])[-1] if p.returncode == 0 else 'ERROR: ' + p.stderr[-400:], time.time() - t


# ---------- 01. como en la base viva al publicar ----------
subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_5b'], env=ENV, check=True, capture_output=True)
GEN = os.path.join(C1A, 'carga', 'generado')
rc1, _, _ = archivo('carga_inicial_todo.sql', ['-v', f'solicitante={ADMIN}'], cwd=GEN)
rc2, _, _ = archivo('publicar.sql', ['-v', f'solicitante={ADMIN}'], cwd=GEN)
rc3, _, _ = archivo('carga_mue_todo.sql', ['-v', f'solicitante={ADMIN}'], cwd=MUE)
rc4, out4, _ = archivo('publicar_mue.sql', ['-v', f'solicitante={ADMIN}'], cwd=MUE)
reg('01 como en la base viva al publicar: carga real (35.781 activos), la primera carga MUE (27 puntos) y el 5b aplicado',
    rc1 == rc2 == rc3 == rc4 == 0 and q('select count(*) from redes.activo_vigente_mat') == '35781' and q('select count(*) from redes.v_punto_ubicacion_vigente') == '27'
    and q("select to_regclass('tecnica.punto_ubicacion_propuestas') is not null") == 't', out4[-300:] if rc4 else '')
md5_5b = q(CONJ)
check_5b = q(CHECK)
rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte5c_editor.sql'))
reg('02 huellas antes: «CORTE 5b (listo para el 5c)», 6 RPC y 2 tablas «NO EXISTE», 8 «CORTE 5b (sin cambiar)»', rc == 0
    and 'CORTE 5b (listo para el 5c)' in out and out.count('NO EXISTE (sin aplicar)') == 8 and out.count('CORTE 5b (sin cambiar)') == 8 and 'DISTINTA' not in out)
ubic0 = q('select count(*) from tecnica.puntos_ubicacion')
cargas0 = q('select count(*) from redes.cargas')
rc, out, seg = archivo(ED('ensayo_en_transaccion_redes_corte5c_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
reg('03 ensayo DESPUÉS de la carga real y la MUE: ERROR con «N de N … SIN FALLAS»', rc != 0 and m and m.group(1) == m.group(2) and m.group(3).startswith('SIN FALLAS'),
    (m.group(0) if m else out[-800:]) + f' ({seg:.1f} s)')
reg('04 el ensayo no deja rastro (ni tablas, ni funciones, ni CHECK, ni capas, ni cargas, ni ubicaciones, ni puntos de prueba)',
    q("select to_regclass('redes.ficha_campo_devoluciones') is null") == 't' and q(CONJ) == md5_5b and q(CHECK) == check_5b
    and q("select count(*) from redes.capas where codigo = 'sensores'") == '0' and q('select count(*) from redes.cargas') == cargas0
    and q('select count(*) from tecnica.puntos_ubicacion') == ubic0 and q("select count(*) from tecnica.puntos where codigo like 'MUE-97%'") == '0')
rc, out, seg = archivo(ED('migracion_redes_corte5c_editor.sql'))
reg('05 migración _editor', rc == 0, f'{seg:.1f} s' if rc == 0 else out[-400:])
rc, out, _ = archivo(ED('verificacion_redes_corte5c_editor.sql'))
reg('06 verificación: 9 OK (la 09 reproyecta un punto en EPSG 9377 en esta base)', rc == 0 and out.count('| OK') == 9 and '| MAL' not in out, '' if rc == 0 else out[-300:])
rc, out, _ = archivo(ED('migracion_redes_corte5c_editor.sql'))
reg('07 repetir la migración se rechaza (guardia)', rc != 0 and 'deténgase' in out)
rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte5c_editor.sql'))
reg('08 huellas después: «CORTE 5c (aplicado)», 6 «NUEVA», 8 «CORTE 5c (reemplazada)» y 2 «EXISTE»', 'CORTE 5c (aplicado)' in out and out.count('NUEVA (aplicada)') == 6
    and out.count('CORTE 5c (reemplazada)') == 8 and out.count('EXISTE (aplicado)') == 2 and 'DISTINTA' not in out)
rc, out, _ = archivo(os.path.join(C5B, 'verificacion_redes_corte5b_editor.sql'))
reg('09 la verificación del 5b, con el 5c aplicado: solo las filas 03 y 05 dicen MAL (a propósito: hay 5 RPC geoportal_tec_punto* y cambió el conjunto de funciones)',
    out.count('| MAL') == 2 and re.search(r'03 las 4 RPC[^\n]*\| MAL', out) is not None and re.search(r'05 huellas[^\n]*\| MAL', out) is not None)
rc, out, _ = archivo(ED('reversa_redes_corte5c_editor.sql'))
reg('10 reversa vacía: las funciones y el CHECK quedan exactos al 5b; las capas nuevas, inactivas', rc == 0 and q(CONJ) == md5_5b and q(CHECK) == check_5b
    and q("select count(*) from redes.capas where codigo = 'sensores' and not activa") == '1', out[-300:] if rc else '')
rc, out, _ = archivo(os.path.join(C5B, 'verificacion_redes_corte5b_editor.sql'))
reg('11 después de la reversa, la verificación del 5b vuelve a dar todo OK', out.count('| OK') == 8 and '| MAL' not in out)
rc, out, _ = archivo(ED('migracion_redes_corte5c_editor.sql'))
rc2, out2, _ = archivo(ED('verificacion_redes_corte5c_editor.sql'))
reg('12 migrar de nuevo: 9 OK (las capas nuevas vuelven a quedar activas)', rc == 0 and out2.count('| OK') == 9, out[-300:] if rc else '')

# ---------- 13. recarga real del acueducto con un tramo editado en la ficha: el choque y «Devolver este campo a la capa» ----------
red = q("select codigo || '|' || diametro_mm from redes.activo_vigente_mat where codigo_anterior = 'Distribucion-8435'").split('|')
q(f"""select public.geoportal_redes_ficha_editar('{ADMIN}', '{red[0]}', '{{"diametro_mm": 250}}', 'Lo midió la cuadrilla al reparar')""")
n_acu = int(q("select filas_esperadas from redes.cargas where capa_codigo = 'acueducto' order by id limit 1"))
import tempfile
maestro = os.path.join(tempfile.mkdtemp(prefix='recarga_5c_'), 'recarga_acueducto.sql')      # fuera de los repositorios
lotes = sorted(f for f in os.listdir(os.path.join(GEN, 'lotes')) if f.startswith('acueducto_'))
open(maestro, 'w', encoding='utf-8').write(
    "\\set ON_ERROR_STOP 1\n\\set QUIET 1\n"
    f"select (public.geoportal_redes_cargue_iniciar(:'solicitante', 'acueducto', '{'5c' * 32}', 'shp', 4326, 'ID', {n_acu}, 'Recarga de prueba del Corte 5c', null) ->> 'carga_id') as carga_acueducto \\gset\n"
    "\\o /dev/null\n" + ''.join(f'\\ir {os.path.join(GEN, "lotes", f)}\n' for f in lotes) + "\\o\n")
rc, out, seg_l = archivo(maestro, ['-v', f'solicitante={ADMIN}'])
os.remove(maestro)
carga = q("select id from redes.v_cargas_estado where capa_codigo = 'acueducto' and estado = 'abierta'")
t0 = time.time(); rj = qj(f"select public.geoportal_redes_carga_resumen('{ADMIN}', {carga})"); seg_r = time.time() - t0
ch = [c for c in rj.get('choques', []) if c['codigo'] == red[0]]
reg('13 recarga real del acueducto (10.578 tramos) desde la RPC de la pantalla: el choque del diámetro (ficha 250 / capa) y nada más cambia',
    rc == 0 and len(ch) == 1 and ch[0]['campo'] == 'diametro_mm' and ch[0]['ficha'] == '250' and ch[0]['capa'] == red[1] and rj.get('lista_para_publicar')
    and set(rj['frente_a_vigente']) == {'igual'}, f'lotes {seg_l:.1f} s, resumen {seg_r:.1f} s · ' + json.dumps(rj.get('choques'), ensure_ascii=False)[:200] + ' · ' + json.dumps(rj.get('frente_a_vigente')))
r = qj(f"select public.geoportal_redes_carga_devolver_campo('{ADMIN}', {carga}, '{red[0]}', 'diametro_mm', 'Técnica corrigió el diámetro en el modelo')")
t0 = time.time(); rj = qj(f"select public.geoportal_redes_carga_resumen('{ADMIN}', {carga})"); seg_r = time.time() - t0
reg('14 «Devolver este campo a la capa»: el resumen otra vez, sin el choque y con ese tramo «cambiado»', r.get('valor_ficha') == '250' and rj.get('choques') == []
    and rj['frente_a_vigente'].get('cambiado') == 1, f'resumen {seg_r:.1f} s · ' + json.dumps(rj.get('frente_a_vigente')))
t0 = time.time(); r = qj(f"select public.geoportal_redes_carga_publicar('{ADMIN}', {carga}, 'Recarga de prueba del Corte 5c')"); seg_p = time.time() - t0
reg('15 publicar: el tramo vuelve al diámetro de la capa (versión nueva), nada se retira, el muro conserva la edición',
    r.get('cambiados') == 1 and r.get('retirados') == 0 and q(f"select diametro_mm from redes.v_activo_vigente where codigo = '{red[0]}'") == red[1]
    and q(f"select count(*) from redes.ficha_ediciones e join redes.activos a on a.id = e.activo_id where a.codigo = '{red[0]}'") == '1', f'publicar {seg_p:.1f} s · ' + json.dumps(r)[:200])

# ---------- 16-17. pozos reales en EPSG 9377 a una capa sin llave, y su recarga en WGS 84 (cruce por geometría de puntos) ----------
c, seg = cargar_desde_sql('sumideros', 'arnes-5c-sum-9377', '(geometria)', 9377,
    "select row_number() over (order by codigo)::integer as orden, ST_AsText(ST_Transform(geom, '+proj=tmerc +lat_0=4 +lon_0=-73 +k=0.9992 +x_0=5000000 +y_0=2000000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs')) as wkt, "
    "jsonb_build_object('NOMBRE', codigo) as atributos from redes.activo_vigente_mat where prefijo = 'POZ' and not retirado")
n_poz = int(q("select count(*) from redes.activo_vigente_mat where prefijo = 'POZ' and not retirado"))
t0 = time.time(); rj = qj(f"select public.geoportal_redes_carga_resumen('{ADMIN}', {c})"); seg_r = time.time() - t0
dif = q(f"select round(max(ST_Distance(f.geom::geography, m.geom::geography))::numeric, 3) from redes.carga_filas f join redes.activo_vigente_mat m on m.codigo = f.atributos ->> 'NOMBRE' where f.carga_id = {c}") if c.isdigit() else '?'
reg(f'16 {n_poz} pozos reales en EPSG 9377 (Origen Nacional), sin columna llave: sin errores de geometría, todos nuevos, y a menos de 1 cm de su lugar',
    c.isdigit() and rj.get('errores') == 0 and rj['frente_a_vigente'] == {'nuevo': n_poz} and rj.get('lista_para_publicar') and float(dif) < 0.01,
    f'lotes {seg:.1f} s, resumen {seg_r:.1f} s, máx. {dif} m · ' + json.dumps(rj.get('bloqueos'), ensure_ascii=False)[:200])
t0 = time.time(); r = qj(f"select public.geoportal_redes_carga_publicar('{ADMIN}', {c}, 'Arnés del Corte 5c: sumideros de prueba')"); seg_p = time.time() - t0
c, seg = cargar_desde_sql('sumideros', 'arnes-5c-sum-4326', '(geometria)', 4326,
    "select row_number() over (order by codigo desc)::integer as orden, ST_AsText(geom) as wkt, jsonb_build_object('NOMBRE', codigo) as atributos "
    "from redes.activo_vigente_mat where prefijo = 'POZ' and not retirado")
t0 = time.time(); rj = qj(f"select public.geoportal_redes_carga_resumen('{ADMIN}', {c})"); seg_r = time.time() - t0
reg('17 la recarga de los mismos pozos en WGS 84 y en otro orden: todos se cruzan por geometría con el suyo, sin nuevos ni retiros',
    r.get('nuevos') == n_poz and rj.get('detalle', {}).get('cruce_por_geometria', {}).get('cruzados') == n_poz and rj.get('retirados') == 0
    and 'nuevo' not in rj['frente_a_vigente'], f'publicar {seg_p:.1f} s · lotes {seg:.1f} s, resumen {seg_r:.1f} s · ' + json.dumps(rj.get('frente_a_vigente')))
q(f"select public.geoportal_redes_carga_anular('{ADMIN}', {c}, 'Arnés del Corte 5c: no se publica')")

# ---------- 18-19. conductos reales sin llave, dos veces (cruce por geometría de líneas, con Hausdorff) ----------
FIL_COL = ("select row_number() over (order by codigo)::integer as orden, ST_AsText(geom) as wkt, jsonb_build_object('MATERIAL', material_codigo, 'DIAMETRO', diametro_mm) as atributos "
           "from redes.activo_vigente_mat where prefijo = 'COL' and not retirado")
n_col = int(q("select count(*) from redes.activo_vigente_mat where prefijo = 'COL' and not retirado"))
c, seg = cargar_desde_sql('interceptores', 'arnes-5c-int-1', '(geometria)', 4326, FIL_COL)
t0 = time.time(); r = qj(f"select public.geoportal_redes_carga_publicar('{ADMIN}', {c}, 'Arnés del Corte 5c: interceptores de prueba')"); seg_p = time.time() - t0
reg(f'18 {n_col} conductos reales a una capa de líneas sin llave: se publican todos como nuevos (INT)', r.get('nuevos') == n_col, f'lotes {seg:.1f} s, publicar {seg_p:.1f} s')
c, seg = cargar_desde_sql('interceptores', 'arnes-5c-int-2', '(geometria)', 4326, FIL_COL.replace('order by codigo', 'order by codigo desc'))
t0 = time.time(); rj = qj(f"select public.geoportal_redes_carga_resumen('{ADMIN}', {c})"); seg_r = time.time() - t0
reg('19 la recarga del mismo archivo en otro orden: todas las líneas se cruzan (Hausdorff) y quedan iguales',
    rj.get('detalle', {}).get('cruce_por_geometria', {}).get('cruzados') == n_col and rj['frente_a_vigente'] == {'igual': n_col} and rj.get('retirados') == 0,
    f'lotes {seg:.1f} s, resumen {seg_r:.1f} s · ' + json.dumps(rj.get('frente_a_vigente')))
q(f"select public.geoportal_redes_carga_anular('{ADMIN}', {c}, 'Arnés del Corte 5c: no se publica')")

# ---------- 20. la capa MUE desde la pantalla, con el archivo de la primera carga ----------
c, seg = cargar_desde_sql('muestreo', 'arnes-5c-mue', 'codigo', 4326,
    "select row_number() over (order by p.codigo)::integer as orden, format('POINT(%s %s)', u.lon, u.lat) as wkt, "
    "jsonb_build_object('codigo', p.codigo, 'nombre', p.nombre, 'barrio', u.barrio_capa, 'exactitud', u.exactitud, 'fuente', case when u.fuente = 'david' then 'david' else 'barrio' end) as atributos "
    "from tecnica.puntos p join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id where p.tipo = 'muestreo' and p.activo")
rj = qj(f"select public.geoportal_redes_carga_resumen('{ADMIN}', {c})")
reg('20 la capa MUE desde la RPC de la pantalla, con lo vigente: los 27 «igual», lista para publicar', rj.get('frente_a_vigente') == {'igual': 27} and rj.get('lista_para_publicar'),
    json.dumps(rj.get('frente_a_vigente')) + ' ' + json.dumps(rj.get('bloqueos'), ensure_ascii=False)[:200])
q(f"select public.geoportal_redes_carga_anular('{ADMIN}', {c}, 'Arnés del Corte 5c: no se publica')")

rc, out, _ = archivo(ED('verificacion_redes_corte5c_editor.sql'))
reg('21 verificación con datos: 9 OK (1 devolución y 0 correcciones)', out.count('| OK') == 9 and '| MAL' not in out and '1 · 0 · 0' in out, '' if out.count('| OK') == 9 else out[-400:])
rc, out, _ = archivo(ED('reversa_redes_corte5c_editor.sql'))
reg('22 la reversa con datos se niega (nada se borra)', rc != 0 and 'se niega' in out and q("select to_regclass('redes.ficha_campo_devoluciones') is not null") == 't')

bien = sum(1 for _, ok, _ in res if ok)
lineas = [('OK    ' if ok else 'FALLA ') + n + (' · ' + d if d else '') for n, ok, d in res]
lineas.append(f'RESULTADO: {bien} de {len(res)}')
os.makedirs(os.path.join(RAIZ, 'resultados'), exist_ok=True)
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write('\n'.join(lineas) + '\n')
print(f'RESULTADO: {bien} de {len(res)}')
