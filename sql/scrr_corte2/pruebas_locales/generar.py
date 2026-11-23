"""Arma los archivos _editor del Motor SCRR, corte 2 (modo «Cartera»), desde sql/ y una base local TEMPORAL del Code A (clúster 55432; NUNCA Supabase).
La base es el doble de Administración con el cargo del supervisor (doble_admin_permisos_4a_con_cargo_supervisor.sql, campo 261bed3c… = producción del 22-nov 13:46).
Uso: python3 -I generar.py [-h]"""
import sys, re, json, pathlib, subprocess, hashlib, os
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent; SQL = PAQ / "sql"; H = pathlib.Path.home()
NOMBRE = "scrr_corte2"
DOBLE = H / "geoportal-consultas/campo/admin_perfiles_22nov/doble_admin_4a/doble_admin_permisos_4a_con_cargo_supervisor.sql"
PSQL = "/opt/homebrew/opt/postgresql@17/bin/psql"
ENV = {**os.environ, "PGHOST": "localhost", "PGPORT": "55432", "PGUSER": "postgres", "PGOPTIONS": "-c client_min_messages=warning", "LC_ALL": "C"}
FUENTES = ["05_guardia.sql", "10_esquema.sql", "20_cargas.sql", "25_control_calendario_corridas.sql", "30_rpc_cargas.sql", "35_rpc_control_calendario.sql",
           "38_rpc_seleccion.sql", "40_retorno.sql", "50_refresco_mapa.sql", "55_permisos.sql", "60_semilla.sql"]
PERMISOS = ["public.geoportal_puede(text,text)", "public.geoportal_mis_permisos(text)", "public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)",
            "public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)"]
CONJ_CAMPO = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
              "where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_campo\\_%')")
CONJ_SCRR = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
             "where p.pronamespace = to_regnamespace('scrr') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_scrr\\_%')")
SIN_WHERE_SCRR = r"""(with f as (
    select p.oid::regprocedure::text as funcion, regexp_replace(regexp_replace(lower(p.prosrc), '--[^\n]*', '', 'g'), '\mdo\s+update\M', 'do_update', 'g') as src
      from pg_proc p join pg_language l on l.oid = p.prolang
     where l.lanname in ('plpgsql', 'sql') and p.prokind in ('f', 'p')
       and (p.pronamespace = to_regnamespace('scrr') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_scrr\_%'))),
  s as (select f.funcion, btrim(regexp_replace(x, '\s+', ' ', 'g')) as st from f, regexp_split_to_table(f.src, ';') x)
  select count(*) from s
   where (s.st ~ '\mdelete\s+from\M' and substring(s.st from '\mdelete\s+from\M.*$') !~ '\m(where|using)\M')
      or (s.st ~ '\mupdate\s+(only\s+)?[a-z_][a-z0-9_."]*(\s+(as\s+)?[a-z_][a-z0-9_]*)?\s+set\M'
          and substring(s.st from '\mupdate\s+(?:only\s+)?[a-z_][a-z0-9_."]*(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?\s+set\M.*$') !~ '\mwhere\M'))"""
CAB = "-- MOTOR SCRR · CORTE 2 (modo «Cartera») · {que} (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)\n"
lee = lambda n: (SQL / n).read_text()

def psql(base, sql=None, archivo=None, at=True, ok=True):
    args = [PSQL, "-X", "-v", "ON_ERROR_STOP=1", "-d", base] + (["-At"] if at else [])
    if archivo: args += ["-f", str(archivo)]
    r = subprocess.run(args, input=sql, capture_output=True, text=True, env=ENV)
    if ok and r.returncode: raise SystemExit(f"psql falló en {base}: {r.stderr[-1500:]}")
    return r

