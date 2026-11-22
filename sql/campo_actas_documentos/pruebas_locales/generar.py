"""Arma los archivos _editor del paquete (b) Actas: firmas, PDF, actas registradas y derivadas (Comercial 21-nov), desde sql/ y la base local
(pgserver temporal; NUNCA Supabase). La base local es la de base_comercial.py (huellas de campo, acta y salida = producción del 21-nov 17:55) con el paquete (a) aplicado.
Uso: python3 -I generar.py [-h]"""
import sys, re, json, pathlib, importlib.util, hashlib
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent; SQL = PAQ / "sql"
A = PAQ.parent / "campo_personal_cuadrillas"
def cargar(n, r):
    s = importlib.util.spec_from_file_location(n, r); m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
bc = cargar("bc", A / "pruebas_locales/base_comercial.py")
ga = cargar("ga", A / "pruebas_locales/generar.py")
NOMBRE = "campo_actas_documentos"
PROD = {"HUELLA_REDES": "1ba192724c2fddcf321104700829f3cc", "HUELLA_TECNICA": "3e9b0121e2b8beb313fad05de9e50f15"}
CONJ_CAMPO_A = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
                "where (p.pronamespace = 'campo'::regnamespace and p.proname not in ('f_no_borrar_catalogo', 'f_firmas_definitivas', 'f_registro_existe')) "
                "or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_campo\\_%')")
TABLAS = ["campo.formularios_documento", "campo.firmas", "campo.documentos_pdf", "campo.documento_intentos", "campo.derivadas_catalogo", "campo.derivadas", "campo.derivada_eventos", "campo.origen_vinculos"]
lee = lambda n: (SQL / n).read_text()

def estructura_condicional():
    t = lee("10_estructura.sql"); assert "$sql_estructura$" not in t
    return ("-- Si una reversa con datos conservó las tablas, la estructura no se repite (nada se borra; se reutiliza lo conservado).\n"
            "do $estructura$\nbegin\n  if to_regclass('campo.formularios_documento') is null then\n    execute $sql_estructura$\n" + t + "\n$sql_estructura$;\n"
            "  else\n    raise notice 'Las tablas de firmas, PDF y derivadas se conservaron de una reversa: se reutilizan';\n  end if;\nend $estructura$;\n")
def cuerpo(): return "\n".join([lee("05_guardia.sql"), estructura_condicional(), lee("20_funciones.sql"), lee("26_rpc.sql"), lee("40_permisos.sql")])
def poner(t, v):
    for k, x in v.items(): t = t.replace("{{" + k + "}}", x)
    assert "{{" not in t, re.findall(r"\{\{[A-Z_]+\}\}", t); return t
def local_a(t, loc):   # el paquete (a) con las huellas de redes y técnica de esta base
    for v, k in {"1ba192724c2fddcf321104700829f3cc": "HUELLA_REDES", "3e9b0121e2b8beb313fad05de9e50f15": "HUELLA_TECNICA"}.items(): t = t.replace(v, loc[k])
    return t
CAB = "-- COMERCIAL 21-NOV · (b) ACTAS: FIRMAS, PDF, ACTAS REGISTRADAS Y DERIVADAS · {que} (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)\n"

def preparar():
    """Base local con (a) aplicado. Devuelve srv, uri, con y las huellas locales (redes, técnica, campo tras (a))."""
    srv, uri, con = bc.preparar()
    q = lambda x: con.execute(x).fetchone()[0]
    loc = {"HUELLA_REDES": q("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p where p.pronamespace = to_regnamespace('redes') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')"),
           "HUELLA_TECNICA": q(bc.CONJUNTO["campo"].replace("'campo'::regnamespace", "to_regnamespace('tecnica')").replace("geoportal\\_campo\\_%", "geoportal\\_tec\\_%"))}
    loc = {k: (v or "(ninguna)") for k, v in loc.items()}
    con.execute(local_a((A / "migracion_campo_personal_cuadrillas_editor.sql").read_text(), loc))
    loc["HUELLA_CAMPO_A"] = q(CONJ_CAMPO_A)
    return srv, uri, con, loc

