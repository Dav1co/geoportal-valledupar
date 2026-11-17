import { useEffect, useState } from "react";
import "./quimicos.css";
import { textoError, type Catalogo as CatalogoDash } from "./apiDashboard";
import { apiQuimicos, subirFicha, type Catalogo, type Comparacion, type Historial, type ParametroQuimico, type Quimico } from "./apiQuimicos";
import { apiAvisos, type MinimoQuimico } from "./apiAvisos";

// Dashboard PTAP · pestaña «Químicos» (Técnica fase 1, Corte 7a; §29). Solo planta: supervisor de planta y administrador.
// · Bodega (una sola; todo en kg): cada químico con su saldo, su dosis óptima, si es de potabilización y su ficha técnica en PDF (URL firmada de 60 s).
// · «Agregar químico»: nombre (su identidad: no se cambia después), para qué sirve, de potabilización, dosis óptima y el PDF (obligatorio).
// · «Cambiar…»: dosis óptima (exige un PDF nuevo), de potabilización, activo y una ficha nueva; siempre con motivo; queda en el historial.
// · Inventario inicial (conteo físico, en kg o toneladas) y ajuste (kg con signo), con motivo.
// · Esperado contra usado: por planta, día y químico de potabilización; la marca sale si se aparta más del porcentaje del parámetro. Solo marca: no rechaza nada.
// Las pantallas del operador (Entrada y Uso de químicos) llegan en el Corte 7b.

const nf = new Intl.NumberFormat("es-CO", { maximumFractionDigits: 1 });
const ROL: Record<string, string> = { coagulante: "Coagulante", desinfectante: "Desinfectante", auxiliar: "Limpieza u otro uso", otro: "Otro" };
const TIPO_EVENTO: Record<string, string> = { alta: "Alta", dosis_optima: "Dosis óptima", potabilizacion: "De potabilización", ficha: "Ficha técnica nueva", activo: "Activo" };
const TIPO_MOV: Record<string, string> = { inventario_inicial: "Inventario inicial", entrada: "Entrada", uso: "Uso", ajuste: "Ajuste" };
const hoyBogota = () => new Date(Date.now() - 5 * 3_600_000).toISOString().slice(0, 10);
const restarDias = (iso: string, d: number) => { const x = new Date(iso + "T12:00:00Z"); x.setUTCDate(x.getUTCDate() - d); return x.toISOString().slice(0, 10); };
const fecha = (iso: string | null) => (iso ? new Date(iso).toLocaleString("es-CO", { timeZone: "America/Bogota", dateStyle: "medium", timeStyle: "short" }) : "—");
const kg = (v: number | null) => (v === null ? "—" : `${nf.format(v)} kg`);

export function QuimicosPTAP(_: { catalogo: CatalogoDash }) {
  const [vista, setVista] = useState<"bodega" | "comparacion" | "parametros" | "minimos">("bodega");
  return (
    <div className="qm">
      <div className="qm-seg" role="tablist" aria-label="Químicos">
        <button type="button" role="tab" aria-selected={vista === "bodega"} onClick={() => setVista("bodega")}>Bodega</button>
        <button type="button" role="tab" aria-selected={vista === "comparacion"} onClick={() => setVista("comparacion")}>Esperado contra usado</button>
        <button type="button" role="tab" aria-selected={vista === "parametros"} onClick={() => setVista("parametros")}>Parámetros</button>
        <button type="button" role="tab" aria-selected={vista === "minimos"} onClick={() => setVista("minimos")}>Saldo mínimo</button>
      </div>
      {vista === "bodega" ? <Bodega /> : vista === "comparacion" ? <ComparacionVista /> : vista === "parametros" ? <ParametrosVista /> : <MinimosVista />}
    </div>
  );
}

