import { useEffect, useMemo, useRef, useState } from "react";
import { apiAseo, avisoDeError, ErrorAseo } from "./apiAseo";
import { abrirCamara, capturarFoto, cerrarCamara, ErrorCamara } from "../campo/camara";
import { useUbicacion, UMBRAL_PRECISION_MALA_M } from "../campo/ubicacion";
import { aplanarDatos, contadorFotos, criteriosActivos, cuerpoFirmas, erroresDeEnvio, erroresDeFirmas, fotosNecesarias, textoFechaHora, type Valores } from "./logica";
import { FirmasActa, FIRMAS_VACIAS, type FirmasLocal } from "./FirmasActa";
import type { Actividad, Confirmacion, Criterio, FormularioAseo, Modalidad, Preparacion, RutaPlan, SeRealizo } from "./tipos";

// Formulario de la auditoría. Se dibuja del catálogo del servidor (preguntas, fotos, causales): aquí no hay ninguna pregunta escrita. Flujo decidido: ¿Se realizó? Sí / No / Parcial → fotos de la ruta → SST (con foto
// obligatoria si la respuesta es «No») → Registrar. Un solo envío (patrón del Paso D): se piden las URL de subida, se suben las fotos y se crea TODO junto (todo o nada, reintento seguro con el mismo identificador).
// Las fotos viven SOLO en memoria (no se guardan en el dispositivo ni en la galería). La fecha y la hora las fija el servidor: aquí solo se muestran.

export type FotoLocal = { id: string; etiqueta: string; blob: Blob; url: string };
export type ResultadoAuditoria = {
  conf: Confirmacion; actividad: Actividad; modalidad: Modalidad; ruta: RutaPlan; seRealizo: SeRealizo; causal: string | null; respuestas: { pregunta: string; respuesta: string }[]; observaciones: string | null;
  fotos: FotoLocal[]; firmas: FirmasLocal; posicion: { inicio: { lat: number; lon: number } | null; fin: { lat: number; lon: number; precision: number } };
};

const coma = (n: number) => n.toFixed(5).replace(".", ",");
const megas = (b: number) => `${(b / 1048576).toLocaleString("es-CO", { maximumFractionDigits: 1 })} MB`;

/** Hora de Bogotá del servidor, avanzando con el reloj del teléfono desde el instante en que llegó (el reloj del teléfono nunca se usa como dato, solo para mover la hora que se muestra). */
function useHoraServidor(inicial: string): string {
  const base = useRef({ t0: Date.now(), iso: inicial });
  const [, tick] = useState(0);
  useEffect(() => { const r = window.setInterval(() => tick((x) => x + 1), 15000); return () => window.clearInterval(r); }, []);
  const [f, h] = base.current.iso.split("T");
  const d = new Date(`${f}T${h.slice(0, 8)}Z`).getTime() + (Date.now() - base.current.t0);
  return new Date(d).toISOString().slice(0, 19);
}

