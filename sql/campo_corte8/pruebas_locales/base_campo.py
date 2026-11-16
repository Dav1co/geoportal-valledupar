"""Base local del Corte 8 (reportes compartidos): los paquetes de campo de Comercial hasta la pasada del 14-nov (con sus 21 huellas vivas comprobadas), la base mínima
y el Corte 1 REAL de Técnica de planta, y el doble de redes.v_reportes_comercial (la vista vacía del 6b). Todo en un clúster local PROPIO (localhost:55434), sin Supabase.
«pgserver» es el sustituto de esta carpeta (crea la base en ese clúster en vez de bajar un PostgreSQL). Necesita psycopg (el Python de Anaconda lo trae).
Uso: CAMPO_DB=campo_local /opt/anaconda3/bin/python3 base_campo.py"""
import sys, pathlib, importlib.util
AQUI = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(AQUI))
CAMPO = pathlib.Path.home() / "geoportal-consultas" / "campo"
TEC = pathlib.Path.home() / "geoportal-consultas" / "tecnica"
def cargar(n, r):
    s = importlib.util.spec_from_file_location(n, r); m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
bl = cargar("bl", CAMPO / "paquete_pasada_14nov" / "pruebas_locales" / "base_local.py")
srv, uri, con = bl.preparar()
h = bl.huellas(con); bien = sum(h[k] == [v] for k, v in {**bl.HUELLAS_VIVAS, **bl.VISTA_VIVA}.items())
assert bien == len(bl.HUELLAS_VIVAS) + len(bl.VISTA_VIVA), f"huellas vivas: {bien}"
con.execute((CAMPO / "paquete_pasada_14nov" / "campo_sql" / "migracion_campo_p14_editor.sql").read_text())
con.execute((AQUI / "base_tecnica_minima.sql").read_text())
con.execute((TEC / "corte1_paso_a" / "migracion_corte1_completa.sql").read_text())
con.execute("""
  -- como en producción: «Revisiones generales» está activa (campo/activar_formatos_d_y_revision_editor.sql)
  update campo.tipos_reporte set activo = true where codigo = 'revision_previa';
  update campo.grupos_reporte set activo = true where codigo = 'facturacion';
  -- doble de redes: la vista vacía que dejó el Corte 6b
  create schema if not exists redes;
  create view redes.v_reportes_comercial as
  select null::text as codigo, null::text as tipo, null::text as subtipo, null::text as area, null::boolean as con_contrato, null::text as estado,
         null::timestamptz as registrado_en, null::numeric(9, 6) as lat, null::numeric(9, 6) as lon where false;
  revoke all on table redes.v_reportes_comercial from public, anon, authenticated, service_role;
  -- los topes de producción para las llamadas simuladas de la Edge
  do $$ begin if not exists (select 1 from pg_roles where rolname = 'authenticator') then create role authenticator noinherit; end if; end $$;
  alter role authenticator set lock_timeout = '8s';
  alter role service_role set statement_timeout = '30s';
""")
print(f"base lista: {uri} · huellas vivas {bien} de {bien} · {con.execute('select count(*) from campo.tipos_reporte').fetchone()[0]} tipos")
con.close()
