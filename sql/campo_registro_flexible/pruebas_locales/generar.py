#!/usr/bin/env python3
"""[Code A] Genera los archivos _editor del paquete «Registro flexible» (25-nov) desde las partes de ../sql y un doble local de producción. NUNCA Supabase.

El doble: rehacer_doble.py (copia exacta del catálogo de campo de producción al 24-nov, Code B) + la migración publicada de Investigación y Análisis
(sql/campo_inv_analisis/migracion_…_editor.sql, publicada el 24-nov) = huella de campo cce59380… y del acta 111506c6…, las de producción.
La huella de Técnica del doble NO es la de producción (el doble 4a es anterior a lo último de Técnica): los archivos _editor llevan la de producción
(838b8098…) y correr_local.py la cambia por la del doble, y lo dice, al probarlos en local. Este paquete no toca ninguna función de esa huella.

Uso: python3 -I generar.py [-h]"""
import sys, re, json, hashlib, pathlib, subprocess
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
import psycopg

AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent; SQL = PAQ / "sql"
NOMBRE = "campo_registro_flexible"
CSV_PROD = pathlib.Path.home() / "geoportal-consultas/campo/paquete_inv_analisis_1/produccion_doble.csv"
MIG_INV = pathlib.Path.home() / "geoportal-emdupar/sql/campo_inv_analisis/migracion_campo_inv_analisis_editor.sql"
PSQL = "/opt/homebrew/opt/postgresql@17/bin/psql"
PUERTO = "55432"
def uri(db): return f"postgresql://postgres@localhost:{PUERTO}/{db}"

HUELLA = {"campo": "select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
                   "where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_campo\\_%')",
          "acta": "select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
                  "where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_acta\\_%')",
          "tecnica": "select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
                     "where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_tec\\_%'))"}
PUBLICADA = {"campo": "cce593806f59d3d27c34d7f2070cc5c1", "acta": "111506c690249ad3b56ebf572566434c"}
TECNICA_PRODUCCION = "838b80984e51cc7873a666f85d657195"   # estado_produccion_2026-11-24 y rutas_de_trabajo (24-nov 20:46)
PERMISOS = {"public.geoportal_puede(text,text)": "32f174a55b95788d3f8187b507303c2f",
            "public.geoportal_mis_permisos(text)": "83166fe17be58da67bbdedaae429bedb",
            "public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)": "01fda69a9d912067b8b4dc153ac7957e",
            "public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)": "e5a90103b4a83440fd826f03266b7245"}
CREAR = "public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone)"
CREAR_N = CREAR[:-1] + ",jsonb)"
TEC = "public.geoportal_campo_tec_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,jsonb,text,jsonb,text,text,timestamp with time zone)"
TEC_N = TEC[:-1] + ",jsonb)"
LISTAR = "public.geoportal_campo_listar_reportes(text,jsonb,text)"; OBTENER = "public.geoportal_campo_obtener_reporte(text,uuid,text)"
DPAGINA = "public.geoportal_campo_descarga_pagina(text,bigint,bigint,integer)"; PDF = "public.geoportal_campo_pdf_datos(text,text,uuid,text)"
DERIVADAS = "public.geoportal_campo_derivadas(text,jsonb,text)"
# Las que cambian de texto con la misma firma (respaldo = su texto publicado)
MISMA_FIRMA = {"LISTAR": LISTAR, "OBTENER": OBTENER, "DESCARGA_PAGINA": DPAGINA, "PDF_DATOS": PDF, "DERIVADAS": DERIVADAS}
NUEVAS_F = ["campo.f_derivadas_filtradas(jsonb)", "campo.f_derivada_sin_correos(jsonb)",
            "public.geoportal_campo_derivadas_descarga_iniciar(text,jsonb,text,boolean,text)", "public.geoportal_campo_derivadas_descarga_pagina(text,bigint,bigint,integer)",
            "public.geoportal_campo_derivadas_descarga_cerrar(text,bigint,integer,text,text)"]
