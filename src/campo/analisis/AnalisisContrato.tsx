import { ObservarContrato } from "./ObservarContrato";
import { Suspense, useCallback, useEffect, useRef, useState, type FormEvent, type ReactNode } from "react";
import { AvisoSinAgua } from "../AvisoSinAgua";
import { lazyConRecarga } from "../../lib/recarga";
import "./analisis.css";
import { apiCampo, ErrorCampo, TEXTO_NO_APLICADO } from "../apiCampo";
import type { Destino } from "../../components/ConfirmarCancelar";
import type { AnalisisCompleto, Predio, RespuestaAnalisis, RespuestaCercanos } from "./tipos";
import { ErrorGps, pedirPosicion, TEXTO_FALLO_GPS } from "./gps";
import { BuscarPredio, pedirPermisoBrujula, type PermisoBrujula } from "./BuscarPredio";
import { GraficaConsumo } from "./GraficaConsumo";
import {
  anios, avisoPrecision, contratoValido, distanciaCorta, distanciaTexto, predioMasCercano, textoCupoCercanos, etiquetaMes, fechaCorta, fechaCorte, filasGrafica, formatoTelefono, haceDias, haceMeses, hrefTelefono, limpiarContrato, m3, marcasDe,
  MAX_DIGITOS_CONTRATO, metodoTexto, periodoReferencia, pesos, plural, primerPredioConPunto, sinCodigo, telefonosVisibles, tramoTexto, urlGoogleMaps,
} from "./logica";

// «Análisis de contrato» (solo lectura): se escribe un contrato y se ve cartera, consumo, medidor, gestiones y ubicación. Lo decide y lo limita el SERVIDOR (permiso
// `analisis_contrato`; cada consulta queda en su bitácora, sin límite diario); aquí solo se dibuja. Tarjeta fija con lo esencial y secciones plegables (<details>, sin librerías).
// DATO PERSONAL (nombre y teléfonos): solo en pantalla. La respuesta vive en el estado de este componente y se descarta al salir: no se guarda en localStorage/sessionStorage,
// no se escribe en la consola, no se reutiliza entre consultas y no sale en ninguna descarga.
const MapaPunto = lazyConRecarga(() => import("./MapaPunto"));

export const FORMATO_CAMBIO_MEDIDOR = "instalacion_medidor";

type Estado =
  | { fase: "inicio" }
  | { fase: "cargando"; contrato: string }
  | { fase: "listo"; r: RespuestaAnalisis }
  | { fase: "error"; texto: string; sesion?: boolean };

function textoError(e: unknown): { texto: string; sesion?: boolean } {
  if (!(e instanceof ErrorCampo)) return { texto: "No se pudo consultar el contrato. Intente de nuevo." };
  switch (e.tipo) {
    case "sesion": return { texto: "Su sesión venció. Vuelva a iniciar sesión.", sesion: true };
    case "red": return { texto: "No hay conexión con el servidor. Revise su señal e intente de nuevo." };
    case "servidor": return { texto: "El servidor no pudo responder en este momento. Intente de nuevo en un momento." };
    case "no_aplicado": return { texto: TEXTO_NO_APLICADO };
    default: return { texto: e.message };          // 400, 403 (y el 429 de «Contratos cerca de mí»): el texto del servidor
  }
}

const capital = (s: string | null | undefined) => (s ? s.charAt(0).toUpperCase() + s.slice(1).toLowerCase() : "");

