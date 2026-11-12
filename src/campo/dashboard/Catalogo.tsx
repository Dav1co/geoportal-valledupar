import { useCallback, useEffect, useState } from "react";
import { apiRev, textoError, type FormularioRev, type GrupoCat } from "./apiRevision";

// Gestión del catálogo (solo administrador): grupos, tipos, subtipos y estados por la ruta «catalogo». Crear, renombrar, reordenar, desactivar y reactivar; NUNCA borrar. Se muestran los
// inactivos con su marca y, antes de confirmar, el efecto del cambio. Cada cambio queda auditado en el servidor con el antes y el después. Los campos propios de cada formato se ven
// (solo lectura) como número; su edición es del Paso D.
type Fila = { entidad: "grupo" | "tipo" | "subtipo" | "estado"; codigo: string; nombre: string; orden: number; activo: boolean; padre?: string; protegido?: boolean; extra?: string };
type Dialogo = { modo: "renombrar" | "reordenar" | "activar" | "desactivar" | "crear"; fila?: Fila; entidad?: Fila["entidad"]; padre?: string };
const CODIGO = /^[a-z][a-z0-9_]{1,59}$/;
const EFECTO: Record<string, (f: Fila) => string> = {
  desactivar: (f) => f.entidad === "grupo" ? "El grupo y sus tipos desaparecerán del formulario de captura; los reportes existentes se conservan."
    : f.entidad === "tipo" ? "Este tipo desaparecerá del formulario de captura; los reportes existentes se conservan y se siguen viendo aquí."
    : f.entidad === "subtipo" ? "Este subtipo dejará de ofrecerse al reportar; los reportes que ya lo tienen lo conservan."
    : "Este estado dejará de ofrecerse para cambiar; los reportes que ya lo tienen lo conservan.",
  activar: (f) => `«${f.nombre}» volverá a ofrecerse.`,
  renombrar: () => "Cambia el nombre que se ve; el código (que identifica a los reportes) no cambia nunca.",
  reordenar: () => "Cambia solo la posición en las listas.",
};

