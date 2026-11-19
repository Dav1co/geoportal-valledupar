import { useCallback, useEffect, useState } from "react";
import "./tokens.css";
import "./tecnica.css";
import "./dano.css";
import "./intervencion.css";
import "./eventos.css";
import { horaClara, nContratos } from "./apiCierre";
import { apiEventos, nReportes, textoReportes, type CatalogoEventos, type Evento } from "./apiEventos";
import { EventoDeclarar, errorEvento } from "./EventoDeclarar";

// Corte 15 · «Eventos de suspensión» (las pantallas; la lógica es del Code A). Cuando se va el agua en una zona llegan decenas de reportes del mismo problema:
// el evento los agrupa, los controla y los cierra en bloque. Esta pantalla se abre desde el Dashboard distribución (pestaña «Suspensiones») y desde el geovisor
// técnico (modo «Afectaciones»). Vistas: la lista, «Declarar evento», el detalle de un evento y los dos catálogos (sectores de cada planta y qué se asocia).
// Quién puede cada cosa lo dice el servidor en el catálogo (`puede`) y lo vuelve a verificar en cada ruta.
type Vista = { v: "lista" } | { v: "declarar" } | { v: "detalle"; codigo: string; aviso?: string } | { v: "plantas" } | { v: "tipos" };
type Filtro = "abierto" | "cerrado" | "anulado" | "todos";
const FILTROS: { c: Filtro; n: string }[] = [{ c: "abierto", n: "Abiertos" }, { c: "cerrado", n: "Cerrados" }, { c: "anulado", n: "Anulados" }, { c: "todos", n: "Todos" }];
export const ESTADO_EVENTO: Record<Evento["estado"], string> = { abierto: "Abierto", cerrado: "Cerrado", anulado: "Anulado" };
const nf = new Intl.NumberFormat("es-CO");

export function EventosSuspension({ onVolver, rotuloVolver = "Volver", inicial, alCambiar }: {
  /** Si viene, la pantalla lleva su barra con «Volver» (cuando se abre desde el geovisor). En el dashboard va dentro de la pestaña, sin barra. */
  onVolver?: () => void; rotuloVolver?: string;
  /** Abrir directo el detalle de un evento (desde la franja o la zona del geovisor) o «Declarar evento». */
  inicial?: { evento?: string; declarar?: boolean };
  /** Algo cambió (se declaró, se cerró, se anuló…): quien la abrió vuelve a leer las zonas vigentes. */
  alCambiar?: () => void;
}) {
  const [cat, setCat] = useState<CatalogoEventos | null>(null);
  const [errorCat, setErrorCat] = useState<string | null>(null);
  const [vista, setVista] = useState<Vista>(inicial?.evento ? { v: "detalle", codigo: inicial.evento } : inicial?.declarar ? { v: "declarar" } : { v: "lista" });
  const [vezCat, setVezCat] = useState(0);
  useEffect(() => { let vivo = true; apiEventos.catalogo().then((c) => { if (vivo) setCat(c); }).catch((e) => { if (vivo) setErrorCat(errorEvento(e)); }); return () => { vivo = false; }; }, [vezCat]);
  const cambio = useCallback(() => { alCambiar?.(); }, [alCambiar]);
  const aLista = () => setVista({ v: "lista" });

  const titulo = vista.v === "declarar" ? "Declarar evento de suspensión" : vista.v === "detalle" ? `Evento ${vista.codigo}` : vista.v === "plantas" ? "Sectores de cada planta" : vista.v === "tipos" ? "Qué reportes se asocian" : "Eventos de suspensión";
  const volver = vista.v === "lista" ? onVolver : aLista;
  const barra = onVolver || vista.v !== "lista" ? (
    <div className="tec-volver-barra">
      {volver ? <button type="button" className="tec-volver" onClick={volver}><span aria-hidden="true">←</span> {vista.v === "lista" ? rotuloVolver : "Volver a los eventos"}</button> : null}
      <span className="tec-volver-tit">{titulo}</span>
    </div>) : null;

  let cuerpo: React.ReactNode;
  if (errorCat) cuerpo = <section className="tec-tarjeta" role="alert"><h2>Eventos de suspensión</h2><p>{errorCat}</p></section>;
  else if (!cat) cuerpo = <p className="tec-sub dan-pad" role="status">Cargando…</p>;
  else if (vista.v === "declarar") cuerpo = <EventoDeclarar cat={cat} onCancelar={aLista}
    onDeclarado={(e) => { cambio(); setVista({ v: "detalle", codigo: e.codigo, aviso: `Evento ${e.codigo} declarado. ${e.asociados_al_declarar === 1 ? "1 reporte que ya estaba en la zona quedó asociado" : `${nf.format(e.asociados_al_declarar)} reportes que ya estaban en la zona quedaron asociados`}.` }); }} />;
  else cuerpo = <Lista cat={cat} onDeclarar={() => setVista({ v: "declarar" })} onAbrir={(codigo) => setVista({ v: "detalle", codigo })} onPlantas={() => setVista({ v: "plantas" })} onTipos={() => setVista({ v: "tipos" })} />;
  void setVezCat;

  return <div className={`tec-modo-distribucion evs-pagina${onVolver ? " tec-pagina" : ""}`} data-testid="eventos" data-vista={vista.v}>{barra}<div className="dan itv evs">{cuerpo}</div></div>;
}

