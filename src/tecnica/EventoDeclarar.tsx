import { Suspense, useEffect, useMemo, useState } from "react";
import { lazyConRecarga } from "../lib/recarga";
import { ErrorTec } from "./apiTecnica";
import { horaClara, instanteDeCampo, nContratos } from "./apiCierre";
import { apiEventos, textoReportes, type CatalogoEventos, type Evento, type VistaPrevia, type ZonaPedida } from "./apiEventos";

// Corte 15 · «Declarar evento de suspensión». Alcances (lo que puede cada quien lo dice el catálogo del servidor):
// · por tubo (corte «origen y tubos», 20-nov): uno o varios tubos de salida; la zona son los sectores asignados a esos tubos (supervisor de distribución);
// · por sectores: uno o varios sectores o subsectores hidráulicos (supervisor de distribución);
// · por círculo: se dibuja en el mapa, centro y radio (supervisor de distribución);
// · total: toda la ciudad, o por una planta, que también es toda la ciudad (el sistema es único; queda guardada la planta) (supervisor de planta o administrador).
// Origen obligatorio (decisión de David, 20-nov): el daño o la intervención (DAN-… o ITV-…) o la causal de un trabajo o actividad; nunca los dos. La observación
// (antes «Causa») sigue obligatoria y solo se ve en pantalla.
// Antes de declarar se pide la VISTA PREVIA: cuántos contratos y usuarios sensibles quedan en la zona y cuántos reportes abiertos se asociarían. No guarda nada.
// Sin nombres de suscriptores ni términos tarifarios: solo conteos.
const MiniMapaEvento = lazyConRecarga(() => import("./MiniMapaEvento").then((m) => ({ default: m.MiniMapaEvento })));
const aLocal = (d: Date) => new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
const nf = new Intl.NumberFormat("es-CO");
export const errorEvento = (e: unknown) => (e instanceof ErrorTec && e.tipo === "permiso" ? "No tiene permiso para esto." : e instanceof ErrorTec && e.tipo === "red" ? "No hay señal o la conexión se cortó. Intente de nuevo."
  : e instanceof Error ? e.message : "No se pudo completar.");
type Modo = "tubos" | "sectores" | "circulo" | "total";
type Origen = "registro" | "trabajo";