RPC_NUEVAS = NUEVAS_F[2:]
# Funciones cuyo md5 exige la guardia: las que se reemplazan y aquellas de las que depende el cambio
FUNCIONES = [CREAR, TEC, *MISMA_FIRMA.values(), "campo.f_derivada_json(bigint)", "campo.f_derivada_estado(bigint)", "campo.f_autorizar_supervision(text)",
             "campo.f_autorizar_registradas(text)", "campo.f_autorizar_reporte(text)", "campo.f_autorizar_documento(text,text,uuid)", "campo.f_perfil(text)",
             "campo.f_tecnica_entrar(text,text)", "campo.f_tecnica_claves(text)", "campo.f_tipo_general(text)", "campo.f_filtrar(jsonb)", "campo.f_grupos_cercanos(numeric,uuid[])",
             "campo.f_validar_datos(bigint,jsonb,boolean)", "campo.f_solo_agregar()", "campo.f_error(text,text)", "campo.f_auditar(text,text,text,jsonb,text)",
             "campo.f_param(text)", "campo.f_ahora_bogota()", "public.geoportal_campo_obtener_formulario(text,boolean)", "public.geoportal_campo_tec_formulario(text)",
             "public.geoportal_campo_preparar_subida(text,integer,text,text,text)", "public.geoportal_campo_tec_preparar_subida(text,integer,text,text)",
             "public.geoportal_campo_descarga_iniciar(text,jsonb,text,boolean,text)", "public.geoportal_campo_descarga_cerrar(text,bigint,integer,text,text)", *PERMISOS]
# Tablas vivas que el paquete lee o toca: su estructura exacta va a la guardia
TABLAS = ["campo.reportes", "campo.reporte_fotos", "campo.reporte_datos_sensibles", "campo.derivadas", "campo.derivada_eventos", "campo.tipos_reporte",
          "campo.parametros", "public.geoportal_auditoria"]
TABLAS_NUEVAS = ["campo.reporte_registro"]
EST_EXPR = ("md5(concat_ws('#', "
  "(select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' NOT NULL' else '' end "
  "|| coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '') || case when a.attidentity <> '' then ' IDENTITY ' || a.attidentity::text else '' end, ', ' order by a.attnum) "
  "from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum where a.attrelid = z.rel and a.attnum > 0 and not a.attisdropped), "
  "(select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ' | ' order by c.conname) from pg_constraint c where c.conrelid = z.rel), "
  "(select string_agg(pg_get_indexdef(i.indexrelid), ' | ' order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid = z.rel), "
  "(select string_agg(pg_get_triggerdef(g.oid), ' | ' order by g.tgname) from pg_trigger g where g.tgrelid = z.rel and not g.tgisinternal), "
  "(select c.relkind::text || ' ' || c.relrowsecurity::text || ' ' || coalesce(c.relacl::text, '') from pg_class c where c.oid = z.rel)))")
# Ninguna función de campo con DELETE o UPDATE sin WHERE (la misma consulta de los paquetes de campo; ON CONFLICT … DO UPDATE no cuenta)
SINWHERE = r"""(with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_campo\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\mwhere\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M'))"""
PARTES = ["05_guardia.sql", "10_estructura.sql", "20_crear.sql", "30_lecturas.sql", "40_derivadas.sql"]
lee = lambda n: (SQL / n).read_text()
CAB = "-- [Code A] REGISTRO FLEXIBLE (25-nov) · {que} (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)\n"
def cuerpo(): return "\n".join(lee(n) for n in PARTES)
def poner(t, v):
    for k, x in v.items():
        if isinstance(x, str): t = t.replace("{{" + k + "}}", x)
    assert "{{" not in t, re.findall(r"\{\{[A-Z_0-9]+\}\}", t); return t
def lit(s): return "'" + s.replace("'", "''") + "'"

