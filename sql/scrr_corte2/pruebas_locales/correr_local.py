"""Recorrido local completo del Motor SCRR, corte 2 (clúster 55432 del Code A; NUNCA Supabase):
generar → ensayo (N de N SIN FALLAS) → huellas ANTES → migración → verificación (8 de 8) → huellas DESPUÉS → pruebas locales del cierre (75)
→ la reversa se niega si hay cartera sin revertir → reversa → la base queda como antes (huella de campo y sin scrr).
Escribe resultados_locales.txt junto al paquete.
Uso: python3 -I correr_local.py [-h]"""
import sys, subprocess, pathlib, re, time
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent
sys.path.insert(0, str(AQUI)); import generar as g
N = g.NOMBRE; salida = []
def log(s): print(s); salida.append(s)
def corre(base, archivo, at=False):
    r = subprocess.run([g.PSQL, "-X", "-d", base, "-f", str(archivo)] + (["-At"] if at else []), capture_output=True, text=True, env=g.ENV)
    return r.returncode, r.stdout, r.stderr

def main():
    t0 = time.time()
    g.main()
    b = g.base_nueva("scrr_local")
    _, _, err = corre(b, PAQ / f"ensayo_en_transaccion_{N}_editor.sql")
    m = re.search(r"RESULTADO: (\d+) de (\d+) pruebas correctas — (SIN FALLAS|FALLAS:.*)", err, re.S)
    log("ensayo: " + (m.group(0)[:3000] if m else "SIN RESULTADO: " + err[-1500:]))
    assert m and "SIN FALLAS" in m.group(0)
    _, out, _ = corre(b, PAQ / f"huellas_solo_lectura_{N}_editor.sql", at=True); log("huellas ANTES:\n" + out.strip())
    rc, _, err = corre(b, PAQ / f"migracion_{N}_editor.sql"); assert rc == 0 and "ERROR" not in err, err[-1500:]; log("migración: aplicada")
    _, out, _ = corre(b, PAQ / f"verificacion_{N}_editor.sql", at=True); log("verificación:\n" + out.strip())
    assert out.count("|OK") == 8 and "FALLA" not in out
    _, out, _ = corre(b, PAQ / f"huellas_solo_lectura_{N}_editor.sql", at=True); log("huellas DESPUÉS:\n" + out.strip())
    _, _, err = corre(b, AQUI / "75_pruebas_cierre_local.sql")
    m = re.search(r"RESULTADO LOCAL: (\d+) de (\d+) pruebas correctas — (SIN FALLAS|FALLAS:.*)", err, re.S)
    log("cierre local: " + (m.group(0)[:3000] if m else "SIN RESULTADO: " + err[-1500:]))
    assert m and "SIN FALLAS" in m.group(0)
    # la reversa se niega si una carga de cartera cambió la tabla y no se revirtió
    g.psql(b, "insert into scrr.cargas (id, tipo, fecha_dato, archivo_nombre, archivo_sha256, filas_leidas, autor) values ('00000000-0000-0000-0000-0000000000aa', 'cartera', current_date, 'zt', repeat('a', 64), 1, 'zt@emdupar.gov.co');"
              "insert into scrr.suscripcion_respaldo (carga_id, contrato, filas, origen) values ('00000000-0000-0000-0000-0000000000aa', '920000000001', '[]', 'archivo');")
    rc, _, err = corre(b, PAQ / f"reversa_{N}_editor.sql")
    log("reversa con cartera sin revertir: " + ("SE NIEGA (correcto)" if "hay cargas de cartera" in err else "NO SE NEGÓ: " + err[-500:]))
    assert "hay cargas de cartera" in err
    g.psql(b, "update scrr.suscripcion_respaldo set revertido_en = now() where carga_id = '00000000-0000-0000-0000-0000000000aa'")
    rc, _, err = corre(b, PAQ / f"reversa_{N}_editor.sql"); assert rc == 0 and "ERROR" not in err, err[-800:]
    quedan = g.valor(b, "select (to_regnamespace('scrr') is null)::text || '|' || (select count(*) from pg_proc where proname like 'geoportal\\_scrr\\_%')::text || '|' || (" + g.CONJ_CAMPO + ")")
    log("reversa: " + quedan + "  (esperado: true|0|261bed3c9242f6261f845ec4e1374b3a)")
    assert quedan == "true|0|261bed3c9242f6261f845ec4e1374b3a"
    g.psql("postgres", f"drop database {b}")
    log(f"RECORRIDO LOCAL COMPLETO SIN FALLAS ({time.time() - t0:.0f} s)")
    (PAQ / "resultados_locales.txt").write_text("\n".join(salida) + "\n")

if __name__ == "__main__":
    main()
