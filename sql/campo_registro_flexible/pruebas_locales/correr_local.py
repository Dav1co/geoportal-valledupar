"""[Code A] Pruebas locales del paquete «Registro flexible» (25-nov). Clúster del Code A (55432), bases emdupar_a_rf_*, cada una rehecha como copia de producción
(generar.rehacer: doble del Code B + la migración publicada de Investigación y Análisis = huellas de campo cce59380… y del acta 111506c6…). NUNCA Supabase.
La huella de Técnica del doble no es la de producción: en los archivos _editor se cambia 838b8098… por la del doble (huellas_locales.json) y se dice en el resultado.
Recorre: huellas ANTES → ensayo (ERROR esperado, N de N) → migración → verificación → huellas DESPUÉS → repetir (rechazo) → registros reales (supervisor con galería y
XY digitado, operario con cámara) → reversa → huellas de vuelta → los registros y sus marcas quedan → repetir reversa (rechazo) → volver a aplicar → verificación.
Guardias (cada una en una base nueva): función de campo distinta, estructura de campo.reporte_fotos distinta, Técnica distinta, tabla nueva distinta.
Mutaciones: el ensayo debe FALLAR si el sello toma la fila vacía de reporte_registro, o si la regla del supervisor se quita.
Escribe ../resultados_locales.txt.
Uso: python3 -I correr_local.py [-h]"""
import sys, re, time, json, pathlib, importlib.util
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent
s = importlib.util.spec_from_file_location("gn", AQUI / "generar.py"); gn = importlib.util.module_from_spec(s); s.loader.exec_module(gn)
N = gn.NOMBRE; HL = json.loads((AQUI / "huellas_locales.json").read_text())
TEC_LOCAL = HL["partida"]["HUELLA_TECNICA_LOCAL"]
LOG = []; TOT = [0, 0]
def out(t=""): print(t); LOG.append(t)
def ok(n, c, d=""):
    TOT[0] += 1; TOT[1] += bool(c); out(f"{'OK   ' if c else 'FALLA'} {n}" + (f"  → {d}" if d and not c else ""))
def leer(n): return (PAQ / n).read_text().replace(gn.TECNICA_PRODUCCION, TEC_LOCAL)
def correr(con, t):
    try: con.execute(t); return None
    except Exception as e:
        try: con.execute("rollback")
        except Exception: pass
        return "\n".join(l for l in str(e).splitlines() if not l.startswith("CONTEXT"))
def huella(con, k): return con.execute(gn.HUELLA[k]).fetchone()[0]
def ver(con): return con.execute(leer(f"verificacion_{N}_editor.sql")).fetchall()
def hl(con): return con.execute(leer(f"huellas_solo_lectura_{N}_editor.sql")).fetchall()
def ensayo(con, texto=None):
    t0 = time.time(); e = correr(con, texto or leer(f"ensayo_en_transaccion_{N}_editor.sql")); dt = time.time() - t0
    m = re.search(r"RESULTADO: (\d+) de (\d+) pruebas correctas( — SIN FALLAS)?", e or ""); return e, m, dt
def migrar(con): return correr(con, leer(f"migracion_{N}_editor.sql"))
def revertir(con): return correr(con, leer(f"reversa_{N}_editor.sql"))

