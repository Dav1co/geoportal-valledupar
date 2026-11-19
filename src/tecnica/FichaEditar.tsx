import { useMemo, useState } from "react";
import { comprimirArchivo } from "../lib/comprimirFoto";
import "./dano.css";
import { IconoCamara } from "./IconoCamara";
import { apiPerfil, subirArchivo, type CambiosFicha, type EdicionFicha, type Opcion } from "./apiRedes";

// Editar la ficha del activo (Corte 3b, §22 y §23). El administrador y, desde el Corte 4a, el supervisor de distribución (§26.2); el origen, solo el
// administrador. El servidor lo vuelve a verificar. Cada guardado es una edición con autor, fecha y motivo: los datos crean una VERSIÓN nueva (nada se sobrescribe); el alias y la placa
// van como eventos; el origen se corrige con una fila nueva. La epicrisis muestra «se cambió X de A a B».

type Campo = { clave: string; rotulo: string; tipo: "texto" | "numero" | "fecha" | "lista" | "largo"; opciones?: Opcion[]; unidad?: string; max?: number };
const vacio = (v: unknown) => v === undefined || v === null ? "" : String(v);

export function FichaEditar({ codigo, edicion, onCancelar, onGuardado }: { codigo: string; edicion: EdicionFicha; onCancelar: () => void; onGuardado: (msg: string) => void }) {
  const v0 = edicion.valores;
  const campos: Campo[] = useMemo(() => {
    const c: Campo[] = [
      { clave: "alias", rotulo: "Alias del activo (nombre propio)", tipo: "texto", max: 60 },
      { clave: "placa", rotulo: "Placa de almacén o número de inventario", tipo: "texto", max: 40 },
      { clave: "nombre", rotulo: "Nombre", tipo: "texto", max: 120 },
      { clave: "estado_codigo", rotulo: "Estado", tipo: "lista", opciones: edicion.estados },
    ];
    if (edicion.lleva.clase) c.push({ clave: "clase", rotulo: "Clase", tipo: "lista", opciones: edicion.clases });
    if (edicion.lleva.efecto) c.push({ clave: "efecto", rotulo: "Efecto en la red", tipo: "lista", opciones: edicion.efectos });
    c.push({ clave: "material_codigo", rotulo: "Material", tipo: "lista", opciones: edicion.materiales });
    if (edicion.lleva.diametro_mm) c.push({ clave: "diametro_mm", rotulo: "Diámetro", tipo: "numero", unidad: "mm" });
    if (edicion.lleva.capacidad) c.push({ clave: "capacidad", rotulo: "Capacidad", tipo: "numero" });
    if (edicion.lleva.profundidad_m) c.push({ clave: "profundidad_m", rotulo: "Profundidad", tipo: "numero", unidad: "m" });
    c.push({ clave: "fecha_instalacion", rotulo: "Fecha de instalación", tipo: "fecha" }, { clave: "barrio_sector", rotulo: "Barrio o sector", tipo: "texto", max: 120 },
           { clave: "observaciones", rotulo: "Observaciones", tipo: "largo", max: 1000 });
    return c;
  }, [edicion]);
  const [val, setVal] = useState<Record<string, string>>(() => Object.fromEntries(campos.map((c) => [c.clave, vacio(v0[c.clave])])));
  const [attr, setAttr] = useState<Record<string, string>>(() => Object.fromEntries(edicion.campos_tipo.map((c) => [c.clave, vacio(c.valor)])));
  const [origen, setOrigen] = useState({ origen: vacio(v0.origen) || "emdupar", aportante: vacio(v0.aportante), nota: vacio(v0.origen_nota) });
  const [motivo, setMotivo] = useState("");
  const [estado, setEstado] = useState<"" | "guardando">("");
  const [error, setError] = useState<string | null>(null);

  const nombreDe = (c: Campo, v: string) => (c.opciones?.find((o) => o.codigo === v)?.nombre ?? v) || "sin dato";
  const cambios: CambiosFicha = {};
  const resumen: string[] = [];
  for (const c of campos) {
    const a = vacio(v0[c.clave]).trim(), b = (val[c.clave] ?? "").trim();
    const igual = c.tipo === "numero" ? (a === "" ? b === "" : Number(a) === Number(b.replace(",", "."))) : a === b;
    if (igual) continue;
    cambios[c.clave] = b === "" ? null : c.tipo === "numero" ? Number(b.replace(",", ".")) : b;
    resumen.push(`${c.rotulo}: de «${nombreDe(c, a)}» a «${nombreDe(c, b)}»`);
  }
  const attrCambios: Record<string, string | number | null> = {};
  for (const c of edicion.campos_tipo) {
    const a = vacio(c.valor).trim(), b = (attr[c.clave] ?? "").trim();
    if (a === b) continue;
    attrCambios[c.clave] = b === "" ? null : c.tipo === "numero" || c.tipo === "entero" ? Number(b.replace(",", ".")) : b;
    resumen.push(`${c.rotulo}: de «${a || "sin dato"}» a «${b || "sin dato"}»`);
  }
  if (Object.keys(attrCambios).length) cambios.atributos = attrCambios;
  const puedeOrigen = edicion.puede_origen === true;
  const origenCambia = puedeOrigen && origen.origen !== (vacio(v0.origen) || "emdupar") || (origen.origen !== "emdupar" && origen.aportante !== vacio(v0.aportante)) || origen.nota.trim() !== vacio(v0.origen_nota);
  if (origenCambia) { cambios.origen = { origen: origen.origen, aportante: origen.origen === "emdupar" ? null : origen.aportante || null, nota: origen.nota.trim() || null }; resumen.push("Se corrige el origen del activo"); }

  async function guardar() {
    setError(null);
    if (!resumen.length) { setError("No hay cambios."); return; }
    const RANGOS: Record<string, [number, number]> = { diametro_mm: [1, 5000], capacidad: [0, 1e12], profundidad_m: [0, 200] };
    for (const c of campos) {
      const v = cambios[c.clave];
      if (c.tipo !== "numero" || v === undefined || v === null) continue;
      if (Number.isNaN(v)) { setError(`${c.rotulo} debe ser un número.`); return; }
      const [mn, mx] = RANGOS[c.clave] ?? [-Infinity, Infinity];
      if ((v as number) < mn || (v as number) > mx) { setError(`${c.rotulo} va de ${mn} a ${mx.toLocaleString("es-CO")}.`); return; }
    }
    if (cambios.alias !== undefined && cambios.alias !== null && String(cambios.alias).length < 2) { setError("El alias lleva de 2 a 60 caracteres."); return; }
    if (cambios.placa !== undefined && cambios.placa !== null && !/^[A-Za-z0-9][A-Za-z0-9./ _-]{0,39}$/.test(String(cambios.placa))) { setError("La placa lleva de 1 a 40 letras, números, punto, guion o barra."); return; }
    if (cambios.fecha_instalacion && (String(cambios.fecha_instalacion) < "1900-01-01" || new Date(String(cambios.fecha_instalacion)) > new Date())) { setError("La fecha de instalación no puede ser futura ni antes de 1900."); return; }
    if (motivo.trim().length < 10) { setError("Escriba el motivo del cambio (10 caracteres o más)."); return; }
    setEstado("guardando");
    try {
      const r = await apiPerfil.editar(codigo, cambios, motivo.trim());
      onGuardado(r.version_nueva ? `Ficha guardada: versión ${r.version}.` : "Ficha guardada.");
    } catch (e) { setError(e instanceof Error ? e.message : "No se pudo guardar."); }
    finally { setEstado(""); }
  }

  const control = (c: Campo) => {
    const id = `fe-${c.clave}`;
    const comun = { id, value: val[c.clave] ?? "", onChange: (e: { target: { value: string } }) => setVal((x) => ({ ...x, [c.clave]: e.target.value })) };
    return (
      <div className="tec-campo" key={c.clave}>
        <label htmlFor={id}>{c.rotulo}{c.unidad ? ` (${c.unidad})` : ""}</label>
        {c.tipo === "lista" ? <select {...comun}>{c.clave === "estado_codigo" ? null : <option value="">Sin dato</option>}{c.opciones!.map((o) => <option key={o.codigo} value={o.codigo}>{o.nombre}</option>)}</select>
          : c.tipo === "largo" ? <textarea {...comun} className="dan-texto" rows={3} maxLength={c.max} />
          : <input {...comun} type={c.tipo === "fecha" ? "date" : "text"} inputMode={c.tipo === "numero" ? "decimal" : undefined} maxLength={c.max} />}
      </div>
    );
  };

  return (
    <section className="red-seccion red-editar" aria-labelledby="fe-tit">
      <h2 id="fe-tit">Editar la ficha</h2>
      <p className="red-nota">Cada cambio queda como una versión nueva, con su autor, la fecha y el motivo. Nada se sobrescribe.</p>
      {campos.map(control)}
      {edicion.campos_tipo.length ? <h3 className="red-sub">Campos del tipo</h3> : null}
      {edicion.campos_tipo.map((c) => (
        <div className="tec-campo" key={c.clave}>
          <label htmlFor={`fa-${c.clave}`}>{c.rotulo}{c.unidad ? ` (${c.unidad})` : ""}</label>
          <input id={`fa-${c.clave}`} type="text" maxLength={120} inputMode={c.tipo === "numero" || c.tipo === "entero" ? "decimal" : undefined} value={attr[c.clave] ?? ""}
            onChange={(e) => setAttr((x) => ({ ...x, [c.clave]: e.target.value }))} />
        </div>))}
      {puedeOrigen ? <>
      <h3 className="red-sub">Origen (solo lo corrige el administrador)</h3>
      <div className="tec-campo"><label htmlFor="fe-origen">Origen</label>
        <select id="fe-origen" value={origen.origen} onChange={(e) => setOrigen((o) => ({ ...o, origen: e.target.value }))}>
          <option value="emdupar">EMDUPAR</option><option value="tercero">Tercero</option><option value="mixto">Tercero y EMDUPAR</option></select></div>
      {origen.origen !== "emdupar" ? <div className="tec-campo"><label htmlFor="fe-aportante">Entregado por</label>
        <select id="fe-aportante" value={origen.aportante} onChange={(e) => setOrigen((o) => ({ ...o, aportante: e.target.value }))}><option value="">Elija…</option>
          {edicion.aportantes.filter((a) => a.codigo !== "emdupar").map((a) => <option key={a.codigo} value={a.codigo}>{a.nombre}</option>)}</select></div> : null}
      <div className="tec-campo"><label htmlFor="fe-onota">Nota del origen (opcional)</label><input id="fe-onota" type="text" maxLength={500} value={origen.nota} onChange={(e) => setOrigen((o) => ({ ...o, nota: e.target.value }))} /></div>
      </> : null}
      <div className="red-cambios" aria-live="polite">
        <strong>{resumen.length ? "Se cambiará:" : "Todavía no hay cambios."}</strong>
        {resumen.length ? <ul>{resumen.map((r) => <li key={r}>{r}</li>)}</ul> : null}
      </div>
      <div className="tec-campo"><label htmlFor="fe-motivo">Motivo del cambio</label>
        <input id="fe-motivo" type="text" maxLength={1000} value={motivo} onChange={(e) => setMotivo(e.target.value)} placeholder="Revisión en campo, plano de obra, acta de entrega…" /></div>
      {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
      <div className="tec-acciones">
        <button type="button" className="tec-boton red-accion" disabled={estado === "guardando"} onClick={() => void guardar()}>{estado === "guardando" ? "Guardando…" : "Guardar cambios"}</button>
        <button type="button" className="tec-boton-sec" disabled={estado === "guardando"} onClick={onCancelar}>Cancelar</button>
      </div>
    </section>
  );
}

/** Reduce una imagen a JPEG (lado mayor 1600 px) hasta que quepa en el tope. */
// compresión común (src/lib/comprimirFoto.ts): 1.600 px, JPEG 0,8, meta 250–500 KB; respeta el giro del celular (EXIF); un JPEG que ya cabe se sube tal cual
const aJpeg = async (archivo: File, maxBytes: number): Promise<Blob> => (await comprimirArchivo(archivo, maxBytes)).blob;

export function FotoPerfilCambiar({ codigo, maxBytes, onCancelar, onGuardado }: { codigo: string; maxBytes: number; onCancelar: () => void; onGuardado: (msg: string) => void }) {
  const [blob, setBlob] = useState<Blob | null>(null);
  const [vista, setVista] = useState<string | null>(null);
  const [motivo, setMotivo] = useState("");
  const [estado, setEstado] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  async function elegir(f: File | undefined) {
    setError(null); if (!f) return;
    if (!/^image\//.test(f.type)) { setError("Elija una foto (JPEG o PNG)."); return; }
    try { const b = await aJpeg(f, maxBytes); setBlob(b); setVista((v) => { if (v) URL.revokeObjectURL(v); return URL.createObjectURL(b); }); }
    catch (e) { setError(e instanceof Error ? e.message : "No se pudo leer la foto."); }
  }
  async function guardar() {
    setError(null);
    if (!blob) { setError("Elija la foto."); return; }
    if (motivo.trim().length < 10) { setError("Escriba el motivo del cambio (10 caracteres o más)."); return; }
    try {
      setEstado("Preparando…"); const p = await apiPerfil.fotoPreparar(codigo);
      setEstado("Subiendo la foto…"); await subirArchivo(p.url_subida, blob, "image/jpeg");
      setEstado("Guardando…"); await apiPerfil.fotoFijar(codigo, p.ruta, motivo.trim());
      onGuardado("Foto principal guardada.");
    } catch (e) { setError(e instanceof Error ? (e.message === "vencida" ? "El permiso para subir venció: intente de nuevo." : e.message) : "No se pudo guardar."); }
    finally { setEstado(null); }
  }
  return (
    <section className="red-seccion red-editar" aria-labelledby="fp-tit">
      <h2 id="fp-tit">Cambiar la foto principal</h2>
      <div className="tec-campo"><label htmlFor="fp-archivo"><IconoCamara />Foto</label><input id="fp-archivo" type="file" accept="image/jpeg,image/png" onChange={(e) => void elegir(e.target.files?.[0])} /></div>
      {vista ? <img className="red-foto-vista" src={vista} alt="Vista previa de la foto principal" /> : null}
      <div className="tec-campo"><label htmlFor="fp-motivo">Motivo del cambio</label><input id="fp-motivo" type="text" maxLength={1000} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></div>
      {error ? <p className="tec-aviso tec-aviso-error" role="alert">{error}</p> : null}
      <div className="tec-acciones">
        <button type="button" className="tec-boton red-accion" disabled={!!estado} onClick={() => void guardar()}>{estado ?? "Guardar foto"}</button>
        <button type="button" className="tec-boton-sec" disabled={!!estado} onClick={onCancelar}>Cancelar</button>
      </div>
    </section>
  );
}