def sin_restos():
    """Regla de David (22-nov): ningún guion borra bases que no haya creado esa misma corrida. Si quedaron restos de otra corrida (bases de prueba o el rol
    scrr_refresco, que es del CLÚSTER), se niega y pide borrarlos a mano con permiso; no los toca."""
    # Lo que de verdad choca es el rol (del clúster) y las bases que lo tienen (la del servidor de revisión y la de Chrome). Las bases de prueba de esta corrida
    # llevan un nombre propio (con el número de proceso), así que un resto de otra corrida no estorba: se reporta y se borra solo con permiso.
    restos = psql("postgres", "select string_agg(datname, ', ' order by datname) from pg_database where datname in ('scrr_chrome', 'scrr_rev')").stdout.strip()
    rol = psql("postgres", "select count(*) from pg_roles where rolname = 'scrr_refresco'").stdout.strip() != "0"
    if restos or rol:
        raise SystemExit(f"Quedaron restos de otra corrida (bases: {restos or 'ninguna'}; rol scrr_refresco: {'sí' if rol else 'no'}). "
                         "Este guion no borra lo que no creó: pida permiso y bórrelos a mano (con su porqué y su alcance), y vuelva a correrlo.")

def base_nueva(nombre):
    """Copia limpia del doble: la plantilla «scrr_plantilla_v2» se arma una vez desde el archivo del doble. La base nueva la crea ESTA corrida (si ya existe, se niega)."""
    if psql("postgres", "select 1 from pg_database where datname = 'scrr_plantilla_v2'").stdout.strip() != "1":
        psql("postgres", "create database scrr_plantilla_v2")
        psql("scrr_plantilla_v2", archivo=DOBLE, at=False)
        psql("scrr_plantilla_v2", archivo=AQUI / "doble_base_local.sql", at=False)
    elif psql("scrr_plantilla_v2", "select (to_regclass('hechos.facturacion_sspd') is not null and (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'cartera_suscripcion') = 23)::text").stdout.strip() != "true":
        raise SystemExit("La plantilla scrr_plantilla_v2 es vieja (sin los dobles locales). Este guion no la borra: pida permiso y bórrela a mano.")
    if psql("postgres", f"select 1 from pg_database where datname = '{nombre}'").stdout.strip() == "1":
        raise SystemExit(f"La base {nombre} ya existe (resto de otra corrida). Este guion no la borra: pida permiso y bórrela a mano.")
    psql("postgres", f"create database {nombre} template scrr_plantilla_v2")
    return nombre

def valor(base, q): return psql(base, q).stdout.strip()
def cuerpo(): return "\n".join(lee(f) for f in FUENTES)
def poner(t, v):
    for k, x in v.items(): t = t.replace("{{" + k + "}}", x)
    assert "{{" not in t, re.findall(r"\{\{[A-Z_]+\}\}", t); return t