def rehacer(db):
    """Rehace la base `db` (emdupar_a_rf*) como copia de producción: doble del Code B + la migración publicada de Investigación y Análisis. Devuelve una conexión."""
    r = subprocess.run([sys.executable, "-I", str(AQUI / "rehacer_doble.py"), "--csv", str(CSV_PROD), "--db", db], capture_output=True, text=True)
    if r.returncode or "SIN DIFERENCIAS" not in r.stdout: raise SystemExit("El doble no quedó igual a producción:\n" + r.stdout[-2000:] + r.stderr[-2000:])
    r = subprocess.run([PSQL, "-X", "-q", "-v", "ON_ERROR_STOP=1", "-h", "localhost", "-p", PUERTO, "-U", "postgres", "-d", db, "-f", str(MIG_INV)], capture_output=True, text=True)
    if r.returncode: raise SystemExit("No se aplicó la migración publicada de Investigación y Análisis:\n" + r.stderr[-2000:])
    con = psycopg.connect(uri(db), autocommit=True)
    # El doble 4a trae un PostGIS mínimo (tipo geometry de dos números en public). Le faltan st_transform y st_clusterdbscan, que usa campo.f_grupos_cercanos
    # (lista y descarga de Supervisión, también las publicadas). Se agregan aquí, en public (fuera de las huellas): st_transform devuelve el punto igual y
    # st_clusterdbscan es un agregado que pone a todos en el mismo grupo. Solo sirven para que esas lecturas corran en local; la agrupación real no se prueba aquí.
    con.execute("""create or replace function public.st_transform(public.geometry, integer) returns public.geometry language sql immutable as $$ select $1 $$;
                   create or replace function public.zz_cluster_paso(integer, public.geometry, double precision, integer) returns integer language sql immutable as $$ select 0 $$;
                   do $$ begin if to_regprocedure('public.st_clusterdbscan(public.geometry,double precision,integer)') is null then
                     create aggregate public.st_clusterdbscan(public.geometry, double precision, integer) (sfunc = public.zz_cluster_paso, stype = integer, initcond = '0'); end if; end $$;""")
    base = {k: con.execute(HUELLA[k]).fetchone()[0] for k in ("campo", "acta")}
    if base != PUBLICADA: raise SystemExit(f"El doble no tiene las huellas publicadas: {base}")
    return con

def md5f(con, f): return con.execute("select md5(pg_get_functiondef(to_regprocedure(%s)))", (f,)).fetchone()[0]
def defn(con, f): return con.execute("select pg_get_functiondef(to_regprocedure(%s))", (f,)).fetchone()[0].rstrip() + ";"
def est(con, t): return con.execute(f"select {EST_EXPR} from (select to_regclass(%s) as rel) z", (t,)).fetchone()[0]