def main():
    srv, uri, con, loc = preparar()
    q = lambda x, *a: con.execute(x, *a).fetchone()[0]
    prod = {**PROD, "HUELLA_CAMPO_A": loc["HUELLA_CAMPO_A"], "SIN_WHERE_CAMPO": ga.SINWHERE}   # la de campo tras (a) es determinista: la base local antes de (a) = producción
    con.execute(poner(cuerpo(), {**loc, "SIN_WHERE_CAMPO": ga.SINWHERE}))
    nuevas = {r[0]: r[1] for r in con.execute("select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)) from pg_proc p where (p.pronamespace = 'campo'::regnamespace and p.proname in "
              "('f_formulario_de_reporte', 'f_documento_de', 'f_registro_existe', 'f_firmas_al_registrar_reporte', 'f_derivadas_al_registrar', 'f_firmas_al_registrar_acta', 'f_firmas_definitivas', "
              "'f_derivada_estado', 'f_autorizar_documento', 'f_autorizar_registradas', 'f_nombre_pdf', 'f_registradas', 'f_registradas_filtradas', 'f_derivada_json')) "
              "or (p.pronamespace = 'public'::regnamespace and p.proname in ('geoportal_campo_documentos_catalogo', 'geoportal_campo_firma_guardar', 'geoportal_campo_pdf_datos', 'geoportal_campo_pdf_registrar', "
              "'geoportal_campo_pdf_fallo', 'geoportal_campo_pdf_obtener', 'geoportal_campo_actas_registradas', 'geoportal_campo_actas_registradas_descarga', 'geoportal_campo_derivadas_abiertas', "
              "'geoportal_campo_derivada_atender', 'geoportal_campo_derivada_cerrar', 'geoportal_campo_derivadas', 'geoportal_campo_actas_abiertas', 'geoportal_campo_origen_vincular')) order by 1").fetchall()}
    con.close(); srv.cleanup()
    assert len(nuevas) == 28, len(nuevas)
    vals = lambda d: ", ".join(f"('{k}', '{v}')" for k, v in d.items())
    huellas = f"""-- Antes: 0 y 1 «PUBLICADA»; 2 «(a) PUBLICADO»; 3 «PUBLICADA»; 4 «NO EXISTE»; 5 «NO EXISTEN». Después: 0, 1 y 3 igual; 2 cambia (anótela); 4 «NUEVA»; 5 «EXISTEN».
select o, k, v, estado from (
  select 0 as o, '0 funciones de redes (conjunto)' as k, (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p where p.pronamespace = to_regnamespace('redes') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')) as v,
         'debe ser {PROD["HUELLA_REDES"]} (PUBLICADA)'::text as estado
  union all
  select 1, '1 funciones de técnica (conjunto)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = to_regnamespace('tecnica') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_tec\\_%')), 'debe ser {PROD["HUELLA_TECNICA"]} (PUBLICADA)'
  union all
  select 2, '2 funciones de campo (conjunto, sin las que protegen datos conservados)', ({CONJ_CAMPO_A}), case ({CONJ_CAMPO_A}) when '{loc["HUELLA_CAMPO_A"]}' then '(a) PUBLICADO: lista para (b)' else 'cambió: si (b) ya está aplicado, anótela; si no, deténgase' end
  union all
  select 3, '3 funciones del acta (conjunto)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_acta\\_%')),
         case (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_acta\\_%'))
              when '111506c690249ad3b56ebf572566434c' then 'PUBLICADA (no cambia con este paquete)' else 'OTRA: deténgase y avise' end
  union all
  select 4, '4 ' || n.f || ' (nueva)', case when to_regprocedure(n.f) is not null then md5(pg_get_functiondef(to_regprocedure(n.f))) end,
         case when to_regprocedure(n.f) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.f))) = n.m then 'NUEVA (aplicada)' else 'OTRA: deténgase y avise' end
    from (values {vals(nuevas)}) n(f, m)
  union all
  select 5, '5 tablas nuevas (8)', null, case (select count(*) from pg_class where oid in ({", ".join(f"to_regclass('{t}')" for t in TABLAS)}))
         when 0 then 'NO EXISTEN (sin aplicar)' when 8 then 'EXISTEN (aplicado o conservadas de una reversa)' else 'A MEDIAS: deténgase y avise' end
  union all
  select 6, '6 INFO actas · revisiones o instalaciones · bucket actas-pdf', null, (select count(*) from acta.actas) || ' · ' || (select count(*) from campo.reportes r join campo.tipos_reporte t on t.id = r.tipo_id
         where t.codigo in ('revision_previa', 'revision_pqr', 'instalacion_medidor', 'instalacion_acometida')) || ' · ' || (select count(*) from storage.buckets where id = 'actas-pdf')
) t order by o, k;
"""
    def fila(n, k, cond): return f"  select {n} as o, '{k}' as k, case when {cond} then 'OK' else 'FALLA' end as estado"
    ver = "select o, k, estado from (\n" + "\n  union all\n".join([
        fila(1, f"1 las {len(nuevas)} funciones nuevas existen con su md5", " and ".join(f"md5(pg_get_functiondef(to_regprocedure('{f}'))) is not distinct from '{m}'" for f, m in nuevas.items())),
        fila(2, "2 las 8 tablas nuevas, con RLS", "(select count(*) from pg_class where relrowsecurity and oid in (" + ", ".join(f"to_regclass('{t}')" for t in TABLAS) + ")) = 8"),
        fila(3, "3 los 9 formularios con PDF y la firma del operario obligatoria", "(select count(*) from campo.formularios_documento where activo and lleva_pdf and firma_operario = 'obligatoria' and firma_usuario = 'opcional' and firma_testigo = 'opcional') = 9"),
        fila(4, "4 disparadores: firmas al registrar (campo y acta), derivadas, firmas definitivas", "(select count(*) from pg_trigger where not tgisinternal and tgname in ('t_firmas_al_registrar', 't_derivadas_al_registrar', 't_firmas_definitivas', 't_firmas_no_vaciar')) = 5"),
        fila(5, "5 da_lugar y da_lugar_otra activos en los 4 REV", "(select count(*) from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id where c.codigo in ('da_lugar', 'da_lugar_otra') and c.activo and t.codigo in ('revision_previa', 'revision_pqr', 'instalacion_medidor', 'instalacion_acometida')) = 8"),
        fila(6, "6 bucket actas-pdf privado, solo PDF, 25 MB", "exists (select 1 from storage.buckets where id = 'actas-pdf' and not public and file_size_limit = 26214400 and allowed_mime_types = array['application/pdf'])"),
        fila(7, "7 permisos: las 14 RPC solo para service_role; tablas sin permisos", "(select bool_and(has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')) from pg_proc p where p.oid in ("
             + ", ".join(f"to_regprocedure('{f}')" for f in nuevas if f.startswith("geoportal_")) + ")) and (select bool_and(not has_table_privilege(r, t, 'select')) from unnest(array[" + ", ".join(f"'{t}'" for t in TABLAS) + "]) t, unnest(array['anon', 'authenticated', 'service_role']) r)"),
        fila(8, "8 la huella del acta no cambió (111506c6…)", "(select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_acta\\_%')) = '111506c690249ad3b56ebf572566434c'"),
        fila(9, "9 ninguna función de campo con DELETE o UPDATE sin WHERE", ga.SINWHERE + " = 0"),
        fila(10, "10 redes.f_funciones_sin_where() devuelve cero filas", "(select count(*) from redes.f_funciones_sin_where()) = 0"),
    ]) + "\n) t order by o;\n"
    escribir = lambda n, t: (PAQ / n).write_text(t)
    escribir(f"migracion_{NOMBRE}_editor.sql", CAB.format(que="MIGRACIÓN (después de la de Personal y cuadrillas)") + "begin;\n" + poner(cuerpo(), prod) + "\ncommit;\n")
    escribir(f"ensayo_en_transaccion_{NOMBRE}_editor.sql", CAB.format(que="ENSAYO (termina en ERROR esperado; no deja nada)") + "begin;\n" + poner(cuerpo(), prod) + "\n" + poner(lee("70_pruebas.sql"), prod) + "\nrollback;\n")
    escribir(f"reversa_{NOMBRE}_editor.sql", CAB.format(que="REVERSA") + "begin;\n" + lee("90_reversa.sql") + "\ncommit;\n")
    escribir(f"huellas_solo_lectura_{NOMBRE}_editor.sql", CAB.format(que="HUELLAS (solo lectura; ANTES y DESPUÉS)") + huellas)
    escribir(f"verificacion_{NOMBRE}_editor.sql", CAB.format(que="VERIFICACIÓN (solo lectura; después de la migración: 10 de 10 OK)") + ver)
    (AQUI / "huellas_locales.json").write_text(json.dumps({"locales": loc, "nuevas": nuevas}, indent=1, ensure_ascii=False))
    for n in sorted(PAQ.glob("*_editor.sql")): print(f"[OK ] {n.name}  md5 {hashlib.md5(n.read_bytes()).hexdigest()}")

if __name__ == "__main__":
    main()
