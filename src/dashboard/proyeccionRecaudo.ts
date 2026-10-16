// Utilidades de la pantalla «Proyección y cumplimiento» (RECAUDO DIARIO). Lógica pura, sin React: tipos y convertidores de
// las vistas v_proy_* (sql/43), semáforo, resumen del mes en curso y armado de la tabla en formato FO-GF-33.
// Todo está en base SIN terceros salvo donde dice «con terceros». Los subsidios NO entran en ninguna cifra de recaudo.

const num = (v: unknown): number | null => {
  if (v == null || v === "") return null;
  const x = typeof v === "number" ? v : Number(v);
  return Number.isFinite(x) ? x : null;
};
const txt = (v: unknown) => String(v ?? "");

// ---------- tipos ----------
export type CumplimientoDia = {
  periodo: string; dia: number; fecha: string; tipo_dia: string; tramo: string; ult_dia: number | null;
  real_dia: number | null; real_acum: number | null;
  meta_certificada_dia: number | null; meta_propia_dia: number | null;
  meta_certificada_acum: number | null; meta_propia_acum: number | null;
  cumplimiento_certificada_pct: number | null; cumplimiento_propia_pct: number | null;
  falta_certificada_mes: number | null; falta_propia_mes: number | null;
  exigencia_dia_certificada: number | null; exigencia_dia_propia: number | null;
  cierre_corregido_con_avance: number | null;
};
export const comoCumplimientoDia = (r: Record<string, unknown>): CumplimientoDia => ({
  periodo: txt(r.periodo), dia: num(r.dia) ?? 0, fecha: txt(r.fecha), tipo_dia: txt(r.tipo_dia), tramo: txt(r.tramo), ult_dia: num(r.ult_dia),
  real_dia: num(r.real_dia), real_acum: num(r.real_acum),
  meta_certificada_dia: num(r.meta_certificada_dia), meta_propia_dia: num(r.meta_propia_dia),
  meta_certificada_acum: num(r.meta_certificada_acum), meta_propia_acum: num(r.meta_propia_acum),
  cumplimiento_certificada_pct: num(r.cumplimiento_certificada_pct), cumplimiento_propia_pct: num(r.cumplimiento_propia_pct),
  falta_certificada_mes: num(r.falta_certificada_mes), falta_propia_mes: num(r.falta_propia_mes),
  exigencia_dia_certificada: num(r.exigencia_dia_certificada), exigencia_dia_propia: num(r.exigencia_dia_propia),
  cierre_corregido_con_avance: num(r.cierre_corregido_con_avance),
});

export type AnualMes = {
  periodo: string; tipo: string; propia: number | null; corregida: number | null; certificada: number | null; conTerceros: number | null;
  acumPropia: number | null; acumCorregida: number | null; acumCertificada: number | null;
};
export const comoAnualMes = (r: Record<string, unknown>): AnualMes => ({
  periodo: txt(r.periodo), tipo: txt(r.tipo), propia: num(r.propia_sin_terceros), corregida: num(r.propia_corregida_sin_terceros),
  certificada: num(r.certificada_sin_terceros), conTerceros: num(r.propia_con_terceros),
  acumPropia: num(r.acum_propia), acumCorregida: num(r.acum_propia_corregida), acumCertificada: num(r.acum_certificada),
});

export type TotalMes = {
  periodo: string; tipo: string; servicios: number | null; otros: number | null; sinTerceros: number | null; conTerceros: number | null;
  acumSinTerceros: number | null; acumConTerceros: number | null;
};
export const comoTotalMes = (r: Record<string, unknown>): TotalMes => ({
  periodo: txt(r.periodo), tipo: txt(r.tipo), servicios: num(r.servicios), otros: num(r.otros), sinTerceros: num(r.sin_terceros),
  conTerceros: num(r.con_terceros), acumSinTerceros: num(r.acum_sin_terceros), acumConTerceros: num(r.acum_con_terceros),
});

export type RecaudoRuta = { periodo: string; tipo: string; ruta: string; grupo: string; recaudo: number | null };
export const comoRecaudoRuta = (r: Record<string, unknown>): RecaudoRuta => ({
  periodo: txt(r.periodo), tipo: txt(r.tipo), ruta: txt(r.ruta), grupo: txt(r.grupo), recaudo: num(r.recaudo),
});

