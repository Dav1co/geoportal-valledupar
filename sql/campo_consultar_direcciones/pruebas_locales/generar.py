#!/usr/bin/env python3
"""[Code A] Genera los _editor del paquete «Consultar direcciones» (25-nov) desde ../sql y un doble local de producción. NUNCA Supabase.
El doble: el del registro flexible (generar.rehacer de campo_registro_flexible: catálogo de producción + Investigación y Análisis + estructura real de
reportes, reporte_fotos y auditoría) + la migración PUBLICADA del registro flexible = huella de campo 66496328…, la de producción hoy. Encima se alinean
catastro_valledupar y cartera_suscripcion con lo que el paquete lee y lo que el ensayo escribe (columnas, NOT NULL e índices por contrato del paso 0 del 25-nov).
Uso: python3 -I generar.py [-h]"""
import sys, json, hashlib, pathlib, importlib.util
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent; SQL = PAQ / "sql"
RF = PAQ.parent / "campo_registro_flexible"
_s = importlib.util.spec_from_file_location("gn0", RF / "pruebas_locales/generar.py"); gn0 = importlib.util.module_from_spec(_s); _s.loader.exec_module(gn0)
HL0 = json.loads((RF / "pruebas_locales/huellas_locales.json").read_text())
NOMBRE = "campo_consultar_direcciones"
HUELLA = gn0.HUELLA; EST_EXPR = gn0.EST_EXPR; SINWHERE = gn0.SINWHERE; PERMISOS = gn0.PERMISOS; lit = gn0.lit; poner = gn0.poner
PUBLICADA = {"campo": "66496328d10a5b25eb01e572edae7cda", "acta": "111506c690249ad3b56ebf572566434c"}
TECNICA_PRODUCCION = gn0.TECNICA_PRODUCCION
# Paso 0 del 25-nov (23:25): estructura de producción de las tablas que el paquete toca (iguales en el doble tras alinear; se comprueba)
EST_PROD = {"campo.consultas_analisis": "1202c7e6e2999e2d5adaccd2e371320d", "campo.parametros": "fd9322f0721b931e71fa96b3010ed6f8",
            "campo.reporte_registro": "6bbcd353497807cfff9d4b0b5722da93"}
TABLAS_NUEVAS = ["campo.reporte_direccion_contrato"]
ALINEAR = """
alter table public.catastro_valledupar add column if not exists act_eco text, add column if not exists unih text, add column if not exists uninh text;
create index if not exists idx_catastro_cod_usuario on public.catastro_valledupar using btree (cod_usuario);
create sequence if not exists public.cartera_suscripcion_id_seq;
alter table public.cartera_suscripcion add column if not exists id bigint not null default nextval('public.cartera_suscripcion_id_seq'::regclass);
alter table public.cartera_suscripcion add column if not exists cargado_en timestamp with time zone not null default now();
alter table public.cartera_suscripcion alter column contrato set not null, alter column periodo_carga set not null;
do $$ begin if not exists (select 1 from pg_constraint where conname = 'cartera_suscripcion_pkey') then alter table public.cartera_suscripcion add constraint cartera_suscripcion_pkey primary key (id); end if; end $$;
"""
CONSULTAR = "public.geoportal_campo_analisis_contrato(text,text,text)"; OBSERVAR = "public.geoportal_campo_analisis_observar(text,text,text,text,text,jsonb,text)"
CREAR = gn0.CREAR_N; OBTENER = gn0.OBTENER; LISTAR = gn0.LISTAR; DPAGINA = gn0.DPAGINA; PDF = gn0.PDF
CAMBIAN = {"CONSULTAR": CONSULTAR, "OBSERVAR": OBSERVAR, "CREAR": CREAR, "OBTENER": OBTENER, "LISTAR": LISTAR, "DPAGINA": DPAGINA, "PDF": PDF}
NUEVAS_F = ["campo.f_texto_censo(text,boolean)", "campo.f_direcciones_contrato(text)", "public.geoportal_campo_direccion_contrato(text,text,text)",
            "public.geoportal_campo_tec_direccion_contrato(text,text,text)"]
RPC_NUEVAS = NUEVAS_F[2:]
FUNCIONES = [*CAMBIAN.values(), gn0.TEC_N, "campo.f_autorizar_reporte(text)", "campo.f_autorizar_analisis(text)", "campo.f_perfil(text)", "campo.f_tecnica_entrar(text,text)",
             "campo.f_param(text)", "campo.f_error(text,text)", "campo.f_error_limite(text)", "campo.f_texto_espera(timestamp with time zone,integer)", "campo.f_auditar(text,text,text,jsonb,text)",
             "campo.f_solo_agregar()", "campo.f_consultas_analisis_inmutable()", "campo.f_tipo_general(text)", "campo.f_autorizar_supervision(text)", "campo.f_autorizar_documento(text,text,uuid)", *PERMISOS]