function Bodega() {
  const [datos, setDatos] = useState<Catalogo | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0);
  const [aviso, setAviso] = useState<string | null>(null);
  const [abierto, setAbierto] = useState<{ tipo: "nuevo" } | { tipo: "cambiar" | "inventario" | "ajuste" | "historial"; q: Quimico } | null>(null);
  useEffect(() => { let vivo = true; setError(null);
    apiQuimicos.catalogo().then((d) => { if (vivo) setDatos(d); }).catch((e) => { if (vivo) setError(textoError(e).texto); });
    return () => { vivo = false; }; }, [vez]);
  const listo = (texto: string) => { setAbierto(null); setAviso(texto); setVez((v) => v + 1); };
  if (error) return <div className="td-aviso td-aviso-error" role="alert">{error} <button type="button" className="td-enlace" onClick={() => setVez((x) => x + 1)}>Reintentar</button></div>;
  if (!datos) return <p className="td-sub" role="status">Cargando los químicos…</p>;
  return (
    <>
      <p className="td-sub">Una sola bodega. Todo se maneja en kg (las entradas se pueden registrar en toneladas). La identidad de un químico (su nombre) no se cambia: si quedó mal, se desactiva con motivo y se crea otro.</p>
      {aviso ? <div className="td-aviso td-aviso-ok" role="status">{aviso}</div> : null}
      <div className="qm-acciones"><button type="button" className="td-boton" onClick={() => setAbierto({ tipo: "nuevo" })}>Agregar químico</button></div>
      {abierto?.tipo === "nuevo" ? <FormNuevo onListo={listo} onCerrar={() => setAbierto(null)} /> : null}
      <div className="qm-lista">
        {datos.quimicos.map((q) => (
          <article key={q.codigo} className={`qm-tarjeta${q.activo ? "" : " qm-inactivo"}`} data-quimico={q.codigo}>
            <div className="qm-cab">
              <h3>{q.nombre}</h3>
              <div className="qm-chips">
                <span className={`qm-chip${q.potabilizacion ? " qm-chip-pot" : ""}`}>{q.potabilizacion ? "De potabilización" : ROL[q.rol] ?? q.rol}</span>
                {!q.activo ? <span className="qm-chip qm-chip-off">Inactivo</span> : null}
              </div>
            </div>
            <dl className="qm-datos">
              <div><dt>Saldo</dt><dd className="qm-saldo">{q.saldo_kg === null ? "Sin inventario inicial" : kg(q.saldo_kg)}</dd></div>
              <div><dt>Dosis óptima</dt><dd>{q.dosis_optima_ppm === null ? (q.potabilizacion ? "Falta fijarla" : "—") : `${nf.format(q.dosis_optima_ppm)} ppm`}</dd></div>
              <div><dt>Ficha técnica</dt><dd>{q.ficha ? <a href={q.ficha.url} target="_blank" rel="noreferrer">Ver PDF</a> : "Falta el PDF"}</dd></div>
              <div><dt>Inventario inicial</dt><dd>{q.inventario_dia ?? "—"}</dd></div>
            </dl>
            <div className="qm-botones">
              <button type="button" className="td-boton-sec" onClick={() => setAbierto({ tipo: "cambiar", q })}>Cambiar…</button>
              <button type="button" className="td-boton-sec" onClick={() => setAbierto({ tipo: "inventario", q })}>Inventario inicial…</button>
              {q.saldo_kg !== null ? <button type="button" className="td-boton-sec" onClick={() => setAbierto({ tipo: "ajuste", q })}>Ajuste…</button> : null}
              <button type="button" className="td-boton-sec" onClick={() => setAbierto({ tipo: "historial", q })}>Historial</button>
            </div>
            {abierto && abierto.tipo !== "nuevo" && abierto.q.codigo === q.codigo ? (
              abierto.tipo === "cambiar" ? <FormCambiar q={q} onListo={listo} onCerrar={() => setAbierto(null)} />
              : abierto.tipo === "inventario" ? <FormInventario q={q} onListo={listo} onCerrar={() => setAbierto(null)} />
              : abierto.tipo === "ajuste" ? <FormAjuste q={q} onListo={listo} onCerrar={() => setAbierto(null)} />
              : <VerHistorial q={q} onCerrar={() => setAbierto(null)} />) : null}
          </article>))}
      </div>
    </>
  );
}

