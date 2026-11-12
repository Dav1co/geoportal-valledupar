import { useMemo, useState } from "react";
import "./formatos.css";
import type { FormularioCampo } from "../apiCampo";
import { formatosDisponibles, type TipoFormato } from "./tipos";
import { FormularioFormato } from "./FormularioFormato";

// Punto de entrada de los formatos del Paso D: selector de formato y, al elegir uno, su formulario. Los formatos salen del catálogo (`formulario`); si el servidor no trae ninguno
// (los formatos nacen inactivos hasta que el administrador los activa), se dice con claridad y no se rompe nada.
export function FormatosCampo({ def, correo, onVolver, puedeActa = false, onAbrirActa }: { def: FormularioCampo; correo: string; onVolver: () => void; puedeActa?: boolean; onAbrirActa?: (contrato: string) => void }) {
  const grupos = useMemo(() => formatosDisponibles(def.grupos), [def]);
  const [codigo, setCodigo] = useState<string | null>(null);
  const [version, setVersion] = useState(0);                    // sube con «Hacer otro»: el formulario nace limpio
  const elegido: TipoFormato | null = useMemo(() => grupos.flatMap((g) => g.tipos).find((t) => t.codigo === codigo) ?? null, [grupos, codigo]);

  if (elegido) {
    return <FormularioFormato key={`${elegido.codigo}-${version}`} def={def} tipo={elegido} correo={correo} onVolver={() => setCodigo(null)} onOtro={() => { setVersion((v) => v + 1); }} puedeActa={puedeActa} onAbrirActa={onAbrirActa} />;
  }

  return (
    <div className="tec-pagina campo-pagina">
      <section className="tec-tarjeta">
        <div className="campo-cab">
          <button type="button" className="tec-boton-sec tec-boton-corto" onClick={onVolver}>← Formatos</button>
          <h1>Formatos de actividad</h1>
        </div>
        {grupos.length === 0 ? (
          <p className="campo-sub" role="status">Por ahora no hay formatos de actividad disponibles para usted. Cuando el administrador los active, aparecerán aquí.</p>
        ) : (
          grupos.map(({ grupo, tipos }) => (
            <div key={grupo.codigo} className="campo-grupo-formatos">
              <h2 className="campo-grupo-titulo">{grupo.nombre}</h2>
              <div className="campo-formatos">
                {tipos.map((t) => (
                  <button key={t.codigo} type="button" className="campo-formato campo-formato-activo" onClick={() => setCodigo(t.codigo)} disabled={!def.puede.reportar}>
                    <strong>{t.nombre}</strong>
                    <span>{resumenFormato(t)}</span>
                  </button>
                ))}
              </div>
            </div>
          ))
        )}
      </section>
    </div>
  );
}

function resumenFormato(t: TipoFormato): string {
  const partes: string[] = [];
  const min = t.fotos_min ?? 1, max = t.fotos_max;
  partes.push(max !== undefined && max !== min ? `${min} a ${max} fotos` : `${min} foto${min === 1 ? "" : "s"}`);
  if (t.genera_resultado) partes.push("efectiva o inefectiva");
  if (t.usa_consecutivo) partes.push("con consecutivo");
  return partes.join(" · ");
}
