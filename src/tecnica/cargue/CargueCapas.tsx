import { useEffect, useMemo, useRef, useState } from "react";
import maplibregl from "maplibre-gl";
import "maplibre-gl/dist/maplibre-gl.css";
import "./cargue.css";
import { CENTRO_VALLEDUPAR, FUENTE_BASE_CALLES } from "../../lib/mapaBase";
import { ErrorTec } from "../apiTecnica";
import { apiCargue, type CapaCargue, type CapasResp, type CargaHistorial, type Choque, type Muestra, type Publicada, type Resumen } from "./apiCargue";
import {
  enLotes, filasConXY, leerArchivo, nombreSistema, normalizarNombre, proponerLlave, proponerSridTabla, revisarLlave, sha256Hex, SIN_LLAVE, SISTEMAS, sridPorRango,
  type CapaLeida, type FilaLote,
} from "./lectores";

// Dashboard distribución · pestaña «Cargue de capas» (Técnica fase 1, Corte 5c; maqueta «Supervision», plan 02).
// · Las capas en 5 grupos, con su estado (al día, desactualizada, sin cargar, sale de otra capa o viene de otro módulo), su versión y su última carga.
// · Cinco pasos: archivo → columna llave → sistema de coordenadas → revisar (nuevos, cambiados, retirados, choques con la ficha y vista previa) → publicar.
// · «Cargar varias capas de un archivo»: un GeoPackage o un zip con varios SHP se reparte por el nombre de cada capa; las que no coinciden se eligen a mano.
// · Historial de cada capa y «Volver a la versión anterior» (revertir, con motivo). Nada se borra: lo que no viene queda retirado con motivo.
// · El supervisor de distribución solo LEE (lista e historial); cargar es del administrador (lo vuelve a decidir el servidor).

const GRUPOS: { c: CapaCargue["grupo"]; n: string; color: string }[] = [
  { c: "acueducto", n: "Acueducto", color: "#1F5FA8" }, { c: "alcantarillado", n: "Alcantarillado", color: "#A0521B" },
  { c: "tecnologia_perdidas", n: "Tecnología y pérdidas", color: "#0E6E5C" }, { c: "calidad_pqr", n: "Calidad, PQR y reportes", color: "#146C94" },
  { c: "base", n: "Base cartográfica", color: "#5B625D" }];
// Capas de la maqueta que no son de este corte (no son activos ni puntos de muestreo): se muestran con su estado, sin cargar.
const OTRAS: { grupo: CapaCargue["grupo"]; nombre: string; geometria: string; nota: string }[] = [
  { grupo: "calidad_pqr", nombre: "PQR técnicas", geometria: "Punto (por dirección)", nota: "Se carga por CSV o Excel y se ubica por dirección cuando llegue el archivo real" },
  { grupo: "calidad_pqr", nombre: "Reportes de la línea 116", geometria: "Punto (por dirección)", nota: "Igual que las PQR, cuando llegue el archivo real" },
  { grupo: "base", nombre: "Barrios", geometria: "Polígono", nota: "Viene de la base cartográfica del geoportal" },
  { grupo: "base", nombre: "Área de prestación del servicio (APS)", geometria: "Polígono", nota: "Viene de la base cartográfica del geoportal" },
  { grupo: "base", nombre: "Predios y contratos", geometria: "Punto", nota: "Viene del catastro comercial" }];
const ESTADO: Record<string, [string, string]> = {
  al_dia: ["Al día", "cg-est-dia"], desactualizada: ["Desactualizada", "cg-est-vieja"], sin_cargar: ["Sin cargar", "cg-est-sin"],
  derivada: ["Sale de otra capa", "cg-est-ext"], otro_modulo: ["Viene de otro módulo", "cg-est-ext"] };
const GEOM: Record<string, string> = { punto: "Punto", linea: "Línea", poligono: "Polígono", mixta: "Mixta" };
const FMT: Record<string, string> = { shp: "SHP en zip", gpkg: "GeoPackage", geojson: "GeoJSON", kml: "KML", csv: "CSV", xlsx: "Excel" };
const EXT: Record<string, string> = { shp: ".zip", gpkg: ".gpkg", geojson: ".geojson,.json", kml: ".kml,.kmz", csv: ".csv,.txt", xlsx: ".xlsx" };
const TIPO_GEOM: Record<string, string[]> = { punto: ["POINT", "MULTIPOINT"], linea: ["LINESTRING", "MULTILINESTRING"], poligono: ["POLYGON", "MULTIPOLYGON"] };
const fecha = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const err = (e: unknown) => (e instanceof ErrorTec && e.tipo === "permiso" ? "No tiene permiso para esta acción (solo el administrador carga capas)." : e instanceof Error ? e.message : "No se pudo completar.");
const n = (x: number | undefined | null) => (x ?? 0).toLocaleString("es-CO");
const formatosDe = (c: CapaCargue) => [...new Set([...c.formatos, ...(c.formatos.includes("csv") ? ["xlsx"] : [])])];
const PASOS = ["Elegir el archivo", "Columna llave", "Sistema de coordenadas", "Revisar los cambios", "Publicar la versión"];

type Vista = { tipo: "lista" } | { tipo: "carga"; capa: CapaCargue } | { tipo: "masiva" } | { tipo: "historial"; capa: CapaCargue };