export default function AnalisisContrato({ onVolver, destinos = [], onIrA, puedeCambioMedidor = false, onCambioMedidor }: {
  onVolver: () => void;
  /** Atajos: a qué formularios puede pasar la persona llevando el contrato (los mismos de «Me equivoqué de formulario»). Vacío = sin atajos. */
  destinos?: Destino[]; onIrA?: (destino: string, contrato: string) => void;
  /** ¿Está activo «Instalación de medidor» en su catálogo y puede reportar? Solo así se ofrece «Instalación de medidor → Cambio». */
  puedeCambioMedidor?: boolean; onCambioMedidor?: (contrato: string) => void;
}) {
  const [texto, setTexto] = useState("");
  const [estado, setEstado] = useState<Estado>({ fase: "inicio" });
  const turno = useRef(0);

  // `directo`: contrato tocado en «Contratos cerca de mí»; se consulta exactamente igual que si se hubiera escrito.
  async function consultar(e?: FormEvent, directo?: string) {
    e?.preventDefault();
    const c = limpiarContrato(directo ?? texto);
    if (directo !== undefined) setTexto(c);
    if (!contratoValido(c)) { setEstado({ fase: "error", texto: "Escriba solo los números del contrato (hasta 12 dígitos)." }); return; }
    const mio = ++turno.current;
    setEstado({ fase: "cargando", contrato: c });
    try {
      const r = await apiCampo.analisisContrato(c);
      if (mio !== turno.current) return;
      setEstado({ fase: "listo", r });
      if (directo !== undefined) requestAnimationFrame(() => document.querySelector("[data-ancla=resultado]")?.scrollIntoView({ block: "start" }));
    } catch (err) {
      if (mio !== turno.current) return;
      setEstado({ fase: "error", ...textoError(err) });
    }
  }

  const cargando = estado.fase === "cargando";
  return (
    <div className="tec-pagina campo-pagina ac-pagina">
      <section className="tec-tarjeta ac-cab">
        <div className="campo-cab">
          <button type="button" className="tec-boton-sec tec-boton-corto" onClick={onVolver}>← Formularios de campo</button>
          <h1>Análisis de contrato</h1>
        </div>
        <form className="ac-buscar" onSubmit={consultar} noValidate>
          <label htmlFor="ac-contrato" className="campo-etiqueta">Número de contrato</label>
          <div className="ac-buscar-fila">
            <input id="ac-contrato" type="text" inputMode="numeric" pattern="[0-9]*" maxLength={MAX_DIGITOS_CONTRATO} autoComplete="off" spellCheck={false}
              value={texto} onChange={(ev) => setTexto(limpiarContrato(ev.target.value))} />
            <button type="submit" className="tec-boton" disabled={cargando || texto === ""}>Consultar</button>
          </div>
        </form>
        <Cercanos onAbrir={(c) => void consultar(undefined, c)} ocupado={cargando} />
        {estado.fase === "error" ? <p className="campo-error" role="alert">{estado.texto}</p> : null}
        {cargando ? <p className="campo-sub" role="status">Consultando el contrato {estado.contrato}…</p> : null}
      </section>
      <div data-ancla="resultado" aria-hidden="true" />
      {estado.fase === "listo" ? <Resultado key={estado.r.contrato} r={estado.r} destinos={destinos} onIrA={onIrA} puedeCambioMedidor={puedeCambioMedidor} onCambioMedidor={onCambioMedidor} /> : null}
    </div>
  );
}

function Resultado({ r, destinos, onIrA, puedeCambioMedidor, onCambioMedidor }: { r: RespuestaAnalisis; destinos: Destino[]; onIrA?: (d: string, c: string) => void; puedeCambioMedidor: boolean; onCambioMedidor?: (c: string) => void }) {
  if (!r.encontrado) return <section className="tec-tarjeta"><p className="ac-aviso" role="status">No encontramos ese contrato.</p></section>;
  if (r.comodin) return <section className="tec-tarjeta"><p className="ac-aviso" role="status">Contrato corporativo: no tiene análisis.</p></section>;
  return <Ficha r={r} destinos={destinos} onIrA={onIrA} puedeCambioMedidor={puedeCambioMedidor} onCambioMedidor={onCambioMedidor} />;
}

function Dato({ et, children }: { et: string; children: ReactNode }) {
  return <div><dt>{et}</dt><dd>{children}</dd></div>;
}
const Corte = ({ children }: { children: ReactNode }) => <span className="ac-corte">{children}</span>;

