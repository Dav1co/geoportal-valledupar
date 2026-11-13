import { useCallback, useEffect, useRef, useState } from "react";
import { apiDash, textoError, type AvisosTurbiedadResp, type UmbralesResp, type UmbralPlanta } from "./apiDashboard";
import { fmtFecha, fmtInstante, fmtValor } from "./formato";
import { interpretarNumero } from "./numeros";

// Dashboard técnico · AVISO DE TURBIEDAD ALTA. Solo supervisor y administrador (el servidor lo verifica en cada ruta; el operador no tiene Dashboard y recibe 403).
// El aviso es informativo: no marca el registro, no entra a la revisión de «Eventos» y no es el máximo de referencia (5.000 NTU). Sin umbral fijado para la planta = apagado.
// Ningún nombre de planta está escrito aquí: todo sale del servidor.
const REFRESCO_MS = 60_000;

/** Banners por planta. Si la consulta falla NO muestra nada ni tapa el resto de la pantalla (el aviso nunca debe romper Resumen ni Eventos). `version` fuerza una recarga. */
export function AvisoTurbiedad({ version = 0 }: { version?: number }) {
  const [datos, setDatos] = useState<AvisosTurbiedadResp | null>(null);
  const v = useRef(0);
  const cargar = useCallback(async () => {
    const mi = ++v.current;
    try { const x = await apiDash.avisosTurbiedad(); if (mi === v.current) setDatos(x); }
    catch { if (mi === v.current) setDatos(null); }
  }, []);
  useEffect(() => { void cargar(); }, [cargar, version]);
  useEffect(() => {
    const id = setInterval(() => { if (document.visibilityState !== "hidden") void cargar(); }, REFRESCO_MS);
    return () => clearInterval(id);
  }, [cargar]);
  if (!datos || datos.avisos.length === 0) return null;
  return (
    <div className="tav-lista" data-testid="avisos-turbiedad" role="status" aria-live="polite">
      {datos.avisos.map((a) => (
        <div key={a.planta} className="tav" data-planta={a.planta}>
          <div className="tav-texto"><span aria-hidden="true">⚠ </span>
            <strong>Turbiedad de ingreso alta ({fmtValor(a.valor, a.decimales)} {a.unidad} en planta {a.planta_nombre}).</strong> Evalúe dosis o coagulante con prueba de jarras
          </div>
          <div className="tav-menor">Muestra del {fmtFecha(a.fecha_muestra)} a las {a.hora_muestra.slice(0, 5)} · umbral de la planta: {fmtValor(a.umbral, a.decimales)} {a.unidad}</div>
        </div>
      ))}
    </div>
  );
}

type Borrador = { umbral: string; motivo: string };
const TXT_UMBRAL = "Escriba el umbral en NTU (por ejemplo 150 o 150,5).";

