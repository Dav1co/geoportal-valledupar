#!/usr/bin/env python3
"""Arma la carga inicial del mapa de la PTAR El Salguero (SQL _editor) desde el GeoJSON de David y la copia D12 de los activos de redes dentro del perímetro.
No consulta ninguna base: solo lee el GeoJSON y escribe archivos SQL. Lo que se carga en producción lo aplica Claude con David.
Uso: python3 -I generar_carga.py RUTA_DEL_GEOJSON [--salida CARPETA]
  -h / --help  imprime este uso. Una opción que no conoce es un error (no se ignora).
Escribe en la carpeta de salida (por omisión, la de este guion):
  carga_ptar_el_salguero_editor.sql         · una transacción: guardia, elementos del dibujo, copia D12 desde redes y comprobación de lo cargado
  verificacion_carga_ptar_el_salguero_editor.sql · una consulta de solo lectura (cuántos por tipo y origen, y las reglas)
  reversa_carga_ptar_el_salguero_editor.sql · desactiva con motivo lo cargado (nada se borra, D9)"""
import hashlib
import json
import os
import re
import sys

USO = __doc__
args = sys.argv[1:]
if not args or args[0] in ('-h', '--help'):
    print(USO); sys.exit(0 if args else 2)
ruta = None
salida = os.path.dirname(os.path.abspath(__file__))
i = 0
while i < len(args):
    a = args[i]
    if a in ('-h', '--help'):
        print(USO); sys.exit(0)
    elif a == '--salida':
        if i + 1 >= len(args):
            print('Falta la carpeta después de --salida', file=sys.stderr); sys.exit(2)
        salida = args[i + 1]; i += 2; continue
    elif a.startswith('-'):
        print(f'Opción desconocida: {a} (-h para el uso)', file=sys.stderr); sys.exit(2)
    elif ruta is None:
        ruta = a
    else:
        print(f'Sobra el argumento: {a} (-h para el uso)', file=sys.stderr); sys.exit(2)
    i += 1
if ruta is None:
    print('Falta la ruta del GeoJSON (-h para el uso)', file=sys.stderr); sys.exit(2)

INSTALACION = 'ptar'
AUTOR = 'carga.ptar@emdupar.gov.co'
TIPOS_GEOM = {'perimetro': ('Polygon', 'MultiPolygon'), 'laguna': ('Polygon', 'MultiPolygon'), 'tramo': ('LineString', 'MultiLineString'),
              'punto_medicion': ('Point',), 'pozo': ('Point',), 'descarga': ('Point',)}
COD = re.compile(r'^[A-Z0-9][A-Z0-9_-]{1,39}$')
ACT = re.compile(r'^[A-Z]{3}-[0-9]{6}$')
BASICAS = {'nombre', 'tipo', 'planta', 'orden', 'codigo', 'punto', 'desde', 'hasta', 'activo_codigo'}
# Capas de redes que se copian (D12): pozos como «pozo», descargas (VER) como «descarga» (David, 21-nov) y conductos como «tramo» sin desde/hasta.
# Se pintan TODOS los activos que tocan el perímetro, salvo los que el GeoJSON ya trae como activo_codigo (regla de David, 21-nov: nada pintado dos veces).
CAPAS_D12 = ('alc_pozos', 'alc_conductos', 'alc_descargas')

crudo = open(ruta, 'rb').read()
huella_geojson = hashlib.md5(crudo).hexdigest()
d = json.loads(crudo)
errores = []
if d.get('type') != 'FeatureCollection' or not isinstance(d.get('features'), list):
    sys.exit('El archivo no es un FeatureCollection de GeoJSON')

