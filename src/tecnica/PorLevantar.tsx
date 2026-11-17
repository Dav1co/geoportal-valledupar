import { useEffect, useState } from "react";
import "./encontrar.css";
import { apiLev, type FiltroLevantar, type FotoLevantar, type ListaLevantar, type PuntoLevantar } from "./apiLevantar";
import { ErrorTec } from "./apiTecnica";
import { HojaLevantamiento } from "./HojaLevantamiento";


// Dashboard distribución → Por verificar → «Otros activos por levantamiento» (Corte 14). Los activos que alguien encontró en la calle y no están en la red.
// Estados, de solo agregar: reportado → asignado a levantamiento → levantado (con el activo nuevo) | descartado con motivo. «Reabrir» lo devuelve a reportado.
// «Quién» es el nombre del funcionario; ningún dato de suscriptores. Las fotos se piden con una lectura firmada de 60 s (queda en la auditoría).
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
  useEffect(() => {
    let vivo = true; setD(null); setError(null);
    apiLev.lista(filtro, null).then((r) => { if (vivo) { setD(r); setItems(r.items); onConteo?.(r.abiertos); } }).catch((e) => { if (vivo) setError(err(e)); });
    return () => { vivo = false; };
  }, [filtro, vez]); // eslint-disable-line react-hooks/exhaustive-deps
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
      {aviso ? <p className="tec-aviso tec-aviso-info dan-pad-x" role="status">{aviso} <button type="button" className="tec-enlace" onClick={() => setAviso(null)}>Cerrar</button></p> : null}
      {!d ? <p className="tec-sub dan-pad" role="status">Cargando…</p>
        : !items.length ? <section className="tec-tarjeta"><p className="red-vacio">No hay activos {filtro === "abiertos" ? "por levantar" : "en ese estado"}.</p></section>
        : <>
            {items.map((p) => <Punto key={p.codigo} p={p} onFicha={onFicha} onCambio={(t) => { setAviso(t); setVez((v) => v + 1); }} />)}
            {d.siguiente ? <div className="dan-pad-x"><button type="button" className="tec-boton-sec" onClick={() => apiLev.lista(filtro, d.siguiente)
              .then((r) => { setItems([...items, ...r.items]); setD({ ...d, siguiente: r.siguiente }); }).catch(() => {})}>Cargar más</button></div> : null}
          </>}
    </div>
  );
}

function Punto({ p, onFicha, onCambio }: { p: PuntoLevantar; onFicha: (c: string) => void; onCambio: (aviso: string) => void }) {
  const [fotos, setFotos] = useState<FotoLevantar[] | null>(null);
  const [errorFotos, setErrorFotos] = useState<string | null>(null);
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
        <button type="button" className="tec-boton-sec" data-accion-lev="fotos" onClick={() => { setErrorFotos(null); apiLev.fotos(p.codigo).then((r) => setFotos(r.fotos)).catch((e) => setErrorFotos(err(e))); }}>Ver {p.fotos === 1 ? "la foto" : `las ${p.fotos} fotos`}</button>
        {p.activo ? <button type="button" className="tec-boton-sec" onClick={() => onFicha(p.activo!)}>Ver la ficha de {p.activo}</button> : null}
        {acciones.map((c) => <button key={c} type="button" className="tec-boton-sec" aria-pressed={accion === c} data-accion-lev={c} onClick={() => { setAccion(accion === c ? null : c); setError(null); setMotivo(""); setActivo(""); }}>{ACCION[c].boton}</button>)}
      </div>
      {errorFotos ? <p className="tec-aviso tec-aviso-error" role="alert">{errorFotos}</p> : null}
      {fotos ? <div className="lev-fotos" data-testid="lev-fotos">{fotos.map((f) => <a key={f.n} href={f.url} target="_blank" rel="noreferrer"><img src={f.url} alt={`Foto ${f.n} de ${p.codigo}`} /></a>)}</div> : null}
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
