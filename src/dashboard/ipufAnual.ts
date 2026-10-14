import type { Ipuf } from "./tipos";

// IPUF por AÑO TARIFARIO (Res. CRA 688): de julio a junio. Se deriva del
// período (AAAAMM), NO de la columna ano_tarifario del origen: desde julio de
// 2026 esa columna trae una etiqueta distinta por mes ('PI - 1032', ...), no
// un año.
//
// Agregación (consistente con las gráficas mensuales y con ipuf_anio_corrido,
// que el origen entrega con este mismo cálculo al cierre de cada año):
//   IPUF anual = Σ pérdida ÷ Σ suscriptores
//              = (agua producida − agua facturada) ÷ (suscriptores promedio × meses)
//   ICUF anual = Σ agua facturada ÷ Σ suscriptores
//   ISUF anual = Σ agua producida ÷ Σ suscriptores        → ISUF − ICUF = IPUF
//   IANC anual = (Σ producida − Σ facturada) ÷ Σ producida (en %, ya ×100)
// Un año con menos de 12 meses es PARCIAL y usa n = sus meses en el divisor.

// El año tarifario 2016-17 solo tiene ene-jun 2017 (6 meses): no se muestra.
export const PRIMER_ANIO_TARIFARIO = 2017;

export function anioTarifarioDe(periodo: string): { inicio: number; etiqueta: string } {
  const a = Number(periodo.slice(0, 4));
  const m = Number(periodo.slice(4));
  const inicio = m >= 7 ? a : a - 1;
  return { inicio, etiqueta: `${inicio}-${String((inicio + 1) % 100).padStart(2, "0")}` };
}

// Exceso REAL sobre la meta de un mes: máx(0, IPUF − meta) × suscriptores (m³)
// y su valor en pesos con la tarifa por m³ de la fuente. La columna
// perdidas_superiores_meta del origen NO sirve para esto: vale meta × suscriptores
// (el volumen que la meta permite), no el exceso.
export function excesoSobreMeta(f: Ipuf): { m3: number; pesos: number | null } | null {
  if (f.ipuf == null || f.meta_ipuf == null || f.suscriptores == null) return null;
  const m3 = Math.max(0, f.ipuf - f.meta_ipuf) * f.suscriptores;
  return { m3, pesos: f.tarifa_m3 != null ? m3 * f.tarifa_m3 : null };
}

export type CambioMeta = { de: number; a: number; periodo: string };

export type IpufAnual = {
  inicio: number;          // año en que empieza (julio): 2017 → '2017-18'
  etiqueta: string;
  meses: number;
  parcial: boolean;        // menos de 12 meses
  desde: string;
  hasta: string;
  ipuf: number | null;
  meta: number | null;     // ponderada por suscriptores
  cambioMeta: CambioMeta | null;   // si la meta cambió dentro del año
  difMeta: number | null;  // ipuf − meta
  estandar: number | null;
  icuf: number | null;
  isuf: number | null;
  ianc: number | null;     // en %
  pesosTotal: number | null;       // A: Σ mensual de perdida_total_pesos
  pesosSobreMeta: number | null;   // B: Σ mensual de máx(0, IPUF − meta) × susc × tarifa
};

const suma = (xs: number[]) => xs.reduce((s, x) => s + x, 0);

export function resumenAnual(filas: Ipuf[]): IpufAnual[] {
  const porAnio = new Map<number, Ipuf[]>();
  for (const f of [...filas].sort((a, b) => a.periodo.localeCompare(b.periodo))) {
    const { inicio } = anioTarifarioDe(f.periodo);
    if (inicio < PRIMER_ANIO_TARIFARIO) continue;
    if (!porAnio.has(inicio)) porAnio.set(inicio, []);
    porAnio.get(inicio)!.push(f);
  }

  return [...porAnio.entries()].map(([inicio, ms]) => {
    // Meses con los cuatro datos base completos (producida, facturada, pérdida, suscriptores).
    const ok = ms.filter(
      (f) => f.perdida_total_m3 != null && f.suscriptores != null && f.agua_potable != null && f.agua_facturada != null,
    );
    const ss = suma(ok.map((f) => f.suscriptores!));
    const per = suma(ok.map((f) => f.perdida_total_m3!));
    const pot = suma(ok.map((f) => f.agua_potable!));
    const fac = suma(ok.map((f) => f.agua_facturada!));

    const conMeta = ms.filter((f) => f.meta_ipuf != null && f.suscriptores != null);
    const ssMeta = suma(conMeta.map((f) => f.suscriptores!));
    const conEst = ms.filter((f) => f.ipuf_estandar != null && f.suscriptores != null);
    const ssEst = suma(conEst.map((f) => f.suscriptores!));

    let cambioMeta: CambioMeta | null = null;
    const metas = ms.filter((f) => f.meta_ipuf != null);
    for (let i = 1; i < metas.length; i++) {
      if (Math.abs(metas[i].meta_ipuf! - metas[i - 1].meta_ipuf!) > 1e-6) {
        cambioMeta = { de: metas[i - 1].meta_ipuf!, a: metas[i].meta_ipuf!, periodo: metas[i].periodo };
        break;
      }
    }

    const ipuf = ss > 0 ? per / ss : null;
    const meta = ssMeta > 0 ? suma(conMeta.map((f) => f.meta_ipuf! * f.suscriptores!)) / ssMeta : null;
    const pesos = ms.map((f) => f.perdida_total_pesos).filter((x): x is number => x != null);
    const excesos = ms.map((f) => excesoSobreMeta(f)?.pesos).filter((x): x is number => x != null);
    return {
      inicio,
      etiqueta: anioTarifarioDe(ms[0].periodo).etiqueta,
      meses: ms.length,
      parcial: ms.length < 12,
      desde: ms[0].periodo,
      hasta: ms[ms.length - 1].periodo,
      ipuf,
      meta,
      cambioMeta,
      difMeta: ipuf != null && meta != null ? ipuf - meta : null,
      estandar: ssEst > 0 ? suma(conEst.map((f) => f.ipuf_estandar! * f.suscriptores!)) / ssEst : null,
      icuf: ss > 0 ? fac / ss : null,
      isuf: ss > 0 ? pot / ss : null,
      ianc: pot > 0 ? ((pot - fac) / pot) * 100 : null,
      pesosTotal: pesos.length ? suma(pesos) : null,
      pesosSobreMeta: excesos.length ? suma(excesos) : null,
    };
  });
}
