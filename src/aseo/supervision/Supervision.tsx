import { useCallback, useEffect, useState } from "react";
import "../../tecnica/dashboard.css";
import "./supervision.css";
import { apiSup, textoError, type Resumen as ResumenT } from "./api";
import { Auditorias } from "./Auditorias";
import { ErrorCaja } from "./comun";
import { Indicadores } from "./Indicadores";
import { PersonalAseo } from "./PersonalAseo";
import { Resumen } from "./Resumen";
import type { FormularioAseo } from "../tipos";

// «Supervisión y dashboard» de Aseo (supervisor y administrador): mismo cascarón que el Dashboard técnico (cabecera, pestañas, secciones registradas). El trabajo del supervisor se llama siempre «revisión».
// Secciones: Resumen, Auditorías, No conformidades, Indicadores y Personal. Las que aún no existen se mostrarían deshabilitadas, sin datos de ejemplo. El servidor vuelve a verificar el permiso en cada ruta.
type Clave = "resumen" | "auditorias" | "nc" | "indicadores" | "personal";
const SECCIONES: { clave: Clave; titulo: string }[] = [{ clave: "resumen", titulo: "Resumen" }, { clave: "auditorias", titulo: "Auditorías" }, { clave: "nc", titulo: "No conformidades" }, { clave: "indicadores", titulo: "Indicadores" }, { clave: "personal", titulo: "Personal" }];

export function Supervision({ def, correo, onVolver }: { def: FormularioAseo; correo: string; onVolver: () => void }) {
  const [activa, setActiva] = useState<Clave>("resumen"); const [abrir, setAbrir] = useState<string | null>(null);
  const [cat, setCat] = useState<Pick<ResumenT, "turnos" | "auditores">>({ turnos: [], auditores: [] });
  const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null); const [intento, setIntento] = useState(0);
  useEffect(() => { let vivo = true; setError(null); apiSup.resumen(1).then((r) => { if (vivo) setCat({ turnos: r.turnos, auditores: r.auditores }); }).catch((e) => { if (vivo) setError(textoError(e)); }); return () => { vivo = false; }; }, [intento]);
  const datos = useCallback((r: ResumenT) => setCat({ turnos: r.turnos, auditores: r.auditores }), []);
  const rotulo = def.perfil === "admin" ? "Administrador" : "Supervisor de aseo";
  return (
    <div className="tdash aseo-modulo">
      <div className="tdash-cab"><div className="tdash-ancho">
        <div className="tdash-fila"><h1>Supervisión y dashboard</h1><button type="button" className="td-boton-claro" onClick={onVolver}>← Volver al inicio</button></div>
        <div className="tdash-sesion">{correo} · {rotulo}</div>
        <nav className="tdash-tabs" aria-label="Secciones de Supervisión y dashboard">
          {SECCIONES.map((s) => <button key={s.clave} type="button" className="tdash-tab" aria-current={activa === s.clave ? "page" : undefined} onClick={() => { setActiva(s.clave); setAbrir(null); }}>{s.titulo}</button>)}
        </nav></div></div>
      <div className="tdash-cuerpo">
        {error && activa !== "resumen" && activa !== "personal" ? <ErrorCaja error={error} onReintentar={() => setIntento((x) => x + 1)} /> : null}
        {activa === "resumen" ? <Resumen onAbrir={(id) => { setAbrir(id); setActiva("nc"); }} onDatos={datos} /> : null}
        {activa === "auditorias" ? <Auditorias def={def} cat={cat} modo="todas" /> : null}
        {activa === "nc" ? <Auditorias key={abrir ?? "nc"} def={def} cat={cat} modo="nc" inicial={abrir ?? undefined} /> : null}
        {activa === "indicadores" ? <Indicadores def={def} cat={cat} /> : null}
        {activa === "personal" ? <PersonalAseo /> : null}
      </div>
    </div>
  );
}
