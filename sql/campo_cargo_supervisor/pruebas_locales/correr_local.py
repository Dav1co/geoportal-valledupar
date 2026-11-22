"""Pruebas locales del cambio «el supervisor de campo cambia área y cargo de los operarios» (Comercial 22-nov) en un PostgreSQL TEMPORAL (pgserver), NUNCA Supabase.
Base: el doble de Administración del 22-nov (campo 3437a83d… y acta 111506c6… = producción), el mismo que cargó el Code B en su servidor de revisión.
Recorre: ensayo → migración → verificación → repetir (rechazo) → reversa → huellas de vuelta → repetir reversa (rechazo) → volver a aplicar; la guardia ante una
función de campo distinta; y deja el doble ya migrado para el Code B (con --doble). Escribe ../resultados_locales.txt.
Uso: python3 -I correr_local.py [-h] [--doble]"""
import sys, re, time, json, pathlib, subprocess, importlib.util, hashlib, shutil
DOBLE_SAL = False
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        if a == "--doble": DOBLE_SAL = True; continue
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent
s = importlib.util.spec_from_file_location("gn", AQUI / "generar.py"); gn = importlib.util.module_from_spec(s); s.loader.exec_module(gn)
N = gn.NOMBRE; NUE = json.loads((AQUI / "huellas_locales.json").read_text())["nuevas"]
LOG = []; TOT = [0, 0]
def out(t=""): print(t); LOG.append(t)
def ok(n, c, d=""):
    TOT[0] += 1; TOT[1] += bool(c); out(f"{'OK   ' if c else 'FALLA'} {n}" + (f"  → {d}" if d and not c else ""))
leer = lambda n: (PAQ / n).read_text()
def correr(con, t):
    try: con.execute(t); return None
    except Exception as e:
        try: con.execute("rollback")
        except Exception: pass
        return "\n".join(l for l in str(e).splitlines() if not l.startswith("CONTEXT"))
def huella(con, k): return con.execute(gn.CONJ[k]).fetchone()[0]
def ver(con): return con.execute(leer(f"verificacion_{N}_editor.sql")).fetchall()
def hl(con): return con.execute(leer(f"huellas_solo_lectura_{N}_editor.sql")).fetchall()