function Lista({ cat, onDeclarar, onAbrir, onPlantas, onTipos }: { cat: CatalogoEventos; onDeclarar: () => void; onAbrir: (codigo: string) => void; onPlantas: () => void; onTipos: () => void }) {
  const [filtro, setFiltro] = useState<Filtro>("abierto");
  const [eventos, setEventos] = useState<Evento[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { let vivo = true; setEventos(null); setError(null);
    apiEventos.lista(filtro).then((r) => { if (vivo) setEventos(r.eventos); }).catch((e) => { if (vivo) setError(errorEvento(e)); }); return () => { vivo = false; }; }, [filtro]);
  const puedeDeclarar = cat.puede.zona || cat.puede.total;
  return (
    <>
      <section className="tec-tarjeta" aria-labelledby="evs-tit" data-testid="evs-lista">
        <h2 id="evs-tit">Eventos de suspensión</h2>
        <p className="red-texto">Cuando se va el agua en una zona, el evento agrupa todos los reportes del mismo problema (bot, línea 116, daños y formato de campo), le dice a quien reporta que ya se sabe del corte y los cierra todos al volver el servicio.</p>
        <div className="evs-barra">
          {puedeDeclarar ? <button type="button" className="tec-boton" data-testid="evs-nuevo" onClick={onDeclarar}>Declarar evento</button> : null}
          {cat.puede.reportes ? <button type="button" className="tec-boton-sec" data-testid="evs-ir-plantas" onClick={onPlantas}>Sectores de cada planta</button> : null}
          {cat.puede.reportes ? <button type="button" className="tec-boton-sec" data-testid="evs-ir-tipos" onClick={onTipos}>Qué reportes se asocian</button> : null}
        </div>
        {!puedeDeclarar ? <p className="tec-ayuda">Su perfil puede ver los eventos, pero no declararlos.</p> : null}
        <div className="dan-fila" role="group" aria-label="Estado de los eventos">{FILTROS.map((f) => <button key={f.c} type="button" className="dan-opcion" aria-pressed={filtro === f.c} data-filtro={f.c} onClick={() => setFiltro(f.c)}>{f.n}</button>)}</div>
        {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
      </section>
      {!eventos && !error ? <p className="tec-sub dan-pad" role="status">Cargando…</p> : null}
      {eventos && eventos.length === 0 ? <section className="tec-tarjeta"><p className="red-vacio" data-testid="evs-vacio">{filtro === "abierto" ? "No hay eventos de suspensión abiertos en este momento." : "No hay eventos con ese estado."}</p></section> : null}
      {eventos?.map((e) => <TarjetaEvento key={e.codigo} e={e} onAbrir={() => onAbrir(e.codigo)} />)}
    </>
  );
}

/** Un evento en la lista: su franja en lenguaje claro, los conteos y «Ver el evento». */
export function TarjetaEvento({ e, onAbrir }: { e: Evento; onAbrir?: () => void }) {
  return (
    <section className="tec-tarjeta itv-bandeja" aria-label={`Evento ${e.codigo}`} data-evento={e.codigo} data-estado={e.estado}>
      <h2><span className="tec-codigo">{e.codigo}</span> <span className={`itv-etiqueta evs-estado-${e.estado}`}>{ESTADO_EVENTO[e.estado]}</span></h2>
      <p className="evs-franja-txt">{e.franja}</p>
      <dl className="evs-lista-datos">
        <div><dt>Contratos en la zona</dt><dd>{nContratos(e.contratos)}{e.sensibles ? ` · ${nf.format(e.sensibles)} ${e.sensibles === 1 ? "usuario sensible" : "usuarios sensibles"}` : ""}</dd></div>
        <div><dt>Reportes</dt><dd data-dato="reportes">{nReportes(e.reportes.total)}{e.reportes.total ? ` (${textoReportes(e.reportes)})` : ""}</dd></div>
        <div><dt>Declarado</dt><dd>{horaClara(e.declarado_en)} · {e.declarado_por}</dd></div>
        {e.fin ? <div><dt>{e.estado === "anulado" ? "Anulado" : "Cerrado"}</dt><dd>{horaClara(e.fin.cuando)} · {e.fin.por}</dd></div> : null}
      </dl>
      {onAbrir ? <div className="tec-acciones"><button type="button" className="tec-boton-sec" onClick={onAbrir}>Ver el evento</button></div> : null}
    </section>
  );
}
