"""Pruebas de mutación del Reparto de facturas, commit 1 (clúster 55432 del Code A; NUNCA Supabase).
A. Código: cada mutación rompe UNA regla en el texto del ensayo generado; el ensayo debe terminar con FALLAS y nombrar la prueba que la cuida.
B. Guardia: cada mutación cambia algo vivo en una copia de la base; la migración debe negarse con su mensaje de guardia.
Usa el ensayo y la migración ya generados (correr antes generar.py o correr_local.py). Escribe resultados_mutaciones.txt junto al paquete.
Uso: python3 -I mutar.py [-h]"""
import sys, pathlib, re, os, subprocess
if __name__ == "__main__":
    for a in sys.argv[1:]:
        if a in ("-h", "--help"): print(__doc__); sys.exit(0)
        print(f"Opción desconocida: {a}\n{__doc__}", file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent; PAQ = AQUI.parent
sys.path.insert(0, str(AQUI)); import generar as g
ENSAYO = (PAQ / f"ensayo_en_transaccion_{g.NOMBRE}_editor.sql").read_text()
MIGRACION = (PAQ / f"migracion_{g.NOMBRE}_editor.sql").read_text()

# (nombre, texto original, texto mutado, prueba que debe fallar)
CODIGO = [
  ("sin la regla de una sola entrega por factura",
   "  v_vig := reparto.f_entrega_vigente(v_c, v_per, v_desde);", "  v_vig := null;", "03.03"),
  ("el calendario toma un período cuya fecha de reparto aún no llega",
   "     and reparto.f_fecha(v.etapas ->> 'reparto') <= reparto.f_hoy()\n", "     and reparto.f_fecha(v.etapas ->> 'reparto') is not null\n", "01.05"),
  ("la entrega de respaldo posterior a la fecha de reparto no cuenta",
   "then e.periodo_reparto = p_periodo or (e.periodo_reparto is null and e.registrado_en >= (p_desde::timestamp at time zone 'America/Bogota'))",
   "then e.periodo_reparto = p_periodo", "08.05"),
  ("una entrega de otro período cuenta como entregada",
   "then e.periodo_reparto = p_periodo or (e.periodo_reparto is null", "then e.periodo_reparto is not null or (e.periodo_reparto is null", "08.04"),
  ("sin ciclo de calendario no toma el mes del día",
   "      v_per := to_char(reparto.f_hoy(), 'YYYYMM'); v_desde := date_trunc('month', reparto.f_hoy())::date;", "      v_per := null; v_desde := null;", "12.04"),
  ("el calendario no entra en la fuente de la jornada",
   "    v_fuente := v_fuente || '|' || coalesce(v_rep.periodo, 'respaldo');", "    v_fuente := v_fuente;", "12.06"),
  ("el Dell también lee una vista",
   "                reparto.jornadas, reparto.jornada_items, reparto.entregas, reparto.entregas_anuladas to homelab_lectura;",
   "                reparto.jornadas, reparto.jornada_items, reparto.entregas, reparto.entregas_anuladas, reparto.v_entregas to homelab_lectura;", "10.09"),
  ("sin la idempotencia del toque (uuid)",
   "  select e.id, e.consecutivo, e.contrato, e.autor, e.registrado_en into v_prev from reparto.entregas e where e.id_cliente = p_id_cliente;\n  if found then\n    if v_prev.autor <> v_email then perform reparto.f_err('Identificador de toque no válido'); end if;\n    return",
   "  select e.id, e.consecutivo, e.contrato, e.autor, e.registrado_en into v_prev from reparto.entregas e where e.id_cliente = p_id_cliente and false;\n  if found then\n    if v_prev.autor <> v_email then perform reparto.f_err('Identificador de toque no válido'); end if;\n    return", "03.02"),
  ("el empate sin consecutivo_predio",
   "select array_agg(x.contrato order by x.cr nulls last, x.cp nulls last, x.contrato) into v_lista", "select array_agg(x.contrato order by x.cr nulls last, x.contrato) into v_lista", "02.02"),
  ("el repartidor sin exigir la actividad reparto",
   "  if not (campo.f_persona_comercial(v_email) and exists (select 1 from campo.f_actividades_persona(v_email) a where a.codigo = 'reparto')) then",
   "  if not campo.f_persona_comercial(v_email) then", "00.04"),
  ("el repartidor anula las de otros",
   "  if not v_sup and (v_e.autor <> v_email or (v_e.registrado_en at time zone 'America/Bogota')::date <> reparto.f_hoy()) then",
   "  if not v_sup and (v_e.registrado_en at time zone 'America/Bogota')::date <> reparto.f_hoy() then", "04.02"),
  ("saltado mal calculado (<=)",
   "(not i.entregada and i.orden_lectura < coalesce(m.maximo, 0))", "(not i.entregada and i.orden_lectura <= coalesce(m.maximo, 0) + 1)", "03.05"),
  ("el archivo sin revisar repetidos",
   "              where c.contrato is not null and exists (select 1 from c c2 where c2.contrato = c.contrato and c2.fila < c.fila)",
   "              where false", "06.04"),
  ("se entrega en una lista de otro día",
   "  if v_j.fecha <> reparto.f_hoy() then", "  if false then", "08.01"),
  ("el consecutivo se reutiliza al anular",
   "  select coalesce(max(e.consecutivo), 0) + 1 into v_cons from reparto.entregas e where e.jornada_id = p_jornada;",
   "  select count(*) + 1 into v_cons from reparto.entregas e where e.jornada_id = p_jornada and not exists (select 1 from reparto.entregas_anuladas a where a.entrega_id = e.id);", "04.06"),
  ("el archivo anulado se sigue usando",
   "  if v_j.lote_id is not null and exists (select 1 from reparto.lotes_anulados a where a.lote_id = v_j.lote_id) then", "  if false then", "06.11"),
  ("se entrega sin GPS",
   "  if p_lon is null or p_lat is null or p_precision_m is null then perform", "  if false then perform", "03.08"),
  ("una RPC ejecutable por authenticated",
   "    execute format('grant execute on function %s to service_role', f.firma);", "    execute format('grant execute on function %s to service_role, authenticated', f.firma);", "10.01"),
]
# (nombre, SQL que cambia lo vivo en la copia, mensaje de la guardia)
GUARDIA = [
  ("la vista del calendario cambió", "create or replace view scrr.v_calendario_vigente as select distinct on (periodo, ciclo) periodo, ciclo, pago_oportuno, fecha_suspension, etapas, motivo, autor, vigente_desde from scrr.calendario_ciclos order by periodo, ciclo, vigente_desde;",
   "scrr.v_calendario_vigente no existe o su definición cambió"),
  ("el calendario tiene un CHECK más", "alter table scrr.calendario_ciclos add constraint zt_ck check (ciclo < 90);", "las restricciones o el disparador de solo inserción de scrr.calendario_ciclos"),
  ("una función de campo que se llama cambió", "create or replace function campo.f_verificar(p_solicitante text, p_modo text) returns text language plpgsql security definer set search_path to 'public', 'campo', 'pg_temp' as $f$ begin return lower(p_solicitante); end $f$;",
   "campo.f_verificar(text,text) no está o cambió"),
  ("la vista de rutas cambió de definición", "create or replace view bi.v_rutas_geoportal as select contrato, periodo as periodo_carga, ciclo, ruta, consecutivo_ruta, consecutivo_predio from hechos.rutas_consecutivos;",
   "la definición de bi.v_rutas_geoportal cambió"),
  ("la tabla de rutas tiene un CHECK que el doble no tenía", "alter table hechos.rutas_consecutivos add constraint zt_ck check (length(contrato) < 20);",
   "tiene disparadores o restricciones"),
  ("la tabla de rutas tiene un NOT NULL", "alter table hechos.rutas_consecutivos alter column periodo set not null;", "las columnas de hechos.rutas_consecutivos"),
  ("cartera_suscripcion con una columna más", "alter table public.cartera_suscripcion add column zt text;", "las columnas de public.cartera_suscripcion"),
  ("la actividad reparto no existe", "alter table campo.actividades disable trigger user; update campo.actividades set activa = false where codigo = 'reparto';", "la actividad «reparto» no existe o no está activa"),
]

def corre(base, texto):
    r = subprocess.run([g.PSQL, "-X", "-d", base], input=texto, capture_output=True, text=True, env=g.ENV)
    return r.stdout + r.stderr

def main():
    salida = []; fallas = 0
    def log(s): print(s); salida.append(s)
    for nombre, a, b, prueba in CODIGO:
        assert ENSAYO.count(a) == 1, f"la mutación «{nombre}» no encuentra su texto"
        base = g.base_nueva(f"reparto_mut_{os.getpid()}")
        try:
            out = corre(base, ENSAYO.replace(a, b))
        finally:
            g.borrar_mia(base)
        m = re.search(r"RESULTADO: (\d+) de (\d+) pruebas correctas — (SIN FALLAS|FALLAS:)", out)
        atrapada = bool(m) and m.group(3) == "FALLAS:" and re.search(r"\n" + re.escape(prueba) + r" ", out[out.index("FALLAS:"):]) is not None
        fallas += not atrapada
        log(f"[{'ATRAPADA' if atrapada else 'NO ATRAPADA'}] {nombre} → {m.group(0) if m else 'sin resultado: ' + out[-300:]} (debe fallar la {prueba})")
    for nombre, cambio, mensaje in GUARDIA:
        base = g.base_nueva(f"reparto_mut_{os.getpid()}")
        try:
            pre = corre(base, "begin;\n" + cambio + "\ncommit;\n")
            assert "ERROR" not in pre, pre[-500:]
            out = corre(base, MIGRACION)
            quedo = g.valor(base, "select (to_regnamespace('reparto') is null)::text")
        finally:
            g.borrar_mia(base)
        atrapada = "GUARDIA REPARTO" in out and mensaje in out and quedo == "true"
        fallas += not atrapada
        msj = re.search(r"GUARDIA REPARTO[^\n]*", out); msj = msj.group(0)[:200] if msj else out[-200:]
        log(f"[{'SE NIEGA' if atrapada else 'NO SE NEGÓ'}] guardia: {nombre} → {msj}")
    log(f"MUTACIONES: {len(CODIGO) + len(GUARDIA) - fallas} de {len(CODIGO) + len(GUARDIA)} atrapadas" + (" — SIN FALLAS" if not fallas else " — HAY FALLAS"))
    (PAQ / "resultados_mutaciones.txt").write_text("\n".join(salida) + "\n")
    sys.exit(1 if fallas else 0)

if __name__ == "__main__":
    main()
