#!/usr/bin/env python3
"""Corte 9a-bis — los 7 sectores y 29 subsectores del Plan Maestro SON los que se operan hoy (respuesta 4 de David, 16-nov-2026).
Vuelve a cargar por el MOTOR del Cargue (capa «sectores») los mismos polígonos de regulatorio/salida_geoportal/, ahora en estado «En operación» y con el
origen dicho así. El motor ve 36 «cambiados» y crea una versión nueva de cada uno: nada se borra, la versión «Proyectado» queda en el historial y se puede
volver a ella con «Volver a la versión anterior» del Cargue. Los polígonos no cambian (lo comprueba).
Escribe en generado/:
  · ensayo_sectores_oficiales.sql  todo en UNA transacción que termina en ERROR a propósito («N de N … SIN FALLAS»);
  · sectores_oficiales.sql         lo mismo, pero confirma si todas las comprobaciones dan bien (si una falla, ERROR y no queda nada).
Uso: python3 -I sectores_oficiales.py   (no necesita base de datos)."""
import hashlib
import json
import os
import sqlite3
import struct

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.join(AQUI, 'generado')
FUENTE = os.environ.get('SALIDA_GEOPORTAL', os.path.expanduser('~/geoportal-consultas/tecnica/paquete_fase1/regulatorio/salida_geoportal'))
ORIGEN = 'Plan Maestro 2014, Anexo C. Sectores con que opera EMDUPAR (confirmado por David el 16-nov-2026)'
NOTA = 'Los 7 sectores y 29 subsectores del Plan Maestro 2014 son los que se operan hoy (David, 16-nov-2026): pasan de «Proyectado» a «En operación»'


def num(x):
    return ('%.9f' % x).rstrip('0').rstrip('.')


