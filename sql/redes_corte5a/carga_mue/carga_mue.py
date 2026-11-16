#!/usr/bin/env python3
"""Primera carga de la capa MUE (puntos de muestreo) — Técnica fase 1, Corte 5a. Sin dependencias (usa el lector de SHP del Corte 1a y psql).
Decisión de David del 15-nov, 14:04 (§4 de hallazgos_capas_redes_15nov.md):
  · 3 puntos con la ubicación VERIFICADA que dio David (fuente «david»);
  · 24 APROXIMADOS al centro del barrio de igual nombre en la capa de barrios, o al de su primera etapa cuando hay varias (fuente «barrio»).
El cruce punto → barrio está escrito abajo, uno por uno, para que David lo revise; el centro se calcula en el PostGIS local (EPSG:3116 → 4326): el
centroide si cae dentro del barrio y, si no, un punto dentro del polígono. Escribe en generado/:
  · carga_mue_todo.sql  (inicia la carga, pasa el lote y muestra el resumen; NO publica) — un solo comando de psql, como la carga inicial;
  · publicar_mue.sql    (aparte, después de revisar el resumen);
  · puntos_mue.csv      (la lista para revisar: código, nombre, barrio de la capa, exactitud, fuente y coordenadas).
Uso: python3 -I carga_mue.py   (PostGIS local en localhost:55432; la capa en ~/Downloads/Barrios_Con_Nombre_EPSG3116)."""
import csv
import hashlib
import json
import os
import subprocess
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.join(AQUI, 'generado')
C1A = os.environ.get('C1A', os.path.expanduser('~/geoportal-emdupar-tec-c1a/sql/redes_corte1a/carga'))
BARRIOS = os.environ.get('BARRIOS', os.path.expanduser('~/Downloads/Barrios_Con_Nombre_EPSG3116/Barrios_Con_Nombre'))
PUNTOS = os.environ.get('PUNTOS', os.path.expanduser('~/geoportal-consultas/tecnica/corte2_paso_a/puntos_muestreo.csv'))
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres')
sys.path.insert(0, C1A)
import shp  # noqa: E402  (lector propio del Corte 1a)

# Verificadas por David en Google Maps (§4 de hallazgos)
VERIFICADAS = {'MUE-24': (10.48067, -73.25744), 'MUE-11': (10.45615, -73.22863), 'MUE-23': (10.46887, -73.24867)}
# Punto → nombre del barrio en la capa (campo RefName). Igual nombre o, si hay varias etapas, la primera.
BARRIO = {
    'MUE-01': 'NOVALITO', 'MUE-02': 'VILLALBA', 'MUE-03': 'EL REFUGIO', 'MUE-04': 'LA NEVADA', 'MUE-05': 'O.G.B.', 'MUE-06': 'PANAMÁ I ETAPA',
    'MUE-07': 'DON CARMELO I ETAPA', 'MUE-08': 'LA VICTORIA', 'MUE-09': 'SIETE DE AGOSTO', 'MUE-10': 'LOS MAYALES', 'MUE-12': 'EL CERRITO',
    'MUE-13': 'FUNDADORES', 'MUE-14': 'LOS ALAMOS', 'MUE-15': 'NANDO MARIN I ETAPA', 'MUE-16': 'TOBÍAS DAZA', 'MUE-17': 'ALFONSO LOPEZ',
    'MUE-18': 'HOSPITAL', 'MUE-19': 'LOPERENA', 'MUE-20': 'EL AMPARO', 'MUE-21': 'EL CARMEN', 'MUE-22': 'SICARARE', 'MUE-25': 'DIVINO NINO',
    'MUE-26': 'GUATAPURI', 'MUE-27': 'DON ALBERTO',
}


