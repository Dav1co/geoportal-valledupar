"""Arma los archivos _editor del paquete (a) Personal y cuadrillas de Comercial (21-nov) desde sql/ y la base local (pgserver temporal; NUNCA Supabase).
- migración: guardia + estructura (se salta si una reversa con datos conservó las tablas) + funciones + reemplazos + RPC + permisos.
- ensayo: lo mismo + las pruebas; termina SIEMPRE en ERROR (todo se deshace).
- reversa: con el texto publicado de las dos funciones reemplazadas, sacado de la base local (sus md5 son las de producción: base_comercial.py lo comprueba).
- huellas y verificación: con las md5 nuevas calculadas en la base local tras aplicar la migración.
Uso: python3 -I generar.py [-h]"""
import sys, re, json, pathlib, importlib.util, hashlib
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent
PAQ = AQUI.parent; SQL = PAQ / "sql"
s = importlib.util.spec_from_file_location("bc", AQUI / "base_comercial.py"); bc = importlib.util.module_from_spec(s); s.loader.exec_module(bc)
NOMBRE = "campo_personal_cuadrillas"
PROD = {"HUELLA_REDES": "1ba192724c2fddcf321104700829f3cc", "HUELLA_TECNICA": "3e9b0121e2b8beb313fad05de9e50f15", "HUELLA_CAMPO": "cf40d2a279c385d17a6cc5da2aac3fa9"}
REEMPLAZADAS = {"public.geoportal_campo_personal(text,jsonb,text)": "f8a83b02da97e8f6a729767f57a394c4",
                "public.geoportal_campo_historial_personal(text,jsonb,text)": "e82377f5de26a2dcc1a007403889ba48"}
SIN_TOCAR = {"public.geoportal_campo_personal_cambiar(text,text,text,text,text,text,text)": "c0302a7b45307215d8f780d8c78cd396",
             "campo.f_formularios_personal()": "283a63c1ee3fad9e5956a65f8a4644b6", "campo.f_formularios_asignados(text)": None, "campo.f_cargo_vigente(text)": None}
NUEVAS = ["public.geoportal_campo_personal_fijar(text,text,text,jsonb,text)", "public.geoportal_campo_cuadrillas(text,jsonb,text)", "public.geoportal_campo_cuadrilla_cambiar(text,jsonb,text)",
          "public.geoportal_campo_catalogos(text,text)", "public.geoportal_campo_catalogo_cambiar(text,jsonb,text)", "public.geoportal_campo_personal_actividad(text,text,text)",
          "campo.f_persona_comercial(text)", "campo.f_area_vigente(text)", "campo.f_cuadrilla_vigente(text)", "campo.f_actividades_propias(text)", "campo.f_cuadrilla_actividades(bigint)",
          "campo.f_miembros_cuadrillas()", "campo.f_actividades_persona(text)", "campo.f_quien_puede(text)", "campo.f_codigo_desde_nombre(text)", "campo.f_motivo_personal(text,boolean)",
          "campo.f_no_borrar_catalogo()"]
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
TABLAS = ["campo.areas_comercial", "campo.actividades", "campo.catalogo_eventos", "campo.cuadrillas", "campo.cuadrilla_eventos"]
lee = lambda n: (SQL / n).read_text()

def estructura_condicional():
    t = lee("10_estructura.sql")
    assert "$estructura$" not in t
    return ("-- Si una reversa con datos conservó las tablas, la estructura no se repite (nada se borra; se reutiliza lo conservado).\n"
            "do $estructura$\nbegin\n  if to_regclass('campo.cuadrillas') is null then\n    execute $sql_estructura$\n" + t + "\n$sql_estructura$;\n"
            "  else\n    raise notice 'Las tablas de Personal y cuadrillas se conservaron de una reversa: se reutilizan';\n  end if;\nend $estructura$;\n")

def cuerpo():
    return "\n".join([lee("05_guardia.sql"), estructura_condicional(), lee("20_funciones.sql"), lee("25_reemplazos.sql"), lee("26_rpc.sql"), lee("40_permisos.sql")])

def poner(t, valores):
    for k, v in valores.items(): t = t.replace("{{" + k + "}}", v)
    assert "{{" not in t, re.findall(r"\{\{[A-Z_]+\}\}", t)
    return t

CAB = "-- COMERCIAL 21-NOV · (a) PERSONAL Y CUADRILLAS · {que} (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)\n"

