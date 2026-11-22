"""Pruebas locales del paquete (b) Actas: firmas, PDF, actas registradas y derivadas (Comercial 21-nov), en un PostgreSQL TEMPORAL (pgserver), NUNCA en Supabase.
Base: base_comercial.py (campo, acta y salida = producción del 21-nov 17:55) con el paquete (a) aplicado. Solo las huellas de redes y técnica se sustituyen por las locales
(esta base no trae redes ni técnica completas). Escribe ../resultados_locales.txt.
Uso: python3 -I correr_local.py [-h]"""
import sys, re, json, time, pathlib, importlib.util
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent
s = importlib.util.spec_from_file_location("gb", AQUI / "generar.py"); gb = importlib.util.module_from_spec(s); s.loader.exec_module(gb)
N = "campo_actas_documentos"
LOCAL = json.loads((AQUI / "huellas_locales.json").read_text())["locales"]
LOG = []; TOT = [0, 0]
def out(t=""): print(t); LOG.append(t)
def ok(nombre, cond, det=""):
    TOT[0] += 1; TOT[1] += bool(cond); out(f"{'OK   ' if cond else 'FALLA'} {nombre}" + (f"  → {det}" if det and not cond else ""))
leer = lambda n: (PAQ / n).read_text()
def local(t): return gb.local_a(t, LOCAL)
def correr(con, t):
    try: con.execute(t); return None
    except Exception as e:
        try: con.execute("rollback")
        except Exception: pass
        return "\n".join(l for l in str(e).splitlines() if not l.startswith("CONTEXT"))
def huellas(con): return {f"{r[0]}|{r[1]}": r[3] for r in con.execute(local(leer(f"huellas_solo_lectura_{N}_editor.sql"))).fetchall()}
def ver(con): return con.execute(leer(f"verificacion_{N}_editor.sql")).fetchall()

