#!/usr/bin/env python3
"""Arnés local del Corte 4b (PostGIS de Homebrew, base redes_local en localhost:55432). Resultado «N de N».
Como en el despliegue (1a con la carga real, Cortes 2, 3a, 3b y 4a): huellas antes · carga real y hechos reales en V85 · ensayo (ERROR esperado y sin
rastro) · migración · verificación · guardia · huellas después · reversa vacía (exacta al 4a) · verificación del 4a · segunda reversa · migrar de nuevo ·
con la carga real: personal, nodos por clasificar (783), crear el activo de un nodo real, gráficas, descarga y un parámetro, con sus tiempos ·
verificación con datos · reversa con datos (rechazo).
Uso: python3 -I correr_local.py   → escribe ../resultados/sql_local.txt
"""
import os
import re
import subprocess
import sys
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
C1A = os.environ.get('C1A', os.path.expanduser('~/geoportal-emdupar-tec-c1a/sql/redes_corte1a'))
C4A = os.path.join(os.path.dirname(RAIZ), 'redes_corte4a')
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
ADMIN = 'carga.local@emdupar.gov.co'
OPER = 'zt.oper@emdupar.gov.co'
SUP = 'zt.dist@emdupar.gov.co'
res = []


def archivo(nombre, extra=None, cwd=None):
    t = time.time()
    p = subprocess.run([PSQL, '-d', 'redes_local', '-X', '-v', 'ON_ERROR_STOP=1'] + (extra or []) + ['-f', nombre], env=ENV, capture_output=True, text=True, cwd=cwd)
    return p.returncode, p.stdout + p.stderr, time.time() - t


def q(sql):
    p = subprocess.run([PSQL, '-d', 'redes_local', '-AtX', '-c', sql], env=ENV, capture_output=True, text=True)
    return (p.stdout.strip() if p.returncode == 0 else 'ERROR: ' + p.stderr.strip())


def qt(sql):
    t = time.time()
    r = q(sql)
    return r, time.time() - t


def reg(nombre, ok, detalle=''):
    res.append((nombre, bool(ok), detalle))
    print(('OK   ' if ok else 'FALLA'), nombre, ('· ' + detalle if detalle else ''))


def lit(s):
    return "'" + s.replace("'", "''") + "'"


ED = lambda n: os.path.join(RAIZ, n)  # noqa: E731
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
VIV = "select string_agg(md5(pg_get_functiondef(oid)), ',' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('geoportal_puede', 'geoportal_mis_permisos', 'geoportal_admin_permisos', 'geoportal_admin_listar')"
ISO = lambda intervalo: q(f"select to_char(now() + interval '{intervalo}', 'YYYY-MM-DD\"T\"HH24:MI:SSOF')")  # noqa: E731

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_4a'], env=ENV, check=True, capture_output=True)
md5_4a = q(CONJ)
viv_0 = q(VIV)
rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte4b_editor.sql'))
reg('01 huellas antes: «CORTE 4a (listo para el 4b)», las 4 de permisos «CORTE 4a (sin cambiar)», 12 RPC y 2 tablas «NO EXISTE»', rc == 0
    and 'CORTE 4a (listo para el 4b)' in out and out.count('CORTE 4a (sin cambiar)') == 4 and out.count('NO EXISTE (sin aplicar)') == 14 and 'DISTINTA' not in out)
