#!/usr/bin/env python3
"""Arnés local de «Cierre por aguas arriba» (Code A, localhost:55432, base redes_local = producción con el Corte 14 + las cotas del Plan Maestro):
  · el ensayo (N de N … SIN FALLAS) y que no deja nada; huellas; migración; verificación; segunda migración; reversa (vuelve la huella del 14);
  · que SOLO AGREGA: ninguna función anterior cambia de texto (la simulación de siempre, tecnica.f_avisos);
  · como la ve producción (service_role, 30 s / 8 s): la RPC con el caso real (RED-000077 → VAL-000684) y otros tramos; tope local 5 s / 6.
Uso: python3 -I correr_local.py"""
import json
import os
import re
import subprocess
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = 'redes_local'
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_14 = '1a9ef250a74fb01962f463d98834cc4a'
NUEVAS = "('f_sim_sentidos', 'f_sim_llenar_sentido', 'f_sim_aguas_arriba_criterio', 'f_simular_aguas_arriba', 'geoportal_redes_simulacion_aguas_arriba')"
VIEJAS = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) from pg_proc p "
          "where (p.pronamespace in ('redes'::regnamespace, 'tecnica'::regnamespace) or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_%')) "
          f"and p.prokind = 'f' and p.proname not in {NUEVAS}")
ADM, OP, NA = 'zt9a.arnes.adm@emdupar.gov.co', 'zt9a.arnes.op@emdupar.gov.co', 'zt9a.arnes.nada@emdupar.gov.co'
T5 = 5000 / 6
res = []


def ok(nombre, cond, det=''):
    res.append((nombre, bool(cond), str(det)[:500]))
    print(('OK    ' if cond else 'FALLA ') + nombre + ('' if cond else ' → ' + str(det)[:500]), flush=True)


def psql(*args, check=False):
    return subprocess.run([PSQL, '-d', BASE, '-X', *args], env=ENV, capture_output=True, text=True, check=check)


def q(sql):
    return psql('-At', '-c', sql, check=True).stdout.strip()


def rehacer(con=''):
    subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')] + ([con] if con else []), env=ENV, check=True, capture_output=True)


def edge(sql):
    t0 = time.time()
    p = psql('-Atq', '-v', 'ON_ERROR_STOP=1', '-c', 'set role service_role', '-c', "set statement_timeout = '30s'", '-c', "set lock_timeout = '8s'", '-c', sql)
    return round((time.time() - t0) * 1000), p.stdout.strip(), (p.stderr.strip() if p.returncode else '')


def archivo(n):
    return os.path.join(RAIZ, n)