elems = []
vistos = set()
for n, f in enumerate(d['features'], 1):
    p = f.get('properties') or {}
    g = f.get('geometry') or {}
    donde = f'elemento {n} ({p.get("codigo") or p.get("nombre") or "sin código"})'
    for k in ('nombre', 'tipo', 'planta', 'orden', 'codigo'):
        if p.get(k) in (None, ''):
            errores.append(f'{donde}: falta «{k}»')
    tipo, cod = p.get('tipo'), str(p.get('codigo') or '')
    if tipo not in TIPOS_GEOM:
        errores.append(f'{donde}: tipo «{tipo}» no válido (perimetro, laguna, tramo, punto_medicion, pozo o descarga)'); continue
    if g.get('type') not in TIPOS_GEOM[tipo]:
        errores.append(f'{donde}: un «{tipo}» no puede ser {g.get("type")}')
    if p.get('planta') != INSTALACION:
        errores.append(f'{donde}: la planta debe ser «{INSTALACION}»')
    if not COD.match(cod):
        errores.append(f'{donde}: código «{cod}» no válido (mayúsculas, números, guion; 2 a 40)')
    if cod in vistos:
        errores.append(f'{donde}: código repetido «{cod}»')
    vistos.add(cod)
    if not isinstance(p.get('orden'), int) or not 0 <= p['orden'] <= 999:
        errores.append(f'{donde}: el orden es un entero de 0 a 999')
    if not 2 <= len(str(p.get('nombre') or '').strip()) <= 120:
        errores.append(f'{donde}: el nombre va de 2 a 120 caracteres')
    act = p.get('activo_codigo')
    if act is not None and not ACT.match(str(act)):
        errores.append(f'{donde}: activo_codigo «{act}» no válido (p. ej. POZ-005503)')
    if (p.get('desde') or p.get('hasta')) and tipo != 'tramo':
        errores.append(f'{donde}: solo un tramo lleva desde/hasta')
    if p.get('punto') and tipo != 'punto_medicion':
        errores.append(f'{donde}: solo un punto de medición lleva «punto»')
    atrib = {k: v for k, v in p.items() if k not in BASICAS and v is not None}
    if p.get('punto'):
        atrib['punto_previsto'] = p['punto']          # el punto de tecnica.puntos se crea con los formularios (corte aparte); aquí queda anotado
    elems.append({'codigo': cod, 'tipo': tipo, 'nombre': str(p['nombre']).strip(), 'orden': p.get('orden', 0), 'geom': json.dumps(g, separators=(',', ':')),
                  'activo': act, 'punto': p.get('punto'), 'desde': p.get('desde'), 'hasta': p.get('hasta'), 'atributos': json.dumps(atrib, ensure_ascii=False, separators=(',', ':'))})
for e in elems:
    for k in ('desde', 'hasta'):
        if e[k] and e[k] not in vistos:
            errores.append(f'{e["codigo"]}: «{k}» apunta a «{e[k]}», que no está en el archivo')
per = [e for e in elems if e['tipo'] == 'perimetro']
if len(per) != 1:
    errores.append(f'Debe haber exactamente un perímetro y hay {len(per)}')
if errores:
    print('El GeoJSON tiene errores; no se generó nada:\n  ' + '\n  '.join(errores), file=sys.stderr); sys.exit(1)


def lit(s):
    return 'null' if s is None else "'" + str(s).replace("'", "''") + "'"


def fila(e, flujo):
    desde = f"(select id from tecnica.elementos_planta where codigo = {lit(e['desde'])} and activo)" if flujo and e['desde'] else 'null'
    hasta = f"(select id from tecnica.elementos_planta where codigo = {lit(e['hasta'])} and activo)" if flujo and e['hasta'] else 'null'
    punto = f"(select id from tecnica.puntos where codigo = {lit(e['punto'])} and tipo = 'ptar' and activo)" if e['punto'] else 'null'
    return (f"  ((select id from _inst), {lit(e['codigo'])}, {lit(e['tipo'])}, {lit(e['nombre'])}, {e['orden']}, st_setsrid(st_geomfromgeojson({lit(e['geom'])}), 4326), "
            f"{desde}, {hasta}, {punto}, {lit(e['activo'])}, {lit(e['atributos'])}::jsonb, 'dibujo', {lit(AUTOR)})")


COLS = 'instalacion_id, codigo, tipo, nombre, orden, geom, desde_id, hasta_id, punto_id, activo_codigo, atributos, origen, creado_por'
puntos_ptar = sorted({e['punto'] for e in elems if e['punto']})
sin_flujo = [e for e in elems if not (e['desde'] or e['hasta'])]
con_flujo = [e for e in elems if e['desde'] or e['hasta']]
cuenta = {}
for e in elems:
    cuenta[e['tipo']] = cuenta.get(e['tipo'], 0) + 1
n_dibujo = len(elems)
codigos_dibujo = ', '.join(lit(e['activo']) for e in elems if e['activo']) or 'null'
per_cod = per[0]['codigo']

