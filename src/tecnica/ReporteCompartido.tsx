import { useEffect, useMemo, useState } from "react";
import { apiCampo, avisoDeError, ErrorCampo, type FormularioCampo } from "../campo/apiCampo";
import { fijarAreaCampo } from "../campo/area";
import { ReporteGeneral } from "../campo/ReporteGeneral";
import { FormularioFormato } from "../campo/formatos/FormularioFormato";
import type { TipoFormato } from "../campo/formatos/tipos";
import "../campo/formatos/formatos.css";

// Técnica fase 1, Corte 8 (§10 y §30.3 de la bitácora): «Reportar anomalía» y «Revisiones generales» desde Técnica.
// NO es otro formulario: monta las MISMAS pantallas de Comercial (ReporteGeneral y FormularioFormato), que hablan con la misma Edge (geoportal-campo) y guardan en
// las mismas tablas. Lo único propio es que, mientras esta pantalla está abierta, las peticiones llevan el área «tecnica»: la base autoriza por el formulario de
// Técnica, entrega solo los tipos que corresponden (el mismo catálogo) y el reporte guarda su área.
export function ReporteCompartido({ formulario, correo, onVolver }: { formulario: "anomalia_compartida" | "revision_compartida"; correo: string; onVolver: () => void }) {
  const [def, setDef] = useState<FormularioCampo | null>(null);
  const [error, setError] = useState<ErrorCampo | null>(null);
  const [intento, setIntento] = useState(0);
  const [version, setVersion] = useState(0);      // sube con «Hacer otro»: la pantalla nace limpia

  useEffect(() => {
    let vivo = true;
    fijarAreaCampo("tecnica");
    setDef(null); setError(null);
    apiCampo.formulario()
      .then((d) => { if (vivo) setDef(d); })
      .catch((e) => { if (vivo) setError(e instanceof ErrorCampo ? e : new ErrorCampo("servidor", "No se pudo cargar.", 0)); });
    return () => { vivo = false; fijarAreaCampo(null); };
  }, [intento]);

  const revision: TipoFormato | null = useMemo(
    () => (def?.grupos.flatMap((g) => g.tipos as TipoFormato[]).find((t) => t.codigo === "revision_previa" && t.activo) ?? null), [def]);

  if (error) {
    const a = avisoDeError(error);
    return (
      <section className="tec-tarjeta" role="alert">
        <p><strong>{error.tipo === "permiso" ? "No tiene asignado este formulario en Técnica." : a.texto}</strong></p>
        {error.tipo !== "permiso" ? <button type="button" className="tec-boton" onClick={() => setIntento((i) => i + 1)}>Reintentar</button> : null}
        <button type="button" className="tec-boton-sec" onClick={onVolver}>Volver</button>
      </section>
    );
  }
  if (!def) return <p className="tec-sub" role="status" style={{ padding: 16 }}>Cargando el formulario…</p>;

  if (formulario === "anomalia_compartida") {
    return <ReporteGeneral key={version} def={def} correo={correo} onVolver={onVolver} onOtro={() => setVersion((v) => v + 1)} />;
  }
  if (!revision) {
    return (
      <section className="tec-tarjeta" role="status">
        <p><strong>«Revisiones generales» no está activa en el catálogo.</strong></p>
        <button type="button" className="tec-boton-sec" onClick={onVolver}>Volver</button>
      </section>
    );
  }
  return <FormularioFormato key={version} def={def} tipo={revision} correo={correo} onVolver={onVolver} onOtro={() => setVersion((v) => v + 1)} />;
}
