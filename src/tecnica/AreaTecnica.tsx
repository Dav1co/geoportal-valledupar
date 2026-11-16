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
import { Geovisor } from "./Geovisor";
import { SelectorDashboards } from "./CabeceraDashboard";
import { apiDash, type MiPerfilRedes } from "./apiRedes";
import { supabase } from "../lib/supabase";

// Área Técnica (Torre B) en el celular. Qué formularios ve cada persona y qué perfil tiene lo decide el SERVIDOR (ruta mis_formularios); aquí solo se dibuja.
// Formularios que ya tienen pantalla construida (el resto se muestra deshabilitado, «Próximamente»). Esta lista no contiene variables ni nombres de campos.
const FORMULARIOS_CON_PANTALLA = new Set(["entrada", "salida", "muestreo", "danos_fallas", "mantenimiento"]);   // mantenimiento = «Registrar intervención» (Corte 3a)      // danos_fallas: pantalla propia (Corte 2), no usa variables. Muestreo: con FormularioPorLugar (variables «por punto»), lista de puntos del servidor
const PANTALLA_PROPIA = new Set(["danos_fallas", "mantenimiento"]);      // formularios con pantalla propia, sin variables de planta (con_campos = false en el servidor)
const ROTULO_PERFIL: Record<MisFormularios["perfil"], string> = { admin: "Administrador", supervisor: "Supervisor técnico", operador: "Operador técnico" };

