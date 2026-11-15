import { useState } from "react";
import { apiRev, textoError, type FormularioRev, type ParametroDef } from "./apiRevision";
import { fmtInstante, fmtNumero } from "./formatoRevision";

// Parámetros editables (solo administrador). Cada cambio exige MOTIVO (10 a 1.000 caracteres) y CONFIRMACIÓN; la base vuelve a validar el rango y deja el valor anterior y el nuevo en la
// auditoría. Un cambio de ritmo, de distancia de duplicados o de zona se aplica de inmediato. La caja de zona se edita completa (mínimos y máximos juntos) para que siempre sea coherente.
const ZONA = ["zona_lat_min", "zona_lat_max", "zona_lon_min", "zona_lon_max"];
const GRUPOS: { titulo: string; claves: (p: ParametroDef) => boolean }[] = [
  { titulo: "Ritmo de reportes", claves: (p) => p.clave.startsWith("limite_") || p.clave === "multiplo_supervisor" || p.clave === "ventana_limite_minutos" },
  { titulo: "Duplicados", claves: (p) => p.clave === "distancia_duplicados_m" },
  { titulo: "Fotos y descripción", claves: (p) => p.clave === "max_fotos" || p.clave === "max_bytes_foto" || p.clave === "max_descripcion" },
  { titulo: "Hora de inicio", claves: (p) => p.clave === "max_horas_inicio" },
];
/** «1.234,5» o «1234.5» o «1234,5» → 1234.5; vacío o ilegible → null. */
export function leerNumero(t: string): number | null {
  const s = t.trim().replace(/\s/g, ""); if (!s) return null;
  const n = s.includes(",") ? Number(s.replace(/\./g, "").replace(",", ".")) : Number(s);
  return Number.isFinite(n) ? n : null;
}
const rango = (p: ParametroDef) => `${p.minimo === null ? "—" : fmtNumero(p.minimo, 6)} a ${p.maximo === null ? "—" : fmtNumero(p.maximo, 6)}`;

