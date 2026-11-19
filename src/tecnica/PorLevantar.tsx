import { Suspense, useEffect, useMemo, useState } from "react";
import { lazyConRecarga } from "../lib/recarga";
import "./encontrar.css";
import { apiLev, metros, metrosEntre, type FiltroLevantar, type ListaLevantar, type PuntoLevantar } from "./apiLevantar";
import { ErrorTec } from "./apiTecnica";
import { HojaLevantamiento } from "./HojaLevantamiento";
import { ActaLevantar } from "./ActaLevantar";


// Dashboard distribución → Por verificar → «Otros activos por levantamiento» (Corte 14). Los activos que alguien encontró en la calle y no están en la red.
// Estados, de solo agregar: reportado → asignado a levantamiento → levantado (con el activo nuevo) | descartado con motivo. «Reabrir» lo devuelve a reportado.
// «Quién» es el nombre del funcionario; ningún dato de suscriptores. Cada punto tiene su «Ver acta (PDF)» (con sus fotos; la consulta queda en la auditoría).
// POSIBLES REPETIDOS (19-nov): un punto por levantar que tiene otro del mismo servicio a menos de la distancia de duplicado (10 m) se marca «Posible repetido de
// LEV-…» (el que se reportó después), se pueden ver los dos en un minimapa y se descarta el repetido con motivo. Se calcula aquí, con los puntos por levantar
// que trae la lista (se traen todas sus páginas, hasta MAX_PARA_REPETIDOS); nada se descarta solo.
const MiniMapaRepetidos = lazyConRecarga(() => import("./MiniMapaRepetidos").then((m) => ({ default: m.MiniMapaRepetidos })));
const DUPLICADO_M = 10, MAX_PARA_REPETIDOS = 400;
type Vecino = { codigo: string; distancia_m: number; lat: number; lon: number };
type Repetido = { vecinos: Vecino[]; original: Vecino | null };      // «original»: el vecino más antiguo, si este punto no es el más antiguo del grupo
/** Para cada punto ABIERTO, los otros abiertos del mismo servicio a menos de `umbral` metros. Entre vecinos, el de código menor es el original. */
export function posiblesRepetidos(items: PuntoLevantar[], umbral: number): Map<string, Repetido> {
  const abiertos = items.filter((p) => p.estado === "reportado" || p.estado === "asignado");
  const r = new Map<string, Repetido>();
  for (const p of abiertos) {
    const vecinos = abiertos.filter((q) => q.codigo !== p.codigo && q.servicio === p.servicio && Math.abs(q.lat - p.lat) < 0.001 && Math.abs(q.lon - p.lon) < 0.001)
      .map((q) => ({ codigo: q.codigo, distancia_m: metrosEntre(p, q), lat: q.lat, lon: q.lon })).filter((v) => v.distancia_m < umbral).sort((a, b) => a.codigo.localeCompare(b.codigo));
    if (vecinos.length) r.set(p.codigo, { vecinos, original: vecinos[0].codigo < p.codigo ? vecinos[0] : null });
  }
  return r;
}
const FILTROS: { c: FiltroLevantar; n: string }[] = [{ c: "abiertos", n: "Por levantar" }, { c: "levantado", n: "Levantados" }, { c: "descartado", n: "Descartados" }, { c: "todos", n: "Todos" }];
const fechaHora = (iso: string) => new Date(iso).toLocaleString("es-CO", { day: "numeric", month: "short", year: "numeric", hour: "numeric", minute: "2-digit", timeZone: "America/Bogota" });
const err = (e: unknown) => (e instanceof ErrorTec && e.tipo === "permiso" ? "Solo el supervisor de distribución o el administrador ven los activos por levantar." : e instanceof Error ? e.message : "No se pudo completar.");
type Accion = "asignado" | "levantado" | "descartado" | "reabierto";
const ACCION: Record<Accion, { boton: string; campo: string; ayuda: string; pideActivo?: boolean; motivoMin: number }> = {
  asignado: { boton: "Asignar a levantamiento", campo: "Nota (opcional): cuadrilla o fecha", ayuda: "", motivoMin: 0 },
  levantado: { boton: "Marcar levantado", campo: "Nota (opcional)", ayuda: "Escriba el código del activo nuevo, ya publicado en la red.", pideActivo: true, motivoMin: 0 },
  descartado: { boton: "Descartar", campo: "Motivo (10 caracteres o más)", ayuda: "", motivoMin: 10 },
  reabierto: { boton: "Reabrir", campo: "Motivo (10 caracteres o más)", ayuda: "Vuelve a «reportado». El historial se conserva.", motivoMin: 10 },
};

