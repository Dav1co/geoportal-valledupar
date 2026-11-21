import { useCallback, useEffect, useState } from "react";
import "./revision.css";
import { apiRev, textoError, type FormularioRev, type CatalogoLectura } from "./apiRevision";
import { Reportes } from "./Reportes";
import { Indicadores } from "./Indicadores";
import { Parametros } from "./Parametros";
import { Catalogo } from "./Catalogo";
import { ConstanciasAdmin } from "../constancia/ConstanciasAdmin";
import { PersonalCampo } from "./PersonalCampo";
import { Cuadrillas } from "./Cuadrillas";
import { supabase } from "../../lib/supabase";

// «Supervisión y dashboard» (antes «Revisión de reportes», Paso C): pantalla del supervisor y del administrador de Formatos de campo. Se carga bajo demanda (React.lazy desde AreaCampo): quien no tiene el permiso no descarga este código.
// Qué se muestra lo decide el SERVIDOR (`puede` y `perfil` de «formulario»). Pasada 14/11: Catálogo y Parámetros los VE el supervisor (solo lectura, ruta «catalogo_lectura»);
// solo el administrador los edita (y la base rechaza cualquier escritura de otro perfil). Personal: lo ve el supervisor; qué edita cada quien lo dice el servidor (desde el 21-nov también el supervisor: cuadrilla, actividades y formularios). Cuadrillas (21-nov): pestaña propia.
type Seccion = "reportes" | "indicadores" | "catalogo" | "parametros" | "personal" | "cuadrillas";

export default function Revision({ correo, onVolver }: { correo: string; onVolver: () => void }) {
  const [def, setDef] = useState<FormularioRev | null>(null);
  const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [seccion, setSeccion] = useState<Seccion>("reportes");
  const [intento, setIntento] = useState(0);
  const cargar = useCallback((incluirInactivos: boolean) => apiRev.formulario(incluirInactivos).then(setDef), []);
  // Lectura completa del supervisor (catálogo con inactivos, parámetros y constancias): se pide la primera vez que abre Catálogo o Parámetros
  const [lectura, setLectura] = useState<CatalogoLectura | null>(null);
  const [errLectura, setErrLectura] = useState<string | null>(null);
  const [intLectura, setIntLectura] = useState(0);
  useEffect(() => {
    let vivo = true; setError(null);
    apiRev.formulario(false).then((d) => { if (vivo) setDef(d); }).catch((e) => { if (vivo) setError(textoError(e)); });
    return () => { vivo = false; };
  }, [intento]);

  const admin = def?.puede.administrar_catalogo === true;
  const supervisa = def?.puede.supervisar === true;
  const necesitaLectura = !!def && supervisa && !admin && (seccion === "catalogo" || seccion === "parametros");
  useEffect(() => {
    if (!necesitaLectura || lectura) return;
    let vivo = true; setErrLectura(null);
    apiRev.catalogoLectura().then((d) => { if (vivo) setLectura(d); }).catch((e) => { if (vivo) setErrLectura(textoError(e).texto); });
    return () => { vivo = false; };
  }, [necesitaLectura, lectura, intLectura]);
  const secciones: { clave: Seccion; titulo: string }[] = [
    { clave: "reportes", titulo: "Reportes" }, { clave: "indicadores", titulo: "Indicadores" },
    { clave: "catalogo", titulo: "Catálogo" }, { clave: "parametros", titulo: "Parámetros" }, { clave: "personal", titulo: "Personal" },
    { clave: "cuadrillas", titulo: "Cuadrillas" },
  ];
  const esperaLectura = errLectura ? <div className="rv-aviso rv-aviso-error" role="alert">{errLectura} <button type="button" className="rv-enlace" onClick={() => setIntLectura((x) => x + 1)}>Reintentar</button></div>
    : <p className="rv-sub" role="status">Cargando…</p>;
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
          : seccion === "catalogo" ? (lectura ? <><Catalogo alCambiar={() => undefined} lectura={lectura} /><ConstanciasAdmin lectura={lectura.constancias} /></> : esperaLectura)
          : seccion === "parametros" ? (lectura ? <Parametros def={{ ...def, parametros: lectura.parametros }} alCambiar={() => undefined} soloLectura /> : esperaLectura)
          : seccion === "personal" ? <PersonalCampo />
          : seccion === "cuadrillas" ? <Cuadrillas />
          : null}
      </div>
    </div>
  );
}
