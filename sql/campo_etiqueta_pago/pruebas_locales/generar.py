#!/usr/bin/env python3
"""[Code A] Genera los _editor del paquete «Etiqueta del último pago» (27-nov) desde ../sql y un doble local de producción. NUNCA Supabase.
El doble: el de «Consultar direcciones» (generar.rehacer de campo_consultar_direcciones = huella de campo 66496328…) + su migración PUBLICADA
= huella de campo c476f14d…, la de producción hoy. La función nueva sale del texto publicado de geoportal_campo_analisis_contrato con UNA sola línea cambiada
(f.ultimo_pago - 'corte' || … → f.ultimo_pago || …); la reversa lleva el texto publicado.
La huella de campo se ordena con collate "C" (en producción la collation de la base no es la del clúster local).
Uso: python3 -I generar.py [-h]"""
import sys, json, hashlib, pathlib, importlib.util
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent; SQL = PAQ / "sql"
DIRS = pathlib.Path.home() / "geoportal-emdupar/sql/campo_consultar_direcciones"
_s = importlib.util.spec_from_file_location("gnd", DIRS / "pruebas_locales/generar.py"); gnd = importlib.util.module_from_spec(_s); _s.loader.exec_module(gnd)
NOMBRE = "campo_etiqueta_pago"
lit = gnd.lit; poner = gnd.poner; SINWHERE = gnd.SINWHERE; PERMISOS = gnd.PERMISOS
HUELLA = dict(gnd.HUELLA)
HUELLA["campo"] = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text collate \"C\", p.proname, p.oid::regprocedure::text collate \"C\")) "
                   "from pg_proc p where p.pronamespace = 'campo'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_campo\\_%')")
PUBLICADA = {"campo": "c476f14d495ea7bdf6c3f42101e9a583", "acta": "111506c690249ad3b56ebf572566434c"}
TECNICA_PRODUCCION = gnd.TECNICA_PRODUCCION
FUNCION = "public.geoportal_campo_analisis_contrato(text,text,text)"
MD5_PUBLICADA = "6ed039f4949ca17daeae67b0a9e249d7"            # verificación publicada de Consultar direcciones (fila 4)
VIEJA_LINEA = "f.ultimo_pago - 'corte' || jsonb_build_object('dias'"
NUEVA_LINEA = "f.ultimo_pago || jsonb_build_object('dias'"
PARTES = ["05_guardia.sql", "30_cambios.sql"]
lee = lambda n: (SQL / n).read_text()
CAB = "-- [Code A] ETIQUETA DEL ÚLTIMO PAGO (27-nov) · {que} (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)\n"
def cuerpo(): return "\n".join(lee(n) for n in PARTES)
def md5f(con, f): return con.execute("select md5(pg_get_functiondef(to_regprocedure(%s)))", (f,)).fetchone()[0]
def defn(con, f): return con.execute("select pg_get_functiondef(to_regprocedure(%s))", (f,)).fetchone()[0].rstrip() + ";"
def a_local(texto, hl=None): return gnd.a_local(texto, None)   # solo la huella de Técnica del doble

def rehacer(db):
    con = gnd.rehacer(db)
    con.execute(gnd.a_local((DIRS / "migracion_campo_consultar_direcciones_editor.sql").read_text(), None))
    h = con.execute(HUELLA["campo"]).fetchone()[0]
    if h != PUBLICADA["campo"]: raise SystemExit(f"El doble no tiene la huella de campo publicada (collate C): {h}")
    h2 = con.execute(gnd.HUELLA["campo"]).fetchone()[0]
    if h2 != PUBLICADA["campo"]: raise SystemExit(f"La huella sin collate no coincide: {h2}")
    if md5f(con, FUNCION) != MD5_PUBLICADA: raise SystemExit("La función publicada del doble no es la de producción")
    return con

def valores(con):
    vieja = defn(con, FUNCION)
    assert vieja.count(VIEJA_LINEA) == 1, "la línea vieja no está una sola vez"
    nueva = vieja.replace(VIEJA_LINEA, NUEVA_LINEA)
    p = {"HUELLA_CAMPO": PUBLICADA["campo"], "HUELLA_ACTA": PUBLICADA["acta"], "HUELLA_TECNICA": TECNICA_PRODUCCION,
         "HUELLA_CAMPO_Q": HUELLA["campo"], "HUELLA_ACTA_Q": HUELLA["acta"], "HUELLA_TECNICA_Q": HUELLA["tecnica"], "SIN_WHERE_CAMPO": SINWHERE,
         "FUNCION": FUNCION, "MD5_VIEJA": MD5_PUBLICADA, "FUNCION_NUEVA": nueva, "FUNCION_VIEJA": vieja, "HUELLA_CAMPO_NUEVA": "x", "MD5_NUEVA": "x"}
    with con.transaction(force_rollback=True):
        con.execute(a_local(poner(cuerpo(), p)))
        p["HUELLA_CAMPO_NUEVA"] = con.execute(HUELLA["campo"]).fetchone()[0]; p["MD5_NUEVA"] = md5f(con, FUNCION)
        assert con.execute(HUELLA["acta"]).fetchone()[0] == p["HUELLA_ACTA"]
        con.execute(poner(lee("90_reversa.sql"), p))
        assert con.execute(HUELLA["campo"]).fetchone()[0] == p["HUELLA_CAMPO"], "la reversa no devuelve la huella"
    return p

