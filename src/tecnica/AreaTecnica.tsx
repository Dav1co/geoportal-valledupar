import { useCallback, useEffect, useState } from "react";
import "./tecnica.css";
import { apiTec, ErrorTec, type FormularioDef, type MisFormularios } from "./apiTecnica";
import { FormularioCaptura, avisoDeError } from "./FormularioCaptura";
import { FormularioPorLugar } from "./FormularioPorLugar";
import { ResumenUltimas24 } from "./ResumenUltimas24";
import { Dashboard } from "./Dashboard";
import { ActivosRedes } from "./ActivosRedes";
import { FormularioDano } from "./FormularioDano";
import { FormularioIntervencion, type DesdeDano } from "./FormularioIntervencion";
import { DashboardRedes } from "./DashboardRedes";
import { apiDash, type MiPerfilRedes } from "./apiRedes";
import { supabase } from "../lib/supabase";

// Área Técnica (Torre B) en el celular. Qué formularios ve cada persona y qué perfil tiene lo decide el SERVIDOR (ruta mis_formularios); aquí solo se dibuja.
// Formularios que ya tienen pantalla construida (el resto se muestra deshabilitado, «Próximamente»). Esta lista no contiene variables ni nombres de campos.
const FORMULARIOS_CON_PANTALLA = new Set(["entrada", "salida", "muestreo", "danos_fallas", "mantenimiento"]);   // mantenimiento = «Registrar intervención» (Corte 3a)      // danos_fallas: pantalla propia (Corte 2), no usa variables. Muestreo: con FormularioPorLugar (variables «por punto»), lista de puntos del servidor
const PANTALLA_PROPIA = new Set(["danos_fallas", "mantenimiento"]);      // formularios con pantalla propia, sin variables de planta (con_campos = false en el servidor)
const ROTULO_PERFIL: Record<MisFormularios["perfil"], string> = { admin: "Administrador", supervisor: "Supervisor técnico", operador: "Operador técnico" };

