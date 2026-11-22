"""Arma los archivos _editor del cambio «el supervisor de campo cambia área y cargo de los operarios» (Comercial 22-nov), desde sql/ y una base local
TEMPORAL (pgserver; NUNCA Supabase). La base es el doble de Administración del 22-nov (campo 3437a83d… y acta 111506c6… = producción del 21-nov 19:45).
Uso: python3 -I generar.py [-h]"""
import sys, re, json, pathlib, subprocess, tempfile, hashlib, importlib.util
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
import pgserver, psycopg
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent; SQL = PAQ / "sql"; H = pathlib.Path.home()
NOMBRE = "campo_cargo_supervisor"
DOBLE = H / "geoportal-consultas/campo/admin_perfiles_22nov/doble_admin_4a/doble_admin_permisos_4a.sql"
PSQL = "/opt/homebrew/opt/postgresql@17/bin/psql"
s = importlib.util.spec_from_file_location("ga", PAQ.parent / "campo_personal_cuadrillas/pruebas_locales/generar.py"); ga = importlib.util.module_from_spec(s); s.loader.exec_module(ga)
PROD = {"HUELLA_CAMPO": "3437a83d1d90055c9861b0964c8f8ffb", "HUELLA_ACTA": "111506c690249ad3b56ebf572566434c",
        "MD5_FIJAR": "fc362a2894e064767cfca039fa5ed299", "MD5_PERSONAL": "7028ce4016505ed5fd8ae706db91464c", "SIN_WHERE_CAMPO": ga.SINWHERE}
FIJAR = "public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)"; PERS = "public.geoportal_campo_personal(text,jsonb,text)"
CONJ = {"campo": "select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
                 "where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_campo\\_%')",
        "acta": "select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
                "where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_acta\\_%')"}
lee = lambda n: (SQL / n).read_text()
CAB = "-- COMERCIAL 22-NOV · CARGO Y ÁREA POR EL SUPERVISOR DE CAMPO · {que} (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)\n"
def cuerpo(): return "\n".join([lee("05_guardia.sql"), lee("20_funciones.sql"), lee("26_rpc.sql"), lee("40_permisos.sql")])
def poner(t, v):
    for k, x in v.items(): t = t.replace("{{" + k + "}}", x)
    assert "{{" not in t, re.findall(r"\{\{[A-Z_]+\}\}", t); return t

def preparar():
    """Base local = el doble de Administración del 22-nov. Devuelve srv, uri, con."""
    srv = pgserver.get_server(tempfile.mkdtemp(prefix="cargo_sup_"), cleanup_mode="delete"); uri = srv.get_uri()
    r = subprocess.run([PSQL, uri, "-v", "ON_ERROR_STOP=1", "-q", "-f", str(DOBLE)], capture_output=True, text=True)
    if r.returncode: raise SystemExit("No cargó el doble: " + r.stderr[-400:])
    return srv, uri, psycopg.connect(uri, autocommit=True)

def md5f(con, f): return con.execute("select md5(pg_get_functiondef(to_regprocedure(%s)))", (f,)).fetchone()[0]

