import { useEffect, useMemo, useState } from "react";
import { apiGestion, type Conciliacion, type FilaConciliacion, type HojaValoracion, type SinFila } from "./apiRedes";
import { ErrorTec } from "./apiTecnica";
import type { Celda } from "./xlsx";

// Dashboard distribución › Inventario regulatorio (Técnica fase 1, Corte 10). Solo el administrador (lo vuelve a decidir el servidor).
// La conciliación de la Valoración Técnica de 2019 (Res. CRA 688 de 2014; una PROPUESTA cuya adopción no está confirmada) con la red del geoportal:
// por fila, lo que dice la valoración contra lo que suma la red amarrada, la diferencia y el porcentaje; las filas sin activos y los activos sin fila.
// Solo lectura: la valoración y el amarre se cargan por psql; la hoja de alcantarillado que vale se cambia en Parámetros. Sin datos de personas.

type Hoja = HojaValoracion["hoja"];
type Filtro = "todas" | "no_calzan" | "sin_activos";
const nf = new Intl.NumberFormat("es-CO", { maximumFractionDigits: 1 });
const nf0 = new Intl.NumberFormat("es-CO", { maximumFractionDigits: 0 });
const millones = (v: number) => `${nf0.format(Math.round(v / 1e6))} millones`;
const fecha = (iso: string) => new Date(iso).toLocaleString("es-CO", { timeZone: "America/Bogota", day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
const UNIDAD: Record<string, string> = { m: "m", un: "un", "L/s": "L/s", "m³": "m³" };
const MOTIVO: Record<SinFila["motivo"], string> = { sin_fila: "Sin fila en la valoración", proyectado: "Proyectado: no entra", fuera: "Fuera de la valoración 2019 (activo posterior)" };
const CLASE: Record<string, string> = { tuberia: "Tubería", valvula: "Válvula", hidrante: "Hidrantes", puntual: "Puntual", terreno: "Terreno", otro: "Otro" };
const cantidad = (v: number | undefined, u?: string) => (v === undefined ? "—" : `${nf.format(v)}${u ? ` ${UNIDAD[u] ?? u}` : ""}`);
const caracteristica = (f: FilaConciliacion) => (f.caracteristica ? ((f.clase === "tuberia" || f.clase === "valvula") && /^[0-9.]+$/.test(f.caracteristica) ? `${f.caracteristica}″` : f.caracteristica) : "");

export function InventarioRegulatorio({ onFicha }: { onFicha: (codigo: string) => void }) {
  const [d, setD] = useState<Conciliacion | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [hoja, setHoja] = useState<Hoja>("acueducto");
  const [filtro, setFiltro] = useState<Filtro>("todas");
  const [msg, setMsg] = useState<{ ok: boolean; t: string } | null>(null);
  const [trabajando, setTrabajando] = useState(false);
  useEffect(() => {
    let vivo = true;
    apiGestion.valoracion().then((r) => { if (vivo) setD(r); })
      .catch((e) => { if (vivo) setError(e instanceof ErrorTec && e.tipo === "permiso" ? "Solo el administrador ve el inventario regulatorio." : e instanceof Error ? e.message : "No se pudo cargar."); });
    return () => { vivo = false; };
  }, []);
  const hojas = useMemo(() => [...(d?.hojas ?? [])].sort((a, b) => Number(b.vigente) - Number(a.vigente) || a.hoja.localeCompare(b.hoja)), [d]);      // primero las que valen
  const deHoja = useMemo(() => (d?.filas ?? []).filter((f) => f.hoja === hoja), [d, hoja]);
  const filas = useMemo(() => deHoja.filter((f) => (filtro === "todas" ? true : filtro === "no_calzan" ? f.comparable && f.calza === false : f.activos === 0)), [deHoja, filtro]);
  const servicio = hoja === "acueducto" ? "acueducto" : "alcantarillado";
  const sinFila = useMemo(() => (d?.sin_fila ?? []).filter((s) => s.sistema === servicio), [d, servicio]);

  if (error) return <section className="tec-tarjeta" role="alert"><p>{error}</p></section>;
  if (!d) return <p className="tec-sub dan-pad" role="status">Cargando…</p>;
  if (!d.cargada) {
    return (
      <section className="tec-tarjeta" aria-label="Inventario regulatorio">
        <h2>Inventario regulatorio</h2>
        <p className="red-vacio">Todavía no se ha cargado la valoración técnica de 2019. Se carga una sola vez, con el paquete de carga del Corte 10.</p>
      </section>);
  }
  const h = hojas.find((x) => x.hoja === hoja);
  const comp = deHoja.filter((f) => f.comparable);
  const tub = deHoja.filter((f) => f.clase === "tuberia");
  const nombreHoja = (x: HojaValoracion) => `${x.nombre.charAt(0)}${x.nombre.slice(1).toLowerCase()}`;

  async function descargar() {
    if (!d || !d.filas) return;
    setTrabajando(true); setMsg(null);
    try {
      const nom = new Map(hojas.map((x) => [x.hoja, x] as const));
      const cols: [string, number][] = [["Sección", 22], ["Hoja", 20], ["Vale", 8], ["N.º", 6], ["Activo de la valoración", 36], ["Clase", 12], ["Característica", 18], ["Unidad", 8],
        ["Cantidad en la valoración", 16], ["Cantidad en la red", 16], ["De ella, marcada aparte", 16], ["Diferencia (red − valoración)", 16], ["Red / valoración (%)", 12], ["Calza", 8],
        ["Activos amarrados", 12], ["Códigos", 26], ["Año de entrada en operación", 12], ["Vida útil (años)", 10], ["Valor total", 18], ["Valor remanente", 18], ["Depreciación anual", 18], ["Nota", 60]];
      const n = (v: number | undefined): Celda => (v === undefined ? null : v);
      const cuerpo: Celda[][] = d.filas.map((f) => ["Filas de la valoración", nom.get(f.hoja)?.nombre ?? f.hoja, nom.get(f.hoja)?.vigente ? "Sí" : "No", f.n, f.nombre, CLASE[f.clase] ?? f.clase, caracteristica(f),
        f.unidad ?? null, n(f.cantidad), n(f.red), n(f.aparte), n(f.diferencia), n(f.pct), f.calza === undefined ? null : f.calza ? "Sí" : "No", f.activos, f.codigos ?? null, n(f.anio_operacion),
        n(f.vida_util), n(f.valor_total), n(f.valor_remanente), n(f.depreciacion_anual), f.nota ?? null]);
      for (const s of d.sin_fila ?? []) {
        cuerpo.push(["Activos sin fila", s.sistema === "acueducto" ? "Acueducto" : "Alcantarillado", null, null, s.tipo, s.prefijo, [s.material, s.diametro_mm ? `${nf.format(s.diametro_mm)} mm` : null].filter(Boolean).join(" · ") || null,
          s.longitud_m !== undefined ? "m" : null, null, n(s.longitud_m), null, null, null, null, s.activos, null, null, null, null, null, null, MOTIVO[s.motivo]]);
      }
      const { LibroXlsx } = await import("./xlsx");
      const libro = new LibroXlsx({ hoja: "Conciliación", encabezados: cols.map((c) => c[0]), anchos: cols.map((c) => c[1]),
        leame: [["Qué es", "Conciliación del inventario regulatorio con la red del geoportal (Técnica, distribución)."],
          ["Fuente", `${d.fuente ?? ""}. Es una propuesta de 2019: su adopción no está confirmada.`],
          ["Archivo de la valoración", `${d.valoracion?.archivo ?? ""} (md5 ${d.valoracion?.md5 ?? ""}), cargado el ${d.valoracion ? fecha(d.valoracion.cargada_en) : ""}`],
          ["Amarre", d.amarre ? `${d.amarre.archivo} (md5 ${d.amarre.md5}), cargado el ${fecha(d.amarre.cargado_en)}. Tramos y conductos por material y diámetro; puntuales uno a uno.` : "Sin amarre vigente"],
          ["Hoja de alcantarillado que vale", `${nom.get(d.hoja_alcantarillado)?.nombre ?? d.hoja_alcantarillado}. La otra va como referencia (columna «Vale»).`],
          ["Totales por hoja", hojas.map((x) => `${x.nombre}: ${x.filas} filas, BCR0 ${millones(x.bcr0)}`).join(" · ")],
          ["Cantidad en la red", "Suma de los activos vigentes amarrados a la fila (metros de tubería o unidades), sin los retirados ni los ocultos. «Marcada aparte»: fuera de servicio u obra de un tercero en el modelo."],
          ["Calza", `La diferencia no pasa del ${nf.format(d.tolerancia_pct)} % de la cantidad de la valoración. Plantas, tanques y terrenos no se comparan por cantidad.`],
          ["Activos sin fila", "Agrupados por tipo, material y diámetro. «Fuera de la valoración 2019»: activos creados después del amarre (por ejemplo, de una inversión)."],
          ["Valores", "El valor y la depreciación son de toda la fila (activos agregados): no se reparten por tramo. Sin datos de personas."],
          ["Generado", `${d.generado_en ? fecha(d.generado_en) : ""} por ${d.generado_por ?? ""}`]] });
      await libro.agregarFilas(cuerpo);
      const blob = await libro.finalizar();
      const url = URL.createObjectURL(blob); const a = document.createElement("a");
      a.href = url; a.download = `inventario_regulatorio_conciliacion_${(d.generado_en ?? "").slice(0, 10)}.xlsx`; document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 30_000);
      setMsg({ ok: true, t: `Listo: ${nf0.format(cuerpo.length)} filas (las tres hojas y los activos sin fila).` });
    } catch (e) { setMsg({ ok: false, t: e instanceof Error ? e.message : "No se pudo generar el Excel." }); } finally { setTrabajando(false); }
  }

  return (
    <>
      <section className="tec-tarjeta" aria-label="Inventario regulatorio" data-testid="reg-resumen">
        <h2>Inventario regulatorio</h2>
        <p className="red-ref-adv" role="note">{d.fuente}: su adopción no está confirmada. Es un dato de referencia y no cambia la ficha de ningún activo.</p>
        <p className="tec-ayuda">Archivo «{d.valoracion?.archivo}» (cargado el {d.valoracion ? fecha(d.valoracion.cargada_en) : ""}). Activos agregados: cada tubería es una fila por material y diámetro, con su longitud total.</p>
        <div className="gest-tabla-caja">
          <table className="gest-tabla">
            <thead><tr><th>Hoja</th><th className="reg-num">Filas</th><th className="reg-num">Valor total</th><th className="reg-num">BCR0 (valor remanente)</th><th className="reg-num">Depreciación anual</th><th>Vale</th></tr></thead>
            <tbody>{hojas.map((x) => (
              <tr key={x.hoja}><td>{nombreHoja(x)}</td><td className="reg-num">{x.filas}</td><td className="reg-num">{millones(x.valor_total)}</td><td className="reg-num">{millones(x.bcr0)}</td>
                <td className="reg-num">{millones(x.depreciacion_anual)}</td><td>{x.vigente ? "Sí" : "Referencia"}</td></tr>))}</tbody>
          </table>
        </div>
        <p className="tec-ayuda">La hoja de alcantarillado que vale se cambia en la pestaña Parámetros («valoracion_hoja_alcantarillado»: 1 o 2), con motivo. No hay que cargar nada de nuevo.</p>
      </section>

      <section className="tec-tarjeta" aria-label="Conciliación con la red" data-testid="reg-conciliacion">
        <h2>Conciliación con la red</h2>
        <div className="dan-fila" role="group" aria-label="Hoja de la valoración">
          {hojas.map((x) => <button key={x.hoja} type="button" className="dan-opcion" aria-pressed={hoja === x.hoja} onClick={() => setHoja(x.hoja)}>{nombreHoja(x)}{x.vigente ? "" : " (referencia)"}</button>)}
        </div>
        <div className="dan-fila" role="group" aria-label="Qué filas ver">
          <button type="button" className="dan-opcion" aria-pressed={filtro === "todas"} onClick={() => setFiltro("todas")}>Todas ({deHoja.length})</button>
          <button type="button" className="dan-opcion" aria-pressed={filtro === "no_calzan"} onClick={() => setFiltro("no_calzan")}>No calzan ({comp.filter((f) => f.calza === false).length})</button>
          <button type="button" className="dan-opcion" aria-pressed={filtro === "sin_activos"} onClick={() => setFiltro("sin_activos")}>Sin activos ({deHoja.filter((f) => f.activos === 0).length})</button>
        </div>
        <p className="tec-ayuda" data-testid="reg-cuenta">{h ? `${nombreHoja(h)}: ` : ""}{tub.filter((f) => f.calza).length} de {tub.length} filas de tubería calzan con la red (diferencia de {nf.format(d.tolerancia_pct)} % o menos).
          La red son los activos vigentes amarrados a cada fila por material y diámetro.</p>
        {filas.length === 0 ? <p className="red-vacio">Ninguna fila con ese filtro.</p> : (
          <div className="gest-tabla-caja">
            <table className="gest-tabla reg-tabla">
              <thead><tr><th className="reg-num">N.º</th><th>Activo de la valoración</th><th className="reg-num">Valoración</th><th className="reg-num">Red</th><th className="reg-num">Diferencia</th><th className="reg-num">Red / valoración</th>
                <th className="reg-num">Activos</th><th>Calza</th><th className="reg-num">Año</th><th className="reg-num">Valor total</th></tr></thead>
              <tbody>{filas.map((f) => (
                <tr key={f.n}>
                  <td className="reg-num">{f.n}</td>
                  <td>{f.nombre}{caracteristica(f) ? ` · ${caracteristica(f)}` : ""}{f.nota ? <span className="reg-nota">{f.nota}</span> : null}</td>
                  <td className="reg-num">{cantidad(f.cantidad, f.unidad)}</td>
                  <td className="reg-num">{f.comparable ? cantidad(f.red, f.unidad) : f.codigos
                    ? f.codigos.split(", ").map((c) => <button key={c} type="button" className="tec-enlace" onClick={() => onFicha(c)}>{c}</button>) : "Sin activo"}
                    {f.comparable && f.aparte ? <span className="reg-nota">{nf.format(f.aparte)} marcados aparte</span> : null}</td>
                  <td className="reg-num">{f.diferencia === undefined ? "—" : `${f.diferencia > 0 ? "+" : ""}${nf.format(f.diferencia)}`}</td>
                  <td className="reg-num">{f.pct === undefined ? "—" : `${nf.format(f.pct)} %`}</td>
                  <td className="reg-num">{nf0.format(f.activos)}</td>
                  <td>{f.calza === undefined ? "—" : f.calza ? "Sí" : "No"}</td>
                  <td className="reg-num">{f.anio_operacion ?? "—"}</td>
                  <td className="reg-num">{f.valor_total === undefined ? "—" : millones(f.valor_total)}</td>
                </tr>))}</tbody>
            </table>
          </div>)}
        <div className="tec-acciones">
          <button type="button" className="tec-boton itv-guardar" disabled={trabajando} onClick={descargar}>{trabajando ? "Generando…" : "Descargar Excel"}</button>
        </div>
        {msg ? <p className={`tec-aviso ${msg.ok ? "tec-aviso-info" : "tec-aviso-error"}`} role={msg.ok ? "status" : "alert"}>{msg.t}</p> : null}
      </section>

      <section className="tec-tarjeta" aria-label="Activos sin fila" data-testid="reg-sin-fila">
        <h2>Activos sin fila ({servicio})</h2>
        <p className="tec-ayuda">Activos vigentes de los tipos que la valoración cubre y que no tienen fila en la hoja que vale: no se remuneran vía tarifa. Agrupados por tipo, material y diámetro.</p>
        {sinFila.length === 0 ? <p className="red-vacio">Todos los activos tienen fila.</p> : (
          <div className="gest-tabla-caja">
            <table className="gest-tabla">
              <thead><tr><th>Tipo</th><th>Material</th><th className="reg-num">Diámetro</th><th>Motivo</th><th className="reg-num">Activos</th><th className="reg-num">Longitud</th></tr></thead>
              <tbody>{sinFila.map((s, i) => (
                <tr key={i}><td>{s.tipo}</td><td>{s.material ?? "Sin dato"}</td><td className="reg-num">{s.diametro_mm ? `${nf.format(s.diametro_mm)} mm` : "—"}</td><td>{MOTIVO[s.motivo]}</td>
                  <td className="reg-num">{nf0.format(s.activos)}</td><td className="reg-num">{s.longitud_m !== undefined && s.prefijo !== "TOR" && s.prefijo !== "VAL" && s.prefijo !== "TAN" ? `${nf.format(s.longitud_m)} m` : "—"}</td></tr>))}</tbody>
            </table>
          </div>)}
      </section>
    </>
  );
}
