import { useCallback, useEffect, useState } from "react";
import { apiRev, textoError, type CatalogosResp, type CodigoNombre, type Cuadrilla, type EventoPersonal, type ItemCatalogo, type PersonalResp } from "./apiRevision";
import { FilaEvento, puedeDe } from "./PersonalCampo";
import { fmtInstante } from "./formatoRevision";

// «Supervisión y dashboard» · Cuadrillas (21-nov, paquete (a) del Code A; decisión B1 de David). El supervisor de campo y el administrador crean cuadrillas, les dan actividades y las
// desactivan con motivo; quién está en cada cuadrilla se fija en Personal. Al final, «Áreas y actividades»: los catálogos, solo para el administrador. Nada se borra: se desactiva con
// motivo y queda en el historial. Qué puede cada quien lo dice el servidor (`puede` de la ruta personal).
type Dlg = { t: "renombrar" | "actividades" | "desactivar"; c: Cuadrilla } | { t: "crear" } | { t: "cat"; cat: "area" | "actividad"; tipo: "crear" | "renombrar" | "desactivar"; item?: ItemCatalogo };
const motivoMalo = (m: string) => m.trim().length < 10 || m.trim().length > 300;
const nombreMalo = (n: string) => n.trim().length < 2 || n.trim().length > 60;
const nMiembros = (c: Cuadrilla) => c.n_miembros ?? c.miembros.length;
const miembrosTxt = (n: number) => (n === 0 ? "Sin miembros" : n === 1 ? "1 miembro" : `${n} miembros`);