export function CargueCapas() {
  const [datos, setDatos] = useState<CapasResp | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [filtro, setFiltro] = useState<"todas" | "pend" | "dia">("todas");
  const [vista, setVista] = useState<Vista>({ tipo: "lista" });
  const [vez, setVez] = useState(0);
  const [aviso, setAviso] = useState<string | null>(null);
  useEffect(() => { let vivo = true; setError(null);
    apiCargue.capas().then((d) => { if (vivo) setDatos(d); }).catch((e) => { if (vivo) setError(e instanceof ErrorTec && e.tipo === "permiso" ? "Solo el supervisor de distribución o el administrador ven el Cargue de capas." : err(e)); });
    return () => { vivo = false; }; }, [vez]);
  const volver = (t?: string) => { setVista({ tipo: "lista" }); setVez((v) => v + 1); setAviso(t ?? null); };

  if (error) return <section className="tec-tarjeta" role="alert"><p>{error}</p></section>;
  if (!datos) return <p className="tec-sub dan-pad" role="status">Cargando las capas…</p>;
  if (vista.tipo === "carga") return <Asistente capa={vista.capa} datos={datos} onCerrar={volver} />;
  if (vista.tipo === "masiva") return <Masiva datos={datos} onCerrar={volver} />;
  if (vista.tipo === "historial") return <Historial capa={vista.capa} puede={datos.puede_cargar} onCerrar={volver} />;

  const visibles = datos.capas;
  const pasa = (est: string) => filtro === "todas" || (filtro === "pend" && (est === "sin_cargar" || est === "desactualizada")) || (filtro === "dia" && est === "al_dia");
  const total = visibles.length + OTRAS.length;
  return (
    <div className="cg" data-testid="cargue">
      <section className="tec-tarjeta cg-cabeza">
        <h2>Cargue de capas</h2>
        <p className="tec-sub">{total} capas en {GRUPOS.length} grupos. Cada carga crea una versión nueva; la anterior queda guardada. Nada se borra: lo que no venga en la versión nueva queda retirado, con motivo, y sus intervenciones se conservan.</p>
        {!datos.puede_cargar ? <p className="tec-aviso tec-aviso-info" role="note">Usted ve el Cargue en solo lectura: las capas las carga el administrador.</p> : null}
        <div className="dan-fila" role="group" aria-label="Filtro de capas">
          {([["todas", "Todas"], ["pend", "Por cargar o desactualizadas"], ["dia", "Al día"]] as const).map(([c, t]) => (
            <button key={c} type="button" className="dan-opcion" aria-pressed={filtro === c} onClick={() => setFiltro(c)}>{t}</button>))}
        </div>
        {datos.puede_cargar ? <button type="button" className="tec-boton-sec" onClick={() => setVista({ tipo: "masiva" })}>Cargar varias capas de un archivo</button> : null}
        <details className="cg-como"><summary>Cómo se carga</summary>
          <ol>
            <li>Archivo: SHP en zip, GeoPackage, GeoJSON, KML, o CSV/Excel con X y Y.</li>
            <li>Columna llave: la que identifica cada elemento. Si la capa no trae código, se cruza por geometría y el geoportal asigna el código.</li>
            <li>Sistema de coordenadas (se detecta del archivo; usted lo confirma).</li>
            <li>Revisar: nuevos, cambiados y retirados, los choques con la ficha y la vista previa en el mapa.</li>
            <li>Publicar la versión. Se puede volver a la anterior.</li>
          </ol>
        </details>
      </section>
      {aviso ? <p className="tec-aviso tec-aviso-info dan-pad-x" role="status">{aviso} <button type="button" className="tec-enlace" onClick={() => setAviso(null)}>Cerrar</button></p> : null}
      {GRUPOS.map((g) => {
        const capas = visibles.filter((c) => c.grupo === g.c && pasa(c.estado));
        const otras = OTRAS.filter((o) => o.grupo === g.c && filtro === "todas");
        const todas = visibles.filter((c) => c.grupo === g.c);
        if (!capas.length && !otras.length) return null;
        return (
          <section key={g.c} className="tec-tarjeta cg-grupo" aria-labelledby={`cg-g-${g.c}`}>
            <h2 id={`cg-g-${g.c}`}><span className="cg-color" style={{ background: g.color }} aria-hidden="true" />{g.n}
              <span className="cg-resumen">{todas.length + OTRAS.filter((o) => o.grupo === g.c).length} capas · {todas.filter((c) => c.estado === "al_dia").length} al día</span></h2>
            {capas.map((c) => (
              <article key={c.codigo} className="cg-capa" data-testid={`capa-${c.codigo}`}>
                <div className="cg-capa-cab">
                  <h3>{c.nombre}{c.prefijo ? <span className="cg-pref"> {c.prefijo}</span> : null}</h3>
                  <span className={`cg-est ${ESTADO[c.estado][1]}`}>{ESTADO[c.estado][0]}</span>
                </div>
                <p className="tec-ayuda">{GEOM[c.geometria] ?? c.geometria} · {c.fuente === "carga" ? formatosDe(c).map((f) => FMT[f] ?? f).join(", ") : c.derivada_de ? `sale de la capa ${datos.capas.find((x) => x.codigo === c.derivada_de)?.nombre ?? c.derivada_de}` : "—"}
                  {c.columna_llave ? ` · llave ${c.columna_llave}` : c.lector === "generico" ? " · llave a elegir (o por geometría)" : ""}</p>
                <p className="tec-ayuda">{c.version ? `Versión ${c.version} · ${fecha(c.ultima?.publicada_en)} · ${n(c.vigentes)} ${c.codigo === "muestreo" ? "puntos activos" : "vigentes"}` : c.fuente === "carga" ? "Todavía no se ha cargado" : `${n(c.vigentes)} vigentes`}</p>
                {c.abierta ? <p className="tec-aviso tec-aviso-error cg-abierta">Hay una carga abierta (la {c.abierta.carga_id}, de {c.abierta.autor}, {fecha(c.abierta.creado_en)}): llegaron {n(c.abierta.recibidas)} de {n(c.abierta.filas)} filas.</p> : null}
                <div className="dash-acciones">
                  {datos.puede_cargar && c.fuente === "carga" && c.lector ? <button type="button" className="tec-boton-sec" onClick={() => setVista({ tipo: "carga", capa: c })}>{c.abierta ? "Seguir o anular la carga" : "Cargar versión"}</button> : null}
                  {c.fuente === "carga" ? <button type="button" className="tec-boton-sec" onClick={() => setVista({ tipo: "historial", capa: c })}>Historial</button> : null}
                </div>
              </article>))}
            {otras.map((o) => (
              <article key={o.nombre} className="cg-capa cg-capa-otra">
                <div className="cg-capa-cab"><h3>{o.nombre}</h3><span className="cg-est cg-est-ext">{o.grupo === "base" ? "Viene de otro módulo" : "Sin cargar"}</span></div>
                <p className="tec-ayuda">{o.geometria} · {o.nota}</p>
              </article>))}
          </section>
        );
      })}
    </div>
  );
}

