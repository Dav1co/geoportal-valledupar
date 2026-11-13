import { useState } from "react";
import { FirmaPad } from "./FirmaPad";
import type { FirmaJpeg } from "./firmas";
import { ROTULO_REPRESENTANTE, type EstadoRepresentante } from "./logica";

// Sección «Firmas» del formulario: la del auditor de la interventoría (obligatoria) y la del representante del operador (opcional: firma con su nombre, se negó, o no había representante).
// «Agregar firma» abre el momento dedicado (FirmaPad); la firma queda como miniatura, sin editar encima. «Volver a firmar» la reemplaza mientras no se haya registrado; al registrar queda definitiva.
export type FirmasLocal = { auditor: FirmaJpeg | null; representante: { estado: EstadoRepresentante; nombre: string; imagen: FirmaJpeg | null } };
export const FIRMAS_VACIAS: FirmasLocal = { auditor: null, representante: { estado: "sin_representante", nombre: "", imagen: null } };

export function FirmasActa({ valor, onCambio, deshabilitado }: { valor: FirmasLocal; onCambio: (v: FirmasLocal) => void; deshabilitado: boolean }) {
  const [pad, setPad] = useState<"auditor" | "representante" | null>(null);
  const rep = valor.representante;
  const ponerRep = (p: Partial<FirmasLocal["representante"]>) => onCambio({ ...valor, representante: { ...rep, ...p } });

  if (pad) return (
    <FirmaPad titulo={pad === "auditor" ? "Firma del auditor de la interventoría" : "Firma del representante del operador"} onCancelar={() => setPad(null)}
      onAceptar={(f) => { onCambio(pad === "auditor" ? { ...valor, auditor: f } : { ...valor, representante: { ...rep, imagen: f } }); setPad(null); }} />
  );
  return (
    <fieldset className="campo-fieldset" disabled={deshabilitado}>
      <legend className="campo-etiqueta">Firmas del acta</legend>
      <div className="campo-campo">
        <span className="campo-etiqueta">Auditor de la interventoría <small>(obligatoria)</small></span>
        {valor.auditor ? (
          <div className="aseo-firma-mini"><img src={valor.auditor.url} alt="Firma del auditor" /><button type="button" className="tec-boton-sec" onClick={() => setPad("auditor")}>Volver a firmar</button></div>
        ) : <button type="button" className="tec-boton campo-boton-foto" onClick={() => setPad("auditor")}>Agregar firma</button>}
        <small className="campo-sub">Quedan en el acta su nombre, su cargo y la fecha y hora del servidor. Es una firma electrónica simple; al registrar queda definitiva.</small>
      </div>
      <div className="campo-campo">
        <span className="campo-etiqueta">Representante del operador de aseo <small>(opcional)</small></span>
        <div className="aseo-opciones" role="radiogroup" aria-label="Representante del operador">
          {(["firmo", "se_nego", "sin_representante"] as const).map((e) => (
            <label key={e} className={`aseo-opcion${rep.estado === e ? " aseo-opcion-on" : ""}`}>
              <input type="radio" name="rep_estado" value={e} checked={rep.estado === e} onChange={() => ponerRep({ estado: e, ...(e !== "firmo" ? { imagen: null } : {}), ...(e === "sin_representante" ? { nombre: "" } : {}) })} />
              {e === "firmo" ? "Firma" : ROTULO_REPRESENTANTE[e]}</label>))}
        </div>
        {rep.estado !== "sin_representante" ? (
          <div className="campo-campo"><label className="campo-etiqueta" htmlFor="aseo-rep-nombre">Nombre del representante{rep.estado === "se_nego" ? <small> (si lo dio)</small> : null}</label>
            <input id="aseo-rep-nombre" className="aseo-entrada" value={rep.nombre} maxLength={120} autoComplete="off" onChange={(e) => ponerRep({ nombre: e.target.value })} /></div>
        ) : null}
        {rep.estado === "firmo" ? (rep.imagen
          ? <div className="aseo-firma-mini"><img src={rep.imagen.url} alt="Firma del representante" /><button type="button" className="tec-boton-sec" onClick={() => setPad("representante")}>Volver a firmar</button></div>
          : <button type="button" className="tec-boton campo-boton-foto" onClick={() => setPad("representante")}>Agregar firma del representante</button>) : null}
      </div>
    </fieldset>
  );
}