export function Cuadrillas() {
  const [per, setPer] = useState<PersonalResp | null>(null);
  const [lista, setLista] = useState<Cuadrilla[] | null>(null);
  const [inactivas, setInactivas] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const [dlg, setDlg] = useState<Dlg | null>(null);
  const [hist, setHist] = useState<number | null>(null);
  const [vez, setVez] = useState(0);
  useEffect(() => {
    let vivo = true; setError(null);
    Promise.all([apiRev.personal(""), apiRev.cuadrillas(inactivas)])
      .then(([p, c]) => { if (vivo) { setPer(p); setLista(c.cuadrillas); } })
      .catch((e) => { if (vivo) setError(textoError(e).texto); });
    return () => { vivo = false; };
  }, [inactivas, vez]);
  const puede = puedeDe(per);
  const hecho = (t: string) => { setDlg(null); setAviso(t); setVez((x) => x + 1); };
  const actividades: CodigoNombre[] = per?.actividades ?? [];

  return (
    <section className="rv-seccion" aria-labelledby="rv-cua-tit" data-testid="cuadrillas">
      <div>
        <h2 id="rv-cua-tit">Cuadrillas</h2>
        <p className="rv-sub">Cada cuadrilla tiene sus actividades; quien esté en ella las hace, además de sus actividades propias. Las personas se ponen en una cuadrilla desde Personal. Por ahora las actividades solo se registran: no bloquean la captura.</p>
      </div>
      <div className="rv-per-cajitas">
        {puede.cuadrillas ? <div className="rv-per-cajita"><strong>Usted puede:</strong> crear y renombrar cuadrillas, darles actividades y desactivarlas con motivo. Una cuadrilla con miembros no se desactiva: primero se sacan en Personal.</div>
          : per ? <div className="rv-per-cajita"><strong>Solo lectura.</strong> Usted ve las cuadrillas, sus miembros, sus actividades y su historial.</div> : null}
      </div>
      <div className="rv-botones">
        {puede.cuadrillas ? <button type="button" className="rv-boton" data-testid="cua-crear" onClick={() => { setAviso(null); setDlg({ t: "crear" }); }}>Crear cuadrilla</button> : null}
        <label className="rv-check"><input type="checkbox" checked={inactivas} onChange={(e) => setInactivas(e.target.checked)} /> Mostrar las desactivadas</label>
      </div>
      {aviso ? <div className="rv-aviso rv-aviso-ok" role="status">{aviso}</div> : null}
      {error ? <div className="rv-aviso rv-aviso-error" role="alert">{error} <button type="button" className="rv-enlace" onClick={() => setVez((x) => x + 1)}>Reintentar</button></div> : null}
      {!lista && !error ? <p className="rv-sub" role="status">Cargando las cuadrillas…</p> : null}
      {lista && lista.length === 0 ? <div className="rv-vacio">{inactivas ? "No hay cuadrillas." : "No hay cuadrillas activas."}{puede.cuadrillas ? " Cree la primera con «Crear cuadrilla»." : ""}</div> : null}
      <ul className="rv-per-lista">
        {(lista ?? []).map((c) => (
          <li key={c.id} className={`rv-per-tarjeta${c.activa ? "" : " rv-inactivo"}`} data-cuadrilla={c.id}>
            <div className="rv-per-cab">
              <div><strong>{c.nombre}</strong><div className="rv-tenue">Creada {fmtInstante(c.creada_en)} · por {c.autor}</div></div>
              {c.activa ? <span className="rv-marca rv-marca-info">{miembrosTxt(nMiembros(c))}</span> : <span className="rv-marca rv-marca-gris">Desactivada</span>}
            </div>
            <dl className="rv-per-dl">
              <dt>Actividades</dt>
              <dd data-dato="actividades">{c.actividades.length === 0 ? <span className="rv-tenue">Ninguna</span> : <span className="rv-per-chips">{c.actividades.map((a) => <span key={a.codigo} className="rv-per-chip" data-actividad={a.codigo}>{a.nombre}</span>)}</span>}</dd>
              <dt>Miembros</dt>
              <dd data-dato="miembros">{c.miembros.length === 0 ? <span className="rv-tenue">Nadie todavía</span> : c.miembros.map((m) => m.nombre ?? m.email.split("@")[0]).join(", ")}</dd>
            </dl>
            <div className="rv-botones">
              {puede.cuadrillas && c.activa ? <>
                <button type="button" className="rv-boton-sec" onClick={() => { setAviso(null); setDlg({ t: "actividades", c }); }}>Actividades</button>
                <button type="button" className="rv-boton-sec" onClick={() => { setAviso(null); setDlg({ t: "renombrar", c }); }}>Renombrar</button>
                <button type="button" className="rv-boton-sec" onClick={() => { setAviso(null); setDlg({ t: "desactivar", c }); }}>Desactivar</button></> : null}
              {puede.cuadrillas && !c.activa ? <BotonAccion texto="Volver a activar" onHecho={hecho} hacer={() => apiRev.cuadrillaCambiar({ tipo: "activar", cuadrilla_id: c.id }).then(() => `La cuadrilla «${c.nombre}» quedó activa.`)} /> : null}
              <button type="button" className="rv-enlace" aria-expanded={hist === c.id} onClick={() => setHist(hist === c.id ? null : c.id)}>{hist === c.id ? "Ocultar el historial" : "Ver su historial"}</button>
            </div>
            {hist === c.id ? <HistorialCuadrilla id={c.id} version={vez} /> : null}
          </li>
        ))}
      </ul>
      {puede.catalogos ? <Catalogos vez={vez} onCambio={hecho} onDlg={(d) => { setAviso(null); setDlg(d); }} /> : null}
      {dlg?.t === "crear" ? <DlgNombre titulo="Crear cuadrilla" inicial="" boton="Crear" onCancelar={() => setDlg(null)}
        enviar={(n) => apiRev.cuadrillaCambiar({ tipo: "crear", nombre: n }).then(() => hecho(`Cuadrilla «${n}» creada. Póngale actividades y, en Personal, sus miembros.`))} /> : null}
      {dlg?.t === "renombrar" ? <DlgNombre titulo={`Renombrar «${dlg.c.nombre}»`} inicial={dlg.c.nombre} boton="Renombrar" onCancelar={() => setDlg(null)}
        enviar={(n) => apiRev.cuadrillaCambiar({ tipo: "renombrar", cuadrilla_id: dlg.c.id, nombre: n }).then(() => hecho(`La cuadrilla ahora se llama «${n}».`))} /> : null}
      {dlg?.t === "desactivar" ? <DlgDesactivar c={dlg.c} onCancelar={() => setDlg(null)} onHecho={hecho} /> : null}
      {dlg?.t === "actividades" ? <DlgActividades c={dlg.c} catalogo={actividades} onCancelar={() => setDlg(null)} onHecho={hecho} /> : null}
      {dlg?.t === "cat" ? <DlgCatalogo d={dlg} onCancelar={() => setDlg(null)} onHecho={hecho} /> : null}
    </section>
  );
}

function BotonAccion({ texto, hacer, onHecho }: { texto: string; hacer: () => Promise<string>; onHecho: (t: string) => void }) {
  const [enviando, setEnviando] = useState(false); const [error, setError] = useState<string | null>(null);
  return <>
    <button type="button" className="rv-boton-sec" disabled={enviando} onClick={() => { setEnviando(true); setError(null); hacer().then(onHecho).catch((e) => { setError(textoError(e).texto); setEnviando(false); }); }}>{enviando ? "Guardando…" : texto}</button>
    {error ? <span className="rv-error" role="alert">{error}</span> : null}
  </>;
}

