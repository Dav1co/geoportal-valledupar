import { useEffect, useState } from "react";
import { apiRedes, type ActivoCorto, type Epicrisis, type EventoEpicrisis, type Ficha } from "./apiRedes";
import { ErrorTec } from "./apiTecnica";

// Ficha del activo (solo lectura), como la maqueta Ficha.dc.html: datos del activo con el nombre visible del tipo (alias, N-12),
// origen (solo si el servidor lo manda: supervisor y administrador), red (extremos o tramos que llegan), componentes y epicrisis.
// La epicrisis de daños e intervenciones queda vacía hasta los Cortes 2 y 3; los cambios del registro (alta, versiones, retiros) sí se ven.

const ETAPAS: Record<string, string> = {
  captacion: "Captación", aduccion: "Aducción", tratamiento: "Tratamiento", almacenamiento: "Almacenamiento", conduccion: "Conducción",
  distribucion: "Distribución", recoleccion: "Recolección", transporte: "Transporte", disposicion: "Disposición", gestion: "Gestión", medicion: "Medición",
};
const ORIGENES: { codigo: "emdupar" | "tercero" | "mixto"; nombre: string }[] = [
  { codigo: "emdupar", nombre: "EMDUPAR" }, { codigo: "tercero", nombre: "Tercero" }, { codigo: "mixto", nombre: "Tercero y EMDUPAR" },
];
const nf = new Intl.NumberFormat("es-CO", { maximumFractionDigits: 2 });

