import { useEffect, useMemo, useState } from "react";
import "./quimicos.css";
import { ErrorTec } from "./apiTecnica";
import { apiQuimicos, type FormularioQuimicos as Def } from "./apiQuimicos";
import { interpretarNumero, formatearNumero } from "./numeros";
import { fmtFecha } from "./formato";

// Pantallas del operador de planta para los químicos (Técnica fase 1, Corte 7b; §29 y respuestas de David del 16-nov):
//   · «Entrada de químicos»: lo que llega a la bodega, en TONELADAS o KG (nunca por cilindros), con proveedor, remisión, lote y vencimiento.
//   · «Uso de químicos»: lo que se gastó, en kg, en qué planta y para qué (dosificación, limpieza u otro).
// El operador NO ve el saldo de la bodega ni la dosis óptima. Qué químicos hay, las plantas y cuántos días atrás se puede registrar lo dice el SERVIDOR.
// Cada envío lleva su clave: repetirlo (mala señal) no duplica el movimiento.

const PARA_QUE: Record<string, string> = { dosificacion: "Dosificación", limpieza: "Limpieza", otro: "Otro uso" };
const UNIDAD: Record<string, string> = { t: "Toneladas", kg: "Kilogramos" };
const claveNueva = () => `q-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`;
const restarDias = (iso: string, n: number) => { const d = new Date(`${iso}T12:00:00Z`); d.setUTCDate(d.getUTCDate() - n); return d.toISOString().slice(0, 10); };
const kg = (n: number) => `${formatearNumero(n, Number.isInteger(n) ? 0 : 1)} kg`;

