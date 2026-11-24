import { Fragment, Suspense, useEffect, useState } from "react";
import { lazyConRecarga } from "../lib/recarga";
import { fijarAreaCampo } from "./area";
import "../tecnica/tecnica.css";
import "./campo.css";
import "./comercial.css";      // modelo visual de Comercial (guía visual, §3–§5): tokens con el color #782a27 en la clase «com-modulo»
import { apiCampo, avisoDeError, ErrorCampo, type FormularioCampo } from "./apiCampo";
import { ReporteGeneral } from "./ReporteGeneral";
import { FormatosCampo } from "./formatos/FormatosCampo";
import { formatosDisponibles } from "./formatos/tipos";
import { entradasDeCampo, veActasRegistradas, type EntradaId } from "./entradas";
import { PantallaActa } from "./acta/PantallaActa";
import { ActasRegistradas } from "./documentos/ActasRegistradas";
import type { Destino } from "../components/ConfirmarCancelar";
import { supabase } from "../lib/supabase";
import { apiReparto, type Perfil } from "./reparto/apiReparto";

// «Supervisión y dashboard» (antes «Revisión de reportes», Paso C): carga diferida. Quien no tiene el permiso de supervisión no descarga este código (ni MapLibre, que viene dentro del mapa).
const Revision = lazyConRecarga(() => import("./dashboard/Revision"));
// «Análisis de contrato»: también diferida (su mapa trae MapLibre, que solo se descarga al abrir la sección «Ubicación»).
const AnalisisContrato = lazyConRecarga(() => import("./analisis/AnalisisContrato"));
// «Encontrar o reportar activo» (Corte 14 de Técnica): la misma pantalla de Técnica, también diferida (trae MapLibre).
const EncontrarActivo = lazyConRecarga(() => import("../tecnica/EncontrarActivo").then((m) => ({ default: m.EncontrarActivo })));
// «Reparto de facturas» (24-nov): diferidas; solo las descarga quien tiene la actividad (la supervisión trae MapLibre).
const PantallaRepartidor = lazyConRecarga(() => import("./reparto/PantallaRepartidor").then((m) => ({ default: m.PantallaRepartidor })));
const PantallaSupervisorReparto = lazyConRecarga(() => import("./reparto/PantallaSupervisor").then((m) => ({ default: m.PantallaSupervisor })));
/** Formato al que lleva el atajo de posible submedición, y lo que llega marcado («Cambio de medidor»). */
const FORMATO_CAMBIO = "instalacion_medidor";
const VALORES_CAMBIO = { inst_modalidad: "cambio" };

// Sección «Formatos de campo» de la Torre A. Qué puede hacer la persona lo decide el SERVIDOR (ruta formulario); aquí solo se dibuja.
// Se usa como pantalla completa para quien solo tiene campo (sin mapa ni datos comerciales) y como vista dentro del área Comercial para quien tiene las dos cosas.
// Las pantallas son ENTRADAS de una lista (entradas.ts): reporte general, formatos de actividad (Paso D) y acta de inspección (solo con el permiso `acta`; su pantalla aún no existe).
// Los formatos «Próximamente» no tienen acción. Esta lista de formatos es de interfaz (no es el catálogo de tipos de reporte, que viene del servidor).
// «Daños» ya no está: son tipos del Reporte general (daño de red de acueducto y de alcantarillado, tapa de manhole, rejilla de sumidero, daño de obra de terceros); no habrá un formulario aparte.
// «SCRR — Próximamente» pasó a ser la entrada «Análisis de contrato» de entradas.ts (permiso `analisis_contrato`); «Instalación de medidor» y «Revisión previa» ya son formatos de actividad.
const ROTULO_PERFIL: Record<FormularioCampo["perfil"], string> = { admin: "Administrador", supervisor: "Supervisor de reportes de campo", reportante: "Reporte de campo" };

/** Permisos que decide el servidor (App los toma del perfil). `acta`: puede capturar actas (si no se informa, la entrada del acta no aparece). `campo`: tiene permiso de campo; por omisión sí (como antes).
 *  Quien solo tiene acta (`campo` falso) NO pide el formulario de campo (su Edge le respondería 403) y ve únicamente las entradas del acta. `dashboardActa`: supervisor de actas (marcador, sin pantalla aún).
 *  `analisis`: permiso `analisis_contrato` (o administrador). Quien solo tiene este (usuario comercial, decisión 12) tampoco pide el formulario y ve solo la tarjeta «Análisis de contrato». */
type PropsCampo = { correo: string; acta?: boolean; campo?: boolean; dashboardActa?: boolean; analisis?: boolean };
/** Formatos de campo con el modelo visual de Comercial: la envoltura (sin caja) fija los tokens de Comercial para esta pantalla y todo lo que abre. */
export function AreaCampo(p: PropsCampo) {
  return <div className="com-modulo com-envoltura"><PantallasCampo {...p} /></div>;
}