/** `soloLectura` (pasada 14/11): el supervisor ve los valores, el rango y quién los cambió, sin botones (la base solo deja cambiarlos al administrador). */
export function Parametros({ def, alCambiar, soloLectura = false }: { def: FormularioRev; alCambiar: () => void; soloLectura?: boolean }) {
  const lista = def.parametros ?? [];
  const [edit, setEdit] = useState<string | null>(null); const [valor, setValor] = useState(""); const [motivo, setMotivo] = useState("");
  const [paso, setPaso] = useState<"editar" | "confirmar">("editar"); const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string | null>(null); const [ok, setOk] = useState<string | null>(null);
  const [zona, setZona] = useState<Record<string, string> | null>(null);
  const zonaP = ZONA.map((k) => lista.find((p) => p.clave === k)).filter((p): p is ParametroDef => !!p);
  const clavesZona = new Set(ZONA);
  const otros = lista.filter((p) => !clavesZona.has(p.clave) && !GRUPOS.some((g) => g.claves(p)));

  const cancelar = () => { setEdit(null); setZona(null); setValor(""); setMotivo(""); setPaso("editar"); setError(null); };
  function abrir(p: ParametroDef) { cancelar(); setOk(null); setEdit(p.clave); setValor(String(p.valor).replace(".", ",")); }
  function abrirZona() { cancelar(); setOk(null); setZona(Object.fromEntries(zonaP.map((p) => [p.clave, String(p.valor).replace(".", ",")]))); }

  const motivoOk = motivo.trim().length >= 10 && motivo.trim().length <= 1000;
  function validarUno(p: ParametroDef): string | null {
    const n = leerNumero(valor); if (n === null) return "Escriba un número.";
    if (n === p.valor) return "Es el valor vigente: no hay nada que cambiar.";
    if ((p.minimo !== null && n < p.minimo) || (p.maximo !== null && n > p.maximo)) return `El valor debe estar entre ${fmtNumero(p.minimo ?? 0, 6)} y ${fmtNumero(p.maximo ?? 0, 6)} ${p.unidad}.`;
    if (["fotos", "bytes", "reportes", "veces", "minutos", "caracteres"].includes(p.unidad) && !Number.isInteger(n)) return "Debe ser un número entero.";
    return null;
  }
  function validarZona(): string | null {
    const v: Record<string, number | null> = Object.fromEntries(ZONA.map((k) => [k, leerNumero(zona?.[k] ?? "")]));
    if (ZONA.some((k) => v[k] === null)) return "Complete los cuatro límites con números.";
    for (const p of zonaP) { const n = v[p.clave] as number; if ((p.minimo !== null && n < p.minimo) || (p.maximo !== null && n > p.maximo)) return `${p.descripcion.split(";")[0]}: debe estar entre ${p.minimo} y ${p.maximo}.`; }
    if ((v.zona_lat_min as number) >= (v.zona_lat_max as number)) return "La latitud mínima debe ser menor que la máxima.";
    if ((v.zona_lon_min as number) >= (v.zona_lon_max as number)) return "La longitud mínima debe ser menor que la máxima.";
    if (zonaP.every((p) => v[p.clave] === p.valor)) return "Son los valores vigentes: no hay nada que cambiar.";
    return null;
  }
  async function guardar(cambios: { clave: string; valor: number }[]) {
    if (enviando) return;                                  // bloquea la doble pulsación
    setEnviando(true); setError(null);
    try {
      const r = await apiRev.parametro(cambios, motivo.trim());
      setOk(`Cambio aplicado: ${r.cambios.map((c) => `${c.clave}: ${fmtNumero(c.antes, 6)} → ${fmtNumero(c.despues, 6)}`).join("; ")}. Quedó auditado con el motivo.`);
      cancelar(); alCambiar();
    } catch (e) { setError(textoError(e).texto); } finally { setEnviando(false); }
  }
  const fila = (p: ParametroDef) => {
    const editando = edit === p.clave;
    return (
      <div key={p.clave} className="rv-param">
        <div className="rv-param-cab">
          <div><strong>{p.descripcion.replace(/\s*\(PROPUESTA[^)]*\)/i, "").replace(/\s*PROPUESTA\.?$/i, "")}</strong><div className="rv-tenue">{p.clave}</div></div>
          <div className="rv-param-v"><span className="rv-tarjeta-v">{fmtNumero(p.valor, 6)}</span> <span className="rv-tenue">{p.unidad}</span></div>
          <div className="rv-tenue">Rango válido: {rango(p)}<br />{p.actualizado_por ? `Cambió ${p.actualizado_por} · ${fmtInstante(p.actualizado_en)}` : "Sin cambios desde la instalación"}</div>
          {soloLectura ? null : <button type="button" className="rv-boton-sec rv-corto" onClick={() => abrir(p)} disabled={editando}>Cambiar</button>}
        </div>
        {editando ? (
          <div className="rv-param-edit">
            <label className="rv-campo">Nuevo valor ({p.unidad})<input type="text" inputMode="decimal" value={valor} onChange={(e) => setValor(e.target.value)} disabled={paso === "confirmar" || enviando} /></label>
            <Motivo valor={motivo} onChange={setMotivo} disabled={paso === "confirmar" || enviando} />
            <Pasos paso={paso} error={validarUno(p) ?? (!motivoOk ? "Escriba el motivo (de 10 a 1.000 caracteres)." : null)} enviando={enviando}
              resumen={`Va a cambiar «${p.clave}» de ${fmtNumero(p.valor, 6)} a ${fmtNumero(leerNumero(valor) ?? 0, 6)} ${p.unidad}. Se aplica de inmediato.`}
              onRevisar={() => setPaso("confirmar")} onVolver={() => setPaso("editar")} onConfirmar={() => void guardar([{ clave: p.clave, valor: leerNumero(valor) as number }])} onCancelar={cancelar} />
            {error ? <p className="rv-error" role="alert">{error}</p> : null}
          </div>
        ) : null}
      </div>
    );
  };
  return (
    <section className="rv-seccion" aria-labelledby="rv-par-tit">
      <div><h2 id="rv-par-tit">Parámetros</h2><p className="rv-sub">Valores que el administrador puede ajustar sin cambiar el sistema. <strong>Un cambio de ritmo, de distancia de duplicados, de fotos, de descripción o de zona se aplica de inmediato.</strong> Todo cambio exige motivo y queda auditado con el valor anterior y el nuevo.</p></div>
      {soloLectura ? <div className="rv-aviso rv-aviso-info" role="note">Solo el administrador puede cambiar los parámetros. Aquí ve los valores vigentes, su rango y quién los cambió.</div> : null}
      {ok ? <div className="rv-aviso rv-aviso-ok" role="status">{ok}</div> : null}
      {lista.length === 0 ? <div className="rv-aviso rv-aviso-info" role="status">El servidor aún no entrega los parámetros (falta aplicar el Paso C en la base).</div> : null}
      {GRUPOS.map((g) => { const ps = lista.filter(g.claves); return ps.length ? <div key={g.titulo}><h3 className="rv-h3">{g.titulo}</h3>{ps.map(fila)}</div> : null; })}
      {otros.length ? <div><h3 className="rv-h3">Otros</h3>{otros.map(fila)}</div> : null}
      {zonaP.length === 4 ? (
        <div>
          <h3 className="rv-h3">Caja de zona de operación</h3>
          <p className="rv-sub">Fuera de esta caja el reporte se guarda igual, con la marca «Fuera de zona». Actual: latitud {fmtNumero(zonaP[0].valor, 6)} a {fmtNumero(zonaP[1].valor, 6)}; longitud {fmtNumero(zonaP[2].valor, 6)} a {fmtNumero(zonaP[3].valor, 6)}.</p>
          {soloLectura ? null : !zona ? <button type="button" className="rv-boton-sec" onClick={abrirZona}>Cambiar la caja de zona</button> : (
            <div className="rv-param-edit">
              <div className="rv-zona">{ZONA.map((k) => { const p = zonaP.find((x) => x.clave === k) as ParametroDef; return (
                <label key={k} className="rv-campo">{k === "zona_lat_min" ? "Latitud mínima (sur)" : k === "zona_lat_max" ? "Latitud máxima (norte)" : k === "zona_lon_min" ? "Longitud mínima (occidente)" : "Longitud máxima (oriente)"}
                  <input type="text" inputMode="decimal" value={zona[k]} onChange={(e) => setZona({ ...zona, [k]: e.target.value })} disabled={paso === "confirmar" || enviando} /><span className="rv-tenue">Rango {rango(p)}</span></label>); })}</div>
              <Motivo valor={motivo} onChange={setMotivo} disabled={paso === "confirmar" || enviando} />
              <Pasos paso={paso} error={validarZona() ?? (!motivoOk ? "Escriba el motivo (de 10 a 1.000 caracteres)." : null)} enviando={enviando} resumen="Va a cambiar la caja de zona de operación. Se aplica de inmediato a los reportes nuevos."
                onRevisar={() => setPaso("confirmar")} onVolver={() => setPaso("editar")} onCancelar={cancelar}
                onConfirmar={() => void guardar(zonaP.filter((p) => leerNumero(zona[p.clave]) !== p.valor).map((p) => ({ clave: p.clave, valor: leerNumero(zona[p.clave]) as number })))} />
              {error ? <p className="rv-error" role="alert">{error}</p> : null}
            </div>
          )}
        </div>
      ) : null}
    </section>
  );
}

