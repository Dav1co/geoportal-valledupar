import { useEffect, useState } from "react";
import "../tecnica/tecnica.css";
import "./campo.css";
import { apiCampo, avisoDeError, ErrorCampo, type FormularioCampo } from "./apiCampo";
import { ReporteGeneral } from "./ReporteGeneral";
import { supabase } from "../lib/supabase";

// Sección «Formatos de campo» de la Torre A. Qué puede hacer la persona lo decide el SERVIDOR (ruta formulario); aquí solo se dibuja.
// Se usa como pantalla completa para quien solo tiene campo (sin mapa ni datos comerciales) y como vista dentro del área Comercial para quien tiene las dos cosas.
// Los formatos «Próximamente» no tienen acción. Esta lista de formatos es de interfaz (no es el catálogo de tipos de reporte, que viene del servidor).
const PROXIMAMENTE = ["Acta de inspección", "Daños", "Instalación de medidor", "Revisión previa", "SCRR"];
const ROTULO_PERFIL: Record<FormularioCampo["perfil"], string> = { admin: "Administrador", supervisor: "Supervisor de reportes de campo", reportante: "Reporte de campo" };

export function AreaCampo({ correo }: { correo: string }) {
  const [def, setDef] = useState<FormularioCampo | null>(null);
  const [error, setError] = useState<ErrorCampo | null>(null);
  const [intento, setIntento] = useState(0);
  const [abierto, setAbierto] = useState(false);
  const [version, setVersion] = useState(0);        // sube con cada «Hacer otro reporte»: el formulario nace limpio y se vuelve a leer la definición

  useEffect(() => {
    let vivo = true;
    setError(null);
    apiCampo.formulario()
      .then((r) => { if (vivo) setDef(r); })
      .catch((e) => { if (vivo) setError(e instanceof ErrorCampo ? e : new ErrorCampo("servidor", "No se pudo cargar.", 0)); });
    return () => { vivo = false; };
  }, [intento, version]);

  if (error) {
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
  if (!def) return <div className="tec-pagina"><section className="tec-tarjeta"><p>Cargando…</p></section></div>;

  if (abierto) {
    return <ReporteGeneral key={version} def={def} correo={correo} onVolver={() => setAbierto(false)} onOtro={() => { setAbierto(true); setVersion((v) => v + 1); }} />;
  }

  return (
    <div className="tec-pagina campo-pagina">
      <section className="tec-tarjeta">
        <h1>Formatos de campo</h1>
        <p className="campo-sub">{ROTULO_PERFIL[def.perfil]}</p>
        <div className="campo-formatos">
          <button type="button" className="campo-formato campo-formato-activo" onClick={() => setAbierto(true)} disabled={!def.puede.reportar}>
            <strong>Reporte general</strong>
            <span>Registre en segundos lo que encontró: tipo, fotos, ubicación y contrato.</span>
          </button>
          {PROXIMAMENTE.map((n) => (
            <div key={n} className="campo-formato campo-formato-proximo" aria-disabled="true">
              <strong>{n}</strong>
              <span>Próximamente</span>
            </div>
          ))}
        </div>
        {def.puede.supervisar && <p className="campo-sub">La revisión de los reportes (lista, mapa y estados) estará disponible próximamente.</p>}
      </section>
    </div>
  );
}
