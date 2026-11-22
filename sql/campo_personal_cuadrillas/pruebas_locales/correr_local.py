"""Pruebas locales del paquete (a) Personal y cuadrillas de Comercial (21-nov) en un PostgreSQL TEMPORAL (pgserver), NUNCA en Supabase.
Corre: el ensayo con las huellas de producción (la guardia debe detenerlo: la base local no es producción), el ensayo con las huellas locales (las pruebas),
el ciclo huellas → migración → verificación → repetir (rechazo) → reversa sin datos → migración → datos → reversa con datos (se conservan) → migración encima,
y la guardia ante una función distinta. Escribe ../resultados_locales.txt.
Uso: python3 -I correr_local.py [-h]"""
import sys, re, json, time, pathlib, importlib.util
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent
s = importlib.util.spec_from_file_location("bc", AQUI / "base_comercial.py"); bc = importlib.util.module_from_spec(s); s.loader.exec_module(bc)
N = "campo_personal_cuadrillas"
PROD = {"1ba192724c2fddcf321104700829f3cc": "HUELLA_REDES", "3e9b0121e2b8beb313fad05de9e50f15": "HUELLA_TECNICA", "cf40d2a279c385d17a6cc5da2aac3fa9": "HUELLA_CAMPO"}
LOG = []; TOT = [0, 0]
def out(t=""): print(t); LOG.append(t)
def ok(nombre, cond, det=""):
    TOT[0] += 1; TOT[1] += bool(cond); out(f"{'OK   ' if cond else 'FALLA'} {nombre}" + (f"  → {det}" if det and not cond else ""))
leer = lambda n: (PAQ / n).read_text()
LOCAL = json.loads((AQUI / "huellas_locales.json").read_text())["locales"]
def local(t):   # cambia SOLO las tres huellas de conjunto de producción por las de la base local (lo demás, md5 por función incluidas, queda igual)
    for v, k in PROD.items(): t = t.replace(v, LOCAL[k])
    return t
def correr(con, t):
    try: con.execute(t); return None
    except Exception as e:
        try: con.execute("rollback")
        except Exception: pass
        return "\n".join(l for l in str(e).splitlines() if not l.startswith("CONTEXT"))

def huellas(con):
    return {f"{r[0]}|{r[1]}": r[3] for r in con.execute(local(leer(f"huellas_solo_lectura_{N}_editor.sql"))).fetchall()}
def ver(con):
    return con.execute(leer(f"verificacion_{N}_editor.sql")).fetchall()

