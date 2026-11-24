"""Recorrido local completo del Reparto de facturas, commit 1 (clúster 55432 del Code A; NUNCA Supabase):
generar → ensayo (N de N SIN FALLAS, con el volumen de producción) → huellas ANTES → migración → verificación (9 de 9) → huellas DESPUÉS
→ concurrencia real en DOS sesiones (el mismo toque a la vez; la misma factura con dos toques a la vez) → la reversa se niega con datos
→ reversa en una base sin datos → la base queda como antes (sin reparto y campo igual).
Escribe resultados_locales.txt junto al paquete.
Uso: python3 -I correr_local.py [-h]"""
import sys, subprocess, pathlib, re, time, os, threading, uuid
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

PREPARA = """
insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta, ver_registro_tecnico)
  values ('ztrep.rep1@emdupar.gov.co', 'ZTREP Repartidor uno', 'consulta', true, 'sin_restriccion', 'todos', false, true, false, false, false, false);
insert into campo.personal_eventos (persona, tipo_evento, valor, autor) values ('ztrep.rep1@emdupar.gov.co', 'asignar_actividad', 'reparto', 'ztrep.adm@emdupar.gov.co');
insert into hechos.rutas_consecutivos (ciclo, consecutivo_ruta, ruta, contrato, periodo) values
  ('8801', '1', '880101', '880000000101', '202610'), ('8801', '2', '880101', '880000000102', '202610');
"""
# Una sesión como la Edge (service_role, topes de producción) que entrega y se queda con la transacción abierta p_espera segundos
def sesion(base, jornada, contrato, id_cliente, espera, salida_hilo, clave):
    sql = (f"set role service_role; set statement_timeout = '30s'; set lock_timeout = '8s'; begin;\n"
           f"select public.geoportal_reparto_entregar('ztrep.rep1@emdupar.gov.co', {jornada}, '{contrato}', -73.25, 10.47, 5, false, '{id_cliente}'::uuid);\n"
           f"select pg_sleep({espera});\ncommit;\n")
    r = subprocess.run([g.PSQL, "-X", "-At", "-d", base], input=sql, capture_output=True, text=True, env=g.ENV)
    salida_hilo[clave] = " ".join(l for l in (r.stdout + r.stderr).splitlines() if l.strip() and l.strip() not in ("SET", "BEGIN", "COMMIT", "ROLLBACK", "") and not l.startswith(("CONTEXT", "HINT")))

def a_la_vez(base, jornada, pares):
    res = {}; hilos = []
    for i, (contrato, idc, espera, retraso) in enumerate(pares):
        def corre_hilo(c=contrato, u=idc, e=espera, d=retraso, k=i):
            time.sleep(d); sesion(base, jornada, c, u, e, res, k)
        h = threading.Thread(target=corre_hilo); h.start(); hilos.append(h)
    for h in hilos: h.join()
    return res

