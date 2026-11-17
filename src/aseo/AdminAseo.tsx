import { useCallback, useEffect, useState } from "react";
import { apiAseo, avisoDeError, ErrorAseo, type Normalizacion, type ResumenCapa, type ResumenPlan } from "./apiAseo";
import { leerCapa, lotes, muestraColumna, sha256Hex, type CapaLeida } from "./cargador";
import { leerXlsx, planDesdeHojas } from "./xlsx";

// Pantalla del administrador: cargar el plan operativo (.xlsx), cargar capas de rutas (GeoJSON o KML; el shapefile se convierte antes), arreglar nombres de barrio y ver el historial. TODO se previsualiza antes de
// confirmar y nada se sobrescribe: cada carga de capa crea una VERSIÓN NUEVA de geometría por ruta y las auditorías ya hechas conservan la suya. El administrador ELIGE la columna del código de ruta (no se supone su nombre).
type Pestana = "plan" | "capa" | "barrios" | "historial";
const aviso = (e: unknown) => (e instanceof ErrorAseo ? avisoDeError(e).texto : "No se pudo completar la operación.");
const num = (n: number | undefined) => (n ?? 0).toLocaleString("es-CO");

export function AdminAseo({ onVolver }: { onVolver: () => void }) {
  const [pestana, setPestana] = useState<Pestana>("plan");
  return (
    <div className="aseo-modulo tec-pagina campo-pagina">
      <section className="tec-tarjeta aseo-hoja">
        <div className="campo-cab"><button type="button" className="tec-boton-sec" onClick={onVolver}>‹ Aseo</button><h1>Administración de rutas</h1></div>
        <div className="aseo-pestanas" role="tablist">
          {([["plan", "Plan operativo"], ["capa", "Capa de rutas"], ["barrios", "Barrios"], ["historial", "Historial"]] as const).map(([k, n]) => (
            <button key={k} type="button" role="tab" aria-selected={pestana === k} className={`aseo-pestana${pestana === k ? " aseo-pestana-on" : ""}`} onClick={() => setPestana(k)}>{n}</button>))}
        </div>
        {pestana === "plan" ? <CargaPlan /> : pestana === "capa" ? <CargaCapa /> : pestana === "barrios" ? <Barrios /> : <Historial />}
      </section>
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
function CargaPlan() {
  const [archivo, setArchivo] = useState<{ nombre: string; sha: string; filas: unknown[]; porHoja: Record<string, number>; avisos: string[] } | null>(null);
  const [provisional, setProvisional] = useState(true);
  const [previa, setPrevia] = useState<ResumenPlan | null>(null);
  const [msg, setMsg] = useState<string | null>(null); const [ocupado, setOcupado] = useState(false);

  async function elegir(f: File | undefined) {
    setPrevia(null); setMsg(null); setArchivo(null); if (!f) return;
    setOcupado(true);
    try {
      const buf = await f.arrayBuffer();
      const p = planDesdeHojas(await leerXlsx(buf));
      const a = { nombre: f.name, sha: await sha256Hex(buf), filas: p.filas, porHoja: p.porHoja, avisos: p.avisos };
      setArchivo(a);
      setPrevia(await apiAseo.cargarPlan({ nombre: a.nombre, sha256: a.sha, provisional }, a.filas, false));
    } catch (e) { setMsg(e instanceof Error && !(e instanceof ErrorAseo) ? e.message : aviso(e)); } finally { setOcupado(false); }
  }
  async function confirmar() {
    if (!archivo) return; setOcupado(true); setMsg(null);
    try { const r = await apiAseo.cargarPlan({ nombre: archivo.nombre, sha256: archivo.sha, provisional }, archivo.filas, true);
      setMsg(r.repetido ? r.mensaje ?? "Este archivo ya se cargó." : `Plan cargado como versión ${r.version}${r.provisional ? " (provisional)" : ""}: ${num(r.rutas_nuevas)} rutas nuevas, ${num(r.rutas_existentes)} existentes, ${num(r.rutas_fuera_de_plan)} fuera de plan.`);
      setPrevia(null); setArchivo(null); } catch (e) { setMsg(aviso(e)); } finally { setOcupado(false); }
  }
  return (
    <div className="aseo-admin">
      <p className="campo-sub">Cargue el plan operativo (.xlsx con las hojas Barrido, Recolección y Puntos críticos). Recargar el mismo archivo no cambia nada; un plan distinto es la versión siguiente y las rutas conservan su identificador. Los servicios que no son de barrido entran inactivos.</p>
      <input type="file" accept=".xlsx" aria-label="Archivo del plan operativo" onChange={(e) => void elegir(e.target.files?.[0])} disabled={ocupado} />
      <label className="campo-check"><input type="checkbox" checked={provisional} onChange={(e) => setProvisional(e.target.checked)} /><span>Versión provisional<small>El plan de junio de 2020 entra como provisional; un plan nuevo se carga como la versión siguiente.</small></span></label>
      {ocupado ? <p className="campo-sub" role="status">Procesando…</p> : null}
      {archivo ? <p className="campo-sub">{archivo.nombre}: {Object.entries(archivo.porHoja).map(([h, n]) => `${h} ${num(n)}`).join(" · ")}.{archivo.avisos.length ? " " + archivo.avisos.join(" ") : ""}</p> : null}
      {previa && !previa.repetido ? (
        <div className="aseo-previa">
          <strong>Vista previa</strong>
          <ul><li>{num(previa.filas)} filas: {num(previa.rutas_nuevas)} rutas nuevas y {num(previa.rutas_existentes)} ya existentes.</li>
            <li>{num(previa.rutas_fuera_de_plan)} rutas activas del mismo servicio no figuran en este archivo y quedarán «fuera de plan» (no se borran).</li>
            {previa.barrios ? <li>Barrios nombrados: {num(previa.barrios.nombres)} nombres en {num(previa.barrios.rutas_con_barrio)} rutas; {num(previa.barrios.nombres_coinciden)} coinciden con la capa de barrios y {num(previa.barrios.nombres - previa.barrios.nombres_coinciden)} no (ver «Barrios»).</li> : null}
            <li>Versión que se creará: {previa.version_siguiente}.</li></ul>
          {previa.con_errores ? <div className="campo-error" role="alert"><p>El archivo tiene filas con problemas; corríjalas y cargue de nuevo:</p><ul>{(previa.errores ?? []).slice(0, 12).map((e, i) => <li key={i}><span className="mono">{e.codigo}</span>: {e.motivo}</li>)}</ul></div> : null}
          <button type="button" className="tec-boton" onClick={() => void confirmar()} disabled={ocupado || previa.con_errores}>Confirmar carga del plan</button>
        </div>
      ) : null}
      {previa?.repetido ? <p className="aseo-aviso" role="status">{previa.mensaje}</p> : null}
      {msg ? <p className="aseo-aviso" role="status">{msg}</p> : null}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
function CargaCapa() {
  const [capa, setCapa] = useState<{ datos: CapaLeida; nombre: string; sha: string } | null>(null);
  const [cargaId, setCargaId] = useState<string | null>(null);
  const [srid, setSrid] = useState(4326);
  const [columna, setColumna] = useState("");
  const [norm, setNorm] = useState<Normalizacion>({ recortar: true });
  const [ceros, setCeros] = useState("");
  const [repetidos, setRepetidos] = useState<"omitir" | "unir">("omitir");
  const [nota, setNota] = useState("");
  const [resumen, setResumen] = useState<ResumenCapa | null>(null);
  const [msg, setMsg] = useState<string | null>(null); const [ocupado, setOcupado] = useState<string | null>(null);

  const normFinal = (): Normalizacion => ({ ...norm, ...(ceros.trim() ? { rellenar_ceros: Number(ceros) } : {}) });
  async function elegir(f: File | undefined) {
    setCapa(null); setCargaId(null); setResumen(null); setMsg(null); setColumna(""); if (!f) return;
    try {
      const buf = await f.arrayBuffer(); const datos = leerCapa(new TextDecoder().decode(buf), f.name);
      setCapa({ datos, nombre: f.name, sha: await sha256Hex(buf) }); setSrid(datos.srid);
    } catch (e) { setMsg(e instanceof Error ? e.message : "No se pudo leer el archivo."); }
  }
  async function subir() {
    if (!capa) return; setMsg(null);
    try {
      setOcupado("Enviando la capa…");
      const ini = await apiAseo.geoIniciar({ nombre: capa.nombre, sha256: capa.sha, srid, origen: capa.datos.origen, filas: capa.datos.filas.length });
      setCargaId(ini.carga_id);
      if (ini.aplicada) { setMsg("Esta capa ya se aplicó antes (mismo archivo). No se cambia nada."); setOcupado(null); return; }
      let hechos = 0;
      for (const l of lotes(capa.datos.filas)) { await apiAseo.geoLote(ini.carga_id, l.base, l.filas); hechos += l.filas.length; setOcupado(`Enviando la capa… ${num(hechos)} de ${num(capa.datos.filas.length)}`); }
      setResumen(await apiAseo.geoResumen(ini.carga_id, null, {}));
    } catch (e) { setMsg(aviso(e)); } finally { setOcupado(null); }
  }
  const previsualizar = useCallback(async () => {
    if (!cargaId || !columna) return; setOcupado("Calculando la vista previa…"); setMsg(null);
    try { setResumen(await apiAseo.geoResumen(cargaId, columna, normFinal())); } catch (e) { setMsg(aviso(e)); } finally { setOcupado(null); }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cargaId, columna, norm, ceros]);
  async function aplicar() {
    if (!cargaId || !columna) return; setOcupado("Aplicando…"); setMsg(null);
    try { const r = await apiAseo.geoAplicar(cargaId, columna, normFinal(), repetidos, nota);
      setMsg(`Listo: ${num(r.versiones_creadas)} versiones nuevas de geometría${r.codigos_repetidos_unidos ? `, ${num(r.codigos_repetidos_unidos)} códigos repetidos unidos` : ""}${r.codigos_repetidos_omitidos ? `, ${num(r.codigos_repetidos_omitidos)} repetidos omitidos` : ""}; ${num(r.geometrias_sin_ruta)} geometrías sin ruta en el plan. Las auditorías anteriores conservan la versión con la que se hicieron.`);
      setResumen(null); setCapa(null); setCargaId(null); } catch (e) { setMsg(aviso(e)); } finally { setOcupado(null); }
  }
  const r = resumen;
  return (
    <div className="aseo-admin">
      <p className="campo-sub">Cargue una capa de rutas en GeoJSON o KML (líneas, áreas o puntos). Si el archivo viene en otro sistema de coordenadas (por ejemplo 3116) se transforma a 4326. Vértices repetidos o a pocos metros (doble clic al dibujar) se limpian solos. Un shapefile se convierte antes a GeoJSON.</p>
      <input type="file" accept=".geojson,.json,.kml,.zip,.shp" aria-label="Archivo de la capa de rutas" onChange={(e) => void elegir(e.target.files?.[0])} disabled={!!ocupado} />
      {capa ? (
        <div className="aseo-previa">
          <p className="campo-sub">{capa.nombre}: {num(capa.datos.filas.length)} objetos en {capa.datos.origen.toUpperCase()}. Columnas: {capa.datos.columnas.join(", ") || "ninguna"}.</p>
          {capa.datos.advertencias.map((a) => <p key={a} className="aseo-aviso" role="status">{a}</p>)}
          <label className="campo-etiqueta" htmlFor="aseo-srid">Sistema de coordenadas del archivo</label>
          <select id="aseo-srid" className="aseo-entrada" value={srid} onChange={(e) => setSrid(Number(e.target.value))} disabled={!!cargaId}>
            <option value={4326}>WGS 84 (EPSG:4326, el de GeoJSON y KML)</option><option value={3116}>MAGNA-SIRGAS / Colombia Bogotá (EPSG:3116)</option><option value={9377}>MAGNA-SIRGAS origen nacional (EPSG:9377)</option><option value={3115}>MAGNA-SIRGAS / Colombia Oeste (EPSG:3115)</option>
            {![4326, 3116, 9377, 3115].includes(srid) ? <option value={srid}>EPSG:{srid} (declarado en el archivo)</option> : null}</select>
          {!cargaId ? <button type="button" className="tec-boton" onClick={() => void subir()} disabled={!!ocupado}>Subir la capa y revisar</button> : null}
        </div>
      ) : null}
      {cargaId && r ? (
        <div className="aseo-previa">
          <label className="campo-etiqueta" htmlFor="aseo-col">¿Qué columna es el código de ruta?</label>
          <select id="aseo-col" className="aseo-entrada" value={columna} onChange={(e) => { setColumna(e.target.value); setResumen((x) => x && { ...x, columna: undefined }); }}>
            <option value="">Elija la columna…</option>{r.columnas.map((c) => <option key={c} value={c}>{c}{capa ? ` (ej.: ${muestraColumna(capa.datos.filas, c, 2).join(" · ")})` : ""}</option>)}</select>
          <fieldset className="campo-fieldset"><legend className="campo-etiqueta">Normalizar el código (opcional)</legend>
            {([["recortar", "Quitar espacios al inicio y al final"], ["quitar_espacios", "Quitar todos los espacios"], ["solo_digitos", "Dejar solo los dígitos"], ["quitar_ceros_izquierda", "Quitar ceros a la izquierda"]] as const).map(([k, t]) => (
              <label className="campo-check" key={k}><input type="checkbox" checked={norm[k] === true} onChange={(e) => setNorm((n) => ({ ...n, [k]: e.target.checked }))} /><span>{t}</span></label>))}
            <label className="campo-etiqueta" htmlFor="aseo-ceros">Rellenar con ceros a la izquierda hasta <small>(largo; vacío = no)</small></label>
            <input id="aseo-ceros" className="aseo-entrada" inputMode="numeric" value={ceros} onChange={(e) => setCeros(e.target.value.replace(/\D/g, ""))} placeholder="13" /></fieldset>
          <button type="button" className="tec-boton-sec" onClick={() => void previsualizar()} disabled={!columna || !!ocupado}>Ver vista previa</button>
          {r.columna ? (
            <div className="aseo-resultado">
              <strong>Vista previa con la columna «{r.columna}»</strong>
              <ul>
                <li><b>{num(r.enlazan)}</b> geometrías enlazan con el plan ({num(r.rutas_enlazadas)} rutas).</li>
                <li><b>{num(r.no_enlazan_total)}</b> no enlazan con ninguna ruta del plan{r.no_enlazan?.length ? `: ${r.no_enlazan.slice(0, 8).map((x) => `«${x.crudo}»${x.crudo !== x.normalizado ? ` → ${x.normalizado}` : ""}`).join(", ")}${(r.no_enlazan_total ?? 0) > 8 ? "…" : ""}` : "."}</li>
                <li><b>{num(r.repetidos_total)}</b> códigos se repiten{r.repetidos?.length ? `: ${r.repetidos.slice(0, 8).map((x) => `${x.codigo} (${x.veces} veces${x.mezcla_tipos ? ", tipos mezclados" : ""})`).join(", ")}` : "."}</li>
                {r.sin_codigo ? <li>{num(r.sin_codigo)} objetos sin valor en esa columna.</li> : null}
                {r.con_error ? <li className="aseo-mal">{num(r.con_error)} geometrías con error: {(r.errores ?? []).slice(0, 4).map((x) => `#${x.orden} ${x.motivo}`).join("; ")}</li> : null}
                {r.vertices_limpiados ? <li>{num(r.vertices_limpiados)} vértices repetidos o casi repetidos se limpiaron.</li> : null}
                <li>{num(r.rutas_activas_sin_trazado_despues)} rutas del plan seguirán sin trazado.</li>
              </ul>
              {(r.repetidos_total ?? 0) > 0 ? (
                <fieldset className="campo-fieldset"><legend className="campo-etiqueta">¿Qué hacer con los códigos repetidos?</legend>
                  {([["omitir", "Omitirlos (no se crea trazado para esas rutas)"], ["unir", "Unir sus geometrías en una sola (solo si son del mismo tipo)"]] as const).map(([k, t]) => (
                    <label className="campo-check" key={k}><input type="radio" name="rep" checked={repetidos === k} onChange={() => setRepetidos(k)} /><span>{t}</span></label>))}</fieldset>) : null}
              <label className="campo-etiqueta" htmlFor="aseo-nota">Nota de la carga <small>(opcional)</small></label>
              <input id="aseo-nota" className="aseo-entrada" maxLength={300} value={nota} onChange={(e) => setNota(e.target.value)} />
              <button type="button" className="tec-boton" onClick={() => void aplicar()} disabled={!!ocupado || !r.completa || (r.enlazan ?? 0) === 0}>Aplicar: crear versión nueva de cada ruta enlazada</button>
              {!r.completa ? <p className="aseo-mal">La carga está incompleta: faltan geometrías por enviar.</p> : null}
            </div>
          ) : null}
        </div>
      ) : null}
      {ocupado ? <p className="campo-sub" role="status">{ocupado}</p> : null}
      {msg ? <p className="aseo-aviso" role="status">{msg}</p> : null}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
function Barrios() {
  const [d, setD] = useState<{ sugerencias_disponibles: boolean; barrios: { nombre: string; rutas: number; ejemplo_ruta: string; sugerencias: string[] }[] } | null>(null);
  const [msg, setMsg] = useState<string | null>(null); const [alias, setAlias] = useState(""); const [barrio, setBarrio] = useState(""); const [ocupado, setOcupado] = useState(false);
  const cargar = useCallback(() => { apiAseo.barriosSinCoincidencia().then(setD).catch((e) => setMsg(aviso(e))); }, []);
  useEffect(() => { cargar(); }, [cargar]);
  async function crear(a: string, b: string) {
    setOcupado(true); setMsg(null);
    try { const r = await apiAseo.alias("crear", a, b, "Corrección de nombre de barrio desde la administración"); setMsg(`Alias creado: ${r.rutas_actualizadas ?? 0} rutas pasaron a «por alias».`); setAlias(""); setBarrio(""); cargar(); } catch (e) { setMsg(aviso(e)); } finally { setOcupado(false); }
  }
  async function trazado() {
    setOcupado(true); setMsg(null);
    try { const r = await apiAseo.regenerarBarrios(); setMsg(`Trazado inicial por barrios: ${num(r.versiones_creadas)} versiones nuevas (${num(r.incompletas)} incompletas), ${num(r.sin_cambios)} sin cambios, ${num(r.con_trazado_propio)} con trazado propio (no se tocan), ${num(r.sin_barrios)} sin barrios.`); cargar(); } catch (e) { setMsg(aviso(e)); } finally { setOcupado(false); }
  }
  return (
    <div className="aseo-admin">
      <p className="campo-sub">Nombres de barrio del plan que no coinciden con la capa de barrios del geoportal. Cree un alias (nombre del plan → nombre de la capa) y vuelva a generar el trazado: la geometría nueva es una versión siguiente y las auditorías anteriores conservan la suya.</p>
      <button type="button" className="tec-boton-sec" onClick={() => void trazado()} disabled={ocupado}>Generar trazado inicial desde los barrios</button>
      {!d ? <p className="campo-sub">Cargando…</p> : d.barrios.length === 0 ? <p className="campo-sub">Todos los nombres de barrio del plan coinciden con la capa.</p> : (
        <ul className="aseo-lista">{d.barrios.slice(0, 60).map((b) => (
          <li key={b.nombre} className="aseo-barrio"><span><strong>{b.nombre}</strong> <small>({b.rutas} rutas, ej. <span className="mono">{b.ejemplo_ruta}</span>)</small></span>
            {b.sugerencias.map((s) => <button key={s} type="button" className="tec-boton-sec aseo-corto" onClick={() => void crear(b.nombre, s)} disabled={ocupado}>Es «{s}»</button>)}
            <button type="button" className="tec-boton-sec aseo-corto" onClick={() => setAlias(b.nombre)}>Elegir…</button></li>))}</ul>)}
      {d && !d.sugerencias_disponibles && d.barrios.length > 0 ? <p className="campo-sub">Las sugerencias por parecido no están disponibles (falta la extensión pg_trgm): escriba el nombre de la capa a mano.</p> : null}
      <div className="aseo-previa"><label className="campo-etiqueta" htmlFor="aseo-alias">Alias (nombre del plan)</label><input id="aseo-alias" className="aseo-entrada" value={alias} onChange={(e) => setAlias(e.target.value)} />
        <label className="campo-etiqueta" htmlFor="aseo-barrio">Nombre del barrio en la capa</label><input id="aseo-barrio" className="aseo-entrada" value={barrio} onChange={(e) => setBarrio(e.target.value)} />
        <button type="button" className="tec-boton" onClick={() => void crear(alias, barrio)} disabled={ocupado || alias.trim().length < 2 || barrio.trim().length < 2}>Crear alias</button></div>
      {msg ? <p className="aseo-aviso" role="status">{msg}</p> : null}
    </div>
  );
}

function Historial() {
  const [d, setD] = useState<Awaited<ReturnType<typeof apiAseo.cargas>> | null>(null); const [msg, setMsg] = useState<string | null>(null);
  useEffect(() => { apiAseo.cargas().then(setD).catch((e) => setMsg(aviso(e))); }, []);
  if (msg) return <p className="aseo-aviso" role="alert">{msg}</p>;
  if (!d) return <p className="campo-sub">Cargando…</p>;
  return (
    <div className="aseo-admin">
      <p className="campo-sub">Rutas activas: <b>{num(d.resumen.rutas)}</b> · puntos: {num(d.resumen.puntos)} · con trazado vigente: <b>{num(d.resumen.con_trazado)}</b> · nombres de barrio sin coincidencia: {num(d.resumen.barrios_sin_coincidencia)}.</p>
      <ul className="aseo-lista">{d.cargas.map((c) => (<li key={c.id} className="aseo-barrio"><span><strong>{c.tipo === "plan" ? `Plan versión ${c.version}${c.provisional ? " (provisional)" : ""}` : "Capa de rutas"}</strong> · {c.nombre}<br /><small>{num(c.filas)} filas · {c.origen ?? ""} · {c.autor} · {new Date(c.creado_en).toLocaleString("es-CO")}{c.tipo === "geometrias" ? (c.aplicada ? " · aplicada" : " · sin aplicar") : ""}</small></span></li>))}</ul>
    </div>
  );
}
