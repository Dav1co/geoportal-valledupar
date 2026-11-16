import { createContext, useCallback, useContext, useEffect, useRef, useState } from "react";
import "./avisos.css";
import { apiAvisos, type AreaAviso, type Aviso, type Avisos, type Bandeja, type ParametroAviso } from "./apiAvisos";
import { textoError } from "./apiDashboard";

// Avisos de Técnica (Técnica fase 1, Corte 12). Solo supervisores y administrador: el servidor decide qué áreas ve cada uno (planta, distribución; Personal, los dos).
// Los avisos se CALCULAN en cada consulta: no se descartan ni se marcan como vistos; desaparecen solos cuando se resuelve la causa. Cada aviso lleva a su bandeja.
// Tres lugares: la tarjeta «Avisos» del modo Supervisión (con su contador), esta pantalla y la franja corta arriba de cada dashboard (los de su área).

const REFRESCO_MS = 60_000;
const NIVEL: Record<Aviso["nivel"], string> = { rojo: "Urgente", naranja: "Atención", info: "Para revisar" };
const AREA: Record<AreaAviso, string> = { planta: "Plantas", distribucion: "Distribución", personal: "Personal" };
const PESTANA: Record<string, Record<string, string>> = {
  ptap: { registros: "Registros", eventos: "Eventos", quimicos: "Químicos", puntos: "Puntos", personal: "Personal técnico" },
  distribucion: { danos: "Daños y fallas", no_identificados: "No identificados", intervenciones: "Intervenciones", bot: "Reportes del bot", cargue: "Cargue de capas",
                  por_verificar: "Por verificar", nodos: "Nodos por clasificar", personal: "Personal" },
};
const hora = (iso: string) => new Date(iso).toLocaleTimeString("es-CO", { timeZone: "America/Bogota", hour: "2-digit", minute: "2-digit" });
const fecha = (iso: string) => new Date(iso).toLocaleString("es-CO", { timeZone: "America/Bogota", dateStyle: "medium", timeStyle: "short" });
const nf = new Intl.NumberFormat("es-CO", { maximumFractionDigits: 0 });

/** Una bandeja concreta: «personal» va al dashboard que la persona tenga (distribución si lo tiene; si no, el PTAP). */
export function resolverBandeja(b: Bandeja, tieneDistribucion: boolean): { tablero: "ptap" | "distribucion"; pestana: string | null } {
  if (b.tablero === "personal") return { tablero: tieneDistribucion ? "distribucion" : "ptap", pestana: "personal" };
  return { tablero: b.tablero, pestana: b.pestana };
}
export function rotuloBandeja(b: Bandeja, tieneDistribucion: boolean): string {
  const r = resolverBandeja(b, tieneDistribucion);
  const tablero = r.tablero === "ptap" ? "Dashboard PTAP" : "Dashboard distribución";
  return r.pestana ? `${tablero} › ${PESTANA[r.tablero][r.pestana] ?? r.pestana}` : tablero;
}

export type EstadoAvisos = { datos: Avisos | null; error: string | null; recargar: () => void };

/** Los avisos de la persona, con recarga cada minuto mientras la pestaña está visible. Si la consulta falla no rompe nada: queda el error para la pantalla. */
export function useAvisos(activo: boolean): EstadoAvisos {
  const [datos, setDatos] = useState<Avisos | null>(null);
  const [error, setError] = useState<string | null>(null);
  const v = useRef(0);
  const recargar = useCallback(() => {
    const mi = ++v.current;
    apiAvisos.avisos().then((d) => { if (mi === v.current) { setDatos(d); setError(null); } })
      .catch((e) => { if (mi === v.current) setError(textoError(e).texto); });
  }, []);
  useEffect(() => {
    if (!activo) return;
    recargar();
    const id = setInterval(() => { if (document.visibilityState !== "hidden") recargar(); }, REFRESCO_MS);
    return () => clearInterval(id);
  }, [activo, recargar]);
  return { datos, error, recargar };
}

/** Lo que la franja de cada dashboard necesita; lo da AreaTecnica (así los dashboards no cambian). */
export const AvisosContexto = createContext<{ estado: EstadoAvisos; tablero: "ptap" | "distribucion"; tieneDistribucion: boolean; onVer: () => void; onAbrir: (b: Bandeja) => void } | null>(null);

function TarjetaAviso({ a, tieneDistribucion, onAbrir }: { a: Aviso; tieneDistribucion: boolean; onAbrir: (b: Bandeja) => void }) {
  return (
    <article className={`av-aviso av-${a.nivel}`} data-aviso={a.clave} data-nivel={a.nivel}>
      <div className="av-cab">
        <span className="av-nivel">{NIVEL[a.nivel]}</span>
        <h3>{a.titulo}</h3>
      </div>
      {a.detalle ? <p className="av-detalle">{a.detalle}</p> : null}
      {a.items.length > 0 ? (
        <ul className="av-items">{a.items.map((t, i) => <li key={i}>{t}</li>)}{a.n > a.items.length ? <li className="av-mas">y {nf.format(a.n - a.items.length)} más</li> : null}</ul>
      ) : null}
      <button type="button" className="av-abrir" onClick={() => onAbrir(a.bandeja)}>Abrir {rotuloBandeja(a.bandeja, tieneDistribucion)}</button>
    </article>
  );
}