GEN = os.path.join(C1A, 'carga', 'generado')
rc1, _, s1 = archivo('carga_inicial_todo.sql', ['-v', f'solicitante={ADMIN}'], cwd=GEN)
rc2, _, s2 = archivo('publicar.sql', ['-v', f'solicitante={ADMIN}'], cwd=GEN)
v85 = q("select st_y(geom) || '|' || st_x(geom) || '|' || codigo from redes.activo_vigente_mat where codigo_anterior = 'V85'").split('|')
SUBIR = lambda ruta: q(f"insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '{ruta}', '{{\"size\": 250000, \"mimetype\": \"image/jpeg\"}}')")  # noqa: E731
prep = q(f"select public.geoportal_redes_preparar_dano('{OPER}', 1)")
did, ruta = re.search(r'"dano_id": "([0-9a-f-]+)"', prep).group(1), re.search(r'"ruta": "([^"]+)"', prep).group(1); SUBIR(ruta)
d = q(f"""select public.geoportal_redes_crear_dano('{OPER}', '{did}', {lit('{"clase": "dano", "tipo": "fuga", "sistema": "acueducto", "activo": "%s", "lat": %s, "lon": %s, "ubicacion_origen": "gps", "t_detectado": "%s", "tipo_rotura": "parcial", "riesgo": "alto", "causa_clase": "terceros", "tercero_tipo": "vehiculo", "tercero_nombre": "Placa ZTL-777", "fotos": [{"n": 1, "momento": "dano", "ruta": "%s"}]}' % (v85[2], v85[0], v85[1], ISO('-3 hours'), ruta))})""")
cod_dano = re.search(r'"codigo": "(DAN-\d+)"', d).group(1)
prep = q(f"select public.geoportal_redes_preparar_intervencion('{SUP}', 1, 0)")
iid, ruta = re.search(r'"intervencion_id": "([0-9a-f-]+)"', prep).group(1), re.search(r'"ruta": "([^"]+)"', prep).group(1); SUBIR(ruta)
r = q(f"""select public.geoportal_redes_crear_intervencion('{SUP}', '{iid}', {lit('{"nace_de": "dano", "dano": "%s", "resuelve_dano": true, "tipo": "reparacion", "sistema": "acueducto", "activo": "%s", "lat": %s, "lon": %s, "ubicacion_origen": "gps", "t_inicio": "%s", "t_fin": "%s", "descripcion": "Cambio del empaque", "ejecutor": "emdupar", "fuentes": [{"aportante": "emdupar", "valor": 480000}], "archivos": [{"n": 1, "clase": "despues", "ruta": "%s"}]}' % (cod_dano, v85[2], v85[0], v85[1], ISO('-2 hours'), ISO('-1 hours'), ruta))})""")
cod_itv = (re.search(r'"codigo": "(ITV-\d+)"', r) or [None, ''])[1]
reg('02 carga real (35.781 activos) y un daño de terceros con su reparación (con valor) reales en V85', rc1 == 0 and rc2 == 0 and q('select count(*) from redes.activo_vigente_mat') == '35781'
    and cod_itv.startswith('ITV-'), f'publicar {s2:.1f} s, {cod_dano}, {cod_itv}')