// Corte 11 (render aprobado por David, 16-nov 13:30): el inicio de Técnica va por MODOS de trabajo (Planta, Redes y Supervisión), con tarjetas grandes.
// Ningún formulario se abre solo; cada persona ve solo los modos en los que tiene algo (lo decide el servidor: formularios asignados, dashboards y geovisor);
// con un solo modo no hay selector. Aquí no hay permisos nuevos: solo se reparte lo que ya llegaba.
type Modo = "planta" | "redes" | "supervision";
const MODOS: { clave: Modo; nombre: string }[] = [{ clave: "planta", nombre: "Planta" }, { clave: "redes", nombre: "Redes" }, { clave: "supervision", nombre: "Supervisión" }];
const FORMULARIOS_REDES = new Set(["danos_fallas", "mantenimiento"]);      // los demás formularios asignados son de planta
const ORDEN_FORM = ["entrada", "salida", "muestreo", "entrada_quimicos", "uso_quimicos", "danos_fallas", "mantenimiento"];
const DESCRIPCION: Record<string, string> = {
  entrada: "El agua que llega a la planta", salida: "El agua tratada que sale a la red", muestreo: "Cloro y turbiedad en los puntos de la red",
  entrada_quimicos: "Lo que llega a la bodega, en toneladas o kg", uso_quimicos: "Lo que se gastó en la planta",
  danos_fallas: "Un daño o una falla en la red", mantenimiento: "Mantenimiento, reparación e inversión",
};
type Tarjeta = { clave: string; nombre: string; descripcion: string; estado: "lista" | "pronto" | "sin_campos"; abrir: () => void };
const CLAVE_MODO = "tec_modo";
function modoGuardado(): Modo | null {
  try { const m = window.localStorage.getItem(CLAVE_MODO); return m === "planta" || m === "redes" || m === "supervision" ? m : null; } catch { return null; }
}
function guardarModo(m: Modo) { try { window.localStorage.setItem(CLAVE_MODO, m); } catch { /* sin almacenamiento: se elige de nuevo la próxima vez */ } }

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
  const [activoDano, setActivoDano] = useState<{ codigo: string; sistema: "acueducto" | "alcantarillado"; lat: number; lon: number } | null>(null);   // Corte 6a: desde el geovisor
  const [vista, setVista] = useState<"inicio" | "captura" | "dashboard" | "activos" | "redes" | "geovisor">("inicio");      // Corte 11: se entra al inicio por modos
  const [modo, setModo] = useState<Modo | null>(modoGuardado);
  // Corte 6b (§30.2): un enlace compartido del geovisor (#geovisor=<código>) se consume una vez: se quita de la barra de direcciones y abre el geovisor
  const [vistaId, setVistaId] = useState<string | null>(() => /(?:^|[#&])geovisor=([a-z0-9]{10})(?:&|$)/.exec(window.location.hash)?.[1] ?? null);
  const [avisoEnlace, setAvisoEnlace] = useState<string | null>(null);
  const [redesListo, setRedesListo] = useState(false);      // Corte 6a: «geovisor» (N-13: supervisores, administrador y el operador con la casilla)     // Corte 4a: «redes» = Dashboard distribución (supervisor de distribución y administrador)
  const [redes, setRedes] = useState<MiPerfilRedes | null>(null);      // perfil de redes (ver_dashboard_redes), del servidor     // el Dashboard PTAP y la ficha de activos (Corte 1b) son solo para supervisor y administrador en esta pantalla (el servidor lo vuelve a verificar en cada ruta)

  useEffect(() => {
    let vivo = true;
    setErrorMis(null);
    apiDash.miPerfil().then((r) => { if (vivo) setRedes(r); }).catch(() => { if (vivo) setRedes(null); }).finally(() => { if (vivo) setRedesListo(true); });
    apiTec.misFormularios()
      .then((r) => {
        if (!vivo) return;
        setMis(r);      // Corte 11: ningún formulario se abre solo
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
  useEffect(() => {
    if (!vistaId || !redesListo) return;      // se espera a saber si tiene el geovisor
    try { window.history.replaceState(null, "", window.location.pathname + window.location.search); } catch { /* sin historial: no importa */ }
    if (redes?.geovisor) setVista("geovisor");
    else { setAvisoEnlace("Le compartieron una vista del geovisor técnico, pero su cuenta no tiene el geovisor. Pídale a su supervisor que se lo active."); setVistaId(null); }
  }, [vistaId, redesListo]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (elegido && version > 0 && !PANTALLA_PROPIA.has(elegido)) cargarDef(elegido, true); }, [version]); // eslint-disable-line react-hooks/exhaustive-deps

  // ----- errores al entrar -----
  if (errorMis) {
    const a = avisoDeError(errorMis);
    const sinAcceso = errorMis.tipo === "permiso" || errorMis.tipo === "denegado";
    // Corte 11: quien no tiene formularios de Técnica pero sí el Dashboard distribución o el geovisor entra al mismo inicio por modos (sigue más abajo)
    if (!(sinAcceso && (redes?.dashboard_redes || redes?.geovisor))) {
      if (sinAcceso && !redesListo) return <div className="tec-pagina"><p className="tec-sub" role="status">Cargando Técnica…</p></div>;
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
  }
  const soloRedes = errorMis !== null;      // sin formularios de Técnica: solo lo de distribución (dashboard, ficha y geovisor)
  if (!mis && !soloRedes) return <div className="tec-pagina"><p className="tec-sub" role="status">Cargando Técnica…</p></div>;
  const formularios = mis?.formularios ?? [];
  const perfil: MisFormularios["perfil"] = mis?.perfil ?? "operador";
  const rotuloPerfil = soloRedes ? (redes?.dashboard_redes ? "Supervisor de distribución" : "Técnica") : ROTULO_PERFIL[perfil];

  const puedeSupervisar = perfil === "admin" || perfil === "supervisor";      // Dashboard PTAP (planta)
  const puedeRedes = redes?.dashboard_redes === true;                                  // Dashboard distribución (Corte 4a)
  // selector arriba de cada dashboard, cuando la persona tiene los dos (§1 de la bitácora: no se solapan)
  // §34: va DENTRO del encabezado de cada dashboard (antes era un bloque aparte que partía la pantalla en dos)
  const selector = puedeSupervisar && puedeRedes
    ? <SelectorDashboards actual={vista === "redes" ? "distribucion" : "ptap"} onElegir={(d) => setVista(d === "ptap" ? "dashboard" : "redes")} /> : null;

  if (puedeSupervisar && vista === "dashboard") return <Dashboard correo={correo} rotuloPerfil={rotuloPerfil} selector={selector} onVolver={() => setVista("inicio")} />;
  if (puedeRedes && vista === "redes") return <DashboardRedes correo={correo} selector={selector} onVolver={() => setVista("inicio")} onGeovisor={redes?.geovisor ? () => setVista("geovisor") : undefined} />;
  const tieneItv = formularios.some((f) => f.clave === "mantenimiento");
  const abrirItv = (d: DesdeDano | null, a: typeof activoItv) => { setDesdeDano(d); setActivoItv(a); setVezItv((v) => v + 1); setElegido("mantenimiento"); setVista("captura"); window.scrollTo?.(0, 0); };
  const tieneGeovisor = redes?.geovisor === true;                                    // Corte 6a: lo decide el servidor (redes.f_geovisor_lectura)
  const abrirDano = (a: typeof activoDano) => { setActivoDano(a); setVezDano((v) => v + 1); setElegido("danos_fallas"); setVista("captura"); window.scrollTo?.(0, 0); };
  if (tieneGeovisor && vista === "geovisor") return <Geovisor vistaId={vistaId} onVolver={() => { setVistaId(null); setVista("inicio"); }} onReportarDano={(a) => abrirDano(a)} onRegistrarIntervencion={(a) => abrirItv(null, a)} />;
  if ((puedeSupervisar || puedeRedes) && vista === "activos") return <ActivosRedes onVolver={() => setVista("inicio")} onRegistrarIntervencion={tieneItv || puedeSupervisar || puedeRedes ? (a) => abrirItv(null, a) : undefined} />;

  // ----- las tarjetas de cada modo (solo lo que la persona ya tenía) -----
  const abrirForm = (clave: string) => { setElegido(clave); setVista("captura"); window.scrollTo?.(0, 0); };
  const tarjetaForm = (f: MisFormularios["formularios"][number]): Tarjeta => {
    const construido = FORMULARIOS_CON_PANTALLA.has(f.clave);
    const activo = (f.con_campos || PANTALLA_PROPIA.has(f.clave)) && construido;
    return { clave: f.clave, nombre: f.nombre, descripcion: f.descripcion?.trim() || DESCRIPCION[f.clave] || "Formulario de Técnica",
             estado: !construido ? "pronto" : !activo ? "sin_campos" : "lista", abrir: () => abrirForm(f.clave) };
  };
  const orden = (c: string) => { const k = ORDEN_FORM.indexOf(c); return k < 0 ? ORDEN_FORM.length : k; };
  const ordenados = [...formularios].sort((x, y) => orden(x.clave) - orden(y.clave));
  const veFicha = puedeSupervisar || puedeRedes;                       // la ficha de activos (el servidor lo vuelve a verificar)
  const editaFicha = perfil === "admin" || puedeRedes;                 // quién edita la ficha: administrador y supervisor de distribución (Corte 4a)
  const supervisa = puedeSupervisar || puedeRedes;
  const porModo: Record<Modo, Tarjeta[]> = {
    planta: ordenados.filter((f) => !FORMULARIOS_REDES.has(f.clave)).map(tarjetaForm),
    redes: [
      ...ordenados.filter((f) => FORMULARIOS_REDES.has(f.clave)).map(tarjetaForm),
      ...(veFicha ? [{ clave: "ficha_buscar", nombre: "Ficha de activos", descripcion: "Buscar un activo por código, placa o alias", estado: "lista" as const, abrir: () => setVista("activos") }] : []),
      ...(tieneGeovisor && !supervisa ? [{ clave: "geovisor", nombre: "Geovisor técnico (solo lectura)", descripcion: "La red y las actividades de hoy en el mapa", estado: "lista" as const, abrir: () => setVista("geovisor") }] : []),
    ],
    supervision: [
      ...(puedeSupervisar ? [{ clave: "dashboard_ptap", nombre: "Dashboard PTAP", descripcion: "Registros, gráficas, puntos y químicos de planta", estado: "lista" as const, abrir: () => setVista("dashboard") }] : []),
      ...(puedeRedes ? [{ clave: "dashboard_distribucion", nombre: "Dashboard distribución", descripcion: "Daños, intervenciones, personal y cargue de capas", estado: "lista" as const, abrir: () => setVista("redes") }] : []),
      ...(tieneGeovisor && supervisa ? [{ clave: "geovisor", nombre: "Geovisor técnico", descripcion: "La red, las actividades y los contratos en el mapa", estado: "lista" as const, abrir: () => setVista("geovisor") }] : []),
      ...(editaFicha ? [{ clave: "ficha_editar", nombre: "Ficha de activos (editar)", descripcion: "Corregir alias, placa y datos de un activo, con motivo", estado: "lista" as const, abrir: () => setVista("activos") }] : []),
    ],
  };
  const modosVisibles = MODOS.filter((m) => porModo[m.clave].length > 0);
  const modoActual: Modo | null = modosVisibles.some((m) => m.clave === modo) ? modo : modosVisibles[0]?.clave ?? null;
  const nombreElegido = formularios.find((f) => f.clave === elegido)?.nombre ?? "Formulario";
  const volverInicio = () => { setElegido(null); setDef(null); setDesdeDano(null); setActivoItv(null); setActivoDano(null); setVista("inicio"); window.scrollTo?.(0, 0); };

  if (vista !== "captura" || !elegido) {
    return (
      <div className="tec-pagina tec-inicio">
        <header className="tec-inicio-cab">
          <div className="tec-inicio-tit">
            <h1>Técnica</h1>
            <p className="tec-inicio-sesion">Sesión de {correo} · {rotuloPerfil}</p>
          </div>
          {modosVisibles.length > 1 ? (
            <div className="tec-modos" role="tablist" aria-label="Modo de trabajo">
              {modosVisibles.map((m) => (
                <button key={m.clave} type="button" role="tab" id={`tec-modo-${m.clave}`} aria-selected={modoActual === m.clave} aria-controls="tec-modo-panel" data-modo={m.clave}
                  className={`tec-modo tec-modo-${m.clave}`} onClick={() => { setModo(m.clave); guardarModo(m.clave); }}>{m.nombre}</button>
              ))}
            </div>
          ) : null}
        </header>
        {avisoEnlace ? <p className="tec-aviso tec-aviso-info" role="status">{avisoEnlace}</p> : null}
        {modoActual ? (
          <section id="tec-modo-panel" role={modosVisibles.length > 1 ? "tabpanel" : undefined} aria-labelledby={modosVisibles.length > 1 ? `tec-modo-${modoActual}` : undefined}
            aria-label={modosVisibles.length > 1 ? undefined : MODOS.find((m) => m.clave === modoActual)?.nombre} className={`tec-tarjetas tec-tarjetas-${modoActual}`} data-modo-actual={modoActual}>
            {modosVisibles.length === 1 ? <h2 className="tec-modo-unico">{MODOS.find((m) => m.clave === modoActual)?.nombre}</h2> : null}
            <div className="tec-rejilla">
              {porModo[modoActual].map((c) => c.estado === "lista" ? (
                <button key={c.clave} type="button" className="tec-tarjeta-modo" data-tarjeta={c.clave} onClick={c.abrir}>
                  <span className="tec-tarjeta-ini" aria-hidden="true" data-ini={c.nombre.trim().charAt(0).toUpperCase()} />
                  <span className="tec-tarjeta-txt"><span className="tec-tarjeta-nom">{c.nombre}</span><span className="tec-tarjeta-desc">{c.descripcion}</span></span>
                </button>
              ) : (
                <div key={c.clave} className="tec-tarjeta-modo tec-tarjeta-pronto" data-tarjeta={c.clave} aria-disabled="true">
                  <span className="tec-tarjeta-ini" aria-hidden="true" data-ini={c.nombre.trim().charAt(0).toUpperCase()} />
                  <span className="tec-tarjeta-txt"><span className="tec-tarjeta-nom">{c.nombre}<span className="tec-pronto">{c.estado === "pronto" ? "Próximamente" : "Sin campos"}</span></span>
                    <span className="tec-tarjeta-desc">{c.descripcion}</span></span>
                </div>
              ))}
            </div>
          </section>
        ) : (
          <section className="tec-tarjeta" role="status">
            <h1>Todavía no tiene formularios asignados</h1>
            <p>Solicite a su supervisor que le asigne los formularios que debe diligenciar.</p>
          </section>
        )}
      </div>
    );
  }

  return (
    <div className="tec-pagina">
      <div className="tec-volver-barra">
        <button type="button" className="tec-volver" onClick={volverInicio}><span aria-hidden="true">←</span> Volver</button>
        <span className="tec-volver-tit">{nombreElegido}</span>
      </div>

      {elegido === "danos_fallas" ? <FormularioDano key={vezDano} correo={correo} activoInicial={activoDano} onSalir={() => { setActivoDano(null); setVezDano((v) => v + 1); }}
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