def main():
    out("PRUEBAS LOCALES · Comercial 21-nov · (a) Personal y cuadrillas"); out("")
    srv, uri, con = bc.preparar()
    h = bc.huellas(con)
    ok("B.01 la base local tiene las huellas de producción: conjuntos de campo (cf40d2a2…), acta y salida, y las 8 funciones",
       all(h[k] == v for k, v in bc.PRODUCCION.items()), str({k: h[k] for k in bc.PRODUCCION if h[k] != bc.PRODUCCION[k]}))
    out("      (redes y técnica no están completas en esta base: solo esas dos huellas se sustituyen por las locales)")
    e = correr(con, leer(f"ensayo_en_transaccion_{N}_editor.sql"))
    ok("E.01 con las huellas de producción, la guardia detiene el ensayo en esta base (no es producción)", e is not None and "deténgase y avise" in e, (e or "")[:200])
    t0 = time.time(); e = correr(con, local(leer(f"ensayo_en_transaccion_{N}_editor.sql"))); dt = time.time() - t0
    m = re.search(r"RESULTADO: (\d+) de (\d+)", e or "")
    out(e or "[sin error: MAL]")
    ok(f"E.02 el ensayo termina en ERROR esperado con todas sus pruebas correctas ({dt:.1f} s)", m is not None and m.group(1) == m.group(2), (e or "")[:300])
    if m: TOT[0] += int(m.group(2)) - 1; TOT[1] += int(m.group(1)) - (1 if m.group(1) == m.group(2) else 0)
    ok("E.03 el ensayo no dejó nada", con.execute("select to_regclass('campo.cuadrillas') is null and to_regprocedure('public.geoportal_campo_cuadrillas(text,jsonb,text)') is null").fetchone()[0])

    antes = huellas(con)
    ok("C.01 huellas antes: reemplazadas LA PUBLICADA, nuevas NO EXISTE, sin tocar SIN CAMBIO, tablas NO EXISTEN",
       all(v in ("LA PUBLICADA", "NO EXISTE (sin aplicar)", "SIN CAMBIO", "NO EXISTEN (sin aplicar)") for k, v in antes.items() if k[0] in "3456"), str({k: v for k, v in antes.items() if k[0] in "3456"}))
    chk_antes = dict(con.execute("select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid = 'campo.personal_eventos'::regclass").fetchall())
    campo_antes = con.execute(bc.CONJUNTO["campo"]).fetchone()[0]
    e = correr(con, local(leer(f"migracion_{N}_editor.sql"))); ok("C.02 migración", e is None, e)
    v = ver(con); ok(f"C.03 verificación {sum(1 for x in v if x[2] == 'OK')} de {len(v)} OK", all(x[2] == "OK" for x in v) and len(v) == 9, str([x for x in v if x[2] != 'OK']))
    d = huellas(con)
    ok("C.04 huellas después: REEMPLAZADA, NUEVA, SIN CAMBIO, EXISTEN", all(v in ("REEMPLAZADA (aplicado)", "NUEVA (aplicada)", "SIN CAMBIO") or v.startswith("EXISTEN") for k, v in d.items() if k[0] in "3456"),
       str({k: v for k, v in d.items() if k[0] in "3456" and not (v.startswith("REEMPL") or v.startswith("NUEVA") or v == "SIN CAMBIO" or v.startswith("EXISTEN"))}))
    e = correr(con, local(leer(f"migracion_{N}_editor.sql"))); ok("C.05 repetir la migración se rechaza", e is not None and "ya parece aplicado" in e, (e or "")[:150])
    e = correr(con, leer(f"reversa_{N}_editor.sql")); ok("C.06 reversa sin datos", e is None, e)
    ok("C.07 tras la reversa: funciones, CHECK y conjunto de campo como antes; sin tablas ni columna nuevas",
       con.execute(bc.CONJUNTO["campo"]).fetchone()[0] == campo_antes
       and dict(con.execute("select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid = 'campo.personal_eventos'::regclass").fetchall()) == chk_antes
       and con.execute("select to_regclass('campo.cuadrillas') is null and not exists (select 1 from pg_attribute where attrelid = 'campo.personal_eventos'::regclass and attname = 'valor' and not attisdropped)").fetchone()[0])
    ok("C.08 y las huellas vuelven al estado de antes", huellas(con) == antes)
    e = correr(con, leer(f"reversa_{N}_editor.sql")); ok("C.09 repetir la reversa se rechaza", e is not None and "no hay nada que revertir" in e, (e or "")[:150])
    e = correr(con, local(leer(f"migracion_{N}_editor.sql"))); ok("C.10 la migración se vuelve a aplicar después de la reversa", e is None, e)
    con.execute("insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo) values "
                "('ciclo.sup@emdupar.gov.co', 'S', 'consulta', true, 'sin_restriccion', 'todos', false, true, true), ('ciclo.op@emdupar.gov.co', 'O', 'consulta', true, 'sin_restriccion', 'todos', false, true, false)")
    cid = con.execute("select (public.geoportal_campo_cuadrilla_cambiar('ciclo.sup@emdupar.gov.co', '{\"tipo\": \"crear\", \"nombre\": \"Ciclo\"}') ->> 'id')::bigint").fetchone()[0]
    con.execute(f"select public.geoportal_campo_personal_fijar('ciclo.sup@emdupar.gov.co', 'ciclo.op@emdupar.gov.co', 'fijar_cuadrilla', '{{\"cuadrilla_id\": {cid}}}')")
    e = correr(con, leer(f"reversa_{N}_editor.sql")); ok("C.11 reversa con datos", e is None, e)
    ok("C.12 con datos, las tablas, la columna y los eventos se conservan (nada se borra) y las RPC nuevas se quitan",
       con.execute("select (select count(*) from campo.cuadrillas) = 1 and (select count(*) from campo.personal_eventos where tipo_evento = 'fijar_cuadrilla') = 1"
                   " and to_regprocedure('public.geoportal_campo_cuadrillas(text,jsonb,text)') is null").fetchone()[0])
    ok("C.13 y las dos funciones reemplazadas vuelven a la md5 publicada", all(con.execute("select md5(pg_get_functiondef(to_regprocedure(%s)))", (f,)).fetchone()[0] == m
       for f, m in {"public.geoportal_campo_personal(text,jsonb,text)": "f8a83b02da97e8f6a729767f57a394c4", "public.geoportal_campo_historial_personal(text,jsonb,text)": "e82377f5de26a2dcc1a007403889ba48"}.items()))
    ok("C.14 la Personal publicada sigue respondiendo con los eventos conservados", con.execute("select jsonb_typeof(public.geoportal_campo_personal('ciclo.sup@emdupar.gov.co') -> 'personas')").fetchone()[0] == "array")
    e = correr(con, local(leer(f"migracion_{N}_editor.sql"))); ok("C.15 la migración se aplica encima de lo conservado", e is None, e)
    v = ver(con); ok(f"C.16 verificación tras re-aplicar {sum(1 for x in v if x[2] == 'OK')} de {len(v)}", all(x[2] == "OK" for x in v), str([x for x in v if x[2] != 'OK']))
    ok("C.17 la persona sigue en su cuadrilla", con.execute("select public.geoportal_campo_personal('ciclo.sup@emdupar.gov.co') -> 'personas' @> jsonb_build_array(jsonb_build_object('email', 'ciclo.op@emdupar.gov.co', 'cuadrilla', jsonb_build_object('id', %s::bigint, 'nombre', 'Ciclo', 'activa', true)))", (cid,)).fetchone()[0])
    con.close(); srv.cleanup()

    srv, uri, con = bc.preparar()
    con.execute("create or replace function public.geoportal_campo_personal(p_solicitante text, p_filtros jsonb default '{}'::jsonb, p_ip text default null) returns jsonb language sql as $$ select '{}'::jsonb $$")
    e = correr(con, local(leer(f"migracion_{N}_editor.sql")))
    ok("G.01 con una función de Personal distinta, la migración se detiene", e is not None and "deténgase y avise" in e, (e or "")[:200])
    con.close(); srv.cleanup()
    out(""); out(f"RESULTADO: {TOT[1]} de {TOT[0]} pruebas correctas" + (" — SIN FALLAS" if TOT[0] == TOT[1] else ""))
    (PAQ / "resultados_locales.txt").write_text("\n".join(LOG) + "\n")

if __name__ == "__main__":
    main()