export function FormularioAuditoria({ def, actividad, modalidad, ruta, ahora, onVolver, onListo }: {
  def: FormularioAseo; actividad: Actividad; modalidad: Modalidad; ruta: RutaPlan; ahora: string; onVolver: () => void; onListo: (r: ResultadoAuditoria) => void;
}) {
  const [seRealizo, setSeRealizo] = useState<SeRealizo | "">("");
  const [causal, setCausal] = useState("");
  const [valores, setValores] = useState<Valores>({});
  const [observaciones, setObservaciones] = useState("");
  const [fotos, setFotos] = useState<FotoLocal[]>([]);
  const [firmas, setFirmas] = useState<FirmasLocal>(FIRMAS_VACIAS);
  const [camara, setCamara] = useState<{ etiqueta: string; nombre: string } | null>(null);
  const [fase, setFase] = useState<"editando" | "enviando">("editando");
  const [progreso, setProgreso] = useState("");
  const [error, setError] = useState<{ texto: string; reintentable: boolean } | null>(null);
  const ubic = useUbicacion();
  const inicio = useRef<{ lat: number; lon: number } | null>(null);
  if (!inicio.current && ubic.fix) inicio.current = { lat: ubic.fix.lat, lon: ubic.fix.lon };       // posición AL ABRIR: el primer fijo del formulario
  const prep = useRef<{ p: Preparacion; n: number; subidas: Set<number> } | null>(null);
  const hora = useHoraServidor(ahora);
  const fotosRef = useRef<FotoLocal[]>([]); fotosRef.current = fotos;
  useEffect(() => () => { fotosRef.current.forEach((f) => URL.revokeObjectURL(f.url)); }, []);      // al salir se liberan; las que pasan al acta las libera la pantalla siguiente

  const criterios = criteriosActivos(actividad);
  const { datos, fotosExigidas } = useMemo(() => aplanarDatos(actividad, valores, seRealizo), [actividad, valores, seRealizo]);
  const necesarias = useMemo(() => fotosNecesarias(actividad, seRealizo, fotosExigidas), [actividad, seRealizo, fotosExigidas]);
  const cuenta = useMemo(() => { const c: Record<string, number> = {}; for (const f of fotos) c[f.etiqueta] = (c[f.etiqueta] ?? 0) + 1; return c; }, [fotos]);
  const errores = [...erroresDeEnvio(actividad, { seRealizo, causal, valores, fotosPorEtiqueta: cuenta }), ...(seRealizo ? erroresDeFirmas({ auditor: firmas.auditor?.b64 ?? null, representante: { estado: firmas.representante.estado, nombre: firmas.representante.nombre, imagen: firmas.representante.imagen?.b64 ?? null } }) : [])];
  const causales = (actividad.causales ?? []).filter((c) => c.activo !== false);
  const secciones = useMemo(() => { const m = new Map<string, Criterio[]>(); for (const c of criterios) { const k = c.seccion ?? ""; m.set(k, [...(m.get(k) ?? []), c]); } return [...m.entries()]; }, [criterios]);
  const sinCriterios = criterios.length === 0;

  const quitarFoto = (id: string) => setFotos((l) => { const f = l.find((x) => x.id === id); if (f) URL.revokeObjectURL(f.url); return l.filter((x) => x.id !== id); });
  const sello = () => [textoFechaHora(hora), ubic.fix ? `${coma(ubic.fix.lat)}, ${coma(ubic.fix.lon)}` : "sin ubicación"];

  async function enviar() {
    if (fase === "enviando" || errores.length > 0 || !seRealizo) return;
    const fin = ubic.fix;
    if (!fin) { setError({ texto: "Todavía no hay ubicación. Espere unos segundos a cielo abierto y pulse «Registrar» otra vez.", reintentable: false }); return; }
    // Fotos a enviar: solo las necesarias, hasta su máximo, en orden estable
    const ordenadas: FotoLocal[] = [];
    for (const n of necesarias) ordenadas.push(...fotos.filter((f) => f.etiqueta === n.etiqueta).slice(0, n.max));
    setError(null); setFase("enviando");
    try {
      if (!prep.current || prep.current.n !== ordenadas.length) { setProgreso("Preparando el envío…"); prep.current = { p: await apiAseo.prepararSubida(actividad.codigo, ordenadas.length), n: ordenadas.length, subidas: new Set() }; }
      const { p, subidas } = prep.current;
      for (let i = 0; i < ordenadas.length; i++) {
        if (subidas.has(i)) continue;
        setProgreso(`Subiendo la foto ${i + 1} de ${ordenadas.length}…`);
        await apiAseo.subirFoto(p.fotos[i].ruta, p.fotos[i].token, ordenadas[i].blob);
        subidas.add(i);
      }
      setProgreso("Registrando la auditoría…");
      const conf = await apiAseo.crear({
        auditoria_id: p.auditoria_id, actividad: actividad.codigo, modalidad: modalidad.codigo, ruta: ruta.codigo, se_realizo: seRealizo, causal: seRealizo === "si" ? null : causal, datos,
        observaciones: observaciones.trim() || null, lat: fin.lat, lon: fin.lon, precision_m: fin.precision_m, lat_inicio: inicio.current?.lat ?? null, lon_inicio: inicio.current?.lon ?? null, precision_inicio_m: null,
        fotos: ordenadas.map((f, i) => ({ orden: i + 1, ruta: p.fotos[i].ruta, etiqueta: f.etiqueta })),
        firmas: cuerpoFirmas({ auditor: firmas.auditor?.b64 ?? null, representante: { estado: firmas.representante.estado, nombre: firmas.representante.nombre, imagen: firmas.representante.imagen?.b64 ?? null } }),
      });
      const respuestas = criterios.filter((c) => c.codigo in datos).map((c) => ({ pregunta: c.nombre, respuesta: textoRespuesta(c, datos[c.codigo]) }));
      setFotos((l) => l.filter((f) => !ordenadas.includes(f)));      // las fotos pasan al acta (la pantalla siguiente las libera)
      onListo({ conf, actividad, modalidad, ruta, seRealizo, causal: seRealizo === "si" ? null : causales.find((c) => c.codigo === causal)?.nombre ?? causal, respuestas, observaciones: observaciones.trim() || null,
        fotos: ordenadas, firmas, posicion: { inicio: inicio.current, fin: { lat: fin.lat, lon: fin.lon, precision: fin.precision_m } } });
    } catch (e) {
      const err = e instanceof ErrorAseo ? e : new ErrorAseo("servidor", "No se pudo completar el envío.", 0);
      if (err.tipo === "subida_vencida") prep.current = null;                // se pedirá un permiso nuevo y se subirá todo de nuevo
      setError(avisoDeError(err)); setFase("editando"); setProgreso("");
    }
  }

  if (camara) return <PanelCamara rotulo={camara.nombre} maxBytes={def.limites.max_bytes_foto} sello={sello} onCerrar={() => setCamara(null)}
    onFoto={(f) => { setFotos((l) => [...l, { id: crypto.randomUUID(), etiqueta: camara.etiqueta, blob: f.blob, url: URL.createObjectURL(f.blob) }]); setCamara(null); }} />;

  const precisionMala = ubic.fix && ubic.fix.precision_m > def.limites.precision_aviso_m;
  const dis = fase === "enviando";
  return (
    <div className="tec-pagina campo-pagina">
      <section className="tec-tarjeta">
        <div className="campo-cab"><button type="button" className="tec-boton-sec" onClick={onVolver} disabled={dis}>‹ Rutas</button><h1>{actividad.nombre} · {modalidad.nombre}</h1></div>
        <dl className="campo-auto">
          <div><dt>Ruta</dt><dd><strong className="mono">{ruta.codigo}</strong> · {ruta.servicio.nombre}<br /><small>{ruta.sectores ?? "Sin sectores"}</small></dd></div>
          <div><dt>Fecha y hora</dt><dd>{textoFechaHora(hora)}<br /><small>La fija el servidor al registrar; la del teléfono no cuenta.</small></dd></div>
          <div><dt>Ubicación</dt><dd>{ubic.fix ? `${coma(ubic.fix.lat)}, ${coma(ubic.fix.lon)} · precisión ${Math.round(ubic.fix.precision_m)} m` : ubic.estado === "buscando" ? "Buscando…" : "Sin ubicación"}
            {precisionMala ? <small> La precisión es baja (más de {UMBRAL_PRECISION_MALA_M} m): salga a cielo abierto. Se puede registrar igual.</small> : null}
            {ubic.mensaje ? <small> {ubic.mensaje}</small> : null}
            <button type="button" className="campo-enlace" onClick={ubic.actualizar} disabled={dis}>Actualizar ubicación</button></dd></div>
        </dl>
        {!ruta.geometria ? <p className="aseo-aviso" role="status">Esta ruta aún no tiene trazado en el mapa: la auditoría se registra igual y queda marcada «sin trazado».</p> : null}

        {sinCriterios && (actividad.fotos ?? []).length === 0 ? <p className="aseo-aviso" role="alert">Criterios pendientes: la actividad aún no tiene criterios de auditoría cargados. No se puede registrar hasta que el administrador los cargue.</p> : null}

        <fieldset className="campo-fieldset" disabled={dis}>
          <legend className="campo-etiqueta">¿Se realizó?</legend>
          <div className="aseo-opciones">{(["si", "no", "parcial"] as const).map((v) => (
            <label key={v} className={`aseo-opcion${seRealizo === v ? " aseo-opcion-on" : ""}`}><input type="radio" name="se_realizo" value={v} checked={seRealizo === v} onChange={() => { setSeRealizo(v); if (v === "si") setCausal(""); }} />{v === "si" ? "Sí" : v === "no" ? "No" : "Parcial"}</label>))}</div>
          {seRealizo && seRealizo !== "si" ? (
            <div className="campo-campo"><label className="campo-etiqueta" htmlFor="aseo-causal">Causal</label>
              <select id="aseo-causal" className="aseo-entrada" value={causal} onChange={(e) => setCausal(e.target.value)}><option value="">Elija la causal…</option>{causales.map((c) => <option key={c.codigo} value={c.codigo}>{c.nombre}</option>)}</select></div>
          ) : null}
        </fieldset>

        {seRealizo && seRealizo !== "no" ? secciones.map(([sec, lista]) => (
          <fieldset className="campo-fieldset" key={sec} disabled={dis}>
            {sec ? <legend className="campo-etiqueta">{sec}</legend> : null}
            {lista.map((c) => <CampoCriterio key={c.codigo} c={c} valor={valores[c.codigo]} onCambio={(v) => setValores((x) => ({ ...x, [c.codigo]: v }))} />)}
          </fieldset>
        )) : null}

        {necesarias.length > 0 ? (
          <fieldset className="campo-fieldset" disabled={dis}>
            <legend className="campo-etiqueta">Fotos</legend>
            <p className="campo-sub">Solo con la cámara del formulario. Las fotos no se guardan en el teléfono.</p>
            <p className="aseo-nota-rostro" role="note">Evite fotografiar el rostro de las personas.</p>
            <div className="campo-fotos">{necesarias.map((n) => {
              const mias = fotos.filter((f) => f.etiqueta === n.etiqueta);
              return (
                <div className="campo-foto" key={n.etiqueta}>
                  <span className="campo-foto-n">{n.nombre} · {contadorFotos(mias.length, n.min, n.max)}</span>
                  <div className="aseo-miniaturas">{mias.map((f) => (<span className="aseo-mini" key={f.id}><img src={f.url} alt={`${n.nombre}`} /><button type="button" className="tec-boton-sec aseo-quitar" onClick={() => quitarFoto(f.id)} aria-label="Quitar esta foto">Quitar</button></span>))}</div>
                  {mias.length < n.max ? <button type="button" className="tec-boton campo-boton-foto" onClick={() => setCamara({ etiqueta: n.etiqueta, nombre: n.nombre })}>Tomar foto</button> : null}
                </div>
              );
            })}</div>
            <p className="campo-sub">Máximo de la actividad: {actividad.fotos_max ?? 5} fotos; cada una hasta {megas(def.limites.max_bytes_foto)}.</p>
          </fieldset>
        ) : null}

        {seRealizo ? (
          <div className="campo-campo"><label className="campo-etiqueta" htmlFor="aseo-obs">Observaciones <small>(opcional)</small></label>
            <textarea id="aseo-obs" className="campo-texto" value={observaciones} maxLength={1000} onChange={(e) => setObservaciones(e.target.value)} disabled={dis} /></div>
        ) : null}

        {seRealizo ? <FirmasActa valor={firmas} onCambio={setFirmas} deshabilitado={dis} /> : null}

        {errores.length > 0 && seRealizo ? <ul className="aseo-faltan" aria-label="Lo que falta"><li><strong>Falta para registrar:</strong></li>{errores.map((e) => <li key={e}>{e}</li>)}</ul> : null}
        {error ? <div className="campo-error" role="alert"><p>{error.texto}</p></div> : null}
        {dis ? <p className="campo-sub" role="status">{progreso} No cierre esta pantalla.</p> : null}
        <button type="button" className="tec-boton campo-boton-foto" onClick={() => void enviar()} disabled={dis || errores.length > 0 || !seRealizo || !ubic.fix}>{dis ? "Enviando…" : error?.reintentable ? "Reintentar" : "Registrar"}</button>
      </section>
    </div>
  );
}