function Ficha({ r, destinos, onIrA, puedeCambioMedidor, onCambioMedidor }: { r: AnalisisCompleto; destinos: Destino[]; onIrA?: (d: string, c: string) => void; puedeCambioMedidor: boolean; onCambioMedidor?: (c: string) => void }) {
  const [verMapa, setVerMapa] = useState(false);
  const s = r.suscriptor, c = r.comercial, md = r.medidor, cons = r.consumo, g = r.gestiones;
  const ref = periodoReferencia(r);
  const marcas = marcasDe(r);
  const tels = telefonosVisibles(s?.telefonos);
  const filas = filasGrafica(cons, r.promedios);
  const punto = primerPredioConPunto(r);
  const cartera = fechaCorte(r.cortes?.cartera ?? c?.corte ?? s?.corte);
  const aConsumo = etiquetaMes(r.cortes?.consumo ?? cons?.periodo_ultimo);
  const ficha = r.cortes?.ficha ? fechaCorta(r.cortes.ficha) : null;
  const instGeoportal = (g?.reportes ?? []).find((x) => x.tipo === FORMATO_CAMBIO_MEDIDOR);
  const atajos = onIrA ? destinos : [];
  const sinFicha = !r.ficha_disponible;

  return (
    <div className="ac-cuerpo">
      {/* ===== Tarjeta fija ===== */}
      <section className="tec-tarjeta ac-tarjeta" aria-label="Resumen del contrato" data-testid="tarjeta">
        <h2 className="ac-titulo">Contrato {r.contrato}{c?.estado ? ` · ${capital(c.estado)}` : ""}</h2>
        <AvisoSinAgua contrato={r.contrato} espera={0} />
        <Distancia predios={r.ubicacion?.predios ?? []} />
        {sinFicha ? <p className="ac-nota" role="note">El análisis mensual aún no se ha calculado: faltan consumo, medidor, pago y PQR.</p> : null}
        <div className="ac-personal">
          <p className="ac-nombre"><strong>{s?.nombre ?? "Sin nombre registrado"}</strong> <span className="ac-tag-personal">dato personal</span></p>
          {tels.length > 0 ? (
            <p className="ac-tels">
              {tels.map((t) => <a key={t} className="ac-tel" href={hrefTelefono(t)}><span aria-hidden="true">☎ </span>{formatoTelefono(t)}</a>)}
              <span className="ac-tag-personal">dato personal</span>
              {s?.telefono_fuente === "censo" ? <span className="ac-tag-censo">censo nov-2025</span> : null}
            </p>
          ) : <p className="campo-sub">Sin teléfono registrado.</p>}
        </div>
        <ul className="ac-lineas">
          <li>{[c?.direccion, c?.barrio ? `Barrio ${c.barrio}` : null].filter(Boolean).join(" · ") || "Sin dirección registrada"}</li>
          <li>{[sinCodigo(c?.categoria) || null, sinCodigo(c?.subcategoria) || null, c?.ciclo ? `Ciclo ${c.ciclo}` : null].filter(Boolean).join(" · ") || "Uso y estrato sin dato"}</li>
          <li>
            Deuda <strong>{pesos(c?.deuda_total)}</strong>{c?.facturas_pendientes !== null && c?.facturas_pendientes !== undefined ? ` · ${plural(c.facturas_pendientes, "factura", "facturas")}` : ""}
            {c?.tramo_mora ? <> · <span className={`ac-tramo ac-tramo-${c.tramo_mora}`}>{tramoTexto(c.tramo_mora)}</span></> : null}
            <Corte>cartera al {cartera}</Corte>
          </li>
          <li>
            {md?.serial ? <>Medidor <strong>{md.serial}</strong> · {anios(md.anios)}</> : md ? "Sin medidor registrado" : "Medidor sin dato"}
            {!sinFicha && cons ? <Corte>ficha a {aConsumo}</Corte> : null}
          </li>
          <li>
            {r.pago ? <>Último pago: {fechaCorta(r.pago.fecha)}{r.pago.dias !== null ? ` (${haceDias(r.pago.dias)})` : ""}{r.pago.valor !== null ? ` · ${pesos(r.pago.valor)}` : ""}</> : "Último pago: sin dato"}
            {r.pago ? <Corte>{r.pago.fuente === "cupones" ? "pagos" : "cartera mensual"} a {aConsumo}</Corte> : null}
          </li>
        </ul>
        <div className="ac-marcas" aria-label="Marcas" data-testid="marcas">
          <h3>Marcas</h3>
          {marcas.length === 0 ? <p className="campo-sub">Sin marcas.</p> : (
            <ul>
              {marcas.map((mk) => (
                <li key={mk.clave} className={mk.alerta ? "ac-marca-alerta" : ""} data-marca={mk.clave}>
                  <strong>{mk.alerta ? "⚠ " : "• "}{mk.titulo}</strong>
                  {mk.detalle ? <span>{mk.detalle}</span> : null}
                  {mk.clave === "submedicion" && puedeCambioMedidor && onCambioMedidor ? (
                    <button type="button" className="tec-boton-sec ac-boton-cambio" onClick={() => onCambioMedidor(r.contrato)}>Instalación de medidor → Cambio</button>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </div>
      </section>

      {/* ===== Secciones plegables ===== */}
      <div className="ac-secciones">
        <details className="ac-seccion" data-seccion="comercial">
          <summary>Comercial y cartera <Corte>cartera al {cartera}</Corte></summary>
          {c ? (
            <dl className="ac-dl">
              <Dato et="Estado comercial">{capital(c.estado) || "—"}</Dato>
              <Dato et="Estado del predio (censo)">{capital(c.estado_predio) || "—"}</Dato>
              <Dato et="Categoría">{c.categoria ?? "—"}</Dato>
              <Dato et="Subcategoría">{c.subcategoria ?? "—"}</Dato>
              <Dato et="Ciclo · ruta">{[c.ciclo, c.ruta].filter(Boolean).join(" · ") || "—"}</Dato>
              <Dato et="Deuda total">{pesos(c.deuda_total)}</Dato>
              <Dato et="Saldo pendiente">{pesos(c.saldo_pendiente)}</Dato>
              <Dato et="Facturas pendientes">{c.facturas_pendientes ?? "—"}</Dato>
              <Dato et="Saldo financiado">{pesos(c.saldo_financiado)}</Dato>
              <Dato et="Valor en reclamo">{pesos(c.valor_reclamo)}</Dato>
              <Dato et="Saldo a favor">{pesos(c.saldo_a_favor)}</Dato>
              <Dato et="Facturas vencidas (corte mensual)">{c.facturas_vencidas ?? "—"}</Dato>
              <Dato et="Tramo de mora">{tramoTexto(c.tramo_mora)}</Dato>
            </dl>
          ) : <p className="campo-sub">Sin datos comerciales.</p>}
        </details>

        <details className="ac-seccion" data-seccion="consumo" open>
          <summary>Consumo (últimos 6 meses) {cons ? <Corte>consumo a {etiquetaMes(cons.periodo_ultimo)}</Corte> : null}</summary>
          {cons && filas.length > 0 ? (
            <>
              <GraficaConsumo filas={filas} grupoEstrato={r.promedios?.estrato?.grupo ?? null} grupoBarrio={r.promedios?.barrio?.grupo ?? null} />
              <p className="ac-resumen" data-testid="resumen-consumo">
                Máx {m3(cons.maximo)} · Mín {m3(cons.minimo)} · Prom {m3(cons.promedio)} m³
                <span className="ac-corte">de {plural(cons.meses_con_lectura, "mes", "meses")} con lectura real</span>
              </p>
              <div className="ac-tabla-scroll">
                <table className="ac-tabla" data-testid="tabla-consumo">
                  <caption className="ac-oculto">Consumo por mes y promedios de comparación</caption>
                  <thead><tr><th scope="col">Mes</th><th scope="col">m³</th><th scope="col">Método · causal</th><th scope="col">Prom. estrato</th><th scope="col">Prom. barrio</th><th scope="col">Prom. uso</th></tr></thead>
                  <tbody>
                    {filas.map((f) => (
                      <tr key={f.periodo} className={f.sinDato ? "ac-fila-vacia" : ""}>
                        <th scope="row">{f.etiqueta}</th>
                        <td>{f.sinDato ? "—" : <>{m3(f.m3)}{f.estimado ? <span className="ac-estimado"> ○ estimado</span> : null}</>}</td>
                        <td>{metodoTexto(f)}</td>
                        <td>{m3(f.estrato)}</td><td>{m3(f.barrio)}</td><td>{m3(f.uso)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <p className="campo-sub ac-pie">
                Promedios del mismo mes sobre contratos con lectura real{r.promedios?.estrato ? ` · estrato: ${r.promedios.estrato.grupo}` : ""}{r.promedios?.barrio ? ` · barrio: ${r.promedios.barrio.grupo}` : ""}{r.promedios?.uso ? ` · uso: ${r.promedios.uso.grupo}` : ""}. Un promedio vacío es un grupo de menos de 30 contratos o un mes sin dato.
              </p>
            </>
          ) : <p className="campo-sub">{sinFicha ? "El consumo sale del análisis mensual, que aún no se ha calculado." : "Sin consumos registrados."}</p>}
        </details>

        <details className="ac-seccion" data-seccion="medidor">
          <summary>Medidor {ficha ? <Corte>ficha del {ficha}</Corte> : null}</summary>
          {md ? (
            <dl className="ac-dl">
              <Dato et="Serial">{md.serial ?? "Sin medidor"}</Dato>
              <Dato et="Diámetro (catastro)">{md.diametro ?? "—"}</Dato>
              <Dato et="Fecha de instalación">{md.fecha_estado === "real" && md.fecha_instalacion ? fechaCorta(md.fecha_instalacion) : md.fecha_estado === "por_defecto" ? "sin dato (fecha por defecto)" : "sin dato"}</Dato>
              <Dato et="Edad">{anios(md.anios)}</Dato>
              <Dato et="Cambio de medidor">
                {md.cambio?.confirmado ? `Cambio de medidor ${haceMeses(md.cambio.confirmado.periodo, ref)} (${etiquetaMes(md.cambio.confirmado.periodo)}): serial anterior ${md.cambio.confirmado.serial_anterior ?? "—"} → ${md.cambio.confirmado.serial_nuevo ?? "—"}`
                  : instGeoportal ? `${instGeoportal.tipo_nombre} registrada en el geoportal ${instGeoportal.consecutivo ?? ""} (${fechaCorta(instGeoportal.fecha)})`
                  : "Sin cambio detectado en los últimos 6 meses"}
              </Dato>
              {md.cambio?.recodificado ? <Dato et="Serial recodificado">{`${etiquetaMes(md.cambio.recodificado.periodo)}: ${md.cambio.recodificado.serial_anterior ?? "—"} → ${md.cambio.recodificado.serial_nuevo ?? "—"} (no es un cambio físico)`}</Dato> : null}
              {r.submedicion && !r.submedicion.marca ? <Dato et="Posible submedición">No se marca{r.submedicion.motivo ? `: ${r.submedicion.motivo}` : ""}.</Dato> : null}
              {r.submedicion?.marca ? <Dato et="Posible submedición">Sí. {marcas.find((x) => x.clave === "submedicion")?.detalle}</Dato> : null}
            </dl>
          ) : <p className="campo-sub">{sinFicha ? "El medidor sale del análisis mensual, que aún no se ha calculado." : "Sin datos del medidor."}</p>}
        </details>

        <details className="ac-seccion" data-seccion="gestiones">
          <summary>Gestiones (cortes, PQR, geoportal)</summary>
          <h3 className="ac-sub">Cortes y suspensiones facturados</h3>
          {g?.emd_facturados && g.emd_facturados.length > 0 ? (
            <ul className="ac-lista">{g.emd_facturados.map((x) => <li key={`${x.codigo}-${x.periodo}`}>{x.concepto} · {etiquetaMes(x.periodo)} ({haceMeses(x.periodo, ref)})</li>)}</ul>
          ) : <p className="campo-sub">{g?.emd_facturados === null || !g ? "Sin dato (falta el análisis mensual)." : "Ninguno facturado."}</p>}
          <h3 className="ac-sub">Registrados en el geoportal</h3>
          {g && g.terreno.length > 0 ? (
            <ul className="ac-lista">{g.terreno.map((x) => <li key={`${x.tipo}-${x.consecutivo}`}>{x.tipo_nombre} {x.consecutivo ?? ""} · {fechaCorta(x.fecha)}{x.estado ? ` · ${x.estado}` : ""}</li>)}</ul>
          ) : <p className="campo-sub">Ninguno registrado.</p>}
          <h3 className="ac-sub">PQR</h3>
          {g?.pqr ? (
            <>
              {g.pqr.ultima ? (
                <p className="ac-parrafo">Última: {g.pqr.ultima.solicitud} · {fechaCorta(g.pqr.ultima.fecha)}{(() => { const p = g.pqr.ultima.fecha.replace(/-/g, "").slice(0, 6); return ` (${haceMeses(p, ref)})`; })()} · {g.pqr.ultima.causal ?? "—"} · {g.pqr.ultima.estado ?? "—"}{g.pqr.ultima.abierta ? " · abierta" : ""}</p>
              ) : null}
              <p className="campo-sub">{plural(g.pqr.abiertas, "abierta", "abiertas")} · {plural(g.pqr.ultimos_12_meses, "en los últimos 12 meses", "en los últimos 12 meses")} · {plural(g.pqr.total, "en total", "en total")}</p>
            </>
          ) : <p className="campo-sub">{sinFicha ? "Sin dato (falta el análisis mensual)." : "Sin PQR registradas."}</p>}
          <h3 className="ac-sub">Reportes del geoportal</h3>
          {g && g.reportes.length > 0 ? (
            <div className="ac-tabla-scroll">
              <table className="ac-tabla">
                <thead><tr><th scope="col">Tipo</th><th scope="col">Consecutivo</th><th scope="col">Fecha</th><th scope="col">Estado</th><th scope="col">Resultado</th></tr></thead>
                <tbody>{g.reportes.map((x, i) => <tr key={`${x.consecutivo}-${i}`}><td>{x.tipo_nombre}</td><td>{x.consecutivo ?? "—"}</td><td>{fechaCorta(x.fecha)}</td><td>{x.estado ?? "—"}</td><td>{x.resultado ?? "—"}</td></tr>)}</tbody>
              </table>
            </div>
          ) : <p className="campo-sub">Ninguno.</p>}
          {g && g.reportes_total > g.reportes.length ? <p className="campo-sub">Se muestran {g.reportes.length} de {g.reportes_total}.</p> : null}
          <h3 className="ac-sub">Actas de inspección</h3>
          {g && g.actas.length > 0 ? (
            <ul className="ac-lista">{g.actas.map((x) => <li key={x.consecutivo}>{x.consecutivo} · {fechaCorta(x.fecha ?? x.registrado_en)}</li>)}</ul>
          ) : <p className="campo-sub">Ninguna.</p>}
          <h3 className="ac-sub">Revisiones que sugieren cambio de medidor</h3>
          {g && g.pendientes.length > 0 ? (
            <ul className="ac-lista">{g.pendientes.map((x, i) => <li key={`${x.consecutivo}-${i}`}>{x.tipo_nombre} {x.consecutivo ?? ""} · {fechaCorta(x.fecha)} · sin instalación posterior</li>)}</ul>
          ) : <p className="campo-sub">Ninguna pendiente.</p>}
        </details>

        <details className="ac-seccion" data-seccion="ubicacion" onToggle={(e) => { if ((e.currentTarget as HTMLDetailsElement).open) setVerMapa(true); }}>
          <summary>Ubicación (mapa y Google Maps)</summary>
          {punto ? (
            <>
              {verMapa ? <Suspense fallback={<p className="campo-sub">Cargando el mapa…</p>}><MapaPunto predios={r.ubicacion?.predios ?? []} /></Suspense> : null}
              <a className="tec-boton-sec ac-gmaps" href={urlGoogleMaps(punto.lat, punto.lon)} target="_blank" rel="noopener noreferrer">Abrir en Google Maps</a>
            </>
          ) : <p className="campo-sub">Sin coordenadas en el catastro.</p>}
          {(r.ubicacion?.predios ?? []).length > 0 ? (
            <ul className="ac-lista">
              {(r.ubicacion?.predios ?? []).map((p, i) => <li key={i}>{[p.direccion, p.barrio].filter(Boolean).join(" · ") || "Predio sin dirección"}{p.lat === null || p.lon === null ? " · sin coordenadas" : ""}</li>)}
            </ul>
          ) : null}
          {(r.ubicacion?.predios_total ?? 0) > (r.ubicacion?.predios.length ?? 0) ? <p className="campo-sub">Se muestran {r.ubicacion?.predios.length} de {r.ubicacion?.predios_total} predios.</p> : null}
        </details>

        {r.fotos && r.fotos.length > 0 ? (
          <details className="ac-seccion" data-seccion="fotos">
            <summary>Fotos del predio</summary>
            <p className="campo-sub">{plural(r.fotos.length, "foto", "fotos")} del catastro.</p>
          </details>
        ) : null}

        <ObservarContrato contrato={r.contrato} />

        {atajos.length > 0 ? (
          <section className="ac-atajos" aria-label="Atajos con este contrato">
            <h3>Atajos con este contrato:</h3>
            <div className="ac-atajos-botones">
              {atajos.map((d) => (
                <button key={d.id} type="button" className="tec-boton-sec" onClick={() => onIrA?.(d.id, r.contrato)}>{d.id === "formatos" ? "Formato…" : d.rotulo}</button>
              ))}
            </div>
          </section>
        ) : null}
      </div>
    </div>
  );
}

// ---------------- Cercanía (agregado del 14/11) ----------------

/** «A 120 m» del predio: se mide en el celular (haversine) al mostrar el análisis y con «Actualizar». La posición no sale del teléfono ni se guarda: solo queda la distancia. */
function Distancia({ predios }: { predios: Predio[] }) {
  type E = { fase: "midiendo" } | { fase: "ok"; m: number; precision: number } | { fase: "error"; texto: string };
  const [e, setE] = useState<E>({ fase: "midiendo" });
  const [buscando, setBuscando] = useState<Promise<PermisoBrujula> | null>(null);   // «Buscar»: pantalla abierta, con el permiso de brújula pedido en el mismo toque
  const turno = useRef(0);
  const hayPunto = predios.some((p) => p.lat !== null && p.lon !== null);
  const varios = predios.filter((p) => p.lat !== null && p.lon !== null).length > 1;
  const medir = useCallback(() => {
    const t = ++turno.current;
    setE({ fase: "midiendo" });
    pedirPosicion().then((pos) => {
      if (t !== turno.current) return;
      const c = predioMasCercano(pos, predios);
      setE(c ? { fase: "ok", m: c.distancia_m, precision: pos.precision_m } : { fase: "error", texto: "Sin coordenadas para medir la distancia." });
    }, (err) => { if (t === turno.current) setE({ fase: "error", texto: err instanceof ErrorGps ? err.message : TEXTO_FALLO_GPS.no_disponible }); });
  }, [predios]);
  useEffect(() => { if (hayPunto) medir(); return () => { turno.current++; }; }, [hayPunto, medir]);
  const cerrarBuscar = useCallback(() => setBuscando(null), []);

  if (!hayPunto) return <p className="campo-sub ac-distancia" data-testid="distancia">Sin coordenadas para medir la distancia.</p>;
  const aviso = e.fase === "ok" ? avisoPrecision(e.precision) : null;
  return (
    <div className="ac-distancia" data-testid="distancia" aria-live="polite">
      <div className="ac-distancia-fila">
        <p className="ac-distancia-valor">
          {e.fase === "ok" ? <><strong data-testid="distancia-valor">{distanciaTexto(e.m)}</strong> <span className="ac-corte">{varios ? "del predio más cercano" : "del predio"} · según su GPS</span></>
            : e.fase === "midiendo" ? <span className="campo-sub">Midiendo la distancia con su GPS…</span> : <span className="campo-sub">Distancia no disponible.</span>}
        </p>
        <div className="ac-distancia-botones">
          <button type="button" className="tec-boton-sec tec-boton-corto" onClick={medir} disabled={e.fase === "midiendo"}>Actualizar</button>
          <button type="button" className="tec-boton tec-boton-corto ac-boton-buscar" onClick={() => setBuscando(pedirPermisoBrujula())}>Buscar</button>
        </div>
      </div>
      {buscando ? <BuscarPredio predios={predios} permiso={buscando} onCerrar={cerrarBuscar} /> : null}
      {aviso ? <p className="ac-nota" role="note">{aviso}</p> : null}
      {e.fase === "error" ? <p className="ac-gps-ayuda" data-testid="gps-ayuda">{e.texto}</p> : null}
    </div>
  );
}

/** «Contratos cerca de mí»: hasta 5 predios con contrato dentro del radio del servidor (300 m). La lista NO muestra nombre ni teléfono (la respuesta no los trae). */
function Cercanos({ onAbrir, ocupado }: { onAbrir: (contrato: string) => void; ocupado: boolean }) {
  type E = { fase: "inicio" } | { fase: "ubicando" } | { fase: "buscando" } | { fase: "listo"; r: RespuestaCercanos; precision: number } | { fase: "gps"; texto: string } | { fase: "error"; texto: string };
  const [e, setE] = useState<E>({ fase: "inicio" });
  const [cupo, setCupo] = useState<RespuestaCercanos["cupo"]>(null);
  const [elegido, setElegido] = useState<string | null>(null);
  const turno = useRef(0);
  useEffect(() => () => { turno.current++; }, []);

  async function buscar() {
    const t = ++turno.current;
    setE({ fase: "ubicando" }); setElegido(null);
    let lat: number, lon: number, precision: number;
    try { ({ lat, lon, precision_m: precision } = await pedirPosicion()); }
    catch (err) { if (t === turno.current) setE({ fase: "gps", texto: err instanceof ErrorGps ? err.message : TEXTO_FALLO_GPS.no_disponible }); return; }
    if (t !== turno.current) return;
    setE({ fase: "buscando" });
    try {
      const r = await apiCampo.analisisCercanos(lat, lon, precision);
      if (t !== turno.current) return;
      if (r.cupo) setCupo(r.cupo);
      setE({ fase: "listo", r, precision });
    } catch (err) {
      if (t === turno.current) setE({ fase: "error", texto: textoError(err).texto });
    }
  }

  const trabajando = e.fase === "ubicando" || e.fase === "buscando";
  return (
    <div className="ac-cerca" data-testid="cercanos">
      <button type="button" className="tec-boton-sec ac-boton-cerca" onClick={() => void buscar()} disabled={trabajando}>Contratos cerca de mí</button>
      {textoCupoCercanos(cupo) ? <p className="campo-sub ac-cupo">{textoCupoCercanos(cupo)}</p> : null}
      {trabajando ? <p className="campo-sub" role="status">{e.fase === "ubicando" ? "Obteniendo su ubicación…" : "Buscando contratos cercanos…"}</p> : null}
      {e.fase === "gps" ? <p className="ac-gps-ayuda" data-testid="gps-ayuda" role="status">{e.texto}</p> : null}
      {e.fase === "error" ? <p className="campo-error" role="alert">{e.texto}</p> : null}
      {e.fase === "listo" ? (
        e.r.contratos.length === 0 ? <p className="ac-aviso-suave" role="status">No hay predios con contrato a menos de {e.r.radio_m.toLocaleString("es-CO")} m.</p> : (
          <div className="ac-cercanos">
            <p className="ac-cercanos-tit">Más cercanos <span className="ac-corte">radio {e.r.radio_m.toLocaleString("es-CO")} m</span></p>
            {avisoPrecision(e.precision) ? <p className="ac-nota" role="note">{avisoPrecision(e.precision)}</p> : null}
            <ul>
              {e.r.contratos.slice(0, 5).map((c) => (
                <li key={c.contrato}>
                  <button type="button" className="ac-cercano" onClick={() => { setElegido(c.contrato); onAbrir(c.contrato); }} disabled={ocupado} aria-current={elegido === c.contrato ? "true" : undefined}>
                    <strong>{c.contrato}</strong>
                    <span className="ac-cercano-dir">{c.direccion ?? "Sin dirección"}</span>
                    <span className="ac-cercano-dist">{distanciaCorta(c.distancia_m)}</span>
                  </button>
                </li>
              ))}
            </ul>
          </div>
        )
      ) : null}
    </div>
  );
}
