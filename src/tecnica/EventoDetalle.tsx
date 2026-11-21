import { Suspense, useEffect, useState } from "react";
import { lazyConRecarga } from "../lib/recarga";
import { horaClara, instanteDeCampo, nContratos } from "./apiCierre";
import { apiEventos, NOMBRE_ORIGEN, nReportes, textoAlcance, textoOrigen, textoReportes, type Asociado, type CatalogoEventos, type EventoDetalle as Detalle, type OrigenReporte } from "./apiEventos";
import { errorEvento } from "./EventoDeclarar";

// Corte 15 · Detalle de un evento de suspensión: qué zona, por qué, desde cuándo y hasta cuándo; los contratos y los usuarios sensibles de la zona; los reportes
// asociados (del bot, de la línea 116, daños y formato de campo) y su historial. Acciones, con motivo y sin borrar nada:
// · ajustar el regreso estimado · cerrar en bloque («dar de alta»: los reportes del bot, la 116 y campo quedan atendidos con el mismo motivo y la misma hora; los
//   daños NO se cierran, siguen hasta su reparación) · anular (los reportes vuelven a su flujo) · desasociar un reporte que es otro problema · asociar uno a mano.
// Quién puede: un total, el supervisor de planta o el administrador; por sectores o círculo, el supervisor de distribución o el administrador; los reportes, el
// supervisor de distribución o el administrador. Lo vuelve a decidir el servidor. Sin nombres de suscriptores: los sensibles van por contrato y tipo.
const MiniMapaEvento = lazyConRecarga(() => import("./MiniMapaEvento").then((m) => ({ default: m.MiniMapaEvento })));
const nf = new Intl.NumberFormat("es-CO");
const ESTADO = { abierto: "Abierto", cerrado: "Cerrado", anulado: "Anulado" } as const;
const MODO: Record<Asociado["modo"], string> = { automatica: "se asoció solo al llegar", al_declarar: "ya estaba en la zona al declarar", manual: "asociado a mano" };
const QUE: Record<string, string> = { regreso: "Se ajustó el regreso estimado", cerrar: "Se cerró el evento", anular: "Se anuló el evento", desasociar: "Se desasoció un reporte", asociar_a_mano: "Se asoció un reporte a mano" };
const aLocal = (d: Date) => new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
type Accion = "" | "regreso" | "cerrar" | "anular" | "asociar";