def valores(con):
    for f, m in PERMISOS.items(): assert md5f(con, f) == m, f
    p = {"HUELLA_CAMPO": PUBLICADA["campo"], "HUELLA_ACTA": PUBLICADA["acta"], "HUELLA_TECNICA": TECNICA_PRODUCCION, "HUELLA_TECNICA_LOCAL": con.execute(HUELLA["tecnica"]).fetchone()[0],
         "HUELLA_CAMPO_Q": HUELLA["campo"], "HUELLA_ACTA_Q": HUELLA["acta"], "HUELLA_TECNICA_Q": HUELLA["tecnica"],
         "F_CREAR": CREAR, "F_CREAR_NUEVA": CREAR_N, "F_TEC": TEC, "F_TEC_NUEVA": TEC_N, "EST_EXPR": EST_EXPR, "SIN_WHERE_CAMPO": SINWHERE,
         "MD5_FUNCIONES": ", ".join(f"({lit(f)}, {lit(md5f(con, f))})" for f in FUNCIONES),
         "PERMISOS_IGUALES": " and ".join(f"md5(pg_get_functiondef(to_regprocedure({lit(f)}))) = {lit(m)}" for f, m in PERMISOS.items()),
         "RESPALDO_CREAR": defn(con, CREAR), "RESPALDO_TEC_CREAR": defn(con, TEC), **{f"RESPALDO_{k}": defn(con, f) for k, f in MISMA_FIRMA.items()},
         **{f"MD5_{k}": md5f(con, f) for k, f in MISMA_FIRMA.items()}, "MD5_CREAR": md5f(con, CREAR), "MD5_TEC": md5f(con, TEC)}
    est_prod = {t: est(con, t) for t in TABLAS}
    p["EST_LISTA"] = ", ".join(f"({lit(t)}, {lit(m)}, null::text)" for t, m in est_prod.items())
    p["EST_NUEVAS"] = "('campo.zz_ninguna', 'x')"; p["MD5_CAMBIAN_NUEVA"] = "('x', 'x')"
    with con.transaction(force_rollback=True):
        con.execute(poner(cuerpo(), {**p, "HUELLA_TECNICA": p["HUELLA_TECNICA_LOCAL"]}))
        p["HUELLA_CAMPO_NUEVA"] = con.execute(HUELLA["campo"]).fetchone()[0]
        assert con.execute(HUELLA["tecnica"]).fetchone()[0] == p["HUELLA_TECNICA_LOCAL"], "la huella de Técnica cambió con el paquete"
        assert con.execute(HUELLA["acta"]).fetchone()[0] == p["HUELLA_ACTA"], "la huella del acta cambió con el paquete"
        cambian = {"CREAR": CREAR_N, "TEC": TEC_N, **MISMA_FIRMA}
        p["MD5_NUEVA"] = {k: md5f(con, f) for k, f in cambian.items()}
        p["MD5_CAMBIAN_NUEVA"] = ", ".join(f"({lit(f)}, {lit(p['MD5_NUEVA'][k])})" for k, f in cambian.items())
        p["MD5_NUEVAS_F"] = {f: md5f(con, f) for f in NUEVAS_F}
        est_nueva = {t: est(con, t) for t in TABLAS}; p["EST_TABLAS_NUEVAS"] = {t: est(con, t) for t in TABLAS_NUEVAS}
        p["ESTADO_NUEVO"] = {t: m for t, m in est_nueva.items() if m != est_prod[t]}
        assert set(p["ESTADO_NUEVO"]) == {"campo.reporte_fotos"}, f"cambió la estructura de más tablas de las previstas: {list(p['ESTADO_NUEVO'])}"
        con.execute(poner(lee("90_reversa.sql"), p))
        assert con.execute(HUELLA["campo"]).fetchone()[0] == p["HUELLA_CAMPO"], "la reversa no devuelve la huella de campo"
        assert {t: est(con, t) for t in TABLAS_NUEVAS} == p["EST_TABLAS_NUEVAS"], "la reversa no conserva la tabla nueva"
        assert est(con, "campo.reporte_fotos") == p["ESTADO_NUEVO"]["campo.reporte_fotos"], "la reversa no conserva la columna nueva"
    p["EST_LISTA"] = ", ".join(f"({lit(t)}, {lit(m)}, {lit(p['ESTADO_NUEVO'][t]) if t in p['ESTADO_NUEVO'] else 'null::text'})" for t, m in est_prod.items())
    p["EST_NUEVAS"] = ", ".join(f"({lit(t)}, {lit(m)})" for t, m in p["EST_TABLAS_NUEVAS"].items())
    p["EST_PRODUCCION"] = est_prod
    return p

