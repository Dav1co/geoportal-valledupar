"""[Code B] Pruebas locales del paquete «Investigación de ubicación recortada y avisos del Análisis de contrato» (23-nov).
Clúster del Code B (55442), bases emdupar_b_inv_prueba*, cada una rehecha como copia exacta de producción (rehacer_doble.py). NUNCA Supabase.
Recorre: huellas ANTES → ensayo (ERROR esperado, N de N) → migración → verificación → huellas DESPUÉS → repetir (rechazo) → registros reales
→ reversa → huellas de vuelta → los registros quedan → repetir reversa (rechazo) → volver a aplicar → verificación.
Guardias (cada una en una base nueva): función de campo distinta, estructura distinta, Investigación distinta, con registros.
Mutación: el ensayo debe FALLAR si preparar_subida se escribe mal. Escribe ../resultados_locales.txt.
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
leer = lambda n: (PAQ / n).read_text()
def correr(con, t):
    try: con.execute(t); return None
    except Exception as e:
        try: con.execute("rollback")
        except Exception: pass
        return "\n".join(l for l in str(e).splitlines() if not l.startswith("CONTEXT"))
def huella(con, k): return con.execute(gn.CONJ[k]).fetchone()[0]
def ver(con): return con.execute(leer(f"verificacion_{N}_editor.sql")).fetchall()
def hl(con): return con.execute(leer(f"huellas_solo_lectura_{N}_editor.sql")).fetchall()
def ensayo(con, texto=None):
    t0 = time.time(); e = correr(con, texto or leer(f"ensayo_en_transaccion_{N}_editor.sql")); dt = time.time() - t0
    m = re.search(r"RESULTADO: (\d+) de (\d+) pruebas correctas( — SIN FALLAS)?", e or ""); return e, m, dt
def inv(con, quien, datos):
    """Registra una Investigación real (sin fotos) en la base, como service_role."""
    con.execute("insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo) "
                "values (%s, 'C', 'consulta', true, 'sin_restriccion', 'todos', false, true, false) on conflict do nothing", (quien,))
    with con.transaction():
        con.execute("set local role service_role")
        p = con.execute("select public.geoportal_campo_preparar_subida(%s, 0, 'campo', null, 'investigacion_ubicacion')", (quien,)).fetchone()[0]
        return con.execute("select public.geoportal_campo_crear_reporte(%s, %s::uuid, 'investigacion_ubicacion', null, '[PRUEBA ZTINV] ciclo', '123456', 10.46, -73.25, 5, false, 'campo', '[]'::jsonb, null, %s::jsonb, null, null, null)",
                           (quien, p["reporte_id"], json.dumps(datos))).fetchone()[0]

def inv_produccion(con, quien):
    """Registra una Investigación como la pide HOY producción (3 fotos con su etiqueta, resultado efectivo y hallazgo)."""
    con.execute("insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_campo, ver_dashboard_campo) "
                "values (%s, 'C', 'consulta', true, 'sin_restriccion', 'todos', false, true, false) on conflict do nothing", (quien,))
    with con.transaction():
        con.execute("set local role service_role")
        p = con.execute("select public.geoportal_campo_preparar_subida(%s, 3, 'campo', null, 'investigacion_ubicacion')", (quien,)).fetchone()[0]
        con.execute("reset role")
        fotos = []
        for i, (f, etq) in enumerate(zip(p["fotos"], ["fachada_nomenclatura", "predio_lote", "vecino_referencia"]), 1):
            con.execute("insert into storage.objects (bucket_id, name, metadata) values ('campo-fotos', %s, '{\"size\": 300000, \"mimetype\": \"image/jpeg\"}')", (f["ruta"],))
            fotos.append({"orden": i, "ruta": f["ruta"], "etiqueta": etq})
        con.execute("set local role service_role")
        return con.execute("select public.geoportal_campo_crear_reporte(%s, %s::uuid, 'investigacion_ubicacion', null, '[PRUEBA ZTINV] guardia', '123456', 10.46, -73.25, 5, false, 'campo', %s::jsonb, null, '{\"hallazgo\": \"ubicado\"}'::jsonb, 'efectivo', null, null)",
                           (quien, p["reporte_id"], json.dumps(fotos))).fetchone()[0]

def main():
    out("PRUEBAS LOCALES · [Code B] Investigación de ubicación recortada y avisos del Análisis de contrato (23-nov) · clúster 55442"); out("")
    con = gn.rehacer("emdupar_b_inv_prueba")
    ok("B.01 la base local es copia exacta de producción (163 de 163) y trae sus huellas (campo 261bed3c…, acta 111506c6…)",
       huella(con, "campo") == gn.PUBLICADA["campo"] and huella(con, "acta") == gn.PUBLICADA["acta"])
    h = hl(con); ok("B.02 huellas de solo lectura ANTES: PUBLICADA", h[0][3].startswith("PUBLICADA") and h[1][3].startswith("PUBLICADA") and h[2][3] == "PUBLICADA", str(h))
    e, m, dt = ensayo(con); out(e or "[sin error: MAL]")
    ok(f"E.01 el ensayo termina en el ERROR esperado con «N de N … SIN FALLAS» ({dt:.1f} s)", m is not None and m.group(1) == m.group(2) and m.group(3) is not None, (e or "")[:400])
    if m: TOT[0] += int(m.group(2)); TOT[1] += int(m.group(1))
    ok("E.02 el ensayo no dejó nada (huella igual, catálogo igual, sin filas ZTINV ni auditoría)", huella(con, "campo") == gn.PUBLICADA["campo"]
       and con.execute(gn.INV_CAMPOS_Q).fetchone()[0] == HL["inv"]["partida_campos"]
       and con.execute("select not exists (select 1 from public.geoportal_lista_blanca where email like 'ztinv.%%') and not exists (select 1 from public.geoportal_auditoria where detalle ->> 'paquete' = 'campo_inv_analisis')"
                       " and not exists (select 1 from campo.reportes where descripcion like '[PRUEBA ZTINV]%%')"
                       " and to_regclass('campo.analisis_observaciones') is null and not exists (select 1 from campo.derivadas_catalogo where codigo like 'aviso\\_%%')"
                       " and not exists (select 1 from information_schema.columns where table_schema = 'campo' and table_name = 'derivadas' and column_name = 'observacion_id')").fetchone()[0])
    e = correr(con, leer(f"migracion_{N}_editor.sql")); ok("C.01 migración", e is None, e)
    v = ver(con); ok(f"C.02 verificación {sum(1 for x in v if x[2] == 'OK')} de {len(v)} OK", len(v) == HL["verificacion"] and all(x[2] == "OK" for x in v), str([x for x in v if x[2] != "OK"]))
    h = hl(con); ok("C.03 huellas DESPUÉS: CON ESTE CAMBIO; acta igual", h[0][3] == "CON ESTE CAMBIO" and h[1][3].startswith("PUBLICADA") and h[2][3] == "CON ESTE CAMBIO", str(h))
    e = correr(con, leer(f"migracion_{N}_editor.sql")); ok("C.04 repetir la migración se rechaza", e is not None and "ya parece aplicado" in e, (e or "")[:200])
    e = correr(con, leer(f"ensayo_en_transaccion_{N}_editor.sql")); ok("C.05 el ensayo sobre una base ya migrada se detiene en la guardia", e is not None and "ya parece aplicado" in e, (e or "")[:200])
    r1 = inv(con, "ciclo.op1@emdupar.gov.co", {"direccion_encontrada": "[PRUEBA ZTINV] CRA 1", "barrio": "[PRUEBA ZTINV] Centro", "tipo_predio": "casa"})
    ok("C.06 con la migración aplicada se registra una Investigación sin fotos con barrio y tipo de predio", r1.get("id") is not None, str(r1))
    e = correr(con, leer(f"reversa_{N}_editor.sql")); ok("C.07 reversa", e is None, e)
    ok("C.08 tras la reversa: huella de campo 261bed3c…, preparar_subida publicada, Investigación como en producción (los 4 nuevos desactivados)",
       huella(con, "campo") == gn.PUBLICADA["campo"] and gn.md5f(con, gn.PREPARAR) == HL["partida"]["MD5_PREPARAR"]
       and con.execute(gn.INV_CAMPOS_Q).fetchone()[0] == HL["inv"]["tras_reversa_campos"] and con.execute(gn.INV_FOTOS_Q).fetchone()[0] == HL["inv"]["partida_fotos"]
       and con.execute("select genera_resultado and fotos_min = 3 from campo.tipos_reporte where codigo = 'investigacion_ubicacion'").fetchone()[0]
       and all(gn.md5f(con, f) == HL["partida"]["MD5_" + k] for k, f in gn.CAMBIAN.items() if "MD5_" + k in HL["partida"]))
    ok("C.08b tras la reversa: las 6 funciones nuevas ya no están; las tablas y las columnas se conservan; los 5 códigos quedan desactivados",
       con.execute("select bool_and(to_regprocedure(f) is null) from unnest(%s::text[]) f", (gn.NUEVAS_F,)).fetchone()[0]
       and con.execute("select to_regclass('campo.analisis_observacion_datos') is not null and exists (select 1 from information_schema.columns where table_schema = 'campo' and table_name = 'derivadas' and column_name = 'observacion_id')"
                       " and (select count(*) from campo.derivadas_catalogo where codigo in ('aviso_desocupado', 'aviso_direccion_errada', 'aviso_actualizacion_datos', 'aviso_otra', 'actividad_supervisor') and not activa) = 5").fetchone()[0])
    ok("C.09 el registro hecho con los campos nuevos se conserva con sus datos (nada se borra)",
       con.execute("select datos ->> 'barrio' = '[PRUEBA ZTINV] Centro' and datos ->> 'tipo_predio' = 'casa' from campo.reportes where id = %s", (r1["id"],)).fetchone()[0])
    e = correr(con, leer(f"reversa_{N}_editor.sql")); ok("C.10 repetir la reversa se rechaza", e is not None and "no es la de este paquete" in e, (e or "")[:200])
    e = correr(con, leer(f"migracion_{N}_editor.sql")); v = ver(con)
    ok("C.11 volver a aplicar después de la reversa, con el registro hecho en medio, funciona y verifica todo OK", e is None and all(x[2] == "OK" for x in v), f"{e} {v}")
    con.close()

    # Volver a aplicar sobre una reversa SIN registros (los 4 campos nuevos desactivados se reactivan, no se duplican)
    con = gn.rehacer("emdupar_b_inv_prueba")
    e1 = correr(con, leer(f"migracion_{N}_editor.sql")); e2 = correr(con, leer(f"reversa_{N}_editor.sql")); e3 = correr(con, leer(f"migracion_{N}_editor.sql"))
    v = ver(con)
    ok("C.12 migrar → revertir → migrar sin registros: los 4 campos se reactivan sin duplicarse y la verificación da todo OK",
       e1 is None and e2 is None and e3 is None and all(x[2] == "OK" for x in v)
       and con.execute("select count(*) from campo.tipo_campos c join campo.tipos_reporte t on t.id = c.tipo_id where t.codigo = 'investigacion_ubicacion'").fetchone()[0] == 11, f"{e1} {e2} {e3} {v}")
    ok("C.13 la auditoría guarda las tres pasadas (migración, reversa, migración)",
       con.execute("select count(*) from public.geoportal_auditoria where accion = 'campo_catalogo' and detalle ->> 'paquete' = 'campo_inv_analisis'").fetchone()[0] == 3)
    con.close()

    # Con un aviso guardado, la reversa se detiene sin cambiar nada (las funciones publicadas dejarían filas vacías en la lista)
    con = gn.rehacer("emdupar_b_inv_prueba"); e = correr(con, leer(f"migracion_{N}_editor.sql"))
    con.execute("insert into public.geoportal_lista_blanca (email, nombre, rol, activo, horario, dias, ver_explorar, ver_analisis_contrato) values ('ciclo.ana@emdupar.gov.co', 'C', 'consulta', true, 'sin_restriccion', 'todos', false, true)")
    con.execute("insert into campo.consultas_analisis (autor, contrato, existe) values ('ciclo.ana@emdupar.gov.co', '880001', true)")
    with con.transaction():
        con.execute("set local role service_role")
        ra = con.execute("select public.geoportal_campo_analisis_observar('ciclo.ana@emdupar.gov.co', '880001', 'actualizacion_datos', null, null, '{\"cedula\": \"12345678\"}'::jsonb)").fetchone()[0]
    h0 = huella(con, "campo"); e2 = correr(con, leer(f"reversa_{N}_editor.sql"))
    ok("R.01 con un aviso guardado, la reversa se detiene y no cambia nada", e is None and ra.get("derivada_id") and e2 is not None and "Hay 1 avisos" in e2 and huella(con, "campo") == h0 == HL["nuevas"]["HUELLA_CAMPO_NUEVA"], (e2 or "")[:250])
    ok("R.02 la verificación sigue 100 % OK después de la reversa rechazada", all(x[2] == "OK" for x in ver(con)))
    con.close()

    # Guardias: cada una en una base nueva, con un cambio que imita una producción distinta
    casos = [
        ("G.01 una función de campo distinta (comentario en f_validar_datos)",
         "create or replace function campo.f_validar_datos_zt() returns int language sql as $$ select 1 $$", "Las funciones de campo no son las publicadas"),
        ("G.02 una columna de más en campo.tipo_fotos", "alter table campo.tipo_fotos add column zt_extra text", "La estructura de campo.tipo_fotos no es la de producción"),
        ("G.03 un permiso de más en campo.derivadas", "grant select on campo.derivadas to anon", "La estructura de campo.derivadas no es la de producción"),
        ("G.04 la Investigación con otro mínimo de fotos", "update campo.tipos_reporte set fotos_min = 4 where codigo = 'investigacion_ubicacion'", "La Investigación de ubicación no está como en producción"),
        ("G.05 la Investigación con una foto ya opcional", "update campo.tipo_fotos set obligatoria = false where codigo = 'vecino_referencia' and tipo_id = 35", "Las fotos de la Investigación no son las de producción"),
        ("G.06 la Investigación sin su actividad", "update campo.actividades set activa = false where codigo = 'investigacion_ubicacion'", "La actividad investigacion_ubicacion no está activa"),
        ("G.08 una política RLS en campo", "create policy zt on campo.parametros for select to homelab_lectura using (true)", "Hay políticas RLS en campo o acta"),
        ("G.09 homelab_lectura sin BYPASSRLS", "alter role homelab_lectura nobypassrls", "No existe el rol homelab_lectura con BYPASSRLS"),
        ("G.10 una tabla campo.analisis_observaciones que no es la del paquete", "create table campo.analisis_observaciones (id uuid primary key)", "La tabla campo.analisis_observaciones ya existe y no es la de este paquete"),
        ("G.11 una columna observacion_id ajena en campo.derivadas", "alter table campo.derivadas add column observacion_id uuid", "La estructura de campo.derivadas no es la de producción"),
        ("G.12 campo.parametros con otra columna (unidad renombrada)", "alter table campo.parametros rename column unidad to unidad_x", "La estructura de campo.parametros no es la de producción"),
        ("G.14 campo.parametros sin el permiso de lectura de homelab_lectura (distinto de producción)", "revoke select on campo.parametros from homelab_lectura", "La estructura de campo.parametros no es la de producción"),
        ("G.13 la clave vigencia_avisos_dias ocupada por otro parámetro", "insert into campo.parametros (clave, valor, unidad, descripcion, minimo, maximo) values ('vigencia_avisos_dias', 7, 'horas', 'otro', 1, 48)",
         "Ya existe el parámetro vigencia_avisos_dias y no es el de este paquete"),
    ]
    for nombre, cambio, esperado in casos:
        con = gn.rehacer("emdupar_b_inv_prueba"); con.execute(cambio)
        e = correr(con, leer(f"migracion_{N}_editor.sql"))
        ok(f"{nombre}: la migración se detiene sin cambiar nada", e is not None and esperado in e
           and gn.md5f(con, gn.PREPARAR) == HL["partida"]["MD5_PREPARAR"], (e or "[aplicó]")[:250])
        con.execute("alter role homelab_lectura bypassrls"); con.close()
    con = gn.rehacer("emdupar_b_inv_prueba"); r0 = inv_produccion(con, "guardia.op@emdupar.gov.co")
    e = correr(con, leer(f"migracion_{N}_editor.sql"))
    ok("G.07 la Investigación con un registro de hoy (3 fotos, efectivo): la migración se detiene", r0.get("id") is not None and e is not None and "ya tiene registros" in e, (e or "[aplicó]")[:250] + str(r0))
    con.close()

    # Mutación: el ensayo tiene que fallar si preparar_subida queda mal escrita
    mutaciones = [("M.01 preparar_subida acepta 0 fotos con CUALQUIER formato", "v_tmin is distinct from 0 then 1", "false then 1", ["03.02", "03.03", "03.04"]),
                  ("M.02 preparar_subida nunca acepta 0 fotos", "v_tmin is distinct from 0 then 1", "true then 1", ["03.01", "04.01"]),
                  ("M.13 la vigencia ignora los avisos cerrados", "where o.contrato = v_c and o.tipo = v_tipo and o.creado_en > clock_timestamp() - make_interval(days => v_vig)",
                   "where o.contrato = v_c and o.tipo = v_tipo and o.creado_en > clock_timestamp() - make_interval(days => v_vig) and campo.f_derivada_estado(d.id) = 'pendiente'", ["20.03"]),
                  ("M.14 la vigencia cuenta desde el último «visto otra vez»", "where o.contrato = v_c and o.tipo = v_tipo and o.creado_en > clock_timestamp() - make_interval(days => v_vig)",
                   "where o.contrato = v_c and o.tipo = v_tipo and coalesce((select max(x.visto_en) from campo.analisis_avisos_vistos x where x.observacion_id = o.id), o.creado_en) > clock_timestamp() - make_interval(days => v_vig)", ["23.04"]),
                  ("M.15 la vigencia no lee el parámetro (siempre 20)", "v_vig := campo.f_param('vigencia_avisos_dias')::integer;", "v_vig := 20;", ["23.05"]),
                  ("M.16 «Otra» no compara el texto (un texto distinto no crearía su aviso)", "and (v_tipo <> 'otra' or lower(o.texto) = lower(v_txt))", "", ["23.09"]),
                  ("M.17 «uno pendiente a la vez» cuenta también los cerrados", "where o.contrato = v_c and o.tipo = v_tipo and campo.f_derivada_estado(d.id) = 'pendiente'",
                   "where o.contrato = v_c and o.tipo = v_tipo", ["23.07"]),
                  ("M.18 «Actualización de datos» con el aviso pendiente no guarda la entrega nueva", "if v_tipo = 'actualizacion_datos' and v_con is not null then", "if false then", ["23.10", "23.11"]),
                  ("M.19 el aviso de posible duplicado no mira la cédula", "or (v_con ? 'cedula' and x.datos ->> 'cedula' = v_con ->> 'cedula'))\n         order by x.id desc limit 1;", ")\n         order by x.id desc limit 1;", ["23.12"]),
                  ("M.20 anular no comprueba que la entrega sea del aviso", "if not exists (select 1 from campo.analisis_observacion_datos x where x.id = p_datos_id and x.observacion_id = v_obs) then",
                   "if not exists (select 1 from campo.analisis_observacion_datos x where x.id = p_datos_id) then", ["23.15"]),
                  ("M.03 la migración no desactiva cita_acordada", "set activo = false where tipo_id = v_t and codigo in ('despeje_caja', 'despeje_observacion', 'visita_concertada', 'cita_acordada');",
                   "set activo = false where tipo_id = v_t and codigo in ('despeje_caja', 'despeje_observacion', 'visita_concertada');", ["01.04"]),
                  ("M.12 la migración no desactiva «observacion» (quedarían dos cajas de texto)", "set activo = false where tipo_id = v_t and codigo = 'observacion';",
                   "set activo = true where tipo_id = v_t and codigo = 'observacion';", ["01.04", "02.02"]),
                  ("M.04 la migración deja la dirección opcional", "set obligatorio = true where tipo_id = v_t and codigo = 'direccion_encontrada'", "set obligatorio = false where tipo_id = v_t and codigo = 'direccion_encontrada'", ["01.03", "04.04"]),
                  ("M.05 el teléfono acepta cualquier número de 10 cifras", "x !~ '^(\\d{7}|3\\d{9}|60\\d{8})$'", "x !~ '^(\\d{7}|\\d{10})$'", ["13.02"]),
                  ("M.06 los datos de contacto los lee quien ve la lista (supervisor de actas)",
                   "declare v_email text; v_obs uuid; v_entregas jsonb; v_n integer; v_vigentes integer;\nbegin\n  v_email := campo.f_autorizar_supervision(p_solicitante);",
                   "declare v_email text; v_obs uuid; v_entregas jsonb; v_n integer; v_vigentes integer;\nbegin\n  v_email := campo.f_autorizar_registradas(p_solicitante);", ["16.02"]),
                  ("M.07 marcar sin haber consultado el contrato", "and q.consultado_en > clock_timestamp() - interval '12 hours'", "", ["11.04"]),
                  ("M.08 la tabla sensible sin SELECT para homelab_lectura",
                   "grant select on campo.analisis_observaciones, campo.analisis_observacion_datos, campo.analisis_observacion_anulaciones to homelab_lectura;",
                   "grant select on campo.analisis_observaciones, campo.analisis_observacion_anulaciones to homelab_lectura;", ["10.02"]),
                  ("M.09 la lista de derivadas trae los datos de contacto",
                   "'trae_datos', exists (select 1 from campo.analisis_observacion_datos x where x.observacion_id = o.id),",
                   "'trae_datos', exists (select 1 from campo.analisis_observacion_datos x where x.observacion_id = o.id), 'datos', (select x.datos from campo.analisis_observacion_datos x where x.observacion_id = o.id order by x.id desc limit 1),", ["15.02"]),
                  ("M.10 «Crear actividad» no cierra el aviso", "  insert into campo.derivada_eventos (derivada_id, tipo_evento, motivo, autor) values (v_d.id, 'atendida_fuera'",
                   "  perform 1; -- insert into campo.derivada_eventos (derivada_id, tipo_evento, motivo, autor) values (v_d.id, 'atendida_fuera'", ["18.07"]),
                  ("M.11 un aviso se puede atender con cualquier formulario", "if not (v_form = any (case when v_d.destino is not null then array[v_d.destino] else v_c.destinos end))",
                   "if v_c.destinos <> '{}' and not (v_form = any (case when v_d.destino is not null then array[v_d.destino] else v_c.destinos end))", ["19.03"])]
    base = leer(f"ensayo_en_transaccion_{N}_editor.sql")
    for nombre, a, b, deben in mutaciones:
        if a not in base: ok(f"{nombre}: el texto a mutar existe", False, a); continue
        con = gn.rehacer("emdupar_b_inv_prueba")
        e, m, _ = ensayo(con, base.replace(a, b, 1))
        fallas = re.findall(r"FALLA (\d\d\.\d\d)", e or "")
        ok(f"{nombre}: el ensayo lo detecta (fallan {', '.join(fallas) or 'ninguna'})", m is not None and m.group(3) is None and all(x in fallas for x in deben), (e or "")[:300])
        con.close()

    out(""); out(f"RESULTADO: {TOT[1]} de {TOT[0]} pruebas correctas" + (" — SIN FALLAS" if TOT[0] == TOT[1] else ""))
    (PAQ / "resultados_locales.txt").write_text("\n".join(LOG) + "\n")
    sys.exit(0 if TOT[0] == TOT[1] else 1)

if __name__ == "__main__":
    main()
