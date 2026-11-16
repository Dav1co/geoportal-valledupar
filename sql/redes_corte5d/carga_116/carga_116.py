#!/usr/bin/env python3
"""Corte 5d — carga inicial de la línea 116 (toda la historia desde 2020) por psql, por el MISMO motor del Cargue de capas (capa «linea_116»).
Lee el Excel (primera hoja, o la que se diga) y escribe, FUERA del repositorio (lleva direcciones y barrios: no se versiona):
  · ensayo_carga_116.sql   todo en UNA transacción que termina en ERROR a propósito («N de N … SIN FALLAS»): mide y no deja nada;
  · carga_116.sql          lo mismo, pero confirma si todas las comprobaciones dan bien (si una falla, ERROR y no queda nada).
NOMBRE no se escribe en ningún archivo: el lector solo toma REPORTE, ESTADO, FECHA_REGISTRO, CONTRATO, DIRECCION, BARRIO, COMUNA, DESC_CAUSAL y SERVICIO.
Uso: python3 -I carga_116.py "<ruta del .xlsx>" [carpeta de salida]
     (por omisión, la salida va a ~/geoportal-consultas/tecnica/paquete_fase1/corte5d/carga_116/; necesita openpyxl)."""
import collections
import datetime
import hashlib
import json
import os
import sys

import openpyxl

if len(sys.argv) < 2:
    raise SystemExit(__doc__)
ARCHIVO = sys.argv[1]
SALIDA = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser('~/geoportal-consultas/tecnica/paquete_fase1/corte5d/carga_116')
COLUMNAS = ['REPORTE', 'ESTADO', 'FECHA_REGISTRO', 'CONTRATO', 'DIRECCION', 'BARRIO', 'COMUNA', 'DESC_CAUSAL', 'SERVICIO']      # NOMBRE no está: no se lee


def texto(v):
    if v is None:
        return None
    if isinstance(v, datetime.datetime):
        return v.strftime('%Y-%m-%d %H:%M:%S')
    if isinstance(v, datetime.date):
        return v.strftime('%Y-%m-%d')
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    s = str(v).strip()
    return s or None


libro = openpyxl.load_workbook(ARCHIVO, read_only=True, data_only=True)
hoja = libro['Hoja1'] if 'Hoja1' in libro.sheetnames else libro[libro.sheetnames[0]]
filas_xl = hoja.iter_rows(values_only=True)
cab = [str(c or '').strip().upper() for c in next(filas_xl)]
faltan = [c for c in COLUMNAS if c not in cab]
if faltan:
    raise SystemExit(f'Al archivo le faltan las columnas {faltan}')
idx = {c: cab.index(c) for c in COLUMNAS}
filas = []
for f in filas_xl:
    if all(v is None for v in f):
        continue
    a = {c.lower(): texto(f[idx[c]]) for c in COLUMNAS}
    filas.append({'orden': len(filas) + 1, 'wkt': None, 'atributos': a})
libro.close()
n = len(filas)
reportes = [f['atributos']['reporte'] for f in filas]
rep = [r for r, k in collections.Counter(reportes).items() if k > 1]
estados = collections.Counter((f['atributos']['estado'] or '').strip().lower() for f in filas)
assert 'nombre' not in json.dumps([list(f['atributos']) for f in filas[:1]])
texto_json = json.dumps(filas, ensure_ascii=False, separators=(',', ':'))
assert '$lote$' not in texto_json
sha = hashlib.sha256(texto_json.encode('utf-8')).hexdigest()
md5_archivo = hashlib.md5(open(ARCHIVO, 'rb').read()).hexdigest()
lotes = [filas[i:i + 200] for i in range(0, n, 200)]
NOTA = f'Carga inicial de la línea 116 por psql: {os.path.basename(ARCHIVO)} ({n} reportes)'[:500]
MOTIVO = 'Carga inicial de toda la historia de la línea 116 (Corte 5d)'

