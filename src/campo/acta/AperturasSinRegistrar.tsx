import { useCallback, useEffect, useState } from "react";
import "./acta.css";
import { avisoDeError, ErrorCampo } from "../apiCampo";
import { fechaHora } from "../formato";
import { apiActa } from "./apiActa";
import { PanelCancelarActa } from "./PanelCancelarActa";
import type { MotivoCancelacion } from "../../components/ConfirmarCancelar";
import type { AperturasSinRegistrar as Datos, FilaApertura } from "./tipos";

// Pantalla mínima de la supervisión (supervisor y administrador): los consecutivos del acta de inspección entregados que NO se registraron (en curso o caducados) y, con el filtro
// «Ver cancelados», los que ya se cancelaron con su motivo. Permite cancelar los colgados de otras personas (el servidor decide el permiso). No es el tablero de actas: no lista las registradas.
const TEXTO: Record<FilaApertura["situacion"], string> = { abierta_en_curso: "En curso", abierta_vencida_sin_registrar: "Caducó sin registrar", cancelada: "Cancelada" };

/** `incrustada`: dentro de la entrada «Actas registradas» (Comercial 21-nov, B2), como pestaña: sin página propia ni «Volver». */
export function AperturasSinRegistrar({ onVolver, incrustada = false }: { onVolver: () => void; incrustada?: boolean }) {
  const [verCancelados, setVerCancelados] = useState(false);
  const [datos, setDatos] = useState<Datos | null>(null);
  const [motivos, setMotivos] = useState<MotivoCancelacion[] | null>(null);
  const [error, setError] = useState<ErrorCampo | null>(null);
  const [cargando, setCargando] = useState(true);
  const [cancelando, setCancelando] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);

  useEffect(() => {
    let vivo = true;
    setCargando(true); setError(null);
    Promise.all([apiActa.aperturasSinRegistrar(verCancelados), apiActa.motivosCancelacion().then((r) => r.motivos, () => null)])
      .then(([d, m]) => { if (vivo) { setDatos(d); setMotivos(m); } })
      .catch((e) => { if (vivo) setError(e instanceof ErrorCampo ? e : new ErrorCampo("servidor", "No se pudo cargar.", 0)); })
      .finally(() => { if (vivo) setCargando(false); });
    return () => { vivo = false; };
  }, [verCancelados, intento]);
  const recargar = useCallback(() => setIntento((i) => i + 1), []);

  const cuerpo = (
      <section className="tec-tarjeta">
        {incrustada ? <h2>Aperturas sin registrar</h2> : <div className="campo-cab">
          <h1>Aperturas sin registrar</h1>
          <button type="button" className="tec-boton-sec" onClick={onVolver}>Volver</button>
        </div>}
        <p className="campo-sub">Consecutivos del acta de inspección que se entregaron y no llegaron a registrarse. Cancelar un registro deja el consecutivo justificado (motivo, quién y cuándo); no se borra nada.</p>
        <label className="campo-check">
          <input type="checkbox" checked={verCancelados} onChange={(e) => setVerCancelados(e.target.checked)} />
          <span><strong>Ver cancelados</strong></span>
        </label>
        {datos && <p className="campo-sub" role="status">En curso: {datos.resumen.en_curso} · Caducadas sin registrar: {datos.resumen.vencidas} · Canceladas: {datos.resumen.canceladas}</p>}
        <button type="button" className="tec-boton-sec" onClick={recargar} disabled={cargando}>{cargando ? "Actualizando…" : "Actualizar"}</button>
        {error && (
          <p className="campo-error" role="alert">{error.tipo === "permiso" || error.tipo === "denegado" ? "Su cuenta no tiene acceso a esta pantalla." : avisoDeError(error).texto}</p>
        )}
        {datos && datos.filas.length === 0 && !error && <p className="campo-sub">No hay aperturas {verCancelados ? "" : "pendientes "}para mostrar.</p>}
        <ul className="acta-lista">
          {datos?.filas.map((f) => (
            <li key={f.acta_id} className="acta-tarjeta">
              <p className="acta-consecutivo-chico"><strong>{f.consecutivo}</strong> · {TEXTO[f.situacion]}</p>
              <p className="campo-sub">Abrió {f.autor} el {fechaHora(f.abierto_en)}{f.situacion === "abierta_en_curso" ? ` · vence el ${fechaHora(f.vence_en)}` : ""}</p>
              {f.situacion === "cancelada" ? (
                <p className="campo-sub">Cancelada el {f.cancelada_en ? fechaHora(f.cancelada_en) : "—"} por {f.cancelada_por ?? "—"} · Motivo: {f.motivo_nombre ?? f.motivo_cancelacion}{f.motivo_texto ? ` — ${f.motivo_texto}` : ""}</p>
              ) : cancelando === f.acta_id ? (
                <PanelCancelarActa actaId={f.acta_id} consecutivo={f.consecutivo} contrato="" motivos={motivos}
                  onHecho={() => { setCancelando(null); recargar(); }} onSeguir={() => setCancelando(null)} />
              ) : (
                <button type="button" className="btn-cancelar" onClick={() => setCancelando(f.acta_id)}>Cancelar</button>
              )}
            </li>
          ))}
        </ul>
        {datos && datos.filas.length >= datos.max_filas && <p className="campo-sub">Se muestran las {datos.max_filas} más recientes.</p>}
      </section>
  );
  return incrustada ? cuerpo : <div className="tec-pagina campo-pagina">{cuerpo}</div>;
}