export function Catalogo({ alCambiar }: { alCambiar: () => void }) {
  const [d, setD] = useState<FormularioRev | null>(null); const [error, setError] = useState<string | null>(null); const [ok, setOk] = useState<string | null>(null);
  const [dlg, setDlg] = useState<Dialogo | null>(null);
  const cargar = useCallback(async () => { try { setD(await apiRev.formulario(true)); setError(null); } catch (e) { setError(textoError(e).texto); } }, []);
  useEffect(() => { void cargar(); }, [cargar]);

  async function aplicar(dg: Dialogo, v: { codigo?: string; nombre: string; orden: string; exige_motivo?: boolean }): Promise<string | null> {
    const entidad = (dg.fila?.entidad ?? dg.entidad) as Fila["entidad"];
    const datos: Record<string, unknown> = {};
    if (dg.modo === "crear") {
      Object.assign(datos, { codigo: v.codigo, nombre: v.nombre.trim(), orden: Number(v.orden) || 100 });
      if (entidad === "tipo") datos.grupo = dg.padre; if (entidad === "subtipo") datos.tipo = dg.padre; if (entidad === "estado") datos.exige_motivo = !!v.exige_motivo;
    } else {
      const f = dg.fila as Fila; datos.codigo = f.codigo; if (entidad === "subtipo") datos.tipo = f.padre;
      if (dg.modo === "renombrar") datos.nombre = v.nombre.trim(); if (dg.modo === "reordenar") datos.orden = Number(v.orden);
    }
    try {
      await apiRev.catalogo(entidad, dg.modo, datos);
      setOk("Cambio guardado y auditado."); setDlg(null); await cargar(); alCambiar(); return null;
    } catch (e) { return textoError(e).texto; }
  }
  const filasGrupo = (g: GrupoCat): Fila => ({ entidad: "grupo", codigo: g.codigo, nombre: g.nombre, orden: g.orden, activo: g.activo });
  return (
    <section className="rv-seccion" aria-labelledby="rv-cat-tit">
      <div><h2 id="rv-cat-tit">Catálogo</h2><p className="rv-sub">Grupos, tipos, subtipos y estados. <strong>Nada se borra:</strong> se desactiva, y lo desactivado se conserva con su marca. Quién cambió qué queda auditado con el antes y el después.</p></div>
      {error ? <div className="rv-aviso rv-aviso-error" role="alert">{error} <button type="button" className="rv-enlace" onClick={() => void cargar()}>Reintentar</button></div> : null}
      {ok ? <div className="rv-aviso rv-aviso-ok" role="status">{ok}</div> : null}
      {!d && !error ? <p className="rv-sub" role="status">Cargando el catálogo…</p> : null}
      {d ? (
        <>
          <div className="rv-cat">
            {d.grupos.map((g) => (
              <div key={g.codigo} className="rv-cat-grupo">
                <Item f={filasGrupo(g)} onAccion={(modo, fila) => setDlg({ modo, fila })} />
                <div className="rv-cat-hijos">
                  {g.tipos.map((t) => (
                    <div key={t.codigo}>
                      <Item f={{ entidad: "tipo", codigo: t.codigo, nombre: t.nombre, orden: t.orden, activo: t.activo, padre: g.codigo, extra: t.campos?.length ? `${t.campos.length} campos propios` : undefined }} onAccion={(modo, fila) => setDlg({ modo, fila })} />
                      <div className="rv-cat-hijos">
                        {t.subtipos.map((s) => <Item key={s.codigo} f={{ entidad: "subtipo", codigo: s.codigo, nombre: s.nombre, orden: s.orden, activo: s.activo, padre: t.codigo }} onAccion={(modo, fila) => setDlg({ modo, fila })} />)}
                        <button type="button" className="rv-enlace" onClick={() => setDlg({ modo: "crear", entidad: "subtipo", padre: t.codigo })}>+ Agregar subtipo a «{t.nombre}»</button>
                      </div>
                    </div>
                  ))}
                  <button type="button" className="rv-enlace" onClick={() => setDlg({ modo: "crear", entidad: "tipo", padre: g.codigo })}>+ Agregar tipo a «{g.nombre}»</button>
                </div>
              </div>
            ))}
            <button type="button" className="rv-boton-sec" onClick={() => setDlg({ modo: "crear", entidad: "grupo" })}>+ Agregar grupo</button>
          </div>
          <h3 className="rv-h3">Estados</h3>
          <div className="rv-cat-grupo">
            {(d.estados ?? []).map((e) => <Item key={e.codigo} f={{ entidad: "estado", codigo: e.codigo, nombre: e.nombre, orden: e.orden, activo: e.activo, protegido: e.codigo === "reportado" || e.codigo === "duplicado", extra: `${e.cambio_manual ? "se cambia a mano" : "lo pone el sistema"}${e.exige_motivo ? " · exige motivo" : ""}` }} onAccion={(modo, fila) => setDlg({ modo, fila })} />)}
            <button type="button" className="rv-boton-sec" onClick={() => setDlg({ modo: "crear", entidad: "estado" })}>+ Agregar estado</button>
          </div>
        </>
      ) : null}
      {dlg ? <DialogoCat dlg={dlg} onAplicar={aplicar} onCancelar={() => setDlg(null)} /> : null}
    </section>
  );
}

function Item({ f, onAccion }: { f: Fila; onAccion: (modo: "renombrar" | "reordenar" | "activar" | "desactivar", f: Fila) => void }) {
  return (
    <div className={`rv-cat-item${f.activo ? "" : " rv-inactivo"}`}>
      <span><strong>{f.nombre}</strong> <span className="rv-tenue">{f.codigo} · posición {f.orden}{f.extra ? ` · ${f.extra}` : ""}</span>{f.activo ? null : <span className="rv-marca rv-marca-gris">Desactivado</span>}</span>
      <span className="rv-cat-acc">
        <button type="button" className="rv-enlace" onClick={() => onAccion("renombrar", f)}>Renombrar</button>
        <button type="button" className="rv-enlace" onClick={() => onAccion("reordenar", f)}>Posición</button>
        {f.protegido && f.activo ? <span className="rv-tenue">del sistema</span> : <button type="button" className="rv-enlace" onClick={() => onAccion(f.activo ? "desactivar" : "activar", f)}>{f.activo ? "Desactivar" : "Reactivar"}</button>}
      </span>
    </div>
  );
}

