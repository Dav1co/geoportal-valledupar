import { lazy, Suspense, useCallback, useEffect, useState } from "react";
import "./cierre.css";
import { apiCierre, horaClara, instanteDeCampo, nContratos, type AguasArriba, type LadoAguasArriba, type Simulacion, type ValvulaDelRegistro, type ValvulaSim } from "./apiCierre";
import { ErrorTec } from "./apiTecnica";

// Corte 9b (Fases 1a y 1b): «¿Qué válvulas cierro?» y el cierre real, dentro de Reportar daño o falla y de Registrar intervención.
//   · Sin daño ni intervención guardados (el formulario a medio llenar): solo la simulación.
//   · Con su código (DAN-… o ITV-…): además «Válvula cerrada» en cada válvula del resultado, «Válvula abierta» en las que cerró este registro y
//     «Guardar esta simulación». Quién puede lo decide el servidor; lo que se muestra son conteos, sin datos de suscriptores.
//   · Corrección del 18-nov: las válvulas cerradas por el registro se leen con «cierres_registro» (por registro; no pide el geovisor). Antes se leían de las
//     afectaciones vigentes del geovisor, y el operador sin esa casilla cerraba la válvula pero no la veía cerrada ni podía abrirla desde aquí.
// «Cierre por aguas arriba» (17-nov): es la opción RECOMENDADA y la primera que se muestra: las válvulas por donde entra el agua al tramo, con sus contratos, el
//   resultado por el otro criterio (el modelo) y el aviso cuando no coinciden. «Aislamiento total» (la simulación de siempre) queda como segunda opción. Si por
//   aguas arriba no se puede, lo dice y muestra el aislamiento total. Si el servidor todavía no tiene la ruta nueva, queda solo el aislamiento total, como antes.
const CRITERIO: Record<string, string> = { cota: "la altura del terreno (el agua baja)", modelo: "el flujo del modelo hidráulico" };
const rango = (min?: number, max?: number) => (min === undefined || max === undefined ? "—" : min !== max ? `De ${nf.format(min)} a ${nf.format(max)}` : nf.format(min));
const MiniMapaCierre = lazy(() => import("./MiniMapaCierre").then((m) => ({ default: m.MiniMapaCierre })));
const nf = new Intl.NumberFormat("es-CO");
const mensaje = (e: unknown) => (e instanceof Error ? e.message : "No se pudo completar. Intente de nuevo.");