def wkt_de_gpkg(blob):
    """Geometría de GeoPackage (cabecera GP + WKB) → WKT en 2D (la misma lectura de carga_pm.py del 9a)."""
    flags = blob[3]
    env = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}[(flags >> 1) & 7]
    d = memoryview(blob)[8 + env:]
    pos = 0

    def leer():
        nonlocal pos
        o = '<' if d[pos] == 1 else '>'
        t = struct.unpack_from(o + 'I', d, pos + 1)[0]
        pos += 5
        dims = 2 + (1 if (t // 1000 in (1, 3) or t & 0x80000000) else 0) + (1 if (t // 1000 in (2, 3) or t & 0x40000000) else 0)
        t = (t & 0xFFFF) % 1000

        def pto():
            nonlocal pos
            c = struct.unpack_from(o + 'd' * dims, d, pos)
            pos += 8 * dims
            return f'{num(c[0])} {num(c[1])}'

        def anillo():
            nonlocal pos
            n = struct.unpack_from(o + 'I', d, pos)[0]
            pos += 4
            return '(' + ','.join(pto() for _ in range(n)) + ')'

        def varios(f):
            nonlocal pos
            n = struct.unpack_from(o + 'I', d, pos)[0]
            pos += 4
            return [f() for _ in range(n)]
        if t == 3:
            return 'POLYGON', '(' + ','.join(varios(anillo)) + ')'
        if t == 6:
            return 'MULTIPOLYGON', '(' + ','.join(x[1] for x in varios(leer)) + ')'
        raise ValueError(f'geometría no admitida: {t}')
    tipo, cuerpo = leer()
    return tipo + cuerpo


def capa(nombre):
    c = sqlite3.connect(os.path.join(FUENTE, 'capas', nombre + '.gpkg'))
    c.row_factory = sqlite3.Row
    out = [dict(r) for r in c.execute(f'select * from "{nombre}" order by fid')]
    c.close()
    return out


def md5(rel):
    return hashlib.md5(open(os.path.join(FUENTE, rel), 'rb').read()).hexdigest()


filas = []
for r in capa('sectores_hidraulicos'):
    filas.append({'atributos': {'llave': r['llave'], 'nombre': f"Sector {r['sector']}", 'clase': 'sector', 'estado': 'En operación', 'sector': int(r['sector']),
                                'subsectores': r['subsectores'], 'tanque_plan': r['tanque_plan'], 'area_ha': r['area_ha'], 'origen': ORIGEN}, 'wkt': wkt_de_gpkg(r['geom'])})
for r in capa('subsectores_hidraulicos'):
    filas.append({'atributos': {'llave': r['llave'], 'nombre': f"Subsector {r['subsector']}", 'clase': 'subsector', 'estado': 'En operación', 'sector': int(r['sector']),
                                'subsector': str(r['subsector']), 'area_ha': r['area_ha'], 'origen': ORIGEN}, 'wkt': wkt_de_gpkg(r['geom'])})
assert len(filas) == 36
for i, f in enumerate(filas, start=1):
    f['orden'] = i
texto = json.dumps(filas, ensure_ascii=False, separators=(',', ':'))
assert '$lote$' not in texto
sha = hashlib.sha256(texto.encode('utf-8')).hexdigest()
archivos = '\n'.join(f'--   {md5(a)}  {a}' for a in ('capas/sectores_hidraulicos.gpkg', 'capas/subsectores_hidraulicos.gpkg'))

CAB = """\\set ON_ERROR_STOP 1
\\if :{?solicitante}
\\else
  \\echo 'Falta el correo del administrador. Uso: psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO -f %s'
  \\quit
\\endif
\\pset pager off
\\timing on
"""
cuerpo = f"""begin;
select set_config('redes.sec_ensayo', :'es_ensayo', true) as ensayo \\gset
do $$
begin
  if (select count(*) from redes.activo_vigente_mat where prefijo = 'SEC' and capa_codigo = 'sectores' and not retirado) <> 36 then
    raise exception 'No están los 36 polígonos de sectores del Plan publicados (carga del Corte 9a): deténgase y avise';
  end if;
  if exists (select 1 from redes.v_cargas_estado where capa_codigo = 'sectores' and estado = 'abierta') then raise exception 'Hay una carga abierta de la capa de sectores: anúlela antes'; end if;
end $$;
select public.geoportal_es_admin(lower(:'solicitante')) as es_admin \\gset
\\if :es_admin
\\else
  \\echo 'Ese correo no es de un administrador del geoportal: se detiene'
  select 1 / 0;
\\endif
create temp table _sec_antes on commit drop as select m.codigo, m.version, m.estado_codigo, m.geom from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado;
\\set QUIET 1
select (public.geoportal_redes_carga_iniciar(:'solicitante', 'sectores', '{sha}', 'gpkg', 4326, 'llave', 36, '{NOTA.replace("'", "''")}') ->> 'carga_id') as carga \\gset
\\o /dev/null
select public.geoportal_redes_carga_lote(:'solicitante', :carga, $lote${texto}$lote$::jsonb);
\\o
\\unset QUIET
select r ->> 's' as seccion, r ->> 'c' as concepto, r ->> 'v' as valor from jsonb_array_elements(public.geoportal_redes_carga_resumen(:'solicitante', :carga) -> 'tabla') r;
select key as dato, value as valor from jsonb_each_text(public.geoportal_redes_carga_publicar(:'solicitante', :carga, '{NOTA.replace("'", "''")}')) order by 1;
create temp table _sec_r on commit drop as select * from (
  select 1 as n, '01 los 36 polígonos de sectores siguen vigentes (7 sectores y 29 subsectores), ahora todos «En operación»' as nombre,
         (select count(*) filter (where clase = 'sector') = 7 and count(*) filter (where clase = 'subsector') = 29 and count(*) filter (where estado_codigo <> 'en_operacion') = 0
            from redes.activo_vigente_mat where prefijo = 'SEC' and capa_codigo = 'sectores' and not retirado) as ok
  union all select 2, '02 cada uno tiene una versión nueva (la «Proyectado» queda en el historial) y su polígono no cambió',
         (select count(*) from _sec_antes a join redes.activo_vigente_mat m on m.codigo = a.codigo where m.version = a.version + 1 and ST_Equals(m.geom, a.geom)) = 36
  union all select 3, '03 ningún activo se retiró ni se ocultó con esta carga', not exists (select 1 from redes.activo_eventos e where e.tipo in ('retirar', 'ocultar') and e.creado_en >= transaction_timestamp())
  union all select 4, '04 el sector de un punto en cada subsector sigue dando el mismo número',
         not exists (select 1 from redes.activo_vigente_mat m join redes.activo_versiones v on v.activo_id = m.activo_id and v.version = m.version
                      cross join lateral redes.f_sector_de(ST_PointOnSurface(m.geom)) s
                      where m.prefijo = 'SEC' and m.clase = 'subsector' and not m.retirado and (s.subsector is distinct from v.atributos -> 'modelo' ->> 'subsector'))
  union all select 5, '05 el origen de los polígonos dice que son los sectores con que se opera',
         (select count(*) from redes.activo_vigente_mat m join redes.activo_versiones v on v.activo_id = m.activo_id and v.version = m.version
           where m.prefijo = 'SEC' and not m.retirado and v.atributos -> 'modelo' ->> 'origen' like '%Sectores con que opera EMDUPAR%') = 36
  union all select 6, '06 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where())
) t;
select n, case when ok then 'OK' else 'FALLA' end as resultado, nombre from _sec_r order by n;
do $$
declare v_t integer; v_b integer;
begin
  select count(*), count(*) filter (where ok) into v_t, v_b from _sec_r;
  if v_b <> v_t or current_setting('redes.sec_ensayo', true) = 'si' then
    raise exception 'SECTORES OFICIALES · CORTE 9a-bis%: % de % comprobaciones correctas — %',
      case when current_setting('redes.sec_ensayo', true) = 'si' then ' (ENSAYO: este ERROR es el esperado y deshace todo)' else ' (se deshace todo)' end,
      v_b, v_t, case when v_b = v_t then 'SIN FALLAS' else (v_t - v_b) || ' FALLA(S)' end;
  end if;
  raise notice 'SECTORES OFICIALES · CORTE 9a-bis: % de % comprobaciones correctas — SIN FALLAS', v_b, v_t;
end $$;
commit;
"""
os.makedirs(SALIDA, exist_ok=True)
for nombre, ensayo, titulo in (('ensayo_sectores_oficiales.sql', 'si', 'ENSAYO (no deja nada; termina en ERROR a propósito)'),
                               ('sectores_oficiales.sql', 'no', 'CARGA (confirma solo si todo da bien)')):
    open(os.path.join(SALIDA, nombre), 'w', encoding='utf-8').write(
        f"""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis — LOS SECTORES DEL PLAN SON LOS DE HOY: {titulo}. Generado por carga_sectores/sectores_oficiales.py.
--   psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO_DEL_ADMINISTRADOR -f {nombre}
-- Vuelve a cargar por el motor del Cargue los mismos 36 polígonos, en estado «En operación». Archivos (md5):
{archivos}
-- =====================================================================
{CAB % nombre}\\set es_ensayo {ensayo}
{cuerpo}""")
print(f'36 polígonos · sha256 {sha} · generado/ensayo_sectores_oficiales.sql y sectores_oficiales.sql')
