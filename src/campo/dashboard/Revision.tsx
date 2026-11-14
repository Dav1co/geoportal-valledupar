import { useCallback, useEffect, useState } from "react";
import "./revision.css";
import { apiRev, textoError, type FormularioRev } from "./apiRevision";
import { Reportes } from "./Reportes";
import { Indicadores } from "./Indicadores";
import { Parametros } from "./Parametros";
import { Catalogo } from "./Catalogo";
import { ConstanciasAdmin } from "../constancia/ConstanciasAdmin";
import { supabase } from "../../lib/supabase";

// «Supervisión y dashboard» (antes «Revisión de reportes», Paso C): pantalla del supervisor y del administrador de Formatos de campo. Se carga bajo demanda (React.lazy desde AreaCampo): quien no tiene el permiso no descarga este código.
// Qué se muestra lo decide el SERVIDOR (`puede` y `perfil` de «formulario»); aquí nunca hay listas de correos. Catálogo y Parámetros solo aparecen para el administrador.
type Seccion = "reportes" | "indicadores" | "catalogo" | "parametros";

export default function Revision({ correo, onVolver }: { correo: string; onVolver: () => void }) {
  const [def, setDef] = useState<FormularioRev | null>(null);
  const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [seccion, setSeccion] = useState<Seccion>("reportes");
  const [intento, setIntento] = useState(0);
  const cargar = useCallback((incluirInactivos: boolean) => apiRev.formulario(incluirInactivos).then(setDef), []);
  useEffect(() => {
    let vivo = true; setError(null);
    apiRev.formulario(false).then((d) => { if (vivo) setDef(d); }).catch((e) => { if (vivo) setError(textoError(e)); });
    return () => { vivo = false; };
  }, [intento]);

  const admin = def?.puede.administrar_catalogo === true;
  const supervisa = def?.puede.supervisar === true;
  const secciones: { clave: Seccion; titulo: string }[] = [
    { clave: "reportes", titulo: "Reportes" }, { clave: "indicadores", titulo: "Indicadores" },
    ...(admin ? [{ clave: "catalogo" as Seccion, titulo: "Catálogo" }, { clave: "parametros" as Seccion, titulo: "Parámetros" }] : []),
  ];
  return (
    <div className="rv">
      <div className="rv-cab">
        <div className="rv-ancho">
          <div className="rv-fila">
            <h1>Supervisión y dashboard</h1>
            <button type="button" className="rv-boton-claro" onClick={onVolver}>← Volver a Formatos de campo</button>
          </div>
          <div className="rv-sesion">{correo} · {def?.perfil === "admin" ? "Administrador" : "Supervisor de reportes de campo"}</div>
          {def && supervisa ? (
            <nav className="rv-tabs" aria-label="Secciones de la revisión">
              {secciones.map((s) => <button key={s.clave} type="button" className="rv-tab" aria-current={seccion === s.clave ? "page" : undefined} onClick={() => setSeccion(s.clave)}>{s.titulo}</button>)}
            </nav>
          ) : null}
        </div>
      </div>
      <div className="rv-cuerpo">
        {error ? (
          <div className="rv-aviso rv-aviso-error" role="alert">{error.texto}{" "}
            {error.sesion ? <button type="button" className="rv-enlace" onClick={() => void supabase.auth.signOut()}>Volver a iniciar sesión</button> : <button type="button" className="rv-enlace" onClick={() => setIntento((x) => x + 1)}>Reintentar</button>}
          </div>
        ) : !def ? <p className="rv-sub" role="status">Cargando la revisión…</p>
          : !supervisa ? <div className="rv-aviso rv-aviso-error" role="alert">Su cuenta no tiene permiso para revisar reportes.</div>
          : seccion === "reportes" ? <Reportes def={def} />
          : seccion === "indicadores" ? <Indicadores def={def} />
          : seccion === "catalogo" && admin ? <><Catalogo alCambiar={() => void cargar(false)} /><ConstanciasAdmin /></>
          : seccion === "parametros" && admin ? <Parametros def={def} alCambiar={() => void cargar(false)} />
          : null}
      </div>
    </div>
  );
}