function Motivo({ valor, onCambiar, id }: { valor: string; onCambiar: (v: string) => void; id: string }) {
  return <label className="td-campo" htmlFor={id}>Motivo (10 caracteres o más)<textarea id={id} rows={2} maxLength={1000} value={valor} onChange={(e) => onCambiar(e.target.value)} /></label>;
}
function useEnvio() {
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const enviar = async (f: () => Promise<void>) => {
    setEnviando(true); setError(null);
    try { await f(); } catch (e) { setError(e instanceof Error ? e.message : "No se pudo guardar."); } finally { setEnviando(false); }
  };
  return { enviando, error, enviar };
}
function Pie({ enviando, error, listo, rotulo, onCerrar, onGuardar }: { enviando: boolean; error: string | null; listo: boolean; rotulo: string; onCerrar: () => void; onGuardar: () => void }) {
  return (
    <>
      {error ? <p className="td-aviso td-aviso-error" role="alert">{error}</p> : null}
      <div className="qm-botones">
        <button type="button" className="td-boton" disabled={!listo || enviando} aria-busy={enviando} onClick={onGuardar}>{enviando ? "Guardando…" : rotulo}</button>
        <button type="button" className="td-boton-sec" onClick={onCerrar}>Cancelar</button>
      </div>
    </>
  );
}

function FormNuevo({ onListo, onCerrar }: { onListo: (t: string) => void; onCerrar: () => void }) {
  const [nombre, setNombre] = useState(""); const [rol, setRol] = useState("coagulante"); const [pot, setPot] = useState(true);
  const [dosis, setDosis] = useState(""); const [pdf, setPdf] = useState<File | null>(null); const [motivo, setMotivo] = useState("");
  const { enviando, error, enviar } = useEnvio();
  const d = dosis.trim() === "" ? null : Number(dosis.replace(",", "."));
  const listo = nombre.trim().length >= 2 && !!pdf && motivo.trim().length >= 10 && (!pot || (d !== null && d > 0)) && (d === null || Number.isFinite(d));
  return (
    <section className="qm-form" aria-label="Agregar químico" data-form="nuevo">
      <h3>Agregar químico</h3>
      <label className="td-campo" htmlFor="qm-n-nombre">Nombre (no se podrá cambiar)<input id="qm-n-nombre" type="text" maxLength={100} value={nombre} onChange={(e) => setNombre(e.target.value)} /></label>
      <label className="td-campo" htmlFor="qm-n-rol">Para qué sirve
        <select id="qm-n-rol" value={rol} onChange={(e) => setRol(e.target.value)}>
          <option value="coagulante">Coagulante</option><option value="desinfectante">Desinfectante</option><option value="auxiliar">Limpieza u otro uso</option>
        </select></label>
      <label className="td-check qm-check"><input type="checkbox" checked={pot} onChange={(e) => setPot(e.target.checked)} /> De potabilización (entra en «esperado contra usado»)</label>
      <label className="td-campo" htmlFor="qm-n-dosis">Dosis óptima (ppm){pot ? "" : " — opcional"}<input id="qm-n-dosis" type="text" inputMode="decimal" value={dosis} onChange={(e) => setDosis(e.target.value)} /></label>
      <label className="td-campo" htmlFor="qm-n-pdf">Ficha técnica (PDF, obligatoria)<input id="qm-n-pdf" type="file" accept="application/pdf,.pdf" onChange={(e) => setPdf(e.target.files?.[0] ?? null)} /></label>
      <Motivo id="qm-n-mot" valor={motivo} onCambiar={setMotivo} />
      <Pie enviando={enviando} error={error} listo={listo} rotulo="Agregar" onCerrar={onCerrar}
        onGuardar={() => void enviar(async () => { const ruta = await subirFicha(pdf!); const r = await apiQuimicos.crear({ nombre, rol, potabilizacion: pot, dosis_optima_ppm: d, ficha: ruta, motivo }); onListo(`Se agregó ${nombre.trim()} (${r.codigo}).`); })} />
    </section>
  );
}

