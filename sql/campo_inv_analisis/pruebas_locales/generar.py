"""[Code B] Arma los archivos _editor del paquete «Investigación de ubicación recortada y avisos del Análisis de contrato» (23-nov)
desde sql/ y el doble de producción (rehacer_doble.py con produccion_doble.csv, 163 de 163 filas iguales). NUNCA Supabase.
Base: clúster del Code B (55442), base emdupar_b_inv_gen, que este guion rehace en cada corrida.
Uso: python3 -I generar.py [-h]"""
import sys, re, json, pathlib, subprocess, hashlib, os
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
import psycopg
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent; SQL = PAQ / "sql"; H = pathlib.Path.home()
NOMBRE = "campo_inv_analisis"
CSV_PROD = H / "geoportal-consultas/campo/paquete_inv_analisis_1/produccion_doble.csv"
PUERTO = os.environ.get("PGPORT_B", "55442")
def uri(db): return f"postgresql://postgres@localhost:{PUERTO}/{db}"

CONJ = {"campo": "select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
                 "where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_campo\\_%')",
        "acta": "select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
                "where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_acta\\_%')"}
PUBLICADA = {"campo": "261bed3c9242f6261f845ec4e1374b3a", "acta": "111506c690249ad3b56ebf572566434c"}
# Las 4 funciones de permisos vivas (md5 de producción, del SCRR corte 2): no se tocan
PERMISOS = {"public.geoportal_puede(text,text)": "32f174a55b95788d3f8187b507303c2f",
            "public.geoportal_mis_permisos(text)": "83166fe17be58da67bbdedaae429bedb",
            "public.geoportal_admin_guardar(text,text,text,text,boolean,text,text)": "01fda69a9d912067b8b4dc153ac7957e",
            "public.geoportal_admin_permisos(text,text,boolean,boolean,boolean,boolean,text,text,boolean,boolean,boolean,text,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean)": "e5a90103b4a83440fd826f03266b7245"}
PREPARAR = "public.geoportal_campo_preparar_subida(text,integer,text,text,text)"
CREAR = "public.geoportal_campo_crear_reporte(text,uuid,text,text,text,text,numeric,numeric,numeric,boolean,text,jsonb,text,jsonb,text,text,uuid,timestamp with time zone)"
# Funciones cuyo md5 exige la guardia: las que se reemplazan y aquellas de las que depende el cambio
FUNCIONES = [PREPARAR, CREAR, "public.geoportal_campo_obtener_formulario(text,boolean)", "campo.f_validar_datos(bigint,jsonb,boolean)", *PERMISOS]
# Tablas vivas que el paquete lee o toca: su estructura exacta va a la guardia
TABLAS = ["campo.tipos_reporte", "campo.tipo_campos", "campo.tipo_fotos", "campo.actividades", "campo.derivadas", "campo.derivadas_catalogo",
          "campo.derivada_eventos", "campo.consultas_analisis", "campo.causales_tipos", "campo.formularios_documento", "campo.grupos_reporte"]
# Estructura de una tabla (z.rel): columnas con tipo, NOT NULL, valor por omisión e identidad; restricciones; índices; disparadores; clase, RLS y permisos.
# Las políticas RLS no entran: la consulta de producción del 23-nov no las trajo (las tablas nuevas copian las de campo.derivadas en la migración).
EST_EXPR = ("md5(concat_ws('#', "
  "(select string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod) || case when a.attnotnull then ' NOT NULL' else '' end "
  "|| coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '') || case when a.attidentity <> '' then ' IDENTITY ' || a.attidentity::text else '' end, ', ' order by a.attnum) "
  "from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum where a.attrelid = z.rel and a.attnum > 0 and not a.attisdropped), "
  "(select string_agg(c.conname || ' ' || pg_get_constraintdef(c.oid), ' | ' order by c.conname) from pg_constraint c where c.conrelid = z.rel), "
  "(select string_agg(pg_get_indexdef(i.indexrelid), ' | ' order by pg_get_indexdef(i.indexrelid)) from pg_index i where i.indrelid = z.rel), "
  "(select string_agg(pg_get_triggerdef(g.oid), ' | ' order by g.tgname) from pg_trigger g where g.tgrelid = z.rel and not g.tgisinternal), "
  "(select c.relkind::text || ' ' || c.relrowsecurity::text || ' ' || coalesce(c.relacl::text, '') from pg_class c where c.oid = z.rel)))")
INV_CAMPOS_Q = ("select string_agg(c.codigo || ':' || c.tipo_dato || ':' || c.obligatorio::text || ':' || c.activo::text, ',' order by c.codigo) "
                "from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id where t.codigo = 'investigacion_ubicacion'")