export function FormularioQuimicos({ formulario, onSalir }: { formulario: "entrada_quimicos" | "uso_quimicos"; onSalir: () => void }) {
  const esEntrada = formulario === "entrada_quimicos";
  const [def, setDef] = useState<Def | null>(null);
  const [errorDef, setErrorDef] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);
  const [quimico, setQuimico] = useState("");
  const [cantidad, setCantidad] = useState("");
  const [unidad, setUnidad] = useState<"t" | "kg">(esEntrada ? "t" : "kg");
  const [dia, setDia] = useState("");
  const [planta, setPlanta] = useState("");
  const [paraQue, setParaQue] = useState("");
  const [proveedor, setProveedor] = useState("");
  const [remision, setRemision] = useState("");
  const [lote, setLote] = useState("");
  const [vence, setVence] = useState("");
  const [clave, setClave] = useState(claveNueva);
  const [enviando, setEnviando] = useState(false);
  const [intentado, setIntentado] = useState(false);
  const [errorEnvio, setErrorEnvio] = useState<string | null>(null);
  const [listo, setListo] = useState<string | null>(null);

  useEffect(() => {
    let vivo = true;
    setDef(null); setErrorDef(null);
    apiQuimicos.formulario(formulario)
      .then((d) => { if (vivo) { setDef(d); setDia(d.hoy); } })
      .catch((e) => { if (vivo) setErrorDef(e instanceof ErrorTec && e.tipo === "permiso" ? "No tiene permiso para este formulario." : e instanceof Error ? e.message : "No se pudo cargar."); });
    return () => { vivo = false; };
  }, [formulario, intento]);

  const num = useMemo(() => interpretarNumero(cantidad), [cantidad]);
  const enKg = num.tipo === "ok" ? (unidad === "t" ? num.valor * 1000 : num.valor) : null;
  const errores = useMemo(() => {
    const e: Record<string, string> = {};
    if (!def) return e;
    if (!quimico) e.quimico = "Elija el químico.";
    if (num.tipo === "vacio") e.cantidad = esEntrada ? "Escriba la cantidad recibida." : "Escriba la cantidad usada.";
    else if (num.tipo === "error") e.cantidad = num.motivo;
    else if (num.valor <= 0) e.cantidad = "La cantidad debe ser mayor que 0.";
    if (!dia) e.dia = "Elija el día.";
    else if (dia > def.hoy) e.dia = "El día no puede ser futuro.";
    else if (dia < restarDias(def.hoy, def.dias_atras)) e.dia = `Se puede registrar hasta ${def.dias_atras} días atrás.`;
    if (!esEntrada) {
      if (!paraQue) e.para_que = "Diga para qué se usó.";
      if (paraQue === "dosificacion" && !planta) e.planta = "Para dosificar, elija la planta.";
    }
    return e;
  }, [def, quimico, num, dia, paraQue, planta, esEntrada]);

  if (errorDef) return (
    <section className="tec-tarjeta" role="alert">
      <p><strong>{errorDef}</strong></p>
      <button type="button" className="tec-boton" onClick={() => setIntento((i) => i + 1)}>Reintentar</button>
    </section>
  );
  if (!def) return <p className="tec-sub" role="status" style={{ padding: "16px" }}>Cargando el formulario…</p>;

  const nombreQuimico = def.quimicos.find((q) => q.codigo === quimico)?.nombre ?? "";
  const limpiar = () => { setCantidad(""); setProveedor(""); setRemision(""); setLote(""); setVence(""); setIntentado(false); setErrorEnvio(null); setClave(claveNueva()); };
  const enviar = async () => {
    setIntentado(true); setErrorEnvio(null); setListo(null);
    if (Object.keys(errores).length > 0 || num.tipo !== "ok") return;
    setEnviando(true);
    try {
      if (esEntrada) {
        const r = await apiQuimicos.entrada({ quimico, cantidad: num.valor, unidad, dia, proveedor: proveedor.trim() || null, remision: remision.trim() || null, lote: lote.trim() || null, vence: vence || null }, clave);
        setListo(`Entrada registrada: ${kg(Math.abs(r.cantidad_kg))} de ${nombreQuimico}, el ${fmtFecha(dia)}.`);
      } else {
        const r = await apiQuimicos.uso({ quimico, cantidad: num.valor, unidad: "kg", dia, para_que: paraQue, planta: planta || null }, clave);
        setListo(`Uso registrado: ${kg(Math.abs(r.cantidad_kg))} de ${nombreQuimico}, el ${fmtFecha(dia)}.`);
      }
      limpiar();
      window.scrollTo?.(0, 0);
    } catch (e) {
      setErrorEnvio(e instanceof ErrorTec && e.tipo === "red" ? "No hay conexión. Sus datos siguen en la pantalla: intente de nuevo." : e instanceof Error ? e.message : "No se pudo guardar.");
    } finally { setEnviando(false); }
  };
  const err = (k: string) => (intentado && errores[k] ? <span className="tec-error" id={`fq-e-${k}`}>{errores[k]}</span> : null);

  return (
    <section className="tec-tarjeta fq" aria-label={esEntrada ? "Entrada de químicos" : "Uso de químicos"}>
      <div>
        <h1>{esEntrada ? "Entrada de químicos" : "Uso de químicos"}</h1>
        <p className="tec-sub">{esEntrada ? "Lo que llegó a la bodega. En toneladas o en kilogramos." : "Lo que se gastó, en kilogramos."}</p>
      </div>
      {listo ? <p className="tec-aviso tec-aviso-ok" role="status">{listo}</p> : null}

      {def.quimicos.length === 0 ? <p className="tec-aviso tec-aviso-info" role="status">No hay químicos activos. Avise al supervisor de planta.</p> : (
        <>
          <div className="tec-campo" role="group" aria-labelledby="fq-l-quimico">
            <span className="fq-rotulo" id="fq-l-quimico">Químico</span>
            <div className="fq-opciones">
              {def.quimicos.map((q) => <button key={q.codigo} type="button" className="tec-planta fq-opcion" aria-pressed={quimico === q.codigo} data-quimico={q.codigo} onClick={() => setQuimico(q.codigo)}>{q.nombre}</button>)}
            </div>
            {err("quimico")}
          </div>

          {!esEntrada ? (
            <>
              <div className="tec-campo" role="group" aria-labelledby="fq-l-para">
                <span className="fq-rotulo" id="fq-l-para">¿Para qué se usó?</span>
                <div className="fq-opciones">
                  {(def.para_que ?? []).map((p) => <button key={p} type="button" className="tec-planta fq-opcion" aria-pressed={paraQue === p} data-para={p} onClick={() => setParaQue(p)}>{PARA_QUE[p] ?? p}</button>)}
                </div>
                {err("para_que")}
              </div>
              <div className="tec-campo" role="group" aria-labelledby="fq-l-planta">
                <span className="fq-rotulo" id="fq-l-planta">Planta {paraQue === "dosificacion" ? null : <span className="tec-oblig">(opcional)</span>}</span>
                <div className="fq-opciones">
                  {def.plantas.map((p) => <button key={p.codigo} type="button" className="tec-planta fq-opcion" aria-pressed={planta === p.codigo} data-planta={p.codigo} onClick={() => setPlanta(planta === p.codigo && paraQue !== "dosificacion" ? "" : p.codigo)}>{p.nombre}</button>)}
                </div>
                {err("planta")}
              </div>
            </>
          ) : null}

          <div className="tec-campo">
            <label htmlFor="fq-cantidad">{esEntrada ? "Cantidad recibida" : "Cantidad usada"}</label>
            {esEntrada ? (
              <div className="qm-seg fq-unidades" role="tablist" aria-label="Unidad">
                {(def.unidades ?? ["t", "kg"]).map((u) => <button key={u} type="button" role="tab" aria-selected={unidad === u} data-unidad={u} onClick={() => setUnidad(u as "t" | "kg")}>{UNIDAD[u] ?? u}</button>)}
              </div>
            ) : null}
            <div className="tec-entrada">
              <input id="fq-cantidad" type="text" inputMode="decimal" autoComplete="off" value={cantidad} onChange={(e) => setCantidad(e.target.value)}
                aria-invalid={intentado && !!errores.cantidad} aria-describedby={intentado && errores.cantidad ? "fq-e-cantidad" : "fq-a-cantidad"} />
              <span className="tec-unidad">{esEntrada ? (unidad === "t" ? "t" : "kg") : "kg"}</span>
            </div>
            <p className="tec-ayuda" id="fq-a-cantidad">{esEntrada && unidad === "t" && enKg !== null && enKg > 0 ? `Son ${kg(enKg)}.` : "Con coma o punto decimal, sin separador de miles."}</p>
            {err("cantidad")}
          </div>

          <div className="tec-campo">
            <label htmlFor="fq-dia">{esEntrada ? "Día en que llegó" : "Día del uso"}</label>
            <input id="fq-dia" type="date" value={dia} min={restarDias(def.hoy, def.dias_atras)} max={def.hoy} onChange={(e) => setDia(e.target.value)} aria-invalid={intentado && !!errores.dia} />
            {err("dia")}
          </div>

          {esEntrada ? (
            <div className="tec-bloque">
              <div className="tec-bloque-tit">Datos de la remisión <span className="tec-oblig">(opcionales)</span></div>
              <div className="tec-campo"><label htmlFor="fq-proveedor">Proveedor</label><input id="fq-proveedor" type="text" maxLength={120} value={proveedor} onChange={(e) => setProveedor(e.target.value)} /></div>
              <div className="tec-campo"><label htmlFor="fq-remision">Número de la remisión</label><input id="fq-remision" type="text" maxLength={60} value={remision} onChange={(e) => setRemision(e.target.value)} /></div>
              <div className="tec-campo"><label htmlFor="fq-lote">Lote del fabricante</label><input id="fq-lote" type="text" maxLength={60} value={lote} onChange={(e) => setLote(e.target.value)} /></div>
              <div className="tec-campo"><label htmlFor="fq-vence">Fecha de vencimiento</label><input id="fq-vence" type="date" value={vence} onChange={(e) => setVence(e.target.value)} /></div>
            </div>
          ) : null}

          {intentado && Object.keys(errores).length > 0 ? <p className="tec-error-caja" role="alert">Revise los datos marcados antes de guardar.</p> : null}
          {errorEnvio ? <p className="tec-aviso tec-aviso-error" role="alert">{errorEnvio}</p> : null}
          <div className="fq-acciones">
            <button type="button" className="tec-boton" disabled={enviando} onClick={() => void enviar()}>{enviando ? "Guardando…" : esEntrada ? "Guardar la entrada" : "Guardar el uso"}</button>
            <button type="button" className="tec-boton-sec" disabled={enviando} onClick={onSalir}>Cancelar</button>
          </div>
        </>
      )}
    </section>
  );
}
