#!/usr/bin/env python3
"""Arnés local del Corte 9a (base de Code B: emdupar_b en localhost:55442; nunca la de Code A). Resultado «N de N».
Recorre el camino de la publicación con la base como producción (hasta el 7a, volumen real: 35.781 activos y 111.950 contratos sintéticos):
huellas → ensayo (sin rastro) → migración → verificación → guardia → reversa exacta → migrar de nuevo → ensayo de la carga (sin rastro) → carga y publicación
del Plan Maestro → no se carga dos veces → verificación de la carga → la reversa se niega con datos → las RPC como las llama la Edge (service_role, 30 s y 8 s).
Uso: python3 -I correr_local.py"""
import os
import re
import subprocess
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
GEN = os.path.join(RAIZ, 'carga_pm', 'generado')
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = os.environ.get('BASE_B', 'emdupar_b')
ENV = dict(os.environ, PGHOST='localhost', PGPORT=os.environ.get('PGPORT_B', '55442'), PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
assert ENV['PGPORT'] != '55432', 'El puerto 55432 es de Code A'
ADMIN = 'carga.local@emdupar.gov.co'
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
EDGE = ['-c', 'set role service_role', '-c', "set statement_timeout = '30s'", '-c', "set lock_timeout = '8s'"]
res = []


def ok(nombre, cond, det=''):
    res.append((nombre, bool(cond), str(det)[:400]))
    print(('OK    ' if cond else 'FALLA ') + nombre + ('' if cond else ' → ' + str(det)[:400]), flush=True)


def archivo(nombre, cwd=RAIZ, var=None):
    t0 = time.time()
    p = subprocess.run([PSQL, '-d', BASE, '-X', '-v', 'ON_ERROR_STOP=1'] + (['-v', var] if var else []) + ['-f', nombre], env=ENV, capture_output=True, text=True, cwd=cwd)
    return p.returncode, p.stdout + p.stderr, time.time() - t0


def q(sql):
    p = subprocess.run([PSQL, '-d', BASE, '-AtX', '-c', sql], env=ENV, capture_output=True, text=True)
    return (p.stdout + p.stderr).strip()


def edge(sql):
    """Como la Edge: rol service_role, 30 s por sentencia y 8 s de espera de candados. Devuelve (texto, error, milisegundos)."""
    t0 = time.time()
    p = subprocess.run([PSQL, '-d', BASE, '-AtqX', '-v', 'ON_ERROR_STOP=1', *EDGE, '-c', sql], env=ENV, capture_output=True, text=True)
    return p.stdout.strip(), p.stderr.strip(), round((time.time() - t0) * 1000)


def rastro():
    return q("select (select count(*) from public.geoportal_lista_blanca where email like 'prueba.redes13.%') || '|' || (select count(*) from redes.activos) || '|' || (select count(*) from redes.activo_eventos)"
             " || '|' || (select count(*) from redes.nodo_eventos) || '|' || (select count(*) from public.geoportal_auditoria) || '|' || (select count(*) from redes.cargas)")


subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=ENV, check=True, capture_output=True)
MD5_BASE = re.search(r"when '([0-9a-f]{32})' then 'CORTE 7a \(listo para el 9a\)'", open(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte9a_editor.sql'), encoding='utf-8').read()).group(1)
MD5_9A = re.search(r"when '([0-9a-f]{32})' then 'CORTE 9a \(aplicado\)'", open(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte9a_editor.sql'), encoding='utf-8').read()).group(1)

# ---- 1. antes de aplicar
ok('01 la base local es como producción hoy: huella del conjunto de redes del 7a publicado', q(CONJ) == MD5_BASE, q(CONJ))
ok('02 volumen real: 35.781 activos vigentes y más de 111 mil contratos en el catastro', q("select count(*) from redes.activo_vigente_mat where not retirado") == '35781'
   and int(q("select count(distinct cod_usuario) from public.catastro_valledupar")) > 111000, q("select count(*) from redes.activo_vigente_mat where not retirado"))
_, t, _ = archivo('huellas_solo_lectura_redes_corte9a_editor.sql')
ok('03 huellas ANTES: «CORTE 7a (listo para el 9a)», 6 «sin cambiar», 13 «NO EXISTE», la vista «CORTE 1a» y nada «DISTINTA» ni «FALTA»',
   'CORTE 7a (listo para el 9a)' in t and t.count('CORTE 7a (sin cambiar)') == 6 and t.count('NO EXISTE (sin aplicar)') == 23 and 'CORTE 1a (sin cambiar)' in t and 'DISTINTA' not in t and 'FALTA' not in t, t[-600:])
r0 = rastro()
c, t, s = archivo('ensayo_en_transaccion_redes_corte9a_editor.sql')
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', t)
ok(f'04 ensayo en transacción: termina en ERROR con «{m.group(1) if m else "?"} de {m.group(2) if m else "?"} … SIN FALLAS» ({s:.1f} s)', c != 0 and m and m.group(1) == m.group(2) and m.group(3).startswith('SIN FALLAS'), t[-900:])
print('     ' + (re.search(r'TIEMPOS:.*', t).group(0) if re.search(r'TIEMPOS:.*', t) else ''))
ok('05 el ensayo no deja rastro (ni personas, ni activos, ni eventos, ni auditoría) y el 9a sigue sin aplicar', rastro() == r0 and q("select to_regclass('redes.ref_cargas') is null") == 't' and q(CONJ) == MD5_BASE, rastro())

# ---- 2. migración
c, t, s = archivo('migracion_redes_corte9a_editor.sql')
ok(f'06 la migración aplica en una transacción ({s:.1f} s)', c == 0, t[-500:])
ok('07 huella del conjunto de redes del 9a', q(CONJ) == MD5_9A, q(CONJ))
_, t, _ = archivo('verificacion_redes_corte9a_editor.sql')
ok('08 verificación: 9 OK y ninguna MAL (antes de la carga)', len(re.findall(r'\| OK', t)) == 9 and 'MAL' not in t, t[-900:])
_, t, _ = archivo('huellas_solo_lectura_redes_corte9a_editor.sql')
ok('09 huellas DESPUÉS: «CORTE 9a (aplicado)», 6 «reemplazada», 13 «NUEVA», 10 tablas y la vista «CORTE 9a»',
   'CORTE 9a (aplicado)' in t and t.count('CORTE 9a (reemplazada)') == 6 and t.count('NUEVA (aplicada)') == 13 and t.count('EXISTE (aplicado)') == 10 and 'CORTE 9a (aplicada)' in t and 'DISTINTA' not in t, t[-600:])
c, t, _ = archivo('migracion_redes_corte9a_editor.sql')
ok('10 guardia: migrar dos veces se niega («ya está aplicado»)', c != 0 and 'ya está aplicado' in t, t[-300:])
ok('11 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', q("select count(*) from redes.f_funciones_sin_where()") == '0')
ok('12 lo publicado sigue igual con el 9a: activos vigentes, nodos por clasificar (783) y ningún activo «por verificar» todavía',
   q("select count(*) from redes.activo_vigente_mat where not retirado") == '35781' and q("select count(*) from redes.v_nodo_vigente where clase_nodo = 'por_clasificar'") == '783'
   and q("select count(*) from redes.v_activo_estado where por_verificar") == '0')

# ---- 3. reversa exacta y volver a migrar
c, t, _ = archivo('reversa_redes_corte9a_editor.sql')
ok('13 la reversa (sin datos cargados) deja las funciones y la vista de nodos EXACTAS como en el 7a', c == 0 and q(CONJ) == MD5_BASE and q("select to_regclass('redes.ref_cargas') is null") == 't'
   and q("select count(*) from information_schema.columns where table_schema = 'redes' and table_name = 'nodo_eventos' and column_name = 'clase'") == '0', t[-400:])
_, t, _ = archivo('huellas_solo_lectura_redes_corte9a_editor.sql')
ok('14 después de la reversa, las huellas vuelven a decir «CORTE 7a (listo para el 9a)» y la vista «CORTE 1a»', 'CORTE 7a (listo para el 9a)' in t and 'CORTE 1a (sin cambiar)' in t and 'DISTINTA' not in t, t[-500:])
c, t, _ = archivo('migracion_redes_corte9a_editor.sql')
ok('15 se puede migrar de nuevo después de la reversa (las siembras son repetibles) y la huella es la misma', c == 0 and q(CONJ) == MD5_9A, t[-400:])

# ---- 4. la carga del Plan Maestro
r0 = rastro() + '|' + q("select count(*) from redes.ref_cargas")
c, t, s = archivo('ensayo_carga_pm.sql', GEN, f'solicitante={ADMIN}')
m = re.search(r'RESULTADO: (\d+) de (\d+) comprobaciones correctas — (.*)', t)
ok(f'16 ensayo de la carga: termina en ERROR con «{m.group(1) if m else "?"} de {m.group(2) if m else "?"} … SIN FALLAS» ({s:.1f} s en local)', m and m.group(1) == m.group(2) and m.group(3).startswith('SIN FALLAS') and 'ENSAYO' in t, t[-900:])
ok('17 el ensayo de la carga no deja rastro', rastro() + '|' + q("select count(*) from redes.ref_cargas") == r0)
c, t, s1 = archivo('carga_pm_todo.sql', GEN, f'solicitante={ADMIN}')
ok(f'18 carga_pm_todo.sql: las 12 cargas de referencia y las cargas del motor abiertas, «lista para publicar: SÍ» en las dos ({s1:.1f} s en local)',
   c == 0 and q("select count(*) from redes.v_ref_carga_vigente") == '12' and len(re.findall(r'lista para publicar\s*\|\s*SÍ', t)) == 2, t[-600:])
ok('19 hasta aquí nada cambió en los activos: los sectores y sumideros no están publicados', q("select count(*) from redes.activo_vigente_mat where prefijo in ('SEC', 'SUM')") == '0')
c, t, s2 = archivo('publicar_pm.sql', GEN, f'solicitante={ADMIN}')
n_ok = len(re.findall(r'^\s*\d+ \| OK ', t, re.M))      # (el arnés calla los NOTICE; en producción el último renglón dice «15 de 15 … SIN FALLAS»)
ok(f'20 publicar_pm.sql: termina bien, con sus {n_ok} comprobaciones en OK y ninguna FALLA ({s2:.1f} s en local)', c == 0 and n_ok == 15 and 'FALLA' not in t, t[-900:])
c, t, _ = archivo('carga_pm_todo.sql', GEN, f'solicitante={ADMIN}')
ok('21 repetir la carga se niega (los mismos archivos por md5) y no duplica nada', c != 0 and 'ya están cargados con el mismo archivo' in t and q("select count(*) from redes.ref_cargas") == '12', t[-300:])
c, t, _ = archivo('carga_pm_todo.sql', GEN, 'solicitante=zt.dist@emdupar.gov.co')
ok('22 la carga solo la corre un administrador', c != 0 and 'no es de un administrador' in t, t[-300:])
_, t, _ = archivo('verificacion_carga_pm.sql', GEN)
ok('23 verificación de la carga: 15 OK y ninguna MAL', len(re.findall(r'\| OK', t)) == 15 and '| MAL' not in t, t[-900:])
_, t, _ = archivo('verificacion_redes_corte9a_editor.sql')
ok('24 la verificación del 9a sigue en 9 OK después de la carga', len(re.findall(r'\| OK', t)) == 9 and 'MAL' not in t, t[-600:])
ok('25 lo que quedó: 36.302 activos vigentes (35.781 + 36 SEC + 484 SUM + el tanque La Popa), 782 nodos por clasificar, 1.746 por verificar y el efecto de las 758 válvulas sin tocar',
   q("select count(*) from redes.activo_vigente_mat where not retirado") == '36302' and q("select count(*) from redes.v_nodo_vigente where clase_nodo = 'por_clasificar'") == '782'
   and q("select count(*) from redes.v_activo_estado where por_verificar") == '1746' and q("select count(*) from redes.activo_vigente_mat where prefijo = 'VAL' and version = 1") == '758',
   q("select count(*) from redes.activo_vigente_mat where not retirado"))
ok('26 «gana la ficha»: VAL-000001 («V85») sigue en su versión y con su alias', q("select version from redes.activo_vigente_mat where codigo = 'VAL-000001'")
   == q("select max(version) from redes.activo_versiones v join redes.activos a on a.id = v.activo_id where a.codigo = 'VAL-000001' and v.carga_id is null or (a.codigo = 'VAL-000001' and v.version = 1)"))
c, t, _ = archivo('reversa_redes_corte9a_editor.sql')
ok('27 con el Plan cargado, la reversa se niega (no borra datos) y no cambia nada', c != 0 and 'la reversa no borra datos' in t and q(CONJ) == MD5_9A, t[-300:])

# ---- 5. como las llama la Edge: service_role, statement_timeout 30 s y lock_timeout 8 s (tiempos en LOCAL: no son los de producción)
SD, AD, OPE = 'zt.dist@emdupar.gov.co', 'zt.admin@emdupar.gov.co', 'zt.oper@emdupar.gov.co'
tiempos = []


def medir(nombre, sql):
    t, e, ms = edge(sql)
    tiempos.append((nombre, ms))
    return t, e


t, e = medir('configuración del geovisor', f"select public.geoportal_redes_geovisor('{SD}')")
ok('28 Edge: la configuración del geovisor trae las 5 capas de referencia', e == '' and t.count('"fuente": "referencia"') == 5, e or t[:200])
# la tesela de zoom 13 con más nodos del modelo y las de la red a ese mismo recuadro
x, y = q("select floor((ST_X(geom) + 180) / 360 * 8192)::int || ' ' || floor((1 - ln(tan(radians(ST_Y(geom))) + 1 / cos(radians(ST_Y(geom)))) / pi()) / 2 * 8192)::int from redes.pm_nodos "
         "where pres_exist_mediana is not null group by 1 order by count(*) desc limit 1").split()
for capa in ('presion_modelo', 'pluvial', 'pluvial_2043', 'plan_valvulas', 'campana_2014'):
    for z, f in ((13, 1), (15, 4)):
        t, e = medir(f'tesela de {capa} z{z}', f"select length(public.geoportal_redes_geovisor_mvt_ref('{SD}', '{capa}', {z}, {int(x) * f}, {int(y) * f}))")
        if e:
            break
    if e:
        break
ok('29 Edge: las teselas de las 5 capas de referencia (z13, la más cargada de nodos del modelo, y z15) responden sin error', e == '', e)
t, e = medir('tesela de la red z13 con sectores', f"select length(public.geoportal_redes_geovisor_mvt('{SD}', 13, {x}, {y}))")
ok('30 Edge: la tesela de la red (ahora con los sectores y su nombre) responde y pesa menos de 700 KB en base64', e == '' and int(t) < 700 * 1024, e or t)
t, e = medir('tarjeta de la campaña (serie de 15 min)', f"select jsonb_array_length(public.geoportal_redes_referencia('{SD}', 'campana_2014', 'CAMP2014-P02') -> 'series' -> 0 -> 'puntos')")
ok('31 Edge: la tarjeta de la campaña trae la serie completa del punto 2 (661 lecturas)', e == '' and t == '661', e or t)
llave = q("select llave from redes.pm_presion_hora where escenario = 'existente' order by llave limit 1")
t, e = medir('tarjeta de presión de modelo', f"select public.geoportal_redes_referencia('{SD}', 'presion_modelo', '{llave}') ->> 'advertencia'")
ok('32 Edge: la tarjeta de presión dice «Presión de MODELO, no medida»', e == '' and t.startswith('Presión de MODELO, no medida'), e or t)
t, e = medir('bandeja por verificar', f"select public.geoportal_redes_por_verificar('{SD}', null, null, 50) ->> 'total'")
ok('33 Edge: la bandeja «Por verificar» (1.746)', e == '' and t == '1746', e or t)
t, e = medir('nodos por clasificar', f"select public.geoportal_redes_nodos_por_clasificar('{AD}', null, null, 50) -> 'sugerencias'")
ok('34 Edge: nodos por clasificar con sus sugerencias (500 no crear, 281 dejar como nodo, 1 crear)', e == '' and '"n": 500' in t and '"n": 281' in t and '"n": 1,' in t, e or t)
nodo = q("select nodo_id from redes.v_nodo_vigente where nombre_modelo = 'S3-437'")
t, e = medir('ficha preliminar de un nodo', f"select jsonb_array_length(public.geoportal_redes_nodo_preliminar('{AD}', {nodo}) -> 'tramos')")
ok('35 Edge: la ficha preliminar de un nodo trae sus tramos', e == '' and int(t or 0) >= 1, e or t)
val = q("select m.codigo from redes.v_pm_por_verificar x join redes.activo_vigente_mat m on m.activo_id = x.activo_id where x.grupo = 'valvula' order by 1 limit 1")
t, e = medir('ficha de una válvula con referencia', f"select jsonb_array_length(public.geoportal_redes_activo('{SD}', '{val}') -> 'referencia')")
ok('36 Edge: la ficha de una válvula trae la referencia del Plan (modelo, presión y sugerencia)', e == '' and int(t or 0) >= 2, e or t)
t, e = medir('ficha de un tramo (RED) con sector', f"select public.geoportal_redes_activo('{OPE}', 'RED-000960') -> 'sector_plan' ->> 'sector'")
ok('37 Edge: la ficha de un tramo real trae su sector según el Plan (también para el operador)', e == '' and t.isdigit(), e or t)
t, e = medir('lista de daños con sector', f"select jsonb_typeof(public.geoportal_redes_danos('{SD}', 'todos', 200) -> 'danos')")
ok('38 Edge: la lista de daños responde', e == '' and t == 'array', e or t)
t, e = edge(f"select public.geoportal_redes_nodo_clasificar('{AD}', {nodo}, 'propuesta_plan', 'Arnés: válvula del Plan que no se instaló') ->> 'clase_nodo'")[:2]
ok('39 Edge (escribe): clasificar un nodo sin crear activo pasa por la API (un insert con motivo; nada sin WHERE)', e == '' and t == 'propuesta_plan', e or t)
t, e = edge(f"select public.geoportal_redes_activo_verificar('{SD}', '{val}', 'Arnés: se revisó en campo y opera bien') ->> 'por_verificar'")[:2]
ok('40 Edge (escribe): marcar «verificado» pasa por la API', e == '' and t == 'false', e or t)
t, e = edge(f"select public.geoportal_redes_por_verificar('{OPE}')")[:2]
ok('41 Edge: el operador no ve la bandeja (42501)', 'Solo el supervisor' in e or '42501' in e, e or t)
peor = max(tiempos, key=lambda z: z[1])
ok(f'42 ninguna llamada pasó de 2 s en local con el volumen real (la más lenta: {peor[0]}, {peor[1]} ms, con el arranque de psql)', peor[1] < 2000, tiempos)
print('TIEMPOS (local, cada uno con el arranque de psql): ' + ' · '.join(f'{n} {ms} ms' for n, ms in tiempos))
print(f'TIEMPOS DE LA CARGA (local): carga_pm_todo.sql {s1:.1f} s · publicar_pm.sql {s2:.1f} s')

bien = sum(1 for r in res if r[1])
print('----')
print(f'RESULTADO: {bien} de {len(res)} — ' + ('SIN FALLAS' if bien == len(res) else f'{len(res) - bien} FALLA(S)'))
raise SystemExit(0 if bien == len(res) else 1)