function Modal({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return <div className="rv-modal-fondo"><div className="rv-modal" role="dialog" aria-modal="true" aria-label={titulo}><h3>{titulo}</h3>{children}</div></div>;
}

function DlgNombre({ titulo, inicial, boton, enviar, onCancelar }: { titulo: string; inicial: string; boton: string; enviar: (n: string) => Promise<void>; onCancelar: () => void }) {
  const [n, setN] = useState(inicial); const [enviando, setEnviando] = useState(false); const [error, setError] = useState<string | null>(null);
  const malo = nombreMalo(n) || n.trim() === inicial.trim();
  return (
    <Modal titulo={titulo}>
      <label className="rv-campo">Nombre (de 2 a 60 caracteres)<input type="text" value={n} maxLength={60} onChange={(e) => setN(e.target.value)} data-campo="nombre" /></label>
      {error ? <p className="rv-error" role="alert">{error}</p> : null}
      <div className="rv-botones">
        <button type="button" className="rv-boton" disabled={enviando || malo} onClick={() => { setEnviando(true); setError(null); enviar(n.trim()).catch((e) => { setError(textoError(e).texto); setEnviando(false); }); }}>{enviando ? "Guardando…" : boton}</button>
        <button type="button" className="rv-boton-sec" disabled={enviando} onClick={onCancelar}>Cancelar</button>
      </div>
    </Modal>
  );
}

function DlgDesactivar({ c, onCancelar, onHecho }: { c: Cuadrilla; onCancelar: () => void; onHecho: (t: string) => void }) {
  const [m, setM] = useState(""); const [enviando, setEnviando] = useState(false); const [error, setError] = useState<string | null>(null);
  const n = nMiembros(c);
  return (
    <Modal titulo={`Desactivar «${c.nombre}»`}>
      {n > 0 ? <p className="rv-aviso rv-aviso-error" role="note">La cuadrilla tiene {miembrosTxt(n).toLowerCase()}: {n === 1 ? "sáquelo" : "sáquelos"} en Personal antes de desactivarla.</p>
        : <p className="rv-sub">La cuadrilla deja de ofrecerse en Personal. No se borra: queda en el historial y se puede volver a activar.</p>}
      <label className="rv-campo">Motivo (de 10 a 300 caracteres)<textarea rows={2} maxLength={300} value={m} onChange={(e) => setM(e.target.value)} /></label>
      {error ? <p className="rv-error" role="alert">{error}</p> : null}
      <div className="rv-botones">
        <button type="button" className="rv-boton" disabled={enviando || motivoMalo(m)} onClick={() => { setEnviando(true); setError(null);
          apiRev.cuadrillaCambiar({ tipo: "desactivar", cuadrilla_id: c.id, motivo: m.trim() }).then(() => onHecho(`La cuadrilla «${c.nombre}» quedó desactivada.`)).catch((e) => { setError(textoError(e).texto); setEnviando(false); }); }}>{enviando ? "Guardando…" : "Desactivar"}</button>
        <button type="button" className="rv-boton-sec" disabled={enviando} onClick={onCancelar}>Cancelar</button>
      </div>
    </Modal>
  );
}

function DlgActividades({ c, catalogo, onCancelar, onHecho }: { c: Cuadrilla; catalogo: CodigoNombre[]; onCancelar: () => void; onHecho: (t: string) => void }) {
  const antes = c.actividades.map((a) => a.codigo);
  const [sel, setSel] = useState<Set<string>>(new Set(antes));
  const [m, setM] = useState(""); const [enviando, setEnviando] = useState(false); const [error, setError] = useState<string | null>(null);
  const agregar = [...sel].filter((a) => !antes.includes(a)), quitar = antes.filter((a) => !sel.has(a));
  // Las activas del catálogo, más las que ya tiene la cuadrilla aunque se hayan desactivado (solo para poder quitarlas)
  const opciones = [...catalogo.map((a) => ({ ...a, activa: true })), ...c.actividades.filter((a) => !catalogo.some((x) => x.codigo === a.codigo)).map((a) => ({ ...a, activa: false }))];
  const malo = (agregar.length === 0 && quitar.length === 0) || (quitar.length > 0 && motivoMalo(m));
  async function guardar() {
    setEnviando(true); setError(null); let hechos = 0;
    try {
      for (const a of agregar) { await apiRev.cuadrillaCambiar({ tipo: "agregar_actividad", cuadrilla_id: c.id, actividad: a }); hechos++; }
      for (const a of quitar) { await apiRev.cuadrillaCambiar({ tipo: "quitar_actividad", cuadrilla_id: c.id, actividad: a, motivo: m.trim() }); hechos++; }
      onHecho(`Actividades de «${c.nombre}» guardadas (${hechos} cambio${hechos === 1 ? "" : "s"}).`);
    } catch (e) { setError(`${textoError(e).texto}${hechos ? ` Se alcanzaron a guardar ${hechos} cambio(s); revise el historial.` : ""}`); setEnviando(false); }
  }
  return (
    <Modal titulo={`Actividades de «${c.nombre}»`}>
      <p className="rv-sub">Quien esté en la cuadrilla hace estas actividades, además de las propias.</p>
      <fieldset className="rv-per-forms" data-campo="actividades">
        <legend>Actividades de la cuadrilla</legend>
        {opciones.map((a) => <label key={a.codigo} className="rv-check"><input type="checkbox" data-actividad={a.codigo} checked={sel.has(a.codigo)} disabled={!a.activa && !sel.has(a.codigo)}
          onChange={() => setSel((s) => { const n = new Set(s); if (n.has(a.codigo)) n.delete(a.codigo); else n.add(a.codigo); return n; })} /> {a.nombre}{a.activa ? null : <span className="rv-per-desact"> (desactivada)</span>}</label>)}
      </fieldset>
      {quitar.length ? <label className="rv-campo">Motivo para quitar {quitar.length === 1 ? "la actividad" : `${quitar.length} actividades`} (de 10 a 300 caracteres)<textarea rows={2} maxLength={300} value={m} onChange={(e) => setM(e.target.value)} /></label> : null}
      {error ? <p className="rv-error" role="alert">{error}</p> : null}
      <div className="rv-botones">
        <button type="button" className="rv-boton" disabled={enviando || malo} onClick={() => void guardar()}>{enviando ? "Guardando…" : "Guardar"}</button>
        <button type="button" className="rv-boton-sec" disabled={enviando} onClick={onCancelar}>Cancelar</button>
      </div>
    </Modal>
  );
}

function HistorialCuadrilla({ id, version }: { id: number; version: number }) {
  const [ev, setEv] = useState<EventoPersonal[] | null>(null); const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let vivo = true; setEv(null); setError(null);
    apiRev.historialPersonal({ cuadrilla_id: id, limite: 50 }).then((r) => { if (vivo) setEv(r.eventos); }).catch((e) => { if (vivo) setError(textoError(e).texto); });
    return () => { vivo = false; };
  }, [id, version]);
  return (
    <div className="rv-per-hist" data-testid="cua-historial">
      {error ? <div className="rv-aviso rv-aviso-error" role="alert">{error}</div> : null}
      {!ev && !error ? <p className="rv-sub" role="status">Cargando el historial…</p> : null}
      {ev && ev.length === 0 ? <div className="rv-vacio">Sin cambios registrados.</div> : null}
      <ol className="rv-per-eventos">{(ev ?? []).map((e) => <FilaEvento key={e.clave ?? e.id} e={e} />)}</ol>
    </div>
  );
}