function FormCambiar({ q, onListo, onCerrar }: { q: Quimico; onListo: (t: string) => void; onCerrar: () => void }) {
  const [dosis, setDosis] = useState(q.dosis_optima_ppm === null ? "" : String(q.dosis_optima_ppm));
  const [pot, setPot] = useState(q.potabilizacion); const [activo, setActivo] = useState(q.activo);
  const [pdf, setPdf] = useState<File | null>(null); const [motivo, setMotivo] = useState("");
  const { enviando, error, enviar } = useEnvio();
  const d = dosis.trim() === "" ? null : Number(dosis.replace(",", "."));
  const cambios: Record<string, unknown> = {};
  if (d !== null && d !== q.dosis_optima_ppm) cambios.dosis_optima_ppm = d;
  if (pot !== q.potabilizacion) cambios.potabilizacion = pot;
  if (activo !== q.activo) cambios.activo = activo;
  const cambiaDosis = "dosis_optima_ppm" in cambios;
  const listo = motivo.trim().length >= 10 && (Object.keys(cambios).length > 0 || !!pdf) && (!cambiaDosis || !!pdf) && (d === null || (Number.isFinite(d) && d > 0));
  return (
    <section className="qm-form" aria-label={`Cambiar ${q.nombre}`} data-form="cambiar">
      <p className="td-sub">El nombre no se cambia. La dosis óptima nueva pide el PDF de la ficha técnica.</p>
      <label className="td-campo" htmlFor={`qm-c-dosis-${q.codigo}`}>Dosis óptima (ppm)<input id={`qm-c-dosis-${q.codigo}`} type="text" inputMode="decimal" value={dosis} onChange={(e) => setDosis(e.target.value)} /></label>
      <label className="td-check qm-check"><input type="checkbox" checked={pot} onChange={(e) => setPot(e.target.checked)} /> De potabilización</label>
      <label className="td-check qm-check"><input type="checkbox" checked={activo} onChange={(e) => setActivo(e.target.checked)} /> Activo (si se desactiva, sale de los formularios)</label>
      <label className="td-campo" htmlFor={`qm-c-pdf-${q.codigo}`}>Ficha técnica nueva (PDF){cambiaDosis ? " — obligatoria al cambiar la dosis" : " — opcional"}
        <input id={`qm-c-pdf-${q.codigo}`} type="file" accept="application/pdf,.pdf" onChange={(e) => setPdf(e.target.files?.[0] ?? null)} /></label>
      {cambiaDosis && !pdf ? <p className="td-aviso td-aviso-info" role="note">Para cambiar la dosis óptima, adjunte el PDF de la ficha técnica.</p> : null}
      <Motivo id={`qm-c-mot-${q.codigo}`} valor={motivo} onCambiar={setMotivo} />
      <Pie enviando={enviando} error={error} listo={listo} rotulo="Guardar los cambios" onCerrar={onCerrar}
        onGuardar={() => void enviar(async () => { const ruta = pdf ? await subirFicha(pdf) : null; const r = await apiQuimicos.fijar(q.codigo, cambios, ruta, motivo);
          onListo(`${q.nombre}: se guardó ${r.cambios.map((c) => TIPO_EVENTO[c]?.toLowerCase() ?? c).join(", ")}.`); })} />
    </section>
  );
}

function FormInventario({ q, onListo, onCerrar }: { q: Quimico; onListo: (t: string) => void; onCerrar: () => void }) {
  const [cant, setCant] = useState(""); const [unidad, setUnidad] = useState<"kg" | "t">("kg"); const [corte, setCorte] = useState(hoyBogota()); const [motivo, setMotivo] = useState("Conteo físico de la bodega");
  const { enviando, error, enviar } = useEnvio();
  const c = Number(cant.replace(",", "."));
  const listo = cant.trim() !== "" && Number.isFinite(c) && c >= 0 && !!corte && motivo.trim().length >= 10;
  return (
    <section className="qm-form" aria-label={`Inventario inicial de ${q.nombre}`} data-form="inventario">
      <p className="td-sub">El conteo físico de la bodega. Desde aquí se cuenta el saldo (lo de antes deja de sumar).</p>
      <div className="qm-fila">
        <label className="td-campo" htmlFor={`qm-i-c-${q.codigo}`}>Cantidad contada<input id={`qm-i-c-${q.codigo}`} type="text" inputMode="decimal" value={cant} onChange={(e) => setCant(e.target.value)} /></label>
        <label className="td-campo" htmlFor={`qm-i-u-${q.codigo}`}>Unidad<select id={`qm-i-u-${q.codigo}`} value={unidad} onChange={(e) => setUnidad(e.target.value as "kg" | "t")}><option value="kg">kg</option><option value="t">toneladas</option></select></label>
        <label className="td-campo" htmlFor={`qm-i-f-${q.codigo}`}>Día del conteo<input id={`qm-i-f-${q.codigo}`} type="date" max={hoyBogota()} value={corte} onChange={(e) => setCorte(e.target.value)} /></label>
      </div>
      {cant.trim() !== "" && Number.isFinite(c) ? <p className="td-sub">Queda en {kg(unidad === "t" ? c * 1000 : c)}.</p> : null}
      <Motivo id={`qm-i-m-${q.codigo}`} valor={motivo} onCambiar={setMotivo} />
      <Pie enviando={enviando} error={error} listo={listo} rotulo="Guardar el inventario" onCerrar={onCerrar}
        onGuardar={() => void enviar(async () => { const r = await apiQuimicos.inventario(q.codigo, c, unidad, corte, motivo); onListo(`${q.nombre}: saldo ${kg(r.saldo_kg)}.`); })} />
    </section>
  );
}

