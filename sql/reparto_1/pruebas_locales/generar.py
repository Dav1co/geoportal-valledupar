"""Arma los archivos _editor del Reparto de facturas (commit 1, SQL) desde sql/ y una base local TEMPORAL del Code A (clúster 55432; NUNCA Supabase).
La plantilla «reparto_plantilla» = doble de Administración con el cargo del supervisor (campo 261bed3c… = producción del 22-nov) + dobles locales del SCRR
(cartera_suscripcion con sus 23 columnas) + dobles de las rutas (doble_rutas_local.sql) + el volumen de producción (volumen_local.sql).
Uso: python3 -I generar.py [-h]"""
import sys, re, json, pathlib, subprocess, hashlib, os
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent; SQL = PAQ / "sql"; H = pathlib.Path.home()
NOMBRE = "reparto_1"
PLANTILLA = "reparto_plantilla"
DOBLE = H / "geoportal-consultas/campo/admin_perfiles_22nov/doble_admin_4a/doble_admin_permisos_4a_con_cargo_supervisor.sql"
DOBLE_SCRR = H / "geoportal-emdupar/sql/scrr_corte2/pruebas_locales/doble_base_local.sql"
PSQL = "/opt/homebrew/opt/postgresql@17/bin/psql"
ENV = {**os.environ, "PGHOST": "localhost", "PGPORT": "55432", "PGUSER": "postgres", "PGOPTIONS": "-c client_min_messages=warning", "LC_ALL": "C"}
for k in ("SUPABASE_RO_URL", "DATABASE_URL", "PGPASSWORD", "PGSERVICE"): ENV.pop(k, None)   # nunca otra base que la local
FUENTES = ["05_guardia.sql", "10_esquema.sql", "20_rpc_repartidor.sql", "30_rpc_supervisor.sql", "55_permisos.sql", "60_semilla.sql"]
PERMISOS = ["public.geoportal_puede(text,text)", "public.geoportal_mis_permisos(text)", "public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)",
            "public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)"]
# Lo que el reparto LLAMA de campo sin tocarlo, con su md5 de producción (consulta A del 23-nov, RESULTADOS_consultas_AB_23nov.md)
CAMPO_LLAMADAS = {"campo.f_verificar(text,text)": "6133b5c36189e31743270064c8398b8a", "campo.f_autorizar_supervision(text)": "5ac3368fa5f3a6347328285501894aec",
                  "campo.f_actividades_persona(text)": "69bc9bd73d5797b826b3e504c1d92070", "campo.f_persona_comercial(text)": "99af03344249f7260357528096e92829",
                  "campo.f_quien_puede(text)": "5a381a87f432b8d2a6c88ad98a13fe3c"}
MD5_V_RUTAS = "51da701454deeee5accfd2163a9c8e31"   # consulta A del 23-nov; el doble local da la misma
COLUMNAS_V_RUTAS = "contrato:text,periodo_carga:text,ciclo:text,ruta:text,consecutivo_ruta:text,consecutivo_predio:text"
COLUMNAS_HECHOS_RUTAS = ",".join(f"{c}:text:YES:" for c in "ciclo consecutivo_ruta ruta contrato direccion consecutivo_predio periodo archivo_origen fecha_carga".split())
COLUMNAS_SUSCRIPCION = ("id:bigint:NO:nextval('cartera_suscripcion_id_seq'::regclass),contrato:text:NO:,"
    + ",".join(f"{c}:text:YES:" for c in "estado identificacion nombre correo telefono direccion barrio categoria subcategoria ciclo".split()) + ","
    + ",".join(f"{c}:numeric:YES:" for c in "facturas_pendientes deuda_total saldo_pendiente saldo_a_favor valor_reclamo saldo_financiado".split()) + ","
    + ",".join(f"{c}:text:YES:" for c in "serial_medidor codigo_reparto ruta".split()) + ",periodo_carga:text:NO:,cargado_en:timestamp with time zone:NO:now()")
CONJ_CAMPO = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
              "where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_campo\\_%')")
CONJ_SCRR = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
             "where p.pronamespace = to_regnamespace('scrr') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_scrr\\_%')")
CONJ_REPARTO = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
                "where p.pronamespace = to_regnamespace('reparto') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_reparto\\_%')")
SIN_WHERE_REPARTO = r"""(with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = to_regnamespace('reparto') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_reparto\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\m(where|using)\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M'))"""
CAB = "-- REPARTO DE FACTURAS · COMMIT 1 (SQL) · {que} (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)\n"
lee = lambda n: (SQL / n).read_text()

