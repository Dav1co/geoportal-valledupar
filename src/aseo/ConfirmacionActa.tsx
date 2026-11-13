import { useEffect, useRef, useState } from "react";
import { generarActaPdf, infoJpeg, type DatosActa, type Membrete } from "./pdf";
import { LOGO, BANDA } from "./membrete";
import { textoFechaHora } from "./logica";
import type { ResultadoAuditoria } from "./FormularioAuditoria";

// Confirmación y ACTA de la auditoría. El acta se genera EN EL NAVEGADOR a partir de lo que ya está en memoria (las fotos recién tomadas) y NO se guarda en el servidor: la fila inmutable es la prueba y el sello
// (SHA-256) permite comprobar que coincide. Descarga directa en PDF con el membrete de EMDUPAR; como respaldo, la vista de la misma acta se imprime con el navegador («Guardar como PDF»). Sin firma digital:
// hay un espacio para firma manuscrita al imprimir. Aseo no envía el acta por correo a nadie.
const aBytes = (b64: string) => Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
const MEMBRETE: Membrete = { logo: { bytes: aBytes(LOGO.b64), ancho: LOGO.ancho, alto: LOGO.alto }, banda: { bytes: aBytes(BANDA.b64), ancho: BANDA.ancho, alto: BANDA.alto } };
const coma = (n: number) => n.toFixed(5).replace(".", ",");
const SI_NO = { si: "Sí", no: "No", parcial: "Parcial" } as const;

export function construirDatosActa(r: ResultadoAuditoria, auditor: { nombre: string; correo: string }): Omit<DatosActa, "fotos"> {
  const p = r.ruta;
  const marcas = [r.conf.lejos_de_ruta && "Lejos de la ruta", r.conf.fuera_de_zona && "Fuera de la zona de operación", r.conf.fuera_de_horario && "Fuera de la franja horaria de la ruta", r.conf.no_programada_hoy && "Ruta no programada ese día", r.conf.sin_trazado && "Ruta sin trazado"].filter((x): x is string => !!x);
  return {
    consecutivo: r.conf.consecutivo, registradoEn: textoFechaHora(new Date(new Date(r.conf.registrado_en).getTime() - 5 * 3600000).toISOString().slice(0, 19)), fechaServicio: r.conf.fecha_servicio.split("-").reverse().join("/"),
    auditor, actividad: r.actividad.nombre, modalidad: r.modalidad.nombre, servicio: `${p.servicio.codigo} · ${p.servicio.nombre}`,
    ruta: { codigo: p.codigo, sectores: p.sectores, turno: p.turno_nombre, horario: p.hora_inicio && p.hora_fin ? `${p.hora_inicio} a ${p.hora_fin}` : null, frecuencia: p.frecuencia_nombre, km: p.km_ruta },
    seRealizo: SI_NO[r.seRealizo], causal: r.causal, respuestas: r.respuestas, observaciones: r.observaciones,
    posicion: { inicio: r.posicion.inicio ? `${coma(r.posicion.inicio.lat)}, ${coma(r.posicion.inicio.lon)}` : null, fin: `${coma(r.posicion.fin.lat)}, ${coma(r.posicion.fin.lon)}`, precision: `${Math.round(r.posicion.fin.precision)} m al enviar` },
    marcas, sello: r.conf.sello,
  };
}