def main():
    srv, uri, con = preparar()
    base = {k: con.execute(v).fetchone()[0] for k, v in CONJ.items()}
    assert base == {"campo": PROD["HUELLA_CAMPO"], "acta": PROD["HUELLA_ACTA"]}, base
    assert md5f(con, FIJAR) == PROD["MD5_FIJAR"] and md5f(con, PERS) == PROD["MD5_PERSONAL"]
    resp = {"RESPALDO_FIJAR": con.execute("select pg_get_functiondef(to_regprocedure(%s))", (FIJAR,)).fetchone()[0].rstrip() + ";",
            "RESPALDO_PERSONAL": con.execute("select pg_get_functiondef(to_regprocedure(%s))", (PERS,)).fetchone()[0].rstrip() + ";"}
    con.execute(poner(cuerpo(), PROD))
    nuevas = {"MD5_FIJAR_NUEVA": md5f(con, FIJAR), "MD5_PERSONAL_NUEVA": md5f(con, PERS), "MD5_SUPERVISOR": md5f(con, "campo.f_supervisor_comercial(text)"),
              "HUELLA_CAMPO_NUEVA": con.execute(CONJ["campo"]).fetchone()[0]}
    con.close(); srv.cleanup()
    v = {**PROD, **resp, **nuevas}
    huellas = f"""-- Solo lectura. ANTES: 1 «PUBLICADA (21-nov 19:45)», 2 «PUBLICADA», 3 y 4 «PUBLICADA», 5 «NO EXISTE». DESPUÉS: 1 «CON ESTE CAMBIO» (anótela), 2 igual, 3 y 4 «CON ESTE CAMBIO», 5 «NUEVA».
select o, k, v, estado from (
  select 1 as o, '1 funciones de campo (conjunto, todas)' as k, ({CONJ["campo"]}) as v,
         case ({CONJ["campo"]}) when '{PROD["HUELLA_CAMPO"]}' then 'PUBLICADA (21-nov 19:45): lista para este cambio' when '{nuevas["HUELLA_CAMPO_NUEVA"]}' then 'CON ESTE CAMBIO' else 'OTRA: deténgase y avise' end as estado
  union all
  select 2, '2 funciones del acta (conjunto)', ({CONJ["acta"]}), case ({CONJ["acta"]}) when '{PROD["HUELLA_ACTA"]}' then 'PUBLICADA (no cambia con este paquete)' else 'OTRA: deténgase y avise' end
  union all
  select 3, '3 {FIJAR}', md5(pg_get_functiondef(to_regprocedure('{FIJAR}'))),
         case md5(pg_get_functiondef(to_regprocedure('{FIJAR}'))) when '{PROD["MD5_FIJAR"]}' then 'PUBLICADA' when '{nuevas["MD5_FIJAR_NUEVA"]}' then 'CON ESTE CAMBIO' else 'OTRA: deténgase y avise' end
  union all
  select 4, '4 {PERS}', md5(pg_get_functiondef(to_regprocedure('{PERS}'))),
         case md5(pg_get_functiondef(to_regprocedure('{PERS}'))) when '{PROD["MD5_PERSONAL"]}' then 'PUBLICADA' when '{nuevas["MD5_PERSONAL_NUEVA"]}' then 'CON ESTE CAMBIO' else 'OTRA: deténgase y avise' end
  union all
  select 5, '5 campo.f_supervisor_comercial(text) (nueva)', case when to_regprocedure('campo.f_supervisor_comercial(text)') is not null then md5(pg_get_functiondef(to_regprocedure('campo.f_supervisor_comercial(text)'))) end,
         case when to_regprocedure('campo.f_supervisor_comercial(text)') is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure('campo.f_supervisor_comercial(text)'))) = '{nuevas["MD5_SUPERVISOR"]}' then 'NUEVA (aplicada)' else 'OTRA: deténgase y avise' end
) t order by o;
"""
    def fila(n, k, cond): return f"  select {n} as o, '{k}' as k, case when {cond} then 'OK' else 'FALLA' end as estado"
    ver = "select o, k, estado from (\n" + "\n  union all\n".join([
        fila(1, "1 las dos RPC y la función nueva con su md5", f"md5(pg_get_functiondef(to_regprocedure('{FIJAR}'))) = '{nuevas['MD5_FIJAR_NUEVA']}' and md5(pg_get_functiondef(to_regprocedure('{PERS}'))) = '{nuevas['MD5_PERSONAL_NUEVA']}' "
             f"and md5(pg_get_functiondef(to_regprocedure('campo.f_supervisor_comercial(text)'))) = '{nuevas['MD5_SUPERVISOR']}'"),
        fila(2, "2 la huella de campo es la de este cambio", f"({CONJ['campo']}) = '{nuevas['HUELLA_CAMPO_NUEVA']}'"),
        fila(3, "3 la huella del acta no cambió (111506c6…)", f"({CONJ['acta']}) = '{PROD['HUELLA_ACTA']}'"),
        fila(4, "4 permisos: las dos RPC solo service_role; la función nueva, nadie",
             f"has_function_privilege('service_role', '{FIJAR}', 'execute') and has_function_privilege('service_role', '{PERS}', 'execute') "
             f"and not has_function_privilege('anon', '{FIJAR}', 'execute') and not has_function_privilege('authenticated', '{FIJAR}', 'execute') "
             f"and not has_function_privilege('anon', '{PERS}', 'execute') and not has_function_privilege('authenticated', '{PERS}', 'execute') "
             "and not has_function_privilege('service_role', 'campo.f_supervisor_comercial(text)', 'execute') and not has_function_privilege('authenticated', 'campo.f_supervisor_comercial(text)', 'execute') "
             "and not has_function_privilege('anon', 'campo.f_supervisor_comercial(text)', 'execute')"),
        fila(5, "5 ninguna función de campo con DELETE o UPDATE sin WHERE", ga.SINWHERE + " = 0"),
        fila(6, "6 redes.f_funciones_sin_where() devuelve cero filas", "(select count(*) from redes.f_funciones_sin_where()) = 0"),
    ]) + "\n) t order by o;\n"
    esc = lambda n, t: (PAQ / n).write_text(t)
    esc(f"migracion_{NOMBRE}_editor.sql", CAB.format(que="MIGRACIÓN") + "begin;\n" + poner(cuerpo(), v) + "\ncommit;\n")
    esc(f"ensayo_en_transaccion_{NOMBRE}_editor.sql", CAB.format(que="ENSAYO (termina en ERROR esperado; no deja nada)") + "begin;\n" + poner(cuerpo(), v) + "\n" + poner(lee("70_pruebas.sql"), v) + "\nrollback;\n")
    esc(f"reversa_{NOMBRE}_editor.sql", CAB.format(que="REVERSA") + "begin;\n" + poner(lee("90_reversa.sql"), v) + "\ncommit;\n")
    esc(f"huellas_solo_lectura_{NOMBRE}_editor.sql", CAB.format(que="HUELLAS (solo lectura; ANTES y DESPUÉS)") + huellas)
    esc(f"verificacion_{NOMBRE}_editor.sql", CAB.format(que="VERIFICACIÓN (solo lectura; después de la migración: 6 de 6 OK)") + ver)
    (AQUI / "huellas_locales.json").write_text(json.dumps({"partida": {k: PROD[k] for k in ("HUELLA_CAMPO", "HUELLA_ACTA", "MD5_FIJAR", "MD5_PERSONAL")}, "nuevas": nuevas}, indent=1))
    for n in sorted(PAQ.glob("*_editor.sql")):
        t = n.read_text(); assert "on commit drop" not in t.lower(), n
        print(f"[OK ] {n.name}  md5 {hashlib.md5(t.encode()).hexdigest()}")
    print(json.dumps(nuevas, indent=1))

if __name__ == "__main__":
    main()