CAB = """\\set ON_ERROR_STOP 1
\\if :{?solicitante}
\\else
  \\echo 'Falta el correo del administrador. Uso: psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO -f %s'
  \\quit
\\endif
\\pset pager off
\\timing on
"""
partes = [f"""begin;
set local statement_timeout = '10min';      -- toda la carga va en una transacción: este tope es solo de esta sesión de psql
select set_config('redes.l116_ensayo', :'es_ensayo', true) as ensayo \\gset
do $$
begin
  if to_regclass('redes.l116_reportes') is null then raise exception 'Falta el Corte 5d (tablas de la línea 116): publíquelo antes'; end if;
  if exists (select 1 from redes.v_cargas_estado where capa_codigo = 'linea_116' and estado = 'abierta') then raise exception 'Hay una carga abierta de la línea 116: anúlela antes'; end if;
end $$;
select public.geoportal_es_admin(lower(:'solicitante')) as es_admin \\gset
\\if :es_admin
\\else
  \\echo 'Ese correo no es de un administrador del geoportal: se detiene'
  select 1 / 0;
\\endif
create temp table _l116_t (paso text, ms numeric) on commit drop;
create temp table _l116_antes on commit drop as select count(*) as n from redes.l116_vigente;
\\set QUIET 1
select clock_timestamp() as t0 \\gset
select (public.geoportal_redes_cargue_iniciar(:'solicitante', 'linea_116', '{sha}', 'xlsx', 4326, 'reporte', {n}, '{NOTA.replace("'", "''")}') ->> 'carga_id') as carga \\gset
\\o /dev/null
"""]
for lote in lotes:
    partes.append(f"select public.geoportal_redes_carga_lote(:'solicitante', :carga, $lote${json.dumps(lote, ensure_ascii=False, separators=(',', ':'))}$lote$::jsonb);\n")
