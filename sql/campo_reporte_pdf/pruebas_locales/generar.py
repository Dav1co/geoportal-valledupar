#!/usr/bin/env python3
"""[Code A] Genera los _editor del paquete «PDF de Reportar anomalía» (27-nov) desde ../sql y un doble local de producción. NUNCA Supabase.

El doble, sobre PostGIS REAL (el mapa necesita st_transform, st_intersection, índices GiST…):
  1. el volcado del doble 4a SIN su PostGIS de juguete (tipos geometry/geography, la conversión, 7 funciones st_*, f_knn_doble y el operador <->), con CREATE EXTENSION postgis en public;
  2. la misma cadena publicada que usan los paquetes anteriores: Investigación y Análisis → registro flexible → consultar direcciones → etiqueta del último pago
     = huella de campo 9f8b8ec5… (collate "C"); acta 111506c6…;
  3. las capas del mapa con la estructura de producción que este paquete lee: public.redes_acueducto y public.redes_alcantarillado (tablas, geom MULTILINESTRING 4326,
     índices GiST idx_redes_acu_geom / idx_redes_alc_geom) con las 10.578 y 9.064 líneas reales (de redes.activo_versiones de la base emdupar_b, solo lectura),
     y public.predios_comercial como VISTA MATERIALIZADA (misma clase que producción) con geom POINT 4326 e índice GiST idx_predcom_geom_n, con los 112 mil
     predios del catastro de emdupar_b (solo lectura).
Uso: python3 -I generar.py [-h]"""
import sys, re, json, hashlib, pathlib, importlib.util, subprocess, tempfile
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
import psycopg
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent; SQL = PAQ / "sql"
CASA = pathlib.Path.home()
PAGO = CASA / "geoportal-emdupar-pago/sql/campo_etiqueta_pago"
_s = importlib.util.spec_from_file_location("gpago", PAGO / "pruebas_locales/generar.py"); gp = importlib.util.module_from_spec(_s); _s.loader.exec_module(gp)
gnd = gp.gnd; gn0 = gnd.gn0
NOMBRE = "campo_reporte_pdf"
lit = gn0.lit; poner = gn0.poner; SINWHERE = gn0.SINWHERE; PERMISOS = gn0.PERMISOS; EST_EXPR = gn0.EST_EXPR; PSQL = gn0.PSQL; PUERTO = gn0.PUERTO
HUELLA = dict(gp.HUELLA)
PUBLICADA = {"campo": "9f8b8ec55fc7e1c56fdf74a5f4e7f3c4", "acta": "111506c690249ad3b56ebf572566434c"}
TECNICA_PRODUCCION = gn0.TECNICA_PRODUCCION
DUMP_4A = CASA / "geoportal-consultas/campo/admin_perfiles_22nov/doble_admin_4a/doble_admin_permisos_4a_con_cargo_supervisor.sql"
ORIGEN_CAPAS = "emdupar_b"       # solo lectura: redes.activo_versiones y catastro_valledupar
RPC = ["public.geoportal_campo_ran_datos(text,uuid,text)", "public.geoportal_campo_ran_registrar(text,uuid,text,text,integer,integer,text)",
       "public.geoportal_campo_ran_obtener(text,uuid,text)"]
INTERNAS = ["campo.f_ran_numerar(uuid)", "campo.f_ran_autorizar(text,uuid)", "campo.f_ran_persona(text)", "campo.f_ran_contenido(uuid)", "campo.f_ran_destino(uuid,text)",
            "campo.f_ran_mapa(numeric,numeric,numeric,numeric)"]