export function PorLevantarLista({ onFicha, onConteo }: { onFicha: (c: string) => void; onConteo?: (n: number) => void }) {
  const [filtro, setFiltro] = useState<FiltroLevantar>("abiertos");
  const [d, setD] = useState<ListaLevantar | null>(null);
  const [items, setItems] = useState<PuntoLevantar[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0);
  const [aviso, setAviso] = useState<string | null>(null);
  const [hoja, setHoja] = useState(false);
  const [soloRepetidos, setSoloRepetidos] = useState(false);
  const [umbral, setUmbral] = useState(DUPLICADO_M);
  useEffect(() => { let vivo = true; apiLev.inicio().then((i) => { if (vivo && i.duplicado_m > 0) setUmbral(i.duplicado_m); }).catch(() => { /* queda en 10 m */ }); return () => { vivo = false; }; }, []);
  useEffect(() => {
    let vivo = true; setD(null); setError(null);
    apiLev.lista(filtro, null).then(async (r) => {
      if (!vivo) return;
      setD(r); setItems(r.items); onConteo?.(r.abiertos);
      // «Por levantar»: se traen las demás páginas para que los posibles repetidos salgan completos (un repetido puede caer en otra página)
      let todos = r.items, sig = r.siguiente;
      while (filtro === "abiertos" && sig && todos.length < MAX_PARA_REPETIDOS) {
        const mas = await apiLev.lista(filtro, sig).catch(() => null);
        if (!vivo || !mas) return;
        todos = [...todos, ...mas.items]; sig = mas.siguiente;
        setItems(todos); setD({ ...r, siguiente: sig });
      }
    }).catch((e) => { if (vivo) setError(err(e)); });
    return () => { vivo = false; };
  }, [filtro, vez]); // eslint-disable-line react-hooks/exhaustive-deps
  const repetidos = useMemo(() => posiblesRepetidos(items, umbral), [items, umbral]);
  const nRepetidos = useMemo(() => [...repetidos.values()].filter((x) => x.original).length, [repetidos]);
  if (error) return <section className="tec-tarjeta" role="alert"><p>{error}</p></section>;
  const n = (c: FiltroLevantar) => !d ? null : c === "abiertos" ? d.abiertos : c === "todos" ? Object.values(d.conteos).reduce((s, x) => s + (x ?? 0), 0) : d.conteos[c] ?? 0;
  return (
    <div data-testid="lev-bandeja">
      <p className="tec-ayuda dan-pad-x">Activos encontrados en la calle que no están en la red. Asígnelos a levantamiento; cuando la capa nueva esté publicada, márquelos «levantado» con el código del activo.</p>
      <div className="dan-fila dan-pad-x" role="group" aria-label="Qué activos por levantar ver">
        {FILTROS.map((f) => <button key={f.c} type="button" className="dan-opcion" aria-pressed={filtro === f.c} data-filtro-lev={f.c} onClick={() => setFiltro(f.c)}>{f.n}{n(f.c) !== null ? `: ${n(f.c)}` : ""}</button>)}
      </div>
      {filtro === "abiertos" && d && d.abiertos > 0 ? <div className="dan-pad-x lev-pdf"><button type="button" className="tec-boton-sec" data-testid="lev-pdf" onClick={() => setHoja(true)}>Descargar en PDF (hoja de levantamiento)</button></div> : null}
      {hoja ? <HojaLevantamiento estado="abiertos" onCerrar={() => setHoja(false)} /> : null}
      {filtro === "abiertos" && d && nRepetidos > 0 ? (
        <div className="tec-aviso lev-repetidos dan-pad-x" role="status" data-testid="lev-repetidos">
          <p><strong>{nRepetidos === 1 ? "1 posible repetido" : `${nRepetidos} posibles repetidos`}:</strong> puntos del mismo servicio a menos de {Math.round(umbral)} m de otro que se reportó antes. Mírelos en el mapa y descarte el que sobre, con el motivo.</p>
          <button type="button" className="tec-boton-sec" aria-pressed={soloRepetidos} data-testid="lev-solo-repetidos" onClick={() => setSoloRepetidos((x) => !x)}>{soloRepetidos ? "Ver todos" : "Ver solo los posibles repetidos y sus originales"}</button>
        </div>) : null}
      {aviso ? <p className="tec-aviso tec-aviso-info dan-pad-x" role="status">{aviso} <button type="button" className="tec-enlace" onClick={() => setAviso(null)}>Cerrar</button></p> : null}
      {!d ? <p className="tec-sub dan-pad" role="status">Cargando…</p>
        : !items.length ? <section className="tec-tarjeta"><p className="red-vacio">No hay activos {filtro === "abiertos" ? "por levantar" : "en ese estado"}.</p></section>
        : <>
            {items.filter((p) => !soloRepetidos || filtro !== "abiertos" || repetidos.has(p.codigo)).map((p) => <Punto key={p.codigo} p={p} repetido={filtro === "abiertos" ? repetidos.get(p.codigo) : undefined} onFicha={onFicha} onCambio={(t) => { setAviso(t); setVez((v) => v + 1); }} />)}
            {d.siguiente ? <div className="dan-pad-x"><button type="button" className="tec-boton-sec" onClick={() => apiLev.lista(filtro, d.siguiente)
              .then((r) => { setItems([...items, ...r.items]); setD({ ...d, siguiente: r.siguiente }); }).catch(() => {})}>Cargar más</button></div> : null}
          </>}
    </div>
  );
}