function FormAjuste({ q, onListo, onCerrar }: { q: Quimico; onListo: (t: string) => void; onCerrar: () => void }) {
  const [v, setV] = useState(""); const [motivo, setMotivo] = useState("");
  const { enviando, error, enviar } = useEnvio();
  const n = Number(v.replace(",", "."));
  const listo = v.trim() !== "" && Number.isFinite(n) && n !== 0 && motivo.trim().length >= 10;
  return (
    <section className="qm-form" aria-label={`Ajuste de ${q.nombre}`} data-form="ajuste">
      <label className="td-campo" htmlFor={`qm-a-${q.codigo}`}>Ajuste en kg (negativo si falta, positivo si sobra)<input id={`qm-a-${q.codigo}`} type="text" inputMode="decimal" value={v} onChange={(e) => setV(e.target.value)} /></label>
      {listo ? <p className="td-sub">El saldo pasa de {kg(q.saldo_kg)} a {kg((q.saldo_kg ?? 0) + n)}.</p> : null}
      <Motivo id={`qm-a-m-${q.codigo}`} valor={motivo} onCambiar={setMotivo} />
      <Pie enviando={enviando} error={error} listo={listo} rotulo="Guardar el ajuste" onCerrar={onCerrar}
        onGuardar={() => void enviar(async () => { const r = await apiQuimicos.ajuste(q.codigo, n, motivo); onListo(`${q.nombre}: saldo ${kg(r.saldo_kg)}.`); })} />
    </section>
  );
}

// Corte 7c: parámetros de químicos editables (el jefe de planta ajusta el desvío). Cada cambio pide motivo y queda en el historial.
const NOMBRE_PARAM: Record<string, { nombre: string; unidad: string }> = {
  desvio_pct: { nombre: "Desvío para la marca de esperado contra usado", unidad: "%" }, marca_esperado_usado: { nombre: "Marca de esperado contra usado", unidad: "1 = encendida · 0 = apagada" },
  dias_atras_uso: { nombre: "Días atrás para registrar un uso", unidad: "días" }, dias_atras_entrada: { nombre: "Días atrás para registrar una entrada", unidad: "días" },
};
function ParametrosVista() {
  const [ps, setPs] = useState<ParametroQuimico[] | null>(null); const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0); const [aviso, setAviso] = useState<string | null>(null); const [abierto, setAbierto] = useState<string | null>(null);
  useEffect(() => { let vivo = true; setError(null);
    apiQuimicos.parametros().then((d) => { if (vivo) setPs(d.parametros); }).catch((e) => { if (vivo) setError(textoError(e).texto); });
    return () => { vivo = false; }; }, [vez]);
  if (error) return <div className="td-aviso td-aviso-error" role="alert">{error} <button type="button" className="td-enlace" onClick={() => setVez((x) => x + 1)}>Reintentar</button></div>;
  if (!ps) return <p className="td-sub" role="status">Cargando los parámetros…</p>;
  return (
    <>
      <p className="td-sub">Cada cambio pide su motivo y queda en el historial, con quién lo hizo.</p>
      {aviso ? <div className="td-aviso td-aviso-ok" role="status">{aviso}</div> : null}
      <div className="qm-lista">
        {ps.map((p) => (
          <article key={p.clave} className="qm-tarjeta" data-parametro={p.clave}>
            <div className="qm-cab"><h3>{NOMBRE_PARAM[p.clave]?.nombre ?? p.clave}</h3></div>
            <p className="qm-param-valor"><strong>{nf.format(p.valor)}</strong> <span className="td-sub">{NOMBRE_PARAM[p.clave]?.unidad ?? ""} · entre {nf.format(p.minimo)} y {nf.format(p.maximo)}</span></p>
            <p className="td-sub">{p.ultimo ? `Último cambio: de ${nf.format(p.ultimo.antes)} a ${nf.format(p.ultimo.despues)} · «${p.ultimo.motivo}» · ${p.ultimo.autor} · ${fecha(p.ultimo.creado_en)}` : "Sin cambios: tiene el valor inicial."}</p>
            {abierto === p.clave
              ? <FormParametro p={p} onCerrar={() => setAbierto(null)} onListo={(t) => { setAbierto(null); setAviso(t); setVez((v) => v + 1); }} />
              : <div className="qm-botones"><button type="button" className="td-boton-sec" onClick={() => { setAviso(null); setAbierto(p.clave); }}>Cambiar…</button></div>}
          </article>))}
      </div>
    </>
  );
}
function FormParametro({ p, onListo, onCerrar }: { p: ParametroQuimico; onListo: (t: string) => void; onCerrar: () => void }) {
  const [v, setV] = useState(String(p.valor).replace(".", ",")); const [motivo, setMotivo] = useState("");
  const { enviando, error, enviar } = useEnvio();
  const n = Number(v.replace(",", "."));
  const enRango = v.trim() !== "" && Number.isFinite(n) && n >= p.minimo && n <= p.maximo;
  const listo = enRango && n !== p.valor && motivo.trim().length >= 10;
  return (
    <section className="qm-form" aria-label={`Cambiar ${NOMBRE_PARAM[p.clave]?.nombre ?? p.clave}`} data-form="parametro">
      <label className="td-campo" htmlFor={`qm-p-${p.clave}`}>Valor nuevo<input id={`qm-p-${p.clave}`} type="text" inputMode="decimal" value={v} onChange={(e) => setV(e.target.value)} aria-invalid={!enRango} /></label>
      {!enRango ? <p className="td-sub">Debe estar entre {nf.format(p.minimo)} y {nf.format(p.maximo)}.</p> : null}
      <Motivo id={`qm-p-m-${p.clave}`} valor={motivo} onCambiar={setMotivo} />
      <Pie enviando={enviando} error={error} listo={listo} rotulo="Guardar el cambio" onCerrar={onCerrar}
        onGuardar={() => void enviar(async () => { const r = await apiQuimicos.fijarParametro(p.clave, n, motivo); onListo(`${NOMBRE_PARAM[p.clave]?.nombre ?? p.clave}: de ${nf.format(r.antes)} a ${nf.format(r.valor)}.`); })} />
    </section>
  );
}

