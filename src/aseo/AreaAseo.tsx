import { lazy, Suspense, useEffect, useState } from "react";
import "../tecnica/tecnica.css";
import "../campo/campo.css";
import "./aseo.css";
import { apiAseo, avisoDeError, ErrorAseo } from "./apiAseo";
import { PantallaActividad } from "./PantallaActividad";
import { supabase } from "../lib/supabase";
import type { FormularioAseo } from "./tipos";

// Interventoría de Aseo (Torre C): auditoría de la prestación del servicio de aseo. Qué puede hacer la persona lo decide el SERVIDOR (ruta formulario); aquí solo se dibuja. Pantalla completa, sin mapa ni datos comerciales:
// el mapa de rutas es propio (MapLibre, carga diferida) y sus datos vienen de la Edge de Aseo. Dashboard y gestión de personal: solo marcadores.
const AdminAseo = lazy(() => import("./AdminAseo").then((m) => ({ default: m.AdminAseo })));
const ROTULO: Record<FormularioAseo["perfil"], string> = { admin: "Administrador", supervisor: "Supervisor de aseo", auditor: "Auditor de aseo" };

export function AreaAseo({ correo }: { correo: string }) {
  const [def, setDef] = useState<FormularioAseo | null>(null);
  const [error, setError] = useState<ErrorAseo | null>(null);
  const [intento, setIntento] = useState(0);
  const [vista, setVista] = useState<{ tipo: "inicio" } | { tipo: "actividad"; codigo: string } | { tipo: "admin" }>({ tipo: "inicio" });

  useEffect(() => {
    let vivo = true; setError(null);
    apiAseo.formulario().then((r) => { if (vivo) setDef(r); }).catch((e) => { if (vivo) setError(e instanceof ErrorAseo ? e : new ErrorAseo("servidor", "No se pudo cargar.", 0)); });
    return () => { vivo = false; };
  }, [intento]);

  if (error) {
    const a = avisoDeError(error); const sinAcceso = error.tipo === "permiso" || error.tipo === "denegado";
    return (
      <div className="tec-pagina"><section className="tec-tarjeta" role="alert">
        <h1>{sinAcceso ? "Sin acceso a Aseo" : "No se pudo abrir Aseo"}</h1>
        <p>{sinAcceso ? "Su cuenta no tiene acceso a la interventoría de aseo. Solicítelo a un administrador." : a.texto}</p>
        {!sinAcceso && error.tipo !== "sesion" ? <button type="button" className="tec-boton" onClick={() => setIntento((i) => i + 1)}>Reintentar</button> : null}
        {error.tipo === "sesion" ? <button type="button" className="tec-boton" onClick={() => void supabase.auth.signOut()}>Volver a iniciar sesión</button> : null}
      </section></div>
    );
  }
  if (!def) return <div className="tec-pagina"><section className="tec-tarjeta"><p>Cargando…</p></section></div>;
  const auditor = { nombre: def.nombre ?? correo.split("@")[0], correo: def.correo ?? correo };

  if (vista.tipo === "admin" && def.puede.administrar) {
    return <Suspense fallback={<div className="tec-pagina"><section className="tec-tarjeta"><p>Cargando la administración…</p></section></div>}><AdminAseo onVolver={() => setVista({ tipo: "inicio" })} /></Suspense>;
  }
  if (vista.tipo === "actividad") {
    const act = def.actividades.find((a) => a.codigo === vista.codigo && a.activa);
    if (act) return <PantallaActividad def={def} actividad={act} auditor={auditor} onSalir={() => setVista({ tipo: "inicio" })} />;
  }

  return (
    <div className="tec-pagina campo-pagina">
      <section className="tec-tarjeta">
        <h1>Interventoría de Aseo</h1>
        <p className="campo-sub">{ROTULO[def.perfil]} · Auditoría de la prestación del servicio</p>
        <div className="campo-formatos">
          {def.actividades.map((a) => a.activa ? (
            <button key={a.codigo} type="button" className="campo-formato campo-formato-activo" onClick={() => setVista({ tipo: "actividad", codigo: a.codigo })}><strong>{a.nombre}</strong><span>Elija la ruta y registre la auditoría con fotos.</span></button>
          ) : (
            <div key={a.codigo} className="campo-formato campo-formato-proximo" aria-disabled="true"><strong>{a.nombre}</strong><span>Próximamente</span></div>
          ))}
          {def.puede.supervisar ? <div className="campo-formato campo-formato-proximo" aria-disabled="true"><strong>Supervisión y dashboard</strong><span>Próximamente. Revisión de auditorías, marcas e indicadores.</span></div> : null}
          {def.puede.administrar ? <>
            <button type="button" className="campo-formato campo-formato-activo" onClick={() => setVista({ tipo: "admin" })}><strong>Administración de rutas</strong><span>Plan operativo, capas de rutas, barrios e historial de cargas.</span></button>
            <div className="campo-formato campo-formato-proximo" aria-disabled="true"><strong>Gestión de personal</strong><span>Próximamente. Hoy los permisos se asignan en Administración.</span></div></> : null}
        </div>
      </section>
    </div>
  );
}
