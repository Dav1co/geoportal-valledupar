import { useRef, useState } from "react";
import { AvisoSinAgua } from "../AvisoSinAgua";
import "./acta.css";
import { avisoDeError, ErrorCampo } from "../apiCampo";
import { apiActa } from "./apiActa";
import { CONTRATO_OK, etiquetaEstrato } from "./logica";
import type { Precarga, PrediosCercanos } from "./tipos";

// Identificación del predio: «con contrato» (se verifica contra el catastro ANTES de abrir el registro: verificar no consume consecutivo) o «sin contrato» (posible conexión clandestina:
// dirección y barrio se escriben a mano y NO se envía contrato). Del catastro solo se precarga dirección, barrio, estrato y uso; nunca nombre ni documento.
// Estratos 0, 9, 99… se muestran tal cual con la etiqueta «código no estándar», sin interpretarlos. El servidor limita las consultas (429) y vuelve a validar el contrato al registrar.

export function IdentificarPredio({ modo, contrato, bloqueado, onModo, onContrato, precarga, onPrecarga, opcional, ubicacion }: {
  modo: "con_contrato" | "sin_contrato"; contrato: string; bloqueado?: boolean;
  onModo: (m: "con_contrato" | "sin_contrato") => void; onContrato: (c: string) => void;
  precarga: Precarga | null; onPrecarga: (p: Precarga, contrato: string) => void;
  /** En el formulario ya abierto la verificación es opcional (la precarga rellena dirección, barrio, estrato y uso). */
  opcional?: boolean;
  /** Coordenada actual, para sugerir contratos cercanos cuando el predio no tiene contrato. */
  ubicacion?: { lat: number; lon: number } | null;
}) {
  const [verificando, setVerificando] = useState(false);
  const [mensaje, setMensaje] = useState<{ texto: string; error: boolean } | null>(null);
  const [cercanos, setCercanos] = useState<PrediosCercanos | null>(null);
  const bloqueo = useRef(false);

  function mostrarError(e: unknown) {
    const err = e instanceof ErrorCampo ? e : new ErrorCampo("servidor", "No se pudo completar la consulta.", 0);
    setMensaje({ texto: err.tipo === "validacion" || err.tipo === "limite" ? err.message : avisoDeError(err).texto, error: true });
  }
  async function verificar() {
    const c = contrato.trim();
    if (bloqueo.current) return;
    if (!CONTRATO_OK.test(c)) { setMensaje({ texto: "El contrato solo puede llevar letras, números y guiones (máximo 20).", error: true }); return; }
    bloqueo.current = true; setVerificando(true); setMensaje(null);
    try {
      const p = await apiActa.precargar(c);
      if (!p.existe) { setMensaje({ texto: "Ese contrato no existe: corríjalo o registre el predio como «sin contrato». No se abre ningún registro con un contrato inexistente.", error: true }); return; }
      onPrecarga(p, c);
      setMensaje({ texto: (p.predios_con_ese_contrato ?? 1) > 1 ? `El contrato existe y tiene ${p.predios_con_ese_contrato} predios en el catastro: revise la dirección.` : "El contrato existe. Revise que la dirección sea la del predio.", error: false });
    } catch (e) {
      mostrarError(e);
    } finally {
      bloqueo.current = false; setVerificando(false);
    }
  }
  async function buscarCercanos() {
    if (!ubicacion || bloqueo.current) return;
    bloqueo.current = true; setVerificando(true); setMensaje(null);
    try { setCercanos(await apiActa.prediosCercanos(ubicacion.lat, ubicacion.lon)); } catch (e) { mostrarError(e); } finally { bloqueo.current = false; setVerificando(false); }
  }

  return (
    <div className="acta-predio">
      <fieldset className="acta-sino" disabled={bloqueado}>
        <legend className="campo-etiqueta">Identificación del predio</legend>
        <label className="acta-radio"><input type="radio" name="acta-modo" checked={modo === "con_contrato"} onChange={() => onModo("con_contrato")} /> <span>Con contrato</span></label>
        <label className="acta-radio"><input type="radio" name="acta-modo" checked={modo === "sin_contrato"} onChange={() => { onModo("sin_contrato"); setMensaje(null); }} /> <span>Sin contrato (posible conexión clandestina)</span></label>
      </fieldset>

      {modo === "con_contrato" && (
        <div className="acta-campo">
          <label className="campo-etiqueta" htmlFor="acta-contrato">Número de contrato</label>
          <div className="acta-fila">
            <input id="acta-contrato" className="acta-input" type="text" inputMode="numeric" autoComplete="off" maxLength={20} value={contrato} disabled={bloqueado}
              onChange={(e) => { onContrato(e.target.value.replace(/[^A-Za-z0-9-]/g, "")); setMensaje(null); }} />
            <button type="button" className="tec-boton" onClick={() => void verificar()} disabled={bloqueado || verificando || contrato.trim() === ""}>{verificando ? "Buscando…" : opcional ? "Precargar" : "Verificar"}</button>
          </div>
          {/* contrato verificado: si el predio está en un evento de suspensión activo, se avisa (solo informa) */}
          {precarga?.existe ? <AvisoSinAgua contrato={contrato} espera={0} /> : null}
          {precarga?.existe && (
            <dl className="campo-auto">
              <div><dt>Dirección</dt><dd>{precarga.direccion ?? "Sin dato"}</dd></div>
              <div><dt>Barrio</dt><dd>{precarga.barrio ?? "Sin dato"}{precarga.barrio_en_lista === false ? " (no está en la lista de barrios)" : ""}</dd></div>
              <div><dt>Estrato</dt><dd>{etiquetaEstrato(precarga.estrato, precarga.estrato_codigo_no_estandar)}</dd></div>
              <div><dt>Uso</dt><dd>{precarga.uso ?? "Sin dato"}</dd></div>
            </dl>
          )}
        </div>
      )}

      {modo === "sin_contrato" && (
        <>
          <p className="campo-sub">Sin contrato: la dirección y el barrio se escriben a mano en el formulario y no se envía número de contrato.</p>
          {ubicacion && !opcional && (
            <>
              <button type="button" className="tec-boton-sec" onClick={() => void buscarCercanos()} disabled={bloqueado || verificando}>{verificando ? "Buscando…" : "¿Hay un contrato cercano?"}</button>
              {cercanos && (cercanos.hay_predios_cercanos
                ? <div className="acta-chips" role="group" aria-label="Contratos cercanos">
                    <p className="campo-sub">Contratos a menos de {Math.round(cercanos.distancia_m)} m. Si el predio es uno de ellos, tóquelo:</p>
                    {cercanos.contratos.map((c) => <button key={c} type="button" className="tec-boton-sec acta-chip" onClick={() => { onModo("con_contrato"); onContrato(c); setCercanos(null); }}>{c}</button>)}
                  </div>
                : <p className="campo-sub">No hay contratos a menos de {Math.round(cercanos.distancia_m)} m.</p>)}
            </>
          )}
        </>
      )}
      {mensaje && <p className={mensaje.error ? "campo-error" : "campo-nota"} role={mensaje.error ? "alert" : "status"}>{mensaje.texto}</p>}
    </div>
  );
}