// =====================================================================================================================
// Asistente de una capa (5 pasos)
// =====================================================================================================================
type Subida = { carga: number; total: number; enviadas: number };
function Asistente({ capa, datos, onCerrar }: { capa: CapaCargue; datos: CapasResp; onCerrar: (aviso?: string) => void }) {
  const [paso, setPaso] = useState(1);
  const [archivo, setArchivo] = useState<File | null>(null);
  const [leidas, setLeidas] = useState<CapaLeida[] | null>(null);
  const [cual, setCual] = useState(0);
  const [leyendo, setLeyendo] = useState(false);
  const [llave, setLlave] = useState<string>("");
  const [srid, setSrid] = useState<number | null>(null);
  const [xy, setXy] = useState<{ x: string; y: string } | null>(null);
  const [subida, setSubida] = useState<Subida | null>(null);
  const [resumen, setResumen] = useState<Resumen | null>(null);
  const [muestra, setMuestra] = useState<Muestra | null>(null);
  const [nota, setNota] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [publicada, setPublicada] = useState<Publicada | null>(null);
  const l = leidas?.[cual] ?? null;
  const esMue = capa.codigo === "muestreo";

  async function elegirArchivo(f: File | null) {
    setArchivo(f); setLeidas(null); setMsg(null); setCual(0);
    if (!f) return;
    setLeyendo(true);
    try {
      const cs = await leerArchivo(f);
      setLeidas(cs);
      prepararCapa(cs[0]);
    } catch (e) { setMsg({ ok: false, t: err(e) }); } finally { setLeyendo(false); }
  }
  function prepararCapa(c: CapaLeida) {
    const fija = capa.columna_llave;
    setLlave(fija ? (c.columnas.find((k) => k.toLowerCase() === fija.toLowerCase()) ? fija : "") : proponerLlave(c) ?? (capa.lector === "generico" ? SIN_LLAVE : ""));
    setSrid(c.srid); setXy(c.xy ?? null);
  }
  const formatoOk = l ? formatosDe(capa).includes(l.formato) : true;
  const tiposMal = l && TIPO_GEOM[capa.geometria] ? Object.entries(l.tipos).filter(([t]) => !TIPO_GEOM[capa.geometria].includes(t)) : [];
  const conError = l ? l.filas.filter((f) => f.error).length : 0;
  const revLlave = l && llave && llave !== SIN_LLAVE ? revisarLlave(l.filas, l.columnas.find((k) => k.toLowerCase() === llave.toLowerCase()) ?? llave) : null;

  /** Las filas que se suben: con la geometría de X y Y en las tablas, la llave fija con su nombre exacto y, en la capa MUE, las columnas en minúscula. */
  function filasParaSubir(): FilaLote[] {
    if (!l) return [];
    const base = l.tabla && xy ? filasConXY(l, xy, srid) : l.filas;
    const fija = capa.columna_llave;
    return base.map((f, i) => {
      let a = { ...f.atributos };
      if (esMue) a = Object.fromEntries(Object.entries(a).map(([k, v]) => [k.toLowerCase(), v]));
      else if (fija) { const k = Object.keys(a).find((x) => x.toLowerCase() === fija.toLowerCase()); if (k && k !== fija) { a[fija] = a[k]; delete a[k]; } }
      return { orden: i + 1, wkt: f.wkt, atributos: a };
    });
  }
  async function subirYRevisar() {
    if (!l || !archivo || !srid) return;
    setOcupado(true); setMsg(null); setResumen(null); setMuestra(null);
    try {
      const filas = filasParaSubir();
      if (filas.length > datos.max_filas) throw new Error(`El archivo trae ${n(filas.length)} elementos y una carga admite ${n(datos.max_filas)}.`);
      const lotes = enLotes(filas, datos.lote_max_filas || 200);
      const huella = await sha256Hex(`${await sha256Hex(await archivo.arrayBuffer())}|${l.nombre}|${llave}|${srid}|${xy ? xy.x + "/" + xy.y : ""}`);
      const ini = await apiCargue.iniciar({ capa: capa.codigo, sha256: huella, formato: l.formato, srid, columna_llave: esMue ? "codigo" : llave, filas: filas.length,
        nota: `${archivo.name}${leidas && leidas.length > 1 ? ` · ${l.nombre}` : ""}`.slice(0, 500) });
      setSubida({ carga: ini.carga_id, total: filas.length, enviadas: Math.min(ini.recibidas, filas.length) });
      let enviadas = 0;
      for (const lote of lotes) {
        const r = await apiCargue.lote(ini.carga_id, lote);
        enviadas += lote.length;
        setSubida({ carga: ini.carga_id, total: filas.length, enviadas: Math.max(enviadas, r.recibidas) });
      }
      await revisar(ini.carga_id);
      setPaso(4);
    } catch (e) { setMsg({ ok: false, t: err(e) }); } finally { setOcupado(false); }
  }
  async function revisar(carga: number) {
    const [r, m] = await Promise.all([apiCargue.resumen(carga), apiCargue.muestra(carga).catch(() => null)]);
    setResumen(r); setMuestra(m);
  }
  async function publicar() {
    if (!subida) return;
    if (nota.trim().length < 10) { setMsg({ ok: false, t: "Escriba la nota de la versión (10 caracteres o más): qué trae y de dónde salió." }); return; }
    setOcupado(true); setMsg(null);
    try { setPublicada(await apiCargue.publicar(subida.carga, nota.trim())); }
    catch (e) { setMsg({ ok: false, t: err(e) }); } finally { setOcupado(false); }
  }

  if (publicada) return (
    <section className="tec-tarjeta cg-asistente" data-testid="publicada">
      <h2>{capa.nombre}: versión {publicada.version_capa} publicada</h2>
      <p>{esMue ? `${n(publicada.nuevos)} puntos nuevos · ${n(publicada.desactivados)} desactivados` : `${n(publicada.nuevos)} nuevos · ${n(publicada.cambiados)} cambiados · ${n(publicada.retirados)} retirados · ${n(publicada.iguales)} iguales`}</p>
      <p className="tec-ayuda">El geovisor ya muestra la versión nueva. Si algo quedó mal, desde el historial de la capa se vuelve a la anterior.</p>
      <button type="button" className="tec-boton" onClick={() => onCerrar(`${capa.nombre}: versión ${publicada.version_capa} publicada.`)}>Volver a las capas</button>
    </section>
  );
  return (
    <section className="tec-tarjeta cg-asistente" aria-labelledby="cg-asis-tit">
      <div className="cg-pasos" aria-hidden="true">{PASOS.map((_, i) => <span key={i} className={i < paso ? "cg-paso-si" : ""} />)}</div>
      <p className="tec-ayuda">Paso {paso} de 5</p>
      <h2 id="cg-asis-tit">{capa.nombre} · {PASOS[paso - 1]}</h2>
      {capa.abierta && !subida && paso === 1 ? <CargaAbierta capa={capa} onAnulada={() => onCerrar(`Se anuló la carga abierta de ${capa.nombre}.`)} /> : null}

      {paso === 1 ? (
        <>
          <div className="tec-campo">
            <label htmlFor="cg-archivo">Archivo ({formatosDe(capa).map((f) => FMT[f]).join(", ")})</label>
            <input id="cg-archivo" type="file" accept={formatosDe(capa).map((f) => EXT[f]).join(",")} disabled={leyendo} onChange={(e) => void elegirArchivo(e.target.files?.[0] ?? null)} />
            <p className="tec-ayuda">El archivo se lee en este equipo; al servidor solo van los elementos, en partes de {datos.lote_max_filas || 200}.</p>
          </div>
          {leyendo ? <p className="tec-sub" role="status">Leyendo el archivo…</p> : null}
          {leidas && leidas.length > 1 ? (
            <div className="tec-campo">
              <label htmlFor="cg-cual">El archivo trae {leidas.length} capas: ¿cuál es «{capa.nombre}»?</label>
              <select id="cg-cual" value={cual} onChange={(e) => { const i = Number(e.target.value); setCual(i); prepararCapa(leidas[i]); }}>
                {leidas.map((c, i) => <option key={i} value={i}>{c.nombre} ({n(c.filas.length)} elementos)</option>)}
              </select>
            </div>) : null}
          {l ? <LeidaResumen l={l} /> : null}
          {l && !formatoOk ? <p className="tec-aviso tec-aviso-error" role="alert">Esta capa no se carga con {FMT[l.formato]}: use {formatosDe(capa).map((f) => FMT[f]).join(", ")}.</p> : null}
          {tiposMal.length ? <p className="tec-aviso tec-aviso-error" role="alert">La capa es de {GEOM[capa.geometria]?.toLowerCase()}s y el archivo trae {tiposMal.map(([t, k]) => `${n(k)} ${t}`).join(", ")}: esas filas no se podrán publicar.</p> : null}
        </>
      ) : null}

      {paso === 2 && l ? (
        <>
          {capa.columna_llave ? (
            <p className={`tec-aviso ${llave ? "tec-aviso-info" : "tec-aviso-error"}`} role={llave ? "status" : "alert"}>
              {llave ? `Esta capa se carga siempre con la columna ${capa.columna_llave} (la llave del modelo).` : `El archivo no trae la columna ${capa.columna_llave}, que es la llave de esta capa.`}</p>
          ) : (
            <div className="tec-campo">
              <label htmlFor="cg-llave">Columna llave (la que identifica cada elemento)</label>
              <select id="cg-llave" value={llave} onChange={(e) => setLlave(e.target.value)}>
                <option value="">Elija…</option>
                {l.columnas.map((c) => { const r = revisarLlave(l.filas, c); return <option key={c} value={c}>{c}{r.unica ? " (única en todas las filas)" : ` (${r.repetidas ? `${n(r.repetidas)} repetidas` : ""}${r.repetidas && r.vacias ? ", " : ""}${r.vacias ? `${n(r.vacias)} vacías` : ""})`}</option>; })}
                {capa.lector === "generico" ? <option value={SIN_LLAVE}>Sin columna llave: cruzar por geometría (a {datos.tolerancia_geometria_m} m)</option> : null}
              </select>
              <p className="tec-ayuda">{llave === SIN_LLAVE ? `Cada elemento se cruza con el vigente del mismo tipo que esté a ${datos.tolerancia_geometria_m} m o menos; lo que no cruce entra como nuevo y el geoportal le asigna su código.`
                : "Si la capa no trae código, el geoportal asigna el prefijo y el consecutivo, y guarda el anterior."}</p>
            </div>
          )}
          {revLlave && !revLlave.unica ? <p className="tec-aviso tec-aviso-error" role="alert">La columna {llave} tiene {revLlave.repetidas ? `${n(revLlave.repetidas)} valores repetidos` : ""}{revLlave.repetidas && revLlave.vacias ? " y " : ""}{revLlave.vacias ? `${n(revLlave.vacias)} vacíos` : ""}: así no se podrá publicar.{capa.lector === "generico" ? " Elija otra o cargue sin columna llave." : ""}</p> : null}
        </>
      ) : null}

      {paso === 3 && l ? (
        <>
          {l.tabla ? (
            <div className="cg-dos">
              <div className="tec-campo"><label htmlFor="cg-x">Columna X (longitud o este)</label>
                <select id="cg-x" value={xy?.x ?? ""} onChange={(e) => { const v = { x: e.target.value, y: xy?.y ?? "" }; setXy(v); if (v.x && v.y) setSrid(proponerSridTabla(l, v).srid); }}>
                  <option value="">Elija…</option>{l.columnas.map((c) => <option key={c} value={c}>{c}</option>)}</select></div>
              <div className="tec-campo"><label htmlFor="cg-y">Columna Y (latitud o norte)</label>
                <select id="cg-y" value={xy?.y ?? ""} onChange={(e) => { const v = { x: xy?.x ?? "", y: e.target.value }; setXy(v); if (v.x && v.y) setSrid(proponerSridTabla(l, v).srid); }}>
                  <option value="">Elija…</option>{l.columnas.map((c) => <option key={c} value={c}>{c}</option>)}</select></div>
            </div>) : null}
          <div className="tec-campo">
            <label htmlFor="cg-srid">Sistema de coordenadas</label>
            <select id="cg-srid" value={srid ?? ""} onChange={(e) => setSrid(e.target.value ? Number(e.target.value) : null)}>
              <option value="">Elija…</option>{SISTEMAS.map((s) => <option key={s.srid} value={s.srid}>{s.nombre}</option>)}</select>
            <p className="tec-ayuda">Detectado: {nombreSistema(l.srid)}{l.sridComo ? ` (${l.sridComo})` : ""}. El servidor lo convierte y revisa que caiga en Valledupar; la vista previa lo muestra en el mapa antes de publicar.</p>
          </div>
          <AvisoRango l={l} srid={srid} xy={xy} />
        </>
      ) : null}

      {paso === 4 && resumen ? (
        <RevisarResumen resumen={resumen} muestra={muestra} esMue={esMue} onDevuelto={async () => { if (subida) await revisar(subida.carga); }} carga={subida?.carga ?? 0} />
      ) : null}

      {paso === 5 && resumen ? (
        <>
          <p>{esMue ? `${n(resumen.frente_a_vigente.nuevo)} nuevos · ${n(resumen.desactivar?.length)} se desactivan` : `${n(resumen.frente_a_vigente.nuevo)} nuevos · ${n(resumen.frente_a_vigente.cambiado)} cambiados · ${n(resumen.retirados)} retirados`}</p>
          <p className="tec-ayuda">{esMue ? "Los puntos que no vienen salen del formulario de Muestreo desde la publicación; sus registros se conservan." : `Los retirados quedan inactivos con el motivo «no vino en la versión ${capa.version + 1}». Sus intervenciones se conservan.`}</p>
          <div className="tec-campo">
            <label htmlFor="cg-nota">Nota de la versión (obligatoria)</label>
            <input id="cg-nota" type="text" maxLength={1000} value={nota} onChange={(e) => setNota(e.target.value)} placeholder="Qué trae y de dónde salió (10 caracteres o más)" />
          </div>
          <p className="tec-ayuda">Al publicar, el geovisor muestra la versión nueva. Se puede volver a la anterior.</p>
        </>
      ) : null}

      {subida && ocupado && paso === 3 ? <Progreso s={subida} /> : null}
      {msg ? <p className={`tec-aviso ${msg.ok ? "tec-aviso-info" : "tec-aviso-error"}`} role={msg.ok ? "status" : "alert"}>{msg.t}</p> : null}

      <div className="tec-acciones cg-nav">
        <button type="button" className="tec-boton-sec" disabled={ocupado} onClick={() => (paso === 1 || paso === 4 ? onCerrar() : setPaso(paso - 1))}>{paso === 1 ? "Cancelar" : paso === 4 ? "Salir (la carga queda abierta)" : "Atrás"}</button>
        {paso === 1 ? <button type="button" className="tec-boton" disabled={!l || !formatoOk || leyendo} onClick={() => setPaso(2)}>Siguiente</button> : null}
        {paso === 2 ? <button type="button" className="tec-boton" disabled={!llave} onClick={() => setPaso(3)}>Siguiente</button> : null}
        {paso === 3 ? <button type="button" className="tec-boton" disabled={!srid || ocupado || (l?.tabla && !(xy?.x && xy?.y))} aria-busy={ocupado} onClick={() => void subirYRevisar()}>{ocupado ? "Subiendo…" : "Subir y revisar"}</button> : null}
        {paso === 4 ? <button type="button" className="tec-boton" disabled={!resumen?.lista_para_publicar} onClick={() => { setMsg(null); setPaso(5); }}>Siguiente</button> : null}
        {paso === 5 ? <button type="button" className="tec-boton" disabled={ocupado} aria-busy={ocupado} onClick={() => void publicar()}>{ocupado ? "Publicando…" : "Publicar versión"}</button> : null}
      </div>
      {subida && (paso === 4 || paso === 5) ? <ConMotivo rotulo="Anular esta carga" onEnviar={async (m) => { await apiCargue.anular(subida.carga, m); onCerrar(`Se anuló la carga de ${capa.nombre}: no cambió nada.`); }} /> : null}
      {conError && paso === 1 ? <p className="tec-ayuda">{n(conError)} elementos no se pudieron leer: el resumen los mostrará como error.</p> : null}
    </section>
  );
}