INV_FOTOS_Q = ("select string_agg(f.codigo || ':' || f.obligatoria::text || ':' || f.soporte_inefectiva::text || ':' || f.activo::text, ',' order by f.codigo) "
               "from campo.tipo_fotos f join campo.tipos_reporte t on t.id = f.tipo_id where t.codigo = 'investigacion_ubicacion'")
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
PARTES = ["05_guardia.sql", "10_investigacion.sql", "20_preparar_subida.sql"]
lee = lambda n: (SQL / n).read_text()
CAB = "-- [Code B] INVESTIGACIÓN Y ANÁLISIS (23-nov) · {que} (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)\n"
def cuerpo(): return "\n".join(lee(n) for n in PARTES)
def poner(t, v):
    for k, x in v.items(): t = t.replace("{{" + k + "}}", x)
    assert "{{" not in t, re.findall(r"\{\{[A-Z_0-9]+\}\}", t); return t
def lit(s): return "'" + s.replace("'", "''") + "'"

def rehacer(db):
    """Rehace la base `db` (emdupar_b_inv*) como copia exacta de producción. Devuelve una conexión."""
    r = subprocess.run([sys.executable, "-I", str(AQUI / "rehacer_doble.py"), "--csv", str(CSV_PROD), "--db", db], capture_output=True, text=True)
    if r.returncode or "SIN DIFERENCIAS" not in r.stdout: raise SystemExit("El doble no quedó igual a producción:\n" + r.stdout[-2000:] + r.stderr[-2000:])
    return psycopg.connect(uri(db), autocommit=True)

def md5f(con, f): return con.execute("select md5(pg_get_functiondef(to_regprocedure(%s)))", (f,)).fetchone()[0]
def est(con, t): return con.execute(f"select {EST_EXPR} from (select to_regclass(%s) as rel) z", (t,)).fetchone()[0]

def valores(con):
    base = {k: con.execute(v).fetchone()[0] for k, v in CONJ.items()}
    assert base == PUBLICADA, base
    for f, m in PERMISOS.items(): assert md5f(con, f) == m, f
    p = {"HUELLA_CAMPO": base["campo"], "HUELLA_ACTA": base["acta"], "MD5_PREPARAR": md5f(con, PREPARAR), "MD5_CREAR": md5f(con, CREAR), "F_CREAR": CREAR,
         "MD5_FUNCIONES": ", ".join(f"({lit(f)}, {lit(md5f(con, f))})" for f in FUNCIONES),
         "EST_LISTA": ", ".join(f"({lit(t)}, {lit(est(con, t))})" for t in TABLAS), "EST_EXPR": EST_EXPR,
         "INV_CAMPOS": con.execute(INV_CAMPOS_Q).fetchone()[0], "INV_FOTOS": con.execute(INV_FOTOS_Q).fetchone()[0],
         "SIN_WHERE_CAMPO": SINWHERE, "PERMISOS_IGUALES": " and ".join(f"md5(pg_get_functiondef(to_regprocedure({lit(f)}))) = {lit(m)}" for f, m in PERMISOS.items()),
         "RESPALDO_PREPARAR": con.execute("select pg_get_functiondef(to_regprocedure(%s))", (PREPARAR,)).fetchone()[0].rstrip() + ";"}
    # md5 de preparar_subida nueva (se aplica sola dentro de una transacción que se deshace)
    with con.transaction(force_rollback=True):
        con.execute(lee("20_preparar_subida.sql")); p["MD5_PREPARAR_NUEVA"] = md5f(con, PREPARAR)
    # el estado de los campos de la Investigación después de migrar y revertir (la guardia lo acepta para volver a aplicar)
    with con.transaction(force_rollback=True):
        con.execute(poner(cuerpo(), {**p, "INV_CAMPOS_TRAS_REVERSA": "(se calcula)"}))
        p["HUELLA_CAMPO_NUEVA"] = con.execute(CONJ["campo"]).fetchone()[0]
        p["INV_CAMPOS_NUEVA"] = con.execute(INV_CAMPOS_Q).fetchone()[0]; p["INV_FOTOS_NUEVA"] = con.execute(INV_FOTOS_Q).fetchone()[0]
        con.execute(poner(lee("90_reversa.sql"), p))
        p["INV_CAMPOS_TRAS_REVERSA"] = con.execute(INV_CAMPOS_Q).fetchone()[0]
        assert con.execute(CONJ["campo"]).fetchone()[0] == p["HUELLA_CAMPO"]
    return p

