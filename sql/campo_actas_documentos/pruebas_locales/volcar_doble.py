"""Vuelca la base doble de Comercial con los paquetes (a) Personal y cuadrillas y (b) Actas YA APLICADOS, para el Code B. Base TEMPORAL (pgserver); nunca Supabase.
Uso: python3 -I volcar_doble.py [-h]      (escribe ../../campo_personal_cuadrillas/doble_para_code_b/doble_comercial_con_actas.sql)"""
import sys, pathlib, subprocess, importlib.util, shutil
for a in sys.argv[1:]:
    if a in ("-h", "--help"): print(__doc__); sys.exit(0)
    print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent
s = importlib.util.spec_from_file_location("gb", AQUI / "generar.py"); gb = importlib.util.module_from_spec(s); s.loader.exec_module(gb)
srv, uri, con, loc = gb.preparar()
con.execute(gb.local_a((PAQ / "migracion_campo_actas_documentos_editor.sql").read_text(), loc))
roles = [r[0] for r in con.execute("select rolname from pg_roles where not rolsuper and rolname !~ '^pg_' order by 1").fetchall()]
ver = con.execute("show server_version").fetchone()[0]; con.close()
pgd = shutil.which("pg_dump", path="/opt/homebrew/opt/postgresql@17/bin") or "pg_dump"
cuerpo = subprocess.run([pgd, "--no-owner", "--format=plain", uri], capture_output=True, text=True, check=True).stdout
cuerpo = cuerpo.replace("SET transaction_timeout = 0;\n", "").replace("SELECT pg_catalog.set_config('search_path', '', false);", "SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', false);  -- el doble de PostGIS (geometry) vive en public")
sal = PAQ.parent / "campo_personal_cuadrillas" / "doble_para_code_b" / "doble_comercial_con_actas.sql"
cab = ("-- Doble local de Comercial para el Code B (Code A, 21-nov): campo + acta + salida (huellas = producción del 21-nov 17:55) con (a) Personal y cuadrillas y (b) Actas YA APLICADOS.\n"
       f"-- PostgreSQL {ver}. Sin datos reales. Cárguelo en una base VACÍA. Incluye el bucket actas-pdf en storage.buckets (doble).\n"
       + "".join(f"do $$ begin if not exists (select 1 from pg_roles where rolname = '{r}') then create role {r} nologin; end if; end $$;\n" for r in roles))
sal.write_text(cab + cuerpo); srv.cleanup()
print(f"[OK ] {sal} ({sal.stat().st_size // 1024} KB)")
