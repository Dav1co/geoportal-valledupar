import { useCallback, useEffect, useState } from "react";
import "./tecnica.css";
import { apiTec, ErrorTec, type FormularioDef, type MisFormularios } from "./apiTecnica";
import { FormularioCaptura, avisoDeError } from "./FormularioCaptura";
import { ResumenUltimas24 } from "./ResumenUltimas24";
import { Dashboard } from "./Dashboard";
import { supabase } from "../lib/supabase";

// Área Técnica (Torre B) en el celular. Qué formularios ve cada persona y qué perfil tiene lo decide el SERVIDOR (ruta mis_formularios); aquí solo se dibuja.
// Formularios que ya tienen pantalla construida (el resto se muestra deshabilitado, «Próximamente»). Esta lista no contiene variables ni nombres de campos.
const FORMULARIOS_CON_PANTALLA = new Set(["entrada"]);
const ROTULO_PERFIL: Record<MisFormularios["perfil"], string> = { admin: "Administrador", supervisor: "Supervisor técnico", operador: "Operador técnico" };

export function AreaTecnica({ uid, correo }: { uid: string; correo: string }) {
  const [mis, setMis] = useState<MisFormularios | null>(null);
  const [errorMis, setErrorMis] = useState<ErrorTec | null>(null);
  const [elegido, setElegido] = useState<string | null>(null);
  const [def, setDef] = useState<FormularioDef | null>(null);
  const [errorDef, setErrorDef] = useState<ErrorTec | null>(null);
  const [version, setVersion] = useState(0);        // sube con cada guardado: refresca el resumen y la definición (fecha y hora propuestas)
  const [intento, setIntento] = useState(0);
  const [vista, setVista] = useState<"captura" | "dashboard">("captura");     // el Dashboard técnico es solo para supervisor y administrador (el servidor lo vuelve a verificar en cada ruta)

  useEffect(() => {
    let vivo = true;
    setErrorMis(null);
    apiTec.misFormularios()
      .then((r) => {
        if (!vivo) return;
        setMis(r);
        setElegido((actual) => actual ?? r.formularios.find((f) => f.con_campos && FORMULARIOS_CON_PANTALLA.has(f.clave))?.clave ?? null);
      })
      .catch((e) => { if (vivo) setErrorMis(e instanceof ErrorTec ? e : new ErrorTec("servidor", "No se pudo cargar.", 0)); });
    return () => { vivo = false; };
  }, [intento]);

  const cargarDef = useCallback((clave: string, silencioso: boolean) => {
    if (!silencioso) setDef(null);
    setErrorDef(null);
    apiTec.formulario(clave)
      .then(setDef)
      .catch((e) => { if (!silencioso) setErrorDef(e instanceof ErrorTec ? e : new ErrorTec("servidor", "No se pudo cargar.", 0)); });
  }, []);

  useEffect(() => { if (elegido) cargarDef(elegido, false); }, [elegido, cargarDef, intento]);
  useEffect(() => { if (elegido && version > 0) cargarDef(elegido, true); }, [version]); // eslint-disable-line react-hooks/exhaustive-deps

  // ----- errores al entrar -----
  if (errorMis) {
    const a = avisoDeError(errorMis);
    const sinAcceso = errorMis.tipo === "permiso" || errorMis.tipo === "denegado";
    return (
      <div className="tec-pagina">
        <section className="tec-tarjeta" role="alert">
          <h1>{sinAcceso ? "Sin acceso a Técnica" : "No se pudo abrir Técnica"}</h1>
          <p>{sinAcceso ? "Su cuenta no tiene acceso a Técnica. Solicítelo a un administrador." : a.texto}</p>
          {a.detalle && !sinAcceso ? <p className="tec-sub">{a.detalle}</p> : null}
          {!sinAcceso && errorMis.tipo !== "sesion" ? <button type="button" className="tec-boton" onClick={() => setIntento((i) => i + 1)}>Reintentar</button> : null}
          {errorMis.tipo === "sesion" ? <button type="button" className="tec-boton" onClick={() => void supabase.auth.signOut()}>Volver a iniciar sesión</button> : null}
        </section>
      </div>
    );
  }
  if (!mis) return <div className="tec-pagina"><p className="tec-sub" role="status">Cargando Técnica…</p></div>;

  const hayAlgunoAsignado = mis.formularios.length > 0;
  const puedeSupervisar = mis.perfil === "admin" || mis.perfil === "supervisor";

  if (puedeSupervisar && vista === "dashboard") return <Dashboard correo={correo} rotuloPerfil={ROTULO_PERFIL[mis.perfil]} onVolver={() => setVista("captura")} />;

  return (
    <div className="tec-pagina">
      <div className="tec-sesion">Sesión de {correo} · {ROTULO_PERFIL[mis.perfil]}</div>

      {hayAlgunoAsignado ? (
        <nav className="tec-formularios" aria-label="Tus formularios">
          <div className="tec-rotulo">Tus formularios</div>
          <div className="tec-chips">
            {mis.formularios.map((f) => {
              const construido = FORMULARIOS_CON_PANTALLA.has(f.clave);
              const activo = f.con_campos && construido;
              return (
                <button key={f.clave} type="button" className="tec-chip-form" aria-pressed={elegido === f.clave} disabled={!activo}
                  title={!construido ? "Próximamente" : !f.con_campos ? "Este formulario todavía no tiene campos" : undefined}
                  onClick={() => setElegido(f.clave)}>
                  {f.nombre}
                  {!construido ? <span className="tec-pronto">Próximamente</span> : !f.con_campos ? <span className="tec-pronto">Sin campos</span> : null}
                </button>
              );
            })}
          </div>
        </nav>
      ) : (
        <section className="tec-tarjeta" role="status">
          <h1>Todavía no tiene formularios asignados</h1>
          <p>Solicite a su supervisor que le asigne los formularios que debe diligenciar.</p>
        </section>
      )}

      {puedeSupervisar ? (
        <div className="tec-supervision">
          <button type="button" className="tec-boton-sec" onClick={() => setVista("dashboard")}>Dashboard técnico</button>
        </div>
      ) : null}

      {elegido && errorDef ? (
        <section className="tec-tarjeta" role="alert">
          <p><strong>{errorDef.tipo === "permiso" ? "No tiene permiso para este formulario." : errorDef.message}</strong></p>
          <button type="button" className="tec-boton" onClick={() => setIntento((i) => i + 1)}>Reintentar</button>
        </section>
      ) : null}
      {elegido && !def && !errorDef ? <p className="tec-sub" role="status">Cargando el formulario…</p> : null}
      {elegido && def ? (
        <>
          <FormularioCaptura key={elegido} def={def} uid={uid} onGuardado={() => setVersion((v) => v + 1)} />
          <ResumenUltimas24 formulario={elegido} version={version} />
        </>
      ) : null}
    </div>
  );
}
