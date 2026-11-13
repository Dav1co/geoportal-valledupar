import { useState } from "react";
import { ConfirmarCancelar, type Destino, type MotivoCancelacion } from "../../components/ConfirmarCancelar";
import { avisoDeError, ErrorCampo } from "../apiCampo";
import { apiActa } from "./apiActa";
import { almacenActa } from "./almacenActa";

// Cancelar una apertura del acta de inspección (consecutivo ya entregado): motivo obligatorio del catálogo, evento «cancelado» en el servidor y, solo si salió bien, se descarta el borrador y las fotos del teléfono.
// Sirve a la tarjeta de «Mis actas» y al formulario. Si se cortó la red NO se descarta nada: no se sabe si quedó cancelada.
export function PanelCancelarActa({ actaId, consecutivo, contrato, motivos, destinos, onIrA, onHecho, onSeguir }: {
  actaId: string; consecutivo: string; contrato: string; motivos: MotivoCancelacion[] | null; destinos?: Destino[];
  onIrA?: (destino: string, contrato: string) => void; onHecho: () => void; onSeguir: () => void;
}) {
  const [ocupado, setOcupado] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function cancelar(motivo: { codigo: string; texto: string } | null, destino?: string) {
    if (ocupado || !motivo) return;
    setOcupado(true); setError(null);
    try {
      await apiActa.cancelar(actaId, motivo.codigo, motivo.texto);
      almacenActa.quitar(actaId);                 // libera el borrador y las fotos de la memoria
      if (destino && onIrA) onIrA(destino, contrato); else onHecho();
    } catch (e) {
      const err = e instanceof ErrorCampo ? e : new ErrorCampo("servidor", "No se pudo cancelar.", 0);
      setError(err.tipo === "red"
        ? "No sabemos si se canceló (se cortó la conexión). Lo escrito y las fotos siguen aquí. Revise «Mis actas» o reintente."
        : err.tipo === "validacion" || err.tipo === "limite" || err.status === 409 ? err.message : avisoDeError(err).texto);
      setOcupado(false);
    }
  }

  return (
    <ConfirmarCancelar titulo={`¿Cancelar el registro ${consecutivo}?`}
      mensaje="El consecutivo ya fue entregado: queda justificado con el motivo, quién y cuándo (no se reutiliza ni se borra). Se descarta lo escrito y las fotos de este teléfono. Si ya lo escribió en un papel, táchelo."
      motivos={motivos} ocupado={ocupado} error={error} destinos={destinos}
      onIrA={onIrA ? (d, m) => void cancelar(m, d) : undefined}
      onConfirmar={(m) => void cancelar(m)} onSeguir={onSeguir} />
  );
}