rc, out, seg = archivo(ED('ensayo_en_transaccion_redes_corte4b_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
reg('03 ensayo DESPUÉS de la carga real y con hechos reales: ERROR con «N de N … SIN FALLAS»', rc != 0 and m and m.group(1) == m.group(2) and m.group(3).startswith('SIN FALLAS'),
    (m.group(0) if m else out[-800:]) + f' ({seg:.1f} s)')
reg('04 el ensayo no deja rastro (ni tablas, ni funciones, ni cambios en los parámetros)', q("select to_regclass('tecnica.personal_ficha_eventos') is null and to_regclass('redes.cuadrillas') is null") == 't'
    and q(CONJ) == md5_4a and q(VIV) == viv_0 and q("select count(*) from redes.parametro_eventos") == '0' and q("select count(*) from redes.alias_eventos") == '0')
rc, out, seg = archivo(ED('migracion_redes_corte4b_editor.sql'))
reg('05 migración _editor', rc == 0, f'{seg:.1f} s' if rc == 0 else out[-400:])
rc, out, _ = archivo(ED('verificacion_redes_corte4b_editor.sql'))
reg('06 verificación: 9 OK', rc == 0 and out.count('| OK') == 9 and '| MAL' not in out, '' if rc == 0 else out[-300:])
rc, out, _ = archivo(ED('migracion_redes_corte4b_editor.sql'))
reg('07 repetir la migración se rechaza (guardia)', rc != 0 and 'deténgase' in out)
rc, out, _ = archivo(ED('huellas_solo_lectura_redes_corte4b_editor.sql'))
reg('08 huellas después: «CORTE 4b (aplicado)», las 4 de permisos igual, 12 «NUEVA» y 2 «EXISTE»', 'CORTE 4b (aplicado)' in out and out.count('CORTE 4a (sin cambiar)') == 4
    and out.count('NUEVA (aplicada)') == 12 and out.count('EXISTE (aplicado)') == 2)
rc, out, _ = archivo(ED('reversa_redes_corte4b_editor.sql'))
reg('09 reversa sin datos: vuelve exactamente al 4a', rc == 0 and q(CONJ) == md5_4a and q(VIV) == viv_0 and q("select to_regclass('redes.v_personal_ficha') is null") == 't', out[-300:] if rc else '')
rc, out, _ = archivo(os.path.join(C4A, 'verificacion_redes_corte4a_editor.sql'))
reg('10 tras la reversa, la verificación del 4a vuelve a dar 8 OK', out.count('| OK') == 8 and '| MAL' not in out)
rc, out, _ = archivo(ED('reversa_redes_corte4b_editor.sql'))
reg('11 una segunda reversa se niega', rc != 0 and 'No hay nada que revertir' in out)
rc, out, _ = archivo(ED('migracion_redes_corte4b_editor.sql'))
reg('12 volver a migrar después de la reversa', rc == 0)

# ---------- con la carga real ----------
r, seg = qt(f"select jsonb_array_length(public.geoportal_redes_personal('{SUP}') -> 'personas')")
reg('13 Personal con la base real: el supervisor de distribución ve la lista', r.isdigit() and int(r) >= 3, f'{r} personas, {seg:.2f} s')
r = q(f"select public.geoportal_redes_personal_fijar('{SUP}', '{OPER}', 'area', 'distribucion', 'Operador de las cuadrillas de redes')")
r2 = q(f"select public.geoportal_redes_personal_fijar('{SUP}', '{OPER}', 'geovisor', 'si', 'Ve la red en la calle (solo lectura)')")
reg('14 área y geovisor del operador real', '"despues": "distribucion"' in r and '"despues": "si"' in r2 and q(f"select redes.f_geovisor_lectura('{OPER}')") == 't')
r, seg = qt(f"select (x ->> 'total') || '|' || (select string_agg(g ->> 'grupo' || '=' || (g ->> 'n'), ',') from jsonb_array_elements(x -> 'grupos') g) from public.geoportal_redes_nodos_por_clasificar('{ADMIN}', null, null, 50) x")
reg('15 nodos por clasificar de la carga real: 783 (S 559, J 213, M 9, Modulo 1, Pila 1), en menos de 1 s', r.startswith('783|') and 'S=559' in r and 'J=213' in r and seg < 1, f'{r} ({seg:.2f} s)')
nodo = q("select nodo_id || '|' || nombre_modelo from redes.v_nodo_vigente where clase_nodo = 'por_clasificar' and nombre_modelo like 'J-%' order by nodo_id limit 1").split('|')
tv0 = q("select max(version) from redes.tesela_version where sistema = 'acueducto'")
r = q(f"select public.geoportal_redes_nodo_crear_activo('{ADMIN}', {nodo[0]}, 'ACC', 'union', null, 'Técnica confirmó que esta J es una unión')")
cod = (re.search(r'"activo": "(ACC-\d+)"', r) or [None, ''])[1]
reg('16 crear el activo de un nodo J real: el nodo queda enlazado, el activo en la tabla materializada y la tesela sube de versión',
    cod.startswith('ACC-') and q(f"select clase_nodo from redes.v_nodo_vigente where nodo_id = {nodo[0]}") == 'activo'
    and q(f"select codigo_anterior from redes.activo_vigente_mat where codigo = '{cod}'") == nodo[1]
    and q("select max(version) from redes.tesela_version where sistema = 'acueducto'") != tv0
    and q("select count(*) from redes.v_nodo_vigente where clase_nodo = 'por_clasificar'") == '782', f'{nodo[1]} → {cod}' if cod else r[:300])
r, seg = qt(f"select public.geoportal_redes_graficas('{SUP}', 12)::text")
reg('17 gráficas con la base real (menos de 1 s): la reparación real cuenta en top_correctivos y en el valor por fuente', v85[2] in r and '480000' in r and seg < 1, f'{seg:.2f} s')
r, seg = qt(f"select public.geoportal_redes_descarga('{SUP}', 'danos', current_date - 30, current_date + 1)::text")
reg('18 descarga de daños de la base real: trae el daño de terceros sin la placa, y queda auditada', cod_dano in r and 'ZTL-777' not in r and seg < 2
    and q(f"select count(*) from public.geoportal_auditoria where accion = 'redes_descarga' and email = '{SUP}'") == '1', f'{seg:.2f} s')
r = q(f"select public.geoportal_redes_parametro_fijar('{ADMIN}', 'itv_radio_danos_m', 200, 'Se amplía el radio de los daños cercanos')")
reg('19 un parámetro real cambia con su evento, y la RPC de daños cercanos lo usa', '"despues": 200' in r and q("select redes.f_param('itv_radio_danos_m')") == '200'
    and '"radio_m": 200' in q(f"select public.geoportal_redes_danos_abiertos('{OPER}', 'acueducto', '{v85[2]}', null, null)"))
rc, out, _ = archivo(ED('verificacion_redes_corte4b_editor.sql'))
reg('20 verificación con datos: 9 OK', out.count('| OK') == 9 and '| MAL' not in out)
rc, out, _ = archivo(ED('reversa_redes_corte4b_editor.sql'))
reg('21 la reversa se niega con fichas del personal (nada se borra)', rc != 0 and 'se niega' in out)

bien = sum(1 for _, ok, _ in res if ok)
lin = [f"{'OK   ' if ok else 'FALLA'} {n}{(' · ' + d) if d else ''}" for n, ok, d in res]
lin.append(f'RESULTADO: {bien} de {len(res)} — {"SIN FALLAS" if bien == len(res) else str(len(res) - bien) + " FALLA(S)"}')
os.makedirs(os.path.join(RAIZ, 'resultados'), exist_ok=True)
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write('\n'.join(lin) + '\n')
print(lin[-1])
sys.exit(0 if bien == len(res) else 1)