def archivos(p):
    H = HUELLA
    huellas = f"""-- Solo lectura. ANTES: 1 «PUBLICADA»; 2 y 3 «PUBLICADA». DESPUÉS: 1 «CON ESTE CAMBIO» (anótela); 2 y 3 igual (este paquete no las cambia).
-- La huella de campo se ordena con collate "C" (mismo valor que la fórmula de los paquetes anteriores en esta base).
select o, k, v, estado from (
  select 1 as o, '1 funciones de campo (conjunto, todas; collate C)' as k, ({H["campo"]}) as v,
         case ({H["campo"]}) when '{p["HUELLA_CAMPO"]}' then 'PUBLICADA (Consultar direcciones): lista para este cambio' when '{p["HUELLA_CAMPO_NUEVA"]}' then 'CON ESTE CAMBIO' else 'OTRA: deténgase y avise' end as estado
  union all
  select 2, '2 funciones del acta (conjunto)', ({H["acta"]}), case ({H["acta"]}) when '{p["HUELLA_ACTA"]}' then 'PUBLICADA (no cambia con este paquete)' else 'OTRA: deténgase y avise' end
  union all
  select 3, '3 funciones de Técnica (conjunto)', ({H["tecnica"]}), case ({H["tecnica"]}) when '{p["HUELLA_TECNICA"]}' then 'PUBLICADA (no cambia con este paquete)' else 'OTRA: deténgase y avise' end
) t order by o;
"""
    def fila(n, k, cond): return f"  select {n} as o, {lit(k)} as k, case when {cond} then 'OK' else 'FALLA' end as estado"
    F = lit(FUNCION)
    filas = [
        fila(1, "1 la huella de campo es la de este cambio", f"({H['campo']}) = '{p['HUELLA_CAMPO_NUEVA']}'"),
        fila(2, "2 la huella del acta no cambió", f"({H['acta']}) = '{p['HUELLA_ACTA']}'"),
        fila(3, "3 la huella de Técnica no cambió", f"({H['tecnica']}) = '{p['HUELLA_TECNICA']}'"),
        fila(4, "4 geoportal_campo_analisis_contrato es la de este cambio y ya no quita el corte del pago",
             f"md5(pg_get_functiondef(to_regprocedure({F}))) = '{p['MD5_NUEVA']}' and position('f.ultimo_pago - ''corte''' in pg_get_functiondef(to_regprocedure({F}))) = 0"),
        fila(5, "5 la RPC sigue solo para service_role y SECURITY DEFINER",
             f"has_function_privilege('service_role', {F}, 'execute') and not has_function_privilege('anon', {F}, 'execute') and not has_function_privilege('authenticated', {F}, 'execute') "
             f"and (select prosecdef from pg_proc where oid = to_regprocedure({F}))"),
        fila(6, "6 las 4 funciones de permisos vivas no cambiaron", " and ".join(f"md5(pg_get_functiondef(to_regprocedure({lit(f)}))) = {lit(m)}" for f, m in PERMISOS.items())),
        fila(7, "7 ninguna función de campo con DELETE o UPDATE sin WHERE", SINWHERE + " = 0"),
        fila(8, "8 redes.f_funciones_sin_where() devuelve cero filas", "(select count(*) from redes.f_funciones_sin_where()) = 0"),
    ]
    ver = "select o, k, estado from (\n" + "\n  union all\n".join(filas) + "\n) t order by o;\n"
    return {f"migracion_{NOMBRE}_editor.sql": CAB.format(que="MIGRACIÓN") + "begin;\n" + poner(cuerpo(), p) + "\ncommit;\n",
            f"ensayo_en_transaccion_{NOMBRE}_editor.sql": CAB.format(que="ENSAYO (termina en ERROR esperado; no deja nada)") + "begin;\n" + poner(lee("70_pruebas.sql"), p) + "\nrollback;\n",
            f"reversa_{NOMBRE}_editor.sql": CAB.format(que="REVERSA") + "begin;\n" + poner(lee("90_reversa.sql"), p) + "\ncommit;\n",
            f"huellas_solo_lectura_{NOMBRE}_editor.sql": CAB.format(que="HUELLAS (solo lectura; ANTES y DESPUÉS)") + huellas,
            f"verificacion_{NOMBRE}_editor.sql": CAB.format(que=f"VERIFICACIÓN (solo lectura; después de la migración: {len(filas)} de {len(filas)} OK)") + ver}, len(filas)

def main():
    con = rehacer("emdupar_a_rf_pagogen")
    p = valores(con); con.close()
    p["CUERPO_MIGRACION"] = poner(cuerpo(), p); p["CUERPO_REVERSA"] = poner(lee("90_reversa.sql"), p)
    salida, n = archivos(p)
    for nombre, t in salida.items():
        assert "on commit drop" not in t.lower(), nombre
        (PAQ / nombre).write_text(t); print(f"[OK ] {nombre}  md5 {hashlib.md5(t.encode()).hexdigest()}")
    (AQUI / "huellas_locales.json").write_text(json.dumps({"partida": {"HUELLA_CAMPO": p["HUELLA_CAMPO"], "MD5_VIEJA": p["MD5_VIEJA"]},
        "nuevas": {"HUELLA_CAMPO_NUEVA": p["HUELLA_CAMPO_NUEVA"], "MD5_NUEVA": p["MD5_NUEVA"]}, "verificacion": n}, indent=1, ensure_ascii=False))
    print(json.dumps({"HUELLA_CAMPO_NUEVA": p["HUELLA_CAMPO_NUEVA"], "MD5_NUEVA": p["MD5_NUEVA"], "verificacion": n}, indent=1))

if __name__ == "__main__":
    main()