export function PanelCierre({ activo, punto, registro }: { activo?: string | null; punto?: { lat: number; lon: number } | null; registro?: string | null }) {
  const [sim, setSim] = useState<Simulacion | null>(null);
  const [ocupado, setOcupado] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [cerradas, setCerradas] = useState<ValvulaDelRegistro[]>([]);
  const [puedeAbrir, setPuedeAbrir] = useState(true);                        // falso: la persona ve la válvula cerrada, pero abrirla pide otro formulario
  const [pedir, setPedir] = useState<{ valvula: string; tipo: "cerrar" | "abrir" } | null>(null);
  const [verMas, setVerMas] = useState(false);
  const [au, setAu] = useState<AguasArriba | null>(null);                    // el cierre por aguas arriba (null: sin calcular o el servidor no lo tiene)
  const [opcion, setOpcion] = useState<"aguas_arriba" | "total">("aguas_arriba");
  const ref = activo ? `a:${activo}` : punto ? `p:${punto.lat.toFixed(5)},${punto.lon.toFixed(5)}` : "";

  const leerCerradas = useCallback(() => {
    if (!registro) { setCerradas([]); setPuedeAbrir(true); return; }
    apiCierre.delRegistro(registro).then((r) => { setCerradas(r.valvulas); setPuedeAbrir(r.puede_abrir !== false); })
      // si el servidor todavía no tiene la lectura por registro, la de antes (solo le responde a quien tiene el geovisor); sin ninguna, el resto del panel sigue
      .catch(() => apiCierre.vigentes().then((r) => { setCerradas(r.valvulas.filter((v) => v.registro === registro)); setPuedeAbrir(true); }).catch(() => { /* la lista de cerradas es ayuda */ }));
  }, [registro]);
  useEffect(() => { leerCerradas(); }, [leerCerradas]);
  useEffect(() => { setSim(null); setAu(null); setOpcion("aguas_arriba"); setError(null); setAviso(null); setPedir(null); }, [ref]);

  async function simular() {
    if (!ref) return;
    setOcupado("Calculando…"); setError(null); setAviso(null);
    const donde = activo ? { activo } : { lat: punto!.lat, lon: punto!.lon };
    try {
      let r: AguasArriba | null = null;
      try { r = await apiCierre.aguasArriba(donde); }
      catch (e) { if (e instanceof ErrorTec && (e.tipo === "red" || e.tipo === "sesion")) throw e; r = null; }      // sin la ruta nueva en el servidor (o si falla): el aislamiento total de siempre
      setAu(r);
      if (r && !r.cae_a_total) { setSim(null); setOpcion("aguas_arriba"); }
      else { setOpcion(r ? "aguas_arriba" : "total"); setSim(r?.aislamiento_total ?? await apiCierre.simular(donde)); }
    } catch (e) { setError(mensaje(e)); } finally { setOcupado(null); }
  }
  async function verTotal() {      // la segunda opción: se calcula al pedirla
    setOpcion("total");
    if (sim || !ref) return;
    setOcupado("Calculando el aislamiento total…"); setError(null);
    try { setSim(await apiCierre.simular(activo ? { activo } : { lat: punto!.lat, lon: punto!.lon })); } catch (e) { setError(mensaje(e)); } finally { setOcupado(null); }
  }
  async function guardar() {
    if (!registro) return;
    setOcupado("Guardando…"); setError(null);
    try { const r = await apiCierre.guardar(registro, sim?.activo.codigo ?? activo); setSim(r); setAviso(`Simulación guardada con ${registro}.`); } catch (e) { setError(mensaje(e)); } finally { setOcupado(null); }
  }
  async function maniobrar(valvula: string, tipo: "cerrar" | "abrir", hecho: string, regreso: string) {
    setOcupado(tipo === "cerrar" ? "Registrando el cierre…" : "Registrando la apertura…"); setError(null); setAviso(null);
    try {
      const r = await apiCierre.maniobra(valvula, tipo, { registro: tipo === "cerrar" ? registro : null, hecho_en: instanteDeCampo(hecho), regreso: tipo === "cerrar" ? instanteDeCampo(regreso) : null });
      setPedir(null);
      setAviso(tipo === "cerrar"
        ? `Válvula ${r.valvula} cerrada (${horaClara(r.hecho_en)}). ${r.vigente.zonas === 0 ? "No deja tramos sin agua." : `En este momento: ${r.vigente.zonas === 1 ? "1 zona sin agua" : `${r.vigente.zonas} zonas sin agua`}, ${nContratos(r.vigente.contratos)}.`}`
        : `Válvula ${r.valvula} abierta (${horaClara(r.hecho_en)}).`);
      leerCerradas();
    } catch (e) { setError(mensaje(e)); } finally { setOcupado(null); }
  }

  const estaCerrada = (c: string) => cerradas.some((v) => v.codigo === c);
  const e = sim?.estrecho;
  const filaValvula = (v: ValvulaSim, i: number) => (
    <li key={v.codigo} className="cie-valvula" data-valvula={v.codigo}>
      <span className="cie-orden" aria-hidden="true">{i + 1}</span>
      <span className="cie-valvula-txt">
        <strong>{v.codigo}{v.codigo_anterior && v.codigo_anterior !== v.codigo ? ` · ${v.codigo_anterior}` : ""}</strong>
        <span>{[v.clase, v.distancia_m !== undefined ? `a ${nf.format(v.distancia_m)} m` : null, v.por_verificar ? "por verificar en campo" : null].filter(Boolean).join(" · ")}</span>
      </span>
      {registro ? (estaCerrada(v.codigo) ? <span className="cie-estado">Cerrada</span>
        : <button type="button" className="tec-boton-sec" disabled={!!ocupado} onClick={() => setPedir({ valvula: v.codigo, tipo: "cerrar" })}>Válvula cerrada</button>) : null}
    </li>);

  return (
    <section className="tec-tarjeta cie" aria-labelledby="cie-tit" data-testid="panel-cierre">
      <h2 id="cie-tit">Cierre de válvulas</h2>
      {cerradas.length ? (
        <div className="cie-cerradas" data-testid="cie-cerradas">
          <p className="cie-rot">Válvulas cerradas por {registro}</p>
          <ul className="cie-lista">{cerradas.map((v) => (
            <li key={v.codigo} className="cie-valvula" data-valvula={v.codigo}>
              <span className="cie-punto" aria-hidden="true" />
              <span className="cie-valvula-txt"><strong>{v.codigo}{v.nombre && v.nombre !== v.codigo ? ` · ${v.nombre}` : ""}</strong>
                <span>Cerrada desde {horaClara(v.desde)}{v.regreso_estimado ? ` · regreso estimado ${horaClara(v.regreso_estimado)}` : ""}</span></span>
              {puedeAbrir ? <button type="button" className="tec-boton-sec" disabled={!!ocupado} onClick={() => setPedir({ valvula: v.codigo, tipo: "abrir" })}>Válvula abierta</button> : null}
            </li>))}</ul>
        </div>) : null}
      {pedir ? <PedirHora valvula={pedir.valvula} tipo={pedir.tipo} ocupado={ocupado} onCancelar={() => setPedir(null)} onConfirmar={(h, r) => void maniobrar(pedir.valvula, pedir.tipo, h, r)} /> : null}
      <p className="tec-ayuda">Según la red registrada en el geoportal: dice qué válvulas cerrar para aislar el daño y cuántos contratos quedan sin agua.</p>
      <button type="button" className="tec-boton" disabled={!ref || !!ocupado} onClick={() => void simular()}>{ocupado === "Calculando…" ? ocupado : "¿Qué válvulas cierro?"}</button>
      {!ref ? <p className="tec-ayuda">{registro ? "Este registro no tiene activo seleccionado: la simulación no se puede hacer desde aquí." : "Elija primero el activo o marque el punto en el mapa."}</p> : null}
      {!registro && (sim || au) ? <p className="tec-ayuda" data-testid="cie-sin-registro">Para marcar una válvula como cerrada, guarde primero este registro.</p> : null}
      {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
      {aviso ? <p className="tec-aviso tec-aviso-ok" role="status">{aviso}</p> : null}
      {au ? (
        <div className="cie-opciones" role="tablist" aria-label="Forma de cerrar" data-testid="cie-opciones">
          <button type="button" role="tab" id="cie-op-au" aria-selected={opcion === "aguas_arriba"} aria-controls="cie-panel" className="cie-opcion" data-opcion="aguas_arriba" disabled={!!ocupado} onClick={() => setOpcion("aguas_arriba")}>
            Cierre por aguas arriba <span className="cie-recomendada">Recomendada</span></button>
          <button type="button" role="tab" id="cie-op-total" aria-selected={opcion === "total"} aria-controls="cie-panel" className="cie-opcion" data-opcion="total" disabled={!!ocupado} onClick={() => void verTotal()}>Aislamiento total</button>
        </div>) : null}
      {au && opcion === "aguas_arriba" ? (
        <div className="cie-resultado" id="cie-panel" role="tabpanel" aria-labelledby="cie-op-au" data-testid="cie-aguas-arriba" data-metodo={au.metodo} aria-live="polite">
          {au.cae_a_total || !au.aguas_arriba.se_puede ? (
            <>
              <p className="tec-aviso cie-aviso-naranja" role="status" data-testid="cie-cae"><strong>Por aguas arriba no se puede.</strong> {au.aguas_arriba.texto ?? "No se pudo determinar por dónde entra el agua."}. Use el aislamiento total.</p>
              <button type="button" className="tec-boton" disabled={!!ocupado} data-testid="cie-ir-total" onClick={() => void verTotal()}>Ver el aislamiento total</button>
            </>
          ) : (
            <>
              <p className="cie-rot">Por donde entra el agua a {au.activo?.codigo ?? activo}</p>
              <p className="cie-texto">{au.aguas_arriba.valvulas_total === 1 ? "Cierre esta válvula:" : `Cierre estas ${au.aguas_arriba.valvulas_total} válvulas, de la más cercana a la más lejana:`}</p>
              <ol className="cie-lista">{(au.aguas_arriba.valvulas ?? []).map(filaValvula)}</ol>
              {(au.aguas_arriba.valvulas_total ?? 0) > (au.aguas_arriba.valvulas ?? []).length ? <p className="tec-ayuda">Se muestran las {(au.aguas_arriba.valvulas ?? []).length} más cercanas de {au.aguas_arriba.valvulas_total}.</p> : null}
              {au.activo ? <Suspense fallback={<p className="tec-sub" role="status">Cargando el mapa…</p>}>
                <MiniMapaCierre activo={au.activo.codigo} lat={au.activo.lat} lon={au.activo.lon} valvulas={au.aguas_arriba.valvulas ?? []} />
              </Suspense> : null}
              <dl className="cie-cifras">
                <div><dt>Tramos sin agua</dt><dd>{rango(au.aguas_arriba.tramos_sin_agua_min, au.aguas_arriba.tramos_sin_agua_max)}</dd></div>
                <div><dt>Contratos sin agua</dt><dd data-testid="cie-au-contratos">{rango(au.aguas_arriba.contratos_min, au.aguas_arriba.contratos_max)}</dd></div>
              </dl>
              <p className="tec-ayuda">Sentido del agua según {CRITERIO[au.criterio] ?? au.criterio}{au.aguas_arriba.entra_por?.codigo ? `; entra por ${au.aguas_arriba.entra_por.codigo}${au.aguas_arriba.entra_por.nombre ? ` (${au.aguas_arriba.entra_por.nombre})` : ""}` : ""}. No es una medición.</p>
            </>)}
          <Comprobacion c={au.comprobacion} />
          {!au.cae_a_total && au.notas.length ? <ul className="cie-notas" data-testid="cie-notas">{au.notas.slice(1).map((n) => <li key={n}>{n}</li>)}</ul> : null}
        </div>) : null}
      {sim && e && (!au || opcion === "total") ? (
        <div className="cie-resultado" data-testid="cie-resultado" aria-live="polite" id={au ? "cie-panel" : undefined} role={au ? "tabpanel" : undefined} aria-labelledby={au ? "cie-op-total" : undefined}>
          <p className="cie-rot">{au ? "Aislamiento total de" : "Para aislar"} {sim.activo.codigo}</p>
          {au ? <p className="tec-ayuda">Cierra todas las válvulas alrededor del tramo, entre o no el agua por ellas.</p> : null}
          {!e.aislable ? <p className="tec-aviso tec-aviso-info">Con las válvulas registradas este tramo no se puede aislar.</p> : (
            <>
              <p className="cie-texto">{e.valvulas_total === 1 ? "Cierre esta válvula:" : `Cierre estas ${e.valvulas_total} válvulas, de la más cercana a la más lejana:`}</p>
              <ol className="cie-lista">{e.valvulas.map(filaValvula)}</ol>
              {e.valvulas_total > e.valvulas.length ? <p className="tec-ayuda">Se muestran las {e.valvulas.length} más cercanas de {e.valvulas_total}.</p> : null}
              <Suspense fallback={<p className="tec-sub" role="status">Cargando el mapa…</p>}>
                <MiniMapaCierre activo={sim.activo.codigo} lat={sim.activo.lat} lon={sim.activo.lon} valvulas={e.valvulas} />
              </Suspense>
            </>)}
          <dl className="cie-cifras">
            <div><dt>Tramos sin agua</dt><dd>{nf.format(e.tramos_sin_agua)}</dd></div>
            <div><dt>Contratos sin agua</dt><dd data-testid="cie-contratos">{sim.rango && sim.contratos_min !== sim.contratos_max ? `De ${nf.format(sim.contratos_min)} a ${nf.format(sim.contratos_max)}` : nf.format(sim.contratos_min)}</dd></div>
          </dl>
          {sim.rango && sim.contratos_min !== sim.contratos_max ? <p className="tec-ayuda">El número menor vale si todas las válvulas de la lista cierran bien; el mayor, si ninguna cierra.</p> : null}
          {sim.segmento_grande ? <p className="tec-aviso tec-aviso-info" data-testid="cie-grande">Este cierre deja sin agua una zona grande. Revise con el supervisor antes de cerrar.</p> : null}
          {sim.si_no_cierra.length ? (
            <div className="cie-mas">
              <button type="button" className="tec-enlace" aria-expanded={verMas} onClick={() => setVerMas((x) => !x)}>{verMas ? "Ocultar «si una válvula no cierra»" : "Si una válvula no cierra…"}</button>
              {verMas ? <ul className="cie-nocierra">{sim.si_no_cierra.map((n) => (
                <li key={n.valvula}><strong>Si {n.valvula} no cierra:</strong> {n.cerrar_en_su_lugar.length ? `cierre ${n.cerrar_en_su_lugar.map((v) => v.codigo).join(", ")}` : "no hace falta cerrar otra"}. Quedan sin agua {nContratos(n.contratos)}.</li>))}</ul> : null}
            </div>) : null}
          {registro ? <button type="button" className="tec-boton-sec" disabled={!!ocupado} onClick={() => void guardar()}>{ocupado === "Guardando…" ? ocupado : "Guardar esta simulación"}</button> : null}
          <p className="cie-nota">No tiene en cuenta presiones ni caudales. Los contratos se cuentan por el tramo más cercano: es una aproximación.</p>
        </div>) : null}
    </section>
  );
}

/** Pide la hora de la maniobra (si no fue ahora) y, al cerrar, la hora estimada de regreso del servicio (opcional). */
export function PedirHora({ valvula, tipo, ocupado, onCancelar, onConfirmar }: { valvula: string; tipo: "cerrar" | "abrir"; ocupado: string | null; onCancelar: () => void; onConfirmar: (hecho: string, regreso: string) => void }) {
  const [hecho, setHecho] = useState(""); const [regreso, setRegreso] = useState("");
  return (
    <div className="cie-pedir" role="group" aria-label={tipo === "cerrar" ? `Cerrar la válvula ${valvula}` : `Abrir la válvula ${valvula}`} data-testid="cie-pedir">
      <p className="cie-rot">{tipo === "cerrar" ? `Válvula ${valvula} cerrada` : `Válvula ${valvula} abierta`}</p>
      <div className="tec-campo"><label htmlFor="cie-hecho">¿A qué hora? <span className="tec-oblig">(déjelo vacío si fue ahora)</span></label>
        <input id="cie-hecho" type="datetime-local" value={hecho} onChange={(e) => setHecho(e.target.value)} /></div>
      {tipo === "cerrar" ? <div className="tec-campo"><label htmlFor="cie-regreso">Regreso estimado del servicio <span className="tec-oblig">(opcional)</span></label>
        <input id="cie-regreso" type="datetime-local" value={regreso} onChange={(e) => setRegreso(e.target.value)} /></div> : null}
      <div className="cie-pedir-acc">
        <button type="button" className="tec-boton" disabled={!!ocupado} onClick={() => onConfirmar(hecho, regreso)}>{ocupado ?? "Confirmar"}</button>
        <button type="button" className="tec-boton-sec" disabled={!!ocupado} onClick={onCancelar}>Cancelar</button>
      </div>
    </div>
  );
}

/** El resultado por el otro criterio (el modelo, cuando manda la cota): se muestra siempre, y avisa cuando no coincide. */
function Comprobacion({ c }: { c: LadoAguasArriba & { coincide: boolean } }) {
  const nombre = c.criterio === "modelo" ? "Resultado del modelo" : "Resultado por la altura del terreno";
  return (
    <div className="cie-comprobacion" data-testid="cie-comprobacion" data-coincide={c.coincide ? "si" : "no"}>
      <p className="cie-rot">{nombre}</p>
      {c.se_puede ? <p className="cie-texto">{c.valvulas_total === 1 ? "1 válvula" : `${nf.format(c.valvulas_total ?? 0)} válvulas`}: {(c.valvulas ?? []).slice(0, 6).map((v) => v.codigo).join(", ")}{(c.valvulas_total ?? 0) > 6 ? "…" : ""} · contratos sin agua: {rango(c.contratos_min, c.contratos_max).toLowerCase()}</p> : null}
      {c.coincide ? <p className="tec-aviso tec-aviso-ok" role="status">Coincide: los dos dan las mismas válvulas.</p>
        : <p className="tec-aviso cie-aviso-naranja" role="status" data-testid="cie-no-coincide">{c.texto ?? "No coincide con el otro criterio: confirme en campo por dónde entra el agua."}.</p>}
    </div>
  );
}