def archivos(p):
    huellas = f"""-- Solo lectura. ANTES: 1 «PUBLICADA», 2 «PUBLICADA», 3 «PUBLICADA». DESPUÉS: 1 «CON ESTE CAMBIO» (anótela), 2 igual, 3 «CON ESTE CAMBIO».
select o, k, v, estado from (
  select 1 as o, '1 funciones de campo (conjunto, todas)' as k, ({CONJ["campo"]}) as v,
         case ({CONJ["campo"]}) when '{p["HUELLA_CAMPO"]}' then 'PUBLICADA (22-nov): lista para este cambio' when '{p["HUELLA_CAMPO_NUEVA"]}' then 'CON ESTE CAMBIO' else 'OTRA: deténgase y avise' end as estado
  union all
  select 2, '2 funciones del acta (conjunto)', ({CONJ["acta"]}), case ({CONJ["acta"]}) when '{p["HUELLA_ACTA"]}' then 'PUBLICADA (no cambia con este paquete)' else 'OTRA: deténgase y avise' end
  union all
  select 3, '3 {PREPARAR}', md5(pg_get_functiondef(to_regprocedure('{PREPARAR}'))),
         case md5(pg_get_functiondef(to_regprocedure('{PREPARAR}'))) when '{p["MD5_PREPARAR"]}' then 'PUBLICADA' when '{p["MD5_PREPARAR_NUEVA"]}' then 'CON ESTE CAMBIO' else 'OTRA: deténgase y avise' end
) t order by o;
"""
    def fila(n, k, cond): return f"  select {n} as o, {lit(k)} as k, case when {cond} then 'OK' else 'FALLA' end as estado"
    filas = [
        fila(1, "1 preparar_subida es la de este cambio", f"md5(pg_get_functiondef(to_regprocedure('{PREPARAR}'))) = '{p['MD5_PREPARAR_NUEVA']}'"),
        fila(2, "2 la huella de campo es la de este cambio", f"({CONJ['campo']}) = '{p['HUELLA_CAMPO_NUEVA']}'"),
        fila(3, "3 la huella del acta no cambió (111506c6…)", f"({CONJ['acta']}) = '{p['HUELLA_ACTA']}'"),
        fila(4, "4 Investigación: id 35, activa, sin resultado, fotos de 0 a 6, contrato si",
             "exists (select 1 from campo.tipos_reporte where codigo = 'investigacion_ubicacion' and id = 35 and activo and not genera_resultado and fotos_min = 0 and fotos_max = 6 and requiere_contrato = 'si')"),
        fila(5, "5 Investigación: campos como decidió David (4 nuevos, 4 desactivados, dirección obligatoria)", f"({INV_CAMPOS_Q}) = {lit(p['INV_CAMPOS_NUEVA'])}"),
        fila(6, "6 Investigación: las 3 fotos opcionales y sin soporte", f"({INV_FOTOS_Q}) = {lit(p['INV_FOTOS_NUEVA'])}"),
        fila(7, "7 preparar_subida sigue solo para service_role",
             f"has_function_privilege('service_role', '{PREPARAR}', 'execute') and not has_function_privilege('anon', '{PREPARAR}', 'execute') and not has_function_privilege('authenticated', '{PREPARAR}', 'execute')"),
        fila(8, "8 las 4 funciones de permisos vivas no cambiaron", p["PERMISOS_IGUALES"]),
        fila(9, "9 ninguna función de campo con DELETE o UPDATE sin WHERE", SINWHERE + " = 0"),
        fila(10, "10 redes.f_funciones_sin_where() devuelve cero filas", "(select count(*) from redes.f_funciones_sin_where()) = 0"),
    ]
    ver = "select o, k, estado from (\n" + "\n  union all\n".join(filas) + "\n) t order by o;\n"
    return {f"migracion_{NOMBRE}_editor.sql": CAB.format(que="MIGRACIÓN") + "begin;\n" + poner(cuerpo(), p) + "\ncommit;\n",
            f"ensayo_en_transaccion_{NOMBRE}_editor.sql": CAB.format(que="ENSAYO (termina en ERROR esperado; no deja nada)") + "begin;\n" + poner(cuerpo(), p) + "\n" + poner(lee("70_pruebas.sql"), p) + "\nrollback;\n",
            f"reversa_{NOMBRE}_editor.sql": CAB.format(que="REVERSA") + "begin;\n" + poner(lee("90_reversa.sql"), p) + "\ncommit;\n",
            f"huellas_solo_lectura_{NOMBRE}_editor.sql": CAB.format(que="HUELLAS (solo lectura; ANTES y DESPUÉS)") + huellas,
            f"verificacion_{NOMBRE}_editor.sql": CAB.format(que=f"VERIFICACIÓN (solo lectura; después de la migración: {len(filas)} de {len(filas)} OK)") + ver}, len(filas)

def main():
    con = rehacer("emdupar_b_inv_gen")
    p = valores(con); con.close()
    salida, n = archivos(p)
    for nombre, t in salida.items():
        assert "on commit drop" not in t.lower(), nombre
        (PAQ / nombre).write_text(t)
        print(f"[OK ] {nombre}  md5 {hashlib.md5(t.encode()).hexdigest()}")
    nuevas = {k: p[k] for k in ("HUELLA_CAMPO_NUEVA", "MD5_PREPARAR_NUEVA")}
    (AQUI / "huellas_locales.json").write_text(json.dumps({"partida": {k: p[k] for k in ("HUELLA_CAMPO", "HUELLA_ACTA", "MD5_PREPARAR", "MD5_CREAR")},
        "permisos": PERMISOS, "inv": {"partida_campos": p["INV_CAMPOS"], "partida_fotos": p["INV_FOTOS"], "nueva_campos": p["INV_CAMPOS_NUEVA"],
        "nueva_fotos": p["INV_FOTOS_NUEVA"], "tras_reversa_campos": p["INV_CAMPOS_TRAS_REVERSA"]}, "nuevas": nuevas, "verificacion": n}, indent=1, ensure_ascii=False))
    print(json.dumps(nuevas, indent=1))

if __name__ == "__main__":
    main()