export function PantallaAvisos({ estado, tieneDistribucion, onAbrir, onVolver }: { estado: EstadoAvisos; tieneDistribucion: boolean; onAbrir: (b: Bandeja) => void; onVolver: () => void }) {
  const [verParametros, setVerParametros] = useState(false);
  const { datos, error, recargar } = estado;
  useEffect(() => { recargar(); }, [recargar]);
  const areas: AreaAviso[] = datos ? (["planta", "distribucion", "personal"] as AreaAviso[]).filter((x) => datos.areas[x]) : [];
  const info = datos ? datos.total - datos.rojos - datos.naranjas : 0;
  return (
    <div className="tec-pagina av-pagina">
      <div className="tec-volver-barra">
        <button type="button" className="tec-volver" onClick={onVolver}><span aria-hidden="true">←</span> Volver</button>
        <span className="tec-volver-tit">Avisos</span>
      </div>
      <div className="av-cuerpo">
        <div className="av-resumen" role="status">
          {datos ? <span><strong className="av-n-rojo">{datos.rojos}</strong> urgentes · <strong className="av-n-naranja">{datos.naranjas}</strong> de atención · <strong>{info}</strong> para revisar
            <span className="av-hora"> · calculados a las {hora(datos.calculado_en)}</span></span> : error ? null : <span>Cargando los avisos…</span>}
          <button type="button" className="av-boton-sec" onClick={recargar}>Actualizar</button>
        </div>
        {error && !datos ? <p className="av-error" role="alert">{error}</p> : null}
        {error && datos ? <p className="av-error" role="alert">No se pudieron actualizar: {error}</p> : null}
        <p className="av-nota">Los avisos no se marcan como vistos: desaparecen solos cuando se resuelve la causa.</p>
        {datos ? areas.map((x) => {
          const lista = datos.avisos.filter((a) => a.area === x);
          return (
            <section key={x} className={`av-area av-area-${x}`} aria-label={AREA[x]} data-area={x}>
              <h2>{AREA[x]}</h2>
              {lista.length === 0 ? <p className="av-vacio">Sin avisos de {AREA[x].toLowerCase()}.</p>
                : <div className="av-rejilla">{lista.map((a) => <TarjetaAviso key={a.clave} a={a} tieneDistribucion={tieneDistribucion} onAbrir={onAbrir} />)}</div>}
            </section>
          );
        }) : null}
        {datos ? (
          <section className="av-area av-param" aria-label="Plazos y mínimos">
            <h2>Plazos y mínimos</h2>
            {verParametros ? <ParametrosAvisos onCambio={recargar} /> : (
              <>
                <p className="av-nota">Las horas de la planta, los plazos de los daños según su riesgo y los demás mínimos de los avisos. Cada cambio pide su motivo.</p>
                <button type="button" className="av-boton-sec" onClick={() => setVerParametros(true)}>Ver y cambiar los plazos</button>
              </>
            )}
          </section>
        ) : null}
      </div>
    </div>
  );
}

/** La franja corta de arriba de cada dashboard: los avisos de su área (y los de Personal). Cada uno abre su pestaña ahí mismo. Sin avisos, no ocupa lugar. */
export function FranjaAvisos({ onElegir, pestanas }: { onElegir: (clave: string) => void; pestanas: string[] }) {
  const ctx = useContext(AvisosContexto);
  if (!ctx || !ctx.estado.datos) return null;
  const propias = ctx.estado.datos.avisos.filter((a) => a.area === "personal" || (ctx.tablero === "ptap" ? a.area === "planta" : a.area === "distribucion"));
  if (propias.length === 0) return null;
  const rojos = propias.filter((a) => a.nivel === "rojo").length;
  const abrir = (a: Aviso) => {
    const r = resolverBandeja(a.bandeja, ctx.tieneDistribucion);
    if (r.tablero === ctx.tablero && r.pestana && pestanas.includes(r.pestana)) onElegir(r.pestana); else ctx.onAbrir(a.bandeja);
  };
  return (
    <div className={`av-franja${rojos > 0 ? " av-franja-roja" : ""}`} role="region" aria-label="Avisos de este dashboard" data-franja={ctx.tablero}>
      <div className="av-franja-ancho">
        <span className="av-franja-tit">{propias.length === 1 ? "1 aviso" : `${propias.length} avisos`}</span>
        <ul className="av-franja-lista">
          {propias.slice(0, 3).map((a) => (
            <li key={a.clave}><button type="button" className={`av-franja-item av-${a.nivel}`} onClick={() => abrir(a)} data-aviso={a.clave}>{a.titulo}</button></li>
          ))}
        </ul>
        <button type="button" className="av-franja-ver" onClick={ctx.onVer}>{propias.length > 3 ? `Ver los ${propias.length}` : "Ver avisos"}</button>
      </div>
    </div>
  );
}