def main():
    t0 = time.time()
    g.main()
    b = g.base_nueva(f"reparto_local_{os.getpid()}")
    b2 = g.base_nueva(f"reparto_rev_{os.getpid()}")
    try:
        _, _, err = corre(b, PAQ / f"ensayo_en_transaccion_{N}_editor.sql")
        m = re.search(r"RESULTADO: (\d+) de (\d+) pruebas correctas — (SIN FALLAS|FALLAS:)[^\n]*(\nTiempos:(\n1[14]\.[^\n]*)+)?", err)
        log("ensayo: " + (m.group(0) if m else "SIN RESULTADO: " + err[-2500:]))
        assert m and "SIN FALLAS" in m.group(0)
        _, out, _ = corre(b, PAQ / f"huellas_solo_lectura_{N}_editor.sql", at=True); log("huellas ANTES:\n" + out.strip())
        rc, _, err = corre(b, PAQ / f"migracion_{N}_editor.sql"); assert rc == 0 and "ERROR" not in err, err[-1500:]; log("migración: aplicada")
        rc, _, err = corre(b, PAQ / f"migracion_{N}_editor.sql")
        log("migración otra vez: " + ("LA GUARDIA SE NIEGA (correcto)" if "GUARDIA REPARTO: el esquema reparto ya existe" in err else "NO SE NEGÓ: " + err[-500:]))
        assert "GUARDIA REPARTO: el esquema reparto ya existe" in err
        _, out, _ = corre(b, PAQ / f"verificacion_{N}_editor.sql", at=True); log("verificación:\n" + out.strip())
        assert out.count("|OK") == 9 and "FALLA" not in out
        _, out, _ = corre(b, PAQ / f"huellas_solo_lectura_{N}_editor.sql", at=True); log("huellas DESPUÉS:\n" + out.strip())
        # --- concurrencia real (dos sesiones) ---
        g.psql(b, PREPARA)
        j = g.valor(b, "select (public.geoportal_reparto_empezar('ztrep.rep1@emdupar.gov.co', 'anterior', '8801', '880101') -> 'jornada' ->> 'id')")
        u = str(uuid.uuid4())
        r = a_la_vez(b, j, [("880000000101", u, 2, 0), ("880000000101", u, 0, 0.5)])
        filas = g.valor(b, f"select count(*) from reparto.entregas where id_cliente = '{u}'")
        ok1 = '"repetida": false' in r[0] and '"repetida": true' in r[1] and filas == "1"
        log(f"concurrencia 1 (el mismo toque dos veces A LA VEZ): {'OK' if ok1 else 'FALLA'} · filas {filas} · 1.ª: {r[0][:120]} · 2.ª: {r[1][:120]}")
        r = a_la_vez(b, j, [("880000000102", str(uuid.uuid4()), 2, 0), ("880000000102", str(uuid.uuid4()), 0, 0.5)])
        filas = g.valor(b, "select count(*) from reparto.entregas where contrato = '880000000102'")
        ok2 = '"consecutivo": 2' in r[0] and "ya se registró" in r[1] and filas == "1"
        log(f"concurrencia 2 (la misma factura, dos toques distintos A LA VEZ): {'OK' if ok2 else 'FALLA'} · filas {filas} · 1.ª: {r[0][:120]} · 2.ª: {r[1][:160]}")
        assert ok1 and ok2
        rc, _, err = corre(b, PAQ / f"reversa_{N}_editor.sql")
        log("reversa con entregas registradas: " + ("SE NIEGA (correcto)" if "ya hay jornadas, entregas o archivos" in err else "NO SE NEGÓ: " + err[-500:]))
        assert "ya hay jornadas, entregas o archivos" in err
        # --- reversa en una base sin datos ---
        antes = g.valor(b2, g.CONJ_CAMPO)
        rc, _, err = corre(b2, PAQ / f"migracion_{N}_editor.sql"); assert rc == 0 and "ERROR" not in err, err[-800:]
        rc, _, err = corre(b2, PAQ / f"reversa_{N}_editor.sql"); assert rc == 0 and "ERROR" not in err, err[-800:]
        quedan = g.valor(b2, "select (to_regnamespace('reparto') is null)::text || '|' || (select count(*) from pg_proc where proname like 'geoportal\\_reparto\\_%')::text || '|' || (" + g.CONJ_CAMPO + ")")
        inactiva = g.valor(b2, "select (not activa)::text from campo.actividades where codigo = 'supervision_reparto'")
        log("reversa: la actividad supervision_reparto queda DESACTIVADA (no se borra): " + inactiva); assert inactiva == "true"
        log("reversa: " + quedan + f"  (esperado: true|0|{antes}: sin reparto, sin RPC y campo igual)")
        assert quedan == f"true|0|{antes}"
        rc, _, err = corre(b2, PAQ / f"reversa_{N}_editor.sql")
        ok3 = rc == 0 and "ERROR" not in err and g.valor(b2, "select (to_regnamespace('reparto') is null)::text") == "true"
        log("reversa otra vez (sin nada que revertir): " + ("termina sin error (correcto)" if ok3 else "FALLA: " + err[-300:])); assert ok3
    finally:
        # solo lo que creó ESTA corrida, también si algo falló
        g.borrar_mia(b); g.borrar_mia(b2)
    log(f"RECORRIDO LOCAL COMPLETO SIN FALLAS ({time.time() - t0:.0f} s)")
    (PAQ / "resultados_locales.txt").write_text("\n".join(salida) + "\n")

if __name__ == "__main__":
    main()