/** «Áreas y actividades»: los dos catálogos, con los desactivados. Solo el administrador (puede.catalogos). */
function Catalogos({ vez, onDlg, onCambio }: { vez: number; onDlg: (d: Dlg) => void; onCambio: (t: string) => void }) {
  const [cat, setCat] = useState<CatalogosResp | null>(null); const [error, setError] = useState<string | null>(null);
  const cargar = useCallback(() => { setError(null); apiRev.catalogos().then(setCat).catch((e) => setError(textoError(e).texto)); }, []);
  useEffect(() => { cargar(); }, [cargar, vez]);
  const bloque = (tipo: "area" | "actividad", titulo: string, items: ItemCatalogo[]) => (
    <div className="rv-per-grupo" data-catalogo={tipo}>
      <div className="rv-fila-cat"><h3 className="rv-h3">{titulo}</h3><button type="button" className="rv-boton-sec" onClick={() => onDlg({ t: "cat", cat: tipo, tipo: "crear" })}>{tipo === "area" ? "Agregar área" : "Agregar actividad"}</button></div>
      <ul className="rv-cat-lista">
        {items.map((i) => (
          <li key={i.codigo} className={`rv-cat-item${i.activa ? "" : " rv-inactivo"}`} data-codigo={i.codigo}>
            <span><strong>{i.nombre}</strong> <small className="rv-tenue">{i.codigo}</small>{i.activa ? null : <span className="rv-marca rv-marca-gris">Desactivada</span>}</span>
            <span className="rv-cat-acc">
              {i.activa ? <>
                <button type="button" className="rv-enlace" onClick={() => onDlg({ t: "cat", cat: tipo, tipo: "renombrar", item: i })}>Renombrar</button>
                <button type="button" className="rv-enlace" onClick={() => onDlg({ t: "cat", cat: tipo, tipo: "desactivar", item: i })}>Desactivar</button></>
                : <BotonAccion texto="Volver a activar" onHecho={onCambio} hacer={() => apiRev.catalogoCambiar({ catalogo: tipo, tipo: "activar", codigo: i.codigo }).then(() => `«${i.nombre}» quedó activa.`)} />}
            </span>
          </li>))}
      </ul>
    </div>
  );
  return (
    <div className="rv-per-hist" data-testid="catalogos">
      <h2 className="rv-h3">Áreas y actividades</h2>
      <p className="rv-sub">Solo el administrador. Lo desactivado deja de ofrecerse para asignar, pero quien ya lo tiene lo conserva (se ve como «desactivada»).</p>
      {error ? <div className="rv-aviso rv-aviso-error" role="alert">{error} <button type="button" className="rv-enlace" onClick={cargar}>Reintentar</button></div> : null}
      {!cat && !error ? <p className="rv-sub" role="status">Cargando…</p> : null}
      {cat ? <>{bloque("area", "Áreas", cat.areas)}{bloque("actividad", "Actividades", cat.actividades)}</> : null}
    </div>
  );
}