export function EventoDetalle({ codigo, cat, avisoInicial, alCambiar }: { codigo: string; cat: CatalogoEventos; avisoInicial?: string; alCambiar: () => void }) {
  const [d, setD] = useState<Detalle | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(avisoInicial ?? null);
  const [vez, setVez] = useState(0);
  const [accion, setAccion] = useState<Accion>("");
  const [ocupado, setOcupado] = useState<string | null>(null); const [errorAccion, setErrorAccion] = useState<string | null>(null);
  const [regreso, setRegreso] = useState(""); const [motivo, setMotivo] = useState(""); const [hecho, setHecho] = useState("");
  const [origen, setOrigen] = useState<OrigenReporte>("bot"); const [ref, setRef] = useState("");
  const [quitando, setQuitando] = useState<string | null>(null); const [motivoQuitar, setMotivoQuitar] = useState("");

  useEffect(() => { let vivo = true; setError(null);
    apiEventos.detalle(codigo).then((r) => { if (vivo) setD(r); }).catch((e) => { if (vivo) setError(errorEvento(e)); }); return () => { vivo = false; }; }, [codigo, vez]);
  const abrirAccion = (a: Accion) => { setAccion(a); setErrorAccion(null); setMotivo(""); setRegreso(""); setHecho(""); setRef(""); setQuitando(null); };
  async function hacer(texto: string, f: () => Promise<string>) {
    setOcupado(texto); setErrorAccion(null);
    try { const t = await f(); setAviso(t); setAccion(""); setQuitando(null); setMotivoQuitar(""); setVez((v) => v + 1); alCambiar(); }
    catch (e) { setErrorAccion(errorEvento(e)); } finally { setOcupado(null); }
  }

  if (error) return <section className="tec-tarjeta" role="alert"><h2>Evento {codigo}</h2><p>{error}</p></section>;
  if (!d) return <p className="tec-sub dan-pad" role="status">Cargando el evento…</p>;
  const abierto = d.estado === "abierto";
  const puedeEvento = abierto && (d.alcance === "total" ? cat.puede.total : cat.puede.zona);
  const puedeReportes = abierto && cat.puede.reportes;
  const enBloque = d.reportes.bot + d.reportes.l116 + d.reportes.campo;
  const regresoIso = instanteDeCampo(regreso), hechoIso = instanteDeCampo(hecho);
  const clave = (a: Asociado) => `${a.origen}:${a.ref}`;

  return (
    <div className="evs" data-testid="evs-detalle" data-evento={d.codigo} data-estado={d.estado}>
      <section className="tec-tarjeta" aria-labelledby="evs-d-tit">
        <h2 id="evs-d-tit"><span className="tec-codigo">{d.codigo}</span> <span className={`itv-etiqueta evs-estado-${d.estado}`} data-testid="evs-estado">{ESTADO[d.estado]}</span></h2>
        {aviso ? <p className="tec-aviso tec-aviso-ok" role="status" data-testid="evs-aviso">{aviso} <button type="button" className="tec-enlace" onClick={() => setAviso(null)}>Cerrar</button></p> : null}
        <p className="evs-franja-txt" data-testid="evs-franja">{d.franja}</p>
        <dl className="evs-lista-datos">
          <div><dt>Alcance</dt><dd data-dato="alcance">{textoAlcance(d)}</dd></div>
          {d.tubos?.length ? <div><dt>{d.tubos.length === 1 ? "Tubo de salida" : "Tubos de salida"}</dt><dd data-dato="tubos">{d.tubos.map((t, i) => <span key={t.codigo}>{i ? ", " : ""}{t.nombre} <small className="evs-tubo-cod tec-codigo">{t.codigo}</small></span>)}</dd></div> : null}
          <div><dt>Zona</dt><dd>{d.zona}{d.alcance === "circulo" && d.circulo ? ` (radio ${nf.format(Math.round(d.circulo.radio_m))} m)` : d.alcance === "sectores" ? ` (${d.sectores.length} ${d.sectores.length === 1 ? "sector o subsector" : "sectores o subsectores"})` : ""}</dd></div>
          {d.origen ? <div><dt>Origen</dt><dd data-dato="origen">{textoOrigen(d)}</dd></div> : null}
          <div><dt>{d.origen ? "Observación (solo se ve en pantalla)" : "Causa"}</dt><dd data-dato="observacion">{d.causa}{!d.origen && d.registro ? ` · ${d.registro}` : ""}</dd></div>
          <div><dt>Sin agua desde</dt><dd>{horaClara(d.desde)}</dd></div>
          <div><dt>Regreso estimado</dt><dd data-dato="regreso">{d.regreso_estimado ? horaClara(d.regreso_estimado) : "Todavía no hay hora estimada"}</dd></div>
          <div><dt>Declarado</dt><dd>{horaClara(d.declarado_en)} · {d.declarado_por}</dd></div>
          {d.fin ? <div><dt>{d.estado === "anulado" ? "Anulado" : "Cerrado"}</dt><dd data-dato="fin">{horaClara(d.fin.cuando)} · {d.fin.por} · «{d.fin.motivo}»</dd></div> : null}
        </dl>
        <dl className="evs-datos">
          <div><dt>Contratos en la zona</dt><dd data-dato="contratos">{nf.format(d.contratos)}</dd></div>
          <div><dt>Usuarios sensibles</dt><dd data-dato="sensibles">{nf.format(d.sensibles)}</dd></div>
          <div><dt>Reportes asociados</dt><dd data-dato="reportes">{nf.format(d.reportes.total)}{d.reportes.total ? <small> ({textoReportes(d.reportes)})</small> : null}</dd></div>
        </dl>
        {d.sensibles_lista.length ? (
          <details className="evs-sensibles" data-testid="evs-sensibles"><summary>Usuarios sensibles de la zona ({nf.format(d.sensibles_lista.length)}): conviene avisarles primero</summary>
            <ul>{d.sensibles_lista.map((s) => <li key={s.contrato}>Contrato <span className="tec-codigo">{s.contrato}</span> · {s.tipo}</li>)}</ul>
            <p className="tec-ayuda">Solo el contrato y el tipo: aquí no hay nombres.</p></details>) : null}
        {d.zona_geojson ? <Suspense fallback={<p className="tec-sub" role="status">Cargando el mapa…</p>}><MiniMapaEvento zona={d.zona_geojson} /></Suspense>
          : <p className="tec-ayuda">Toda la ciudad: no se dibuja una zona en el mapa.</p>}

        {abierto && !puedeEvento ? <p className="tec-ayuda" data-testid="evs-sin-permiso">{d.alcance === "total" ? "Un evento total lo ajusta, lo cierra o lo anula el supervisor de planta o el administrador." : "Este evento lo ajusta, lo cierra o lo anula el supervisor de distribución o el administrador."}</p> : null}
        {puedeEvento && accion === "" ? (
          <div className="tec-acciones" data-testid="evs-acciones">
            <button type="button" className="tec-boton" onClick={() => abrirAccion("cerrar")}>Cerrar el evento (volvió el agua)</button>
            <button type="button" className="tec-boton-sec" onClick={() => abrirAccion("regreso")}>Ajustar el regreso estimado</button>
            <button type="button" className="tec-boton-sec" onClick={() => abrirAccion("anular")}>Anular el evento</button>
          </div>) : null}

        {accion === "regreso" ? (
          <div className="cie-pedir" role="group" aria-label="Ajustar el regreso estimado" data-testid="evs-f-regreso">
            <div className="tec-campo"><label htmlFor="evs-n-regreso">Nuevo regreso estimado del servicio</label>
              <input id="evs-n-regreso" type="datetime-local" className="dan-hora" value={regreso} onChange={(e) => setRegreso(e.target.value)} /></div>
            <div className="tec-campo"><label htmlFor="evs-m-regreso">Motivo <span className="tec-oblig">(opcional)</span></label>
              <input id="evs-m-regreso" type="text" maxLength={300} value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="La reparación tomó más tiempo…" /></div>
            <p className="tec-ayuda">Es la hora que se le dice a quien reporta. El cambio queda en el historial.</p>
            <div className="tec-acciones">
              <button type="button" className="tec-boton" disabled={!!ocupado || !regresoIso} onClick={() => void hacer("Guardando…", async () => { await apiEventos.regreso(d.codigo, regresoIso!, motivo.trim() || undefined); return "Regreso estimado ajustado."; })}>{ocupado ?? "Guardar la hora"}</button>
              <button type="button" className="tec-boton-sec" disabled={!!ocupado} onClick={() => setAccion("")}>Cancelar</button></div>
          </div>) : null}

        {accion === "cerrar" ? (
          <div className="cie-pedir" role="group" aria-label="Cerrar el evento" data-testid="evs-f-cerrar">
            <p className="red-texto" data-testid="evs-cierre-explica">Al cerrar, {enBloque === 0 ? "no hay reportes del bot, de la línea 116 ni de campo por cerrar" : `${enBloque === 1 ? "el reporte" : `los ${nf.format(enBloque)} reportes`} del bot, de la línea 116 y de campo ${enBloque === 1 ? "queda atendido" : "quedan atendidos"}, con este mismo motivo y la misma hora`}.
              {d.reportes.danos ? ` ${d.reportes.danos === 1 ? "El daño asociado NO se cierra: sigue" : `Los ${d.reportes.danos} daños asociados NO se cierran: siguen`} hasta su reparación.` : ""} Nada se borra.</p>
            <div className="tec-campo"><label htmlFor="evs-m-cerrar">Motivo del cierre (10 caracteres o más)</label>
              <textarea id="evs-m-cerrar" className="dan-texto" rows={2} maxLength={500} value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Se reparó la tubería y el servicio volvió a la zona." /></div>
            <div className="tec-campo"><label htmlFor="evs-h-cerrar">¿A qué hora volvió el agua? <span className="tec-oblig">(vacío = ahora)</span></label>
              <input id="evs-h-cerrar" type="datetime-local" className="dan-hora" max={aLocal(new Date())} value={hecho} onChange={(e) => setHecho(e.target.value)} /></div>
            <div className="tec-acciones">
              <button type="button" className="tec-boton" disabled={!!ocupado || motivo.trim().length < 10} data-testid="evs-cerrar-confirmar"
                onClick={() => void hacer("Cerrando…", async () => { const r = await apiEventos.cerrar(d.codigo, motivo.trim(), hechoIso);
                  const n = r.cerrados.bot + r.cerrados.l116 + r.cerrados.campo;
                  return `Evento cerrado. ${n === 0 ? "No había reportes por cerrar" : `${n === 1 ? "1 reporte quedó atendido" : `${nf.format(n)} reportes quedaron atendidos`} (${[r.cerrados.bot ? `${r.cerrados.bot} del bot` : "", r.cerrados.l116 ? `${r.cerrados.l116} de la línea 116` : "", r.cerrados.campo ? `${r.cerrados.campo} de campo` : ""].filter(Boolean).join(" · ")})`}.${r.danos_siguen_abiertos ? ` ${r.danos_siguen_abiertos === 1 ? "1 daño sigue abierto" : `${r.danos_siguen_abiertos} daños siguen abiertos`} hasta su reparación.` : ""}`; })}>{ocupado ?? "Cerrar el evento"}</button>
              <button type="button" className="tec-boton-sec" disabled={!!ocupado} onClick={() => setAccion("")}>Cancelar</button></div>
          </div>) : null}

        {accion === "anular" ? (
          <div className="cie-pedir" role="group" aria-label="Anular el evento" data-testid="evs-f-anular">
            <p className="red-texto">Anular es para un evento declarado por error. {d.reportes.total ? `${d.reportes.total === 1 ? "El reporte asociado vuelve" : `Los ${nf.format(d.reportes.total)} reportes asociados vuelven`} a su flujo normal.` : ""} Nada se borra: queda en el historial con el motivo.</p>
            <div className="tec-campo"><label htmlFor="evs-m-anular">Motivo (10 caracteres o más)</label>
              <textarea id="evs-m-anular" className="dan-texto" rows={2} maxLength={500} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></div>
            <div className="tec-acciones">
              <button type="button" className="tec-boton" disabled={!!ocupado || motivo.trim().length < 10} data-testid="evs-anular-confirmar"
                onClick={() => void hacer("Anulando…", async () => { const r = await apiEventos.anular(d.codigo, motivo.trim()); return `Evento anulado. ${r.reportes_liberados === 1 ? "1 reporte volvió" : `${nf.format(r.reportes_liberados)} reportes volvieron`} a su flujo.`; })}>{ocupado ?? "Anular el evento"}</button>
              <button type="button" className="tec-boton-sec" disabled={!!ocupado} onClick={() => setAccion("")}>Cancelar</button></div>
          </div>) : null}
        {errorAccion && accion !== "asociar" && !quitando ? <p className="tec-aviso tec-aviso-error" role="alert" data-testid="evs-error">{errorAccion}</p> : null}
      </section>

      <section className="tec-tarjeta" aria-labelledby="evs-d-rep" data-testid="evs-asociados">
        <h2 id="evs-d-rep">{nReportes(d.reportes.total)}</h2>
        <p className="tec-ayuda">Todo reporte que llega dentro de la zona mientras el evento está abierto queda asociado. Si uno es otro problema, desasócielo con el motivo: vuelve a su flujo.</p>
        {d.asociados.length === 0 ? <p className="red-vacio">Todavía no hay reportes asociados a este evento.</p> : null}
        <ul className="evs-items">
          {d.asociados.map((a) => (
            <li key={clave(a)} data-asociado={clave(a)}>
              <p><strong>{a.rotulo}</strong>{a.tipo ? ` · ${a.tipo}` : ""}</p>
              <p className="tec-ayuda">{NOMBRE_ORIGEN[a.origen]}{a.cuando ? ` · ${horaClara(a.cuando)}` : ""} · {MODO[a.modo]}</p>
              {puedeReportes && quitando !== clave(a) ? <button type="button" className="tec-enlace" onClick={() => { setQuitando(clave(a)); setMotivoQuitar(""); setErrorAccion(null); setAccion(""); }}>Desasociar</button> : null}
              {quitando === clave(a) ? (
                <div className="cie-pedir" role="group" aria-label={`Desasociar ${a.rotulo}`}>
                  <div className="tec-campo"><label htmlFor="evs-m-quitar">¿Por qué no es de este evento? (10 caracteres o más)</label>
                    <input id="evs-m-quitar" type="text" maxLength={300} value={motivoQuitar} onChange={(e) => setMotivoQuitar(e.target.value)} placeholder="Es una fuga interna del predio, no la falta de agua de la zona." /></div>
                  {errorAccion ? <p className="tec-aviso tec-aviso-error" role="alert">{errorAccion}</p> : null}
                  <div className="tec-acciones">
                    <button type="button" className="tec-boton" disabled={!!ocupado || motivoQuitar.trim().length < 10} data-testid="evs-quitar-confirmar"
                      onClick={() => void hacer("Desasociando…", async () => { await apiEventos.desasociar(d.codigo, a.origen, a.ref, motivoQuitar.trim()); return `${a.rotulo} desasociado: vuelve a su flujo.`; })}>{ocupado ?? "Desasociar"}</button>
                    <button type="button" className="tec-boton-sec" disabled={!!ocupado} onClick={() => setQuitando(null)}>Cancelar</button></div>
                </div>) : null}
            </li>))}
        </ul>
        {d.lista_max && d.reportes.total > d.asociados.length ? <p className="tec-ayuda">Se muestran los {d.asociados.length} más recientes de {nf.format(d.reportes.total)}.</p> : null}
        {puedeReportes && accion !== "asociar" ? <button type="button" className="tec-boton-sec" data-testid="evs-asociar" onClick={() => abrirAccion("asociar")}>Asociar un reporte a mano</button> : null}
        {accion === "asociar" ? (
          <div className="cie-pedir" role="group" aria-label="Asociar un reporte a mano" data-testid="evs-f-asociar">
            <div className="dan-fila" role="group" aria-label="De dónde es el reporte">
              {(["bot", "l116", "dano", "campo"] as OrigenReporte[]).map((o) => <button key={o} type="button" className="dan-opcion" aria-pressed={origen === o} data-origen={o} onClick={() => setOrigen(o)}>{NOMBRE_ORIGEN[o]}</button>)}</div>
            <div className="tec-campo"><label htmlFor="evs-ref">{origen === "dano" ? "Código del daño" : origen === "campo" ? "Código del reporte de campo" : origen === "l116" ? "Número del reporte de la línea 116" : "Identificador del reporte del bot"}</label>
              <input id="evs-ref" type="text" maxLength={40} autoComplete="off" value={ref} onChange={(e) => setRef(e.target.value)} placeholder={origen === "dano" ? "DAN-000123" : origen === "campo" ? "REP-000123" : ""} /></div>
            <div className="tec-campo"><label htmlFor="evs-m-asociar">Motivo (10 caracteres o más)</label>
              <input id="evs-m-asociar" type="text" maxLength={300} value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Está fuera de la zona, pero es por el mismo corte." /></div>
            {errorAccion ? <p className="tec-aviso tec-aviso-error" role="alert" data-testid="evs-error-asociar">{errorAccion}</p> : null}
            <div className="tec-acciones">
              <button type="button" className="tec-boton" disabled={!!ocupado || !ref.trim() || motivo.trim().length < 10} data-testid="evs-asociar-confirmar"
                onClick={() => void hacer("Asociando…", async () => { await apiEventos.asociar(d.codigo, origen, origen === "dano" || origen === "campo" ? ref.trim().toUpperCase() : ref.trim(), motivo.trim()); return "Reporte asociado al evento."; })}>{ocupado ?? "Asociar"}</button>
              <button type="button" className="tec-boton-sec" disabled={!!ocupado} onClick={() => setAccion("")}>Cancelar</button></div>
          </div>) : null}
      </section>

      <section className="tec-tarjeta" aria-labelledby="evs-d-his" data-testid="evs-historial">
        <h2 id="evs-d-his">Historial</h2>
        <ul className="evs-items">
          <li><p><strong>Se declaró el evento</strong></p><p className="tec-ayuda">{horaClara(d.declarado_en)} · {d.declarado_por} · {nContratos(d.contratos)} en la zona</p></li>
          {d.historial.map((h, i) => <li key={i} data-que={h.que}><p><strong>{QUE[h.que] ?? h.que}</strong>{h.motivo ? `: «${h.motivo}»` : ""}</p><p className="tec-ayuda">{horaClara(h.cuando)} · {h.por}</p></li>)}
        </ul>
      </section>
    </div>
  );
}