rehacer()
viejas0, aud0 = q(VIEJAS), q('select count(*) from public.geoportal_auditoria')
p = psql('-q', '-f', archivo('ensayo_en_transaccion_redes_9b_aguasarriba_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — SIN FALLAS', p.stderr)
ok(f'01 el ensayo termina en el ERROR esperado: {m.group(1) if m else "?"} de {m.group(2) if m else "?"} … SIN FALLAS', m and m.group(1) == m.group(2) and 'esperado' in p.stderr, p.stderr[-1500:])
for linea in re.findall(r'(?:TIEMPOS|CASO REAL)[^\n]*', p.stderr):
    print('   ' + linea)
ok('02 … y no deja nada (sigue la huella del 14, no están las funciones ni los parámetros, ni una fila de auditoría)',
   q(CONJ) == MD5_14 and q("select to_regprocedure('redes.f_simular_aguas_arriba(bigint)')") == '' and q("select count(*) from redes.parametros where clave like 'sim_aguas%'") == '0'
   and q('select count(*) from public.geoportal_auditoria') == aud0)
filas = psql('-AtF', '|', '-f', archivo('huellas_solo_lectura_redes_9b_aguasarriba_editor.sql')).stdout.strip().splitlines()
ok('03 las huellas antes: «CORTE 14 (listo para aguas arriba)», las 5 nuevas no existen y la simulación de siempre es la publicada', any('listo para aguas arriba' in f for f in filas)
   and sum('NO EXISTE (sin aplicar)' in f for f in filas) == 5 and any('LA PUBLICADA' in f for f in filas) and not any('DISTINTA' in f or 'FALTA' in f for f in filas), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('migracion_redes_9b_aguasarriba_editor.sql'))
ok('04 la migración se aplica', p.returncode == 0, p.stderr)
ok('05 SOLO AGREGA: ninguna función anterior de redes, tecnica ni public.geoportal_* cambió de texto', q(VIEJAS) == viejas0)
filas = psql('-AtF', '|', '-f', archivo('huellas_solo_lectura_redes_9b_aguasarriba_editor.sql')).stdout.strip().splitlines()
ok('06 las huellas después: «AGUAS ARRIBA (aplicada)» y 5 nuevas', any('AGUAS ARRIBA (aplicada)' in f for f in filas) and sum('NUEVA (aplicada)' in f for f in filas) == 5, '\n'.join(filas))
filas = psql('-AtF', '|', '-f', archivo('verificacion_redes_9b_aguasarriba_editor.sql')).stdout.strip().splitlines()
ok(f'07 la verificación: las {sum(1 for f in filas if not f.startswith("INFO"))} filas OK', filas and all(f.endswith('|OK') for f in filas if not f.startswith('INFO')), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('migracion_redes_9b_aguasarriba_editor.sql'))
ok('08 una segunda migración se niega', p.returncode != 0 and 'ya está aplicado' in p.stderr, p.stderr)
ok('09 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', q('select count(*) from redes.f_funciones_sin_where()') == '0')

# como la ve producción
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('{ADM}', 'ZT9A arnés admin', 'admin', 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('{OP}', 'ZT9A arnés operador', 'consulta', true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('{NA}', 'ZT9A arnés sin Técnica', 'consulta', 'sin_restriccion', 'todos')")
q(f"insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('{OP}', 'asignar_formulario', 'danos_fallas', '{ADM}')")
hay_cotas = q("select count(*) from redes.pm_nodos where carga_id = redes.f_ref_vigente('pm_nodos') and cota_m is not null") != '0'
ms, out, e = edge(f"select public.geoportal_redes_simulacion_aguas_arriba('{OP}', 'RED-000077')")
j = json.loads(out) if not e else {}
au = j.get('aguas_arriba', {})
ok(f'10 EL CASO REAL como la Edge ({ms} ms; tope local {T5:.0f} ms): RED-000077 por {j.get("criterio")} pide {au.get("valvulas_total")} válvula '
   f'{[v["codigo"] for v in au.get("valvulas", [])]}, entra por {au.get("entra_por", {}).get("nombre")}; {j.get("contratos_min")} a {j.get("contratos_max")} contratos',
   not e and ms < T5 and (not hay_cotas or (j['metodo'] == 'aguas_arriba' and [v['codigo'] for v in au['valvulas']] == ['VAL-000684'])), e or out[:400])
co = j.get('comprobacion', {})
ok(f'11 … la comprobación por el modelo da otras válvulas {[v["codigo"] for v in co.get("valvulas", [])]} y lo dice: «{co.get("texto")}»',
   not e and (not hay_cotas or (co.get('coincide') is False and 'confirme en campo' in co.get('texto', ''))), out[:300])
ms, out, e = edge(f"select public.geoportal_redes_simulacion_cierre('{OP}', 'RED-000077')")
t = json.loads(out) if not e else {}
ok(f'12 … frente al aislamiento total de siempre ({ms} ms): {t.get("estrecho", {}).get("valvulas_total")} válvulas y {t.get("contratos_min")} a {t.get("contratos_max")} contratos',
   not e and t['estrecho']['valvulas_total'] > 100)
cods = q("select string_agg(codigo, ',') from (select m.codigo from redes.activo_vigente_mat m join redes.tramo_nodos tn on tn.activo_id = m.activo_id and tn.version = m.version "
         "where m.sistema = 'acueducto' and m.prefijo = 'RED' and m.cuenta_vigente and not m.retirado and tn.nodo_ini is not null and tn.nodo_fin is not null order by md5(m.codigo) limit 12) s").split(',')
peor, caen, errs = 0, 0, []
for c in cods:
    ms, out, e = edge(f"select public.geoportal_redes_simulacion_aguas_arriba('{OP}', '{c}')")
    peor = max(peor, ms)
    if e:
        errs.append(c + ': ' + e[:120])
    elif json.loads(out)['cae_a_total']:
        caen += 1
ok(f'13 otros 12 tramos de la red real como la Edge: el más lento {peor} ms (tope local {T5:.0f} ms); {caen} caen al aislamiento total', not errs and peor < T5, errs)
ms, out, e = edge(f"select public.geoportal_redes_simulacion_aguas_arriba('{OP}', null, 10.46453, -73.25294)")
ok(f'14 por un punto del mapa como la Edge ({ms} ms): toma el tramo más cercano ({json.loads(out)["activo"]["codigo"] if not e else e[:100]})', not e and ms < T5, e)
ok('15 alguien sin Técnica no simula; la API no ejecuta las internas', 'permission denied' in edge("select redes.f_simular_aguas_arriba(1)")[2]
   and edge(f"select public.geoportal_redes_simulacion_aguas_arriba('{NA}', 'RED-000077')")[2] != '')
ok('16 simular no escribió nada: ni simulaciones guardadas ni auditoría del operador',
   q(f"select (select count(*) from redes.simulaciones_cierre where autor = '{OP}') + (select count(*) from public.geoportal_auditoria where email = '{OP}')") == '0')
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('reversa_redes_9b_aguasarriba_editor.sql'))
ok('17 la reversa se aplica: vuelve la huella del 14, las funciones anteriores siguen igual y los parámetros quedan «sin uso» (no se borran)',
   p.returncode == 0 and q(CONJ) == MD5_14 and q(VIEJAS) == viejas0 and q("select count(*) from redes.parametros where clave in ('sim_aguas_arriba_criterio', 'sim_cota_minima_m') and descripcion like 'Sin uso%'") == '2', p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('reversa_redes_9b_aguasarriba_editor.sql'))
ok('18 una segunda reversa se niega', p.returncode != 0 and 'No hay nada que revertir' in p.stderr, p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('migracion_redes_9b_aguasarriba_editor.sql'))
ok('19 después de la reversa, la migración se vuelve a aplicar y los parámetros recuperan su valor y su descripción',
   p.returncode == 0 and q("select count(*) from redes.parametros where clave in ('sim_aguas_arriba_criterio', 'sim_cota_minima_m') and descripcion like 'Cierre por aguas arriba%'") == '2', p.stderr)
rehacer()
malas = [r for r in res if not r[1]]
print(f'\nRESULTADO: {len(res) - len(malas)} de {len(res)} — ' + ('SIN FALLAS' if not malas else f'{len(malas)} FALLA(S)'))