export type SubsidioMes = { periodo: string; deficitAbs: number | null };
export const comoSubsidioMes = (r: Record<string, unknown>): SubsidioMes => ({ periodo: txt(r.periodo), deficitAbs: num(r.deficit_abs) });

export type DiaOrigen = { periodo: string; origen: string; dia: number | null };
export const comoDiaOrigen = (r: Record<string, unknown>): DiaOrigen => ({ periodo: txt(r.periodo), origen: txt(r.origen), dia: num(r.dia) });

// ---------- formato ----------
// Millones con un decimal y el signo $ ($ 2.007,6 M). El valor exacto va en el tooltip (fmtExacto).
export function fm1(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(v)) return "—";
  return `$ ${(v / 1e6).toLocaleString("es-CO", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} M`;
}
// Millones sin el signo (para las celdas de la tabla FO-GF-33).
export function mm1(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(v)) return "—";
  return (v / 1e6).toLocaleString("es-CO", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
}
export function fmtExacto(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(v)) return "";
  return `$ ${Math.round(v).toLocaleString("es-CO")}`;
}
export function fmtPct1(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(v)) return "—";
  return `${v.toLocaleString("es-CO", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} %`;
}
export const diferencia = (a: number | null, b: number | null) => (a == null || b == null ? null : a - b);
export const divSegura = (a: number | null, b: number | null) => (a == null || b == null || b === 0 ? null : a / b);

// Semáforo suave del cumplimiento: ≥100 verde, 90–99,9 ámbar, <90 rojo.
export type Semaforo = "verde" | "ambar" | "rojo";
export function semaforo(pct: number | null): Semaforo | null {
  if (pct == null || !Number.isFinite(pct)) return null;
  return pct >= 100 ? "verde" : pct >= 90 ? "ambar" : "rojo";
}

// ---------- mes en curso ----------
export const MESES_CORTO = ["Ene", "Feb", "Mar", "Abr", "May", "Jun", "Jul", "Ago", "Sep", "Oct", "Nov", "Dic"];
export const mesCorto = (periodo: string) => MESES_CORTO[Number(periodo.slice(4)) - 1] ?? periodo;
export const diasDelMes = (periodo: string) => new Date(Number(periodo.slice(0, 4)), Number(periodo.slice(4)), 0).getDate();

// El mes en curso es el que el cargue diario marca con origen «curso». Si no hay, el último período de v_proy_cumplimiento
// cuyo último día cargado es menor que los días del mes.
export function periodoEnCurso(cum: CumplimientoDia[], diario: DiaOrigen[]): { periodo: string | null; origen: string | null } {
  const curso = diario.filter((d) => d.origen === "curso").map((d) => d.periodo).sort();
  if (curso.length) return { periodo: curso[curso.length - 1], origen: "curso" };
  const abiertos = [...new Set(cum.filter((c) => c.ult_dia != null && c.ult_dia < diasDelMes(c.periodo)).map((c) => c.periodo))].sort();
  return abiertos.length ? { periodo: abiertos[abiertos.length - 1], origen: null } : { periodo: null, origen: null };
}

export type ResumenMes = {
  periodo: string; ultDia: number; diasMes: number;
  realAcum: number | null; metaCertAcum: number | null; metaPropiaAcum: number | null;
  cumplCert: number | null; cumplPropia: number | null;
  faltaCert: number | null; faltaPropia: number | null;
  metaCertMes: number | null; metaPropiaMes: number | null;
  cierre: number | null; difCierreCert: number | null; difCierrePropia: number | null;
  restantes: CumplimientoDia[]; totalExigCert: number | null; totalExigPropia: number | null; promExigCert: number | null; promExigPropia: number | null;
};

const suma = (xs: (number | null)[]) => {
  const v = xs.filter((x): x is number => x != null);
  return v.length ? v.reduce((a, b) => a + b, 0) : null;
};