const textoRespuesta = (c: Criterio, v: unknown): string => {
  if (typeof v === "boolean") return v ? "Sí" : "No";
  if (Array.isArray(v)) return v.map((x) => c.opciones?.find((o) => o.codigo === x)?.nombre ?? String(x)).join(", ");
  if (c.tipo_dato === "opcion") return c.opciones?.find((o) => o.codigo === v)?.nombre ?? String(v);
  return `${String(v)}${c.unidad ? " " + c.unidad : ""}`;
};

function CampoCriterio({ c, valor, onCambio }: { c: Criterio; valor: string | string[] | undefined; onCambio: (v: string | string[]) => void }) {
  const id = `aseo-c-${c.codigo}`, v = typeof valor === "string" ? valor : "";
  const rot = <label className="campo-etiqueta" htmlFor={id}>{c.nombre}{c.obligatorio ? "" : <small> (opcional)</small>}</label>;
  const ayuda = c.ayuda ? <small className="campo-sub">{c.ayuda}</small> : null;
  switch (c.tipo_dato) {
    case "si_no":
      return (<div className="campo-campo"><span className="campo-etiqueta" id={id}>{c.nombre}</span>
        <div className="aseo-opciones" role="radiogroup" aria-labelledby={id}>{(["si", "no"] as const).map((o) => (<label key={o} className={`aseo-opcion${v === o ? " aseo-opcion-on" : ""}`}><input type="radio" name={id} value={o} checked={v === o} onChange={() => onCambio(o)} />{o === "si" ? "Sí" : "No"}</label>))}</div>
        {c.exige_foto_si ? <small className="campo-sub">Si responde «{c.exige_foto_si === "si" ? "Sí" : "No"}» se pedirá una foto de evidencia.</small> : null}{ayuda}</div>);
    case "texto": return <div className="campo-campo">{rot}<textarea id={id} className="campo-texto" value={v} maxLength={c.maximo ?? 300} onChange={(e) => onCambio(e.target.value)} />{ayuda}</div>;
    case "entero": case "decimal": return <div className="campo-campo">{rot}<input id={id} className="aseo-entrada" inputMode="decimal" value={v} onChange={(e) => onCambio(e.target.value)} />{c.unidad ? <small className="campo-sub">{c.unidad}</small> : null}{ayuda}</div>;
    case "opcion": return <div className="campo-campo">{rot}<select id={id} className="aseo-entrada" value={v} onChange={(e) => onCambio(e.target.value)}><option value="">Elija…</option>{(c.opciones ?? []).filter((o) => o.activo !== false).map((o) => <option key={o.codigo} value={o.codigo}>{o.nombre}</option>)}</select>{ayuda}</div>;
    case "opciones": { const sel = Array.isArray(valor) ? valor : [];
      return (<div className="campo-campo"><span className="campo-etiqueta">{c.nombre}</span>{(c.opciones ?? []).filter((o) => o.activo !== false).map((o) => (
        <label key={o.codigo} className="campo-check"><input type="checkbox" checked={sel.includes(o.codigo)} onChange={(e) => onCambio(e.target.checked ? [...sel, o.codigo] : sel.filter((x) => x !== o.codigo))} /><span>{o.nombre}</span></label>))}{ayuda}</div>); }
    case "dia_hora": return <div className="campo-campo">{rot}<input id={id} className="aseo-entrada" type="datetime-local" value={v} onChange={(e) => onCambio(e.target.value)} />{ayuda}</div>;
  }
}