function valor(v: unknown, unidad?: string): string | null {
  if (v === undefined || v === null || v === "") return null;
  if (typeof v === "number") return `${nf.format(v)}${unidad ? " " + unidad : ""}`;
  if (typeof v === "boolean") return v ? "Sí" : "No";
  return `${String(v)}${unidad ? " " + unidad : ""}`;
}
const fecha = (iso: string) => new Date(iso).toLocaleString("es-CO", { timeZone: "America/Bogota", day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
const fechaDia = (iso: string) => { const [a, m, d] = iso.slice(0, 10).split("-"); return `${d}/${m}/${a}`; };
const tonoEstado = (a: { retirado: boolean; cuenta_vigente?: boolean; punteado?: boolean }) =>
  a.retirado ? "red-estado-retirado" : a.punteado || a.cuenta_vigente === false ? "red-estado-aviso" : "red-estado-ok";

function Dato({ rotulo, v }: { rotulo: string; v: string | null }) {
  return (
    <div className="red-dato">
      <span className="red-dato-rot">{rotulo}</span>
      <span className={v === null || v === "Sin dato" ? "red-dato-val red-sin-dato" : "red-dato-val"}>{v ?? "Sin dato"}</span>
    </div>
  );
}

function FilaActivo({ a, onAbrir, detalle }: { a: ActivoCorto; onAbrir: (c: string) => void; detalle?: string }) {
  return (
    <button type="button" className="red-fila" onClick={() => onAbrir(a.codigo)}>
      <span className={a.prefijo === "RED" || a.prefijo === "CON" || a.prefijo === "COL" ? "red-icono red-icono-linea" : "red-icono"} aria-hidden="true" />
      <span className="red-fila-txt">
        <span className="red-fila-cod">{a.codigo}</span>
        <span className="red-fila-sub">{a.tipo}{a.clase ? ` · ${a.clase}` : ""}{detalle ? ` · ${detalle}` : ""}</span>
      </span>
      <span className={`red-fila-estado ${tonoEstado(a)}`}>{a.retirado ? "Retirado" : a.estado}</span>
    </button>
  );
}

export function FichaActivo({ codigo, onVolver, onAbrir, rotuloVolver, onRegistrarIntervencion }: {
  codigo: string; onVolver: () => void; onAbrir: (c: string) => void; rotuloVolver: string;
  onRegistrarIntervencion?: (a: { codigo: string; sistema: "acueducto" | "alcantarillado"; lat: number; lon: number }) => void;     // Corte 3a (pospuesto del 1b)
}) {
  const [ficha, setFicha] = useState<Ficha | null>(null);
  const [error, setError] = useState<ErrorTec | null>(null);
  const [epi, setEpi] = useState<Epicrisis | null>(null);
  const [errorEpi, setErrorEpi] = useState<string | null>(null);
  const [cargandoMas, setCargandoMas] = useState(false);
  const [intento, setIntento] = useState(0);

  useEffect(() => {
    let vivo = true;
    setFicha(null); setError(null); setEpi(null); setErrorEpi(null);
    apiRedes.activo(codigo)
      .then((f) => { if (vivo) setFicha(f); })
      .catch((e) => { if (vivo) setError(e instanceof ErrorTec ? e : new ErrorTec("servidor", "No se pudo cargar la ficha.", 0)); });
    apiRedes.epicrisis(codigo)
      .then((r) => { if (vivo) setEpi(r); })
      .catch((e) => { if (vivo) setErrorEpi(e instanceof Error ? e.message : "No se pudo cargar la epicrisis."); });
    window.scrollTo?.(0, 0);
    return () => { vivo = false; };
  }, [codigo, intento]);

  const masEpicrisis = () => {
    if (!epi?.siguiente) return;
    setCargandoMas(true);
    apiRedes.epicrisis(codigo, epi.siguiente)
      .then((r) => setEpi({ ...r, items: [...epi.items, ...r.items] }))
      .catch((e) => setErrorEpi(e instanceof Error ? e.message : "No se pudo cargar."))
      .finally(() => setCargandoMas(false));
  };

  const volver = (
    <button type="button" className="red-volver" onClick={onVolver}>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M15 6l-6 6 6 6" /></svg>
      {rotuloVolver}
    </button>
  );

  if (error) {
    return (
      <div className="red-ficha">
        <header className="red-cabeza">{volver}<h1 className="red-codigo">{codigo}</h1></header>
        <section className="red-seccion" role="alert">
          <p className="red-texto"><strong>{error.tipo === "permiso" ? "No tiene permiso para ver esta ficha." : error.message}</strong></p>
          {error.tipo !== "permiso" && error.status !== 404 ? <button type="button" className="tec-boton-sec" onClick={() => setIntento((i) => i + 1)}>Reintentar</button> : null}
        </section>
      </div>
    );
  }
  if (!ficha) return <div className="red-ficha"><header className="red-cabeza">{volver}<h1 className="red-codigo">{codigo}</h1></header><p className="tec-sub red-cargando" role="status">Cargando la ficha…</p></div>;

  const a = ficha.activo;
  const claves = new Set(a.campos.map((c) => c.clave));
  const hechos = (epi?.items ?? []).filter((e) => e.grupo === "hecho");
  const registro = (epi?.items ?? []).filter((e) => e.grupo === "registro");
  const modelo = ficha.modelo ? Object.entries(ficha.modelo).filter(([, v]) => v !== null && v !== "") : [];

  return (
    <div className="red-ficha">
      <header className="red-cabeza">
        {volver}
        <span className="red-ceja">{a.sistema_nombre} · {ETAPAS[a.etapa] ?? a.etapa}</span>
        <h1 className="red-codigo">{a.codigo}</h1>
        <span className="red-tipo">{a.tipo}{a.clase ? ` · ${a.clase}` : ""}{a.nombre ? ` · ${a.nombre}` : ""}</span>
        <div className="red-chips">
          <span className={`red-chip ${tonoEstado(a)}`}>{a.retirado ? "Retirado" : a.estado}</span>
          {a.codigo_anterior ? <span className="red-chip red-chip-suave">Código anterior: {a.codigo_anterior}</span> : null}
          {a.por_verificar ? <span className="red-chip red-chip-suave">Por verificar</span> : null}
        </div>
        {onRegistrarIntervencion && !a.retirado && (a.sistema === "acueducto" || a.sistema === "alcantarillado") ? (
          <button type="button" className="tec-boton red-accion" onClick={() => onRegistrarIntervencion({ codigo: a.codigo, sistema: a.sistema as "acueducto" | "alcantarillado", lat: a.lat, lon: a.lon })}>Registrar intervención</button>
        ) : null}
      </header>

      <div className="red-cuerpo">
        {a.retirado ? <p className="tec-aviso tec-aviso-error red-aviso">Este activo está retirado: no vino en la última carga de su capa. Su hoja de vida se conserva.</p> : null}
        {!a.retirado && a.punteado ? <p className="tec-aviso tec-aviso-info red-aviso">Estado «{a.estado}»: se dibuja punteado y no cuenta como activo vigente en los indicadores.</p> : null}

        <section className="red-seccion" aria-labelledby="red-t-datos">
          <h2 id="red-t-datos">Datos del activo</h2>
          <div className="red-rejilla">
            <Dato rotulo="Tipo" v={a.tipo} />
            <Dato rotulo="Etapa" v={ETAPAS[a.etapa] ?? a.etapa} />
            {!claves.has("material_codigo") && a.material ? <Dato rotulo="Material" v={a.material} /> : null}
            {a.campos.map((c) => <Dato key={c.clave} rotulo={c.rotulo} v={valor(c.valor, c.unidad)} />)}
            <Dato rotulo="Fecha de instalación" v={a.fecha_instalacion ? fechaDia(a.fecha_instalacion) : null} />
            <Dato rotulo="Barrio o sector" v={a.barrio_sector ?? null} />
          </div>
          {a.tipo !== a.tipo_catalogo ? <p className="red-nota">En el catálogo: {a.tipo_catalogo} ({a.prefijo}).</p> : null}
        </section>

        {ficha.tramo || ficha.nodo || ficha.contratos_enlazados !== undefined ? (
          <section className="red-seccion" aria-labelledby="red-t-red">
            <h2 id="red-t-red">En la red</h2>
            {ficha.tramo ? (
              <div className="red-lista">
                {(["inicio", "fin"] as const).map((k) => {
                  const ext = ficha.tramo?.[k];
                  if (!ext) return <div key={k} className="red-fila red-fila-fija"><span className="red-fila-txt"><span className="red-fila-sub">{k === "inicio" ? "Desde" : "Hasta"}: sin nodo en la topología</span></span></div>;
                  return ext.activo
                    ? <FilaActivo key={k} a={ext.activo} onAbrir={onAbrir} detalle={`${k === "inicio" ? "desde" : "hasta"} ${ext.nombre}`} />
                    : <div key={k} className="red-fila red-fila-fija"><span className="red-icono red-icono-nodo" aria-hidden="true" /><span className="red-fila-txt"><span className="red-fila-cod">{ext.nombre}</span><span className="red-fila-sub">{k === "inicio" ? "Desde" : "Hasta"} · nodo del modelo, sin activo</span></span></div>;
                })}
              </div>
            ) : null}
            {ficha.nodo ? <Dato rotulo="Nodo del modelo" v={`${ficha.nodo.nombre_visible} · ${ficha.nodo.tramos === 1 ? "llega 1 tramo" : `llegan ${ficha.nodo.tramos} tramos`}`} /> : null}
            {ficha.contratos_enlazados !== undefined ? <Dato rotulo="Contratos enlazados a este tramo (por cercanía)" v={nf.format(ficha.contratos_enlazados)} /> : null}
            {ficha.tramo && ficha.tramo.metodo !== "modelo" ? <p className="red-nota">Enlace de la topología: {ficha.tramo.metodo === "extremos" ? "por cercanía de los extremos" : "incompleto"}.</p> : null}
          </section>
        ) : null}

        {ficha.origen ? (
          <section className="red-seccion" aria-labelledby="red-t-origen">
            <h2 id="red-t-origen">Origen</h2>
            <div className="red-chips" role="list">
              {ORIGENES.map((o) => <span key={o.codigo} role="listitem" aria-current={ficha.origen?.origen === o.codigo ? "true" : undefined} className={ficha.origen?.origen === o.codigo ? "red-opcion red-opcion-sel" : "red-opcion"}>{o.nombre}</span>)}
            </div>
            {ficha.origen.origen !== "emdupar" ? <Dato rotulo="Entregado por" v={ficha.origen.aportante_nombre ?? null} /> : null}
            <Dato rotulo="Soporte" v={ficha.origen.tiene_soporte ? "Tiene soporte cargado" : "Sin soporte todavía"} />
            {ficha.origen.nota ? <p className="red-nota">{ficha.origen.nota}</p> : null}
          </section>
        ) : null}

        {modelo.length > 0 ? (
          <details className="red-seccion red-plegable">
            <summary><h2>Datos del modelo hidráulico</h2><span className="red-cuenta">{modelo.length}</span></summary>
            <div className="red-rejilla">{modelo.map(([k, v]) => <Dato key={k} rotulo={k} v={valor(v)} />)}</div>
          </details>
        ) : null}

        <section className="red-seccion" aria-labelledby="red-t-comp">
          <div className="red-tit-fila"><h2 id="red-t-comp">Componentes</h2><span className="red-cuenta">{ficha.componentes.length}</span></div>
          {ficha.componentes.length > 0
            ? <div className="red-lista">{ficha.componentes.map((c) => <FilaActivo key={c.codigo} a={c} onAbrir={onAbrir} />)}</div>
            : <p className="red-texto red-sin-dato">{ficha.admite_componentes ? "Sin componentes registrados." : "Este tipo de activo no lleva componentes."}</p>}
          {ficha.parte_de.length > 0 ? (
            <>
              <h3 className="red-sub">Hace parte de</h3>
              <div className="red-lista">{ficha.parte_de.map((c) => <FilaActivo key={c.codigo} a={c} onAbrir={onAbrir} />)}</div>
            </>
          ) : null}
        </section>

        <section className="red-seccion" aria-labelledby="red-t-epi">
          <div>
            <h2 id="red-t-epi">Epicrisis del activo</h2>
            <span className="red-nota">Daños, fallas e intervenciones, en orden.</span>
          </div>
          {errorEpi ? <p className="tec-error-caja">{errorEpi}</p> : null}
          {!epi && !errorEpi ? <p className="tec-sub" role="status">Cargando…</p> : null}
          {epi && hechos.length === 0 ? <p className="red-vacio">Todavía no hay daños, fallas ni intervenciones registrados para este activo.</p> : null}
          {hechos.length > 0 ? <ol className="red-linea">{hechos.map((e) => <EventoItem key={`${e.clase}-${e.ref_id}`} e={e} />)}</ol> : null}
          {registro.length > 0 ? (
            <details className="red-registro">
              <summary>Cambios del registro ({epi?.siguiente ? `${registro.length}+` : registro.length})</summary>
              <ol className="red-linea">{registro.map((e) => <EventoItem key={`${e.clase}-${e.ref_id}`} e={e} />)}</ol>
              {epi?.siguiente ? <button type="button" className="tec-boton-sec" disabled={cargandoMas} onClick={masEpicrisis}>{cargandoMas ? "Cargando…" : "Ver más"}</button> : null}
            </details>
          ) : null}
        </section>

        <p className="red-nota red-pie">Versión {a.version} de la ficha · {fecha(a.version_creada_en)} · {a.lat.toFixed(5)}, {a.lon.toFixed(5)}</p>
      </div>
    </div>
  );
}

const ROTULO_CLASE: Record<string, string> = { dano: "Daño", falla: "Falla", intervencion: "Intervención", alta: "Alta", version: "Nueva versión", evento_retirar: "Retiro", evento_reactivar: "Reactivación", evento_ocultar: "Oculto", evento_reincluir: "Reincluido",
  evento_verificar: "Verificado", evento_por_verificar: "Por verificar", componente_agregar: "Componente agregado", componente_quitar: "Componente quitado",
  es_componente_agregar: "Pasa a ser componente", es_componente_quitar: "Deja de ser componente" };

function EventoItem({ e }: { e: EventoEpicrisis }) {
  return (
    <li className={`red-evento${e.estado === "revertida" ? " red-evento-revertido" : ""}${e.grupo === "hecho" ? ` red-evento-${e.clase}` : ""}`}>
      <span className="red-evento-punto" aria-hidden="true" />
      <div className="red-evento-txt">
        <span className="red-nota">{fecha(e.cuando)}{e.estado === "revertida" ? " · revertida" : e.grupo === "hecho" && e.estado ? ` · ${e.estado}` : ""}</span>
        <span className="red-evento-tit">{ROTULO_CLASE[e.clase] ?? e.clase}</span>
        <span className="red-texto">{e.resumen}</span>
        {e.autor ? <span className="red-nota">{e.autor}</span> : null}
      </div>
    </li>
  );
}
