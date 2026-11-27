#!/usr/bin/env python3
"""[Code A] Pruebas locales del paquete «Etiqueta del último pago» (27-nov). Clúster del Code A (55432), bases emdupar_a_rf_pago*, cada una rehecha como copia
de producción (generar.rehacer: doble de Consultar direcciones + su migración publicada = huella de campo c476f14d…). NUNCA Supabase.
La huella de Técnica del doble no es la de producción: en los _editor se cambia 838b8098… por la del doble y se dice en el resultado.
Recorre: huellas ANTES → ensayo (ERROR esperado, N de N) → no dejó nada → migración → verificación → huellas DESPUÉS → repetir (rechazo) → ensayo sobre la base
migrada (rechazo) → reversa → huella de vuelta → repetir reversa (rechazo) → volver a aplicar → verificación.
Guardias (base nueva cada una): otra función de campo; la función del análisis cambiada. Mutación: una migración que no quita el «- 'corte'» → el ensayo falla.
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
LOG = []; TOT = [0, 0]
def out(t=""): print(t); LOG.append(t)
def ok(n, c, d=""):
    TOT[0] += 1; TOT[1] += bool(c); out(f"{'OK   ' if c else 'FALLA'} {n}" + (f"  → {d}" if d and not c else ""))
def leer(n): return gn.a_local((PAQ / n).read_text())
def correr(con, t):
    try: con.execute(t); return None
    except Exception as e:
        try: con.execute("rollback")
        except Exception: pass
        return "\n".join(l for l in str(e).splitlines() if not l.startswith("CONTEXT"))
def huella(con, k="campo"): return con.execute(gn.HUELLA[k]).fetchone()[0]
def ver(con): return con.execute(leer(f"verificacion_{N}_editor.sql")).fetchall()
def hl(con): return con.execute(leer(f"huellas_solo_lectura_{N}_editor.sql")).fetchall()
def ensayo(con, texto=None):
    t0 = time.time(); e = correr(con, texto or leer(f"ensayo_en_transaccion_{N}_editor.sql")); dt = time.time() - t0
    m = re.search(r"RESULTADO: (\d+) de (\d+) pruebas correctas( — SIN FALLAS)?", e or ""); return e, m, dt
def migrar(con): return correr(con, leer(f"migracion_{N}_editor.sql"))
def revertir(con): return correr(con, leer(f"reversa_{N}_editor.sql"))

def main():
    out(f"PRUEBAS LOCALES · [Code A] Etiqueta del último pago (27-nov) · clúster {gn.gnd.gn0.PUERTO}")
    out(f"Huella de Técnica: en los _editor va la de producción {gn.TECNICA_PRODUCCION}; en local se cambia por la del doble.")
    out("")
    con = gn.rehacer("emdupar_a_rf_pago1")
    ok("01 huellas ANTES: campo, acta y Técnica «PUBLICADA»", all(r[3].startswith("PUBLICADA") for r in hl(con)), str(hl(con)))
    e, m, dt = ensayo(con)
    ok(f"02 ensayo: termina en ERROR esperado, {m.group(1)} de {m.group(2)} ({dt:.1f} s)" if m else "02 ensayo", bool(m and m.group(3)), (e or "")[-1500:])
    ok("03 el ensayo no dejó nada (huella de campo publicada, sin datos ZTPAG)", huella(con) == gn.PUBLICADA["campo"]
       and con.execute("select count(*) from bi_interno.ficha_contrato where contrato like '9918000001__'").fetchone()[0] == 0
       and con.execute("select count(*) from public.geoportal_lista_blanca where email like 'ztpag.%'").fetchone()[0] == 0)
    t0 = time.time(); e = migrar(con); ok(f"04 migración ({time.time() - t0:.1f} s)", e is None, e)
    v = ver(con); ok(f"05 verificación {sum(r[2] == 'OK' for r in v)} de {len(v)}", all(r[2] == "OK" for r in v), str(v))
    h = hl(con); ok("06 huellas DESPUÉS: campo «CON ESTE CAMBIO», acta y Técnica sin cambio", h[0][3] == "CON ESTE CAMBIO" and all(r[3].startswith("PUBLICADA") for r in h[1:]), str(h))
    ok(f"07 huella de campo nueva = {HL['nuevas']['HUELLA_CAMPO_NUEVA']}", huella(con) == HL["nuevas"]["HUELLA_CAMPO_NUEVA"])
    e = migrar(con); ok("08 repetir la migración: la guardia la rechaza", e is not None and "ya parece aplicado" in e, e)
    e, m, _ = ensayo(con); ok("09 el ensayo sobre la base ya migrada se detiene en la guardia", e is not None and not m and "ya parece aplicado" in e, (e or "")[-400:])
    e = revertir(con); ok("10 reversa", e is None, e)
    ok("11 la huella de campo vuelve a la publicada", huella(con) == gn.PUBLICADA["campo"])
    e = revertir(con); ok("12 repetir la reversa: se rechaza", e is not None and "no es la de este paquete" in e, e)
    e = migrar(con); ok("13 volver a aplicar sobre lo que dejó la reversa", e is None, e)
    v = ver(con); ok(f"14 verificación otra vez {sum(r[2] == 'OK' for r in v)} de {len(v)}", all(r[2] == "OK" for r in v), str(v))
    con.close()
    out(""); out("Guardias (una base nueva cada una):")
    con = gn.rehacer("emdupar_a_rf_pago2")
    con.execute("create or replace function campo.f_zz_otra() returns int language sql as $$ select 1 $$")
    e = migrar(con); ok("15 otra función de campo: la migración se detiene sin cambiar nada", e is not None and "no son las publicadas" in e and gn.md5f(con, gn.FUNCION) == gn.MD5_PUBLICADA, e)
    con.close()
    con = gn.rehacer("emdupar_a_rf_pago3")
    # la función del análisis distinta pero la huella de campo «publicada»: no se puede sin cambiar la huella; se prueba la guardia por md5 quitando la huella
    texto = leer(f"migracion_{N}_editor.sql").replace(f"is distinct from '{gn.PUBLICADA['campo']}'", "is distinct from v")
    con.execute(gn.defn(con, gn.FUNCION).replace("v_hoy - (f.ultimo_pago ->> 'fecha')::date", "v_hoy - (f.ultimo_pago ->> 'fecha')::date + 0"))
    e = correr(con, texto); ok("16 la función del análisis cambiada: la guardia (md5) la rechaza sin cambiar nada", e is not None and "no es la publicada" in e, e)
    con.close()
    out(""); out("Mutaciones (el ensayo debe fallar):")
    con = gn.rehacer("emdupar_a_rf_pago4")
    mut = leer(f"ensayo_en_transaccion_{N}_editor.sql").replace("then f.ultimo_pago || jsonb_build_object('dias'", "then f.ultimo_pago - 'corte' || jsonb_build_object('dias'", 1)
    mut = mut.replace("position('f.ultimo_pago - ''corte''' in", "0 * position('x' in", 1)   # que no cae solo por la 01.05
    mut = mut.replace(f"raise exception 'La función {gn.FUNCION} no es la de este paquete", f"raise notice 'La función {gn.FUNCION} no es la de este paquete", 1)  # la reversa no corta el ensayo
    e, m, _ = ensayo(con, mut)
    ok("17 una migración que sigue quitando el corte: el ensayo falla en 02.01", bool(m) and not m.group(3) and "FALLA 02.01" in (e or ""), (e or "")[-600:])
    con.close()
    out(""); out(f"RESULTADO: {TOT[1]} de {TOT[0]}" + (" — SIN FALLAS" if TOT[0] == TOT[1] else " — CON FALLAS"))
    (PAQ / "resultados_locales.txt").write_text("\n".join(LOG) + "\n")
    sys.exit(0 if TOT[0] == TOT[1] else 1)

if __name__ == "__main__":
    main()