// Corte 12: el saldo mínimo de cada químico (kg). Arranca vacío: sin mínimo no hay aviso. Por debajo del mínimo sale el aviso «saldo bajo» en Avisos.
function MinimosVista() {
  const [qs, setQs] = useState<MinimoQuimico[] | null>(null); const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0); const [aviso, setAviso] = useState<string | null>(null); const [abierto, setAbierto] = useState<string | null>(null);
  useEffect(() => { let vivo = true; setError(null);
    apiAvisos.minimos().then((d) => { if (vivo) setQs(d.quimicos); }).catch((e) => { if (vivo) setError(textoError(e).texto); });
    return () => { vivo = false; }; }, [vez]);
  if (error) return <div className="td-aviso td-aviso-error" role="alert">{error} <button type="button" className="td-enlace" onClick={() => setVez((x) => x + 1)}>Reintentar</button></div>;
  if (!qs) return <p className="td-sub" role="status">Cargando los saldos mínimos…</p>;
  return (
    <>
      <p className="td-sub">Cuando el saldo de un químico baja de su mínimo, sale un aviso. Sin mínimo fijado no hay aviso. Cada cambio pide su motivo.</p>
      {aviso ? <div className="td-aviso td-aviso-ok" role="status">{aviso}</div> : null}
      <div className="qm-lista">
        {qs.map((q) => (
          <article key={q.codigo} className={`qm-tarjeta${q.bajo ? " qm-cmp-marca" : ""}`} data-minimo={q.codigo}>
            <div className="qm-cab"><h3>{q.nombre}</h3>{q.bajo ? <span className="qm-chip qm-chip-marca">Por debajo del mínimo</span> : null}</div>
            <p className="qm-param-valor"><span className="td-sub">Saldo</span> <strong>{kg(q.saldo_kg)}</strong> · <span className="td-sub">Mínimo</span> <strong>{q.minimo_kg === null ? "sin fijar" : kg(q.minimo_kg)}</strong></p>
            {q.ultimo ? <p className="td-sub">Último cambio: «{q.ultimo.motivo}» · {q.ultimo.autor} · {fecha(q.ultimo.creado_en)}</p> : null}
            {abierto === q.codigo
              ? <FormMinimo q={q} onCerrar={() => setAbierto(null)} onListo={(t) => { setAbierto(null); setAviso(t); setVez((v) => v + 1); }} />
              : <div className="qm-botones"><button type="button" className="td-boton-sec" onClick={() => { setAviso(null); setAbierto(q.codigo); }}>{q.minimo_kg === null ? "Fijar el mínimo…" : "Cambiar el mínimo…"}</button></div>}
          </article>))}
      </div>
    </>
  );
}
function FormMinimo({ q, onListo, onCerrar }: { q: MinimoQuimico; onListo: (t: string) => void; onCerrar: () => void }) {
  const [v, setV] = useState(q.minimo_kg === null ? "" : String(q.minimo_kg).replace(".", ",")); const [motivo, setMotivo] = useState("");
  const { enviando, error, enviar } = useEnvio();
  const vacio = v.trim() === ""; const n = Number(v.replace(",", "."));
  const valido = vacio ? q.minimo_kg !== null : Number.isFinite(n) && n > 0 && n <= 10_000_000 && n !== q.minimo_kg;
  const listo = valido && motivo.trim().length >= 10;
  return (
    <section className="qm-form" aria-label={`Saldo mínimo de ${q.nombre}`} data-form="minimo">
      <label className="td-campo" htmlFor={`qm-min-${q.codigo}`}>Saldo mínimo (kg){q.minimo_kg !== null ? " — vacío para quitarlo" : ""}
        <input id={`qm-min-${q.codigo}`} type="text" inputMode="decimal" value={v} onChange={(e) => setV(e.target.value)} aria-invalid={!vacio && !valido} /></label>
      <Motivo id={`qm-min-m-${q.codigo}`} valor={motivo} onCambiar={setMotivo} />
      <Pie enviando={enviando} error={error} listo={listo} rotulo={vacio ? "Quitar el mínimo" : "Guardar el mínimo"} onCerrar={onCerrar}
        onGuardar={() => void enviar(async () => { const r = await apiAvisos.fijarMinimo(q.codigo, vacio ? null : n, motivo);
          onListo(r.minimo_kg === null ? `${q.nombre}: sin saldo mínimo.` : `${q.nombre}: saldo mínimo ${kg(r.minimo_kg)}.`); })} />
    </section>
  );
}

