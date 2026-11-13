// Lector mínimo de .xlsx para el plan operativo (PURO: solo zip + XML, sin librerías). Un .xlsx es un zip: se lee el directorio central y se descomprimen con DecompressionStream («deflate-raw») las
// partes necesarias (libro, relaciones, textos compartidos y hojas). Devuelve las celdas como texto o número; las horas de Excel (fracción del día) las convierte planDesdeLibro.
export type Hoja = { nombre: string; filas: (string | number | null)[][] };

async function inflar(datos: Uint8Array): Promise<Uint8Array> {
  const flujo = new Blob([datos as BlobPart]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  return new Uint8Array(await new Response(flujo).arrayBuffer());
}
const u16 = (d: DataView, o: number) => d.getUint16(o, true), u32 = (d: DataView, o: number) => d.getUint32(o, true);

async function leerZip(buf: ArrayBuffer): Promise<Map<string, () => Promise<Uint8Array>>> {
  const d = new DataView(buf), b = new Uint8Array(buf);
  let eocd = -1;
  for (let i = b.length - 22; i >= Math.max(0, b.length - 65557); i--) if (u32(d, i) === 0x06054b50) { eocd = i; break; }
  if (eocd < 0) throw new Error("El archivo no es un .xlsx válido (no se encontró el directorio del zip).");
  const n = u16(d, eocd + 10); let p = u32(d, eocd + 16);
  const partes = new Map<string, () => Promise<Uint8Array>>();
  for (let k = 0; k < n; k++) {
    if (u32(d, p) !== 0x02014b50) throw new Error("El zip del .xlsx está dañado.");
    const metodo = u16(d, p + 10), csize = u32(d, p + 20), nlen = u16(d, p + 28), elen = u16(d, p + 30), clen = u16(d, p + 32), local = u32(d, p + 42);
    const nombre = new TextDecoder().decode(b.subarray(p + 46, p + 46 + nlen));
    partes.set(nombre, async () => {
      const lnlen = u16(d, local + 26), lelen = u16(d, local + 28), ini = local + 30 + lnlen + lelen;
      const crudo = b.subarray(ini, ini + csize);
      if (metodo === 0) return crudo;
      if (metodo === 8) return inflar(crudo);
      throw new Error("El .xlsx usa una compresión no soportada.");
    });
    p += 46 + nlen + elen + clen;
  }
  return partes;
}

const texto = async (partes: Map<string, () => Promise<Uint8Array>>, nombre: string): Promise<string | null> => { const f = partes.get(nombre); return f ? new TextDecoder().decode(await f()) : null; };
const des = (s: string) => s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&#10;/g, "\n").replace(/&#13;/g, "").replace(/&amp;/g, "&");
const columnaIdx = (ref: string) => { let n = 0; for (const c of ref.replace(/\d/g, "")) n = n * 26 + c.charCodeAt(0) - 64; return n - 1; };

export async function leerXlsx(buf: ArrayBuffer): Promise<Hoja[]> {
  const z = await leerZip(buf);
  const libro = await texto(z, "xl/workbook.xml"), rels = await texto(z, "xl/_rels/workbook.xml.rels");
  if (!libro || !rels) throw new Error("El archivo no parece un libro de Excel (.xlsx).");
  const compartidas: string[] = [];
  const ss = await texto(z, "xl/sharedStrings.xml");
  if (ss) for (const m of ss.matchAll(/<si>([\s\S]*?)<\/si>/g)) compartidas.push(des([...m[1].matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map((t) => t[1]).join("")));
  const destinos = new Map<string, string>();
  for (const m of rels.matchAll(/<Relationship\b[^>]*>/g)) { const id = m[0].match(/\bId="([^"]+)"/)?.[1], t = m[0].match(/\bTarget="([^"]+)"/)?.[1]; if (id && t) destinos.set(id, t.replace(/^\//, "").startsWith("xl/") ? t.replace(/^\//, "") : "xl/" + t.replace(/^\//, "")); }
  const hojas: Hoja[] = [];
  for (const m of libro.matchAll(/<sheet\b[^>]*>/g)) {
    const nombre = des(m[0].match(/\bname="([^"]*)"/)?.[1] ?? ""), rid = m[0].match(/\br:id="([^"]+)"/)?.[1] ?? "";
    const xml = await texto(z, destinos.get(rid) ?? "");
    if (!xml) continue;
    const filas: (string | number | null)[][] = [];
    for (const fila of xml.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)) {
      const celdas: (string | number | null)[] = [];
      for (const c of fila[1].matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
        const ref = c[1].match(/\br="([A-Z]+\d+)"/)?.[1] ?? "", tipo = c[1].match(/\bt="([^"]+)"/)?.[1] ?? "", cuerpo = c[2] ?? "";
        const v = cuerpo.match(/<v>([\s\S]*?)<\/v>/)?.[1];
        let valor: string | number | null = null;
        if (tipo === "s" && v !== undefined) valor = compartidas[Number(v)] ?? null;
        else if (tipo === "inlineStr") valor = des([...cuerpo.matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map((t) => t[1]).join(""));
        else if (tipo === "str" || tipo === "e") valor = v !== undefined ? des(v) : null;
        else if (v !== undefined && v !== "") valor = Number(v);
        celdas[columnaIdx(ref)] = valor;
      }
      for (let i = 0; i < celdas.length; i++) if (celdas[i] === undefined) celdas[i] = null;
      filas.push(celdas);
    }
    hojas.push({ nombre, filas });
  }
  return hojas;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
// Plan operativo → filas para geoportal_aseo_cargar_plan. Las columnas se reconocen por el ENCABEZADO (sin tildes ni saltos de línea), no por su posición.
// ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
export type FilaPlan = { codigo: string; clase: "ruta" | "punto"; turno: number | null; servicio: string; frecuencia: string | null; hora_inicio: string | null; hora_fin: string | null; sectores: string | null; caracterizacion: string | null; km_ruta: number | null };
const norm = (s: unknown) => String(s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/\s+/g, " ").trim();
const horaTexto = (v: string | number | null): string | null => {
  if (v === null || v === "") return null;
  if (typeof v === "number") { const m = Math.round(v * 1440) % 1440; return `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`; }
  const t = String(v).match(/^(\d{1,2}):(\d{2})/); return t ? `${t[1].padStart(2, "0")}:${t[2]}` : null;
};
const codigoDe = (v: string | number | null): string => (typeof v === "number" ? v.toFixed(0) : String(v ?? "").trim());
const prefijoNum = (v: string | number | null): string | null => { const m = String(v ?? "").match(/^\s*(\d+)/); return m ? m[1] : null; };

export function planDesdeHojas(hojas: Hoja[]): { filas: FilaPlan[]; porHoja: Record<string, number>; avisos: string[] } {
  const filas: FilaPlan[] = [], porHoja: Record<string, number> = {}, avisos: string[] = [];
  for (const h of hojas) {
    const enc = (h.filas[0] ?? []).map(norm);
    const col = (...claves: string[]) => enc.findIndex((e) => claves.some((c) => e.startsWith(c)));
    const iCod = col("codigo ruta", "codigo zona"), iTur = col("turno"), iSrv = col("tipo de servicio"), iFre = col("frecuencia", "ciclo de atencion"), iHi = col("hora inicio"), iHf = col("hora fin");
    const iSec = col("sectores atendidos", "ubicacion"), iCar = col("caracterizacion"), iKm = col("kilometros ruta");
    if (iCod < 0 || iSrv < 0) { avisos.push(`La hoja «${h.nombre}» no tiene las columnas de código y tipo de servicio: se omite.`); continue; }
    const esPunto = norm(h.nombre).startsWith("puntos");
    let n = 0;
    for (const f of h.filas.slice(1)) {
      const cod = codigoDe(f[iCod] ?? null); if (!cod) continue;
      const turno = iTur >= 0 ? Number(prefijoNum(f[iTur] ?? null)) || null : null;
      filas.push({
        codigo: cod, clase: esPunto ? "punto" : "ruta", turno: esPunto ? 1 : turno, servicio: (prefijoNum(f[iSrv] ?? null) ?? "").padStart(2, "0"),
        frecuencia: esPunto || iFre < 0 ? null : (prefijoNum(f[iFre] ?? null) ?? "").padStart(2, "0"),
        hora_inicio: iHi >= 0 ? horaTexto(f[iHi] ?? null) : null, hora_fin: iHf >= 0 ? horaTexto(f[iHf] ?? null) : null,
        sectores: iSec >= 0 && f[iSec] != null ? String(f[iSec]).trim() : null,
        caracterizacion: esPunto ? (iFre >= 0 && f[iFre] != null ? String(f[iFre]).trim() : null) : iCar >= 0 && f[iCar] != null ? String(f[iCar]).trim() : null,
        km_ruta: iKm >= 0 && typeof f[iKm] === "number" ? Math.round((f[iKm] as number) * 1000) / 1000 : null,   // se guarda solo «km de ruta»; los kilómetros al mes no (D15)
      });
      n++;
    }
    porHoja[h.nombre] = n;
  }
  return { filas, porHoja, avisos };
}