export function ConfirmacionActa({ r, auditor, onOtra, onSalir }: { r: ResultadoAuditoria; auditor: { nombre: string; correo: string }; onOtra: () => void; onSalir: () => void }) {
  const [generando, setGenerando] = useState(false); const [error, setError] = useState<string | null>(null);
  const fotosRef = useRef(r.fotos); fotosRef.current = r.fotos;
  useEffect(() => () => { fotosRef.current.forEach((f) => URL.revokeObjectURL(f.url)); }, []);      // al salir de la confirmación se liberan las fotos de la memoria
  const nombreFoto = (c: string) => (r.actividad.fotos ?? []).find((f) => f.codigo === c)?.nombre ?? c;
  const datos = construirDatosActa(r, auditor);

  async function descargar() {
    setGenerando(true); setError(null);
    try {
      const fotos = [];
      for (const f of r.fotos) { const bytes = new Uint8Array(await f.blob.arrayBuffer()); const i = infoJpeg(bytes); fotos.push({ bytes, ancho: i.ancho, alto: i.alto, etiqueta: nombreFoto(f.etiqueta) }); }
      const pdf = generarActaPdf({ ...datos, fotos }, MEMBRETE);
      const url = URL.createObjectURL(new Blob([pdf as BlobPart], { type: "application/pdf" }));
      const a = document.createElement("a"); a.href = url; a.download = `acta-${r.conf.consecutivo}.pdf`; document.body.appendChild(a); a.click(); a.remove();
      window.setTimeout(() => URL.revokeObjectURL(url), 60000);
    } catch { setError("No se pudo generar el PDF en este navegador. Use «Imprimir» y elija «Guardar como PDF»."); } finally { setGenerando(false); }
  }

  return (
    <div className="tec-pagina campo-pagina">
      <section className="tec-tarjeta aseo-acta" aria-label="Acta de la auditoría">
        <div className="aseo-acta-membrete"><img src={`data:image/jpeg;base64,${LOGO.b64}`} alt="EMDUPAR S.A. E.S.P." width={150} /></div>
        <h1>Auditoría registrada</h1>
        <p className="aseo-consecutivo" role="status">{datos.consecutivo}{r.conf.repetido ? " (ya estaba registrada)" : ""}</p>
        {datos.marcas.length > 0 ? <p className="aseo-aviso" role="status">Marcas del registro (no impiden nada): {datos.marcas.join("; ")}.</p> : null}
        <dl className="campo-auto">
          <div><dt>Fecha y hora oficiales</dt><dd>{datos.registradoEn}</dd></div>
          <div><dt>Auditor</dt><dd>{datos.auditor.nombre}<br /><small>{datos.auditor.correo}</small></dd></div>
          <div><dt>Ruta</dt><dd><span className="mono">{datos.ruta.codigo}</span> · {datos.servicio}<br /><small>{datos.ruta.sectores ?? ""}</small></dd></div>
          <div><dt>¿Se realizó?</dt><dd>{datos.seRealizo}{datos.causal ? ` · ${datos.causal}` : ""}</dd></div>
          {datos.respuestas.map((x) => <div key={x.pregunta}><dt>{x.pregunta}</dt><dd>{x.respuesta}</dd></div>)}
          {datos.observaciones ? <div><dt>Observaciones</dt><dd>{datos.observaciones}</dd></div> : null}
          <div><dt>Ubicación</dt><dd>{datos.posicion.fin}<br /><small>{datos.posicion.precision}</small></dd></div>
          <div><dt>Sello de integridad (SHA-256)</dt><dd className="mono aseo-sello">{datos.sello}</dd></div>
        </dl>
        <div className="aseo-miniaturas">{r.fotos.map((f) => <span className="aseo-mini" key={f.id}><img src={f.url} alt={nombreFoto(f.etiqueta)} /><small>{nombreFoto(f.etiqueta)}</small></span>)}</div>
        <p className="campo-sub aseo-firma-imprimir">Firma manuscrita (opcional al imprimir): ______________________ · Recibe: ______________________</p>
        <p className="campo-sub">El acta no se guarda en el servidor: descárguela ahora, mientras las fotos siguen en este teléfono. No lleva firma digital.</p>
        {error ? <div className="campo-error" role="alert"><p>{error}</p></div> : null}
        <div className="aseo-acciones">
          <button type="button" className="tec-boton campo-boton-foto" onClick={() => void descargar()} disabled={generando}>{generando ? "Generando…" : "Descargar acta (PDF)"}</button>
          <button type="button" className="tec-boton-sec" onClick={() => window.print()}>Imprimir</button>
          <button type="button" className="tec-boton-sec" onClick={onOtra}>Auditar otra ruta</button>
          <button type="button" className="tec-boton-sec" onClick={onSalir}>Salir</button>
        </div>
      </section>
    </div>
  );
}