def archivos(p):
    H = HUELLA
    huellas = f"""-- Solo lectura. ANTES: 1 «PUBLICADA», 2 «PUBLICADA», 3 «PUBLICADA». DESPUÉS: 1 «CON ESTE CAMBIO» (anótela), 2 y 3 igual (este paquete no las cambia).
select o, k, v, estado from (
  select 1 as o, '1 funciones de campo (conjunto, todas)' as k, ({H["campo"]}) as v,
         case ({H["campo"]}) when '{p["HUELLA_CAMPO"]}' then 'PUBLICADA (24-nov): lista para este cambio' when '{p["HUELLA_CAMPO_NUEVA"]}' then 'CON ESTE CAMBIO' else 'OTRA: deténgase y avise' end as estado
  union all
  select 2, '2 funciones del acta (conjunto)', ({H["acta"]}), case ({H["acta"]}) when '{p["HUELLA_ACTA"]}' then 'PUBLICADA (no cambia con este paquete)' else 'OTRA: deténgase y avise' end
  union all
  select 3, '3 funciones de Técnica (conjunto)', ({H["tecnica"]}), case ({H["tecnica"]}) when '{p["HUELLA_TECNICA"]}' then 'PUBLICADA (no cambia con este paquete)' else 'OTRA: deténgase y avise' end
) t order by o;
"""
    def fila(n, k, cond): return f"  select {n} as o, {lit(k)} as k, case when {cond} then 'OK' else 'FALLA' end as estado"
    api = lambda f: f"has_function_privilege('service_role', {lit(f)}, 'execute') and not has_function_privilege('anon', {lit(f)}, 'execute') and not has_function_privilege('authenticated', {lit(f)}, 'execute')"
    filas = [
        fila(1, "1 la huella de campo es la de este cambio", f"({H['campo']}) = '{p['HUELLA_CAMPO_NUEVA']}'"),
        fila(2, "2 la huella del acta no cambió (111506c6…)", f"({H['acta']}) = '{p['HUELLA_ACTA']}'"),
        fila(3, "3 la huella de Técnica no cambió (838b8098…)", f"({H['tecnica']}) = '{p['HUELLA_TECNICA']}'"),
        fila(4, "4 crear_reporte y la entrada de Técnica: solo la firma nueva (con p_registro), con su md5",
             f"to_regprocedure({lit(CREAR)}) is null and to_regprocedure({lit(TEC)}) is null and md5(pg_get_functiondef(to_regprocedure({lit(CREAR_N)}))) = {lit(p['MD5_NUEVA']['CREAR'])} "
             f"and md5(pg_get_functiondef(to_regprocedure({lit(TEC_N)}))) = {lit(p['MD5_NUEVA']['TEC'])}"),
        fila(5, "5 lista, detalle, descarga, datos del PDF y derivadas son los de este cambio",
             " and ".join(f"md5(pg_get_functiondef(to_regprocedure({lit(f)}))) = {lit(p['MD5_NUEVA'][k])}" for k, f in MISMA_FIRMA.items())),
        fila(6, "6 las 5 funciones nuevas existen con su md5", " and ".join(f"md5(pg_get_functiondef(to_regprocedure({lit(f)}))) = {lit(m)}" for f, m in p["MD5_NUEVAS_F"].items())),
        fila(7, "7 las RPC cambiadas y las 3 nuevas, solo para service_role; las 2 internas, para nadie de la API",
             " and ".join(api(f) for f in [CREAR_N, TEC_N, *MISMA_FIRMA.values(), *RPC_NUEVAS]) + " and "
             + " and ".join(f"not has_function_privilege({lit(r)}, {lit(f)}, 'execute')" for f in NUEVAS_F[:2] for r in ("anon", "authenticated", "service_role"))),
        fila(8, "8 campo.reporte_registro: llave reporte_id, RLS activa, sin políticas, sin permisos para la API y SELECT (solo) para homelab_lectura",
             "(select relrowsecurity from pg_class where oid = 'campo.reporte_registro'::regclass) "
             "and (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'campo.reporte_registro'::regclass and contype = 'p') = 'PRIMARY KEY (reporte_id)' "
             "and not exists (select 1 from pg_policies where schemaname in ('campo', 'acta')) "
             + "".join(f"and not has_table_privilege('{r}', 'campo.reporte_registro', '{x}') " for r in ("anon", "authenticated", "service_role") for x in ("select", "insert", "update", "delete"))
             + "and has_table_privilege('homelab_lectura', 'campo.reporte_registro', 'select') and not has_table_privilege('homelab_lectura', 'campo.reporte_registro', 'insert')"),
        fila(9, "9 campo.reporte_registro es de solo inserción (los mismos disparadores que reporte_fotos)",
             "(select string_agg(tgname || ':' || tgfoid::regproc::text || ':' || tgtype, ',' order by tgname) from pg_trigger where tgrelid = 'campo.reporte_registro'::regclass and not tgisinternal) "
             "= (select string_agg(tgname || ':' || tgfoid::regproc::text || ':' || tgtype, ',' order by tgname) from pg_trigger where tgrelid = 'campo.reporte_fotos'::regclass and not tgisinternal)"),
        fila(10, "10 la estructura de campo.reporte_registro y de campo.reporte_fotos es la de este cambio",
             " and ".join(f"(select {EST_EXPR} from (select to_regclass({lit(t)}) as rel) z) = {lit(m)}" for t, m in {**p["EST_TABLAS_NUEVAS"], **p["ESTADO_NUEVO"]}.items())),
        fila(11, "11 campo.reporte_fotos.origen: camara por omisión; homelab_lectura la lee si lee la tabla",
             "exists (select 1 from information_schema.columns where table_schema = 'campo' and table_name = 'reporte_fotos' and column_name = 'origen' and column_default = '''camara''::text' and is_nullable = 'NO') "
             "and has_column_privilege('homelab_lectura', 'campo.reporte_fotos', 'origen', 'select') = has_table_privilege('homelab_lectura', 'campo.reporte_fotos', 'select')"),
        fila(12, "12 campo.reportes no cambió (el sello de los reportes anteriores no se mueve)", f"(select {EST_EXPR} from (select to_regclass('campo.reportes') as rel) z) = {lit(p['EST_PRODUCCION']['campo.reportes'])}"),
        fila(13, "13 las 4 funciones de permisos vivas no cambiaron", p["PERMISOS_IGUALES"]),
        fila(14, "14 ninguna función de campo con DELETE o UPDATE sin WHERE", SINWHERE + " = 0"),
        fila(15, "15 redes.f_funciones_sin_where() devuelve cero filas", "(select count(*) from redes.f_funciones_sin_where()) = 0"),
    ]
    ver = "select o, k, estado from (\n" + "\n  union all\n".join(filas) + "\n) t order by o;\n"
    partes = [("columnas", "(select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' NOT NULL' else '' end || coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '') || case when a.attidentity <> '' then ' IDENTITY ' || a.attidentity::text else '' end, ', ' order by a.attnum) from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum where a.attrelid = z.rel and a.attnum > 0 and not a.attisdropped)"),
              ("restricciones", "(select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ' | ' order by c.conname) from pg_constraint c where c.conrelid = z.rel)"),
              ("indices", "(select string_agg(pg_get_indexdef(i.indexrelid), ' | ' order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid = z.rel)"),
              ("disparadores", "(select string_agg(pg_get_triggerdef(g.oid), ' | ' order by g.tgname) from pg_trigger g where g.tgrelid = z.rel and not g.tgisinternal)"),
              ("clase_rls_permisos", "(select c.relkind::text || ' ' || c.relrowsecurity::text || ' ' || coalesce(c.relacl::text, '') from pg_class c where c.oid = z.rel)")]
    filas_c = []
    for tb in TABLAS:
        filas_c.append(f"  select {lit(tb)} as tabla, '0 md5 (el que compara la guardia)' as parte, (select {EST_EXPR} from (select to_regclass({lit(tb)}) as rel) z) as valor, "
                       f"case (select {EST_EXPR} from (select to_regclass({lit(tb)}) as rel) z) when {lit(p['EST_PRODUCCION'][tb])} then 'IGUAL AL DOBLE' else 'DISTINTO: envíe esta salida al Code A' end as estado")
        for k, x in partes:
            filas_c.append(f"  select {lit(tb)}, {lit(k)}, (select {x} from (select to_regclass({lit(tb)}) as rel) z), ''")
    consulta = ("-- Solo lectura. Antes de publicar: corra esto en producción y mire la columna «estado» de las filas «0 md5». Si alguna dice DISTINTO, copie TODA la salida\n"
                "-- (CSV) y envíela al Code A: la guardia del paquete se regenera con la estructura real. Si las 8 dicen IGUAL AL DOBLE, siga con la guía.\n"
                "select tabla, parte, valor, estado from (\n" + "\n  union all\n".join(filas_c) + "\n) t order by tabla, parte;\n")
    return {f"consulta_produccion_estructura_{NOMBRE}_editor.sql": CAB.format(que="CONSULTA DE ESTRUCTURA (solo lectura; antes de publicar)") + consulta,
            f"migracion_{NOMBRE}_editor.sql": CAB.format(que="MIGRACIÓN") + "begin;\n" + poner(cuerpo(), p) + "\ncommit;\n",
            f"ensayo_en_transaccion_{NOMBRE}_editor.sql": CAB.format(que="ENSAYO (termina en ERROR esperado; no deja nada)") + "begin;\n" + poner(lee("70_pruebas.sql"), p) + "\nrollback;\n",
            f"reversa_{NOMBRE}_editor.sql": CAB.format(que="REVERSA") + "begin;\n" + poner(lee("90_reversa.sql"), p) + "\ncommit;\n",
            f"huellas_solo_lectura_{NOMBRE}_editor.sql": CAB.format(que="HUELLAS (solo lectura; ANTES y DESPUÉS)") + huellas,
            f"verificacion_{NOMBRE}_editor.sql": CAB.format(que=f"VERIFICACIÓN (solo lectura; después de la migración: {len(filas)} de {len(filas)} OK)") + ver}, len(filas)