const AREA_PARAM: Record<ParametroAviso["area"], string> = { planta: "Plantas", distribucion: "Distribución", sistema: "Bot de avisos (solo el administrador)" };
function ParametrosAvisos({ onCambio }: { onCambio: () => void }) {
  const [ps, setPs] = useState<ParametroAviso[] | null>(null); const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0); const [aviso, setAviso] = useState<string | null>(null); const [abierto, setAbierto] = useState<string | null>(null);
  useEffect(() => { let vivo = true; setError(null);
    apiAvisos.parametros().then((d) => { if (vivo) setPs(d.parametros); }).catch((e) => { if (vivo) setError(textoError(e).texto); });
    return () => { vivo = false; }; }, [vez]);
  if (error) return <p className="av-error" role="alert">{error} <button type="button" className="av-boton-sec" onClick={() => setVez((x) => x + 1)}>Reintentar</button></p>;
  if (!ps) return <p className="av-nota" role="status">Cargando los plazos…</p>;
  const grupos = (["planta", "distribucion", "sistema"] as ParametroAviso["area"][]).filter((g) => ps.some((p) => p.area === g));
  return (
    <>
      {aviso ? <p className="av-ok" role="status">{aviso}</p> : null}
      {grupos.map((g) => (
        <div key={g} className="av-param-grupo">
          <h3>{AREA_PARAM[g]}</h3>
          <div className="av-rejilla">
            {ps.filter((p) => p.area === g).map((p) => (
              <article key={p.clave} className="av-param-tarjeta" data-parametro={p.clave}>
                <h4>{p.nombre}</h4>
                <p className="av-param-valor"><strong>{nf.format(p.valor)}</strong> {p.unidad} <span className="av-nota">· de {nf.format(p.minimo)} a {nf.format(p.maximo)}</span></p>
                <p className="av-nota">{p.descripcion}</p>
                {p.ultimo ? <p className="av-nota">Último cambio: de {nf.format(p.ultimo.antes)} a {nf.format(p.ultimo.despues)} · «{p.ultimo.motivo}» · {p.ultimo.autor} · {fecha(p.ultimo.creado_en)}</p> : null}
                {abierto === p.clave
                  ? <FormParametroAviso p={p} onCerrar={() => setAbierto(null)} onListo={(t) => { setAbierto(null); setAviso(t); setVez((v) => v + 1); onCambio(); }} />
                  : <button type="button" className="av-boton-sec" onClick={() => { setAviso(null); setAbierto(p.clave); }}>Cambiar…</button>}
              </article>
            ))}
          </div>
        </div>
      ))}
    </>
  );
}
function FormParametroAviso({ p, onListo, onCerrar }: { p: ParametroAviso; onListo: (t: string) => void; onCerrar: () => void }) {
  const [v, setV] = useState(String(p.valor)); const [motivo, setMotivo] = useState("");
  const [enviando, setEnviando] = useState(false); const [error, setError] = useState<string | null>(null);
  const n = Number(v.trim());
  const valido = /^\d+$/.test(v.trim()) && n >= p.minimo && n <= p.maximo && n !== p.valor;
  const listo = valido && motivo.trim().length >= 10 && motivo.length <= 500;
  const guardar = async () => {
    setEnviando(true); setError(null);
    try { const r = await apiAvisos.fijarParametro(p.clave, n, motivo.trim()); onListo(`${p.nombre}: de ${nf.format(r.antes)} a ${nf.format(r.valor)} ${p.unidad}.`); }
    catch (e) { setError(textoError(e).texto); } finally { setEnviando(false); }
  };
  return (
    <section className="av-form" aria-label={`Cambiar ${p.nombre}`} data-form="parametro-aviso">
      <label className="av-campo" htmlFor={`av-p-${p.clave}`}>Valor nuevo ({p.unidad}, número entero)
        <input id={`av-p-${p.clave}`} type="text" inputMode="numeric" value={v} onChange={(e) => setV(e.target.value)} aria-invalid={!valido} /></label>
      <label className="av-campo" htmlFor={`av-m-${p.clave}`}>Motivo (de 10 a 500 caracteres)
        <textarea id={`av-m-${p.clave}`} rows={2} value={motivo} maxLength={500} onChange={(e) => setMotivo(e.target.value)} /></label>
      {error ? <p className="av-error" role="alert">{error}</p> : null}
      <div className="av-form-botones">
        <button type="button" className="av-boton" disabled={!listo || enviando} onClick={() => void guardar()}>{enviando ? "Guardando…" : "Guardar el cambio"}</button>
        <button type="button" className="av-boton-sec" onClick={onCerrar} disabled={enviando}>Cancelar</button>
      </div>
    </section>
  );
}
