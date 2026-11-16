#!/usr/bin/env python3
"""Arnés local del Corte 6c (PostGIS de Homebrew, base redes_local en localhost:55432). Resultado «N de N».
Como producción el 16-nov (1a con la carga real de 35.781 activos, Cortes 2 a 6b, la MUE y el hotfix de pg-safeupdate) más 111.950 contratos SINTÉTICOS:
huellas antes · ensayo (ERROR esperado y sin rastro) · migración · verificación · guardia · huellas después · reversa (exacta al 6b + hotfix) · migrar de nuevo ·
y, COMO LAS VE PRODUCCIÓN, las llamadas de la Edge: con el rol service_role, statement_timeout = 30 s y lock_timeout = 8 s (los topes de Supabase), midiendo
el tiempo de cada RPC que lee tablas grandes: la configuración del geovisor, TODAS las teselas de contratos de zoom 16 de la ciudad, la tarjeta, y (revisión
de los cortes anteriores) una recarga completa del acueducto por las RPC de la pantalla del Cargue de capas.
pg-safeupdate no se carga en local: lo cubre la comprobación estática redes.f_funciones_sin_where (ensayo y verificación).
Uso: python3 -I correr_local.py   → escribe ../resultados/sql_local.txt
"""
import base64
import glob
import json
import math
import os
import re
import subprocess
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
C1A = os.environ.get('C1A', os.path.expanduser('~/geoportal-emdupar-tec-c1a/sql/redes_corte1a'))
ADMIN = 'carga.local@emdupar.gov.co'
SUP = 'arnes.dist@emdupar.gov.co'
# Lo que ve producción: cada petición de la API entra como authenticator, cambia a service_role y lleva estos topes.
EDGE = ['-c', 'set role service_role', '-c', "set statement_timeout = '30s'", '-c', "set lock_timeout = '8s'"]
res = []