def main():
    out("PRUEBAS LOCALES · Comercial 21-nov · (b) Actas: firmas, PDF, actas registradas y derivadas"); out("")
    srv, uri, con, loc = gb.preparar()
    ok("B.01 la base local es la de producción con (a) aplicado (huella de campo tras (a) determinista)", loc["HUELLA_CAMPO_A"] == LOCAL["HUELLA_CAMPO_A"])
    e = correr(con, leer(f"ensayo_en_transaccion_{N}_editor.sql"))
    ok("E.01 con las huellas de redes y técnica de producción, la guardia detiene el ensayo en esta base", e is not None and "deténgase y avise" in e, (e or "")[:200])
    t0 = time.time(); e = correr(con, local(leer(f"ensayo_en_transaccion_{N}_editor.sql"))); dt = time.time() - t0
    m = re.search(r"RESULTADO: (\d+) de (\d+)", e or ""); out(e or "[sin error: MAL]")
    ok(f"E.02 el ensayo termina en ERROR esperado con todas sus pruebas correctas ({dt:.1f} s)", m is not None and m.group(1) == m.group(2), (e or "")[:300])
    if m: TOT[0] += int(m.group(2)) - 1; TOT[1] += int(m.group(1)) - (1 if m.group(1) == m.group(2) else 0)
    ok("E.03 el ensayo no dejó nada", con.execute("select to_regclass('campo.formularios_documento') is null and not exists (select 1 from storage.buckets where id = 'actas-pdf')").fetchone()[0])
    antes = huellas(con)
    ok("C.01 huellas antes: (a) PUBLICADO, acta PUBLICADA, nuevas NO EXISTE, tablas NO EXISTEN",
       antes.get("2|2 funciones de campo (conjunto, sin las que protegen datos conservados)", "").startswith("(a) PUBLICADO") and all(v.startswith(("NO EXISTE", "PUBLICADA", "debe ser")) or k[0] in "26" for k, v in antes.items()), str(antes)[:400])
    trg_antes = con.execute("select count(*) from pg_trigger where not tgisinternal and tgrelid in ('campo.reportes'::regclass, 'acta.actas'::regclass)").fetchone()[0]
    campo_antes = con.execute(gb.CONJ_CAMPO_A).fetchone()[0]
    e = correr(con, local(leer(f"migracion_{N}_editor.sql"))); ok("C.02 migración", e is None, e)
    v = ver(con); ok(f"C.03 verificación {sum(1 for x in v if x[2] == 'OK')} de {len(v)} OK", len(v) == 10 and all(x[2] == "OK" for x in v), str([x for x in v if x[2] != "OK"]))
    d = huellas(con); ok("C.04 huellas después: NUEVA, EXISTEN, acta PUBLICADA", all(not v.startswith(("NO EXISTE", "OTRA", "A MEDIAS")) for v in d.values()), str({k: v for k, v in d.items() if v.startswith(("NO", "OTRA", "A M"))}))
    e = correr(con, local(leer(f"migracion_{N}_editor.sql"))); ok("C.05 repetir la migración se rechaza", e is not None and "ya parecen aplicadas" in e, (e or "")[:150])
    e = correr(con, leer(f"reversa_{N}_editor.sql")); ok("C.06 reversa sin datos", e is None, e)
    ok("C.07 tras la reversa: conjunto de campo y disparadores como antes; sin tablas ni bucket; da_lugar desactivado (no borrado)",
       con.execute(gb.CONJ_CAMPO_A).fetchone()[0] == campo_antes and con.execute("select count(*) from pg_trigger where not tgisinternal and tgrelid in ('campo.reportes'::regclass, 'acta.actas'::regclass)").fetchone()[0] == trg_antes
       and con.execute("select to_regclass('campo.firmas') is null and not exists (select 1 from storage.buckets where id = 'actas-pdf') and (select count(*) from campo.tipo_campos where codigo in ('da_lugar', 'da_lugar_otra') and not activo) = 8").fetchone()[0])
    e = correr(con, leer(f"reversa_{N}_editor.sql")); ok("C.08 repetir la reversa se rechaza", e is not None and "no hay nada que revertir" in e, (e or "")[:150])
    e = correr(con, local(leer(f"migracion_{N}_editor.sql"))); ok("C.09 la migración se vuelve a aplicar (reactiva da_lugar)", e is None, e)
    v = ver(con); ok(f"C.10 verificación tras re-aplicar {sum(1 for x in v if x[2] == 'OK')} de {len(v)}", all(x[2] == "OK" for x in v), str([x for x in v if x[2] != "OK"]))
    con.execute("insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo) values ('ciclo.rep@emdupar.gov.co', 'R', 'consulta', true, 'sin_restriccion', 'todos', false, true)")
    rid = con.execute("select gen_random_uuid()").fetchone()[0]
    con.execute("select public.geoportal_campo_firma_guardar('ciclo.rep@emdupar.gov.co', 'campo', %s, 'operario', 'firmo', null, encode('\\xffd8ffe0'::bytea || convert_to(repeat('C', 300), 'UTF8'), 'base64'))", (rid,))
    e = correr(con, leer(f"reversa_{N}_editor.sql")); ok("C.11 reversa con una firma guardada", e is None, e)
    ok("C.12 con datos se conservan las firmas con su protección (nada se borra); las RPC se quitan",
       con.execute("select (select count(*) from campo.firmas) = 1 and to_regprocedure('public.geoportal_campo_firma_guardar(text,text,uuid,text,text,text,text,text)') is null"
                   " and exists (select 1 from pg_trigger where tgname = 't_firmas_definitivas') and exists (select 1 from storage.buckets where id = 'actas-pdf')").fetchone()[0])
    trg = con.execute("select count(*), string_agg(tgname, ',') from pg_trigger where not tgisinternal and tgrelid in ('campo.reportes'::regclass, 'acta.actas'::regclass)").fetchone()
    ok("C.13 y el registro vuelve a ser el de hoy (sin disparadores en campo.reportes ni acta.actas)", trg[0] == trg_antes, f"{trg} vs {trg_antes}")
    e = correr(con, local(leer(f"migracion_{N}_editor.sql"))); ok("C.14 la migración se aplica encima de lo conservado", e is None, e)
    v = ver(con); ok(f"C.15 verificación {sum(1 for x in v if x[2] == 'OK')} de {len(v)} y la firma sigue", all(x[2] == "OK" for x in v) and con.execute("select count(*) from campo.firmas").fetchone()[0] == 1, str([x for x in v if x[2] != "OK"]))
    con.close(); srv.cleanup()
    srv, uri, con, loc = gb.preparar()
    con.execute("create or replace function campo.f_cargo_vigente(p_email text) returns text language sql stable as $$ select 'x'::text $$")
    e = correr(con, local(leer(f"migracion_{N}_editor.sql"))); ok("G.01 con una función de campo distinta, la migración se detiene", e is not None and "deténgase y avise" in e, (e or "")[:200])
    con.close(); srv.cleanup()
    out(""); out(f"RESULTADO: {TOT[1]} de {TOT[0]} pruebas correctas" + (" — SIN FALLAS" if TOT[0] == TOT[1] else ""))
    (PAQ / "resultados_locales.txt").write_text("\n".join(LOG) + "\n")

if __name__ == "__main__":
    main()