NUEVAS = INTERNAS + RPC
# Columnas que el paquete lee, con su tipo (las de producción; el doble las tiene iguales)
COLUMNAS = [("campo.reportes", c, t) for c, t in [("id", "uuid"), ("seq", "bigint"), ("tipo_id", "bigint"), ("subtipo_id", "bigint"), ("descripcion", "text"), ("contrato", "text"),
            ("lat", "numeric(9,6)"), ("lon", "numeric(9,6)"), ("precision_m", "numeric(8,1)"), ("autor", "text"), ("registrado_en", "timestamp with time zone"),
            ("inicio_en", "timestamp with time zone"), ("inicio_origen", "text")]] + \
  [("campo.reporte_fotos", "orden", "smallint"), ("campo.reporte_fotos", "ruta_storage", "text"), ("campo.reporte_fotos", "etiqueta", "text"), ("campo.reporte_fotos", "origen", "text"),
   ("campo.reporte_eventos", "tipo_evento", "text"), ("campo.reporte_eventos", "estado_nuevo", "text"), ("campo.reporte_eventos", "motivo", "text"), ("campo.reporte_eventos", "acta_id", "uuid"),
   ("campo.reporte_eventos", "reporte_original_id", "uuid"), ("campo.reporte_registro", "xy_manual", "boolean"), ("campo.reporte_registro", "lat_registro", "numeric(9,6)"),
   ("campo.reporte_registro", "direccion", "text"), ("campo.reporte_direccion_contrato", "direccion_comercial", "text"), ("campo.reporte_direccion_contrato", "direccion_catastro", "text"),
   ("campo.estados_reporte", "nombre", "text"), ("public.geoportal_lista_blanca", "nombre", "text"), ("acta.actas", "consecutivo", "text")]