def q(sql):
    p = subprocess.run([PSQL, '-d', os.environ.get('PGBASE', 'redes_local'), '-AtX', '-v', 'ON_ERROR_STOP=1'], input=sql, env=ENV, capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit(p.stderr)
    return p.stdout.strip()


puntos = list(csv.DictReader(open(PUNTOS, encoding='utf-8'), delimiter=';'))
assert len(puntos) == 27 and {p['codigo'] for p in puntos} == set(VERIFICADAS) | set(BARRIO), 'Los 27 puntos no cuadran con el cruce'
_, filas = shp.leer(BARRIOS)
nombre_de = lambda f: (f.get('RefName') or f.get('Text_1') or '').strip()  # noqa: E731
poligonos = {}
for f in filas:
    poligonos.setdefault(nombre_de(f), []).append(shp.wkt(f['geom']))
faltan = [b for b in BARRIO.values() if b not in poligonos]
assert not faltan, f'Barrios que no están en la capa: {faltan}'

# centro de cada barrio en el PostGIS local (unión si el barrio tiene varios polígonos)
valores = ',\n'.join(f"('{b.replace(chr(39), chr(39) * 2)}', ST_GeomFromText('{w}', 3116))" for b in sorted(set(BARRIO.values())) for w in poligonos[b])
res = q(f"""set search_path to public, extensions;
with b(nombre, g) as (values {valores}),
u as (select nombre, count(*) as n, ST_Union(g) as g from b group by nombre)
select nombre || '|' || n || '|' || round(ST_Y(p)::numeric, 6) || '|' || round(ST_X(p)::numeric, 6) || '|' || metodo
  from (select nombre, n, ST_Transform(case when ST_Contains(g, ST_Centroid(g)) then ST_Centroid(g) else ST_PointOnSurface(g) end, 4326) as p,
               case when ST_Contains(g, ST_Centroid(g)) then 'centroide' else 'punto dentro del polígono' end as metodo from u) x order by 1;""")
centro = {}
for l in (x for x in res.splitlines() if x.count('|') == 4):
    n, cnt, lat, lon, metodo = l.split('|')
    centro[n] = (float(lat), float(lon), int(cnt), metodo)

lote, revisar = [], []
for i, p in enumerate(sorted(puntos, key=lambda x: x['codigo']), start=1):
    c = p['codigo']
    if c in VERIFICADAS:
        lat, lon = VERIFICADAS[c]
        a = {'codigo': c, 'nombre': p['nombre'], 'zona': p['zona'].lower(), 'exactitud': 'verificada', 'fuente': 'david'}
        nota = 'verificada por David (Google Maps)'
    else:
        b = BARRIO[c]
        lat, lon, cnt, metodo = centro[b]
        a = {'codigo': c, 'nombre': p['nombre'], 'zona': p['zona'].lower(), 'barrio': b, 'exactitud': 'aproximada', 'fuente': 'barrio'}
        nota = f'centro del barrio {b} ({metodo}{"; " + str(cnt) + " polígonos unidos" if cnt > 1 else ""})'
    lote.append({'orden': i, 'atributos': a, 'wkt': f'POINT({lon:.6f} {lat:.6f})'})
    revisar.append([c, p['nombre'], a.get('barrio', ''), a['exactitud'], a['fuente'], f'{lat:.6f}', f'{lon:.6f}', nota])

texto = json.dumps(lote, ensure_ascii=False, separators=(',', ':'))
sha = hashlib.sha256(texto.encode('utf-8')).hexdigest()
os.makedirs(SALIDA, exist_ok=True)
with open(os.path.join(SALIDA, 'puntos_mue.csv'), 'w', encoding='utf-8', newline='') as f:
    w = csv.writer(f, delimiter=';')
    w.writerow(['codigo', 'nombre', 'barrio_de_la_capa', 'exactitud', 'fuente', 'lat', 'lon', 'nota'])
    w.writerows(revisar)
CAB = """\\set ON_ERROR_STOP 1
\\if :{?solicitante}
\\else
  \\echo 'Falta el correo del administrador. Uso: psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO -f %s'
  \\quit
\\endif
\\pset pager off
"""
open(os.path.join(SALIDA, 'carga_mue_todo.sql'), 'w', encoding='utf-8').write(f"""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a — PRIMERA CARGA DE LA CAPA MUE (27 puntos de muestreo). Generado por carga_mue.py. NO PUBLICA.
-- Un solo comando (la cadena de conexión la pone usted en su terminal; no va en ningún archivo):
--   psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO_DEL_ADMINISTRADOR -f carga_mue_todo.sql
-- Inicia la carga, pasa el lote de 27 puntos y muestra el resumen (punto por punto: exactitud, fuente, barrio y coordenadas).
-- No toca tecnica.puntos hasta publicar. Repetirlo no duplica (iniciar devuelve la carga abierta; el lote es idempotente). Después: publicar_mue.sql.
-- =====================================================================
{CAB % 'carga_mue_todo.sql'}\\set QUIET 1
select (public.geoportal_redes_carga_iniciar(:'solicitante', 'muestreo', '{sha}', 'csv', 4326, 'codigo', {len(lote)},
        'Primera carga de los 27 puntos de muestreo: 3 verificados por David y 24 aproximados al centro de su barrio (§4 de hallazgos, 15-nov)') ->> 'carga_id') as carga_mue \\gset
\\echo '  carga de la capa de muestreo:' :carga_mue
\\o /dev/null
select public.geoportal_redes_carga_lote(:'solicitante', :carga_mue, $lote${texto}$lote$::jsonb);
\\o
\\echo '=================== RESUMEN (no se ha publicado nada) ==================='
select r ->> 's' as seccion, r ->> 'c' as concepto, r ->> 'v' as valor from jsonb_array_elements(public.geoportal_redes_carga_resumen(:'solicitante', :carga_mue) -> 'tabla') r;
\\echo 'Si dice «lista para publicar: SÍ» y la lista de puntos está bien, corra publicar_mue.sql con el mismo comando.'
""")
open(os.path.join(SALIDA, 'publicar_mue.sql'), 'w', encoding='utf-8').write(f"""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a — PUBLICAR LA PRIMERA CARGA DE LA CAPA MUE. Generado por carga_mue.py.
-- Córralo SOLO después de revisar el resumen de carga_mue_todo.sql:
--   psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO_DEL_ADMINISTRADOR -f publicar_mue.sql
-- En tecnica.puntos no cambia nada (los 27 ya existen y vienen todos): solo se agrega su ubicación en tecnica.puntos_ubicacion.
-- =====================================================================
{CAB % 'publicar_mue.sql'}\\timing on
select key as dato, value as valor from jsonb_each_text(public.geoportal_redes_carga_publicar(:'solicitante',
  (select id from redes.v_cargas_estado where capa_codigo = 'muestreo' and sha256 = '{sha}' and estado = 'abierta'),
  'Primera carga de los 27 puntos de muestreo (§4 de hallazgos, decisión de David del 15-nov)')) order by 1;
\\echo '=================== LO QUE QUEDÓ VIGENTE ==================='
select p.codigo, p.nombre, u.exactitud, u.fuente, u.barrio_capa, u.lat, u.lon from tecnica.puntos p left join redes.v_punto_ubicacion_vigente u on u.punto_id = p.id
 where p.tipo = 'muestreo' order by p.codigo;
""")
print(f'{len(lote)} puntos · sha256 {sha} · {sum(1 for r in revisar if r[3] == "verificada")} verificados · generado/carga_mue_todo.sql, publicar_mue.sql y puntos_mue.csv')