function VerHistorial({ q, onCerrar }: { q: Quimico; onCerrar: () => void }) {
  const [h, setH] = useState<Historial | null>(null); const [error, setError] = useState<string | null>(null);
  useEffect(() => { apiQuimicos.historial(q.codigo).then(setH).catch((e) => setError(textoError(e).texto)); }, [q.codigo]);
  return (
    <section className="qm-form" aria-label={`Historial de ${q.nombre}`} data-form="historial">
      {error ? <p className="td-aviso td-aviso-error" role="alert">{error}</p> : !h ? <p className="td-sub" role="status">Cargando…</p> : (
        <>
          <h4>Ficha</h4>
          <ul className="qm-historial">{h.eventos.map((e, i) => (
            <li key={i}><strong>{TIPO_EVENTO[e.tipo] ?? e.tipo}</strong>{e.dosis_optima_ppm !== null ? ` · ${nf.format(e.dosis_optima_ppm)} ppm` : ""}
              {e.potabilizacion !== null ? ` · ${e.potabilizacion ? "de potabilización" : "no es de potabilización"}` : ""}{e.activo !== null ? ` · ${e.activo ? "activo" : "inactivo"}` : ""}
              {e.ficha ? <> · <a href={e.ficha.url} target="_blank" rel="noreferrer">PDF</a></> : null}<br /><span className="td-sub">«{e.motivo}» · {e.autor} · {fecha(e.creado_en)}</span></li>))}</ul>
          <h4>Movimientos (los últimos 100)</h4>
          {h.movimientos.length === 0 ? <p className="td-sub">Todavía no hay movimientos.</p> : (
            <ul className="qm-historial">{h.movimientos.map((m, i) => (
              <li key={i}><strong>{TIPO_MOV[m.tipo] ?? m.tipo}</strong> · {m.dia} · {kg(m.cantidad_kg)}{m.unidad === "t" ? ` (${nf.format(m.cantidad)} t)` : ""}
                {m.planta ? ` · ${m.planta}` : ""}{m.para_que ? ` · ${m.para_que}` : ""}{m.dosis_optima_ppm !== null ? ` · dosis ${nf.format(m.dosis_optima_ppm)} ppm` : ""}
                {m.remision ? ` · remisión ${m.remision}` : ""}{m.remision_foto ? <> · <a href={m.remision_foto.url} target="_blank" rel="noreferrer" data-remision-foto>Ver la foto de la remisión</a></> : null}<br /><span className="td-sub">{m.motivo ? `«${m.motivo}» · ` : ""}{m.autor} · {fecha(m.registrado_en)}</span></li>))}</ul>)}
        </>)}
      <div className="qm-botones"><button type="button" className="td-boton-sec" onClick={onCerrar}>Cerrar</button></div>
    </section>
  );
}