def main():
    sin_restos()
    b = base_nueva(f"scrr_gen_{os.getpid()}")
    md5p = lambda f: f"md5(pg_get_functiondef(to_regprocedure('{f}')))"
    PROD = {"HUELLA_CAMPO": valor(b, CONJ_CAMPO), "MD5_AUTORIZAR_SUPERVISION": valor(b, f"select {md5p('campo.f_autorizar_supervision(text)')}"),
            "COLUMNAS_SUSCRIPCION": valor(b, "select string_agg(column_name || ':' || data_type, ',' order by ordinal_position) from information_schema.columns "
                                              "where table_schema = 'public' and table_name = 'cartera_suscripcion'"),
            "SIN_WHERE_SCRR": SIN_WHERE_SCRR}
    assert PROD["HUELLA_CAMPO"] == "261bed3c9242f6261f845ec4e1374b3a", PROD
    assert PROD["MD5_AUTORIZAR_SUPERVISION"] == "5ac3368fa5f3a6347328285501894aec", PROD
    # las 23 columnas de producción (David, 22-nov: id al principio, cargado_en al final)
    assert PROD["COLUMNAS_SUSCRIPCION"] == ("id:bigint,contrato:text,estado:text,identificacion:text,nombre:text,correo:text,telefono:text,direccion:text,barrio:text,"
        "categoria:text,subcategoria:text,ciclo:text,facturas_pendientes:numeric,deuda_total:numeric,saldo_pendiente:numeric,saldo_a_favor:numeric,valor_reclamo:numeric,"
        "saldo_financiado:numeric,serial_medidor:text,codigo_reparto:text,ruta:text,periodo_carga:text,cargado_en:timestamp with time zone"), PROD["COLUMNAS_SUSCRIPCION"]
    permisos_antes = {f: valor(b, f"select {md5p(f)}") for f in PERMISOS}
    # en el ensayo, las md5 de las 4 funciones de permisos se toman ANTES de la migración y se comparan al final (sirve en local y en producción)
    captura = ("create temp table ztscrr_permisos as select f, md5(pg_get_functiondef(to_regprocedure(f))) as md5 from unnest(array["
               + ", ".join(f"'{f}'" for f in PERMISOS) + "]) f;\n")
    PROD["PERMISOS_SIN_CAMPO"] = ""
    PROD["PERMISOS_SIN_CAMBIO"] = "not exists (select 1 from ztscrr_permisos z where md5(pg_get_functiondef(to_regprocedure(z.f))) is distinct from z.md5)"
    psql(b, "begin;\n" + poner(cuerpo(), PROD) + "\ncommit;\n", at=False)
    nuevas = {"HUELLA_SCRR": valor(b, CONJ_SCRR), "RPC": valor(b, "select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname like 'geoportal\\_scrr\\_%'"),
              "TABLAS": valor(b, "select count(*) from pg_class where relnamespace = 'scrr'::regnamespace and relkind in ('r','p') and not relispartition")}
    assert valor(b, CONJ_CAMPO) == PROD["HUELLA_CAMPO"]
    psql("postgres", f"drop database {b}"); psql("postgres", "drop role if exists scrr_refresco")
    v = {**PROD, **nuevas}

    huellas = f"""-- Solo lectura. ANTES: 1 «PUBLICADA (22-nov 13:46)», 2 «NO EXISTE», 3 a 6 con su md5 (anótelas). DESPUÉS: 1 igual, 2 «CON ESTE CORTE», 3 a 6 IGUALES a las de antes.
select o, k, v, estado from (
  select 1 as o, '1 funciones de campo (conjunto)' as k, ({CONJ_CAMPO}) as v,
         case ({CONJ_CAMPO}) when '{PROD["HUELLA_CAMPO"]}' then 'PUBLICADA (22-nov 13:46): lista para este corte' else 'OTRA: deténgase y avise' end as estado
  union all
  select 2, '2 funciones de scrr y public.geoportal_scrr_* (conjunto)', ({CONJ_SCRR}),
         case when to_regnamespace('scrr') is null then 'NO EXISTE (sin aplicar)' when ({CONJ_SCRR}) = '{nuevas["HUELLA_SCRR"]}' then 'CON ESTE CORTE' else 'OTRA: deténgase y avise' end
""" + "".join(f"""  union all
  select {i + 3}, '{i + 3} {f.split('(')[0]} (no se toca)', {md5p(f)}, 'anote: debe ser igual antes y después'
""" for i, f in enumerate(PERMISOS)) + ") t order by o;\n"

    def fila(n, k, cond): return f"  select {n} as o, '{k}' as k, case when {cond} then 'OK' else 'FALLA' end as estado"
    ver = "select o, k, estado from (\n" + "\n  union all\n".join([
        fila(1, f"1 el esquema scrr con sus {nuevas['TABLAS']} tablas y las {nuevas['RPC']} RPC con la huella del corte",
             f"to_regnamespace('scrr') is not null and (select count(*) from pg_class where relnamespace = 'scrr'::regnamespace and relkind in ('r','p') and not relispartition) = {nuevas['TABLAS']} "
             f"and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname like 'geoportal\\_scrr\\_%') = {nuevas['RPC']} and ({CONJ_SCRR}) = '{nuevas['HUELLA_SCRR']}'"),
        fila(2, "2 la huella de campo no cambió (261bed3c…)", f"({CONJ_CAMPO}) = '{PROD['HUELLA_CAMPO']}'"),
        fila(3, "3 permisos: las RPC solo service_role; scrr, nadie",
             "(select bool_and(has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') "
             "and not has_function_privilege('authenticated', p.oid, 'execute')) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_scrr\\_%') "
             "and not exists (select 1 from pg_proc p where p.pronamespace = 'scrr'::regnamespace and (has_function_privilege('service_role', p.oid, 'execute') "
             "or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))) "
             "and not exists (select 1 from pg_class c where c.relnamespace = 'scrr'::regnamespace and c.relkind in ('r','p','v') and (has_table_privilege('service_role', c.oid, 'select') "
             "or has_table_privilege('authenticated', c.oid, 'select') or has_table_privilege('anon', c.oid, 'select')))"),
        fila(4, "4 ninguna función de scrr con DELETE o UPDATE sin WHERE", SIN_WHERE_SCRR + " = 0"),
        fila(5, "5 redes.f_funciones_sin_where() devuelve cero filas", "(select count(*) from redes.f_funciones_sin_where()) = 0"),
        fila(6, "6 semilla: 11 parámetros, 6 tipos de actividad, 17 anomalías DEFINITIVAS, 4 causas de control y el calendario de noviembre (24 ciclos)",
             "(select count(*) from scrr.v_parametros_vigentes) = 11 and (select count(*) from scrr.tipos_actividad) = 6 "
             "and (select count(*) from scrr.anomalias where not provisional) = 17 and (select count(*) from scrr.causas_control) = 4 "
             "and (select count(*) from scrr.v_calendario_vigente where periodo = '202611') >= 24"),
        fila(7, "7 particiones de hoy: historial del día y pagos del mes",
             "to_regclass('scrr.cartera_historial_' || to_char((now() at time zone 'America/Bogota')::date, 'YYYYMMDD')) is not null "
             "and to_regclass('scrr.pagos_contrato_' || to_char((now() at time zone 'America/Bogota')::date, 'YYYYMM')) is not null"),
        fila(8, "8 public.cartera_suscripcion con sus mismas 23 columnas (id … cargado_en)",
             f"(select string_agg(column_name || ':' || data_type, ',' order by ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'cartera_suscripcion') = '{PROD['COLUMNAS_SUSCRIPCION']}'"),
        fila(9, "9 rol scrr_refresco: solo MAINTAIN sobre predios_comercial (sin superusuario; el login lo da David aparte)",
             "exists (select 1 from pg_roles where rolname = 'scrr_refresco' and not rolsuper and not rolcreaterole and not rolinherit) "
             "and has_table_privilege('scrr_refresco', 'public.predios_comercial', 'MAINTAIN') and not has_table_privilege('scrr_refresco', 'public.predios_comercial', 'SELECT')"),
    ]) + "\n) t order by o;\n"

    reversa = lee("90_reversa.sql")
    esc = lambda n, t: (PAQ / n).write_text(t)
    esc(f"migracion_{NOMBRE}_editor.sql", CAB.format(que="MIGRACIÓN (una transacción)") + "begin;\n" + poner(cuerpo(), v) + "\ncommit;\n")
    esc(f"ensayo_en_transaccion_{NOMBRE}_editor.sql", CAB.format(que="ENSAYO (termina en ERROR esperado; no deja nada)") + "begin;\n" + captura + poner(cuerpo(), v) + "\n"
        + poner(lee("70_pruebas.sql"), v) + "\nrollback;\n")
    esc(f"reversa_{NOMBRE}_editor.sql", CAB.format(que="REVERSA") + "begin;\n" + reversa + "\ncommit;\n")
    esc(f"huellas_solo_lectura_{NOMBRE}_editor.sql", CAB.format(que="HUELLAS (solo lectura; ANTES y DESPUÉS)") + huellas)
    esc(f"verificacion_{NOMBRE}_editor.sql", CAB.format(que="VERIFICACIÓN (solo lectura; después de la migración: 9 de 9 OK)") + ver)
    (AQUI / "huellas_locales.json").write_text(json.dumps({"partida": {k: PROD[k] for k in ("HUELLA_CAMPO", "MD5_AUTORIZAR_SUPERVISION")}, "permisos": permisos_antes, "nuevas": nuevas}, indent=1))
    for n in sorted(PAQ.glob("*_editor.sql")):
        t = n.read_text(); assert "on commit drop" not in t.lower(), n
        print(f"[OK ] {n.name}  md5 {hashlib.md5(t.encode()).hexdigest()}")
    print(json.dumps(nuevas, indent=1))

if __name__ == "__main__":
    main()
