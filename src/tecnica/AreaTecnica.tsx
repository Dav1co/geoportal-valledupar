import { useCallback, useEffect, useState } from "react";
import "./tokens.css";      // Corte 13: los tokens de Técnica (colores por modo, fuente, tamaños, espacios y radios)
import "./tecnica.css";
import { apiTec, ErrorTec, type FormularioDef, type MisFormularios } from "./apiTecnica";
import { FormularioCaptura, avisoDeError } from "./FormularioCaptura";
import { FormularioPorLugar } from "./FormularioPorLugar";
import { ResumenUltimas24 } from "./ResumenUltimas24";
import { Dashboard } from "./Dashboard";
import { ActivosRedes } from "./ActivosRedes";
import { FormularioDano } from "./FormularioDano";
import { FormularioQuimicos } from "./FormularioQuimicos";
import { ReporteCompartido } from "./ReporteCompartido";
import { FormularioIntervencion, type DesdeDano } from "./FormularioIntervencion";
import { DashboardRedes } from "./DashboardRedes";
import { Geovisor } from "./Geovisor";
import { SelectorDashboards } from "./CabeceraDashboard";
import { apiDash, type MiPerfilRedes } from "./apiRedes";
import { pedirPestana } from "./CabeceraDashboard";
import { AvisosContexto, PantallaAvisos, resolverBandeja, useAvisos } from "./Avisos";
import type { Bandeja } from "./apiAvisos";
import { EncontrarActivo } from "./EncontrarActivo";      // Corte 14
import { EventosSuspension } from "./EventosSuspension";      // Corte 15: «Suspensiones» en el inicio y el aviso que abre su evento
import { supabase } from "../lib/supabase";
import { DashboardPTAR } from "./ptar/DashboardPTAR";      // PTAR-2 (Code C): el cuarto modo «PTAR» y su Dashboard
import { SistemaControlPTAR } from "./ptar/SistemaControlPTAR";      // PTAR-3: el mapa de la planta en su vista propia
import { apiPtar, type PerfilPtar } from "./ptar/apiPtar";
import "./ptar/tokens_ptar.css";

// Área Técnica (Torre B) en el celular. Qué formularios ve cada persona y qué perfil tiene lo decide el SERVIDOR (ruta mis_formularios); aquí solo se dibuja.
// Formularios que ya tienen pantalla construida (el resto se muestra deshabilitado, «Próximamente»). Esta lista no contiene variables ni nombres de campos.
const FORMULARIOS_CON_PANTALLA = new Set(["entrada", "salida", "muestreo", "danos_fallas", "mantenimiento", "entrada_quimicos", "uso_quimicos", "anomalia_compartida", "revision_compartida", "ptar_caracterizacion"]);      // PTAR-3: la Caracterización (FormularioPorLugar, puntos de la PTAR)   // Corte 7b: los dos de químicos. Corte 8: los dos compartidos con Comercial   // mantenimiento = «Registrar intervención» (Corte 3a)      // danos_fallas: pantalla propia (Corte 2), no usa variables. Muestreo: con FormularioPorLugar (variables «por punto»), lista de puntos del servidor
const PANTALLA_PROPIA = new Set(["danos_fallas", "mantenimiento", "entrada_quimicos", "uso_quimicos", "anomalia_compartida", "revision_compartida"]);      // formularios con pantalla propia, sin variables de planta (con_campos = false en el servidor)
const ROTULO_PERFIL: Record<MisFormularios["perfil"], string> = { admin: "Administrador", supervisor: "Supervisor técnico", operador: "Operador técnico" };