def main():
    srv, uri, con = bc.preparar()
    q = lambda x, *a: con.execute(x, *a).fetchone()[0]
    for f, m in {**REEMPLAZADAS, **{k: v for k, v in SIN_TOCAR.items() if v}}.items():
        assert q("select md5(pg_get_functiondef(to_regprocedure(%s)))", (f,)) == m, f"{f} local no es la de producción"
    respaldo = {f: q("select pg_get_functiondef(to_regprocedure(%s))", (f,)) for f in REEMPLAZADAS}
    sin_tocar_md5 = {f: q("select md5(pg_get_functiondef(to_regprocedure(%s)))", (f,)) for f in SIN_TOCAR}
    local = {"HUELLA_REDES": q("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p where p.pronamespace = to_regnamespace('redes') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')"),
             "HUELLA_TECNICA": q(bc.CONJUNTO["campo"].replace("'campo'::regnamespace", "to_regnamespace('tecnica')").replace("geoportal\\_campo\\_%", "geoportal\\_tec\\_%")),
             "HUELLA_CAMPO": q(bc.CONJUNTO["campo"])}
    local = {k: (v or "(ninguna)") for k, v in local.items()}
    migr = "begin;\n" + poner(cuerpo(), PROD) + "\ncommit;\n"
    con.execute(poner(cuerpo(), local))
    nuevas = {f: q("select md5(pg_get_functiondef(to_regprocedure(%s)))", (f,)) for f in NUEVAS + list(REEMPLAZADAS)}
    con.close(); srv.cleanup()

    rev = lee("90_reversa.sql").replace("{{RESPALDO_PERSONAL}}", respaldo["public.geoportal_campo_personal(text,jsonb,text)"].rstrip() + ";")
    rev = rev.replace("{{RESPALDO_HISTORIAL}}", respaldo["public.geoportal_campo_historial_personal(text,jsonb,text)"].rstrip() + ";")
    vals = lambda d: ", ".join(f"('{k}', '{v}')" for k, v in d.items())
    huellas = f"""select o, k, v, estado from (
  select 0 as o, '0 funciones de redes (conjunto)' as k,
         (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p where p.pronamespace = to_regnamespace('redes') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')) as v,
         case (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p where p.pronamespace = to_regnamespace('redes') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')) when '{PROD["HUELLA_REDES"]}' then 'PUBLICADA (21-nov)' else 'OTRA: deténgase y avise' end as estado
  union all
  select 1, '1 funciones de técnica (conjunto)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = to_regnamespace('tecnica') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_tec\\_%')), 'debe ser {PROD["HUELLA_TECNICA"]} (PUBLICADA)'
  union all
  select 2, '2 funciones de campo (conjunto, sin f_no_borrar_catalogo)', (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where (p.pronamespace = 'campo'::regnamespace and p.proname <> 'f_no_borrar_catalogo') or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_campo\\_%')), 'antes debe ser {PROD["HUELLA_CAMPO"]}; después, anótela'
  union all
  select 3, '3 ' || a.f || ' (se reemplaza)', md5(pg_get_functiondef(to_regprocedure(a.f))),
         case md5(pg_get_functiondef(to_regprocedure(a.f))) when a.m then 'LA PUBLICADA' when n.m then 'REEMPLAZADA (aplicado)' else 'OTRA: deténgase y avise' end
    from (values {vals(REEMPLAZADAS)}) a(f, m) join (values {vals({f: nuevas[f] for f in REEMPLAZADAS})}) n(f, m) on n.f = a.f
  union all
  select 4, '4 ' || n.f || ' (nueva)', case when to_regprocedure(n.f) is not null then md5(pg_get_functiondef(to_regprocedure(n.f))) end,
         case when to_regprocedure(n.f) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.f))) = n.m then 'NUEVA (aplicada)' else 'OTRA: deténgase y avise' end
    from (values {vals({f: nuevas[f] for f in NUEVAS})}) n(f, m)
  union all
  select 5, '5 ' || a.f || ' (no se toca)', md5(pg_get_functiondef(to_regprocedure(a.f))), case when md5(pg_get_functiondef(to_regprocedure(a.f))) = a.m then 'SIN CAMBIO' else 'OTRA: deténgase y avise' end
    from (values {vals(sin_tocar_md5)}) a(f, m)
  union all
  select 6, '6 tablas nuevas (5)', null, case (select count(*) from pg_class where oid in ({", ".join(f"to_regclass('{t}')" for t in TABLAS)}))
         when 0 then 'NO EXISTEN (sin aplicar)' when 5 then 'EXISTEN (aplicado o conservadas de una reversa)' else 'A MEDIAS: deténgase y avise' end
  union all
  select 7, '7 INFO personas de Comercial · eventos de Personal · cuadrillas', null,
         (select count(*) from public.geoportal_lista_blanca lb where lb.activo and lb.rol <> 'admin' and (coalesce(lb.ver_campo, false) or coalesce(lb.ver_dashboard_campo, false) or coalesce(lb.ver_acta, false) or coalesce(lb.ver_dashboard_acta, false)))
         || ' · ' || (select count(*) from campo.personal_eventos) || ' · ' || coalesce((select count(*) from pg_class where oid = to_regclass('campo.cuadrillas'))::text, '0')
) t order by o, k;
"""
    def fila(n, k, cond): return f"  select {n} as o, '{k}' as k, case when {cond} then 'OK' else 'FALLA' end as estado"
    ver = "select o, k, estado from (\n" + "\n  union all\n".join([
        fila(1, "1 las 17 funciones nuevas existen con su md5", " and ".join(f"md5(pg_get_functiondef(to_regprocedure('{f}'))) is not distinct from '{nuevas[f]}'" for f in NUEVAS)),
        fila(2, "2 las 2 reemplazadas tienen el texto nuevo", " and ".join(f"md5(pg_get_functiondef(to_regprocedure('{f}'))) = '{nuevas[f]}'" for f in REEMPLAZADAS)),
        fila(3, "3 personal_cambiar (la de la Edge publicada) y f_formularios_personal sin cambio", " and ".join(f"md5(pg_get_functiondef(to_regprocedure('{f}'))) = '{m}'" for f, m in SIN_TOCAR.items() if m)),
        fila(4, "4 las 5 tablas nuevas existen, con RLS y con su protección", "(select count(*) from pg_class where relrowsecurity and oid in (" + ", ".join(f"to_regclass('{t}')" for t in TABLAS) + ")) = 5"
             " and (select count(*) from pg_trigger where not tgisinternal and tgrelid in (" + ", ".join(f"to_regclass('{t}')" for t in TABLAS) + ")) = 10"),
        fila(5, "5 semilla: las 4 áreas de D2 y las 10 actividades de D4", "(select count(*) from campo.areas_comercial where codigo in ('facturacion', 'cartera_scrr', 'perdidas', 'pqr_atencion')) = 4"
             " and (select count(*) from campo.actividades where codigo in ('suspension', 'corte', 'reconexion', 'lectura', 'reparto', 'revision_previa', 'revision_pqr', 'instalacion_medidor', 'instalacion_acometida', 'posible_perdida')) = 10"),
        fila(6, "6 personal_eventos: columna valor y los 7 tipos", "exists (select 1 from pg_attribute where attrelid = 'campo.personal_eventos'::regclass and attname = 'valor' and not attisdropped)"
             " and pg_get_constraintdef((select oid from pg_constraint where conrelid = 'campo.personal_eventos'::regclass and conname = 'personal_eventos_tipo_evento_check')) like '%quitar_actividad%'"),
        fila(7, "7 permisos: las 6 RPC solo para service_role; tablas sin permisos", "(select bool_and(has_function_privilege('service_role', f, 'execute') and not has_function_privilege('anon', f, 'execute') and not has_function_privilege('authenticated', f, 'execute')) from unnest(array["
             + ", ".join(f"'{f}'" for f in NUEVAS[:6]) + "]) f) and (select bool_and(not has_table_privilege(r, t, 'select')) from unnest(array[" + ", ".join(f"'{t}'" for t in TABLAS) + "]) t, unnest(array['anon', 'authenticated', 'service_role']) r)"),
        fila(8, "8 ninguna función de campo con DELETE o UPDATE sin WHERE (la regla de redes.f_funciones_sin_where aplicada a campo)", SINWHERE + " = 0"),
        fila(9, "9 redes.f_funciones_sin_where() devuelve cero filas", "(select count(*) from redes.f_funciones_sin_where()) = 0"),
    ]) + "\n) t order by o;\n"
    escribir = lambda n, t: (PAQ / n).write_text(t)
    escribir(f"migracion_{NOMBRE}_editor.sql", CAB.format(que="MIGRACIÓN") + migr)
    escribir(f"ensayo_en_transaccion_{NOMBRE}_editor.sql", CAB.format(que="ENSAYO (termina en ERROR esperado; no deja nada)") + "begin;\n" + poner(cuerpo(), PROD) + "\n" + lee("70_pruebas.sql") + "\nrollback;\n")
    escribir(f"reversa_{NOMBRE}_editor.sql", CAB.format(que="REVERSA") + "begin;\n" + rev + "\ncommit;\n")
    escribir(f"huellas_solo_lectura_{NOMBRE}_editor.sql", CAB.format(que="HUELLAS (solo lectura; correr ANTES y DESPUÉS)") + "-- Antes: 0, 1 y 2 «PUBLICADA»; 3 «LA PUBLICADA»; 4 «NO EXISTE»; 5 «SIN CAMBIO»; 6 «NO EXISTEN». Después: 0 y 1 «PUBLICADA»; 2 cambia (anótela); 3 «REEMPLAZADA»; 4 «NUEVA»; 5 «SIN CAMBIO»; 6 «EXISTEN».\n" + huellas)
    escribir(f"verificacion_{NOMBRE}_editor.sql", CAB.format(que="VERIFICACIÓN (solo lectura; después de la migración: 9 de 9 OK)") + ver)
    (AQUI / "huellas_locales.json").write_text(json.dumps({"locales": local, "nuevas": nuevas}, indent=1, ensure_ascii=False))
    for n in sorted(PAQ.glob("*_editor.sql")): print(f"[OK ] {n.name}  md5 {hashlib.md5(n.read_bytes()).hexdigest()}")

if __name__ == "__main__":
    main()