function LeidaResumen({ l }: { l: CapaLeida }) {
  return (
    <div className="cg-leida" data-testid="leida">
      <p><strong>{n(l.filas.length)}</strong> elementos · {FMT[l.formato]}{l.tabla ? " (la geometría sale de X y Y)" : ` · ${Object.entries(l.tipos).map(([t, k]) => `${n(k)} ${t}`).join(", ")}`}</p>
      <p className="tec-ayuda">Columnas: {l.columnas.slice(0, 30).join(", ")}{l.columnas.length > 30 ? ` y ${l.columnas.length - 30} más` : ""}</p>
      {l.avisos.map((a, i) => <p key={i} className="tec-aviso tec-aviso-info">{a}</p>)}
    </div>
  );
}

/** Aviso si el rango de las coordenadas no se parece al sistema elegido (la guarda final es la caja de Valledupar en el servidor). */
function AvisoRango({ l, srid, xy }: { l: CapaLeida; srid: number | null; xy: { x: string; y: string } | null }) {
  const det = useMemo(() => {
    if (l.tabla) return xy?.x && xy?.y ? proponerSridTabla(l, xy) : null;
    const xs: number[] = [], ys: number[] = [];
    for (const f of l.filas.slice(0, 300)) { const m = f.wkt && /(-?[0-9.]+) (-?[0-9.]+)/.exec(f.wkt); if (m) { xs.push(Number(m[1])); ys.push(Number(m[2])); } }
    return sridPorRango(xs, ys);
  }, [l, xy]);
  if (!det || !srid || det.srid === null) return null;
  const clase = (s: number) => (s === 4326 || s === 4686 ? "g" : s === 9377 ? "n" : "z");
  if (clase(det.srid) === clase(srid)) return null;
  return <p className="tec-aviso tec-aviso-error" role="alert">Las coordenadas del archivo parecen de {nombreSistema(det.srid)}, no de {nombreSistema(srid)}: revise antes de subir.</p>;
}