function Motivo({ valor, onChange, disabled }: { valor: string; onChange: (v: string) => void; disabled: boolean }) {
  return <label className="rv-campo">Motivo (de 10 a 1.000 caracteres)<textarea rows={2} maxLength={1000} value={valor} onChange={(e) => onChange(e.target.value)} disabled={disabled} /><span className="rv-tenue">{valor.trim().length.toLocaleString("es-CO")} de 1.000</span></label>;
}
function Pasos({ paso, error, enviando, resumen, onRevisar, onVolver, onConfirmar, onCancelar }: { paso: "editar" | "confirmar"; error: string | null; enviando: boolean; resumen: string; onRevisar: () => void; onVolver: () => void; onConfirmar: () => void; onCancelar: () => void }) {
  return paso === "editar" ? (
    <div>{error ? <p className="rv-tenue" role="status">{error}</p> : null}
      <div className="rv-botones"><button type="button" className="rv-boton" disabled={!!error} onClick={onRevisar}>Revisar el cambio</button><button type="button" className="rv-boton-sec" onClick={onCancelar}>Cancelar</button></div></div>
  ) : (
    <div><p className="rv-aviso rv-aviso-info" role="status">{resumen} ¿Confirma?</p>
      <div className="rv-botones"><button type="button" className="rv-boton" disabled={enviando} onClick={onConfirmar}>{enviando ? "Guardando…" : "Confirmar el cambio"}</button><button type="button" className="rv-boton-sec" disabled={enviando} onClick={onVolver}>Volver</button></div></div>
  );
}