def psql(base, sql=None, archivo=None, at=True, ok=True):
    args = [PSQL, "-X", "-v", "ON_ERROR_STOP=1", "-d", base] + (["-At"] if at else [])
    if archivo: args += ["-f", str(archivo)]
    r = subprocess.run(args, input=sql, capture_output=True, text=True, env=ENV)
    if ok and r.returncode: raise SystemExit(f"psql falló en {base}: {r.stderr[-1500:]}")
    return r

def valor(base, q): return psql(base, q).stdout.strip()

def plantilla():
    """La plantilla se arma UNA vez (si no existe) y no se borra: las bases de cada corrida son copias. Si existe pero no es la de este paquete, se niega."""
    if valor("postgres", f"select count(*) from pg_database where datname = '{PLANTILLA}'") == "0":
        psql("postgres", f"create database {PLANTILLA}")
        for f in (DOBLE, DOBLE_SCRR, AQUI / "doble_rutas_local.sql", AQUI / "volumen_local.sql"):
            psql(PLANTILLA, archivo=f, at=False)
    elif valor(PLANTILLA, "select (to_regclass('bi.v_rutas_geoportal') is not null and (select count(*) from hechos.rutas_consecutivos) > 600000)::text") != "true":
        raise SystemExit(f"La plantilla {PLANTILLA} no tiene los dobles de rutas o el volumen. Este guion no la borra: pida permiso y bórrela a mano.")

def base_nueva(nombre):
    plantilla()
    if valor("postgres", f"select count(*) from pg_database where datname = '{nombre}'") != "0":
        raise SystemExit(f"La base {nombre} ya existe (resto de otra corrida). Este guion no la borra: pida permiso y bórrela a mano.")
    psql("postgres", f"create database {nombre} template {PLANTILLA}")
    return nombre

def borrar_mia(nombre):
    """Solo bases que creó ESTA corrida (su nombre lleva el número de proceso)."""
    assert nombre.endswith(f"_{os.getpid()}"), nombre
    psql("postgres", f"drop database if exists {nombre}", ok=False)

def cuerpo(): return "\n".join(lee(f) for f in FUENTES)
def poner(t, v):
    for k, x in v.items(): t = t.replace("{{" + k + "}}", x)
    assert "{{" not in t, re.findall(r"\{\{[A-Z_]+\}\}", t); return t

def md5p(f): return f"md5(pg_get_functiondef(to_regprocedure('{f}')))"