function DlgCatalogo({ d, onCancelar, onHecho }: { d: Extract<Dlg, { t: "cat" }>; onCancelar: () => void; onHecho: (t: string) => void }) {
  const que = d.cat === "area" ? "el área" : "la actividad";
  if (d.tipo === "desactivar" && d.item) {
    const it = d.item;
    return <DlgMotivo titulo={`Desactivar ${que} «${it.nombre}»`} nota="Deja de ofrecerse para asignar; quien ya la tiene la conserva. Se puede volver a activar." boton="Desactivar" onCancelar={onCancelar}
      enviar={(m) => apiRev.catalogoCambiar({ catalogo: d.cat, tipo: "desactivar", codigo: it.codigo, motivo: m }).then(() => onHecho(`«${it.nombre}» quedó desactivada.`))} />;
  }
  if (d.tipo === "renombrar" && d.item) {
    const it = d.item;
    return <DlgNombre titulo={`Renombrar ${que} «${it.nombre}»`} inicial={it.nombre} boton="Renombrar" onCancelar={onCancelar}
      enviar={(n) => apiRev.catalogoCambiar({ catalogo: d.cat, tipo: "renombrar", codigo: it.codigo, nombre: n }).then(() => onHecho(`Ahora se llama «${n}».`))} />;
  }
  return <DlgNombre titulo={d.cat === "area" ? "Agregar área" : "Agregar actividad"} inicial="" boton="Agregar" onCancelar={onCancelar}
    enviar={(n) => apiRev.catalogoCambiar({ catalogo: d.cat, tipo: "crear", nombre: n }).then((r) => onHecho(`«${n}» agregada${r.codigo ? ` (código ${r.codigo})` : ""}.`))} />;
}

function DlgMotivo({ titulo, nota, boton, enviar, onCancelar }: { titulo: string; nota: string; boton: string; enviar: (m: string) => Promise<void>; onCancelar: () => void }) {
  const [m, setM] = useState(""); const [enviando, setEnviando] = useState(false); const [error, setError] = useState<string | null>(null);
  return (
    <Modal titulo={titulo}>
      <p className="rv-sub">{nota}</p>
      <label className="rv-campo">Motivo (de 10 a 300 caracteres)<textarea rows={2} maxLength={300} value={m} onChange={(e) => setM(e.target.value)} /></label>
      {error ? <p className="rv-error" role="alert">{error}</p> : null}
      <div className="rv-botones">
        <button type="button" className="rv-boton" disabled={enviando || motivoMalo(m)} onClick={() => { setEnviando(true); setError(null); enviar(m.trim()).catch((e) => { setError(textoError(e).texto); setEnviando(false); }); }}>{enviando ? "Guardando…" : boton}</button>
        <button type="button" className="rv-boton-sec" disabled={enviando} onClick={onCancelar}>Cancelar</button>
      </div>
    </Modal>
  );
}