partes.append(f"""\\o
insert into _l116_t values ('subir {len(lotes)} lotes', round(extract(epoch from clock_timestamp() - :'t0'::timestamptz) * 1000));
\\unset QUIET
select clock_timestamp() as t0 \\gset
select r ->> 's' as seccion, r ->> 'c' as concepto, r ->> 'v' as valor from jsonb_array_elements(public.geoportal_redes_carga_resumen(:'solicitante', :carga) -> 'tabla') r;
insert into _l116_t values ('resumen', round(extract(epoch from clock_timestamp() - :'t0'::timestamptz) * 1000));
select clock_timestamp() as t0 \\gset
select key as dato, value as valor from jsonb_each_text(public.geoportal_redes_carga_publicar(:'solicitante', :carga, '{MOTIVO}')) order by 1;
insert into _l116_t values ('publicar', round(extract(epoch from clock_timestamp() - :'t0'::timestamptz) * 1000));
select clock_timestamp() as t0 \\gset
select (public.geoportal_redes_geovisor_capa(:'solicitante', 'pqr_116', ((clock_timestamp() at time zone 'America/Bogota')::date - interval '12 months')::date, null) -> 'features') is not null as capa_ok \\gset
insert into _l116_t values ('capa del geovisor, 12 meses', round(extract(epoch from clock_timestamp() - :'t0'::timestamptz) * 1000));
select paso, ms from _l116_t;
create temp table _l116_r on commit drop as select * from (
  select 1 as n, '01 llegaron las {n} filas del archivo y la carga quedó publicada' as nombre,
         (select count(*) from redes.carga_filas where carga_id = :carga) = {n} and exists (select 1 from redes.v_cargas_estado where id = :carga and estado = 'publicada') as ok
  union all select 2, '02 NOMBRE no está en la base: ninguna fila de la carga lo guarda y ninguna tabla de la 116 tiene esa columna',
         not exists (select 1 from redes.carga_filas where carga_id = :carga and (atributos ? 'nombre' or atributos ? 'NOMBRE'))
         and not exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name like 'l116\\_%' and column_name ~ 'nombre|telefono')
  union all select 3, '03 cada número de reporte del archivo está una sola vez ({n - len(rep)} distintos)',
         (select count(*) from redes.l116_reportes r where r.reporte in (select (f.atributos ->> 'reporte')::bigint from redes.carga_filas f where f.carga_id = :carga)) = {n - len(rep)}
  union all select 4, '04 los estados vigentes de los reportes del archivo cuadran con él (registrados {estados.get('registrado', 0)}, atendidos {estados.get('atendido', 0)})',
         (select count(*) filter (where v.estado = 'registrado') = {estados.get('registrado', 0)} and count(*) filter (where v.estado = 'atendido') = {estados.get('atendido', 0)}
            from redes.l116_vigente v where not v.oculto and v.reporte in (select (f.atributos ->> 'reporte')::bigint from redes.carga_filas f where f.carga_id = :carga))
  union all select 5, '05 todo reporte nuevo tiene su método de ubicación (contrato, dirección, barrio o sin ubicar) y su evento de alta',
         not exists (select 1 from redes.l116_reportes r left join redes.l116_eventos e on e.reporte_id = r.id and e.tipo = 'alta' where r.carga_id = :carga and e.metodo is null)
  union all select 6, '06 la publicación y la capa del geovisor (12 meses) en menos de 30 s y 8 s',
         (select ms from _l116_t where paso = 'publicar') < 30000 and (select ms from _l116_t where paso like 'capa%') < 8000
  union all select 7, '07 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where())
) t;
select n, case when ok then 'OK' else 'FALLA' end as resultado, nombre from _l116_r order by n;
select 'INFO ubicación de los reportes de esta carga: ' || string_agg(metodo || ' ' || k, ' · ' order by metodo) as info
  from (select e.metodo, count(*) as k from redes.l116_eventos e join redes.l116_reportes r on r.id = e.reporte_id where r.carga_id = :carga and e.tipo = 'alta' group by 1) x;
do $$
declare v_t integer; v_b integer;
begin
  select count(*), count(*) filter (where ok) into v_t, v_b from _l116_r;
  if v_b <> v_t or current_setting('redes.l116_ensayo', true) = 'si' then
    raise exception 'CARGA DE LA LÍNEA 116 · CORTE 5d%: % de % comprobaciones correctas — %',
      case when current_setting('redes.l116_ensayo', true) = 'si' then ' (ENSAYO: este ERROR es el esperado y deshace todo)' else ' (se deshace todo)' end,
      v_b, v_t, case when v_b = v_t then 'SIN FALLAS' else (v_t - v_b) || ' FALLA(S)' end;
  end if;
  raise notice 'CARGA DE LA LÍNEA 116 · CORTE 5d: % de % comprobaciones correctas — SIN FALLAS', v_b, v_t;
end $$;
commit;
""")
cuerpo = ''.join(partes)
os.makedirs(SALIDA, exist_ok=True)
for nombre, ensayo, titulo in (('ensayo_carga_116.sql', 'si', 'ENSAYO (no deja nada; termina en ERROR a propósito)'),
                               ('carga_116.sql', 'no', 'CARGA (confirma solo si todo da bien)')):
    open(os.path.join(SALIDA, nombre), 'w', encoding='utf-8').write(
        f"""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d — CARGA INICIAL DE LA LÍNEA 116: {titulo}. Generado por carga_116/carga_116.py (no se versiona: lleva direcciones).
--   psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO_DEL_ADMINISTRADOR -f {nombre}
-- Archivo: {os.path.basename(ARCHIVO)} (md5 {md5_archivo}) · {n} reportes · {len(lotes)} lotes de 200 · sha256 de las filas {sha}
-- Sin NOMBRE: solo {', '.join(COLUMNAS)}.
-- =====================================================================
{CAB % nombre}\\set es_ensayo {ensayo}
{cuerpo}""")
print(f'{n} reportes ({len(rep)} números repetidos) · estados {dict(estados)} · {len(lotes)} lotes · sha256 {sha} · {SALIDA}/ensayo_carga_116.sql y carga_116.sql')