export function AreaTecnica({ uid, correo }: { uid: string; correo: string }) {
  const [mis, setMis] = useState<MisFormularios | null>(null);
  const [errorMis, setErrorMis] = useState<ErrorTec | null>(null);
  const [elegido, setElegido] = useState<string | null>(null);
  const [def, setDef] = useState<FormularioDef | null>(null);
  const [errorDef, setErrorDef] = useState<ErrorTec | null>(null);
  const [version, setVersion] = useState(0);        // sube con cada guardado: refresca el resumen y la definición (fecha y hora propuestas)
  const [intento, setIntento] = useState(0);
  const [vezDano, setVezDano] = useState(0);         // sube al terminar o cancelar un daño: abre uno nuevo en blanco
  const [vezItv, setVezItv] = useState(0);           // ídem para la intervención
  const [desdeDano, setDesdeDano] = useState<DesdeDano | null>(null);      // «Registrar la reparación» desde el daño recién guardado
  const [activoItv, setActivoItv] = useState<{ codigo: string; sistema: "acueducto" | "alcantarillado"; lat: number; lon: number } | null>(null);   // desde la ficha
  const [vista, setVista] = useState<"captura" | "dashboard" | "activos" | "redes">("captura");     // Corte 4a: «redes» = Dashboard distribución (supervisor de distribución y administrador)
  const [redes, setRedes] = useState<MiPerfilRedes | null>(null);      // perfil de redes (ver_dashboard_redes), del servidor     // el Dashboard PTAP y la ficha de activos (Corte 1b) son solo para supervisor y administrador en esta pantalla (el servidor lo vuelve a verificar en cada ruta)

  useEffect(() => {
    let vivo = true;
    setErrorMis(null);
    apiDash.miPerfil().then((r) => { if (vivo) setRedes(r); }).catch(() => { if (vivo) setRedes(null); });
    apiTec.misFormularios()
      .then((r) => {
        if (!vivo) return;
        setMis(r);
        setElegido((actual) => actual ?? r.formularios.find((f) => (f.con_campos || PANTALLA_PROPIA.has(f.clave)) && FORMULARIOS_CON_PANTALLA.has(f.clave))?.clave ?? null);
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

  useEffect(() => { if (elegido && !PANTALLA_PROPIA.has(elegido)) cargarDef(elegido, false); }, [elegido, cargarDef, intento]);
  useEffect(() => { if (elegido && version > 0 && !PANTALLA_PROPIA.has(elegido)) cargarDef(elegido, true); }, [version]); // eslint-disable-line react-hooks/exhaustive-deps

  // ----- errores al entrar -----
  if (errorMis) {
    const a = avisoDeError(errorMis);
    const sinAcceso = errorMis.tipo === "permiso" || errorMis.tipo === "denegado";
    // quien solo tiene el Dashboard distribución (sin formularios de Técnica) entra directo a él
    if (sinAcceso && redes?.dashboard_redes) return <DashboardRedes onVolver={() => setIntento((i) => i + 1)} />;
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
  const puedeSupervisar = mis.perfil === "admin" || mis.perfil === "supervisor";      // Dashboard PTAP (planta)
  const puedeRedes = redes?.dashboard_redes === true;                                  // Dashboard distribución (Corte 4a)
  // selector arriba de cada dashboard, cuando la persona tiene los dos (§1 de la bitácora: no se solapan)
  const selector = puedeSupervisar && puedeRedes ? (
    <div className="tec-selector-dash" role="group" aria-label="Dashboard">
      <button type="button" className="tec-chip-form" aria-pressed={vista === "dashboard"} onClick={() => setVista("dashboard")}>Dashboard PTAP</button>
      <button type="button" className="tec-chip-form" aria-pressed={vista === "redes"} onClick={() => setVista("redes")}>Dashboard distribución</button>
    </div>) : null;

  if (puedeSupervisar && vista === "dashboard") return <>{selector ? <div className="tec-pagina tec-pagina-selector">{selector}</div> : null}<Dashboard correo={correo} rotuloPerfil={ROTULO_PERFIL[mis.perfil]} onVolver={() => setVista("captura")} /></>;
  if (puedeRedes && vista === "redes") return <DashboardRedes selector={selector} onVolver={() => setVista("captura")} />;
  const tieneItv = mis.formularios.some((f) => f.clave === "mantenimiento");
  const abrirItv = (d: DesdeDano | null, a: typeof activoItv) => { setDesdeDano(d); setActivoItv(a); setVezItv((v) => v + 1); setElegido("mantenimiento"); setVista("captura"); window.scrollTo?.(0, 0); };
  if ((puedeSupervisar || puedeRedes) && vista === "activos") return <ActivosRedes onVolver={() => setVista("captura")} onRegistrarIntervencion={tieneItv || puedeSupervisar || puedeRedes ? (a) => abrirItv(null, a) : undefined} />;

  return (
    <div className="tec-pagina">
      <div className="tec-sesion">Sesión de {correo} · {ROTULO_PERFIL[mis.perfil]}</div>

      {hayAlgunoAsignado ? (
        <nav className="tec-formularios" aria-label="Tus formularios">
          <div className="tec-rotulo">Tus formularios</div>
          <div className="tec-chips">
            {mis.formularios.map((f) => {
              const construido = FORMULARIOS_CON_PANTALLA.has(f.clave);
              const activo = (f.con_campos || PANTALLA_PROPIA.has(f.clave)) && construido;
              return (
                <button key={f.clave} type="button" className="tec-chip-form" aria-pressed={elegido === f.clave} disabled={!activo}
                  title={!construido ? "Próximamente" : !activo ? "Este formulario todavía no tiene campos" : undefined}
                  onClick={() => setElegido(f.clave)}>
                  {f.nombre}
                  {!construido ? <span className="tec-pronto">Próximamente</span> : !activo ? <span className="tec-pronto">Sin campos</span> : null}
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

      {puedeSupervisar || puedeRedes ? (
        <div className="tec-supervision">
          {puedeSupervisar ? <button type="button" className="tec-boton-sec" onClick={() => setVista("dashboard")}>Dashboard PTAP</button> : null}
          {puedeRedes ? <button type="button" className="tec-boton-sec" onClick={() => setVista("redes")}>Dashboard distribución</button> : null}
          <button type="button" className="tec-boton-sec" onClick={() => setVista("activos")}>Ficha de activos (redes)</button>
        </div>
      ) : null}

      {elegido === "danos_fallas" ? <FormularioDano key={vezDano} correo={correo} onSalir={() => setVezDano((v) => v + 1)}
        onRegistrarReparacion={tieneItv || puedeSupervisar || puedeRedes ? (d) => abrirItv(d, null) : undefined} /> : null}
      {elegido === "mantenimiento" ? <FormularioIntervencion key={vezItv} correo={correo} desdeDano={desdeDano} activoInicial={activoItv}
        onSalir={() => { setDesdeDano(null); setActivoItv(null); setVezItv((v) => v + 1); }} /> : null}
      {elegido && !PANTALLA_PROPIA.has(elegido) && errorDef ? (
        <section className="tec-tarjeta" role="alert">
          <p><strong>{errorDef.tipo === "permiso" ? "No tiene permiso para este formulario." : errorDef.message}</strong></p>
          <button type="button" className="tec-boton" onClick={() => setIntento((i) => i + 1)}>Reintentar</button>
        </section>
      ) : null}
      {elegido && !PANTALLA_PROPIA.has(elegido) && !def && !errorDef ? <p className="tec-sub" role="status">Cargando el formulario…</p> : null}
      {elegido && !PANTALLA_PROPIA.has(elegido) && def ? (
        <>
          {def.variables.some((v) => v.alcance === "por_punto")
            ? <FormularioPorLugar key={elegido} def={def} uid={uid} onGuardado={() => setVersion((v) => v + 1)} />      /* con variables «por punto»: tarjetas por lugar */
            : <FormularioCaptura key={elegido} def={def} uid={uid} onGuardado={() => setVersion((v) => v + 1)} />}
          <ResumenUltimas24 formulario={elegido} version={version} />
        </>
      ) : null}
    </div>
  );
}