function Punto({ p, repetido, onFicha, onCambio }: { p: PuntoLevantar; repetido?: Repetido; onFicha: (c: string) => void; onCambio: (aviso: string) => void }) {
  const [verMapa, setVerMapa] = useState(false);      // el punto y sus posibles repetidos, juntos en el minimapa
  const [acta, setActa] = useState(false);      // «Ver acta (PDF)»: el mismo documento que descarga quien reportó
  const [accion, setAccion] = useState<Accion | null>(null);
  const [activo, setActivo] = useState("");
  const [motivo, setMotivo] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const abierto = p.estado === "reportado" || p.estado === "asignado";
  const acciones: Accion[] = abierto ? [...(p.estado === "reportado" ? ["asignado" as const] : []), "levantado", "descartado"] : ["reabierto"];
  const a = accion ? ACCION[accion] : null;
  const puede = !!a && motivo.trim().length >= a.motivoMin && (!a.pideActivo || /^[A-Za-z]{3}-\d{1,8}$/.test(activo.trim()));
  async function enviar() {
    if (!accion || !puede || enviando) return;
    setEnviando(true); setError(null);
    try {
      const r = await apiLev.evento(p.codigo, accion, { activo: ACCION[accion].pideActivo ? activo.trim().toUpperCase() : null, motivo: motivo.trim() || null });
      onCambio(`${p.codigo} quedó «${r.estado_nombre.toLowerCase()}»${r.activo ? ` (${r.activo})` : ""}.`);
    } catch (e) { setError(err(e)); setEnviando(false); }
  }
  return (
    <section className="tec-tarjeta itv-bandeja" aria-label={p.codigo} data-levantar={p.codigo} data-estado={p.estado}>
      <h2>{p.codigo} · {p.tipo_nombre} de {p.servicio} <span className={`itv-etiqueta${p.estado === "levantado" ? " lev-etq-ok" : ""}`}>{p.estado_nombre}</span>{p.precision_baja ? <> <span className="itv-etiqueta lev-etq-baja">Precisión baja</span></> : null}</h2>
      {repetido ? (
        <div className={`tec-aviso lev-repetido${repetido.original ? "" : " lev-repetido-original"}`} role="note" data-testid="lev-repetido" data-original={repetido.original?.codigo ?? ""}>
          {repetido.original
            ? <p><strong>Posible repetido de {repetido.original.codigo}</strong> (a {metros(repetido.original.distancia_m)}, reportado antes).{repetido.vecinos.length > 1 ? ` También cerca: ${repetido.vecinos.filter((v) => v.codigo !== repetido.original!.codigo).map((v) => `${v.codigo} (${metros(v.distancia_m)})`).join(", ")}.` : ""}</p>
            : <p><strong>{repetido.vecinos.length === 1 ? "Tiene un posible repetido" : `Tiene ${repetido.vecinos.length} posibles repetidos`}:</strong> {repetido.vecinos.map((v) => `${v.codigo} (a ${metros(v.distancia_m)})`).join(", ")}. Este se reportó primero.</p>}
          <div className="dash-acciones">
            <button type="button" className="tec-boton-sec" aria-expanded={verMapa} data-testid="lev-ver-mapa" onClick={() => setVerMapa((x) => !x)}>{verMapa ? "Ocultar el mapa" : repetido.vecinos.length === 1 ? "Ver los dos en el mapa" : `Ver los ${repetido.vecinos.length + 1} en el mapa`}</button>
            {repetido.original ? <button type="button" className="tec-boton-sec" data-testid="lev-descartar-repetido"
              onClick={() => { setAccion("descartado"); setError(null); setActivo(""); setMotivo(`Repetido de ${repetido.original!.codigo} (a ${metros(repetido.original!.distancia_m)})`); }}>Descartar como repetido</button> : null}
          </div>
          {verMapa ? <Suspense fallback={<p className="tec-sub" role="status">Cargando el mapa…</p>}>
            <MiniMapaRepetidos puntos={[{ codigo: p.codigo, lat: p.lat, lon: p.lon, principal: true }, ...repetido.vecinos.map((v) => ({ codigo: v.codigo, lat: v.lat, lon: v.lon }))]} /></Suspense> : null}
        </div>) : null}
      {p.observacion ? <p className="pv-motivo">{p.observacion}</p> : null}
      <p className="tec-ayuda">Reportado el {fechaHora(p.registrado_en)} por {p.quien} ({p.area === "comercial" ? "Comercial" : "Técnica"}) · precisión ± {Math.round(p.precision_m)} m · {p.lat}, {p.lon}{p.sector ? ` · ${p.sector}` : ""}</p>
      {p.estado !== "reportado" ? <p className="tec-ayuda">{p.estado_nombre} el {fechaHora(p.estado_desde)}{p.estado_quien ? ` por ${p.estado_quien}` : ""}{p.activo ? <> · activo <strong>{p.activo}</strong></> : null}{p.estado_motivo ? ` · ${p.estado_motivo}` : ""}</p> : null}
      {p.propuesta && abierto ? (
        <p className="tec-aviso tec-aviso-info lev-propuesta" role="status" data-testid="lev-propuesta"><strong>Posiblemente levantado:</strong> {p.propuesta.activo} ({p.propuesta.tipo}), a {String(p.propuesta.distancia_m).replace(".", ",")} m, cargado el {fechaHora(p.propuesta.cargado_en)}.{" "}
          <button type="button" className="tec-boton-sec" disabled={enviando} data-testid="lev-confirmar-propuesta" onClick={async () => { setEnviando(true); setError(null);
            try { const r = await apiLev.evento(p.codigo, "levantado", { activo: p.propuesta!.activo, motivo: "Confirmado: es el activo nuevo de la capa" }); onCambio(`${p.codigo} quedó «levantado» (${r.activo}).`); } catch (e) { setError(err(e)); setEnviando(false); } }}>Confirmar: es {p.propuesta.activo}</button></p>
      ) : null}
      {error && !accion ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
      <div className="dash-acciones">
        <button type="button" className="tec-boton-sec" data-accion-lev="acta" onClick={() => setActa(true)}>Ver acta (PDF)</button>
        {p.activo ? <button type="button" className="tec-boton-sec" onClick={() => onFicha(p.activo!)}>Ver la ficha de {p.activo}</button> : null}
        {acciones.map((c) => <button key={c} type="button" className="tec-boton-sec" aria-pressed={accion === c} data-accion-lev={c} onClick={() => { setAccion(accion === c ? null : c); setError(null); setMotivo(""); setActivo(""); }}>{ACCION[c].boton}</button>)}
      </div>
      {acta ? <ActaLevantar codigo={p.codigo} onCerrar={() => setActa(false)} /> : null}
      {a && accion ? (
        <div className="lev-form">
          {a.ayuda ? <p className="tec-ayuda">{a.ayuda}</p> : null}
          {a.pideActivo ? <><label htmlFor={`lev-act-${p.codigo}`}>Código del activo nuevo</label><input id={`lev-act-${p.codigo}`} type="text" maxLength={12} autoCapitalize="characters" placeholder="VAL-000123" value={activo} onChange={(e) => setActivo(e.target.value)} /></> : null}
          <label htmlFor={`lev-mot-${p.codigo}`}>{a.campo}</label>
          <input id={`lev-mot-${p.codigo}`} type="text" maxLength={500} value={motivo} onChange={(e) => setMotivo(e.target.value)} />
          {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
          <div className="dash-acciones">
            <button type="button" className="tec-boton" disabled={!puede || enviando} data-testid="lev-confirmar" onClick={() => void enviar()}>{enviando ? "Guardando…" : a.boton}</button>
            <button type="button" className="tec-boton-sec" disabled={enviando} onClick={() => setAccion(null)}>Cancelar</button>
          </div>
        </div>
      ) : null}
    </section>
  );
}