export function EventoDeclarar({ cat, onCancelar, onDeclarado }: { cat: CatalogoEventos; onCancelar: () => void; onDeclarado: (e: Evento & { asociados_al_declarar: number }) => void }) {
  const tubosCat = (cat.tubos ?? []).filter((t) => t.activo);
  const causales = (cat.causales ?? []).filter((c) => c.activa);
  const modos: Modo[] = [...(cat.puede.zona ? ((tubosCat.length ? ["tubos", "sectores", "circulo"] : ["sectores", "circulo"]) as Modo[]) : []), ...(cat.puede.total ? (["total"] as Modo[]) : [])];
  const [modo, setModo] = useState<Modo | "">(modos.length === 1 ? modos[0] : "");
  const [sectores, setSectores] = useState<string[]>([]);
  const [tubos, setTubos] = useState<string[]>([]);
  const [origen, setOrigen] = useState<Origen | "">("");
  const [causal, setCausal] = useState("");
  const [circulo, setCirculo] = useState<{ lat: number; lon: number; radio_m: number } | null>(null);
  const [radioTxt, setRadioTxt] = useState("200");
  const [total, setTotal] = useState<"ciudad" | "planta" | "">("");
  const [planta, setPlanta] = useState("");
  const ahora = useMemo(() => aLocal(new Date()), []);
  const [causa, setCausa] = useState(""); const [registro, setRegistro] = useState(""); const [desde, setDesde] = useState(ahora); const [regreso, setRegreso] = useState("");
  const [previa, setPrevia] = useState<{ clave: string; v: VistaPrevia } | null>(null);
  const [ocupado, setOcupado] = useState<string | null>(null); const [error, setError] = useState<string | null>(null); const [intentado, setIntentado] = useState(false);

  const zona: ZonaPedida | null = modo === "tubos" ? (tubos.length ? { alcance: "tubos", tubos } : null)
    : modo === "sectores" ? (sectores.length ? { alcance: "sectores", sectores } : null)
    : modo === "circulo" ? (circulo ? { alcance: "circulo", lat: Number(circulo.lat.toFixed(6)), lon: Number(circulo.lon.toFixed(6)), radio_m: Math.round(circulo.radio_m) } : null)
    : modo === "total" ? (total === "ciudad" ? { alcance: "total", total: "ciudad" } : total === "planta" && planta ? { alcance: "total", total: "planta", planta } : null) : null;
  const desdeIso = instanteDeCampo(desde), regresoIso = instanteDeCampo(regreso);
  const clave = zona ? JSON.stringify(zona) + "|" + (desdeIso ?? "") : "";
  const vista = previa && previa.clave === clave ? previa.v : null;      // la vista previa solo vale para la zona y la hora que se ven
  useEffect(() => { setError(null); }, [clave]);

  const radioNum = Number(radioTxt.replace(",", "."));
  const radioOk = Number.isFinite(radioNum) && radioNum >= cat.limites.radio_min_m && radioNum <= cat.limites.radio_max_m;
  function ponerRadio(t: string) {
    const v = t.replace(/[^0-9]/g, ""); setRadioTxt(v);
    const n = Number(v); if (circulo && Number.isFinite(n) && n >= cat.limites.radio_min_m && n <= cat.limites.radio_max_m) setCirculo({ ...circulo, radio_m: n });
  }
  const minDesde = aLocal(new Date(Date.now() - cat.limites.horas_atras_max * 3_600_000));
  const sinSectores = tubosCat.filter((t) => tubos.includes(t.codigo) && t.sectores.length === 0);

  const faltas: string[] = [];
  if (!modo) faltas.push("Elija el alcance del evento.");
  if (modo === "tubos" && tubos.length === 0) faltas.push("Marque al menos un tubo de salida.");
  if (modo === "tubos" && sinSectores.length) faltas.push(`${sinSectores.map((t) => t.nombre).join(", ")}: no tiene sectores asignados. Se asignan en «Tubo de salida → sectores».`);
  if (modo === "sectores" && sectores.length === 0) faltas.push("Marque al menos un sector o subsector.");
  if (modo === "sectores" && sectores.length > cat.limites.sectores_max) faltas.push(`Máximo ${cat.limites.sectores_max} sectores o subsectores.`);
  if (modo === "circulo" && !circulo) faltas.push("Toque el mapa para poner el centro del círculo.");
  if (modo === "circulo" && !radioOk) faltas.push(`El radio va de ${cat.limites.radio_min_m} a ${nf.format(cat.limites.radio_max_m)} m.`);
  if (modo === "total" && !total) faltas.push("Diga si es toda la ciudad o por una planta.");
  if (modo === "total" && total === "planta" && !planta) faltas.push("Elija la planta.");
  if (!origen) faltas.push("Diga el origen: un daño o intervención, o un trabajo o actividad.");
  if (origen === "registro" && !/^(DAN|ITV)-\d{6}$/.test(registro.trim().toUpperCase())) faltas.push("Escriba el daño o la intervención como DAN-000123 o ITV-000123.");
  if (origen === "trabajo" && !causales.some((c) => c.codigo === causal)) faltas.push("Elija la causal del trabajo o actividad.");
  if (causa.trim().length < 5) faltas.push("Escriba la observación (de 5 a 200 letras).");
  if (!desdeIso) faltas.push("Escriba desde cuándo no hay agua.");
  else if (new Date(desdeIso).getTime() > Date.now() + 120_000) faltas.push("«Desde» no puede ser una hora futura.");
  if (regresoIso && desdeIso && new Date(regresoIso) <= new Date(desdeIso)) faltas.push("El regreso estimado debe ser después de «Desde».");
  const faltasZona = faltas.filter((f) => !/observación|origen|daño o la intervención|causal|regreso/.test(f));

  async function verPrevia() {
    if (!zona || faltasZona.length) { setIntentado(true); return; }
    setOcupado("Calculando…"); setError(null);
    try { setPrevia({ clave, v: await apiEventos.vistaPrevia(zona, desdeIso) }); } catch (e) { setError(errorEvento(e)); } finally { setOcupado(null); }
  }
  async function declarar() {
    setIntentado(true);
    if (!zona || faltas.length || !vista || vista.ya_abierto) return;
    setOcupado("Declarando…"); setError(null);
    try { onDeclarado(await apiEventos.declarar(zona, { causa: causa.trim(), registro: origen === "registro" ? registro.trim().toUpperCase() : null, causal: origen === "trabajo" ? causal : null, desde: desdeIso, regreso: regresoIso })); }
    catch (e) { setError(errorEvento(e)); setOcupado(null); }
  }

  const opcion = (sel: boolean, txt: string, f: () => void, clave: string) => <button key={clave} type="button" className="dan-opcion" aria-pressed={sel} data-opcion={clave} disabled={!!ocupado} onClick={f}>{txt}</button>;
  const grupo = (clase: "sector" | "subsector", titulo: string) => {
    const lista = cat.sectores.filter((s) => s.clase === clase);
    return lista.length ? (
      <fieldset className="evs-sectores" data-clase={clase}>
        <legend className="dan-rot">{titulo}</legend>
        {lista.map((s) => <label key={s.codigo} className="dan-check"><input type="checkbox" checked={sectores.includes(s.codigo)} disabled={!!ocupado} data-sector={s.codigo}
          onChange={(e) => setSectores((x) => (e.target.checked ? [...x, s.codigo] : x.filter((c) => c !== s.codigo)))} />{s.nombre}</label>)}
      </fieldset>) : null;
  };

  return (
    <div className="evs" data-testid="evs-declarar">
      <section className="tec-tarjeta" aria-labelledby="evs-t1">
        <h2 id="evs-t1">1. Dónde no hay agua</h2>
        {modos.length === 0 ? <p className="tec-aviso tec-aviso-error" role="alert">Su perfil no puede declarar eventos de suspensión.</p> : null}
        <div className="dan-fila" role="group" aria-label="Alcance del evento">
          {cat.puede.zona && tubosCat.length ? opcion(modo === "tubos", "Por tubo", () => setModo("tubos"), "tubos") : null}
          {cat.puede.zona ? opcion(modo === "sectores", "Por sectores", () => setModo("sectores"), "sectores") : null}
          {cat.puede.zona ? opcion(modo === "circulo", "Por círculo en el mapa", () => setModo("circulo"), "circulo") : null}
          {cat.puede.total ? opcion(modo === "total", "Total", () => setModo("total"), "total") : null}
        </div>
        {modo === "tubos" ? (
          <>
            <p className="tec-ayuda">Cuando falla o se cierra una salida de la planta. Marque uno o varios tubos: la zona son los sectores y subsectores que abastecen.</p>
            <fieldset className="evs-sectores evs-tubos" data-testid="evs-tubos"><legend className="dan-rot">Tubos de salida</legend>
              {tubosCat.map((t) => (
                <label key={t.codigo} className="dan-check" data-tubo={t.codigo}>
                  <input type="checkbox" checked={tubos.includes(t.codigo)} disabled={!!ocupado} onChange={(e) => setTubos((x) => (e.target.checked ? [...x, t.codigo] : x.filter((c) => c !== t.codigo)))} />
                  <span className="evs-tubo"><span className="evs-tubo-nom">{t.nombre}</span> <small className="evs-tubo-cod tec-codigo">{t.codigo}</small>
                    <small className="evs-tubo-n">{t.sectores.length === 0 ? "Sin sectores asignados" : t.sectores.length === 1 ? "1 sector o subsector" : `${t.sectores.length} sectores o subsectores`}</small></span>
                </label>))}
            </fieldset>
            {sinSectores.length ? <p className="tec-aviso tec-aviso-info" data-testid="evs-tubo-sin">{sinSectores.map((t) => t.nombre).join(", ")} todavía no {sinSectores.length === 1 ? "tiene" : "tienen"} sectores asignados: no se puede declarar por {sinSectores.length === 1 ? "ese tubo" : "esos tubos"}. Se asignan en «Tubo de salida → sectores».</p> : null}
          </>) : null}
        {modo === "sectores" ? (
          <>
            <p className="tec-ayuda">Para un daño grande, un cierre de válvulas o un trabajo programado. Marque uno o varios; la zona es la suma.</p>
            {grupo("sector", "Sectores hidráulicos")}{grupo("subsector", "Subsectores")}
            {cat.sectores.length === 0 ? <p className="tec-aviso tec-aviso-error" role="alert">No hay sectores hidráulicos cargados.</p> : null}
          </>) : null}
        {modo === "circulo" ? (
          <>
            <p className="tec-ayuda">Para una afectación localizada que no coincide con un sector.</p>
            <Suspense fallback={<p className="tec-sub" role="status">Cargando el mapa…</p>}>
              <MiniMapaEvento circulo={circulo} limites={{ min: cat.limites.radio_min_m, max: cat.limites.radio_max_m }} onCirculo={(c) => { setCirculo(c); setRadioTxt(String(Math.round(c.radio_m))); }} />
            </Suspense>
            <div className="tec-campo evs-radio"><label htmlFor="evs-radio">Radio del círculo (m)</label>
              <input id="evs-radio" type="text" inputMode="numeric" maxLength={4} value={radioTxt} disabled={!!ocupado} onChange={(e) => ponerRadio(e.target.value)} aria-invalid={!radioOk} />
              <span className="tec-ayuda">De {cat.limites.radio_min_m} a {nf.format(cat.limites.radio_max_m)} m. {circulo ? `Centro: ${circulo.lat.toFixed(5)}, ${circulo.lon.toFixed(5)}.` : "Todavía no hay centro."}</span></div>
          </>) : null}
        {modo === "total" ? (
          <>
            <p className="tec-ayuda">Para una falla de planta, de captación o de energía. El sistema es único: una falla de planta deja sin agua a toda la ciudad; queda guardada la planta.</p>
            <div className="dan-fila" role="group" aria-label="Qué queda sin agua">
              {opcion(total === "ciudad", "Toda la ciudad", () => setTotal("ciudad"), "ciudad")}
              {opcion(total === "planta", "Por una planta (toda la ciudad)", () => setTotal("planta"), "planta")}
            </div>
            {total === "planta" ? (
              <div className="tec-campo"><label htmlFor="evs-planta">Planta</label>
                <select id="evs-planta" value={planta} disabled={!!ocupado} onChange={(e) => setPlanta(e.target.value)}><option value="">Elija…</option>
                  {cat.plantas.map((p) => <option key={p.codigo} value={p.codigo}>{p.nombre}</option>)}</select>
              </div>) : null}
          </>) : null}
      </section>

      <section className="tec-tarjeta" aria-labelledby="evs-t2">
        <h2 id="evs-t2">2. Origen, observación y tiempos</h2>
        <div className="tec-campo"><span className="dan-rot" id="evs-origen-rot">Origen del evento</span>
          <div className="dan-fila" role="group" aria-labelledby="evs-origen-rot" data-testid="evs-origen">
            {opcion(origen === "registro", "Daño o intervención", () => setOrigen("registro"), "origen-registro")}
            {opcion(origen === "trabajo", "Trabajo o actividad", () => setOrigen("trabajo"), "origen-trabajo")}
          </div></div>
        {origen === "registro" ? (
          <div className="tec-campo"><label htmlFor="evs-registro">Daño o intervención que lo origina</label>
            <input id="evs-registro" type="text" maxLength={10} autoComplete="off" value={registro} disabled={!!ocupado} onChange={(e) => setRegistro(e.target.value)} placeholder="DAN-000123" />
            <span className="tec-ayuda">El código del daño o de la intervención: DAN-000123 o ITV-000123.</span></div>) : null}
        {origen === "trabajo" ? (
          <fieldset className="evs-sectores evs-causales" data-testid="evs-causales"><legend className="dan-rot">Causal</legend>
            {causales.map((c) => <label key={c.codigo} className="dan-check" data-causal={c.codigo}><input type="radio" name="evs-causal" checked={causal === c.codigo} disabled={!!ocupado} onChange={() => setCausal(c.codigo)} />{c.nombre}</label>)}
            {causales.length === 0 ? <p className="tec-aviso tec-aviso-error" role="alert">No hay causales activas.</p> : null}
          </fieldset>) : null}
        <div className="tec-campo"><label htmlFor="evs-causa">Observación (solo se ve en pantalla)</label>
          <input id="evs-causa" type="text" maxLength={200} value={causa} disabled={!!ocupado} onChange={(e) => setCausa(e.target.value)} placeholder="Daño en la tubería de la carrera 9, mantenimiento del tanque…" />
          <span className="tec-ayuda">De 5 a 200 letras. Se ve en las pantallas del geoportal (avisos, mapa y detalle del evento); no sale en las descargas.</span></div>
        <div className="dan-dos">
          <div className="tec-campo"><label htmlFor="evs-desde">Sin agua desde</label>
            <input id="evs-desde" type="datetime-local" className="dan-hora" min={minDesde} max={aLocal(new Date())} value={desde} disabled={!!ocupado} onChange={(e) => setDesde(e.target.value)} />
            <span className="tec-ayuda">Hasta {cat.limites.horas_atras_max} horas atrás.</span></div>
          <div className="tec-campo"><label htmlFor="evs-regreso">Regreso estimado del servicio <span className="tec-oblig">(opcional)</span></label>
            <input id="evs-regreso" type="datetime-local" className="dan-hora" value={regreso} disabled={!!ocupado} onChange={(e) => setRegreso(e.target.value)} />
            <span className="tec-ayuda">Se puede ajustar después.</span></div>
        </div>
      </section>

      <section className="tec-tarjeta" aria-labelledby="evs-t3" data-testid="evs-previa">
        <h2 id="evs-t3">3. A quién afecta</h2>
        <p className="tec-ayuda">Antes de declarar, mire cuántos contratos quedan en la zona y cuántos reportes abiertos se asociarían. No guarda nada.</p>
        <button type="button" className="tec-boton-sec" disabled={!!ocupado || !zona} data-testid="evs-ver-previa" onClick={() => void verPrevia()}>{ocupado === "Calculando…" ? ocupado : vista ? "Volver a calcular" : "Ver a quién afecta"}</button>
        {previa && !vista && zona ? <p className="tec-ayuda" data-testid="evs-previa-vieja">Cambió la zona o la hora: vuelva a calcular.</p> : null}
        {vista ? (
          <div className="evs-resumen" data-testid="evs-previa-datos" aria-live="polite">
            <p className="evs-zona">Sin agua en <strong>{vista.zona}</strong></p>
            <dl className="evs-datos">
              <div><dt>Contratos en la zona</dt><dd data-dato="contratos">{nf.format(vista.contratos)}</dd></div>
              <div><dt>Usuarios sensibles</dt><dd data-dato="sensibles">{nf.format(vista.sensibles)}</dd></div>
              <div><dt>Reportes que se asociarían</dt><dd data-dato="reportes">{nf.format(vista.reportes.total)}{vista.reportes.total ? <small> ({textoReportes(vista.reportes)})</small> : null}</dd></div>
            </dl>
            <p className="tec-ayuda">El conteo de contratos es aproximado (por el tramo más cercano de cada contrato). Sin nombres.{vista.sensibles ? " Los usuarios sensibles se listan en el detalle del evento." : ""}</p>
            {vista.ya_abierto ? <p className="tec-aviso tec-aviso-error" role="alert" data-testid="evs-ya-abierto">Ya hay un evento abierto para esa misma zona: {vista.ya_abierto}. No se puede declarar otro igual.</p> : null}
            {vista.zona_geojson && modo !== "circulo" ? (
              <Suspense fallback={<p className="tec-sub" role="status">Cargando el mapa…</p>}><MiniMapaEvento zona={vista.zona_geojson} /></Suspense>) : null}
            {!vista.zona_geojson ? <p className="tec-ayuda">Toda la ciudad: no se dibuja una zona en el mapa.</p> : null}
          </div>) : null}
      </section>

      {intentado && faltas.length ? <div className="tec-aviso tec-aviso-error dan-errores dan-pad-x" role="alert"><strong>Falta completar:</strong><ul>{faltas.map((f) => <li key={f}>{f}</li>)}</ul></div> : null}
      {intentado && !faltas.length && !vista ? <p className="tec-aviso tec-aviso-error dan-pad-x" role="alert">Antes de declarar, pulse «Ver a quién afecta».</p> : null}
      {error ? <p className="tec-aviso tec-aviso-error dan-pad-x" role="alert" data-testid="evs-error">{error}</p> : null}
      <div className="tec-acciones dan-pad-x">
        <button type="button" className="tec-boton" disabled={!!ocupado || !!vista?.ya_abierto} data-testid="evs-declarar-boton" onClick={() => void declarar()}>{ocupado === "Declarando…" ? ocupado : "Declarar evento"}</button>
        <button type="button" className="tec-boton-sec" disabled={!!ocupado} onClick={onCancelar}>Cancelar</button>
      </div>
      {vista && !vista.ya_abierto ? <p className="tec-ayuda dan-pad-x">Al declarar, los reportes que lleguen dentro de la zona mientras el evento esté abierto quedan asociados a él{regresoIso ? `, y a quien reporta se le dice el regreso estimado (${horaClara(regresoIso)})` : ""}. {nContratos(vista.contratos)} en la zona.</p> : null}
    </div>
  );
}