function PanelCamara({ rotulo, maxBytes, sello, onFoto, onCerrar }: { rotulo: string; maxBytes: number; sello: () => string[]; onFoto: (f: { blob: Blob }) => void; onCerrar: () => void }) {
  const videoRef = useRef<HTMLVideoElement>(null); const flujo = useRef<MediaStream | null>(null);
  const [error, setError] = useState<string | null>(null); const [lista, setLista] = useState(false); const [procesando, setProcesando] = useState(false);
  useEffect(() => {
    let vivo = true;
    abrirCamara().then((f) => { if (!vivo) { cerrarCamara(f); return; } flujo.current = f; const v = videoRef.current; if (v) { v.srcObject = f; void v.play().catch(() => {}); } })
      .catch((e) => { if (vivo) setError(e instanceof ErrorCamara ? e.message : "No se pudo abrir la cámara."); });
    return () => { vivo = false; cerrarCamara(flujo.current); flujo.current = null; };
  }, []);
  async function capturar() {
    const v = videoRef.current; if (!v || procesando) return;
    setProcesando(true);
    try {
      const f = await capturarFoto(v, sello(), maxBytes);
      if (!f) { setError(`La foto pesa más de ${megas(maxBytes)} aun reducida. Acérquese o mejore la luz e intente de nuevo.`); return; }
      onFoto(f);
    } catch (e) { setError(e instanceof ErrorCamara ? e.message : "No se pudo tomar la foto."); } finally { setProcesando(false); }
  }
  return (
    <div className="campo-camara" role="dialog" aria-modal="true" aria-label={`Cámara · ${rotulo}`}>
      <div className="campo-camara-cab">{rotulo}<small className="aseo-camara-nota"> · Evite fotografiar el rostro de las personas.</small></div>
      {error ? <div className="campo-camara-error"><p role="alert">{error}</p></div> : <video ref={videoRef} className="campo-video" autoPlay playsInline muted onLoadedMetadata={() => setLista(true)} />}
      <div className="campo-camara-acc">
        <button type="button" className="tec-boton-sec" onClick={onCerrar}>Cancelar</button>
        {!error && <button type="button" className="tec-boton campo-capturar" onClick={() => void capturar()} disabled={!lista || procesando}>{procesando ? "Procesando…" : "Tomar foto"}</button>}
      </div>
    </div>
  );
}