def main():
    out("PRUEBAS LOCALES · Comercial 22-nov · el supervisor de campo cambia área y cargo de los operarios"); out("")
    srv, uri, con = gn.preparar()
    ok("B.01 la base local tiene las huellas de producción (campo 3437a83d…, acta 111506c6…)", huella(con, "campo") == gn.PROD["HUELLA_CAMPO"] and huella(con, "acta") == gn.PROD["HUELLA_ACTA"])
    h = hl(con); ok("B.02 huellas de solo lectura ANTES: PUBLICADA y NO EXISTE", h[0][3].startswith("PUBLICADA") and h[2][3] == "PUBLICADA" and h[3][3] == "PUBLICADA" and h[4][3].startswith("NO EXISTE"), str(h))
    t0 = time.time(); e = correr(con, leer(f"ensayo_en_transaccion_{N}_editor.sql")); dt = time.time() - t0
    m = re.search(r"RESULTADO: (\d+) de (\d+) pruebas correctas( — SIN FALLAS)?", e or ""); out(e or "[sin error: MAL]")
    ok(f"E.01 el ensayo termina en el ERROR esperado con «N de N … SIN FALLAS» ({dt:.1f} s)", m is not None and m.group(1) == m.group(2) and m.group(3) is not None, (e or "")[:400])
    if m: TOT[0] += int(m.group(2)); TOT[1] += int(m.group(1))
    ok("E.02 el ensayo no dejó nada (huella de campo igual, sin función nueva, sin filas ZTCAR)", huella(con, "campo") == gn.PROD["HUELLA_CAMPO"]
       and con.execute("select to_regprocedure('campo.f_supervisor_comercial(text)') is null and not exists (select 1 from public.geoportal_lista_blanca where email like 'ztcar.%%')"
                       " and not exists (select 1 from campo.areas_comercial where codigo like 'ztcar%%') and not exists (select 1 from public.geoportal_auditoria where email like 'ztcar.%%')").fetchone()[0])
    e = correr(con, leer(f"migracion_{N}_editor.sql")); ok("C.01 migración", e is None, e)
    v = ver(con); ok(f"C.02 verificación {sum(1 for x in v if x[2] == 'OK')} de {len(v)} OK", len(v) == 6 and all(x[2] == "OK" for x in v), str([x for x in v if x[2] != "OK"]))
    h = hl(con); ok("C.03 huellas DESPUÉS: CON ESTE CAMBIO y NUEVA; acta igual", h[0][3] == "CON ESTE CAMBIO" and h[1][3].startswith("PUBLICADA") and h[2][3] == h[3][3] == "CON ESTE CAMBIO" and h[4][3].startswith("NUEVA"), str(h))
    e = correr(con, leer(f"migracion_{N}_editor.sql")); ok("C.04 repetir la migración se rechaza", e is not None and "ya parece aplicado" in e, (e or "")[:200])
    e = correr(con, leer(f"ensayo_en_transaccion_{N}_editor.sql")); ok("C.05 el ensayo sobre una base ya migrada se detiene en la guardia", e is not None and "ya parece aplicado" in e, (e or "")[:200])
    # un cambio hecho por un supervisor antes de la reversa: se conserva como evento (nada se borra)
    con.execute("insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo) values "
                "('ciclo.sup@emdupar.gov.co', 'C S', 'consulta', true, 'sin_restriccion', 'todos', false, true, true), ('ciclo.op@emdupar.gov.co', 'C O', 'consulta', true, 'sin_restriccion', 'todos', false, true, false)")
    con.execute("begin; set local role service_role; select public.geoportal_campo_personal_fijar('ciclo.sup@emdupar.gov.co', 'ciclo.op@emdupar.gov.co', 'fijar_cargo', '{\"cargo\": \"Ciclo lector\"}'::jsonb); commit;")
    e = correr(con, leer(f"reversa_{N}_editor.sql")); ok("C.06 reversa", e is None, e)
    ok("C.07 tras la reversa: huella de campo 3437a83d…, las dos RPC con su md5 publicado y sin función nueva",
       huella(con, "campo") == gn.PROD["HUELLA_CAMPO"] and gn.md5f(con, gn.FIJAR) == gn.PROD["MD5_FIJAR"] and gn.md5f(con, gn.PERS) == gn.PROD["MD5_PERSONAL"]
       and con.execute("select to_regprocedure('campo.f_supervisor_comercial(text)') is null").fetchone()[0])
    ok("C.08 el cargo que fijó el supervisor sigue como evento (nada se borra)", con.execute("select campo.f_cargo_vigente('ciclo.op@emdupar.gov.co') = 'Ciclo lector'").fetchone()[0])
    e = correr(con, "begin; set local role service_role; select public.geoportal_campo_personal_fijar('ciclo.sup@emdupar.gov.co', 'ciclo.op@emdupar.gov.co', 'fijar_cargo', '{\"cargo\": \"Ciclo otro\"}'::jsonb); commit;")
    ok("C.09 y vuelve la regla publicada: el supervisor ya no fija cargos (42501)", e is not None and "Solo el administrador puede hacerlo" in e, (e or "")[:200])
    e = correr(con, leer(f"reversa_{N}_editor.sql")); ok("C.10 repetir la reversa se rechaza", e is not None and "no hay nada que revertir" in e, (e or "")[:200])
    e = correr(con, leer(f"migracion_{N}_editor.sql")); ok("C.11 la migración se vuelve a aplicar", e is None, e)
    v = ver(con); ok(f"C.12 verificación tras volver a aplicar {sum(1 for x in v if x[2] == 'OK')} de {len(v)}", all(x[2] == "OK" for x in v), str([x for x in v if x[2] != "OK"]))
    con.execute("create or replace function public.geoportal_campo_personal_fijar(p_solicitante text, p_persona text, p_tipo text, p_datos jsonb default '{}'::jsonb, p_ip text default null) returns jsonb language sql as $$ select '{}'::jsonb $$")
    e = correr(con, leer(f"reversa_{N}_editor.sql")); ok("C.13 la reversa no pisa una RPC que cambió después", e is not None and "la reversa no las pisa" in e, (e or "")[:200])
    con.close(); srv.cleanup()
    srv, uri, con = gn.preparar()
    con.execute("create or replace function campo.f_cargo_vigente(p_email text) returns text language sql stable as $$ select 'x'::text $$")
    e = correr(con, leer(f"migracion_{N}_editor.sql")); ok("G.01 con una función de campo distinta, la migración se detiene sin cambiar nada", e is not None and "deténgase y avise" in e
       and con.execute("select to_regprocedure('campo.f_supervisor_comercial(text)') is null").fetchone()[0], (e or "")[:200])
    e = correr(con, leer(f"ensayo_en_transaccion_{N}_editor.sql")); ok("G.02 y el ensayo también", e is not None and "deténgase y avise" in e, (e or "")[:200])
    con.close(); srv.cleanup()
    if DOBLE_SAL:   # el doble del Code B con este cambio ya aplicado (base vacía + psql), y la comprobación de que carga y conserva las huellas
        srv, uri, con = gn.preparar(); con.execute(leer(f"migracion_{N}_editor.sql"))
        roles = [x[0] for x in con.execute("select rolname from pg_roles where not rolsuper and rolname !~ '^pg_' order by 1").fetchall()]; con.close()
        cuerpo = subprocess.run([str(pathlib.Path(gn.PSQL).with_name("pg_dump")), "--no-owner", "--format=plain", uri], capture_output=True, text=True, check=True).stdout
        cuerpo = cuerpo.replace("SET transaction_timeout = 0;\n", "").replace("SELECT pg_catalog.set_config('search_path', '', false);", "SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', false);  -- el doble de PostGIS (geometry) vive en public")
        sal = gn.DOBLE.parent / "doble_admin_permisos_4a_con_cargo_supervisor.sql"
        sal.write_text("-- Doble de Administración del 22-nov (doble_admin_permisos_4a.sql) CON el cambio «cargo y área por el supervisor de campo» aplicado (Code A). Base VACÍA. NUNCA Supabase.\n"
                       + "".join(f"do $$ begin if not exists (select 1 from pg_roles where rolname = '{x}') then create role {x} nologin; end if; end $$;\n" for x in roles) + cuerpo)
        srv.cleanup()
        import pgserver, psycopg, tempfile
        s2 = pgserver.get_server(tempfile.mkdtemp(prefix="cargo_sup_d_"), cleanup_mode="delete")
        r = subprocess.run([gn.PSQL, s2.get_uri(), "-v", "ON_ERROR_STOP=1", "-q", "-f", str(sal)], capture_output=True, text=True)
        c2 = psycopg.connect(s2.get_uri(), autocommit=True)
        ok(f"D.01 el doble con el cambio carga en una base vacía y tiene la huella nueva ({sal.name}, md5 {hashlib.md5(sal.read_bytes()).hexdigest()})",
           r.returncode == 0 and c2.execute(gn.CONJ["campo"]).fetchone()[0] == NUE["HUELLA_CAMPO_NUEVA"], r.stderr[-300:])
        c2.close(); s2.cleanup()
    out(""); out(f"RESULTADO: {TOT[1]} de {TOT[0]} pruebas correctas" + (" — SIN FALLAS" if TOT[0] == TOT[1] else ""))
    (PAQ / "resultados_locales.txt").write_text("\n".join(LOG) + "\n")

if __name__ == "__main__":
    main()