PARTES = ["05_guardia.sql", "10_estructura.sql", "20_funciones.sql", "30_cambios.sql"]
lee = lambda n: (SQL / n).read_text()
CAB = "-- [Code A] CONSULTAR DIRECCIONES (25-nov) · {que} (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)\n"
def cuerpo(): return "\n".join(lee(n) for n in PARTES)

def rehacer(db):
    con = gn0.rehacer(db)
    con.execute(gn0.a_local((RF / "migracion_campo_registro_flexible_editor.sql").read_text(), HL0))
    con.execute(ALINEAR)
    h = con.execute(HUELLA["campo"]).fetchone()[0]
    if h != PUBLICADA["campo"]: raise SystemExit(f"El doble no tiene la huella de campo publicada: {h}")
    for t, m in EST_PROD.items(): assert est(con, t) == m, f"{t} del doble no es la de producción ({est(con, t)})"
    return con
def a_local(texto, hl): return gn0.a_local(texto, HL0)       # solo la huella de Técnica (campo.reportes no se compara en este paquete)
def md5f(con, f): return con.execute("select md5(pg_get_functiondef(to_regprocedure(%s)))", (f,)).fetchone()[0]
def defn(con, f): return con.execute("select pg_get_functiondef(to_regprocedure(%s))", (f,)).fetchone()[0].rstrip() + ";"
def est(con, t): return con.execute(f"select {EST_EXPR} from (select to_regclass(%s) as rel) z", (t,)).fetchone()[0]

def valores(con):
    for f, m in PERMISOS.items(): assert md5f(con, f) == m, f
    p = {"HUELLA_CAMPO": PUBLICADA["campo"], "HUELLA_ACTA": PUBLICADA["acta"], "HUELLA_TECNICA": TECNICA_PRODUCCION, "HUELLA_TECNICA_LOCAL": con.execute(HUELLA["tecnica"]).fetchone()[0],
         "HUELLA_CAMPO_Q": HUELLA["campo"], "HUELLA_ACTA_Q": HUELLA["acta"], "HUELLA_TECNICA_Q": HUELLA["tecnica"], "EST_EXPR": EST_EXPR, "SIN_WHERE_CAMPO": SINWHERE,
         "MD5_FUNCIONES": ", ".join(f"({lit(f)}, {lit(md5f(con, f))})" for f in FUNCIONES),
         "PERMISOS_IGUALES": " and ".join(f"md5(pg_get_functiondef(to_regprocedure({lit(f)}))) = {lit(m)}" for f, m in PERMISOS.items()),
         "RESPALDOS": "\n\n".join(defn(con, f) for f in CAMBIAN.values())}
    p["EST_LISTA"] = ", ".join(f"({lit(t)}, {lit(m)}, null::text)" for t, m in EST_PROD.items())
    p["EST_NUEVAS"] = "('campo.zz_ninguna', 'x')"; p["MD5_CAMBIAN_NUEVA"] = "('x', 'x')"
    with con.transaction(force_rollback=True):
        con.execute(a_local(poner(cuerpo(), p), None))
        p["HUELLA_CAMPO_NUEVA"] = con.execute(HUELLA["campo"]).fetchone()[0]
        assert con.execute(HUELLA["tecnica"]).fetchone()[0] == p["HUELLA_TECNICA_LOCAL"]; assert con.execute(HUELLA["acta"]).fetchone()[0] == p["HUELLA_ACTA"]
        p["MD5_NUEVA"] = {k: md5f(con, f) for k, f in CAMBIAN.items()}; p["MD5_NUEVAS_F"] = {f: md5f(con, f) for f in NUEVAS_F}
        p["MD5_CAMBIAN_NUEVA"] = ", ".join(f"({lit(f)}, {lit(p['MD5_NUEVA'][k])})" for k, f in CAMBIAN.items())
        p["EST_TABLAS_NUEVAS"] = {t: est(con, t) for t in TABLAS_NUEVAS}
        p["ESTADO_NUEVO"] = {t: est(con, t) for t in EST_PROD if est(con, t) != EST_PROD[t]}
        assert set(p["ESTADO_NUEVO"]) == {"campo.consultas_analisis"}, p["ESTADO_NUEVO"]
        con.execute(poner(lee("90_reversa.sql"), p))
        assert con.execute(HUELLA["campo"]).fetchone()[0] == p["HUELLA_CAMPO"], "la reversa no devuelve la huella"
        assert {t: est(con, t) for t in TABLAS_NUEVAS} == p["EST_TABLAS_NUEVAS"]
    p["EST_LISTA"] = ", ".join(f"({lit(t)}, {lit(m)}, {lit(p['ESTADO_NUEVO'][t]) if t in p['ESTADO_NUEVO'] else 'null::text'})" for t, m in EST_PROD.items())
    p["EST_NUEVAS"] = ", ".join(f"({lit(t)}, {lit(m)})" for t, m in p["EST_TABLAS_NUEVAS"].items())
    return p