def main():
    con = rehacer("emdupar_a_rf_gen")
    p = valores(con); con.close()
    p["CUERPO_MIGRACION"] = poner(cuerpo(), p)          # el ensayo aplica la migración y la reversa dentro de su transacción (marcadores en 70_pruebas.sql)
    p["CUERPO_REVERSA"] = poner(lee("90_reversa.sql"), p)
    salida, n = archivos(p)
    for nombre, t in salida.items():
        assert "on commit drop" not in t.lower(), nombre
        (PAQ / nombre).write_text(t)
        print(f"[OK ] {nombre}  md5 {hashlib.md5(t.encode()).hexdigest()}")
    (AQUI / "huellas_locales.json").write_text(json.dumps({
        "partida": {"HUELLA_CAMPO": p["HUELLA_CAMPO"], "HUELLA_ACTA": p["HUELLA_ACTA"], "HUELLA_TECNICA_PRODUCCION": p["HUELLA_TECNICA"], "HUELLA_TECNICA_LOCAL": p["HUELLA_TECNICA_LOCAL"],
                    "MD5_CREAR": p["MD5_CREAR"], "MD5_TEC": p["MD5_TEC"]},
        "nuevas": {"HUELLA_CAMPO_NUEVA": p["HUELLA_CAMPO_NUEVA"], "MD5_NUEVA": p["MD5_NUEVA"], "FUNCIONES_NUEVAS": p["MD5_NUEVAS_F"], "TABLAS_NUEVAS": p["EST_TABLAS_NUEVAS"],
                   "ESTRUCTURA_NUEVA": p["ESTADO_NUEVO"]},
        "estructura_produccion": p["EST_PRODUCCION"], "verificacion": n}, indent=1, ensure_ascii=False))
    print(json.dumps({"HUELLA_CAMPO_NUEVA": p["HUELLA_CAMPO_NUEVA"], "verificacion": n}, indent=1))

if __name__ == "__main__":
    main()
