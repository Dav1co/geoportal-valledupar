"""Base local de Comercial (21-nov) en un PostgreSQL TEMPORAL (pgserver), NUNCA en Supabase.
Cadena: la de Análisis de contrato (campo A … constancias, pasada 14-nov, permisos de Aseo, dobles de bi y hechos) + Análisis de contrato + base mínima de Técnica
y su Corte 1 + Corte 8 (reportes compartidos) + lo del Corte 14 que toca campo (CHECK de personal_eventos.formulario y f_formularios_personal).
Comprueba que las huellas locales son las de producción del 21-nov 17:55 (HUELLAS_PARTIDA_21nov_1755.md).
Uso: python3 -I base_comercial.py [-h]      (solo arma la base, compara las huellas y la borra)"""
import sys, re, pathlib, importlib.util
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
H = pathlib.Path.home()
CAMPO = H / "geoportal-consultas/campo"; TEC = H / "geoportal-consultas/tecnica"
C8 = H / "geoportal-emdupar/sql/campo_corte8"; C14 = H / "geoportal-emdupar/sql/redes_corte14"
def cargar(n, r):
    s = importlib.util.spec_from_file_location(n, r); m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
an = cargar("an", CAMPO / "paquete_analisis_contrato/pruebas_locales/correr_local_analisis.py")

PRODUCCION = {   # 21-nov 17:55, corridas en producción (solo lectura)
  "conjunto:campo": "cf40d2a279c385d17a6cc5da2aac3fa9", "conjunto:acta": "111506c690249ad3b56ebf572566434c", "conjunto:salida": "4edfed3308540fe84d287c13e5dc2027",
  "campo.f_formularios_personal()": "283a63c1ee3fad9e5956a65f8a4644b6",
  "campo.f_validar_datos(bigint,jsonb,boolean)": "f3d09600df18aa558e5bc046d6934f70",
  "public.geoportal_acta_listar(text,jsonb,text)": "790b6193d883e5dab3ae5dcfadf48ed6",
  "public.geoportal_acta_mis_actas(text,text)": "b9d4995abae5a8d2273b8f3e5e82d931",
  "public.geoportal_acta_obtener(text,uuid,text)": "a63afe334a93b4f18e26d68e820f9cc1",
  "public.geoportal_campo_historial_personal(text,jsonb,text)": "e82377f5de26a2dcc1a007403889ba48",
  "public.geoportal_campo_personal(text,jsonb,text)": "f8a83b02da97e8f6a729767f57a394c4",
  "public.geoportal_campo_personal_cambiar(text,text,text,text,text,text,text)": "c0302a7b45307215d8f780d8c78cd396",
}
CONJUNTO = {
  "campo": "select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_campo\\_%')",
  "acta": "select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = 'acta'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_acta\\_%')",
  "salida": "select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.proname, p.oid::regprocedure::text)) from pg_proc p where p.pronamespace = to_regnamespace('salida')",
}

def huellas(con):
    h = {f"conjunto:{k}": con.execute(v).fetchone()[0] for k, v in CONJUNTO.items()}
    for f in PRODUCCION:
        if not f.startswith("conjunto:"): h[f] = con.execute("select md5(pg_get_functiondef(to_regprocedure(%s)))", (f,)).fetchone()[0]
    return h

def preparar():
    srv, uri, con, q = an.base()
    con.execute((CAMPO / "paquete_analisis_contrato/migracion_analisis_contrato_editor.sql").read_text())
    con.execute((C8 / "pruebas_locales/base_tecnica_minima.sql").read_text())
    con.execute((TEC / "corte1_paso_a/migracion_corte1_completa.sql").read_text())
    t = (C8 / "pruebas_locales/base_campo.py").read_text()
    con.execute(re.search(r'con\.execute\("""\n(.*?)"""\)', t, re.S).group(1))     # los ajustes «como en producción» del Corte 8 (vista materializada, redes.v_reportes_comercial, topes)
    con.execute((C8 / "migracion_tecnica_corte8_editor.sql").read_text())
    r = (C14 / "sql/25_reemplazos.sql").read_text()
    con.execute(re.search(r"CREATE OR REPLACE FUNCTION campo\.f_formularios_personal\(\).*?\$function\$;", r, re.S).group(0))
    con.execute("alter table campo.personal_eventos drop constraint personal_eventos_formulario_check;"
                "alter table campo.personal_eventos add constraint personal_eventos_formulario_check check (formulario is null or formulario ~ '^(reporte_general|acta|activo_campo|tipo:[a-z][a-z0-9_]{1,59})$');")
    # como en producción: campo.f_grupos_cercanos es la del Paso A con PostGIS (la cadena local la sustituye porque aquí no hay PostGIS). Se crea con el texto
    # publicado y sin validar el cuerpo (no se llama en estas pruebas), para que el conjunto de campo sea el de producción (cf40d2a2…; MD5_CAMPO_PRODUCCION_21nov.md).
    f30 = (CAMPO / "paquete_campo_base/sql/30_funciones_internas.sql").read_text()
    gc = re.search(r"create function campo\.f_grupos_cercanos\(p_eps_m numeric, p_ids uuid\[\]\).*?\n\$\$;", f30, re.S).group(0)
    con.execute("set check_function_bodies = off; " + gc.replace("create function", "create or replace function", 1) + " reset check_function_bodies;")
    # como en producción: redes.f_funciones_sin_where (Corte 6c), la que el ensayo y la verificación exigen en cero
    r6 = (H / "geoportal-emdupar/sql/redes_corte6c/sql/26_rpc.sql").read_text()
    con.execute(re.search(r"create function redes\.f_funciones_sin_where\(\).*?\$\$;", r6, re.S).group(0))
    return srv, uri, con

if __name__ == "__main__":
    srv, uri, con = preparar(); h = huellas(con); bien = 0
    for k, v in PRODUCCION.items():
        ok = h[k] == v; bien += ok; print(f"[{'OK ' if ok else 'MAL'}] {k} local={h[k]} producción={v}")
    print(f"RESULTADO: {bien} de {len(PRODUCCION)} huellas locales iguales a las de producción")
    con.close(); srv.cleanup()
