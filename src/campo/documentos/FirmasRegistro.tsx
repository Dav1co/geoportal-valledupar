import { useState } from "react";
import { FirmaPad } from "../../aseo/FirmaPad";
import type { FirmaJpeg } from "../../aseo/firmas";
import type { EstadoUsuario, ReglasFirmas } from "./apiDocumentos";
import { efectivo, ESTADO_TEXTO, testigoNombre, type FirmasLocal, type FuenteFormulario } from "./firmasLogica";
import "./documentos.css";

// Sección «Firmas» de los formularios con valor probatorio (Comercial 21-nov; B4 y B5 de David). Usa el momento dedicado de Aseo (FirmaPad y firmas.ts, sin cambiarlos):
// Limpiar, Cancelar y OK; la firma queda como miniatura y se puede repetir hasta registrar; al registrar queda definitiva. La del operario es obligatoria; la del usuario y la
// del testigo, opcionales. Lo que el formulario ya pregunta (firma_atendio, atendio_nombre) no se vuelve a preguntar aquí.
type Pad = "operario" | "usuario" | "testigo";
const TITULO: Record<Pad, string> = { operario: "Firma del operario de EMDUPAR", usuario: "Firma del usuario (quien atendió)", testigo: "Firma del testigo" };

function Mini({ f, alt, onRepetir, texto }: { f: FirmaJpeg | null; alt: string; onRepetir: () => void; texto: string }) {
  return f ? <div className="doc-firma-mini"><img src={f.url} alt={alt} /><button type="button" className="tec-boton-sec" onClick={onRepetir}>Volver a firmar</button></div>
    : <button type="button" className="tec-boton campo-boton-foto" onClick={onRepetir}>{texto}</button>;
}

export function FirmasRegistro({ reglas, valor, onCambio, fuente, deshabilitado, nombreOperario }: {
  reglas: ReglasFirmas; valor: FirmasLocal; onCambio: (v: FirmasLocal) => void; fuente: FuenteFormulario; deshabilitado: boolean; nombreOperario?: string;
}) {
  const [pad, setPad] = useState<Pad | null>(null);
  const { estado, nombre } = efectivo(valor, fuente);
  const ponerUsuario = (p: Partial<FirmasLocal["usuario"]>) => onCambio({ ...valor, usuario: { ...valor.usuario, ...p } });
  const ponerTestigo = (p: Partial<FirmasLocal["testigo"]>) => onCambio({ ...valor, testigo: { ...valor.testigo, ...p } });

  if (pad) return (
    <div className="com-modulo doc-firma-envoltura">
      <FirmaPad titulo={TITULO[pad]} onCancelar={() => setPad(null)}
        onAceptar={(f) => { onCambio(pad === "operario" ? { ...valor, operario: f } : pad === "usuario" ? { ...valor, usuario: { ...valor.usuario, imagen: f } } : { ...valor, testigo: { ...valor.testigo, imagen: f } }); setPad(null); }} />
    </div>
  );
  return (
    <fieldset className="campo-fieldset doc-firmas" disabled={deshabilitado} data-testid="firmas">
      <legend className="campo-etiqueta">Firmas</legend>
      {reglas.operario !== "no" ? (
        <div className="doc-firma-bloque" data-firma="operario">
          <span className="campo-etiqueta">Operario de EMDUPAR {reglas.operario === "obligatoria" ? <small>(obligatoria para registrar)</small> : <small>(opcional)</small>}</span>
          <Mini f={valor.operario} alt="Firma del operario" onRepetir={() => setPad("operario")} texto="Agregar mi firma" />
          <small className="campo-sub">Quedan en el acta {nombreOperario ? `su nombre (${nombreOperario})` : "su nombre"} y la fecha y hora del servidor. Es una firma electrónica simple; al registrar queda definitiva.</small>
        </div>) : null}
      {reglas.usuario !== "no" ? (
        <div className="doc-firma-bloque" data-firma="usuario">
          <span className="campo-etiqueta">Usuario (quien atendió) <small>({reglas.usuario === "obligatoria" ? "obligatoria" : "opcional"})</small></span>
          {fuente.estado !== undefined ? (
            <p className="campo-sub" data-dato="estado-usuario">{estado ? <>Según «Firma de quien atendió»: <strong>{ESTADO_TEXTO[estado]}</strong>.</> : "Responda «Firma de quien atendió» en el formulario."}</p>
          ) : (
            <div className="doc-opciones" role="radiogroup" aria-label="¿Firmó el usuario?">
              {(["firmo", "no_firmo", "nadie_atendio"] as EstadoUsuario[]).map((e) => (
                <label key={e} className={`doc-opcion${valor.usuario.estado === e ? " doc-opcion-on" : ""}`}>
                  <input type="radio" name="doc-usuario-estado" value={e} checked={valor.usuario.estado === e} data-estado={e}
                    onChange={() => ponerUsuario({ estado: e, ...(e !== "firmo" ? { imagen: null } : {}) })} />{ESTADO_TEXTO[e]}</label>))}
            </div>)}
          {estado === "firmo" ? <>
            {fuente.nombre !== undefined ? <p className="campo-sub">Firma: <strong>{nombre || "(escriba el nombre de quien atendió en el formulario)"}</strong></p>
              : <div className="tec-campo"><label htmlFor="doc-usuario-nombre">Nombre de quien firma</label>
                <input id="doc-usuario-nombre" value={valor.usuario.nombre} maxLength={120} autoComplete="off" onChange={(e) => ponerUsuario({ nombre: e.target.value })} /></div>}
            <Mini f={valor.usuario.imagen} alt="Firma del usuario" onRepetir={() => setPad("usuario")} texto="Agregar la firma del usuario" />
          </> : null}
        </div>) : null}
      {estado === "no_firmo" && reglas.testigo !== "no" ? (
        <div className="doc-firma-bloque" data-firma="testigo">
          <span className="campo-etiqueta">Testigo <small>(opcional)</small></span>
          <small className="campo-sub">Si el usuario no quiso firmar, puede firmar un testigo con su nombre.</small>
          {fuente.testigoNombre !== undefined ? <p className="campo-sub">Testigo: <strong>{testigoNombre(valor, fuente) || "(escriba el nombre del testigo en el acta)"}</strong></p>
            : <div className="tec-campo"><label htmlFor="doc-testigo-nombre">Nombre del testigo</label>
            <input id="doc-testigo-nombre" value={valor.testigo.nombre} maxLength={120} autoComplete="off" onChange={(e) => ponerTestigo({ nombre: e.target.value })} /></div>}
          <Mini f={valor.testigo.imagen} alt="Firma del testigo" onRepetir={() => setPad("testigo")} texto="Agregar la firma del testigo" />
        </div>) : null}
    </fieldset>
  );
}