function Progreso({ s }: { s: Subida }) {
  const pct = Math.round((100 * s.enviadas) / Math.max(1, s.total));
  return (
    <div className="cg-progreso" role="status" aria-live="polite">
      <div className="cg-barra"><span style={{ width: `${pct}%` }} /></div>
      <p className="tec-ayuda">Subiendo: {n(s.enviadas)} de {n(s.total)} elementos ({pct} %). Si se corta, vuelva a elegir el mismo archivo: la carga sigue donde iba.</p>
    </div>
  );
}

function CargaAbierta({ capa, onAnulada }: { capa: CapaCargue; onAnulada: () => void }) {
  const a = capa.abierta!;
  return (
    <div className="tec-aviso tec-aviso-error cg-abierta" role="alert">
      <p>Hay una carga abierta de esta capa (la {a.carga_id}, de {a.autor}, {fecha(a.creado_en)}; llegaron {n(a.recibidas)} de {n(a.filas)} filas). Para seguirla, elija el mismo archivo con la misma llave y el mismo sistema; para empezar otra, anúlela.</p>
      <ConMotivo rotulo="Anular la carga abierta" onEnviar={async (m) => { await apiCargue.anular(a.carga_id, m); onAnulada(); }} />
    </div>
  );
}

const ACCION: Record<string, string> = { nuevo: "Nuevos", cambiado: "Cambiados", igual: "Iguales", reactivar: "Vuelven", nuevo_por_tipo: "Cambian de tipo",
  ubicacion: "Cambian de ubicación", conserva_verificada: "Conservan la verificada", nuevo_sin_codigo: "Nuevos sin código" };
const CAMPO: Record<string, string> = { nombre: "nombre", estado_codigo: "estado", clase: "clase", efecto: "efecto", material_codigo: "material", diametro_mm: "diámetro (mm)",
  capacidad: "capacidad", profundidad_m: "profundidad (m)", origen: "origen" };
function RevisarResumen({ resumen: r, muestra, esMue, carga, onDevuelto }: { resumen: Resumen; muestra: Muestra | null; esMue: boolean; carga: number; onDevuelto: () => Promise<void> }) {
  const f = r.frente_a_vigente ?? {};
  const cruce = r.detalle?.cruce_por_geometria as { cruzados: number; sin_par_nuevos: number; tolerancia_m: number } | undefined;
  return (
    <div className="cg-revisar" data-testid="resumen">
      <div className="cg-cifras">
        {esMue ? (<>
          <Cifra t="Nuevos" v={(f.nuevo ?? 0) + (f.nuevo_sin_codigo ?? 0)} /><Cifra t="Cambian de ubicación" v={f.ubicacion} /><Cifra t="Se desactivan" v={r.desactivar?.length} /><Cifra t="Iguales" v={(f.igual ?? 0) + (f.conserva_verificada ?? 0)} />
        </>) : (<>
          <Cifra t="Nuevos" v={(f.nuevo ?? 0) + (f.nuevo_por_tipo ?? 0)} /><Cifra t="Cambiados" v={f.cambiado} /><Cifra t="Retirados" v={r.retirados} /><Cifra t="Iguales" v={(f.igual ?? 0) + (f.reactivar ?? 0)} />
        </>)}
      </div>
      <p className="tec-ayuda">Llegaron {n(r.recibidas)} de {n(r.esperadas)} filas{r.errores ? ` · ${n(r.errores)} con error de geometría` : ""}{f.reactivar ? ` · ${n(f.reactivar)} vuelven (estaban retirados)` : ""}{f.conserva_verificada ? ` · ${n(f.conserva_verificada)} conservan su ubicación verificada` : ""}.</p>
      {cruce ? <p className="tec-aviso tec-aviso-info">Cruce por geometría (a {cruce.tolerancia_m} m): {n(cruce.cruzados)} elementos encontraron su par vigente y {n(cruce.sin_par_nuevos)} entran como nuevos.</p> : null}
      {r.bloqueos.length ? <div className="tec-aviso tec-aviso-error" role="alert"><strong>No se puede publicar todavía:</strong><ul>{r.bloqueos.map((b, i) => <li key={i}>{b}</li>)}</ul></div> : <p className="tec-aviso tec-aviso-info" role="status">Lista para publicar.</p>}
      {r.avisos.length ? <div className="tec-aviso tec-aviso-info"><strong>Avisos:</strong><ul>{r.avisos.map((a, i) => <li key={i}>{a}</li>)}</ul></div> : null}
      {muestra ? <MapaMuestra m={muestra} /> : null}
      {muestra && muestra.errores.length ? <p className="tec-ayuda">Primeras filas con error: {muestra.errores.slice(0, 5).map((e) => `fila ${e.orden}${e.llave ? ` (${e.llave})` : ""}: ${e.error}`).join(" · ")}</p> : null}
      {r.choques && r.choques.length ? (
        <section className="cg-choques" aria-labelledby="cg-ch-tit">
          <h3 id="cg-ch-tit">Choques con la ficha ({n(r.choques.length)})</h3>
          <p className="tec-ayuda">Estos campos se editaron en la ficha y la capa trae otro valor: gana la ficha. Si Técnica ya corrigió el modelo, devuelva el campo a la capa (con motivo): desde esta publicación lo manda la capa, hasta que se vuelva a editar en la ficha.</p>
          {r.choques.slice(0, 100).map((c) => <ItemChoque key={`${c.codigo}-${c.campo}`} c={c} carga={carga} onDevuelto={onDevuelto} />)}
          {r.choques.length > 100 ? <p className="tec-ayuda">Y {n(r.choques.length - 100)} más.</p> : null}
        </section>) : null}
      {esMue && r.puntos ? (
        <details className="cg-como"><summary>Los puntos, uno por uno ({r.puntos.length})</summary>
          <ul className="cg-puntos">{r.puntos.map((p) => <li key={p.orden}><strong>{p.codigo ?? `fila ${p.orden}`}</strong> {p.nombre ?? ""} · {ACCION[p.accion] ?? p.accion} · {p.exactitud}{p.barrio ? ` · ${p.barrio}` : ""}{p.error ? ` · ${p.error}` : ""}</li>)}</ul>
        </details>) : null}
    </div>
  );
}
const Cifra = ({ t, v }: { t: string; v: number | undefined }) => <div className="cg-cifra"><span>{t}</span><strong>{n(v)}</strong></div>;

