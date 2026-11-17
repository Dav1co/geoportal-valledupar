import { lazy, Suspense, useEffect, useState } from "react";
import { apiPerfil, apiRedes, type ActivoCorto, type Epicrisis, type EventoEpicrisis, type Ficha, type FotoFirmada, type Galeria, type Perfil, type Regulatorio } from "./apiRedes";
import { FichaEditar, FotoPerfilCambiar } from "./FichaEditar";

// Corte 3b: la ficha como «perfil» del activo (§22 y §23): minimapa estático arriba, alias propio y placa, foto principal, galería (supervisor y
// administrador; la lectura queda auditada) y la epicrisis como muro (daños, intervenciones y cambios de la ficha). Editar la ficha y su foto, por ahora
// solo el administrador (el servidor lo decide y manda «editable»).
const MiniMapaEstatico = lazy(() => import("./MiniMapaEstatico").then((m) => ({ default: m.MiniMapaEstatico })));
const ORIGEN_FOTO: Record<string, string> = { perfil: "Foto de perfil", dano: "Daño", intervencion: "Intervención" };
const CLASE_FOTO: Record<string, string> = { dano: "el daño", entorno: "entorno", reparado: "reparado", antes: "antes", durante: "durante", despues: "después", perfil: "" };
const pieFoto = (f: FotoFirmada) => [ORIGEN_FOTO[f.origen], f.codigo, CLASE_FOTO[f.clase ?? ""] || null].filter(Boolean).join(" · ");
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