carga = f"""-- =====================================================================
-- TÉCNICA · PTAR (Code C) · CARGA INICIAL DEL MAPA DE LA PTAR EL SALGUERO (generado por carga/generar_carga.py; no se edita a mano).
-- GeoJSON: {os.path.basename(ruta)} · md5 {huella_geojson} · {n_dibujo} elementos del dibujo ({', '.join(f'{k} {v}' for k, v in sorted(cuenta.items()))}).
-- Más la copia D12: los activos vigentes de redes ({', '.join(CAPAS_D12)}) que tocan el perímetro {per_cod}, sin retirados ni ocultos y sin los que ya están en el dibujo.
-- redes NO se toca (solo se lee redes.v_activo_vigente). Nada se borra. Va DESPUÉS de la migración de PTAR-1. Una transacción: si algo no calza, no queda nada.
-- =====================================================================
begin;
do $$
begin
  if to_regclass('tecnica.elementos_planta') is null then raise exception 'CARGA PTAR: falta la migración de PTAR-1 (tecnica.elementos_planta)'; end if;
  if not exists (select 1 from tecnica.instalaciones where codigo = '{INSTALACION}' and activa) then raise exception 'CARGA PTAR: falta la instalación {INSTALACION}'; end if;
  if exists (select 1 from tecnica.elementos_planta e join tecnica.instalaciones i on i.id = e.instalacion_id where i.codigo = '{INSTALACION}' and e.activo) then
    raise exception 'CARGA PTAR: la PTAR ya tiene elementos activos: esta carga es solo la inicial (para corregir, desactive con motivo y cree la fila nueva, D9)';
  end if;
  if (select count(*) from tecnica.puntos where codigo in ({', '.join(lit(x) for x in puntos_ptar) or "''"}) and tipo = 'ptar' and activo) <> {len(puntos_ptar)} then
    raise exception 'CARGA PTAR: faltan los puntos de la PTAR ({', '.join(puntos_ptar)}): aplique antes PTAR-3 (tecnica_ptar_control)';
  end if;
end $$;
create temp table _inst on commit drop as select id from tecnica.instalaciones where codigo = '{INSTALACION}';

-- 1. El dibujo de David (primero lo que no lleva flujo; luego los tramos con desde/hasta, que apuntan a elementos ya cargados)
insert into tecnica.elementos_planta ({COLS}) values
{(','+chr(10)).join(fila(e, False) for e in sin_flujo)};
""" + (f"""insert into tecnica.elementos_planta ({COLS}) values
{(','+chr(10)).join(fila(e, True) for e in con_flujo)};
""" if con_flujo else '') + f"""
-- 2. Copia D12 desde redes: lo que toca el perímetro (pozos, descargas y conductos como «tramo» sin desde/hasta), menos lo que ya trae el dibujo
insert into tecnica.elementos_planta ({COLS})
select (select id from _inst), 'PTAR-' || v.codigo, case v.capa_codigo when 'alc_conductos' then 'tramo' when 'alc_descargas' then 'descarga' else 'pozo' end,
       coalesce(nullif(btrim(v.nombre), ''), case v.prefijo when 'POZ' then 'Pozo ' when 'COL' then 'Conducto ' when 'VER' then 'Descarga ' else 'Activo ' end || v.codigo),
       0, v.geom, null, null, null, v.codigo,
       jsonb_strip_nulls(jsonb_build_object('capa', v.capa_codigo, 'prefijo', v.prefijo, 'version_redes', v.version, 'diametro_mm', v.diametro_mm,
                                            'material', v.material_codigo, 'profundidad_m', v.profundidad_m)),
       'redes', {lit(AUTOR)}
  from redes.v_activo_vigente v
 where v.capa_codigo in ({', '.join(lit(c) for c in CAPAS_D12)}) and not v.retirado and not v.oculto
   and st_intersects(v.geom, (select e.geom from tecnica.elementos_planta e where e.codigo = {lit(per_cod)} and e.activo))
   and v.codigo not in ({codigos_dibujo});

-- 3. Comprobación (si algo no calza, ERROR y no queda nada)
do $$
declare v_d integer; v_r integer; v_p integer; v_t integer; v_v integer; v_fuera integer;
begin
  select count(*) filter (where origen = 'dibujo'), count(*) filter (where origen = 'redes'), count(*) filter (where origen = 'redes' and tipo = 'pozo'),
         count(*) filter (where origen = 'redes' and tipo = 'tramo'), count(*) filter (where origen = 'redes' and tipo = 'descarga')
    into v_d, v_r, v_p, v_t, v_v from tecnica.elementos_planta where instalacion_id = (select id from _inst) and activo;
  if v_d <> {n_dibujo} then raise exception 'CARGA PTAR: se cargaron % elementos del dibujo y el archivo trae {n_dibujo}', v_d; end if;
  if v_p = 0 or v_t = 0 then raise exception 'CARGA PTAR: la copia de redes no trajo pozos (%) o conductos (%)', v_p, v_t; end if;
  select count(*) into v_fuera from tecnica.elementos_planta e left join redes.activos a on a.codigo = e.activo_codigo
   where e.instalacion_id = (select id from _inst) and e.origen = 'redes' and a.id is null;
  if v_fuera > 0 then raise exception 'CARGA PTAR: % elementos copiados no tienen su activo en redes', v_fuera; end if;
  if exists (select 1 from redes.f_funciones_sin_where()) then raise exception 'CARGA PTAR: hay funciones con DELETE o UPDATE sin WHERE'; end if;
  raise notice 'CARGA PTAR: % del dibujo + % copiados de redes (% pozos, % descargas, % tramos) = % elementos', v_d, v_r, v_p, v_v, v_t, v_d + v_r;
end $$;
commit;
"""

