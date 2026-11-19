import { Suspense, useEffect, useState } from "react";
import { lazyConRecarga } from "../lib/recarga";
import "../tecnica/tecnica.css";
import "../campo/campo.css";
import "./aseo.css";      // trae los tokens de Aseo (tokens.css)
import { apiAseo, avisoDeError, ErrorAseo } from "./apiAseo";
import { PantallaActividad } from "./PantallaActividad";
import { supabase } from "../lib/supabase";
import type { FormularioAseo } from "./tipos";

// Interventoría de Aseo (Torre C): auditoría de la prestación del servicio de aseo. Qué puede hacer la persona lo decide el SERVIDOR (ruta formulario); aquí solo se dibuja. Pantalla completa, sin mapa ni datos comerciales:
// el mapa de rutas es propio (MapLibre, carga diferida) y sus datos vienen de la Edge de Aseo. «Supervisión y dashboard» (supervisor y administrador) incluye el personal como pestaña; también es de carga diferida.
const Supervision = lazyConRecarga(() => import("./supervision/Supervision").then((m) => ({ default: m.Supervision })));
const AdminAseo = lazyConRecarga(() => import("./AdminAseo").then((m) => ({ default: m.AdminAseo })));
// Cuadro con la inicial de cada tarjeta del inicio (guía visual, §5; como el inicio de Técnica): la letra va por CSS (data-ini) y no se lee en voz alta ni entra al texto del botón.
const ini = (nombre: string) => <span className="aseo-tarjeta-ini" data-ini={nombre.trim().charAt(0).toUpperCase()} aria-hidden="true" />;
const ROTULO: Record<FormularioAseo["perfil"], string> = { admin: "Administrador", supervisor: "Supervisor de aseo", auditor: "Auditor de aseo" };

export function AreaAseo({ correo }: { correo: string }) {
  const [def, setDef] = useState<FormularioAseo | null>(null);
  const [error, setError] = useState<ErrorAseo | null>(null);
  const [intento, setIntento] = useState(0);
  const [vista, setVista] = useState<{ tipo: "inicio" } | { tipo: "actividad"; codigo: string } | { tipo: "admin" } | { tipo: "supervision" }>({ tipo: "inicio" });

  useEffect(() => {
    let vivo = true; setError(null);
    apiAseo.formulario().then((r) => { if (vivo) setDef(r); }).catch((e) => { if (vivo) setError(e instanceof ErrorAseo ? e : new ErrorAseo("servidor", "No se pudo cargar.", 0)); });
    return () => { vivo = false; };
  }, [intento]);

  if (error) {
    const a = avisoDeError(error); const sinAcceso = error.tipo === "permiso" || error.tipo === "denegado";
    return (
      <div className="aseo-modulo tec-pagina"><section className="tec-tarjeta" role="alert">
        <h1>{sinAcceso ? "Sin acceso a Aseo" : "No se pudo abrir Aseo"}</h1>
        <p>{sinAcceso ? "Su cuenta no tiene acceso a la interventoría de aseo. Solicítelo a un administrador." : a.texto}</p>
        {!sinAcceso && error.tipo !== "sesion" ? <button type="button" className="tec-boton" onClick={() => setIntento((i) => i + 1)}>Reintentar</button> : null}
        {error.tipo === "sesion" ? <button type="button" className="tec-boton" onClick={() => void supabase.auth.signOut()}>Volver a iniciar sesión</button> : null}
      </section></div>
    );
  }
  if (!def) return <div className="aseo-modulo tec-pagina"><section className="tec-tarjeta"><p>Cargando…</p></section></div>;
  const auditor = { nombre: def.nombre ?? correo.split("@")[0], correo: def.correo ?? correo };

  if (vista.tipo === "admin" && def.puede.administrar) {
    return <Suspense fallback={<div className="aseo-modulo tec-pagina"><section className="tec-tarjeta"><p>Cargando la administración…</p></section></div>}><AdminAseo onVolver={() => setVista({ tipo: "inicio" })} /></Suspense>;
  }
  if (vista.tipo === "supervision" && def.puede.supervisar) {
    return <Suspense fallback={<div className="aseo-modulo tec-pagina"><section className="tec-tarjeta"><p>Cargando Supervisión y dashboard…</p></section></div>}><Supervision def={def} correo={auditor.correo} onVolver={() => setVista({ tipo: "inicio" })} /></Suspense>;
  }
  if (vista.tipo === "actividad") {
    const act = def.actividades.find((a) => a.codigo === vista.codigo && a.activa);
    if (act) return <PantallaActividad def={def} actividad={act} auditor={auditor} onSalir={() => setVista({ tipo: "inicio" })} />;
  }

  return (
    <div className="aseo-modulo aseo-inicio tec-pagina campo-pagina">
      <section className="tec-tarjeta aseo-hoja">
        <h1>Interventoría de Aseo</h1>
        <p className="campo-sub">{ROTULO[def.perfil]} · Auditoría de la prestación del servicio</p>
        <div className="campo-formatos">
          {def.actividades.map((a) => a.activa ? (
            <button key={a.codigo} type="button" className="campo-formato campo-formato-activo" onClick={() => setVista({ tipo: "actividad", codigo: a.codigo })}>{ini(a.nombre)}<span className="aseo-tarjeta-txt"><strong>{a.nombre}</strong><span>Elija la ruta y registre la auditoría con fotos.</span></span></button>
          ) : (
            <div key={a.codigo} className="campo-formato campo-formato-proximo" aria-disabled="true">{ini(a.nombre)}<span className="aseo-tarjeta-txt"><strong>{a.nombre}</strong><span>Próximamente</span></span></div>
          ))}
          {def.puede.supervisar ? <button type="button" className="campo-formato campo-formato-activo campo-formato-gestion" onClick={() => setVista({ tipo: "supervision" })}>{ini("Supervisión y dashboard")}<span className="aseo-tarjeta-txt"><strong>Supervisión y dashboard</strong><span>Revisión de las actas de supervisión, no conformidades e indicadores.</span></span></button> : null}
          {def.puede.administrar ? <>
            <button type="button" className="campo-formato campo-formato-activo campo-formato-gestion" onClick={() => setVista({ tipo: "admin" })}>{ini("Administración de rutas")}<span className="aseo-tarjeta-txt"><strong>Administración de rutas</strong><span>Plan operativo, capas de rutas, barrios e historial de cargas.</span></span></button></> : null}
        </div>
      </section>
    </div>
  );
}