def registros_reales(con):
    """Como la Edge (service_role, topes de producción): un supervisor con una foto de galería y XY digitado, y un operario con cámara. Devuelve los ids."""
    con.execute("insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo) values "
                "('ztrf.sup.real@emdupar.gov.co', 'ZTRF Supervisor', 'consulta', true, 'sin_restriccion', 'todos', false, true, true), "
                "('ztrf.op.real@emdupar.gov.co', 'ZTRF Operario', 'consulta', true, 'sin_restriccion', 'todos', false, true, false) on conflict do nothing")
    ids = []
    for quien, origen, reg, prec in (("ztrf.sup.real@emdupar.gov.co", "galeria", {"xy_manual": True, "lat_registro": 10.48, "lon_registro": -73.27}, None),
                                     ("ztrf.op.real@emdupar.gov.co", "camara", {"lat_registro": 10.46, "lon_registro": -73.25, "precision_registro_m": 5}, 5)):
        with con.transaction():
            con.execute("set local role service_role"); con.execute("set local statement_timeout = '30s'"); con.execute("set local lock_timeout = '8s'")
            p = con.execute("select public.geoportal_campo_preparar_subida(%s, 1, 'campo', null, 'otro')", (quien,)).fetchone()[0]
            con.execute("reset role")
            ruta = p["fotos"][0]["ruta"]
            con.execute("insert into storage.objects (bucket_id, name, metadata) values ('campo-fotos', %s, '{\"size\": 300000, \"mimetype\": \"image/jpeg\"}')", (ruta,))
            con.execute("set local role service_role")
            r = con.execute("select public.geoportal_campo_crear_reporte(%s, %s::uuid, 'otro', null, '[PRUEBA ZTRF] real', null, 10.461, -73.251, %s, false, 'campo', %s::jsonb, "
                            "null, null, null, null, null, null, %s::jsonb)", (quien, p["reporte_id"], prec, json.dumps([{"orden": 1, "ruta": ruta, "origen": origen}]), json.dumps(reg))).fetchone()[0]
            ids.append(r["id"])
    return ids