verif = f"""-- TÉCNICA · PTAR · VERIFICACIÓN DE LA CARGA INICIAL (solo lectura; una consulta, apta para el editor SQL). GeoJSON md5 {huella_geojson}.
with e as (select e.* from tecnica.elementos_planta e join tecnica.instalaciones i on i.id = e.instalacion_id where i.codigo = '{INSTALACION}' and e.activo)
select k, valor, case when ok then 'OK' else 'REVISAR' end as estado from (
  select 1 as o, 'elementos del dibujo (esperado {n_dibujo})' as k, count(*)::text as valor, count(*) = {n_dibujo} as ok from e where origen = 'dibujo'
  union all select 2, 'copiados de redes: pozos', count(*)::text, count(*) > 0 from e where origen = 'redes' and tipo = 'pozo'
  union all select 2, 'copiados de redes: descargas (VER)', count(*)::text, bool_and(activo_codigo like 'VER-%') is not false from e where origen = 'redes' and tipo = 'descarga'
  union all select 2, 'ningún activo del dibujo copiado otra vez', (select count(*) from e x join e y on x.activo_codigo = y.activo_codigo and x.origen = 'dibujo' and y.origen = 'redes')::text,
                   not exists (select 1 from e x join e y on x.activo_codigo = y.activo_codigo and x.origen = 'dibujo' and y.origen = 'redes') from (select 1) z
  union all select 3, 'copiados de redes: conductos (tramos sin desde/hasta)', count(*)::text, count(*) > 0 and bool_and(desde_id is null and hasta_id is null) from e where origen = 'redes' and tipo = 'tramo'
  union all select 4, 'perímetro (esperado 1)', count(*)::text, count(*) = 1 from e where tipo = 'perimetro'
  union all select 5, 'lagunas', count(*)::text, count(*) = {cuenta.get('laguna', 0)} from e where tipo = 'laguna'
  union all select 5, 'puntos de medición enlazados a su punto de la PTAR (esperado {len(puntos_ptar)})', count(punto_id)::text, count(punto_id) = {len(puntos_ptar)} from e where tipo = 'punto_medicion'
  union all select 6, 'copiados con su activo en redes', count(a.id)::text || ' de ' || count(*)::text, count(a.id) = count(*) from e left join redes.activos a on a.codigo = e.activo_codigo where e.origen = 'redes'
  union all select 7, 'sin activos repetidos', (count(*) - count(distinct activo_codigo))::text, count(*) = count(distinct activo_codigo) from e where activo_codigo is not null
  union all select 8, 'pg-safeupdate: funciones con DELETE/UPDATE sin WHERE', (select count(*) from redes.f_funciones_sin_where())::text, not exists (select 1 from redes.f_funciones_sin_where())
) t order by o;
"""

reversa = f"""-- TÉCNICA · PTAR · REVERSA DE LA CARGA INICIAL: desactiva con motivo todo lo cargado de la PTAR (nada se borra, D9). Solo si hace falta repetir la carga.
begin;
update tecnica.elementos_planta set activo = false, motivo_inactivo = 'Reversa de la carga inicial del mapa de la PTAR (GeoJSON md5 {huella_geojson})'
 where activo and creado_por = {lit(AUTOR)} and instalacion_id = (select id from tecnica.instalaciones where codigo = '{INSTALACION}');
commit;
"""

os.makedirs(salida, exist_ok=True)
for nombre, texto in (('carga_ptar_el_salguero_editor.sql', carga), ('verificacion_carga_ptar_el_salguero_editor.sql', verif),
                      ('reversa_carga_ptar_el_salguero_editor.sql', reversa)):
    open(os.path.join(salida, nombre), 'w', encoding='utf-8').write(texto)
print(f'GeoJSON md5 {huella_geojson}: {n_dibujo} elementos del dibujo ({", ".join(f"{k} {v}" for k, v in sorted(cuenta.items()))}); '
      f'activos del dibujo excluidos de la copia D12: {codigos_dibujo}. Archivos en {salida}')