def main():
    b = base_nueva(f"reparto_gen_{os.getpid()}")
    try:
        loc = {f: valor(b, f"select {md5p(f)}") for f in CAMPO_LLAMADAS}
        assert loc == CAMPO_LLAMADAS, ("el doble de campo no es el de producción", loc)
        assert valor(b, CONJ_CAMPO) == "261bed3c9242f6261f845ec4e1374b3a"
        assert valor(b, "select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attnum) from pg_attribute a "
                        "where a.attrelid = 'bi.v_rutas_geoportal'::regclass and a.attnum > 0 and not a.attisdropped") == COLUMNAS_V_RUTAS
        assert valor(b, "select md5(pg_get_viewdef('bi.v_rutas_geoportal'::regclass, true))") == MD5_V_RUTAS
        cols = "select string_agg(column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, ''), ',' order by ordinal_position) from information_schema.columns "
        assert valor(b, cols + "where table_schema = 'hechos' and table_name = 'rutas_consecutivos'") == COLUMNAS_HECHOS_RUTAS
        assert valor(b, cols + "where table_schema = 'public' and table_name = 'cartera_suscripcion'") == COLUMNAS_SUSCRIPCION
        PROD = {"MD5_CAMPO_LLAMADAS": ", ".join(f"('{f}', '{m}')" for f, m in CAMPO_LLAMADAS.items()),
                "COLUMNAS_V_RUTAS": COLUMNAS_V_RUTAS, "MD5_V_RUTAS": MD5_V_RUTAS, "COLUMNAS_HECHOS_RUTAS": COLUMNAS_HECHOS_RUTAS,
                "COLUMNAS_SUSCRIPCION": COLUMNAS_SUSCRIPCION.replace("'", "''"), "SIN_WHERE_REPARTO": SIN_WHERE_REPARTO,
                "PERMISOS_SIN_CAMBIO": "not exists (select 1 from ztrep_antes z where z.f <> 'campo' and md5(pg_get_functiondef(to_regprocedure(z.f))) is distinct from z.md5)",
                "CAMPO_SIN_CAMBIO": f"({CONJ_CAMPO}) = (select z.md5 from ztrep_antes z where z.f = 'campo')"}
        permisos_antes = {f: valor(b, f"select {md5p(f)}") for f in PERMISOS}
        # en el ensayo, las md5 de las 4 funciones de permisos y la huella de campo se toman ANTES de la migración y se comparan al final (sirve en local y en producción)
        captura = ("create temp table ztrep_antes as select f, md5(pg_get_functiondef(to_regprocedure(f))) as md5 from unnest(array["
                   + ", ".join(f"'{f}'" for f in PERMISOS) + "]) f\n  union all select 'campo', (" + CONJ_CAMPO + ");\n")
        psql(b, "begin;\n" + poner(cuerpo(), PROD) + "\ncommit;\n", at=False)
        nuevas = {"HUELLA_REPARTO": valor(b, CONJ_REPARTO),
                  "RPC": valor(b, "select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname like 'geoportal\\_reparto\\_%'"),
                  "TABLAS": valor(b, "select count(*) from pg_class where relnamespace = 'reparto'::regnamespace and relkind = 'r'"),
                  "VISTAS": valor(b, "select count(*) from pg_class where relnamespace = 'reparto'::regnamespace and relkind = 'v'")}
        assert valor(b, CONJ_CAMPO) == "261bed3c9242f6261f845ec4e1374b3a"
    finally:
        borrar_mia(b)
    v = {**PROD, **nuevas}

    lista_campo = ", ".join(f"'{f}'" for f in CAMPO_LLAMADAS)
    huellas = f"""-- Solo lectura. ANTES: 1 «NO EXISTE»; 2 a 7 con su md5 (anótelas); 8 «LAS DE PRODUCCIÓN»; 9 «LA DE PRODUCCIÓN». DESPUÉS: 1 «CON ESTE CORTE»; 2 a 9 IGUALES a las de antes.
select o, k, v, estado from (
  select 1 as o, '1 funciones de reparto y public.geoportal_reparto_* (conjunto)' as k, ({CONJ_REPARTO}) as v,
         case when to_regnamespace('reparto') is null then 'NO EXISTE (sin aplicar)' when ({CONJ_REPARTO}) = '{nuevas["HUELLA_REPARTO"]}' then 'CON ESTE CORTE' else 'OTRA: deténgase y avise' end as estado
  union all
  select 2, '2 funciones de campo (conjunto)', ({CONJ_CAMPO}), 'anote: debe ser igual antes y después (hoy 261bed3c…; cambia con el paquete del Code B, que va antes)'
  union all
  select 3, '3 funciones de scrr (conjunto)', ({CONJ_SCRR}), 'anote: debe ser igual antes y después (722fc84b… el 23-nov)'
""" + "".join(f"""  union all
  select {i + 4}, '{i + 4} {f.split('(')[0]} (no se toca)', {md5p(f)}, 'anote: debe ser igual antes y después'
""" for i, f in enumerate(PERMISOS)) + f"""  union all
  select 8, '8 las 5 funciones de campo que llama el reparto', (select string_agg(md5(pg_get_functiondef(to_regprocedure(f))), ' ' order by f) from unnest(array[{lista_campo}]) f),
         case when (select bool_and(md5(pg_get_functiondef(to_regprocedure(x.f))) = x.m) from (values {PROD["MD5_CAMPO_LLAMADAS"]}) x(f, m)) then 'LAS DE PRODUCCIÓN (23-nov)' else 'OTRA: deténgase y avise' end
  union all
  select 9, '9 definición de bi.v_rutas_geoportal (md5; no se toca)', md5(pg_get_viewdef('bi.v_rutas_geoportal'::regclass, true)),
         case md5(pg_get_viewdef('bi.v_rutas_geoportal'::regclass, true)) when '51da701454deeee5accfd2163a9c8e31' then 'LA DE PRODUCCIÓN (23-nov)' else 'OTRA: deténgase y avise' end
) t order by o;
"""

    def fila(n, k, cond): return f"  select {n} as o, '{k}' as k, case when {cond} then 'OK' else 'FALLA' end as estado"
    ver = "select o, k, estado from (\n" + "\n  union all\n".join([
        fila(1, f"1 el esquema reparto con sus {nuevas['TABLAS']} tablas, {nuevas['VISTAS']} vistas y las {nuevas['RPC']} RPC con la huella del corte",
             f"to_regnamespace('reparto') is not null and (select count(*) from pg_class where relnamespace = 'reparto'::regnamespace and relkind = 'r') = {nuevas['TABLAS']} "
             f"and (select count(*) from pg_class where relnamespace = 'reparto'::regnamespace and relkind = 'v') = {nuevas['VISTAS']} "
             f"and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname like 'geoportal\\_reparto\\_%') = {nuevas['RPC']} and ({CONJ_REPARTO}) = '{nuevas['HUELLA_REPARTO']}'"),
        fila(2, "2 las 5 funciones de campo que llama el reparto siguen con su md5 de producción",
             f"(select bool_and(md5(pg_get_functiondef(to_regprocedure(x.f))) = x.m) from (values {PROD['MD5_CAMPO_LLAMADAS']}) x(f, m))"),
        fila(3, "3 permisos: las RPC solo service_role; reparto, nadie",
             "(select bool_and(has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') "
             "and not has_function_privilege('authenticated', p.oid, 'execute')) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_reparto\\_%') "
             "and not exists (select 1 from pg_proc p where p.pronamespace = 'reparto'::regnamespace and (has_function_privilege('service_role', p.oid, 'execute') "
             "or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))) "
             "and not exists (select 1 from pg_class c where c.relnamespace = 'reparto'::regnamespace and c.relkind in ('r','p','v') and (has_table_privilege('service_role', c.oid, 'select') "
             "or has_table_privilege('authenticated', c.oid, 'select') or has_table_privilege('anon', c.oid, 'select')))"),
        fila(4, "4 ninguna función de reparto con DELETE o UPDATE sin WHERE", SIN_WHERE_REPARTO + " = 0"),
        fila(5, "5 redes.f_funciones_sin_where() devuelve cero filas", "(select count(*) from redes.f_funciones_sin_where()) = 0"),
        fila(6, "6 semilla: 4 parámetros (ventana 5 días, vigencia de archivos 45, tope 10000 filas, precisión mala 30 m) y ningún dato",
             "(select jsonb_object_agg(clave, valor) from reparto.v_parametros_vigentes) = '{\"ventana_dias\": 5, \"lote_vigencia_dias\": 45, \"tope_filas_lote\": 10000, \"precision_mala_m\": 30}'::jsonb "
             "and not exists (select 1 from reparto.jornadas) and not exists (select 1 from reparto.entregas) and not exists (select 1 from reparto.lotes)"),
        fila(7, "7 las 8 tablas son de solo inserción (16 disparadores)",
             "(select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'reparto'::regnamespace and not t.tgisinternal "
             "and t.tgfoid = 'reparto.f_solo_insercion()'::regprocedure) = 16"),
    ]) + "\n) t order by o;\n"

    esc = lambda n, t: (PAQ / n).write_text(t)
    esc(f"migracion_{NOMBRE}_editor.sql", CAB.format(que="MIGRACIÓN (una transacción)") + "begin;\n" + poner(cuerpo(), v) + "\ncommit;\n")
    esc(f"ensayo_en_transaccion_{NOMBRE}_editor.sql", CAB.format(que="ENSAYO (termina en ERROR esperado; no deja nada)") + "begin;\n" + captura + poner(cuerpo(), v) + "\n"
        + poner(lee("70_pruebas.sql"), v) + "\nrollback;\n")
    esc(f"reversa_{NOMBRE}_editor.sql", CAB.format(que="REVERSA") + "begin;\n" + lee("90_reversa.sql") + "\ncommit;\n")
    esc(f"huellas_solo_lectura_{NOMBRE}_editor.sql", CAB.format(que="HUELLAS (solo lectura; ANTES y DESPUÉS)") + huellas)
    esc(f"verificacion_{NOMBRE}_editor.sql", CAB.format(que="VERIFICACIÓN (solo lectura; después de la migración: 7 de 7 OK)") + ver)
    (AQUI / "huellas_locales.json").write_text(json.dumps({"campo_llamadas": CAMPO_LLAMADAS, "permisos": permisos_antes, "nuevas": nuevas}, indent=1))
    for n in sorted(PAQ.glob("*_editor.sql")):
        t = n.read_text(); assert "on commit drop" not in t.lower(), n
        print(f"[OK ] {n.name}  md5 {hashlib.md5(t.encode()).hexdigest()}")
    print(json.dumps(nuevas, indent=1))

if __name__ == "__main__":
    main()
