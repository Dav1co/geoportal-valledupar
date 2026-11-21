"""Vuelca la base doble de Comercial (campo + acta + salida, con el paquete (a) aplicado) a un .sql plano para el Code B. Base TEMPORAL (pgserver); nunca Supabase.
Uso: python3 -I volcar_doble.py [-h]      (escribe ../doble_para_code_b/doble_comercial_con_personal.sql)"""
import sys, json, pathlib, subprocess, importlib.util, shutil
for a in sys.argv[1:]:
    if a in ("-h", "--help"): print(__doc__); sys.exit(0)
    print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent
s = importlib.util.spec_from_file_location("bc", AQUI / "base_comercial.py"); bc = importlib.util.module_from_spec(s); s.loader.exec_module(bc)
s = importlib.util.spec_from_file_location("cl", AQUI / "correr_local.py"); cl = importlib.util.module_from_spec(s); s.loader.exec_module(cl)
srv, uri, con = bc.preparar()
con.execute(cl.local((PAQ / "migracion_campo_personal_cuadrillas_editor.sql").read_text()))
roles = [r[0] for r in con.execute("select rolname from pg_roles where not rolsuper and rolname !~ '^pg_' order by 1").fetchall()]   # los roles del doble (anon, service_role, dell_envios…)
ver = con.execute("show server_version").fetchone()[0]
con.close()
pgd = shutil.which("pg_dump", path="/opt/homebrew/opt/postgresql@17/bin") or "pg_dump"
sal = PAQ / "doble_para_code_b" / "doble_comercial_con_personal.sql"
cuerpo = subprocess.run([pgd, "--no-owner", "--format=plain", uri], capture_output=True, text=True, check=True).stdout.replace("SET transaction_timeout = 0;\n", "").replace("SELECT pg_catalog.set_config('search_path', '', false);", "SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', false);  -- el doble de PostGIS (geometry) vive en public")   # pg_dump 17 sobre una base 16
cab = ("-- Doble local de Comercial para el Code B (Code A, 21-nov): cadena de campo + acta + salida (huellas de 8 funciones y conjuntos de acta y salida = producción del 21-nov 17:55)\n"
       f"-- con el paquete (a) Personal y cuadrillas YA APLICADO (rama comercial-personal-cuadrillas, cf21358). PostgreSQL {ver}. Sin datos reales. Cárguelo en una base VACÍA.\n"
       + "".join(f"do $$ begin if not exists (select 1 from pg_roles where rolname = '{r}') then create role {r} nologin; end if; end $$;\n" for r in roles))
sal.write_text(cab + cuerpo)
srv.cleanup()
print(f"[OK ] {sal} ({sal.stat().st_size // 1024} KB), roles: {roles}")