def archivos(p):
    H = HUELLA
    huellas = f"""-- Solo lectura. ANTES: 1, 2 y 3 «PUBLICADA». DESPUÉS: 1 «CON ESTE CAMBIO» (anótela); 2 y 3 igual (este paquete no las cambia).
select o, k, v, estado from (
  select 1 as o, '1 funciones de campo (conjunto, todas)' as k, ({H["campo"]}) as v,
         case ({H["campo"]}) when '{p["HUELLA_CAMPO"]}' then 'PUBLICADA (25-nov, registro flexible): lista para este cambio' when '{p["HUELLA_CAMPO_NUEVA"]}' then 'CON ESTE CAMBIO' else 'OTRA: deténgase y avise' end as estado
  union all
  select 2, '2 funciones del acta (conjunto)', ({H["acta"]}), case ({H["acta"]}) when '{p["HUELLA_ACTA"]}' then 'PUBLICADA (no cambia con este paquete)' else 'OTRA: deténgase y avise' end
  union all
  select 3, '3 funciones de Técnica (conjunto)', ({H["tecnica"]}), case ({H["tecnica"]}) when '{p["HUELLA_TECNICA"]}' then 'PUBLICADA (no cambia con este paquete)' else 'OTRA: deténgase y avise' end
) t order by o;
"""
    def fila(n, k, cond): return f"  select {n} as o, {lit(k)} as k, case when {cond} then 'OK' else 'FALLA' end as estado"
    api = lambda f: f"has_function_privilege('service_role', {lit(f)}, 'execute') and not has_function_privilege('anon', {lit(f)}, 'execute') and not has_function_privilege('authenticated', {lit(f)}, 'execute')"
    T = "campo.reporte_direccion_contrato"
    filas = [
        fila(1, "1 la huella de campo es la de este cambio", f"({H['campo']}) = '{p['HUELLA_CAMPO_NUEVA']}'"),
        fila(2, "2 la huella del acta no cambió", f"({H['acta']}) = '{p['HUELLA_ACTA']}'"),
        fila(3, "3 la huella de Técnica no cambió", f"({H['tecnica']}) = '{p['HUELLA_TECNICA']}'"),
        fila(4, "4 las 7 funciones que cambian son las de este cambio", " and ".join(f"md5(pg_get_functiondef(to_regprocedure({lit(f)}))) = {lit(p['MD5_NUEVA'][k])}" for k, f in CAMBIAN.items())),
        fila(5, "5 las 4 funciones nuevas existen con su md5", " and ".join(f"md5(pg_get_functiondef(to_regprocedure({lit(f)}))) = {lit(m)}" for f, m in p["MD5_NUEVAS_F"].items())),
        fila(6, "6 las RPC nuevas y cambiadas, solo para service_role; las 2 internas, para nadie de la API",
             " and ".join(api(f) for f in [*RPC_NUEVAS, CONSULTAR, OBSERVAR, CREAR, OBTENER, LISTAR, DPAGINA, PDF]) + " and "
             + " and ".join(f"not has_function_privilege({lit(r)}, {lit(f)}, 'execute')" for f in NUEVAS_F[:2] for r in ("anon", "authenticated", "service_role"))),
        fila(7, f"7 {T}: llave reporte_id, RLS sin políticas, sin permisos para la API, SELECT (solo) para homelab_lectura y solo inserción",
             f"(select relrowsecurity from pg_class where oid = '{T}'::regclass) and (select pg_get_constraintdef(oid) from pg_constraint where conrelid = '{T}'::regclass and contype = 'p') = 'PRIMARY KEY (reporte_id)' "
             "and not exists (select 1 from pg_policies where schemaname in ('campo', 'acta')) "
             + "".join(f"and not has_table_privilege('{r}', '{T}', '{x}') " for r in ("anon", "authenticated", "service_role") for x in ("select", "insert", "update", "delete"))
             + f"and has_table_privilege('homelab_lectura', '{T}', 'select') and not has_table_privilege('homelab_lectura', '{T}', 'insert') "
             f"and (select string_agg(tgname || ':' || tgfoid::regproc::text || ':' || tgtype, ',' order by tgname) from pg_trigger where tgrelid = '{T}'::regclass and not tgisinternal) "
             "= (select string_agg(tgname || ':' || tgfoid::regproc::text || ':' || tgtype, ',' order by tgname) from pg_trigger where tgrelid = 'campo.reporte_fotos'::regclass and not tgisinternal)"),
        fila(8, "8 la estructura de la tabla nueva y de campo.consultas_analisis (con via) es la de este cambio",
             " and ".join(f"(select {EST_EXPR} from (select to_regclass({lit(t)}) as rel) z) = {lit(m)}" for t, m in {**p["EST_TABLAS_NUEVAS"], **p["ESTADO_NUEVO"]}.items())),
        fila(9, "9 la bitácora: via por omisión «analisis» y lo de antes quedó como analisis",
             "exists (select 1 from information_schema.columns where table_schema = 'campo' and table_name = 'consultas_analisis' and column_name = 'via' and column_default = '''analisis''::text' and is_nullable = 'NO') "
             "and has_column_privilege('homelab_lectura', 'campo.consultas_analisis', 'via', 'select')"),
        fila(10, "10 el parámetro limite_direccion_hora existe (consultas, de 1 a 1000)", "exists (select 1 from campo.parametros where clave = 'limite_direccion_hora' and unidad = 'consultas' and minimo = 1 and maximo = 1000 and valor between 1 and 1000)"),
        fila(11, "11 campo.reporte_registro y campo.parametros (estructura) no cambiaron",
             " and ".join(f"(select {EST_EXPR} from (select to_regclass({lit(t)}) as rel) z) = {lit(EST_PROD[t])}" for t in ("campo.reporte_registro", "campo.parametros"))),
        fila(12, "12 las 4 funciones de permisos vivas no cambiaron", p["PERMISOS_IGUALES"]),
        fila(13, "13 ninguna función de campo con DELETE o UPDATE sin WHERE", SINWHERE + " = 0"),
        fila(14, "14 redes.f_funciones_sin_where() devuelve cero filas", "(select count(*) from redes.f_funciones_sin_where()) = 0"),
    ]
    ver = "select o, k, estado from (\n" + "\n  union all\n".join(filas) + "\n) t order by o;\n"
    return {f"migracion_{NOMBRE}_editor.sql": CAB.format(que="MIGRACIÓN") + "begin;\n" + poner(cuerpo(), p) + "\ncommit;\n",
            f"ensayo_en_transaccion_{NOMBRE}_editor.sql": CAB.format(que="ENSAYO (termina en ERROR esperado; no deja nada)") + "begin;\n" + poner(lee("70_pruebas.sql"), p) + "\nrollback;\n",
            f"reversa_{NOMBRE}_editor.sql": CAB.format(que="REVERSA") + "begin;\n" + poner(lee("90_reversa.sql"), p) + "\ncommit;\n",
            f"huellas_solo_lectura_{NOMBRE}_editor.sql": CAB.format(que="HUELLAS (solo lectura; ANTES y DESPUÉS)") + huellas,
            f"verificacion_{NOMBRE}_editor.sql": CAB.format(que=f"VERIFICACIÓN (solo lectura; después de la migración: {len(filas)} de {len(filas)} OK)") + ver}, len(filas)