function DialogoCat({ dlg, onAplicar, onCancelar }: { dlg: Dialogo; onAplicar: (d: Dialogo, v: { codigo?: string; nombre: string; orden: string; exige_motivo?: boolean }) => Promise<string | null>; onCancelar: () => void }) {
  const f = dlg.fila;
  const [codigo, setCodigo] = useState(""); const [nombre, setNombre] = useState(f?.nombre ?? ""); const [orden, setOrden] = useState(String(f?.orden ?? 100)); const [exige, setExige] = useState(false);
  const [enviando, setEnviando] = useState(false); const [error, setError] = useState<string | null>(null);
  const necesitaNombre = dlg.modo === "crear" || dlg.modo === "renombrar"; const necesitaOrden = dlg.modo === "crear" || dlg.modo === "reordenar";
  const valido = (!necesitaNombre || nombre.trim().length >= 2) && (!necesitaOrden || Number.isInteger(Number(orden))) && (dlg.modo !== "crear" || CODIGO.test(codigo));
  const titulo = dlg.modo === "crear" ? `Agregar ${dlg.entidad}` : `${dlg.modo === "desactivar" ? "Desactivar" : dlg.modo === "activar" ? "Reactivar" : dlg.modo === "renombrar" ? "Renombrar" : "Cambiar la posición de"} «${f?.nombre}»`;
  async function enviar() { if (enviando || !valido) return; setEnviando(true); setError(null); const e = await onAplicar(dlg, { codigo, nombre, orden, exige_motivo: exige }); if (e) { setError(e); setEnviando(false); } }
  return (
    <div className="rv-modal-fondo" onMouseDown={(e) => { if (e.target === e.currentTarget && !enviando) onCancelar(); }}>
      <div className="rv-modal" role="dialog" aria-modal="true" aria-label={titulo}>
        <h3>{titulo}</h3>
        <p className="rv-sub">{dlg.modo === "crear" ? "Un código nuevo no se puede cambiar después (identifica a los reportes). Use minúsculas, números y guion bajo." : EFECTO[dlg.modo](f as Fila)}</p>
        {dlg.modo === "crear" ? <label className="rv-campo">Código<input type="text" value={codigo} onChange={(e) => setCodigo(e.target.value)} autoComplete="off" aria-invalid={codigo !== "" && !CODIGO.test(codigo)} /></label> : null}
        {necesitaNombre ? <label className="rv-campo">Nombre<input type="text" value={nombre} onChange={(e) => setNombre(e.target.value)} maxLength={160} autoComplete="off" /></label> : null}
        {necesitaOrden ? <label className="rv-campo">Posición<input type="text" inputMode="numeric" value={orden} onChange={(e) => setOrden(e.target.value)} /></label> : null}
        {dlg.modo === "crear" && dlg.entidad === "estado" ? <label className="rv-check"><input type="checkbox" checked={exige} onChange={(e) => setExige(e.target.checked)} /> Exige motivo al cambiarlo</label> : null}
        <p className="rv-tenue">Queda registrado quién lo hizo, cuándo, y los valores de antes y de después.</p>
        {error ? <p className="rv-error" role="alert">{error}</p> : null}
        <div className="rv-botones"><button type="button" className="rv-boton" disabled={enviando || !valido} onClick={() => void enviar()}>{enviando ? "Guardando…" : "Confirmar"}</button><button type="button" className="rv-boton-sec" disabled={enviando} onClick={onCancelar}>Cancelar</button></div>
      </div>
    </div>
  );
}