function ComparacionVista() {
  const [hasta, setHasta] = useState(hoyBogota()); const [desde, setDesde] = useState(restarDias(hoyBogota(), 13));
  const [datos, setDatos] = useState<Comparacion | null>(null); const [error, setError] = useState<string | null>(null); const [vez, setVez] = useState(0);
  useEffect(() => { let vivo = true; setError(null); setDatos(null);
    apiQuimicos.comparacion(desde, hasta).then((d) => { if (vivo) setDatos(d); }).catch((e) => { if (vivo) setError(textoError(e).texto); });
    return () => { vivo = false; }; }, [vez]); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <>
      <p className="td-sub">Por planta y día, para los químicos de potabilización. Esperado = dosis óptima (ppm) × volumen tratado (caudal de ingreso Qi promedio del día × 86,4) ÷ 1.000.
        Usado = lo registrado en «Uso de químicos» para dosificar. La dosis es la que guardó cada uso (no cambia hacia atrás). Es solo una marca: no rechaza nada.</p>
      <div className="qm-fila">
        <label className="td-campo" htmlFor="qm-cmp-d">Desde<input id="qm-cmp-d" type="date" value={desde} max={hasta} onChange={(e) => setDesde(e.target.value)} /></label>
        <label className="td-campo" htmlFor="qm-cmp-h">Hasta<input id="qm-cmp-h" type="date" value={hasta} max={hoyBogota()} onChange={(e) => setHasta(e.target.value)} /></label>
        <button type="button" className="td-boton-sec qm-ver" onClick={() => setVez((v) => v + 1)}>Ver</button>
      </div>
      {error ? <div className="td-aviso td-aviso-error" role="alert">{error}</div> : !datos ? <p className="td-sub" role="status">Calculando…</p> : (
        <>
          <p className="td-sub">{datos.marca_activa ? `La marca sale si lo usado se aparta más de ${datos.desvio_pct} % de lo esperado.` : "La marca está apagada."}</p>
          {datos.filas.length === 0 ? <p className="td-vacio">No hay días con caudal de ingreso y dosis óptima (o usos) en ese rango.</p> : (
            <div className="qm-cmp">
              {datos.filas.map((f) => (
                <article key={`${f.dia}-${f.planta}-${f.quimico}`} className={`qm-cmp-fila${f.marca ? " qm-cmp-marca" : ""}`} data-cmp={`${f.dia}|${f.planta}|${f.quimico}`}>
                  <div className="qm-cab"><h4>{f.dia} · {f.planta_nombre} · {f.quimico_nombre}</h4>{f.marca ? <span className="qm-chip qm-chip-marca">Marca</span> : null}</div>
                  <dl className="qm-datos">
                    <div><dt>Qi promedio</dt><dd>{nf.format(f.qi_lps)} L/s ({nf.format(f.volumen_m3)} m³)</dd></div>
                    <div><dt>Dosis óptima</dt><dd>{f.dosis_optima_ppm === null ? "Sin fijar" : `${nf.format(f.dosis_optima_ppm)} ppm`}</dd></div>
                    <div><dt>Esperado</dt><dd>{kg(f.esperado_kg)}</dd></div>
                    <div><dt>Usado</dt><dd>{kg(f.usado_kg)}{f.desvio_pct !== null ? ` (${f.desvio_pct > 0 ? "+" : ""}${nf.format(f.desvio_pct)} %)` : ""}</dd></div>
                  </dl>
                </article>))}
            </div>)}
        </>)}
    </>
  );
}
