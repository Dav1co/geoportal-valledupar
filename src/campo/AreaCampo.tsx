import { lazy, Suspense, useEffect, useState } from "react";
import "../tecnica/tecnica.css";
import "./campo.css";
import { apiCampo, avisoDeError, ErrorCampo, type FormularioCampo } from "./apiCampo";
import { ReporteGeneral } from "./ReporteGeneral";
import { FormatosCampo } from "./formatos/FormatosCampo";
import { formatosDisponibles } from "./formatos/tipos";
import { entradasDeCampo, type EntradaId } from "./entradas";
import { PantallaActa } from "./acta/PantallaActa";
import { supabase } from "../lib/supabase";

// Revisión de reportes (Paso C): carga diferida. Quien no tiene el permiso de supervisión no descarga este código (ni MapLibre, que viene dentro del mapa).
const Revision = lazy(() => import("./dashboard/Revision"));

// Sección «Formatos de campo» de la Torre A. Qué puede hacer la persona lo decide el SERVIDOR (ruta formulario); aquí solo se dibuja.
// Se usa como pantalla completa para quien solo tiene campo (sin mapa ni datos comerciales) y como vista dentro del área Comercial para quien tiene las dos cosas.
// Las pantallas son ENTRADAS de una lista (entradas.ts): reporte general, formatos de actividad (Paso D) y acta de inspección (solo con el permiso `acta`; su pantalla aún no existe).
// Los formatos «Próximamente» no tienen acción. Esta lista de formatos es de interfaz (no es el catálogo de tipos de reporte, que viene del servidor).
const PROXIMAMENTE = ["Daños", "Instalación de medidor", "Revisión previa", "SCRR"];
const ROTULO_PERFIL: Record<FormularioCampo["perfil"], string> = { admin: "Administrador", supervisor: "Supervisor de reportes de campo", reportante: "Reporte de campo" };

/** Permisos que decide el servidor (App los toma del perfil). `acta`: puede capturar actas (si no se informa, la entrada del acta no aparece). `campo`: tiene permiso de campo; por omisión sí (como antes).
 *  Quien solo tiene acta (`campo` falso) NO pide el formulario de campo (su Edge le respondería 403) y ve únicamente las entradas del acta. `dashboardActa`: supervisor de actas (marcador, sin pantalla aún). */
export function AreaCampo({ correo, acta = false, campo = true, dashboardActa = false }: { correo: string; acta?: boolean; campo?: boolean; dashboardActa?: boolean }) {
  const [def, setDef] = useState<FormularioCampo | null>(null);
  const [error, setError] = useState<ErrorCampo | null>(null);
  const [intento, setIntento] = useState(0);
  const [abierta, setAbierta] = useState<EntradaId | null>(null);   // pantalla abierta (null = la lista de entradas)
  const [version, setVersion] = useState(0);        // sube con cada «Hacer otro reporte»: el formulario nace limpio y se vuelve a leer la definición

  useEffect(() => {
    if (!campo) return;                  // solo acta: no hay formulario de campo que pedir
    let vivo = true;
    setError(null);
    apiCampo.formulario()
      .then((r) => { if (vivo) setDef(r); })
      .catch((e) => { if (vivo) setError(e instanceof ErrorCampo ? e : new ErrorCampo("servidor", "No se pudo cargar.", 0)); });
    return () => { vivo = false; };
  }, [intento, version, campo]);

  if (campo && error) {
    const a = avisoDeError(error);
    const sinAcceso = error.tipo === "permiso" || error.tipo === "denegado";
    return (
      <div className="tec-pagina">
        <section className="tec-tarjeta" role="alert">
          <h1>{sinAcceso ? "Sin acceso a Formatos de campo" : "No se pudo abrir Formatos de campo"}</h1>
          <p>{sinAcceso ? "Su cuenta no tiene acceso a Formatos de campo. Solicítelo a un administrador." : a.texto}</p>
          {!sinAcceso && error.tipo !== "sesion" ? <button type="button" className="tec-boton" onClick={() => setIntento((i) => i + 1)}>Reintentar</button> : null}
          {error.tipo === "sesion" ? <button type="button" className="tec-boton" onClick={() => void supabase.auth.signOut()}>Volver a iniciar sesión</button> : null}
        </section>
      </div>
    );
  }
  if (campo && !def) return <div className="tec-pagina"><section className="tec-tarjeta"><p>Cargando…</p></section></div>;

  if (abierta === "acta" && acta) {
    return <PantallaActa correo={correo} onVolver={() => setAbierta(null)} />;
  }
  if (def && abierta === "reporte_general") {
    return <ReporteGeneral key={version} def={def} correo={correo} onVolver={() => setAbierta(null)} onOtro={() => { setAbierta("reporte_general"); setVersion((v) => v + 1); }} />;
  }
  if (def && abierta === "formatos") {
    return <FormatosCampo def={def} correo={correo} onVolver={() => setAbierta(null)} />;
  }

  if (abierta === "revision" && def?.puede.supervisar) {
    return <Suspense fallback={<div className="tec-pagina"><section className="tec-tarjeta"><p>Cargando la revisión…</p></section></div>}><Revision correo={correo} onVolver={() => setAbierta(null)} /></Suspense>;
  }

  const entradas = entradasDeCampo({
    puedeReportar: def?.puede.reportar ?? false, hayFormatos: def ? formatosDisponibles(def.grupos).length > 0 : false,
    puedeActa: acta, puedeCampo: campo, puedeSupervisarActas: dashboardActa, puedeSupervisar: def?.puede.supervisar ?? false,
  });

  return (
    <div className="tec-pagina campo-pagina">
      <section className="tec-tarjeta">
        <h1>{campo ? "Formatos de campo" : "Acta de inspección"}</h1>
        <p className="campo-sub">{def ? ROTULO_PERFIL[def.perfil] : "Registro digital de actas"}</p>
        <div className="campo-formatos">
          {entradas.map((e) => e.pendiente ? (
            <div key={e.id} className="campo-formato campo-formato-proximo" aria-disabled="true">
              <strong>{e.titulo}</strong>
              <span>Próximamente. {e.descripcion}</span>
            </div>
          ) : (
            <button key={e.id} type="button" className="campo-formato campo-formato-activo" onClick={() => setAbierta(e.id)} disabled={!e.habilitada}>
              <strong>{e.titulo}</strong>
              <span>{e.descripcion}</span>
            </button>
          ))}
          {campo && PROXIMAMENTE.map((n) => (
            <div key={n} className="campo-formato campo-formato-proximo" aria-disabled="true">
              <strong>{n}</strong>
              <span>Próximamente</span>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