export function resumenMes(cum: CumplimientoDia[], periodo: string): ResumenMes | null {
  const dias = cum.filter((c) => c.periodo === periodo).sort((a, b) => a.dia - b.dia);
  if (!dias.length) return null;
  const ultDia = dias[0].ult_dia;
  if (ultDia == null) return null;
  const hoy = dias.find((d) => d.dia === ultDia) ?? null;
  const ultimo = dias[dias.length - 1];
  const restantes = dias.filter((d) => d.dia > ultDia);
  const exC = restantes.map((r) => r.exigencia_dia_certificada), exP = restantes.map((r) => r.exigencia_dia_propia);
  const cierre = hoy?.cierre_corregido_con_avance ?? null;
  const metaCertMes = ultimo.meta_certificada_acum, metaPropiaMes = ultimo.meta_propia_acum;
  return {
    periodo, ultDia, diasMes: dias.length,
    realAcum: hoy?.real_acum ?? null, metaCertAcum: hoy?.meta_certificada_acum ?? null, metaPropiaAcum: hoy?.meta_propia_acum ?? null,
    cumplCert: hoy?.cumplimiento_certificada_pct ?? null, cumplPropia: hoy?.cumplimiento_propia_pct ?? null,
    faltaCert: hoy?.falta_certificada_mes ?? null, faltaPropia: hoy?.falta_propia_mes ?? null,
    metaCertMes, metaPropiaMes, cierre,
    difCierreCert: diferencia(cierre, metaCertMes), difCierrePropia: diferencia(cierre, metaPropiaMes),
    restantes, totalExigCert: suma(exC), totalExigPropia: suma(exP),
    promExigCert: restantes.length && suma(exC) != null ? (suma(exC) as number) / exC.filter((x) => x != null).length : null,
    promExigPropia: restantes.length && suma(exP) != null ? (suma(exP) as number) / exP.filter((x) => x != null).length : null,
  };
}

export type MarcaDia = { texto: string; clase: "festivo" | "finde" | "" };
export function marcaDia(tipo: string): MarcaDia {
  const t = tipo.toLowerCase();
  if (t === "festivo") return { texto: "Festivo", clase: "festivo" };
  if (t === "sabado" || t === "sábado") return { texto: "Sábado", clase: "finde" };
  if (t === "domingo") return { texto: "Domingo", clase: "finde" };
  return { texto: t ? t.charAt(0).toUpperCase() + t.slice(1).replace("miercoles", "miércoles") : "—", clase: "" };
}

// ---------- tabla FO-GF-33 ----------
// Orden y rótulos de las rutas. Una ruta nueva que no esté aquí se agrega al final de su grupo con su propio nombre, para que los
// subtotales siempre cuadren con v_proy_recaudo_total.
export const RUTAS_SERVICIOS: [string, string][] = [
  ["ACUEDUCTO - CARGO FIJO", "Acueducto cargo fijo"],
  ["ACUEDUCTO - BASICO", "Acueducto básico"],
  ["ALCANTARILLADO - CARGO FIJO", "Alcantarillado cargo fijo"],
  ["ALCANTARILLADO - BASICO", "Alcantarillado básico"],
  ["PLUVIAL", "Pluvial"],
  ["ACUEDUCTO - RECARGO POR MORA", "Recargo por mora"],
];
export const RUTAS_OTROS: [string, string][] = [
  ["ACUEDUCTO - OTROS INGRESOS (SOBRANTES VENTAS DE PLIEGOS, MULTAS Y OTROS)", "Acueducto otros ingresos"],
  ["ALCANTARILLADO - OTROS INGRESOS (SOBRANTES VENTAS DE PLIEGOS, MULTAS Y OTROS)", "Alcantarillado otros ingresos"],
];

export type FilaFO = { clave: string; etiqueta: string; tipo: "ruta" | "subtotal" | "total" | "acum" | "meta"; valores: (number | null)[]; total: number | null };
export type TablaFO = { anio: string; periodos: string[]; estado: ("real" | "proyectado")[]; filas: FilaFO[] };