function ItemChoque({ c, carga, onDevuelto }: { c: Choque; carga: number; onDevuelto: () => Promise<void> }) {
  const campo = c.campo.startsWith("atributos.") ? c.campo.slice(10).replace(/_/g, " ") : CAMPO[c.campo] ?? c.campo;
  return (
    <article className="cg-choque" data-testid={`choque-${c.codigo}-${c.campo}`}>
      <p><strong>{c.codigo}</strong> · {campo}: ficha «{c.ficha ?? "—"}», capa «{c.capa ?? "—"}»</p>
      <ConMotivo rotulo="Devolver este campo a la capa" onEnviar={async (m) => { await apiCargue.devolverCampo(carga, c.codigo, c.campo, m); await onDevuelto(); }} />
    </article>
  );
}

/** Acción con motivo (anular, revertir, devolver): botón que abre el motivo y lo envía. */
function ConMotivo({ rotulo, onEnviar }: { rotulo: string; onEnviar: (motivo: string) => Promise<void> }) {
  const [abierto, setAbierto] = useState(false);
  const [motivo, setMotivo] = useState("");
  const [msg, setMsg] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);
  const id = useRef(`cgm-${Math.random().toString(36).slice(2, 8)}`).current;
  if (!abierto) return <button type="button" className="tec-boton-sec" onClick={() => { setAbierto(true); setMsg(null); }}>{rotulo}</button>;
  return (
    <div className="dash-motivo">
      <label htmlFor={id}>Motivo ({rotulo.toLowerCase()})</label>
      <input id={id} type="text" maxLength={1000} value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Por qué (10 caracteres o más)" />
      {msg ? <p className="tec-aviso tec-aviso-error" role="alert">{msg}</p> : null}
      <div className="tec-acciones">
        <button type="button" className="tec-boton itv-guardar" disabled={enviando} onClick={async () => {
          if (motivo.trim().length < 10) { setMsg("Escriba el motivo (10 caracteres o más)."); return; }
          setEnviando(true); setMsg(null);
          try { await onEnviar(motivo.trim()); setAbierto(false); setMotivo(""); } catch (e) { setMsg(err(e)); } finally { setEnviando(false); }
        }}>{enviando ? "Guardando…" : `Confirmar: ${rotulo.toLowerCase()}`}</button>
        <button type="button" className="tec-boton-sec" disabled={enviando} onClick={() => setAbierto(false)}>Cancelar</button>
      </div>
    </div>
  );
}

/** Vista previa: una muestra de lo que llegó (hasta 400 elementos) y la caja de todo, sobre el mapa de calles. */
function MapaMuestra({ m }: { m: Muestra }) {
  const cont = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!cont.current) return;
    const caja: GeoJSON.FeatureCollection = { type: "FeatureCollection", features: m.caja ? [{ type: "Feature", properties: {}, geometry: { type: "Polygon",
      coordinates: [[[m.caja[0], m.caja[1]], [m.caja[2], m.caja[1]], [m.caja[2], m.caja[3]], [m.caja[0], m.caja[3]], [m.caja[0], m.caja[1]]]] } }] : [] };
    const mapa = new maplibregl.Map({
      container: cont.current, center: CENTRO_VALLEDUPAR, zoom: 11.5, maxZoom: 19, minZoom: 5, attributionControl: { compact: true }, dragRotate: false, touchPitch: false,
      style: { version: 8, sources: { base: FUENTE_BASE_CALLES, m: { type: "geojson", data: m.muestra }, caja: { type: "geojson", data: caja } },
        layers: [
          { id: "base", type: "raster", source: "base" },
          { id: "caja", type: "line", source: "caja", paint: { "line-color": "#6D28D9", "line-width": 2, "line-dasharray": [2, 2] } },
          { id: "pol", type: "fill", source: "m", filter: ["==", ["geometry-type"], "Polygon"], paint: { "fill-color": "rgba(31,95,168,0.25)", "fill-outline-color": "#1F5FA8" } },
          { id: "lin", type: "line", source: "m", filter: ["==", ["geometry-type"], "LineString"], paint: { "line-color": "#1F5FA8", "line-width": 2.5 } },
          { id: "pto", type: "circle", source: "m", filter: ["==", ["geometry-type"], "Point"], paint: { "circle-radius": 4, "circle-color": "#1F5FA8", "circle-stroke-color": "#fff", "circle-stroke-width": 1.5 } },
        ] },
    });
    mapa.on("error", () => {});
    if (m.caja) mapa.fitBounds([[m.caja[0], m.caja[1]], [m.caja[2], m.caja[3]]], { padding: 24, maxZoom: 17, duration: 0 });
    (cont.current as unknown as { __mapa?: maplibregl.Map }).__mapa = mapa;     // para las pruebas en Chrome
    return () => mapa.remove();
  }, [m]);
  return (
    <figure className="cg-mapa">
      <div ref={cont} className="cg-mapa-lienzo" role="img" aria-label={`Vista previa de la carga: ${m.muestra.features.length} de ${m.con_geometria} elementos y la caja de todos`} />
      <figcaption className="tec-ayuda">Vista previa: {n(m.muestra.features.length)} de {n(m.con_geometria)} elementos; la línea morada es la caja de todo lo que llegó. Confirme que cae en Valledupar.</figcaption>
    </figure>
  );
}