def archivo(nombre):
    t = time.time()
    p = subprocess.run([PSQL, '-d', 'redes_local', '-X', '-v', 'ON_ERROR_STOP=1', '-f', nombre], env=ENV, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr, time.time() - t


def q(sql):
    p = subprocess.run([PSQL, '-d', 'redes_local', '-AtX', '-c', sql], env=ENV, capture_output=True, text=True)
    return (p.stdout.strip() if p.returncode == 0 else 'ERROR: ' + p.stderr.strip())


def edge(sql, extra=()):
    """Una llamada como la de la Edge: service_role, 30 s y 8 s. Devuelve (texto, segundos, falló)."""
    t = time.time()
    p = subprocess.run([PSQL, '-d', 'redes_local', '-AtqX', '-v', 'ON_ERROR_STOP=1', *EDGE, *extra, '-c', sql], env=ENV, capture_output=True, text=True)
    return (p.stdout.strip() if p.returncode == 0 else 'ERROR: ' + p.stderr.strip()), time.time() - t, p.returncode != 0


def reg(nombre, ok, detalle=''):
    res.append((nombre, bool(ok), detalle))
    print(('OK   ' if ok else 'FALLA'), nombre, ('· ' + detalle if detalle else ''), flush=True)


ED = lambda n: os.path.join(RAIZ, n)  # noqa: E731
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
SEP = '-- ====================================================================='


def consulta(nombre):
    return open(ED(nombre), encoding='utf-8').read().split(SEP, 2)[2].strip().rstrip(';')


def huellas():
    return q(f"select string_agg(objeto || '=' || estado, E'\\n') from ({consulta('huellas_solo_lectura_redes_corte6c_editor.sql')}) h")


def tesela_xy(z, lon, lat):
    n = 1 << z
    return int((lon + 180) / 360 * n), int((1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n)


def contratos_de(b64):
    return set(re.findall(rb'(?<![0-9])[0-9]{6}(?![0-9])', base64.b64decode(b64 or '')))


# ---------- base como en vivo ----------
HOT = '8113af17c6bd862d62a6cbc4bc4cba1f'
t0 = time.time()
subprocess.run(['sh', os.path.join(AQUI, 'base_chrome.sh'), 'solo_hotfix'], env=ENV, check=True, capture_output=True)
reg('00 base como producción: carga real, MUE, 6b + hotfix de safeupdate (huella 8113af17…) y 111.950 contratos sintéticos', q(CONJ) == HOT,
    f"{time.time() - t0:.0f} s · {q('select count(distinct cod_usuario) from public.catastro_valledupar')} contratos en el catastro · {q('select count(*) from redes.activo_vigente_mat')} activos vigentes")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('{SUP}', 'Arnés distribución', 'consulta', true, true, 'sin_restriccion', 'todos') on conflict do nothing")

# ---------- lo que pasaba con el 6b (para dejarlo medido) ----------
out, s, mal = edge(f"select public.geoportal_redes_geovisor('{SUP}') -> 'contratos_capa'")
reg('01 ANTES (6b + hotfix): la configuración del geovisor rehace la copia de contratos dentro de la petición', not mal and '"filas"' in out, f'{s:.1f} s en local (44,7 s en producción, contra el tope de 30 s) · {out}')
zc, (xc, yc) = 17, tesela_xy(17, -73.255, 10.470)
antes_b64 = q(f"select public.geoportal_redes_geovisor_mvt_contratos('{SUP}', {zc}, {xc}, {yc})")
h = huellas()
reg('02 huellas antes: «CORTE 6b + hotfix (listo para el 6c)», 3 «CORTE 6b (sin cambiar)», 2 «NO EXISTE», 4 «EXISTE (sin aplicar)» y los 4 índices «EXISTE»',
    'CORTE 6b + hotfix (listo para el 6c)' in h and h.count('CORTE 6b (sin cambiar)') == 3 and h.count('NO EXISTE (sin aplicar)') == 2 and h.count('EXISTE (sin aplicar)') == 6
    and h.count('=EXISTE\n') + h.endswith('=EXISTE') == 4 and 'DISTINTA' not in h and 'FALTA' not in h, h.replace('\n', ' | ')[:400])
c, out, s = archivo(ED('ensayo_en_transaccion_redes_corte6c_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
tm = re.search(r'TIEMPOS: .*', out)
reg('03 ensayo con el volumen real: ERROR esperado, N de N SIN FALLAS', c != 0 and m and m.group(1) == m.group(2) and 'SIN FALLAS' in m.group(3),
    (m.group(0) if m else out[-600:]) + f' · {s:.1f} s · ' + (tm.group(0) if tm else ''))
reg('04 el ensayo no deja rastro', q("select to_regclass('redes.contratos_capa') is not null") == 't' and q(CONJ) == HOT
    and q("select count(*) from public.geoportal_auditoria where email like 'prueba.redes12.%'") == '0' and q("select count(*) from public.catastro_valledupar where cod_usuario like '9900000012%'") == '0'
    and q("select count(*) from public.geoportal_lista_blanca where email like 'prueba.redes12.%'") == '0')
c, out, s = archivo(ED('migracion_redes_corte6c_editor.sql'))
reg('05 migración', c == 0, f'{s:.1f} s' + ('' if c == 0 else ' · ' + out[-400:]))
md5_6c = q(CONJ)
filas = [x for x in q(consulta('verificacion_redes_corte6c_editor.sql')).split('\n') if x]
reg('06 verificación: todas las filas OK', len(filas) == 10 and all(x.endswith('|OK') for x in filas if not x.startswith('INFO')), ' | '.join(filas)[-330:])
c, out, _ = archivo(ED('migracion_redes_corte6c_editor.sql'))
reg('07 guardia: migrar dos veces se niega', c != 0 and 'Corte 6c ya está aplicado' in out, out.strip().split('\n')[-1][:160])
h = huellas()
reg('08 huellas después: «CORTE 6c (aplicado)», 3 «CORTE 6c (reemplazada)», 2 «NUEVA», 4 «RETIRADO» y los 4 índices',
    'CORTE 6c (aplicado)' in h and h.count('CORTE 6c (reemplazada)') == 3 and h.count('NUEVA (aplicada)') == 2 and h.count('RETIRADO (aplicado)') == 4 and 'FALTA' not in h, h.replace('\n', ' | ')[:300])
c, out, _ = archivo(ED('reversa_redes_corte6c_editor.sql'))
reg('09 reversa: exacta al 6b + hotfix (8113af17…), con la copia derivada de vuelta (vacía) y su función', c == 0 and q(CONJ) == HOT and q('select count(*) from redes.contratos_capa') == '0'
    and q("select to_regprocedure('redes.f_funciones_sin_where()') is null") == 't' and int(q('select redes.f_refrescar_contratos_capa()')) > 100000, out[-300:] if c else '')
c, out, _ = archivo(ED('reversa_redes_corte6c_editor.sql'))
reg('10 reversa dos veces: se niega', c != 0 and 'no está aplicado' in out, out.strip().split('\n')[-1][:160])
c, out, _ = archivo(ED('migracion_redes_corte6c_editor.sql'))
reg('11 migrar de nuevo después de la reversa: la misma huella', c == 0 and q(CONJ) == md5_6c, md5_6c)

# ---------- como las ve producción: service_role, 30 s y 8 s ----------
out, s1, mal = edge(f"select public.geoportal_redes_geovisor('{SUP}')")
cfg = json.loads(out) if not mal else {}
_, s2, _ = edge(f"select public.geoportal_redes_geovisor('{SUP}')")
reg('12 Edge (service_role, 30 s y 8 s): la configuración del geovisor ya no rehace nada: responde en menos de 1 s las dos veces, con la capa de contratos y sin «contratos_capa»',
    not mal and s1 < 1 and s2 < 1 and 'contratos_capa' not in cfg and any(x['codigo'] == 'contratos' for x in cfg.get('capas', [])) and cfg.get('zoom', {}).get('contratos') == 16,
    f'{s1 * 1000:.0f} ms y {s2 * 1000:.0f} ms' + (' · ' + out[:200] if mal else ''))
out, s, mal = edge(f"select public.geoportal_redes_geovisor_mvt_contratos('{SUP}', {zc}, {xc}, {yc})")
reg('13 la tesela al vuelo trae los mismos contratos que traía la copia del 6b (misma tesela del centro, zoom 17) y pesa lo mismo (±1 %: solo cambia el orden)',
    not mal and contratos_de(out) == contratos_de(antes_b64) and len(contratos_de(out)) > 50 and abs(len(out) - len(antes_b64)) <= 0.01 * len(antes_b64),
    f'{len(contratos_de(out))} contratos · {len(out) * 3 // 4} bytes (antes {len(antes_b64) * 3 // 4}) · {s * 1000:.0f} ms')
binario = base64.b64decode(out or '')
reg('14 la tesela no lleva nombres, direcciones, barrios ni teléfonos de la cartera sintética', len(binario) > 0 and b'SUSCRIPTOR' not in binario and b'DIRECCION' not in binario and b'3000000000' not in binario and b'BARRIO' not in binario)
# todas las teselas de zoom 16 que tienen predios (peor caso de la capa), una por una, como peticiones de la Edge
teselas = q("select string_agg(x || ' ' || y || ' ' || n, ',' order by n desc) from (select floor((ST_X(geom) + 180) / 360 * 65536)::int x, "
            "floor((1 - ln(tan(radians(ST_Y(geom))) + 1 / cos(radians(ST_Y(geom)))) / pi()) / 2 * 65536)::int y, count(*) n from public.catastro_valledupar where geom is not null group by 1, 2) t").split(',')
peor = (0, '', 0, 0)
total = 0.0
pesada = (0, '')
fallas = []
for fila in teselas:
    x, y, n = fila.split()
    out, s, mal = edge(f"select length(decode(nullif(public.geoportal_redes_geovisor_mvt_contratos('{SUP}', 16, {x}, {y}), ''), 'base64'))")
    if mal:
        fallas.append(f'{x}/{y}: {out[:80]}')
        continue
    total += s
    b = int(out or 0)
    if s > peor[0]:
        peor = (s, f'{x}/{y}', int(n), b)
    if b > pesada[0]:
        pesada = (b, f'{x}/{y} ({n} predios)')
reg('15 Edge: TODAS las teselas de contratos de zoom 16 de la ciudad, una por una: ninguna falla, ninguna pasa de 2 s (meta del encargo: 10 s; tope: 30 s) ni de 500 KB',
    not fallas and len(teselas) > 100 and peor[0] < 2 and pesada[0] < 500 * 1024,
    f'{len(teselas)} teselas · la más lenta {peor[0] * 1000:.0f} ms ({peor[1]}, {peor[2]} predios, {peor[3] // 1024} KB) · la más pesada {pesada[0] // 1024} KB en {pesada[1]} · '
    f'recorrerlas todas {total:.1f} s' + (' · ' + '; '.join(fallas[:3]) if fallas else ''))
c1 = q("select cod_usuario from public.catastro_valledupar where cod_usuario ~ '^[1-9][0-9]{5}$' order by cod_usuario limit 1")
n0 = int(q("select count(*) from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta'"))
out, s_tj, mal = edge(f"select public.geoportal_redes_contrato_tarjeta('{SUP}', '{c1}', '127.0.0.1')")
tj = json.loads(out) if not mal else {}
reg('16 Edge: la tarjeta de un contrato sintético: nombre del último corte, estado y uso leídos en el momento, 6 meses de consumo; sin teléfono ni deuda; menos de 300 ms',
    not mal and tj['suscriptor']['nombre'].startswith('SUSCRIPTOR SINTETICO') and tj['estado'] in ('activo', 'retirado', 'otro') and tj['uso'] in ('Residencial', 'Comercial')
    and len(tj['consumo']['meses']) == 6 and '3000000000' not in out and '99999' not in out and s_tj < 0.3, f"{s_tj * 1000:.0f} ms · {out[:160]}")
reg('17 la lectura quedó en la auditoría sin el nombre', int(q("select count(*) from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta'")) == n0 + 1
    and 'SUSCRIPTOR' not in q("select detalle::text from public.geoportal_auditoria where accion = 'redes_contrato_tarjeta' order by id desc limit 1"))
out, _, mal = edge('select count(*) from redes.f_funciones_sin_where()')
reg('18 la API no ejecuta la comprobación estática (interna); como administrador de la base devuelve cero funciones con DELETE o UPDATE sin WHERE',
    mal and 'permission denied' in out.lower() or 'permiso denegado' in out.lower(), q('select count(*) from redes.f_funciones_sin_where()'))
res[-1] = (res[-1][0], res[-1][1] and q('select count(*) from redes.f_funciones_sin_where()') == '0', res[-1][2])

# ---------- revisión de los cortes anteriores (punto 5 del encargo): lo pesado, medido con la red real ----------
t = time.time(); n_v = q('select redes.f_refrescar_vigente()'); s_v = time.time() - t
t = time.time(); n_ct = q('select redes.f_recalcular_contrato_tramo()'); s_ct = time.time() - t
reg('19 INFO redes.f_refrescar_vigente y redes.f_recalcular_contrato_tramo con la red real y 112 mil predios (cada una menos de 30 s en local)', s_v < 30 and s_ct < 30 and 'ERROR' not in n_v + n_ct,
    f'f_refrescar_vigente {s_v:.1f} s ({n_v} activos) · f_recalcular_contrato_tramo {s_ct:.1f} s ({n_ct} contratos enlazados)')
# una recarga COMPLETA del acueducto por las RPC de la pantalla (iniciar, 53 lotes de 200, resumen y publicar), cada una como petición de la Edge
out, s, mal = edge(f"select public.geoportal_redes_cargue_iniciar('{ADMIN}', 'acueducto', '{'6c' * 32}', 'shp', 4326, 'ID', 10578, 'Arnés 6c: recarga completa de prueba', null) ->> 'carga_id'")
if mal:      # firma de psql del 1a
    out, s, mal = edge(f"select public.geoportal_redes_carga_iniciar('{ADMIN}', 'acueducto', '{'6c' * 32}', 'shp', 4326, 'ID', 10578, 'Arnés 6c: recarga completa de prueba') ->> 'carga_id'")
carga = out
lotes = sorted(glob.glob(os.path.join(C1A, 'carga', 'generado', 'lotes', 'acueducto_*.sql')))
s_lote = 0.0
mal_lote = ''
for f in lotes:
    t = time.time()
    p = subprocess.run([PSQL, '-d', 'redes_local', '-AtqX', '-v', 'ON_ERROR_STOP=1', '-v', f'solicitante={ADMIN}', '-v', f'carga_acueducto={carga}', *EDGE, '-f', f], env=ENV, capture_output=True, text=True)
    s_lote = max(s_lote, time.time() - t)
    if p.returncode != 0 and not mal_lote:
        mal_lote = p.stderr.strip()[:200]
out_r, s_res, mal_r = edge(f"select public.geoportal_redes_carga_resumen('{ADMIN}', {carga or 0})")
out_p, s_pub, mal_p = edge(f"select public.geoportal_redes_carga_publicar('{ADMIN}', {carga or 0}, 'Arnés 6c: recarga completa de prueba')")
reg('20 INFO Cargue de capas: recarga COMPLETA del acueducto (10.578 tramos) por las RPC de la pantalla, cada una como petición de la Edge (30 s y 8 s): ninguna falla en local',
    not mal and not mal_lote and not mal_r and not mal_p and len(lotes) == 53,
    f'lote más lento {s_lote:.1f} s de {len(lotes)} · resumen {s_res:.1f} s · publicar {s_pub:.1f} s' + ''.join(' · ' + x[:200] for x in (mal_lote, out_r if mal_r else '', out_p if mal_p else '') if x))
filas = [x for x in q(consulta('verificacion_redes_corte6c_editor.sql')).split('\n') if x]
reg('21 verificación después de todo: todas OK', len(filas) == 10 and all(x.endswith('|OK') for x in filas if not x.startswith('INFO')), filas[-1])

ok = sum(1 for _, b, _ in res if b)
texto = '\n'.join(('OK    ' if b else 'FALLA ') + n + ((' · ' + d) if d else '') for n, b, d in res)
texto += f'\n\nRESULTADO: {ok} de {len(res)} — ' + ('SIN FALLAS' if ok == len(res) else f'{len(res) - ok} FALLA(S)') + '\n'
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write(texto)
print(f'\nRESULTADO: {ok} de {len(res)}')
