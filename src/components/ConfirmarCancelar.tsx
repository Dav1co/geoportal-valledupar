import { useEffect, useRef, useState } from "react";
import "./confirmar.css";

// Panel en línea para CANCELAR un registro en curso (todos los formularios de campo, Aseo y Técnica). No es un cuadro del navegador: se queda dentro de la página, con el foco en el título,
// «Esc» = seguir editando, botones de al menos 48 px y pensado para 380 px. Dos variantes:
//  - sin `motivos`: se descarta lo que está en el teléfono (no hay nada en el servidor);
//  - con `motivos`: hay un consecutivo entregado, así que el motivo (del catálogo del servidor) es obligatorio, y el texto solo si el motivo lo exige («Otro»).
// `destinos` (opcional) ofrece «Me equivoqué de formulario»: pasar a otro formulario llevando SOLO el contrato (no se trasladan fotos ni texto).

export type MotivoCancelacion = { codigo: string; nombre: string; exige_texto: boolean };
export type Destino = { id: string; rotulo: string };
export const MOTIVO_EQUIVOCACION = "equivocacion_formulario";
export const MIN_TEXTO_MOTIVO = 10;

export function ConfirmarCancelar({ titulo, mensaje, motivos, rotuloConfirmar = "Sí, cancelar", rotuloSeguir = "Seguir editando", ocupado = false, error = null, destinos, onIrA, onConfirmar, onSeguir }: {
  titulo: string; mensaje: string; motivos?: MotivoCancelacion[] | null; rotuloConfirmar?: string; rotuloSeguir?: string; ocupado?: boolean; error?: string | null;
  destinos?: Destino[]; onIrA?: (destino: string, motivo: { codigo: string; texto: string } | null) => void;
  onConfirmar: (motivo: { codigo: string; texto: string } | null) => void; onSeguir: () => void;
}) {
  const [codigo, setCodigo] = useState("");
  const [texto, setTexto] = useState("");
  const raiz = useRef<HTMLDivElement>(null);
  const refTitulo = useRef<HTMLHeadingElement>(null);
  const conMotivo = motivos !== undefined;
  const elegido = motivos?.find((m) => m.codigo === codigo) ?? null;
  const textoOk = !elegido?.exige_texto || texto.trim().length >= MIN_TEXTO_MOTIVO;
  const puede = !ocupado && (!conMotivo || (elegido !== null && textoOk));

  useEffect(() => { refTitulo.current?.focus(); raiz.current?.scrollIntoView?.({ block: "nearest" }); }, []);
  useEffect(() => {
    const f = (e: KeyboardEvent) => { if (e.key === "Escape" && !ocupado) onSeguir(); };
    window.addEventListener("keydown", f);
    return () => window.removeEventListener("keydown", f);
  }, [ocupado, onSeguir]);

  return (
    <div className="conf-canc" role="alertdialog" aria-labelledby="conf-canc-tit" aria-describedby="conf-canc-msg" ref={raiz}>
      <h2 id="conf-canc-tit" ref={refTitulo} tabIndex={-1}>{titulo}</h2>
      <p id="conf-canc-msg" className="conf-canc-msg">{mensaje}</p>
      {conMotivo ? (
        motivos === null || motivos.length === 0 ? (
          <p className="conf-canc-error" role="alert">No se pudo cargar la lista de motivos: cancelar este registro necesita la actualización del servidor (SQL/Edge), que aún no está aplicada, o falló la conexión. Cierre este aviso y vuelva a intentarlo.</p>
        ) : (
          <>
            <label className="conf-canc-etq" htmlFor="conf-canc-motivo">Motivo</label>
            <select id="conf-canc-motivo" className="conf-canc-entrada" value={codigo} disabled={ocupado} onChange={(e) => setCodigo(e.target.value)}>
              <option value="">Elija el motivo…</option>
              {motivos.map((m) => <option key={m.codigo} value={m.codigo}>{m.nombre}</option>)}
            </select>
            {elegido?.exige_texto && (
              <>
                <label className="conf-canc-etq" htmlFor="conf-canc-texto">Escriba cuál (mínimo {MIN_TEXTO_MOTIVO} caracteres)</label>
                <textarea id="conf-canc-texto" className="conf-canc-entrada conf-canc-area" value={texto} maxLength={1000} disabled={ocupado} onChange={(e) => setTexto(e.target.value)} />
              </>
            )}
          </>
        )
      ) : null}
      {error && <p className="conf-canc-error" role="alert">{error}</p>}
      {destinos && destinos.length > 0 && onIrA && (!conMotivo || codigo === MOTIVO_EQUIVOCACION) && (
        <div className="conf-canc-destinos">
          <p className="conf-canc-msg">¿Se equivocó de formulario? {conMotivo ? "Cancele y abra el correcto" : "Pase al correcto"}: solo se lleva el contrato; las fotos y lo escrito no se trasladan.</p>
          {destinos.map((d) => (
            <button key={d.id} type="button" className="tec-boton-sec conf-canc-boton" disabled={ocupado || (conMotivo && !puede)} onClick={() => onIrA(d.id, conMotivo && elegido ? { codigo: elegido.codigo, texto: texto.trim() } : null)}>
              {conMotivo ? `Cancelar e ir a «${d.rotulo}»` : `Ir a «${d.rotulo}»`}
            </button>
          ))}
        </div>
      )}
      <div className="conf-canc-acciones">
        <button type="button" className="tec-boton conf-canc-boton conf-canc-peligro" disabled={!puede} aria-busy={ocupado} onClick={() => onConfirmar(conMotivo && elegido ? { codigo: elegido.codigo, texto: texto.trim() } : null)}>
          {ocupado ? "Cancelando…" : rotuloConfirmar}
        </button>
        <button type="button" className="tec-boton-sec conf-canc-boton" disabled={ocupado} onClick={onSeguir}>{rotuloSeguir}</button>
      </div>
    </div>
  );
}
