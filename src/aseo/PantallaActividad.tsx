import { useEffect, useRef, useState } from "react";
import { apiAseo, avisoDeError, ErrorAseo } from "./apiAseo";
import { SelectorRuta } from "./SelectorRuta";
import { FormularioAuditoria, type ResultadoAuditoria } from "./FormularioAuditoria";
import { ConfirmacionActa } from "./ConfirmacionActa";
import type { Actividad, FormularioAseo, Modalidad, PlanResp, RutaPlan } from "./tipos";

// Flujo de una actividad (hoy: Barrido): 1) modalidad (Manual o Mecánico, del catálogo) → 2) ruta (búsqueda o mapa) → 3) formulario con la ruta precargada → 4) registro y acta con el membrete.
export function PantallaActividad({ def, actividad, auditor, onSalir }: { def: FormularioAseo; actividad: Actividad; auditor: { nombre: string; correo: string }; onSalir: () => void }) {
  const [modalidad, setModalidad] = useState<Modalidad | null>(null);
  const [plan, setPlan] = useState<PlanResp | null>(null);
  const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [intento, setIntento] = useState(0);
  const [ruta, setRuta] = useState<RutaPlan | null>(null);
  const [resultado, setResultado] = useState<ResultadoAuditoria | null>(null);
  const cache = useRef(new Map<string, PlanResp>());
  const modalidades = (actividad.modalidades ?? []).filter((m) => m.activa).sort((a, b) => (a.orden ?? 0) - (b.orden ?? 0));

  useEffect(() => {
    if (!modalidad) return;
    const k = `${actividad.codigo}/${modalidad.codigo}`;
    let vivo = true; setError(null);
    const previo = cache.current.get(k);
    if (previo) setPlan(previo); else setPlan(null);
    apiAseo.plan(actividad.codigo, modalidad.codigo, previo?.etag).then((r) => {
      if (!vivo) return;
      if (r.sin_cambios && previo) { setPlan({ ...previo, ahora: r.ahora ?? previo.ahora }); return; }
      cache.current.set(k, r); setPlan(r);
    }).catch((e) => { if (vivo) setError({ texto: e instanceof ErrorAseo ? avisoDeError(e).texto : "No se pudo cargar las rutas.", sesion: e instanceof ErrorAseo && e.tipo === "sesion" }); });
    return () => { vivo = false; };
  }, [modalidad, actividad.codigo, intento]);

  if (resultado) return <ConfirmacionActa r={resultado} auditor={auditor} onSalir={onSalir} onOtra={() => { setResultado(null); setRuta(null); }} />;

  if (ruta && modalidad && plan) {
    return <FormularioAuditoria def={def} actividad={actividad} modalidad={modalidad} ruta={ruta} ahora={plan.ahora ?? def.ahora} onVolver={() => setRuta(null)} onListo={setResultado} />;
  }

  return (
    <div className="tec-pagina campo-pagina">
      <section className="tec-tarjeta">
        <div className="campo-cab"><button type="button" className="tec-boton-sec" onClick={modalidad ? () => { setModalidad(null); setPlan(null); } : onSalir}>‹ {modalidad ? "Modalidad" : "Aseo"}</button><h1>{actividad.nombre}{modalidad ? ` · ${modalidad.nombre}` : ""}</h1></div>
        {!modalidad ? (
          <>
            <p className="campo-sub">Elija la modalidad que va a auditar.</p>
            {modalidades.length === 0 ? <p className="aseo-aviso" role="alert">La actividad no tiene modalidades activas. Avise al administrador.</p> : (
              <div className="campo-formatos">{modalidades.map((m) => (
                <button key={m.codigo} type="button" className="campo-formato campo-formato-activo" onClick={() => setModalidad(m)}><strong>{m.nombre}</strong><span>{m.servicios.filter((s) => s.activo !== false).map((s) => s.nombre).join(", ")}</span></button>))}</div>)}
          </>
        ) : error ? (
          <div className="campo-error" role="alert"><p>{error.texto}</p>{!error.sesion ? <button type="button" className="tec-boton" onClick={() => setIntento((i) => i + 1)}>Reintentar</button> : null}</div>
        ) : !plan || !plan.rutas ? <p className="campo-sub">Cargando las rutas…</p> : (
          <SelectorRuta actividad={actividad.codigo} modalidad={modalidad.codigo} rutas={plan.rutas} ahora={plan.ahora ?? def.ahora} minCaracteres={def.limites.busqueda_min_caracteres} zoomInicial={def.limites.mapa_zoom_inicial} onElegir={setRuta} />
        )}
      </section>
    </div>
  );
}