/** Tarjeta plegable para fijar o apagar el umbral de cada planta (solo supervisor y administrador). El jefe de planta lo define; nace vacío = aviso apagado. */
export function ConfigAvisoTurbiedad({ onCambio }: { onCambio: () => void }) {
  const [datos, setDatos] = useState<UmbralesResp | null>(null);
  const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [borr, setBorr] = useState<Record<string, Borrador>>({});
  const [errPlanta, setErrPlanta] = useState<Record<string, string>>({});
  const [ocupada, setOcupada] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const cargar = useCallback(async () => {
    try { setDatos(await apiDash.umbralesAviso()); setError(null); } catch (e) { setError(textoError(e)); }
  }, []);
  useEffect(() => { void cargar(); }, [cargar]);

  const b = (p: string): Borrador => borr[p] ?? { umbral: "", motivo: "" };
  const poner = (p: string, c: Partial<Borrador>) => { setBorr((x) => ({ ...x, [p]: { ...b(p), ...c } })); setErrPlanta((x) => ({ ...x, [p]: "" })); setMsg(null); };

  async function guardar(p: UmbralPlanta, apagar: boolean) {
    if (ocupada) return;
    const f = b(p.planta); let valor: number | null = null;
    if (!apagar) {
      const i = interpretarNumero(f.umbral);
      if (i.tipo === "vacio") return setErrPlanta((x) => ({ ...x, [p.planta]: TXT_UMBRAL }));
      if (i.tipo === "error") return setErrPlanta((x) => ({ ...x, [p.planta]: i.motivo }));
      if (i.valor <= 0) return setErrPlanta((x) => ({ ...x, [p.planta]: "El umbral debe ser mayor que cero." }));
      if (i.valor >= p.tope) return setErrPlanta((x) => ({ ...x, [p.planta]: `El umbral debe ser menor que el máximo de referencia (${fmtValor(p.tope, 0)} NTU).` }));
      valor = i.valor;
    }
    if (p.activo && f.motivo.trim().length < 10) return setErrPlanta((x) => ({ ...x, [p.planta]: "Indique el motivo del cambio (de 10 a 500 caracteres)." }));
    setOcupada(p.planta); setMsg(null);
    try {
      await apiDash.fijarUmbralAviso(p.planta, valor, f.motivo);
      setBorr((x) => ({ ...x, [p.planta]: { umbral: "", motivo: "" } }));
      setMsg(apagar ? `Aviso apagado en planta ${p.planta_nombre}.` : `Umbral de planta ${p.planta_nombre} fijado en ${fmtValor(valor as number, 1)} ${datos?.unidad ?? "NTU"}.`);
      await cargar(); onCambio();
    } catch (e) { setErrPlanta((x) => ({ ...x, [p.planta]: textoError(e).texto })); }
    finally { setOcupada(null); }
  }

  return (
    <details className="tav-config" data-testid="config-aviso-turbiedad">
      <summary>Avisos de turbiedad de ingreso <span className="tav-estado">{datos ? (datos.plantas.some((p) => p.activo) ? "activo" : "apagado") : "…"}</span></summary>
      <div className="tav-cuerpo">
        <p className="td-sub">Cuando la lectura vigente más reciente de turbiedad de ingreso de una planta (de menos de 24 horas) supera su umbral, el Resumen y Eventos muestran un aviso. Sin umbral, la planta no avisa. No es el máximo de referencia y no entra a la revisión.</p>
        {error ? <div className="td-aviso td-aviso-error" role="alert">{error.texto} {!error.sesion ? <button type="button" className="td-enlace" onClick={() => void cargar()}>Reintentar</button> : null}</div> : null}
        {msg ? <div className="td-aviso td-aviso-ok" role="status">{msg}</div> : null}
        {(datos?.plantas ?? []).map((p) => {
          const f = b(p.planta); const idu = `tav-u-${p.planta}`; const idm = `tav-m-${p.planta}`;
          return (
            <fieldset key={p.planta} className="tav-planta" data-planta={p.planta}>
              <legend>Planta {p.planta_nombre}</legend>
              <p className="tav-vigente" data-testid={`estado-${p.planta}`}>{p.activo && p.umbral !== null ? <>Aviso encendido con umbral de <strong>{fmtValor(p.umbral, 1)} {datos?.unidad}</strong>, fijado por {p.fijado_por} el {fmtInstante(p.desde)}.</> : <>Aviso <strong>apagado</strong> (sin umbral).</>}</p>
              <div className="tav-fila">
                <label className="td-campo" htmlFor={idu}>{p.activo ? "Nuevo umbral" : "Umbral"} ({datos?.unidad ?? "NTU"})
                  <input id={idu} type="text" inputMode="decimal" autoComplete="off" value={f.umbral} onChange={(e) => poner(p.planta, { umbral: e.target.value })} aria-describedby={`${idu}-ay`} />
                </label>
                <span id={`${idu}-ay`} className="td-sub">Menor que {fmtValor(p.tope, 0)} NTU (máximo de referencia).</span>
              </div>
              {p.activo ? (
                <label className="td-campo" htmlFor={idm}>Motivo del cambio (obligatorio, de 10 a 500 caracteres)
                  <textarea id={idm} rows={2} maxLength={500} value={f.motivo} onChange={(e) => poner(p.planta, { motivo: e.target.value })} />
                </label>
              ) : null}
              {errPlanta[p.planta] ? <div className="td-aviso td-aviso-error" role="alert">{errPlanta[p.planta]}</div> : null}
              <div className="td-botones">
                <button type="button" className="td-boton" disabled={ocupada !== null} onClick={() => void guardar(p, false)}>{ocupada === p.planta ? "Guardando…" : p.activo ? "Cambiar umbral" : "Encender el aviso"}</button>
                {p.activo ? <button type="button" className="td-boton-sec" disabled={ocupada !== null} onClick={() => void guardar(p, true)}>Apagar el aviso</button> : null}
              </div>
            </fieldset>
          );
        })}
        {datos && datos.historial.length > 0 ? (
          <details className="tav-hist"><summary>Historial reciente</summary>
            <ul>{datos.historial.map((h, i) => (
              <li key={i}>{fmtInstante(h.creado_en)} · planta {h.planta_nombre} · {fmtValor(h.umbral, 1)} {datos.unidad} · fijado por {h.creado_por}{h.motivo ? ` («${h.motivo}»)` : ""}{!h.activo ? ` · cerrado el ${fmtInstante(h.desactivado_en)} por ${h.desactivado_por}${h.motivo_cierre ? ` («${h.motivo_cierre}»)` : ""}` : " · vigente"}</li>
            ))}</ul>
          </details>
        ) : null}
      </div>
    </details>
  );
}