// =====================================================================================================================
// Historial de una capa y «Volver a la versión anterior»
// =====================================================================================================================
const ESTADO_CARGA: Record<string, string> = { abierta: "Abierta", publicada: "Publicada", revertida: "Revertida", anulada: "Anulada" };
function Historial({ capa, puede, onCerrar }: { capa: CapaCargue; puede: boolean; onCerrar: (aviso?: string) => void }) {
  const [cargas, setCargas] = useState<CargaHistorial[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0);
  useEffect(() => { apiCargue.historial(capa.codigo).then((r) => setCargas(r.cargas)).catch((e) => setError(err(e))); }, [capa.codigo, vez]);
  const ultima = cargas?.find((c) => c.estado === "publicada");
  return (
    <section className="tec-tarjeta cg-asistente" aria-labelledby="cg-his-tit">
      <h2 id="cg-his-tit">{capa.nombre} · Historial</h2>
      {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : !cargas ? <p className="tec-sub" role="status">Cargando…</p>
        : !cargas.length ? <p className="red-vacio">Esta capa todavía no tiene cargas.</p>
        : cargas.map((c) => {
          const pub = c.eventos.find((e) => e.tipo === "publicar");
          return (
            <article key={c.carga_id} className="cg-capa" data-testid={`carga-${c.carga_id}`}>
              <div className="cg-capa-cab"><h3>Carga {c.carga_id}{pub?.version_capa ? ` · versión ${pub.version_capa}` : ""}</h3><span className="itv-etiqueta">{ESTADO_CARGA[c.estado]}</span></div>
              <p className="tec-ayuda">{fecha(c.creado_en)} · {c.autor} · {FMT[c.formato] ?? c.formato} · {nombreSistema(c.srid)} · llave {c.columna_llave === SIN_LLAVE ? "por geometría" : c.columna_llave} · {n(c.filas)} filas{c.masiva ? " · carga masiva" : ""}</p>
              {c.nota ? <p className="tec-ayuda">Archivo: {c.nota}</p> : null}
              {c.eventos.map((e, i) => <p key={i} className="red-texto">{e.tipo === "publicar" ? `Publicada: ${n(e.nuevos)} nuevos, ${n(e.cambiados)} cambiados, ${n(e.retirados)} retirados` : e.tipo === "revertir" ? "Revertida" : "Anulada"} · «{e.motivo}» · {e.autor} · {fecha(e.creado_en)}</p>)}
            </article>);
        })}
      {puede && ultima ? (
        <div className="cg-revertir">
          <p className="tec-ayuda">Volver a la versión anterior deshace la carga {ultima.carga_id}: lo que retiró vuelve, lo que agregó deja de contar y lo que cambió vuelve a su versión anterior. Nada se borra.</p>
          <ConMotivo rotulo="Volver a la versión anterior" onEnviar={async (m) => { await apiCargue.revertir(capa.codigo, m); setVez((v) => v + 1); }} />
        </div>) : null}
      <button type="button" className="tec-boton-sec" onClick={() => onCerrar()}>Volver a las capas</button>
    </section>
  );
}

// =====================================================================================================================
// Carga masiva: un GeoPackage o un zip con varias capas, repartido por el nombre
// =====================================================================================================================
const ALIAS: Record<string, string[]> = {
  acueducto: ["acueducto", "redes_acueducto", "red_acueducto", "tuberia", "tuberias", "tramos_acueducto", "pipes", "distribucion"],
  alc_conductos: ["conductos", "alc_conductos", "colectores", "tramos_alcantarillado", "conductos_alcantarillado", "redes_alcantarillado"],
  alc_pozos: ["pozos", "alc_pozos", "pozos_inspeccion", "manholes"], alc_descargas: ["descargas", "alc_descargas", "vertimientos"],
  acometidas: ["acometidas", "acometida"], captaciones: ["captaciones", "bocatomas"], aduccion: ["aduccion", "tuberia_aduccion"], desarenadores: ["desarenadores"],
  bombeo_ap: ["bombeo_ap", "estaciones_bombeo_ap", "eba"], sumideros: ["sumideros"], interceptores: ["interceptores", "emisarios"], bombeo_ar: ["bombeo_ar", "ebar", "ebr"],
  ptar: ["ptar"], sectores: ["sectores", "sectores_hidraulicos"], sensores: ["sensores"], scada: ["scada", "telemetria"], muestreo: ["muestreo", "puntos_muestreo", "mue"],
};
const ORDEN_PUBLICAR = ["alc_pozos", "alc_descargas"];       // los conductos se enlazan con ellos: van antes
type ItemMasiva = { l: CapaLeida; destino: string; llave: string; srid: number | null; estado?: "subiendo" | "lista" | "bloqueada" | "error" | "publicada";
  carga?: number; resumen?: Resumen; msg?: string; enviadas?: number; publicada?: Publicada };