// Corte 11 (render aprobado por David, 16-nov 13:30): el inicio de Técnica va por MODOS de trabajo (Planta, Redes y Supervisión), con tarjetas grandes.
// Ningún formulario se abre solo; cada persona ve solo los modos en los que tiene algo (lo decide el servidor: formularios asignados, dashboards y geovisor);
// con un solo modo no hay selector. Aquí no hay permisos nuevos: solo se reparte lo que ya llegaba.
type Modo = "planta" | "redes" | "supervision" | "ptar";      // PTAR-2 (D5): cuarto modo, en pizarra
// Corte 13 (David, 16:30): «Planta» pasa a «Plantas» y «Redes» a «Distribución». Las claves internas no cambian (el modo recordado de cada persona sigue sirviendo).
const MODOS: { clave: Modo; nombre: string }[] = [{ clave: "planta", nombre: "Plantas" }, { clave: "redes", nombre: "Distribución" }, { clave: "supervision", nombre: "Supervisión" }, { clave: "ptar", nombre: "PTAR" }];
const CLASE_MODO: Record<Modo, string> = { planta: "tec-modo-plantas", redes: "tec-modo-distribucion", supervision: "tec-modo-supervision", ptar: "tec-modo-ptar" };
const FORMULARIOS_REDES = new Set(["danos_fallas", "mantenimiento", "anomalia_compartida", "revision_compartida"]);      // Corte 8: los compartidos van en Redes      // los demás formularios asignados son de planta
const ORDEN_FORM = ["entrada", "salida", "muestreo", "entrada_quimicos", "uso_quimicos", "danos_fallas", "mantenimiento", "anomalia_compartida", "revision_compartida", "ptar_caracterizacion"];
const esPtar = (clave: string) => clave.startsWith("ptar_");      // PTAR-3: los formularios de la PTAR van en el modo PTAR
const DESCRIPCION: Record<string, string> = {
  entrada: "El agua que llega a la planta", salida: "El agua tratada que sale a la red", muestreo: "Cloro y turbiedad en los puntos de la red",
  entrada_quimicos: "Lo que llega a la bodega, en toneladas o kg", uso_quimicos: "Lo que se gastó en la planta",
  danos_fallas: "Un daño o una falla en la red de acueducto o alcantarillado", mantenimiento: "Registrar una reparación, un mantenimiento o una obra",
  anomalia_compartida: "El mismo reporte de anomalías de Comercial", revision_compartida: "La misma revisión general de Comercial",
  ptar_caracterizacion: "Caudal y resultados del laboratorio en el afluente, el efluente y el río Cesar",
};
const DESCRIPCION_PROPIA = new Set(["danos_fallas", "mantenimiento", "ptar_caracterizacion"]);
type Tarjeta = { clave: string; nombre: string; descripcion: string; estado: "lista" | "pronto" | "sin_campos"; abrir: () => void; contador?: { n: number; nivel: "rojo" | "naranja" | "info" } };
const CLAVE_MODO = "tec_modo";
function modoGuardado(): Modo | null {
  try { const m = window.localStorage.getItem(CLAVE_MODO); return m === "planta" || m === "redes" || m === "supervision" || m === "ptar" ? m : null; } catch { return null; }
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
  const [vista, setVista] = useState<"inicio" | "captura" | "dashboard" | "activos" | "redes" | "geovisor" | "avisos" | "encontrar" | "suspensiones" | "ptar" | "control_ptar">("inicio");      // PTAR-2: «ptar» = Dashboard PTAR · PTAR-3: «control_ptar» = Sistema de Control PTAR
  const [controlDesde, setControlDesde] = useState<"inicio" | "ptar">("inicio");      // a dónde vuelve el Sistema de Control      // Corte 15: «suspensiones»      // Corte 14: «encontrar»      // Corte 12: «avisos»      // Corte 11: se entra al inicio por modos
  const [eventoSusp, setEventoSusp] = useState<{ codigo: string | null; vez: number; desde: "inicio" | "avisos" | "dashboard" | "redes" }>({ codigo: null, vez: 0, desde: "inicio" });      // el evento que se abre directo (desde su aviso) y a dónde vuelve
  const [modo, setModo] = useState<Modo | null>(modoGuardado);
  // Corte 6b (§30.2): un enlace compartido del geovisor (#geovisor=<código>) se consume una vez: se quita de la barra de direcciones y abre el geovisor
  const [vistaId, setVistaId] = useState<string | null>(() => /(?:^|[#&])geovisor=([a-z0-9]{10})(?:&|$)/.exec(window.location.hash)?.[1] ?? null);
  const [avisoEnlace, setAvisoEnlace] = useState<string | null>(null);
  const [redesListo, setRedesListo] = useState(false);      // Corte 6a: «geovisor» (N-13: supervisores, administrador y el operador con la casilla)     // Corte 4a: «redes» = Dashboard distribución (supervisor de distribución y administrador)
  const [redes, setRedes] = useState<MiPerfilRedes | null>(null);
  const [ptar, setPtar] = useState<PerfilPtar | null>(null);      // PTAR-2: alcance PTAP / PTAR (D6), del servidor; si la ruta falla, todo queda como antes (PTAP sí, PTAR no)      // perfil de redes (ver_dashboard_redes), del servidor     // el Dashboard PTAP y la ficha de activos (Corte 1b) son solo para supervisor y administrador en esta pantalla (el servidor lo vuelve a verificar en cada ruta)

  useEffect(() => {
    let vivo = true;
    setErrorMis(null);
    apiPtar.perfil().then((r) => { if (vivo) setPtar(r); }).catch(() => { if (vivo) setPtar(null); });
    apiDash.miPerfil().then((r) => { if (vivo) setRedes(r); }).catch(() => { if (vivo) setRedes(null); }).finally(() => { if (vivo) setRedesListo(true); });
    apiTec.misFormularios()
      .then((r) => {
        if (!vivo) return;
        setMis(r);      // Corte 11: ningún formulario se abre solo
      })
      .catch((e) => { if (vivo) setErrorMis(e instanceof ErrorTec ? e : new ErrorTec("servidor", "No se pudo cargar.", 0)); });
    return () => { vivo = false; };
  }, [intento]);

  // Corte 12: los avisos (solo supervisores y administrador; el servidor decide qué áreas). Se piden cuando se sabe que la persona supervisa.
  const supervisaAlgo = ((mis?.perfil === "admin" || mis?.perfil === "supervisor") && ptar?.ptap !== false) || redes?.dashboard_redes === true;      // PTAR-2: quien solo tiene la PTAR no recibe los avisos de la PTAP
  const avisos = useAvisos(supervisaAlgo);

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
    if (!(sinAcceso && (redes?.dashboard_redes || redes?.geovisor || redes?.activo_campo))) {
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

  const puedeSupervisar = (perfil === "admin" || perfil === "supervisor") && ptar?.ptap !== false;      // Dashboard PTAP (planta); PTAR-2 (D6): sin el alcance PTAP, no
  const puedePtar = ptar?.ptar === true;                                                                // Dashboard PTAR y su mapa (D6: alcance PTAR)
  const puedeRedes = redes?.dashboard_redes === true;                                  // Dashboard distribución (Corte 4a)
  // selector arriba de cada dashboard, cuando la persona tiene los dos (§1 de la bitácora: no se solapan)
  // §34: va DENTRO del encabezado de cada dashboard (antes era un bloque aparte que partía la pantalla en dos)
  // PTAR-2: con el Dashboard PTAR son hasta tres; el selector sale cuando hay dos o más
  const tableros = [...(puedeSupervisar ? ["ptap" as const] : []), ...(puedePtar ? ["ptar" as const] : []), ...(puedeRedes ? ["distribucion" as const] : [])];
  const selector = tableros.length > 1
    ? <SelectorDashboards opciones={tableros} actual={vista === "redes" ? "distribucion" : vista === "ptar" ? "ptar" : "ptap"} onElegir={(d) => { setVista(d === "ptap" ? "dashboard" : d === "ptar" ? "ptar" : "redes"); window.scrollTo?.(0, 0); }} /> : null;

  // Corte 12: un aviso abre su bandeja (el dashboard y la pestaña que corresponde)
  // Corte 15: los eventos de suspensión los ven el administrador, el supervisor de planta y el de distribución (el servidor lo vuelve a decidir en cada ruta)
  const abrirSuspensiones = (evento: string | null, desde: "inicio" | "avisos" | "dashboard" | "redes") => { setEventoSusp((e) => ({ codigo: evento, vez: e.vez + 1, desde })); setVista("suspensiones"); window.scrollTo?.(0, 0); };
  const abrirBandeja = (b: Bandeja) => {
    if (b.evento) { abrirSuspensiones(b.evento, vista === "avisos" || vista === "dashboard" || vista === "redes" ? vista : "inicio"); return; }      // el aviso de un evento abre ese evento y «Volver» regresa a donde estaba
    const r = resolverBandeja(b, puedeRedes);
    const tablero = r.tablero === "distribucion" && !puedeRedes ? "ptap" : r.tablero;
    if (tablero === "ptap" && !puedeSupervisar) return;
    pedirPestana(r.pestana);
    setVista(tablero === "ptap" ? "dashboard" : "redes"); window.scrollTo?.(0, 0);
  };
  const ctxAvisos = (tablero: "ptap" | "distribucion") => ({ estado: avisos, tablero, tieneDistribucion: puedeRedes, onVer: () => setVista("avisos"), onAbrir: abrirBandeja });
  if ((puedeSupervisar || puedeRedes) && vista === "suspensiones") return (
    <div className="tec-envoltura tec-modo-distribucion">
      <EventosSuspension key={eventoSusp.vez} inicial={eventoSusp.codigo ? { evento: eventoSusp.codigo } : undefined} alCambiar={avisos.recargar}
        rotuloVolver={eventoSusp.desde === "avisos" ? "Volver a los avisos" : "Volver"} onVolver={() => { setVista(eventoSusp.desde); window.scrollTo?.(0, 0); }} />
    </div>);
  if ((puedeSupervisar || puedeRedes) && vista === "avisos") return <PantallaAvisos estado={avisos} tieneDistribucion={puedeRedes} onAbrir={abrirBandeja} onVolver={() => setVista("inicio")} />;
  if (puedeSupervisar && vista === "dashboard") return <AvisosContexto.Provider value={ctxAvisos("ptap")}><Dashboard correo={correo} rotuloPerfil={rotuloPerfil} selector={selector} onVolver={() => setVista("inicio")} /></AvisosContexto.Provider>;
  const abrirControl = (desde: "inicio" | "ptar") => { setControlDesde(desde); setVista("control_ptar"); window.scrollTo?.(0, 0); };
  if (puedePtar && vista === "control_ptar") return <div className="tec-envoltura tec-modo-ptar"><SistemaControlPTAR rotuloVolver={controlDesde === "ptar" ? "Volver al Dashboard PTAR" : "Volver al inicio"} onVolver={() => { setVista(controlDesde); window.scrollTo?.(0, 0); }} /></div>;
  if (puedePtar && vista === "ptar") return <DashboardPTAR correo={correo} rotuloPerfil={rotuloPerfil} admin={ptar?.admin === true} selector={selector} onVolver={() => setVista("inicio")} onControl={() => abrirControl("ptar")} />;
  if (puedeRedes && vista === "redes") return <AvisosContexto.Provider value={ctxAvisos("distribucion")}><DashboardRedes correo={correo} selector={selector} onVolver={() => setVista("inicio")} onGeovisor={redes?.geovisor ? () => setVista("geovisor") : undefined} /></AvisosContexto.Provider>;
  const tieneItv = formularios.some((f) => f.clave === "mantenimiento");
  const abrirItv = (d: DesdeDano | null, a: typeof activoItv) => { setDesdeDano(d); setActivoItv(a); setVezItv((v) => v + 1); setElegido("mantenimiento"); setVista("captura"); window.scrollTo?.(0, 0); };
  const tieneGeovisor = redes?.geovisor === true;                                    // Corte 6a: lo decide el servidor (redes.f_geovisor_lectura)
  const abrirDano = (a: typeof activoDano) => { setActivoDano(a); setVezDano((v) => v + 1); setElegido("danos_fallas"); setVista("captura"); window.scrollTo?.(0, 0); };
  if (tieneGeovisor && vista === "geovisor") return <div className="tec-envoltura tec-modo-geovisor"><Geovisor vistaId={vistaId} onVolver={() => { setVistaId(null); setVista("inicio"); }} onReportarDano={(a) => abrirDano(a)} onRegistrarIntervencion={(a) => abrirItv(null, a)} /></div>;
  const fichaBuscar = redes?.ficha_buscar === true;      // 9a-bis (David, 16-nov): la Ficha de activos en modo buscar (solo lectura) también para el operador de redes; lo decide el servidor
  if ((puedeSupervisar || puedeRedes || fichaBuscar) && vista === "activos") return <div className="tec-envoltura tec-modo-distribucion"><ActivosRedes onVolver={() => setVista("inicio")} onRegistrarIntervencion={tieneItv || puedeSupervisar || puedeRedes ? (a) => abrirItv(null, a) : undefined} /></div>;

  // Corte 14: «Encontrar o reportar activo» (lo decide el servidor: administrador, supervisores y el operador con el formulario asignado en Personal)
  const encontrar = redes?.activo_campo === true;
  if (encontrar && vista === "encontrar") return <EncontrarActivo onVolver={() => setVista("inicio")} onReportarDano={(a) => abrirDano(a)} />;
  const tarjetaEncontrar = { clave: "activo_campo", nombre: "Encontrar o reportar activo", descripcion: "Los activos que tiene cerca, o reportar uno que no está en la red", estado: "lista" as const, abrir: () => { setVista("encontrar"); window.scrollTo?.(0, 0); } };

  // Corte 15: «Suspensiones». En Plantas para el supervisor de planta y el administrador; en Supervisión para el supervisor de distribución (David, 19-nov)
  const tarjetaSuspensiones: Tarjeta = { clave: "suspensiones", nombre: "Suspensiones", descripcion: "Eventos de suspensión del servicio: declarar, ver a quién afecta y cerrar", estado: "lista", abrir: () => abrirSuspensiones(null, "inicio") };
  // ----- las tarjetas de cada modo (solo lo que la persona ya tenía) -----
  const abrirForm = (clave: string) => { setElegido(clave); setVista("captura"); window.scrollTo?.(0, 0); };
  const tarjetaForm = (f: MisFormularios["formularios"][number]): Tarjeta => {
    const construido = FORMULARIOS_CON_PANTALLA.has(f.clave);
    const activo = (f.con_campos || PANTALLA_PROPIA.has(f.clave)) && construido;
    // Corte 13: en los de distribución manda la descripción de aquí (la del servidor decía «Daños o fallas en la planta» y repetía el nombre de la intervención)
    return { clave: f.clave, nombre: f.nombre, descripcion: (DESCRIPCION_PROPIA.has(f.clave) ? DESCRIPCION[f.clave] : null) || f.descripcion?.trim() || DESCRIPCION[f.clave] || "Formulario de Técnica",
             estado: !construido ? "pronto" : !activo ? "sin_campos" : "lista", abrir: () => abrirForm(f.clave) };
  };
  const orden = (c: string) => { const k = ORDEN_FORM.indexOf(c); return k < 0 ? ORDEN_FORM.length : k; };
  // «activo_campo» tiene su propia tarjeta (tarjetaEncontrar): si el servidor lo lista entre los formularios, no se repite
  const ordenados = formularios.filter((f) => f.clave !== "activo_campo").sort((x, y) => orden(x.clave) - orden(y.clave));
  const veFicha = puedeSupervisar || puedeRedes || fichaBuscar;        // la ficha de activos (el servidor lo vuelve a verificar)
  const editaFicha = perfil === "admin" || puedeRedes;                 // quién edita la ficha: administrador y supervisor de distribución (Corte 4a)
  const supervisa = puedeSupervisar || puedeRedes;
  // «Encontrar o reportar activo» (David, 17-nov): en Distribución para todo el que lo tiene; en Plantas para quien tiene formularios de planta,
  // los supervisores y el administrador. Ya no va en Supervisión.
  // PTAR-2 (D6): quien solo tiene la PTAR no ve los formularios de la PTAP (el servidor los cierra en PTAR-4, f_autorizar_captura)
  // 24-nov: el alcance PTAP/PTAR existe SOLO para supervisor y administrador. geoportal_tec_ptar_perfil devuelve ptap:false a todo el que no lo es, así que al
  // operador no se le puede vaciar la lista por eso: sus formularios son los que el servidor le entrega en mis_formularios (que además decide cada ruta).
  const alcanceSinPtap = (perfil === "admin" || perfil === "supervisor") && ptar?.ptap === false;
  const formulariosPlanta = alcanceSinPtap ? [] : ordenados.filter((f) => !FORMULARIOS_REDES.has(f.clave) && !esPtar(f.clave));
  // PTAR-3: los de la PTAR (Caracterización), para quien tiene el alcance PTAR o es operador con el formulario asignado (el servidor lo vuelve a decidir)
  const formulariosPtar = puedePtar || perfil === "operador" ? ordenados.filter((f) => esPtar(f.clave)) : [];
  const porModo: Record<Modo, Tarjeta[]> = {
    planta: [
      ...formulariosPlanta.map(tarjetaForm),
      ...(encontrar && (formulariosPlanta.length > 0 || supervisa) ? [tarjetaEncontrar] : []),
      ...(puedeSupervisar ? [tarjetaSuspensiones] : []),
    ],
    redes: [
      ...ordenados.filter((f) => FORMULARIOS_REDES.has(f.clave)).map(tarjetaForm),
      ...(encontrar ? [tarjetaEncontrar] : []),
      ...(veFicha ? [{ clave: "ficha_buscar", nombre: "Ficha de activos", descripcion: "Buscar un activo por código, placa o alias", estado: "lista" as const, abrir: () => setVista("activos") }] : []),
      ...(tieneGeovisor && !supervisa ? [{ clave: "geovisor", nombre: "Geovisor técnico (solo lectura)", descripcion: "La red y las actividades de hoy en el mapa", estado: "lista" as const, abrir: () => setVista("geovisor") }] : []),
    ],
    supervision: [
      ...(supervisa ? [{ clave: "avisos", nombre: "Avisos", estado: "lista" as const, abrir: () => setVista("avisos"),
          descripcion: avisos.datos ? (avisos.datos.total === 0 ? "Nada pendiente por ahora" : `${avisos.datos.rojos} urgentes · ${avisos.datos.naranjas} de atención`) : "Lo que falta por hacer o pasó su plazo",
          contador: avisos.datos ? { n: avisos.datos.total, nivel: avisos.datos.rojos > 0 ? "rojo" as const : avisos.datos.naranjas > 0 ? "naranja" as const : "info" as const } : undefined }] : []),
      ...(puedeSupervisar ? [{ clave: "dashboard_ptap", nombre: "Dashboard PTAP", descripcion: "Registros, gráficas, puntos y químicos de planta", estado: "lista" as const, abrir: () => setVista("dashboard") }] : []),
      ...(puedeRedes ? [tarjetaSuspensiones] : []),
      ...(puedeRedes ? [{ clave: "dashboard_distribucion", nombre: "Dashboard distribución", descripcion: "Daños, intervenciones, personal y cargue de capas", estado: "lista" as const, abrir: () => setVista("redes") }] : []),
      ...(tieneGeovisor && supervisa ? [{ clave: "geovisor", nombre: "Geovisor técnico", descripcion: "La red, las actividades y los contratos en el mapa", estado: "lista" as const, abrir: () => setVista("geovisor") }] : []),
      ...(editaFicha ? [{ clave: "ficha_editar", nombre: "Ficha de activos (editar)", descripcion: "Corregir alias, placa y datos de un activo, con motivo", estado: "lista" as const, abrir: () => setVista("activos") }] : []),
    ],
    // PTAR-2 (D5): el cuarto modo. El Dashboard PTAR (con el mapa) funciona; los tres formularios quedan en «Próximamente» hasta PTAR-4
    ptar: [
      ...(puedePtar ? [{ clave: "control_ptar", nombre: "Sistema de Control PTAR", descripcion: "El mapa de la planta: lagunas, colectores, pozos y puntos de medición con sus parámetros", estado: "lista" as const, abrir: () => abrirControl("inicio") }] : []),
      ...(puedePtar ? [{ clave: "dashboard_ptar", nombre: "Dashboard PTAR", descripcion: "Secciones de la PTAR El Salguero y el acceso al Sistema de Control", estado: "lista" as const, abrir: () => { setVista("ptar"); window.scrollTo?.(0, 0); } }] : []),
      ...formulariosPtar.map(tarjetaForm),
      ...(puedePtar ? [
      { clave: "ptar_afluente", nombre: "Afluente", descripcion: "El agua residual que llega a la planta", estado: "pronto" as const, abrir: () => {} },
      { clave: "ptar_lagunas", nombre: "Entre lagunas", descripcion: "Las mediciones entre una laguna y la siguiente", estado: "pronto" as const, abrir: () => {} },
      { clave: "ptar_efluente", nombre: "Efluente", descripcion: "El agua tratada que sale al río", estado: "pronto" as const, abrir: () => {} },
      ] : []),
    ],
  };
  const modosVisibles = MODOS.filter((m) => porModo[m.clave].length > 0);
  // La primera vez (sin modo recordado): quien no tiene formularios propios y sí supervisa (el supervisor de distribución) abre en Supervisión (David, 16-nov 14:39)
  const modoInicial: Modo | null = formularios.length === 0 && porModo.supervision.length > 0 ? "supervision" : modosVisibles[0]?.clave ?? null;
  const modoActual: Modo | null = modosVisibles.some((m) => m.clave === modo) ? modo : modoInicial;
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
            aria-label={modosVisibles.length > 1 ? undefined : MODOS.find((m) => m.clave === modoActual)?.nombre} className={`tec-tarjetas tec-tarjetas-${modoActual} ${CLASE_MODO[modoActual]}`} data-modo-actual={modoActual}>
            {modosVisibles.length === 1 ? <h2 className="tec-modo-unico">{MODOS.find((m) => m.clave === modoActual)?.nombre}</h2> : null}
            <div className="tec-rejilla">
              {porModo[modoActual].map((c) => c.estado === "lista" ? (
                <button key={c.clave} type="button" className="tec-tarjeta-modo" data-tarjeta={c.clave} onClick={c.abrir}>
                  <span className="tec-tarjeta-ini" aria-hidden="true" data-ini={c.nombre.trim().charAt(0).toUpperCase()} />
                  <span className="tec-tarjeta-txt"><span className="tec-tarjeta-nom">{c.nombre}{c.contador ? <span className={`tec-contador tec-contador-${c.contador.nivel}`} data-contador={c.contador.n} aria-label={`${c.contador.n} avisos`}>{c.contador.n}</span> : null}</span><span className="tec-tarjeta-desc">{c.descripcion}</span></span>
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
    <div className={`tec-pagina ${FORMULARIOS_REDES.has(elegido) ? "tec-modo-distribucion" : esPtar(elegido) ? "tec-modo-ptar" : "tec-modo-plantas"}`} data-modo-form={FORMULARIOS_REDES.has(elegido) ? "distribucion" : esPtar(elegido) ? "ptar" : "plantas"}>
      <div className="tec-volver-barra">
        <button type="button" className="tec-volver" onClick={volverInicio}><span aria-hidden="true">←</span> Volver</button>
        <span className="tec-volver-tit">{nombreElegido}</span>
      </div>

      {elegido === "anomalia_compartida" || elegido === "revision_compartida" ? <ReporteCompartido key={elegido} formulario={elegido} correo={correo} onVolver={volverInicio} /> : null}
      {elegido === "entrada_quimicos" || elegido === "uso_quimicos" ? <FormularioQuimicos key={elegido} formulario={elegido} onSalir={volverInicio} /> : null}
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