def main():
    out("PRUEBAS LOCALES · [Code A] Registro flexible para supervisores de Comercial (25-nov) · clúster 55432"); out("")
    out(f"Huella de Técnica: en los _editor va la de producción {gn.TECNICA_PRODUCCION}; en local se cambia por la del doble {TEC_LOCAL} (el doble 4a es anterior a lo último de Técnica).")
    out("")
    con = gn.rehacer("emdupar_a_rf_ciclo")
    h = hl(con); ok("01 huellas ANTES: campo, acta y Técnica «PUBLICADA»", all(x[3].startswith("PUBLICADA") for x in h), str(h))
    e, m, dt = ensayo(con)
    ok(f"02 ensayo: termina en ERROR esperado, {m.group(1) if m else '?'} de {m.group(2) if m else '?'} ({dt:.1f} s)", bool(m and m.group(3)), (e or "")[:3000])
    ok("03 el ensayo no dejó nada (huella de campo publicada, sin la tabla nueva)", huella(con, "campo") == gn.PUBLICADA["campo"] and con.execute("select to_regclass('campo.reporte_registro')").fetchone()[0] is None)
    t0 = time.time(); e = migrar(con); ok(f"04 migración ({time.time() - t0:.1f} s)", e is None, e or "")
    v = ver(con); ok(f"05 verificación {sum(x[2] == 'OK' for x in v)} de {len(v)}", all(x[2] == "OK" for x in v), str([x for x in v if x[2] != "OK"]))
    h = hl(con); ok("06 huellas DESPUÉS: campo «CON ESTE CAMBIO», acta y Técnica sin cambio", h[0][3] == "CON ESTE CAMBIO" and h[1][3].startswith("PUBLICADA") and h[2][3].startswith("PUBLICADA"), str(h))
    ok(f"07 huella de campo nueva = {HL['nuevas']['HUELLA_CAMPO_NUEVA']}", huella(con, "campo") == HL["nuevas"]["HUELLA_CAMPO_NUEVA"])
    e = migrar(con); ok("08 repetir la migración: la guardia la rechaza", e is not None and "ya parece aplicado" in e, e or "(no rechazó)")
    e, m, _ = ensayo(con); ok("09 el ensayo sobre la base ya migrada también se detiene en la guardia", e is not None and "ya parece aplicado" in e, (e or "")[:300])
    ids = registros_reales(con)
    ok("10 registros reales: el supervisor con galería y XY digitado, el operario con cámara", len(ids) == 2)
    marcas = con.execute("select string_agg(rr.xy_manual::text || ':' || f.origen, ',' order by x.seq) from campo.reportes x join campo.reporte_registro rr on rr.reporte_id = x.id "
                         "join campo.reporte_fotos f on f.reporte_id = x.id where x.id = any (%s::uuid[])", (ids,)).fetchone()[0]
    ok("11 sus marcas: true:galeria, false:camara", marcas == "true:galeria,false:camara", marcas)
    e = revertir(con); ok("12 reversa", e is None, e or "")
    ok("13 la huella de campo vuelve a la publicada", huella(con, "campo") == gn.PUBLICADA["campo"])
    h = hl(con); ok("14 huellas tras la reversa: las tres «PUBLICADA»", all(x[3].startswith("PUBLICADA") for x in h), str(h))
    marcas2 = con.execute("select string_agg(rr.xy_manual::text || ':' || f.origen, ',' order by x.seq) from campo.reportes x join campo.reporte_registro rr on rr.reporte_id = x.id "
                          "join campo.reporte_fotos f on f.reporte_id = x.id where x.id = any (%s::uuid[])", (ids,)).fetchone()[0]
    ok("15 nada se borró: los registros y sus marcas siguen", marcas2 == marcas, marcas2)
    e = revertir(con); ok("16 repetir la reversa: se rechaza", e is not None and "no es la de este paquete" in e, e or "(no rechazó)")
    e = migrar(con); ok("17 volver a aplicar sobre lo que dejó la reversa", e is None, e or "")
    v = ver(con); ok(f"18 verificación otra vez {sum(x[2] == 'OK' for x in v)} de {len(v)}", all(x[2] == "OK" for x in v), str([x for x in v if x[2] != "OK"]))
    con.close()

    out(""); out("Guardias (una base nueva cada una):")
    casos = [("19 una función de campo distinta", "create or replace function campo.f_tipo_general(p_codigo text) returns boolean language sql stable security definer set search_path = campo, pg_temp as $$ select false $$", "no son las publicadas"),
             ("20 la estructura de campo.reporte_fotos distinta", "alter table campo.reporte_fotos add column zz text", "estructura de campo.reporte_fotos"),
             ("21 las funciones de Técnica distintas", "create function tecnica.zz_otra() returns int language sql as $$ select 1 $$", "Técnica no son las publicadas"),
             ("22 una tabla campo.reporte_registro que no es la de este paquete", "create table campo.reporte_registro (reporte_id uuid primary key)", "ya existe y no es la de este paquete")]
    for i, (nombre, cambio, texto) in enumerate(casos):
        con = gn.rehacer(f"emdupar_a_rf_g{i}")
        con.execute(cambio)
        e = migrar(con); ok(f"{nombre}: la migración se detiene sin cambiar nada", e is not None and texto in e and con.execute("select count(*) from pg_proc where proname = 'geoportal_campo_derivadas_descarga_iniciar'").fetchone()[0] == 0, e or "(no se detuvo)")
        con.close()

    out(""); out("Mutaciones (el ensayo debe fallar):")
    con = gn.rehacer("emdupar_a_rf_mut")
    base = leer(f"ensayo_en_transaccion_{N}_editor.sql")
    muts = [("23 sello con la fila vacía de reporte_registro", "case when v_rr.reporte_id is null then '' else to_jsonb(v_rr)::text end", "to_jsonb(v_rr)::text", "02.01"),
            ("24 sin la regla del supervisor", "if v_xy or v_no_camara > 0 then\n    if v_via_tec then", "if false then\n    if v_via_tec then", "03.04")]
    mig = leer(f"migracion_{N}_editor.sql")
    for nombre, a, b, prueba in muts:
        assert base.count(a) == 1 and mig.count(a) == 1, nombre
        # la reversa del ensayo exige el md5 de las funciones de este paquete: se le dan los de la versión mutada (si no, se detiene antes del resultado)
        with con.transaction(force_rollback=True):
            con.execute(mig.replace(a, b).replace("begin;\n", "", 1).rsplit("commit;", 1)[0])
            nuevos = {k: gn.md5f(con, f) for k, f in {"CREAR": gn.CREAR_N, "TEC": gn.TEC_N, **gn.MISMA_FIRMA}.items()}
        texto = base.replace(a, b)
        for k, m5 in HL["nuevas"]["MD5_NUEVA"].items(): texto = texto.replace(m5, nuevos[k])
        e, m, _ = ensayo(con, texto)
        ok(f"{nombre}: el ensayo falla en {prueba}", bool(m) and not m.group(3) and f"FALLA {prueba}" in (e or ""), (e or "")[:400])
    con.close()
    out(""); out(f"RESULTADO: {TOT[1]} de {TOT[0]}" + (" — SIN FALLAS" if TOT[0] == TOT[1] else ""))
    (PAQ / "resultados_locales.txt").write_text("\n".join(LOG) + "\n")

if __name__ == "__main__":
    main()