function Masiva({ datos, onCerrar }: { datos: CapasResp; onCerrar: (aviso?: string) => void }) {
  const [archivo, setArchivo] = useState<File | null>(null);
  const [items, setItems] = useState<ItemMasiva[] | null>(null);
  const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [fase, setFase] = useState<"elegir" | "revisar" | "hecho">("elegir");
  const [nota, setNota] = useState("");
  const cargables = datos.capas.filter((c) => c.fuente === "carga" && c.lector && c.codigo !== "muestreo");
  const destinoDe = (nombre: string) => { const k = normalizarNombre(nombre); return cargables.find((c) => c.codigo === k || normalizarNombre(c.nombre) === k || (ALIAS[c.codigo] ?? []).includes(k))?.codigo ?? ""; };
  const llaveDe = (destino: string, l: CapaLeida) => { const c = cargables.find((x) => x.codigo === destino); if (!c) return ""; return c.columna_llave ?? proponerLlave(l) ?? SIN_LLAVE; };
  const poner = (i: number, cambio: Partial<ItemMasiva>) => setItems((xs) => xs && xs.map((x, k) => (k === i ? { ...x, ...cambio } : x)));

  async function elegir(f: File | null) {
    setArchivo(f); setItems(null); setMsg(null); setFase("elegir");
    if (!f) return;
    try {
      const cs = (await leerArchivo(f)).filter((c) => !c.tabla);
      if (!cs.length) throw new Error("El archivo no trae capas con geometría.");
      setItems(cs.map((l) => { const d = destinoDe(l.nombre); return { l, destino: d, llave: llaveDe(d, l), srid: l.srid }; }));
    } catch (e) { setMsg({ ok: false, t: err(e) }); }
  }
  async function subirTodas() {
    if (!items || !archivo) return;
    const usados = items.filter((x) => x.destino);
    const dup = usados.map((x) => x.destino).filter((d, i, a) => a.indexOf(d) !== i);
    if (dup.length) { setMsg({ ok: false, t: `Dos capas del archivo van a la misma capa (${[...new Set(dup)].join(", ")}): elija una.` }); return; }
    if (usados.some((x) => !x.srid)) { setMsg({ ok: false, t: "Elija el sistema de coordenadas de cada capa." }); return; }
    setOcupado(true); setMsg(null);
    const masiva = crypto.randomUUID();
    const hFile = await sha256Hex(await archivo.arrayBuffer());
    for (let i = 0; i < items.length; i++) {
      const it = items[i];
      if (!it.destino || !it.srid) continue;
      poner(i, { estado: "subiendo", msg: undefined, enviadas: 0 });
      try {
        const capa = cargables.find((c) => c.codigo === it.destino)!;
        const fija = capa.columna_llave;
        const filas: FilaLote[] = it.l.filas.map((f, k) => {
          const a = { ...f.atributos };
          if (fija) { const c = Object.keys(a).find((x) => x.toLowerCase() === fija.toLowerCase()); if (c && c !== fija) { a[fija] = a[c]; delete a[c]; } }
          return { orden: k + 1, wkt: f.wkt, atributos: a };
        });
        const huella = await sha256Hex(`${hFile}|${it.l.nombre}|${it.llave}|${it.srid}`);
        const ini = await apiCargue.iniciar({ capa: it.destino, sha256: huella, formato: it.l.formato, srid: it.srid, columna_llave: it.llave, filas: filas.length,
          nota: `${archivo.name} · ${it.l.nombre}`.slice(0, 500), masiva });
        let env = 0;
        for (const lote of enLotes(filas, datos.lote_max_filas || 200)) { await apiCargue.lote(ini.carga_id, lote); env += lote.length; poner(i, { enviadas: env }); }
        const r = await apiCargue.resumen(ini.carga_id);
        poner(i, { estado: r.lista_para_publicar ? "lista" : "bloqueada", carga: ini.carga_id, resumen: r });
      } catch (e) { poner(i, { estado: "error", msg: err(e) }); }
    }
    setOcupado(false); setFase("revisar");
  }
  async function publicarTodas() {
    if (!items) return;
    if (nota.trim().length < 10) { setMsg({ ok: false, t: "Escriba la nota de la versión (10 caracteres o más)." }); return; }
    setOcupado(true); setMsg(null);
    const orden = items.map((x, i) => ({ x, i })).filter(({ x }) => x.estado === "lista" && x.carga)
      .sort((a, b) => (ORDEN_PUBLICAR.includes(b.x.destino) ? 1 : 0) - (ORDEN_PUBLICAR.includes(a.x.destino) ? 1 : 0));
    for (const { x, i } of orden) {
      try { const p = await apiCargue.publicar(x.carga!, nota.trim()); poner(i, { estado: "publicada", publicada: p }); }
      catch (e) { poner(i, { estado: "error", msg: err(e) }); setMsg({ ok: false, t: `Se detuvo en ${x.l.nombre}: ${err(e)}. Las demás quedan abiertas para revisarlas una por una.` }); break; }
    }
    setOcupado(false); setFase("hecho");
  }
  const listas = items?.filter((x) => x.estado === "lista").length ?? 0;
  return (
    <section className="tec-tarjeta cg-asistente" aria-labelledby="cg-mas-tit" data-testid="masiva">
      <h2 id="cg-mas-tit">Cargar varias capas de un archivo</h2>
      <p className="tec-sub">GeoPackage o zip con varios SHP. Cada capa se asigna por su nombre; las que no coincidan se eligen a mano. Cada una queda como su propia versión.</p>
      {fase === "elegir" ? (
        <div className="tec-campo">
          <label htmlFor="cg-mas-arch">Archivo (.gpkg o .zip)</label>
          <input id="cg-mas-arch" type="file" accept=".gpkg,.zip" disabled={ocupado} onChange={(e) => void elegir(e.target.files?.[0] ?? null)} />
        </div>) : null}
      {items?.map((it, i) => (
        <article key={i} className="cg-capa" data-testid={`masiva-${normalizarNombre(it.l.nombre)}`}>
          <div className="cg-capa-cab"><h3>{it.l.nombre}</h3><span className="tec-ayuda">{n(it.l.filas.length)} elementos · {Object.keys(it.l.tipos).join(", ")}</span></div>
          {fase === "elegir" ? (
            <div className="cg-dos">
              <div className="tec-campo"><label htmlFor={`cg-md-${i}`}>Va a la capa</label>
                <select id={`cg-md-${i}`} value={it.destino} onChange={(e) => poner(i, { destino: e.target.value, llave: llaveDe(e.target.value, it.l) })}>
                  <option value="">No cargar</option>{cargables.map((c) => <option key={c.codigo} value={c.codigo}>{c.nombre}</option>)}</select></div>
              <div className="tec-campo"><label htmlFor={`cg-ms-${i}`}>Sistema de coordenadas</label>
                <select id={`cg-ms-${i}`} value={it.srid ?? ""} onChange={(e) => poner(i, { srid: e.target.value ? Number(e.target.value) : null })}>
                  <option value="">Elija…</option>{SISTEMAS.map((s) => <option key={s.srid} value={s.srid}>{s.nombre}</option>)}</select></div>
              {it.destino && !cargables.find((c) => c.codigo === it.destino)?.columna_llave ? (
                <div className="tec-campo"><label htmlFor={`cg-mk-${i}`}>Columna llave</label>
                  <select id={`cg-mk-${i}`} value={it.llave} onChange={(e) => poner(i, { llave: e.target.value })}>
                    {it.l.columnas.filter((c) => revisarLlave(it.l.filas, c).unica).map((c) => <option key={c} value={c}>{c} (única)</option>)}
                    <option value={SIN_LLAVE}>Sin columna llave: cruzar por geometría</option></select></div>) : null}
              {it.destino ? <p className="tec-ayuda">{cargables.find((c) => c.codigo === it.destino)?.columna_llave ? `Llave fija: ${it.llave} · ` : ""}detectado: {nombreSistema(it.l.srid)}</p> : null}
            </div>
          ) : it.destino ? (
            <>
              {it.estado === "subiendo" ? <p className="tec-ayuda" role="status">Subiendo {n(it.enviadas)} de {n(it.l.filas.length)}…</p> : null}
              {it.resumen ? <p>{cargables.find((c) => c.codigo === it.destino)?.nombre}: {n((it.resumen.frente_a_vigente.nuevo ?? 0) + (it.resumen.frente_a_vigente.nuevo_por_tipo ?? 0))} nuevos · {n(it.resumen.frente_a_vigente.cambiado)} cambiados · {n(it.resumen.retirados)} retirados · {n(it.resumen.frente_a_vigente.igual)} iguales</p> : null}
              {it.resumen?.bloqueos.length ? <ul className="tec-aviso tec-aviso-error">{it.resumen.bloqueos.map((b, k) => <li key={k}>{b}</li>)}</ul> : null}
              {it.resumen?.choques?.length ? <p className="tec-ayuda">{n(it.resumen.choques.length)} choques con la ficha (gana la ficha). Para devolver campos a la capa, siga esta carga desde «Cargar versión» de la capa.</p> : null}
              {it.estado === "publicada" && it.publicada ? <p className="tec-aviso tec-aviso-info">Publicada: versión {it.publicada.version_capa}.</p> : null}
              {it.msg ? <p className="tec-aviso tec-aviso-error" role="alert">{it.msg}</p> : null}
            </>
          ) : <p className="tec-ayuda">No se carga.</p>}
        </article>))}
      {fase === "revisar" ? (
        <div className="tec-campo">
          <label htmlFor="cg-mas-nota">Nota de la versión (para todas las capas)</label>
          <input id="cg-mas-nota" type="text" maxLength={1000} value={nota} onChange={(e) => setNota(e.target.value)} placeholder="Qué trae y de dónde salió (10 caracteres o más)" />
          <p className="tec-ayuda">Se publican las {listas} listas, una por una (los pozos y las descargas antes que los conductos). Las bloqueadas quedan abiertas: anúlelas o corríjalas desde su capa.</p>
        </div>) : null}
      {msg ? <p className={`tec-aviso ${msg.ok ? "tec-aviso-info" : "tec-aviso-error"}`} role={msg.ok ? "status" : "alert"}>{msg.t}</p> : null}
      <div className="tec-acciones cg-nav">
        <button type="button" className="tec-boton-sec" disabled={ocupado} onClick={() => onCerrar(fase === "hecho" ? "Carga masiva terminada." : undefined)}>{fase === "hecho" ? "Volver a las capas" : "Salir"}</button>
        {fase === "elegir" ? <button type="button" className="tec-boton" disabled={!items?.some((x) => x.destino) || ocupado} aria-busy={ocupado} onClick={() => void subirTodas()}>{ocupado ? "Subiendo…" : "Subir y revisar todas"}</button> : null}
        {fase === "revisar" ? <button type="button" className="tec-boton" disabled={!listas || ocupado} aria-busy={ocupado} onClick={() => void publicarTodas()}>{ocupado ? "Publicando…" : `Publicar las ${listas} listas`}</button> : null}
      </div>
    </section>
  );
}