function PantallasCampo({ correo, acta = false, campo = true, dashboardActa = false, analisis = false }: PropsCampo) {
  const [def, setDef] = useState<FormularioCampo | null>(null);
  const [error, setError] = useState<ErrorCampo | null>(null);
  const [intento, setIntento] = useState(0);
  const [abierta, setAbierta] = useState<EntradaId | null>(null);   // pantalla abierta (null = la lista de entradas)
  const [contratoPuente, setContratoPuente] = useState("");   // contrato que pasa de un formulario a otro (formato con irregularidad → acta; «me equivoqué de formulario» al cancelar); vacío = nada que precargar
  const [formatoInicial, setFormatoInicial] = useState<string | undefined>(undefined);                    // atajo de submedición: formato que se abre de una vez…
  const [valoresIniciales, setValoresIniciales] = useState<Record<string, unknown> | undefined>(undefined); // …y lo que trae marcado («Cambio»)
  const [version, setVersion] = useState(0);        // sube con cada «Hacer otro reporte»: el formulario nace limpio y se vuelve a leer la definición
  const [reparto, setReparto] = useState<Perfil>({ es_repartidor: false, es_supervisor: false });   // lo decide el servidor (perfil liviano de geoportal-reparto)

  useEffect(() => { fijarAreaCampo(null); }, []);      // Comercial: sin área (por si antes se abrió un reporte compartido desde Técnica)
  // Reparto de facturas: ¿repartidor o supervisor de reparto? Una consulta liviana (no lee rutas). Si falla, simplemente no aparecen las entradas.
  useEffect(() => {
    if (!campo) return;
    let vivo = true;
    apiReparto.perfil().then((p) => { if (vivo) setReparto(p); }).catch(() => { /* sin la Edge o sin permiso: sin entradas de reparto */ });
    return () => { vivo = false; };
  }, [campo]);
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

  // «Me equivoqué de formulario» (Cancelar): a qué otros formularios se puede pasar desde `desde`, llevando solo el contrato.
  const destinosDesde = (desde: EntradaId): Destino[] => [
    ...(campo && def?.puede.reportar && desde !== "reporte_general" ? [{ id: "reporte_general", rotulo: "Reportar anomalía" }] : []),
    ...(campo && def?.puede.reportar && desde !== "formatos" && formatosDisponibles(def.grupos).length > 0 ? [{ id: "formatos", rotulo: "Formatos de actividad" }] : []),
    ...(acta && desde !== "acta" ? [{ id: "acta", rotulo: "Reportar posible pérdida" }] : []),
  ];
  const irA = (destino: string, contrato: string) => { setContratoPuente(contrato); setFormatoInicial(undefined); setValoresIniciales(undefined); setVersion((v) => v + 1); setAbierta(destino as EntradaId); };
  // Atajo de «Análisis de contrato» (posible submedición): Instalación de medidor con «Cambio» ya marcado y el contrato cargado. Solo si el formato está activo y puede reportar.
  const puedeCambioMedidor = campo && def?.puede.reportar === true && formatosDisponibles(def.grupos).some((g) => g.tipos.some((t) => t.codigo === FORMATO_CAMBIO));
  const abrirCambioMedidor = (contrato: string) => { setContratoPuente(contrato); setFormatoInicial(FORMATO_CAMBIO); setValoresIniciales(VALORES_CAMBIO); setVersion((v) => v + 1); setAbierta("formatos"); };
  const volver = () => { setContratoPuente(""); setFormatoInicial(undefined); setValoresIniciales(undefined); setAbierta(null); };

  if (abierta === "acta" && acta) {
    return <PantallaActa correo={correo} contratoInicial={contratoPuente} destinos={destinosDesde("acta")} onIrA={irA} onVolver={() => { setContratoPuente(""); setAbierta(null); }} />;
  }
  if (def && abierta === "reporte_general") {
    return <ReporteGeneral key={version} def={def} correo={correo} contratoInicial={contratoPuente} destinos={destinosDesde("reporte_general")} onIrA={irA}
      onVolver={() => { setContratoPuente(""); setAbierta(null); }} onOtro={() => { setContratoPuente(""); setAbierta("reporte_general"); setVersion((v) => v + 1); }} />;
  }
  if (def && abierta === "formatos") {
    return <FormatosCampo key={version} def={def} correo={correo} contratoInicial={contratoPuente} destinos={destinosDesde("formatos")} onIrA={irA}
      onVolver={volver} puedeActa={acta} onAbrirActa={(c) => { setContratoPuente(c); setAbierta("acta"); }} formatoInicial={formatoInicial} valoresIniciales={valoresIniciales} />;
  }
  // R3 (22-nov): también el supervisor de campo. Las aperturas y la lectura por geoportal-acta siguen solo con dashboardActa (ActasRegistradas elige la vía por puedeAperturas).
  if (abierta === "acta_supervision" && veActasRegistradas({ puedeSupervisarActas: dashboardActa, puedeSupervisar: def?.puede.supervisar === true })) {
    return <ActasRegistradas correo={correo} onVolver={() => setAbierta(null)} nombres={nombresFormularios(def)} puedeAperturas={dashboardActa} puedeCerrarDerivadas={def?.puede.supervisar === true} />;
  }

  if (abierta === "activo_campo" && campo) {
    return (
      <Suspense fallback={<div className="tec-pagina"><section className="tec-tarjeta"><p>Cargando…</p></section></div>}>
        <EncontrarActivo onVolver={() => setAbierta(null)} rotuloVolver="Volver" />
      </Suspense>
    );
  }

  if (abierta === "analisis_contrato" && analisis) {
    return (
      <Suspense fallback={<div className="tec-pagina"><section className="tec-tarjeta"><p>Cargando Análisis de contrato…</p></section></div>}>
        <AnalisisContrato onVolver={volver} destinos={destinosDesde("analisis_contrato")} onIrA={irA} puedeCambioMedidor={puedeCambioMedidor} onCambioMedidor={abrirCambioMedidor} />
      </Suspense>
    );
  }

  if (abierta === "reparto" && campo && reparto.es_repartidor) {
    return <Suspense fallback={<div className="tec-pagina"><section className="tec-tarjeta"><p>Cargando Reparto de facturas…</p></section></div>}><PantallaRepartidor onVolver={() => setAbierta(null)} /></Suspense>;
  }
  if (abierta === "reparto_supervision" && campo && reparto.es_supervisor) {
    return <Suspense fallback={<div className="tec-pagina"><section className="tec-tarjeta"><p>Cargando la supervisión del reparto…</p></section></div>}><PantallaSupervisorReparto onVolver={() => setAbierta(null)} /></Suspense>;
  }

  if (abierta === "revision" && def?.puede.supervisar) {
    return <Suspense fallback={<div className="tec-pagina"><section className="tec-tarjeta"><p>Cargando Supervisión y dashboard…</p></section></div>}><Revision correo={correo} onVolver={() => setAbierta(null)} /></Suspense>;
  }

  const entradas = entradasDeCampo({
    puedeReportar: def?.puede.reportar ?? false, hayFormatos: def ? formatosDisponibles(def.grupos).length > 0 : false,
    puedeActa: acta, puedeCampo: campo, puedeSupervisarActas: dashboardActa, puedeSupervisar: def?.puede.supervisar ?? false, puedeAnalisis: analisis, puedeActivoCampo: campo,
    puedeRepartir: reparto.es_repartidor, puedeSupervisarReparto: reparto.es_supervisor,
  });

  return (
    <div className="tec-pagina campo-pagina com-inicio">
      <section className="tec-tarjeta com-hoja">
        <h1>{campo || !acta ? "Formatos de campo" : "Reportar posible pérdida"}</h1>
        <p className="campo-sub">{def ? ROTULO_PERFIL[def.perfil] : acta ? "Registro digital de actas" : "Consulta de contratos"}</p>
        <div className="campo-formatos">
          {entradas.map((e, i) => {
            const separar = i > 0 && entradas[i - 1].seccion !== e.seccion;
            const clase = `campo-formato${e.gestion ? " campo-formato-gestion" : ""}${e.abreMas ? " campo-formato-mas" : ""}`;
            return (
              <Fragment key={e.id}>
                {separar ? <hr className="campo-separador" aria-hidden="true" /> : null}
                {e.pendiente ? (
                  <div className={`${clase} campo-formato-proximo`} aria-disabled="true">
                    <span className="com-tarjeta-ini" data-ini={e.titulo.charAt(0)} aria-hidden="true" />
                    <span className="com-tarjeta-txt"><strong>{e.titulo}</strong><span>Próximamente. {e.descripcion}</span></span>
                  </div>
                ) : (
                  <button type="button" className={`${clase} campo-formato-activo`} onClick={() => setAbierta(e.id)} disabled={!e.habilitada}>
                    <span className="com-tarjeta-ini" data-ini={e.titulo.charAt(0)} aria-hidden="true" />
                    <span className="com-tarjeta-txt"><strong>{e.titulo}</strong>{e.descripcion ? <span>{e.descripcion}</span> : null}</span>
                    {e.abreMas ? <span className="campo-formato-flecha" aria-hidden="true">›</span> : null}
                  </button>
                )}
              </Fragment>
            );
          })}
        </div>
      </section>
    </div>
  );
}

/** Nombre de cada formulario por su código (del catálogo de Formatos de campo) más el acta de posible pérdida: para el selector de «Actas registradas». */
function nombresFormularios(def: FormularioCampo | null): Map<string, string> {
  const m = new Map<string, string>([["acta", "Reportar posible pérdida"]]);
  for (const g of def?.grupos ?? []) for (const t of g.tipos) m.set(t.codigo, t.nombre);
  return m;
}