def main():
    con = rehacer("emdupar_a_rf_dirgen")
    p = valores(con); con.close()
    p["CUERPO_MIGRACION"] = poner(cuerpo(), p); p["CUERPO_REVERSA"] = poner(lee("90_reversa.sql"), p)
    salida, n = archivos(p)
    for nombre, t in salida.items():
        assert "on commit drop" not in t.lower(), nombre
        (PAQ / nombre).write_text(t); print(f"[OK ] {nombre}  md5 {hashlib.md5(t.encode()).hexdigest()}")
    (AQUI / "huellas_locales.json").write_text(json.dumps({"partida": {"HUELLA_CAMPO": p["HUELLA_CAMPO"], "HUELLA_TECNICA_LOCAL": p["HUELLA_TECNICA_LOCAL"]},
        "nuevas": {"HUELLA_CAMPO_NUEVA": p["HUELLA_CAMPO_NUEVA"], "MD5_NUEVA": p["MD5_NUEVA"], "FUNCIONES_NUEVAS": p["MD5_NUEVAS_F"], "TABLAS_NUEVAS": p["EST_TABLAS_NUEVAS"],
                   "ESTRUCTURA_NUEVA": p["ESTADO_NUEVO"]}, "verificacion": n}, indent=1, ensure_ascii=False))
    print(json.dumps({"HUELLA_CAMPO_NUEVA": p["HUELLA_CAMPO_NUEVA"], "verificacion": n}, indent=1))

if __name__ == "__main__":
    main()