PARTES = ["05_guardia.sql", "10_estructura.sql", "20_funciones.sql"]
lee = lambda n: (SQL / n).read_text()
CAB = "-- [Code A] PDF DE «REPORTAR ANOMALÍA» (27-nov) · {que} (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)\n"
def cuerpo(): return "\n".join(lee(n) for n in PARTES)
def md5f(con, f): return con.execute("select md5(pg_get_functiondef(to_regprocedure(%s)))", (f,)).fetchone()[0]
def est(con, t): return con.execute(f"select {EST_EXPR} from (select to_regclass(%s) as rel) z", (t,)).fetchone()[0]
def a_local(texto, hl=None): return gp.a_local(texto)
def psql(db, *args, entrada=None):
    r = subprocess.run([PSQL, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-h", "localhost", "-p", PUERTO, "-U", "postgres", "-d", db, *args], input=entrada, capture_output=True, text=True)
    if r.returncode: raise SystemExit(f"psql {db}: {r.stderr[-1500:]}")
    return r.stdout

def volcado_postgis_real() -> str:
    """El volcado del doble 4a sin su PostGIS de juguete y con la extensión real; se escribe en un temporal (no se toca el original)."""
    t = DUMP_4A.read_text()
    bloques = re.split(r"(?=\n--\n-- Name: )", t)
    q = re.compile(r"-- Name: (geography; Type: TYPE|geometry; Type: TYPE|CAST \(public\.geometry AS public\.geography\); Type: CAST|st_[a-z]+\([^)]*\); Type: FUNCTION|f_knn_doble\([^)]*\); Type: FUNCTION|<->; Type: OPERATOR); Schema: (public|-)")
    fuera = [b for b in bloques if q.search(b)]
    assert len(fuera) == 12, f"se esperaban 12 objetos de juguete, hay {len(fuera)}"
    t2 = "".join(b for b in bloques if not q.search(b))
    # los puntos del catastro vienen como «(x,y)» del tipo de juguete: pasan a EWKT (SRID=4326;POINT(x y)) en su bloque COPY
    ini = t2.index("COPY public.catastro_valledupar ("); fin = t2.index("\n\\.\n", ini)
    bloque, n = re.subn(r"\t\((-?[0-9.]+),(-?[0-9.]+)\)\t", r"\tSRID=4326;POINT(\1 \2)\t", t2[ini:fin])
    assert n == bloque.count("\n"), (n, bloque.count("\n"))
    t2 = t2[:ini] + bloque + t2[fin:]
    marca = "SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', false);"
    assert t2.count(marca) == 1
    t2 = t2.replace(marca, "CREATE EXTENSION IF NOT EXISTS postgis SCHEMA public;\n" + marca, 1)
    f = tempfile.NamedTemporaryFile("w", suffix="_doble_postgis_real.sql", delete=False); f.write(t2); f.close()
    return f.name

CAPAS_SQL = """
create table public.redes_acueducto (id bigint primary key, geom geometry(MultiLineString, 4326));
create table public.redes_alcantarillado (id bigint primary key, geom geometry(MultiLineString, 4326));
create index idx_redes_acu_geom on public.redes_acueducto using gist (geom);
create index idx_redes_alc_geom on public.redes_alcantarillado using gist (geom);
alter table public.predios_comercial_fuente_local add column geom geometry(Point, 4326), add column sin_contrato boolean;
-- Capas de los dos mapas con la estructura de producción (paso 0 de David, 27-nov): clase, columnas, geometría e índice GiST con su nombre y definición exactos
alter table public.catastro_valledupar alter column geom type geometry(Point, 4326) using st_setsrid(geom, 4326);
create index idx_catastro_geom on public.catastro_valledupar using gist (geom);
alter table public.barrios_valledupar add column geom geometry(MultiPolygon, 4326);
create index idx_barrios_geom on public.barrios_valledupar using gist (geom);
create table public.terrenos_valledupar (ogc_fid serial primary key, codigo character varying(30), matricula character varying, geom geometry(MultiPolygon, 4326));
create index terrenos_valledupar_geom_geom_idx on public.terrenos_valledupar using gist (geom);
-- tecnica.elementos_planta con el DDL EXACTO de producción (sql/tecnica_ptar/sql/10_esquema.sql, publicado el 21-nov): sus CHECK de tipo, forma, nombre, código e inactivo.
-- Sin las dos llaves foráneas a tecnica.instalaciones y tecnica.puntos (no existen en el doble); las pruebas no escriben en esta tabla, solo los datos sintéticos.
create table tecnica.elementos_planta (
  id bigint generated always as identity primary key, codigo text not null check (codigo ~ '^[A-Z0-9][A-Z0-9_-]{1,39}$'), instalacion_id bigint not null,
  tipo text not null check (tipo in ('perimetro', 'laguna', 'tramo', 'punto_medicion', 'pozo', 'descarga')), nombre text not null check (length(btrim(nombre)) between 2 and 120),
  orden smallint not null default 0 check (orden between 0 and 999), geom geometry(Geometry, 4326) not null, punto_id bigint,
  desde_id bigint references tecnica.elementos_planta (id), hasta_id bigint references tecnica.elementos_planta (id),
  activo_codigo text check (activo_codigo is null or activo_codigo ~ '^[A-Z]{3}-[0-9]{6}$'), atributos jsonb not null default '{}'::jsonb check (jsonb_typeof(atributos) = 'object'),
  origen text not null check (origen in ('dibujo', 'redes')), activo boolean not null default true,
  motivo_inactivo text check (motivo_inactivo is null or length(btrim(motivo_inactivo)) between 10 and 1000), inactivado_en timestamptz,
  reemplaza_id bigint references tecnica.elementos_planta (id), creado_por text not null check (creado_por = lower(creado_por) and position('@' in creado_por) > 1),
  creado_en timestamptz not null default clock_timestamp(),
  constraint elementos_planta_forma check ((tipo in ('perimetro', 'laguna') and geometrytype(geom) in ('POLYGON', 'MULTIPOLYGON'))
    or (tipo = 'tramo' and geometrytype(geom) in ('LINESTRING', 'MULTILINESTRING')) or (tipo in ('punto_medicion', 'pozo', 'descarga') and geometrytype(geom) = 'POINT')),
  constraint elementos_planta_valida check (st_isvalid(geom) and not st_isempty(geom)),
  constraint elementos_planta_punto check (punto_id is null or tipo = 'punto_medicion'),
  constraint elementos_planta_flujo check ((desde_id is null and hasta_id is null) or tipo = 'tramo'),
  constraint elementos_planta_redes check (origen <> 'redes' or activo_codigo is not null),
  constraint elementos_planta_inactivo check ((activo and motivo_inactivo is null and inactivado_en is null) or (not activo and motivo_inactivo is not null and inactivado_en is not null)));
create unique index uq_elementos_planta_codigo_activo on tecnica.elementos_planta (codigo) where activo;
create index ix_elementos_planta_geom on tecnica.elementos_planta using gist (geom);
"""
PREDIOS_SQL = """
drop materialized view public.predios_comercial;   -- solo en esta base, recién creada por este guion: se rehace con geom (misma clase: vista materializada)
create materialized view public.predios_comercial as select id, cod_usuario, deuda_total, barrio, estado_predio, tramo_mora, geom, sin_contrato from public.predios_comercial_fuente_local;
create unique index predios_comercial_id_key on public.predios_comercial using btree (id);
create index idx_predcom_geom_n on public.predios_comercial using gist (geom);
analyze public.redes_acueducto; analyze public.redes_alcantarillado; analyze public.predios_comercial;
"""
# Datos SINTÉTICOS de las capas que no hay en local (David, 27-nov): terrenos alrededor de cada predio del centro y de los puntos de prueba, barrios en cuadrícula de
# 500 m (la celda más densa se llama «CENTRO (SINTÉTICO)»), elementos de Técnica cerca de los puntos de prueba (uno inactivo, que no debe salir) y 1 de cada 9 predios
# «sin contrato». PUNTOS_PRUEBA: el de los reportes de prueba y el más denso del centro (celda de 120 × 60 m con más predios).
PUNTOS_PRUEBA = [(10.476071, -73.251529)]
SINTETICOS_SQL = """
update public.predios_comercial_fuente_local set sin_contrato = (id % 9 = 0) where true;
refresh materialized view public.predios_comercial;
insert into public.terrenos_valledupar (codigo, matricula, geom)
select 'ZT-' || p.id, null, st_multi(st_transform(st_expand(st_transform(p.geom, 3116), 4.4), 4326))
  from public.predios_comercial p
 where p.geom is not null and exists (select 1 from (values {{PUNTOS}}) z(lat, lon)
         where st_dwithin(st_transform(p.geom, 3116), st_transform(st_setsrid(st_makepoint(z.lon, z.lat), 4326), 3116), 700));
with c as (select st_transform(st_setsrid(st_makepoint({{LON_DENSO}}, {{LAT_DENSO}}), 4326), 3116) as d),
     g as (select i, j, st_makeenvelope(1060000 + i * 500, 1640000 + j * 500, 1060000 + (i + 1) * 500, 1640000 + (j + 1) * 500, 3116) as e
             from generate_series(-60, 60) i, generate_series(-60, 60) j)
insert into public.barrios_valledupar (id, nombre, buscable, geom)
select 900000 + row_number() over (order by g.i, g.j), case when st_intersects(g.e, c.d) then 'CENTRO (SINTÉTICO)' else 'ZTRP BARRIO ' || g.i || '/' || g.j end, true,
       st_multi(st_transform(g.e, 4326))
  from g, c
 where st_intersects(st_transform(g.e, 4326), st_makeenvelope(-73.36, 10.35, -73.18, 10.56, 4326));
-- elementos con los tipos REALES de producción (pozo, descarga, punto de medición, tramo y laguna) y un pozo inactivo, que no debe salir
insert into tecnica.elementos_planta (codigo, instalacion_id, tipo, nombre, geom, origen, activo, motivo_inactivo, inactivado_en, creado_por)
select 'ZTRP-E' || n || '-' || k, 1, tipo, 'ZTRP elemento ' || n, geom, 'dibujo', activo, case when activo then null else '[PRUEBA ZTRP] pozo dado de baja' end,
       case when activo then null else now() end, 'ztrp.carga@emdupar.gov.co'
  from (select v.lat, v.lon, row_number() over () as k from (values {{PUNTOS}}) v(lat, lon)) z,
       lateral (values (1, 'pozo', st_setsrid(st_makepoint(z.lon + 0.00012, z.lat + 0.00008), 4326), true),
                       (2, 'descarga', st_setsrid(st_makepoint(z.lon - 0.00020, z.lat - 0.00005), 4326), true),
                       (3, 'punto_medicion', st_setsrid(st_makepoint(z.lon + 0.00030, z.lat - 0.00012), 4326), true),
                       (4, 'tramo', st_setsrid(st_makeline(st_makepoint(z.lon - 0.0004, z.lat + 0.0001), st_makepoint(z.lon + 0.0004, z.lat + 0.00015)), 4326), true),
                       (5, 'laguna', st_setsrid(st_makeenvelope(z.lon + 0.00035, z.lat + 0.00005, z.lon + 0.00050, z.lat + 0.00020), 4326), true),
                       (6, 'pozo', st_setsrid(st_makepoint(z.lon + 0.00005, z.lat - 0.00003), 4326), false)) e(n, tipo, geom, activo);
analyze public.terrenos_valledupar; analyze public.barrios_valledupar; analyze tecnica.elementos_planta; analyze public.predios_comercial;
"""
def punto_denso(con):
    """El centro de la celda de 120 × 60 m con más predios a 1,5 km o menos de la plaza Alfonso López (la zona densa del centro, donde los números se amontonan)."""
    return con.execute("select st_y(c), st_x(c) from (select st_transform(st_setsrid(st_makepoint(st_x(k) + 60, st_y(k) + 30), 3116), 4326) as c from "
                       "(select st_snaptogrid(st_transform(geom, 3116), 120, 60) as k, count(*) as n from public.predios_comercial where geom is not null "
                       "and st_dwithin(st_transform(geom, 3116), st_transform(st_setsrid(st_makepoint(-73.2489, 10.4772), 4326), 3116), 1500) group by 1 order by n desc limit 1) q) z").fetchone()

def rehacer(db):
    """Rehace `db` (emdupar_a_rf_*) como copia de producción con PostGIS real y la etiqueta del pago publicada. Devuelve una conexión."""
    assert db.startswith("emdupar_a_rf_ran"), db
    dump = volcado_postgis_real()
    try:
        r = subprocess.run([sys.executable, "-I", str(gn0.AQUI / "rehacer_doble.py"), "--csv", str(gn0.CSV_PROD), "--base", dump, "--db", db], capture_output=True, text=True)
    finally:
        pathlib.Path(dump).unlink()
    if r.returncode or "SIN DIFERENCIAS" not in r.stdout: raise SystemExit("El doble no quedó igual a producción:\n" + r.stdout[-2000:] + r.stderr[-2000:])
    psql(db, "-f", str(gn0.MIG_INV))
    con = psycopg.connect(gn0.uri(db), autocommit=True)
    con.execute(gn0.ALINEAR_PRODUCCION)
    base = {k: con.execute(gn0.HUELLA[k]).fetchone()[0] for k in ("campo", "acta")}
    if base != gn0.PUBLICADA: raise SystemExit(f"El doble no tiene las huellas publicadas: {base}")
    con.execute(gn0.a_local((gnd.RF / "migracion_campo_registro_flexible_editor.sql").read_text(), gnd.HL0))
    con.execute(gnd.ALINEAR)
    con.execute(gnd.a_local((gp.DIRS / "migracion_campo_consultar_direcciones_editor.sql").read_text(), None))
    con.execute(gp.a_local((gp.PAQ / "migracion_campo_etiqueta_pago_editor.sql").read_text()))
    h = con.execute(HUELLA["campo"]).fetchone()[0]
    if h != PUBLICADA["campo"]: raise SystemExit(f"El doble no tiene la huella de campo esperada: {h}")
    # capas del mapa (volumen real, desde emdupar_b, solo lectura)
    con.execute(CAPAS_SQL)
    for capa, tabla in (("acueducto", "redes_acueducto"), ("alc_conductos", "redes_alcantarillado")):
        datos = psql(ORIGEN_CAPAS, "-c", f"copy (select id, st_multi(geom) from redes.activo_versiones where capa_codigo = '{capa}' and geometrytype(geom) = 'LINESTRING') to stdout")
        psql(db, "-c", f"copy public.{tabla} (id, geom) from stdin", entrada=datos)
    datos = psql(ORIGEN_CAPAS, "-c", "copy (select 9000000 + row_number() over (order by cod_usuario), cod_usuario, geom from (select distinct on (cod_usuario) cod_usuario, geom "
                                     "from public.catastro_valledupar where geom is not null and cod_usuario is not null order by cod_usuario, id) x) to stdout")
    psql(db, "-c", "copy public.predios_comercial_fuente_local (id, cod_usuario, geom) from stdin", entrada=datos)
    con.execute(PREDIOS_SQL)
    lat_d, lon_d = punto_denso(con)
    puntos = ", ".join(f"({lat}::double precision, {lon}::double precision)" for lat, lon in [*PUNTOS_PRUEBA, (lat_d, lon_d)])
    con.execute(SINTETICOS_SQL.replace("{{PUNTOS}}", puntos).replace("{{LAT_DENSO}}", str(lat_d)).replace("{{LON_DENSO}}", str(lon_d)))
    return con

def valores(con):
    for f, m in PERMISOS.items(): assert md5f(con, f) == m, f
    p = {"HUELLA_CAMPO": PUBLICADA["campo"], "HUELLA_ACTA": PUBLICADA["acta"], "HUELLA_TECNICA": TECNICA_PRODUCCION,
         "HUELLA_CAMPO_Q": HUELLA["campo"], "HUELLA_ACTA_Q": HUELLA["acta"], "HUELLA_TECNICA_Q": HUELLA["tecnica"], "SIN_WHERE_CAMPO": SINWHERE, "EST_EXPR": EST_EXPR,
         "MD5_PERMISOS": ", ".join(f"({lit(f)}, {lit(m)})" for f, m in PERMISOS.items()),
         "COLUMNAS": ", ".join(f"({lit(t)}, {lit(c)}, {lit(ty)})" for t, c, ty in COLUMNAS),
         "EST_TABLA_NUEVA": "x", "EST_TABLA_RAN": "x", "MD5_NUEVAS": "('x', 'x')"}
    with con.transaction(force_rollback=True):
        con.execute(a_local(poner(cuerpo(), p)))
        p["HUELLA_CAMPO_NUEVA"] = con.execute(HUELLA["campo"]).fetchone()[0]
        assert con.execute(HUELLA["acta"]).fetchone()[0] == p["HUELLA_ACTA"]
        p["MD5_NUEVAS_D"] = {f: md5f(con, f) for f in NUEVAS}
        p["MD5_NUEVAS"] = ", ".join(f"({lit(f)}, {lit(m)})" for f, m in p["MD5_NUEVAS_D"].items())
        p["EST_TABLA_NUEVA"] = est(con, "campo.reporte_pdf"); p["EST_TABLA_RAN"] = est(con, "campo.reporte_ran")
        con.execute(poner(lee("90_reversa.sql"), p))
        assert con.execute(HUELLA["campo"]).fetchone()[0] == p["HUELLA_CAMPO"], "la reversa no devuelve la huella"
    return p

def archivos(p):
    H = HUELLA
    huellas = f"""-- Solo lectura. ANTES: 1 «LISTA PARA ESTE CAMBIO» (huella con la etiqueta del último pago); 2 y 3 «PUBLICADA». DESPUÉS: 1 «CON ESTE CAMBIO»; 2 y 3 igual.
select o, k, v, estado from (
  select 1 as o, '1 funciones de campo (conjunto, todas; collate C)' as k, ({H["campo"]}) as v,
         case ({H["campo"]}) when '{p["HUELLA_CAMPO"]}' then 'LISTA PARA ESTE CAMBIO (con la etiqueta del último pago)' when '{p["HUELLA_CAMPO_NUEVA"]}' then 'CON ESTE CAMBIO'
              when 'c476f14d495ea7bdf6c3f42101e9a583' then 'FALTA PUBLICAR la etiqueta del último pago: deténgase' else 'OTRA: deténgase y avise' end as estado
  union all
  select 2, '2 funciones del acta (conjunto)', ({H["acta"]}), case ({H["acta"]}) when '{p["HUELLA_ACTA"]}' then 'PUBLICADA (no cambia con este paquete)' else 'OTRA: deténgase y avise' end
  union all
  select 3, '3 funciones de Técnica (conjunto)', ({H["tecnica"]}), case ({H["tecnica"]}) when '{p["HUELLA_TECNICA"]}' then 'PUBLICADA (no cambia con este paquete)' else 'OTRA: deténgase y avise' end
) t order by o;
"""
    def fila(n, k, cond): return f"  select {n} as o, {lit(k)} as k, case when {cond} then 'OK' else 'FALLA' end as estado"
    api = lambda f: f"has_function_privilege('service_role', {lit(f)}, 'execute') and not has_function_privilege('anon', {lit(f)}, 'execute') and not has_function_privilege('authenticated', {lit(f)}, 'execute')"
    T = "campo.reporte_pdf"
    filas = [
        fila(1, "1 la huella de campo es la de este cambio", f"({H['campo']}) = '{p['HUELLA_CAMPO_NUEVA']}'"),
        fila(2, "2 la huella del acta no cambió", f"({H['acta']}) = '{p['HUELLA_ACTA']}'"),
        fila(3, "3 la huella de Técnica no cambió", f"({H['tecnica']}) = '{p['HUELLA_TECNICA']}'"),
        fila(4, "4 las 9 funciones nuevas existen con su md5", " and ".join(f"md5(pg_get_functiondef(to_regprocedure({lit(f)}))) = {lit(m)}" for f, m in p["MD5_NUEVAS_D"].items())),
        fila(5, "5 las 3 RPC solo para service_role; las 6 internas, para nadie de la API",
             " and ".join(api(f) for f in RPC) + " and " + " and ".join(f"not has_function_privilege({lit(r)}, {lit(f)}, 'execute')" for f in INTERNAS for r in ("anon", "authenticated", "service_role"))),
        fila(6, f"6 {T}: estructura de este paquete, RLS sin políticas, sin permisos para la API, SELECT (solo) para homelab_lectura, solo inserción",
             f"(select {EST_EXPR} from (select to_regclass('{T}') as rel) z) = '{p['EST_TABLA_NUEVA']}' and (select relrowsecurity from pg_class where oid = '{T}'::regclass) "
             "and not exists (select 1 from pg_policies where schemaname in ('campo', 'acta')) "
             + "".join(f"and not has_table_privilege('{r}', '{T}', '{x}') " for r in ("anon", "authenticated", "service_role") for x in ("select", "insert", "update", "delete"))
             + f"and has_table_privilege('homelab_lectura', '{T}', 'select') and not has_table_privilege('homelab_lectura', '{T}', 'insert') "
             f"and (select string_agg(tgname || ':' || tgfoid::regproc::text || ':' || tgtype, ',' order by tgname) from pg_trigger where tgrelid = '{T}'::regclass and not tgisinternal) "
             "= (select string_agg(tgname || ':' || tgfoid::regproc::text || ':' || tgtype, ',' order by tgname) from pg_trigger where tgrelid = 'campo.reporte_fotos'::regclass and not tgisinternal)"),
        fila(10, "10 campo.reporte_ran: estructura de este paquete, RLS, sin permisos para la API, SELECT para homelab_lectura, solo inserción y números seguidos desde 1",
             f"(select {EST_EXPR} from (select to_regclass('campo.reporte_ran') as rel) z) = '{p['EST_TABLA_RAN']}' and (select relrowsecurity from pg_class where oid = 'campo.reporte_ran'::regclass) "
             + "".join(f"and not has_table_privilege('{r}', 'campo.reporte_ran', '{x}') " for r in ("anon", "authenticated", "service_role") for x in ("select", "insert", "update", "delete"))
             + "and has_table_privilege('homelab_lectura', 'campo.reporte_ran', 'select') and not has_table_privilege('homelab_lectura', 'campo.reporte_ran', 'insert') "
             "and (select string_agg(tgname || ':' || tgfoid::regproc::text || ':' || tgtype, ',' order by tgname) from pg_trigger where tgrelid = 'campo.reporte_ran'::regclass and not tgisinternal) "
             "= (select string_agg(tgname || ':' || tgfoid::regproc::text || ':' || tgtype, ',' order by tgname) from pg_trigger where tgrelid = 'campo.reporte_fotos'::regclass and not tgisinternal) "
             "and (select coalesce(max(numero), 0) = count(*) and coalesce(min(numero), 1) = 1 from campo.reporte_ran)"),
        fila(7, "7 las 4 funciones de permisos vivas no cambiaron", " and ".join(f"md5(pg_get_functiondef(to_regprocedure({lit(f)}))) = {lit(m)}" for f, m in PERMISOS.items())),
        fila(8, "8 ninguna función de campo con DELETE o UPDATE sin WHERE", SINWHERE + " = 0"),
        fila(9, "9 redes.f_funciones_sin_where() devuelve cero filas", "(select count(*) from redes.f_funciones_sin_where()) = 0"),
    ]
    ver = "select o, k, estado from (\n" + "\n  union all\n".join(filas) + "\n) t order by o;\n"
    return {f"migracion_{NOMBRE}_editor.sql": CAB.format(que="MIGRACIÓN") + "begin;\n" + poner(cuerpo(), p) + "\ncommit;\n",
            f"ensayo_en_transaccion_{NOMBRE}_editor.sql": CAB.format(que="ENSAYO (termina en ERROR esperado; no deja nada)") + "begin;\n" + poner(lee("70_pruebas.sql"), p) + "\nrollback;\n",
            f"reversa_{NOMBRE}_editor.sql": CAB.format(que="REVERSA") + "begin;\n" + poner(lee("90_reversa.sql"), p) + "\ncommit;\n",
            f"huellas_solo_lectura_{NOMBRE}_editor.sql": CAB.format(que="HUELLAS (solo lectura; ANTES y DESPUÉS)") + huellas,
            f"verificacion_{NOMBRE}_editor.sql": CAB.format(que=f"VERIFICACIÓN (solo lectura; después de la migración: {len(filas)} de {len(filas)} OK)") + ver}, len(filas)

def main():
    con = rehacer("emdupar_a_rf_rangen")
    p = valores(con); con.close()
    p["CUERPO_MIGRACION"] = poner(cuerpo(), p); p["CUERPO_REVERSA"] = poner(lee("90_reversa.sql"), p)
    salida, n = archivos(p)
    for nombre, t in salida.items():
        assert "on commit drop" not in t.lower(), nombre
        (PAQ / nombre).write_text(t); print(f"[OK ] {nombre}  md5 {hashlib.md5(t.encode()).hexdigest()}")
    (AQUI / "huellas_locales.json").write_text(json.dumps({"partida": {"HUELLA_CAMPO": p["HUELLA_CAMPO"]},
        "nuevas": {"HUELLA_CAMPO_NUEVA": p["HUELLA_CAMPO_NUEVA"], "FUNCIONES_NUEVAS": p["MD5_NUEVAS_D"], "TABLA_NUEVA": p["EST_TABLA_NUEVA"], "TABLA_RAN": p["EST_TABLA_RAN"]}, "verificacion": n}, indent=1, ensure_ascii=False))
    print(json.dumps({"HUELLA_CAMPO_NUEVA": p["HUELLA_CAMPO_NUEVA"], "verificacion": n}, indent=1))

if __name__ == "__main__":
    main()
