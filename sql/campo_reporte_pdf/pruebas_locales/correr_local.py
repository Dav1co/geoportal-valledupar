#!/usr/bin/env python3
"""[Code A] Pruebas locales del paquete «PDF de Reportar anomalía» (27-nov). Clúster del Code A (55432), bases emdupar_a_rf_ran*, cada una rehecha como copia de
producción con PostGIS REAL (generar.rehacer: huella de campo 9f8b8ec5…, capas del mapa con volumen real). NUNCA Supabase.
La huella de Técnica del doble no es la de producción: en los _editor se cambia 838b8098… por la del doble.
Recorre: huellas ANTES → ensayo (ERROR esperado, N de N) → no dejó nada → migración → verificación → huellas DESPUÉS → repetir (rechazo) → ensayo sobre la base
migrada (rechazo) → reversa → huella de vuelta y la tabla con sus filas → repetir reversa (rechazo) → volver a aplicar sobre la tabla que quedó → verificación.
Guardias (base nueva cada una): otra función de campo; sin el índice GiST de los predios; una campo.reporte_pdf que no es la del paquete.
Mutaciones (el ensayo debe fallar): el contenido lee los datos sensibles; la autorización deja pasar al autor (operario); el número RAN en orden de pedidos.
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
def huella(con): return con.execute(gn.HUELLA["campo"]).fetchone()[0]
def ver(con): return con.execute(leer(f"verificacion_{N}_editor.sql")).fetchall()
def hl(con): return con.execute(leer(f"huellas_solo_lectura_{N}_editor.sql")).fetchall()
def ensayo(con, texto=None):
    t0 = time.time(); e = correr(con, texto or leer(f"ensayo_en_transaccion_{N}_editor.sql")); dt = time.time() - t0
    m = re.search(r"RESULTADO: (\d+) de (\d+) pruebas correctas( — SIN FALLAS)?", e or ""); return e, m, dt
def migrar(con, texto=None): return correr(con, texto or leer(f"migracion_{N}_editor.sql"))
def revertir(con): return correr(con, leer(f"reversa_{N}_editor.sql"))
def filas_pdf(con): return con.execute("select count(*) from campo.reporte_pdf").fetchone()[0] if con.execute("select to_regclass('campo.reporte_pdf')").fetchone()[0] else -1

def main():
    out(f"PRUEBAS LOCALES · [Code A] PDF de Reportar anomalía (27-nov) · clúster {gn.PUERTO} · PostGIS real")
    out(f"Huella de Técnica: en los _editor va la de producción {gn.TECNICA_PRODUCCION}; en local se cambia por la del doble.")
    out("")
    con = gn.rehacer("emdupar_a_rf_ran1")
    h = hl(con); ok("01 huellas ANTES: campo «LISTA PARA ESTE CAMBIO»; acta y Técnica «PUBLICADA»", h[0][3].startswith("LISTA") and all(r[3].startswith("PUBLICADA") for r in h[1:]), str(h))
    e, m, dt = ensayo(con)
    ok(f"02 ensayo: termina en ERROR esperado, {m.group(1)} de {m.group(2)} ({dt:.1f} s)" if m else "02 ensayo", bool(m and m.group(3)), (e or "")[-2500:])
    ok("03 el ensayo no dejó nada (huella de partida, sin la tabla, sin correos ZTRAN)", huella(con) == gn.PUBLICADA["campo"] and filas_pdf(con) == -1
       and con.execute("select count(*) from public.geoportal_lista_blanca where email like 'ztran.%'").fetchone()[0] == 0)
    t0 = time.time(); e = migrar(con); ok(f"04 migración ({time.time() - t0:.1f} s)", e is None, e)
    v = ver(con); ok(f"05 verificación {sum(r[2] == 'OK' for r in v)} de {len(v)}", all(r[2] == "OK" for r in v), str(v))
    h = hl(con); ok("06 huellas DESPUÉS: campo «CON ESTE CAMBIO», acta y Técnica sin cambio", h[0][3] == "CON ESTE CAMBIO" and all(r[3].startswith("PUBLICADA") for r in h[1:]), str(h))
    ok(f"07 huella de campo nueva = {HL['nuevas']['HUELLA_CAMPO_NUEVA']}", huella(con) == HL["nuevas"]["HUELLA_CAMPO_NUEVA"])
    e = migrar(con); ok("08 repetir la migración: la guardia la rechaza", e is not None and "ya parece aplicado" in e, e)
    e, m, _ = ensayo(con); ok("09 el ensayo sobre la base ya migrada se detiene en la guardia", e is not None and not m and "ya parece aplicado" in e, (e or "")[-300:])
    # una fila real en la tabla antes de la reversa (como la dejaría producción)
    rid = con.execute("insert into campo.reportes (id, tipo_id, descripcion, lat, lon, precision_m, origen, autor) select gen_random_uuid(), t.id, '[PRUEBA ZTRAN] local', 10.47, -73.25, 5, 'campo', 'ztran.local@emdupar.gov.co' "
                      "from campo.tipos_reporte t where t.codigo = 'otro' returning id").fetchone()[0]
    con.execute("insert into campo.reporte_pdf (reporte_id, version, sello, nombre, ruta, sha256, bytes, generado_por) values (%s, 1, repeat('a', 64), '20261127120000-RAN-000001.pdf', "
                "'campo/2026-11/' || %s || '/bbbbbbbbbbbbbbbb/20261127120000-RAN-000001.pdf', repeat('b', 64), 5000, 'ztran.local@emdupar.gov.co')", (rid, str(rid)))
    e = revertir(con); ok("10 reversa", e is None, e)
    ok("11 la huella vuelve a la de partida y la tabla queda con su fila (nada se borra)", huella(con) == gn.PUBLICADA["campo"] and filas_pdf(con) == 1)
    e = revertir(con); ok("12 repetir la reversa: se rechaza", e is not None and "no es la de este paquete" in e, e)
    e = migrar(con); ok("13 volver a aplicar sobre la tabla que dejó la reversa (con su fila)", e is None and filas_pdf(con) == 1, e)
    v = ver(con); ok(f"14 verificación otra vez {sum(r[2] == 'OK' for r in v)} de {len(v)}", all(r[2] == "OK" for r in v), str(v))
    con.close()
    out(""); out("Guardias (una base nueva cada una):")
    con = gn.rehacer("emdupar_a_rf_ran2")
    con.execute("create or replace function campo.f_zz_otra() returns int language sql as $$ select 1 $$")
    e = migrar(con); ok("15 otra función de campo: la migración se detiene sin cambiar nada", e is not None and "no son las esperadas" in e and filas_pdf(con) == -1, e)
    con.close()
    con = gn.rehacer("emdupar_a_rf_ran3")
    con.execute("drop index public.idx_predcom_geom_n")   # solo en esta base, recién creada por este guion
    e = migrar(con); ok("16 sin el índice GiST de los predios: la migración se detiene sin cambiar nada", e is not None and "idx_predcom_geom_n" in e and filas_pdf(con) == -1, e)
    con.close()
    con = gn.rehacer("emdupar_a_rf_ran4")
    con.execute("create table campo.reporte_pdf (id bigint primary key)")
    e = migrar(con); ok("17 una campo.reporte_pdf que no es la del paquete: la migración se detiene", e is not None and "no es la de este paquete" in e, e)
    con.close()
    out(""); out("Mutaciones (el ensayo debe fallar):")
    con = gn.rehacer("emdupar_a_rf_ran5")
    base = leer(f"ensayo_en_transaccion_{N}_editor.sql")
    a = "    'descripcion', v.descripcion,\n"
    assert base.count(a) == 1
    mut = base.replace(a, "    'descripcion', v.descripcion || coalesce(' ' || (select d.datos::text from campo.reporte_datos_sensibles d where d.reporte_id = p_id), ''),\n", 1)
    mut = mut.replace("raise exception 'La función % no es la de este paquete", "raise notice 'La función % no es la de este paquete", 1)
    e, m, _ = ensayo(con, mut)
    ok("18 el contenido lee los datos sensibles: el ensayo falla en 04.01", bool(m) and not m.group(3) and "FALLA 04.01" in (e or ""), (e or "")[-600:])
    a = "  v_email := campo.f_autorizar_supervision(p_solicitante);\n  select t.codigo into v_cod"
    assert base.count(a) == 1
    mut = base.replace(a, "  v_email := campo.f_autorizar_documento(p_solicitante, 'campo', p_id);\n  select t.codigo into v_cod", 1)
    mut = mut.replace("raise exception 'La función % no es la de este paquete", "raise notice 'La función % no es la de este paquete", 1)
    e, m, _ = ensayo(con, mut)
    ok("19 la autorización de los documentos (deja pasar al autor): el ensayo falla en 02.02", bool(m) and not m.group(3) and "FALLA 02.02" in (e or ""), (e or "")[-600:])
    a = "     and (p_hasta is null or (r.registrado_en, r.seq) <= (v_reg, v_seq))"
    assert base.count(a) == 1
    mut = base.replace(a, "     and (p_hasta is null or r.id = p_hasta)", 1)   # numera solo el pedido: orden de pedidos, no de registro
    mut = mut.replace("raise exception 'La función % no es la de este paquete", "raise notice 'La función % no es la de este paquete", 1)
    e, m, _ = ensayo(con, mut)
    ok("20 numerar en el orden de los pedidos (no en el de registro): el ensayo falla en 01b.05", bool(m) and not m.group(3) and "FALLA 01b.05" in (e or ""), (e or "")[-600:])
    con.close()
    out(""); out(f"RESULTADO: {TOT[1]} de {TOT[0]}" + (" — SIN FALLAS" if TOT[0] == TOT[1] else " — CON FALLAS"))
    (PAQ / "resultados_locales.txt").write_text("\n".join(LOG) + "\n")
    sys.exit(0 if TOT[0] == TOT[1] else 1)

if __name__ == "__main__":
    main()