export function armarTablaFO(rutas: RecaudoRuta[], metaCertificadaPorMes: Map<string, number>): TablaFO | null {
  if (!rutas.length) return null;
  const anio = [...rutas].map((r) => r.periodo.slice(0, 4)).sort()[0];
  const periodos = Array.from({ length: 12 }, (_, i) => `${anio}${String(i + 1).padStart(2, "0")}`);
  const estado = periodos.map((p) => (rutas.some((r) => r.periodo === p && r.tipo === "real") ? "real" : "proyectado") as "real" | "proyectado");
  const val = (ruta: string, p: string) => {
    const fs = rutas.filter((r) => r.ruta === ruta && r.periodo === p);
    return fs.length ? suma(fs.map((f) => f.recaudo)) : null;
  };
  const conocidas = new Set([...RUTAS_SERVICIOS, ...RUTAS_OTROS].map(([k]) => k));
  const extra = (g: string) => [...new Set(rutas.filter((r) => r.grupo === g && !conocidas.has(r.ruta)).map((r) => r.ruta))].sort().map((k) => [k, k] as [string, string]);
  const tot = (xs: (number | null)[]) => suma(xs);
  const filaRuta = ([k, e]: [string, string]): FilaFO => {
    const v = periodos.map((p) => val(k, p));
    return { clave: k, etiqueta: e, tipo: "ruta", valores: v, total: tot(v) };
  };
  const filas: FilaFO[] = [];
  const serv = [...RUTAS_SERVICIOS, ...extra("servicio")].map(filaRuta);
  const otros = [...RUTAS_OTROS, ...extra("otros")].map(filaRuta);
  const terc = extra("tercero").length ? extra("tercero") : [["TERCERO", "Tercero"] as [string, string]];
  const tercero = terc.map(filaRuta);
  const colSum = (fs: FilaFO[]) => periodos.map((_, i) => suma(fs.map((f) => f.valores[i])));
  const sumServ = colSum(serv), sumOtros = colSum(otros), sumTerc = colSum(tercero);
  const sinTerc = periodos.map((_, i) => suma([sumServ[i], sumOtros[i]]));
  const conTerc = periodos.map((_, i) => suma([sinTerc[i], sumTerc[i]]));
  const acum = (v: (number | null)[]) => { let a = 0; return v.map((x) => (x == null ? null : (a += x))); };
  filas.push(...serv);
  filas.push({ clave: "sum_serv", etiqueta: "Suma servicios", tipo: "subtotal", valores: sumServ, total: tot(sumServ) });
  filas.push(...otros);
  filas.push({ clave: "sum_otros", etiqueta: "Suma otros ingresos", tipo: "subtotal", valores: sumOtros, total: tot(sumOtros) });
  filas.push({ clave: "sin_terceros", etiqueta: "Recaudo sin terceros", tipo: "total", valores: sinTerc, total: tot(sinTerc) });
  filas.push(...tercero);
  filas.push({ clave: "con_terceros", etiqueta: "Recaudo con terceros", tipo: "total", valores: conTerc, total: tot(conTerc) });
  const aSin = acum(sinTerc), aCon = acum(conTerc);
  filas.push({ clave: "acum_sin", etiqueta: "Acumulado sin terceros", tipo: "acum", valores: aSin, total: aSin[aSin.length - 1] ?? null });
  filas.push({ clave: "acum_con", etiqueta: "Acumulado con terceros", tipo: "acum", valores: aCon, total: aCon[aCon.length - 1] ?? null });
  const meta = periodos.map((p) => metaCertificadaPorMes.get(p) ?? null);
  filas.push({ clave: "meta", etiqueta: "Meta certificada FO-GF-33 (sin terceros)", tipo: "meta", valores: meta, total: null });
  return { anio, periodos, estado, filas };
}

// Meta certificada del mes: la meta acumulada del último día de cada mes de v_proy_cumplimiento (septiembre) y, para los meses
// proyectados sin ese dato, certificada_sin_terceros de v_proy_anual (octubre a diciembre). Sin dato en ninguna: no hay meta.
export function metaCertificadaPorMes(cum: CumplimientoDia[], anual: AnualMes[] = []): Map<string, number> {
  const m = new Map<string, CumplimientoDia>();
  for (const c of cum) { const a = m.get(c.periodo); if (!a || c.dia > a.dia) m.set(c.periodo, c); }
  const out = new Map<string, number>();
  for (const [p, c] of m) if (c.meta_certificada_acum != null) out.set(p, c.meta_certificada_acum);
  for (const a of anual) if (a.tipo === "proyectado" && a.certificada != null && !out.has(a.periodo)) out.set(a.periodo, a.certificada);
  return out;
}

// ---------- subsidios (informativo) ----------
export type FilaSubsidio = { periodo: string; recaudoConTerceros: number | null; deficit: number | null; ingresosTotales: number | null };
export function armarSubsidios(totales: TotalMes[], subs: SubsidioMes[]): FilaSubsidio[] {
  const s = new Map(subs.map((x) => [x.periodo, x.deficitAbs]));
  return totales
    .filter((t) => t.tipo === "real" && s.get(t.periodo) != null)
    .sort((a, b) => a.periodo.localeCompare(b.periodo))
    .map((t) => {
      const d = s.get(t.periodo) ?? null;
      return { periodo: t.periodo, recaudoConTerceros: t.conTerceros, deficit: d, ingresosTotales: t.conTerceros != null && d != null ? t.conTerceros + d : null };
    });
}