// Corte 10. «Inventario regulatorio»: la fila de la Valoración Técnica 2019 a la que está amarrado el activo. Solo llega a supervisor y administrador (lo decide
// el servidor). Los valores son de TODA la fila (activos agregados): no se reparten por tramo. Es una propuesta de 2019: se dice en el encabezado.
const pesos = new Intl.NumberFormat("es-CO", { style: "currency", currency: "COP", maximumFractionDigits: 0 });
const UNIDAD_REG: Record<string, string> = { m: "m", un: "unidades", "L/s": "L/s", "m³": "m³" };
function InventarioRegulatorio({ r }: { r: Regulatorio }) {
  return (
    <section className="red-seccion red-referencia" aria-labelledby="red-t-reg" data-testid="ficha-regulatorio">
      <h2 id="red-t-reg">Inventario regulatorio</h2>
      <p className="red-nota">{r.fuente}. Dato de referencia: no hace parte de la ficha oficial del activo y no la cambia.</p>
      <div className="red-rejilla">
        <Dato rotulo="Remunerado vía tarifa" v={r.remunerado ? "Sí" : "No"} />
        {r.filas?.length ? <Dato rotulo={r.filas.length === 1 ? "Fila de la valoración" : "Filas de la valoración"} v={r.filas.map((f) => `${f.n}`).join(" y ")} /> : null}
      </div>
      {r.texto ? <p className="red-texto">{r.texto}</p> : null}
      {!r.filas && r.nota ? <p className="red-nota">{r.nota}</p> : null}
      {(r.filas ?? []).map((f) => (
        <div key={`${f.hoja}-${f.n}`} className="red-ref-grupo">
          <h3 className="red-sub">Fila {f.n} · {f.nombre}{f.clase === "tuberia" || f.clase === "valvula" ? (f.diametro_pulg ? ` de ${nf.format(f.diametro_pulg)} pulgadas` : "") : ""}</h3>
          <div className="red-rejilla">
            <Dato rotulo="Hoja" v={f.hoja} />
            <Dato rotulo="En la fila" v={`${f.cantidad === undefined ? "Sin cantidad" : `${nf.format(f.cantidad)} ${UNIDAD_REG[f.unidad ?? ""] ?? ""}`.trim()} · ${nf.format(f.activos)} ${f.activos === 1 ? "activo amarrado" : "activos amarrados"}`} />
            <Dato rotulo="Entrada en operación (regulatoria)" v={f.fecha_operacion ? fechaDia(f.fecha_operacion) : null} />
            <Dato rotulo="Vida útil" v={f.vida_util === undefined ? null : `${nf.format(f.vida_util)} años`} />
            <Dato rotulo="Vida útil remanente a hoy" v={f.vida_remanente_hoy === undefined ? null : `${nf.format(f.vida_remanente_hoy)} años${f.fin_vida_util ? ` (hasta ${fechaDia(f.fin_vida_util)})` : ""}`} />
            <Dato rotulo="Valor de la fila" v={f.valor_total === undefined ? null : pesos.format(f.valor_total)} />
            <Dato rotulo="Valor remanente de la fila (al iniciar la tarifa)" v={f.valor_remanente === undefined ? null : pesos.format(f.valor_remanente)} />
            <Dato rotulo="Depreciación anual de la fila" v={f.depreciacion_anual === undefined ? null : pesos.format(f.depreciacion_anual)} />
          </div>
          {f.nota ? <p className="red-nota">{f.nota}.</p> : null}
        </div>))}
      {r.filas?.length ? <p className="red-nota">El valor y la depreciación son de toda la fila (activos agregados): no se reparten por activo. La fecha es la de entrada en operación regulatoria, no la de instalación.</p> : null}
    </section>
  );
}

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
  const [perfil, setPerfil] = useState<Perfil | null>(null);
  const [modo, setModo] = useState<"ver" | "editar" | "foto">("ver");
  const [aviso, setAviso] = useState<string | null>(null);
  const [galeria, setGaleria] = useState<Galeria | null>(null);
  const [errorGal, setErrorGal] = useState<string | null>(null);
  const [cargandoGal, setCargandoGal] = useState(false);
  const [grande, setGrande] = useState<FotoFirmada | null>(null);

  useEffect(() => {
    let vivo = true;
    setFicha(null); setError(null); setEpi(null); setErrorEpi(null);
    apiRedes.activo(codigo)
      .then((f) => { if (vivo) setFicha(f); })
      .catch((e) => { if (vivo) setError(e instanceof ErrorTec ? e : new ErrorTec("servidor", "No se pudo cargar la ficha.", 0)); });
    setPerfil(null); setGaleria(null); setErrorGal(null);
    apiPerfil.perfil(codigo).then((p) => { if (vivo) setPerfil(p); }).catch(() => {});      // sin perfil, la ficha se ve igual (como en el 1b)
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
  // el muro (§22): daños, fallas, intervenciones y cambios de la ficha; lo demás del registro (alta, versiones de carga, retiros, componentes) va plegado
  const enMuro = (e: EventoEpicrisis) => e.grupo === "hecho" || e.clase === "ficha";
  const hechos = (epi?.items ?? []).filter(enMuro);
  const registro = (epi?.items ?? []).filter((e) => !enMuro(e));
  const verGaleria = () => {
    setCargandoGal(true); setErrorGal(null);
    apiPerfil.galeria(codigo).then(setGaleria).catch((e) => setErrorGal(e instanceof Error ? e.message : "No se pudo cargar la galería.")).finally(() => setCargandoGal(false));
  };
  const listo = (msg: string) => { setModo("ver"); setAviso(msg); setIntento((i) => i + 1); window.scrollTo?.(0, 0); };
  const modelo = ficha.modelo ? Object.entries(ficha.modelo).filter(([, v]) => v !== null && v !== "") : [];

  return (
    <div className="red-ficha">
      <header className="red-cabeza">
        {volver}
        <span className="red-ceja">{a.sistema_nombre} · {ETAPAS[a.etapa] ?? a.etapa}</span>
        <h1 className="red-codigo">{a.codigo}</h1>
        {perfil?.alias ? <span className="red-alias">{perfil.alias}</span> : null}
        <span className="red-tipo">{a.tipo}{a.clase ? ` · ${a.clase}` : ""}{a.nombre ? ` · ${a.nombre}` : ""}</span>
        <div className="red-chips">
          <span className={`red-chip ${tonoEstado(a)}`}>{a.retirado ? "Retirado" : a.estado}</span>
          {a.codigo_anterior ? <span className="red-chip red-chip-suave">Código anterior: {a.codigo_anterior}</span> : null}
          {a.por_verificar ? <span className="red-chip red-chip-suave">Por verificar</span> : null}
          {perfil && !perfil.editable ? <span className="red-chip red-chip-suave" data-solo-lectura>Solo lectura</span> : null}
          {ficha.sector_hidraulico ? <span className="red-chip red-chip-suave">Sector {ficha.sector_hidraulico.sector}{ficha.sector_hidraulico.subsector ? ` · ${ficha.sector_hidraulico.subsector}` : ""}</span> : null}
          {perfil?.placa ? <span className="red-chip red-chip-placa">Placa: {perfil.placa}</span> : null}
        </div>
        {perfil?.editable && modo === "ver" ? (
          <div className="red-acciones-edicion">
            <button type="button" className="tec-boton-sec" onClick={() => { setAviso(null); setModo("editar"); }}>Editar ficha</button>
            <button type="button" className="tec-boton-sec" onClick={() => { setAviso(null); setModo("foto"); }}>Cambiar foto principal</button>
          </div>
        ) : null}
        {onRegistrarIntervencion && !a.retirado && (a.sistema === "acueducto" || a.sistema === "alcantarillado") ? (
          <button type="button" className="tec-boton red-accion" onClick={() => onRegistrarIntervencion({ codigo: a.codigo, sistema: a.sistema as "acueducto" | "alcantarillado", lat: a.lat, lon: a.lon })}>Registrar intervención</button>
        ) : null}
      </header>

      {(a.sistema === "acueducto" || a.sistema === "alcantarillado") || perfil?.foto_principal ? (
        <div className="red-portada">
          {a.sistema === "acueducto" || a.sistema === "alcantarillado" ? (
            <Suspense fallback={<div className="red-minimapa red-minimapa-cargando" role="status">Cargando el mapa…</div>}>
              <MiniMapaEstatico sistema={a.sistema} codigo={a.codigo} lat={a.lat} lon={a.lon} />
            </Suspense>) : null}
          {perfil?.foto_principal ? (
            <figure className="red-foto-principal">
              <button type="button" onClick={() => setGrande(perfil.foto_principal!)} aria-label="Ver la foto principal en grande">
                <img src={perfil.foto_principal.url} alt={`Foto principal de ${a.codigo}`} />
              </button>
              <figcaption>{pieFoto(perfil.foto_principal)} · {fecha(perfil.foto_principal.cuando)}</figcaption>
            </figure>) : null}
        </div>) : null}

      <div className="red-cuerpo">
        {aviso ? <p className="tec-aviso tec-aviso-info red-aviso" role="status">{aviso}</p> : null}
        {modo === "editar" && perfil?.edicion ? <FichaEditar codigo={a.codigo} edicion={perfil.edicion} onCancelar={() => setModo("ver")} onGuardado={listo} /> : null}
        {modo === "foto" && perfil?.edicion ? <FotoPerfilCambiar codigo={a.codigo} maxBytes={perfil.edicion.max_bytes_foto} onCancelar={() => setModo("ver")} onGuardado={listo} /> : null}
        {a.retirado ? <p className="tec-aviso tec-aviso-error red-aviso">Este activo está retirado: no vino en la última carga de su capa. Su hoja de vida se conserva.</p> : null}
        {a.por_verificar && ficha.por_verificar_motivo ? <p className="tec-aviso tec-aviso-info red-aviso" data-por-verificar>Por verificar en campo. {ficha.por_verificar_motivo}</p> : null}
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
            {a.prefijo !== "SEC" ? <Dato rotulo="Sector hidráulico (por su ubicación)" v={ficha.sector_hidraulico ? `Sector ${ficha.sector_hidraulico.sector}${ficha.sector_hidraulico.subsector ? ` · subsector ${ficha.sector_hidraulico.subsector}` : ""}` : "Fuera de los sectores"} /> : null}
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

        {(ficha.referencia ?? []).length > 0 ? (
          <section className="red-seccion red-referencia" aria-labelledby="red-t-ref">
            <h2 id="red-t-ref">Referencia del Plan Maestro 2014</h2>
            <p className="red-nota">Datos de referencia. No hacen parte de la ficha oficial del activo y no la cambian.</p>
            {ficha.referencia!.map((g) => (
              <div key={g.titulo} className="red-ref-grupo">
                <h3 className="red-sub">{g.titulo}</h3>
                {g.advertencia ? <p className="red-ref-adv" role="note">{g.advertencia}</p> : null}
                <div className="red-rejilla">{g.filas.map((f) => <Dato key={f.r} rotulo={f.r} v={`${typeof f.v === "number" ? nf.format(f.v) : f.v}${f.u ? ` ${f.u}` : ""}`} />)}</div>
              </div>))}
            {ficha.referencia![0].origen ? <p className="red-nota">Origen: {ficha.referencia![0].origen}.</p> : null}
          </section>
        ) : null}

        {ficha.regulatorio ? <InventarioRegulatorio r={ficha.regulatorio} /> : null}

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

        {perfil?.fotos !== undefined ? (
          <section className="red-seccion" aria-labelledby="red-t-gal">
            <div className="red-tit-fila"><h2 id="red-t-gal">Galería</h2><span className="red-cuenta">{perfil.fotos}</span></div>
            {perfil.fotos === 0 ? <p className="red-texto red-sin-dato">Todavía no hay fotos de daños, intervenciones ni de perfil.</p>
              : !galeria ? <button type="button" className="tec-boton-sec" disabled={cargandoGal} onClick={verGaleria}>{cargandoGal ? "Cargando…" : `Ver las fotos (${perfil.fotos})`}</button> : null}
            {errorGal ? <p className="tec-error-caja">{errorGal}</p> : null}
            {galeria ? (
              <>
                <div className="red-galeria">{galeria.fotos.map((f) => (
                  <figure key={f.url} className="red-gal-foto">
                    <button type="button" onClick={() => setGrande(f)} aria-label={`Ver en grande: ${pieFoto(f)}`}><img src={f.url} alt={pieFoto(f)} loading="lazy" /></button>
                    <figcaption>{pieFoto(f)}<br />{fecha(f.cuando)}</figcaption>
                  </figure>))}</div>
                <p className="red-nota">Los enlaces de las fotos vencen al minuto. {galeria.total > galeria.fotos.length ? `Se muestran las ${galeria.fotos.length} más recientes de ${galeria.total}.` : ""}</p>
              </>) : null}
          </section>
        ) : null}

        <section className="red-seccion" aria-labelledby="red-t-epi">
          <div>
            <h2 id="red-t-epi">Epicrisis del activo</h2>
            <span className="red-nota">El muro del activo: daños, fallas, intervenciones y cambios de la ficha, del más reciente al más antiguo.</span>
          </div>
          {errorEpi ? <p className="tec-error-caja">{errorEpi}</p> : null}
          {!epi && !errorEpi ? <p className="tec-sub" role="status">Cargando…</p> : null}
          {epi && hechos.length === 0 ? <p className="red-vacio">Todavía no hay daños, fallas, intervenciones ni cambios de la ficha para este activo.</p> : null}
          {hechos.length > 0 ? <ol className="red-linea">{hechos.map((e) => <EventoItem key={`${e.clase}-${e.ref_id}`} e={e} />)}</ol> : null}
          {registro.length > 0 ? (
            <details className="red-registro">
              <summary>Cambios del registro ({epi?.siguiente ? `${registro.length}+` : registro.length})</summary>
              <ol className="red-linea">{registro.map((e) => <EventoItem key={`${e.clase}-${e.ref_id}`} e={e} />)}</ol>
              {epi?.siguiente ? <button type="button" className="tec-boton-sec" disabled={cargandoMas} onClick={masEpicrisis}>{cargandoMas ? "Cargando…" : "Ver más"}</button> : null}
            </details>
          ) : null}
        </section>

        {grande ? (
          <div className="red-visor" role="dialog" aria-modal="true" aria-label={pieFoto(grande)} onClick={() => setGrande(null)}>
            <img src={grande.url} alt={pieFoto(grande)} />
            <p>{pieFoto(grande)} · {fecha(grande.cuando)}</p>
            <button type="button" className="tec-boton" onClick={() => setGrande(null)}>Cerrar</button>
          </div>) : null}
        <p className="red-nota red-pie">Versión {a.version} de la ficha · {fecha(a.version_creada_en)} · {a.lat.toFixed(5)}, {a.lon.toFixed(5)}</p>
      </div>
    </div>
  );
}

const ROTULO_CLASE: Record<string, string> = { dano: "Daño", falla: "Falla", intervencion: "Intervención", ficha: "Cambio de la ficha", alta: "Alta", version: "Nueva versión", evento_retirar: "Retiro", evento_reactivar: "Reactivación", evento_ocultar: "Oculto", evento_reincluir: "Reincluido",
  evento_verificar: "Verificado", evento_por_verificar: "Por verificar", componente_agregar: "Componente agregado", componente_quitar: "Componente quitado",
  es_componente_agregar: "Pasa a ser componente", es_componente_quitar: "Deja de ser componente" };

function EventoItem({ e }: { e: EventoEpicrisis }) {
  return (
    <li className={`red-evento${e.estado === "revertida" ? " red-evento-revertido" : ""}${e.grupo === "hecho" || e.clase === "ficha" ? ` red-evento-${e.clase}` : ""}`}>
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
