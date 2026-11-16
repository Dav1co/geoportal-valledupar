// Lectores de capas del Cargue de capas (Técnica fase 1, Corte 5c; D-20). PUROS: sin React ni red, todo en el navegador.
// · SHP en zip (.shp + .dbf, con .prj y .cpg si vienen), GeoPackage (lector propio de SQLite, sin librerías), GeoJSON, KML o KMZ, y CSV o Excel con X y Y.
// · El archivo nunca sale del navegador: a la Edge van solo filas {orden, wkt, atributos}. La geometría la reproyecta la base (f_geo_desde_wkt).
// · La detección del sistema de coordenadas (.prj, gpkg_spatial_ref_sys, «crs» del GeoJSON o el rango de X y Y) es una propuesta: la persona la confirma.
// · Un GeoPackage o un zip con varios SHP trae varias capas: la carga masiva las reparte por el nombre.

export type Valor = string | number | boolean | null;
export type Atributos = Record<string, Valor>;
export type FilaLeida = { wkt: string | null; atributos: Atributos; error?: string };
export type Formato = "shp" | "gpkg" | "geojson" | "kml" | "csv" | "xlsx";
export type CapaLeida = {
  nombre: string;               // el de la capa dentro del archivo (o el del archivo)
  formato: Formato;
  srid: number | null;          // detectado (null = no se pudo)
  sridComo: string;             // de dónde salió la detección, para mostrarlo
  columnas: string[];
  filas: FilaLeida[];           // en las tablas (CSV y Excel), wkt va nulo hasta elegir X y Y
  tabla: boolean;               // CSV o Excel: la geometría sale de dos columnas
  xy?: { x: string; y: string } | null;      // columnas X y Y propuestas
  tipos: Record<string, number>;             // POINT, LINESTRING… → cuántas
  avisos: string[];
};

export const SISTEMAS: { srid: number; nombre: string }[] = [
  { srid: 9377, nombre: "MAGNA-SIRGAS Origen Nacional (EPSG 9377)" },
  { srid: 3116, nombre: "MAGNA-SIRGAS Colombia Bogotá (EPSG 3116)" },
  { srid: 3117, nombre: "MAGNA-SIRGAS Colombia Este Central (EPSG 3117)" },
  { srid: 3118, nombre: "MAGNA-SIRGAS Colombia Este (EPSG 3118)" },
  { srid: 3115, nombre: "MAGNA-SIRGAS Colombia Oeste (EPSG 3115)" },
  { srid: 3114, nombre: "MAGNA-SIRGAS Colombia Oeste Oeste (EPSG 3114)" },
  { srid: 4686, nombre: "MAGNA-SIRGAS geográficas (EPSG 4686)" },
  { srid: 4326, nombre: "WGS 84, latitud y longitud (EPSG 4326)" },
];
export const nombreSistema = (s: number | null) => SISTEMAS.find((x) => x.srid === s)?.nombre ?? (s ? `EPSG ${s} (no se acepta)` : "Sin detectar");

// =====================================================================================================================
// ZIP (lectura): directorio central y «deflate» con DecompressionStream del navegador (Chrome 80+, Safari 16.4+)
// =====================================================================================================================
export async function leerZip(buf: ArrayBuffer): Promise<Map<string, Uint8Array>> {
  const v = new DataView(buf), b = new Uint8Array(buf), out = new Map<string, Uint8Array>();
  let fin = -1;
  for (let i = b.length - 22; i >= Math.max(0, b.length - 65557); i--) if (v.getUint32(i, true) === 0x06054b50) { fin = i; break; }
  if (fin < 0) throw new Error("El archivo no es un .zip válido.");
  const n = v.getUint16(fin + 10, true);
  let p = v.getUint32(fin + 16, true);
  const dec = new TextDecoder();
  for (let k = 0; k < n; k++) {
    if (v.getUint32(p, true) !== 0x02014b50) throw new Error("El .zip está dañado (directorio central).");
    const metodo = v.getUint16(p + 10, true), comp = v.getUint32(p + 20, true), largoNombre = v.getUint16(p + 28, true);
    const largoExtra = v.getUint16(p + 30, true), largoCom = v.getUint16(p + 32, true), local = v.getUint32(p + 42, true);
    const nombre = dec.decode(b.subarray(p + 46, p + 46 + largoNombre));
    p += 46 + largoNombre + largoExtra + largoCom;
    if (nombre.endsWith("/") || nombre.startsWith("__MACOSX/")) continue;
    const ini = local + 30 + v.getUint16(local + 26, true) + v.getUint16(local + 28, true);
    const datos = b.subarray(ini, ini + comp);
    if (metodo === 0) out.set(nombre, datos);
    else if (metodo === 8) out.set(nombre, await inflar(datos));
    else throw new Error(`El .zip usa una compresión que no se lee aquí (${nombre}). Vuelva a comprimirlo con la opción normal.`);
  }
  return out;
}
async function inflar(datos: Uint8Array): Promise<Uint8Array> {
  if (typeof DecompressionStream === "undefined") throw new Error("Este navegador no puede abrir archivos .zip. Use Chrome o Safari al día.");
  const s = new Blob([datos as BlobPart]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  return new Uint8Array(await new Response(s).arrayBuffer());
}

// =====================================================================================================================
// WKT
// =====================================================================================================================
type Pos = number[];
// Las coordenadas se escriben IGUAL que en la carga inicial del Corte 1a (shp.py: 9 decimales sin los ceros del final; en grados ≈ 0,1 mm), para que la
// recarga del mismo archivo salga «igual» y no cree versiones nuevas. El parámetro queda por compatibilidad de las llamadas.
const redondeo = (_geograficas: boolean) => 0;
function num9(v: number) { const s = v.toFixed(9).replace(/0+$/, "").replace(/\.$/, ""); return s === "-0" || s === "" ? "0" : s; }
function fmt(p: Pos, _r: number) { return `${num9(p[0])} ${num9(p[1])}`; }
function anillo(ps: Pos[], r: number) { return "(" + ps.map((p) => fmt(p, r)).join(", ") + ")"; }
/** Geometría GeoJSON (cualquier sistema) → WKT 2D. Las colecciones mixtas no se admiten (una fila, un elemento). */
export function geojsonAWkt(g: { type: string; coordinates?: unknown; geometries?: unknown[] } | null | undefined, geograficas: boolean): string | null {
  if (!g || !g.type) return null;
  const r = redondeo(geograficas), c = g.coordinates as never;
  switch (g.type) {
    case "Point": return `POINT(${fmt(c, r)})`;
    case "MultiPoint": return `MULTIPOINT(${(c as Pos[]).map((p) => "(" + fmt(p, r) + ")").join(", ")})`;
    case "LineString": return `LINESTRING${anillo(c, r)}`;
    case "MultiLineString": return `MULTILINESTRING(${(c as Pos[][]).map((l) => anillo(l, r)).join(", ")})`;
    case "Polygon": return `POLYGON(${(c as Pos[][]).map((l) => anillo(l, r)).join(", ")})`;
    case "MultiPolygon": return `MULTIPOLYGON(${(c as Pos[][][]).map((pl) => "(" + pl.map((l) => anillo(l, r)).join(", ") + ")").join(", ")})`;
    case "GeometryCollection": {
      const gs = (g.geometries ?? []) as { type: string }[];
      if (gs.length === 1) return geojsonAWkt(gs[0] as never, geograficas);
      throw new Error("colección de geometrías mezcladas");
    }
    default: throw new Error(`tipo de geometría ${g.type}`);
  }
}
const tipoWkt = (w: string | null) => (w ? w.slice(0, w.indexOf("(")).trim().toUpperCase() : "SIN GEOMETRÍA");
function contarTipos(filas: FilaLeida[]) {
  const t: Record<string, number> = {};
  for (const f of filas) { const k = f.error ? "CON ERROR" : tipoWkt(f.wkt); t[k] = (t[k] ?? 0) + 1; }
  return t;
}
function columnasDe(filas: FilaLeida[]) {
  const s = new Set<string>();
  for (const f of filas) for (const k of Object.keys(f.atributos)) s.add(k);
  return [...s];
}
/** Un valor de atributo: los números con más de 15 dígitos y los objetos viajan como texto (sin perder precisión). */
function valor(x: unknown): Valor {
  if (x === null || x === undefined) return null;
  if (typeof x === "number") return Number.isFinite(x) ? (Number.isInteger(x) && Math.abs(x) > 9e15 ? String(x) : x) : null;
  if (typeof x === "boolean") return x;
  if (typeof x === "bigint") return x.toString();
  if (typeof x === "string") return x.length > 2000 ? x.slice(0, 2000) : x;
  return JSON.stringify(x).slice(0, 2000);
}

// =====================================================================================================================
// Sistema de coordenadas
// =====================================================================================================================
/** Desde el WKT de un .prj o de gpkg_spatial_ref_sys. */
export function sridDePrj(wkt: string): number | null {
  const t = wkt.replace(/\s+/g, " ");
  const auth = [...t.matchAll(/AUTHORITY\["EPSG","?(\d{4,6})"?\]/gi)].map((m) => Number(m[1]));
  const ultima = auth.length ? auth[auth.length - 1] : null;      // la de la proyección va al final
  if (ultima && SISTEMAS.some((s) => s.srid === ultima)) return ultima;
  if (/Origen[_ -]?Nacional|CTM[_ -]?12|Transverse_Mercator_12|\b9377\b/i.test(t)) return 9377;
  if (/^\s*(PROJCS|PROJCRS)/i.test(t)) {
    if (/Este[_ -]?Central/i.test(t)) return 3117;
    if (/Oeste[_ -]?Oeste/i.test(t)) return 3114;
    if (/Bogot/i.test(t)) return 3116;
    if (/Colombia[_ -]?Este|MAGNA[_ -]?Este/i.test(t)) return 3118;
    if (/Colombia[_ -]?Oeste|MAGNA[_ -]?Oeste/i.test(t)) return 3115;
    const p = (n: string) => Number((new RegExp(`PARAMETER\\["${n}",(-?[0-9.]+)\\]`, "i").exec(t) ?? [])[1]);
    const cm = p("central_meridian"), fe = p("false_easting");
    if (Math.abs(cm + 73) < 1e-6 && Math.abs(fe - 5000000) < 1) return 9377;
    if (Math.abs(cm + 74.07750791666666) < 1e-4 && Math.abs(fe - 1000000) < 1) return 3116;
    if (Math.abs(cm + 71.07750791666666) < 1e-4 && Math.abs(fe - 1000000) < 1) return 3117;
    return null;
  }
  if (/MAGNA/i.test(t)) return 4686;
  if (/WGS[_ ]?(19)?84/i.test(t)) return 4326;
  return null;
}
/** Por el rango de las coordenadas (CSV y Excel, o un SHP sin .prj). Es una propuesta. */
export function sridPorRango(xs: number[], ys: number[]): { srid: number | null; nota: string } {
  if (!xs.length) return { srid: null, nota: "Sin coordenadas" };
  const med = (a: number[]) => [...a].sort((p, q) => p - q)[Math.floor(a.length / 2)];
  const x = med(xs), y = med(ys);
  if (x > -80 && x < -66 && y > -5 && y < 14) return { srid: 4326, nota: "por el rango de las coordenadas (grados)" };
  if (x > 4.5e6 && x < 5.5e6 && y > 1.0e6 && y < 3.2e6) return { srid: 9377, nota: "por el rango de las coordenadas (Origen Nacional)" };
  if (x > 0.5e6 && x < 1.6e6 && y > 0.5e6 && y < 2.2e6) return { srid: 3116, nota: "por el rango de las coordenadas: parece MAGNA Bogotá; confirme si es otra zona" };
  return { srid: null, nota: "el rango de las coordenadas no corresponde a ningún sistema conocido" };
}
const esGeograficas = (srid: number | null) => srid === 4326 || srid === 4686;

// =====================================================================================================================
// SHP + DBF
// =====================================================================================================================
function decodificador(cpg?: Uint8Array) {
  const c = cpg ? new TextDecoder().decode(cpg).trim().toUpperCase() : "";
  if (/1252|LATIN|8859/.test(c)) return (u: Uint8Array) => new TextDecoder("windows-1252").decode(u);
  if (/UTF/.test(c)) return (u: Uint8Array) => new TextDecoder("utf-8").decode(u);
  // sin .cpg: UTF-8 si es válido; si no, Windows-1252 (lo de ArcGIS en español)
  return (u: Uint8Array) => { try { return new TextDecoder("utf-8", { fatal: true }).decode(u); } catch { return new TextDecoder("windows-1252").decode(u); } };
}
export function leerDbf(buf: Uint8Array, cpg?: Uint8Array): Atributos[] {
  const v = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const n = v.getUint32(4, true), largoCab = v.getUint16(8, true), largoReg = v.getUint16(10, true);
  const dec = decodificador(cpg), ascii = new TextDecoder("latin1");
  const campos: { nombre: string; tipo: string; largo: number; desde: number }[] = [];
  let desde = 1;
  for (let p = 32; p + 32 <= largoCab && buf[p] !== 0x0d; p += 32) {
    const crudo = buf.subarray(p, p + 11); const fin = crudo.indexOf(0);
    const nombre = dec(fin >= 0 ? crudo.subarray(0, fin) : crudo).trim();
    const largo = buf[p + 16];
    campos.push({ nombre, tipo: String.fromCharCode(buf[p + 11]), largo, desde });
    desde += largo;
  }
  const out: Atributos[] = [];
  for (let i = 0; i < n; i++) {
    const r = largoCab + i * largoReg;
    if (r + largoReg > buf.length) break;
    if (buf[r] === 0x2a) { out.push({ __borrado: true }); continue; }       // registro borrado («*»): se descarta junto con su forma
    const a: Atributos = {};
    for (const c of campos) {
      const crudo = buf.subarray(r + c.desde, r + c.desde + c.largo);
      if (c.tipo === "N" || c.tipo === "F") {
        const s = ascii.decode(crudo).trim();
        // un entero de más de 15 cifras (un código largo) se queda como texto para no perder precisión; los decimales («130.000000000000000») son número
        a[c.nombre] = s === "" || /^\*+$/.test(s) ? null : (/^[-+]?\d{16,}$/.test(s) ? s : Number.isFinite(Number(s)) ? Number(s) : null);
      } else if (c.tipo === "L") {
        const s = ascii.decode(crudo).trim().toUpperCase();
        a[c.nombre] = s && "TY".includes(s[0]) ? true : s && "FN".includes(s[0]) ? false : null;
      } else if (c.tipo === "D") {
        const s = ascii.decode(crudo).trim();
        a[c.nombre] = /^\d{8}$/.test(s) ? `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}` : null;
      } else if (c.tipo === "I" && c.largo === 4) {
        a[c.nombre] = new DataView(crudo.buffer, crudo.byteOffset, 4).getInt32(0, true);
      } else {
        const s = dec(crudo).replace(/[ \u0000]+$/, "");      // como la carga inicial: sin los espacios del final (los del comienzo se conservan)
        a[c.nombre] = s === "" ? null : s;
      }
    }
    out.push(a);
  }
  return out;
}
/** Area con signo (anillo de SHP: el exterior va en sentido horario → área negativa con esta fórmula). */
function areaConSigno(ps: Pos[]) { let s = 0; for (let i = 0; i + 1 < ps.length; i++) s += ps[i][0] * ps[i + 1][1] - ps[i + 1][0] * ps[i][1]; return s / 2; }
export function leerShp(buf: Uint8Array, geograficas: boolean): (string | null)[] {
  const v = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  if (v.getInt32(0, false) !== 9994) throw new Error("El .shp no es un shapefile válido.");
  const r = redondeo(geograficas), out: (string | null)[] = [];
  let p = 100;
  while (p + 8 <= buf.length) {
    const largo = v.getInt32(p + 4, false) * 2;
    const c = p + 8;
    p = c + largo;
    if (largo < 4) { out.push(null); continue; }
    const tipo = v.getInt32(c, true);
    const t = tipo % 10 === 0 && tipo !== 0 ? 0 : tipo > 20 ? tipo - 20 : tipo > 10 ? tipo - 10 : tipo;    // Z (11-18) y M (21-28) → 2D
    if (t === 0) { out.push(null); continue; }
    if (t === 1) { out.push(`POINT(${fmt([v.getFloat64(c + 4, true), v.getFloat64(c + 12, true)], r)})`); continue; }
    if (t === 8) {
      const n = v.getInt32(c + 36, true), ps: string[] = [];
      for (let i = 0; i < n; i++) ps.push("(" + fmt([v.getFloat64(c + 40 + i * 16, true), v.getFloat64(c + 48 + i * 16, true)], r) + ")");
      out.push(n === 1 ? `POINT${ps[0]}` : `MULTIPOINT(${ps.join(", ")})`);
      continue;
    }
    if (t === 3 || t === 5) {
      const np = v.getInt32(c + 36, true), n = v.getInt32(c + 40, true), base = c + 44 + np * 4;
      const partes: Pos[][] = [];
      for (let i = 0; i < np; i++) {
        const ini = v.getInt32(c + 44 + i * 4, true), fin = i + 1 < np ? v.getInt32(c + 48 + i * 4, true) : n;
        const ps: Pos[] = [];
        for (let k = ini; k < fin; k++) ps.push([v.getFloat64(base + k * 16, true), v.getFloat64(base + k * 16 + 8, true)]);
        partes.push(ps);
      }
      if (t === 3) out.push(partes.length === 1 ? `LINESTRING${anillo(partes[0], r)}` : `MULTILINESTRING(${partes.map((l) => anillo(l, r)).join(", ")})`);
      else {
        // los anillos en sentido horario abren un polígono; los antihorarios son huecos del anterior
        const pols: Pos[][][] = [];
        for (const a of partes) { if (areaConSigno(a) <= 0 || !pols.length) pols.push([a]); else pols[pols.length - 1].push(a); }
        out.push(pols.length === 1 ? `POLYGON(${pols[0].map((l) => anillo(l, r)).join(", ")})`
          : `MULTIPOLYGON(${pols.map((pl) => "(" + pl.map((l) => anillo(l, r)).join(", ") + ")").join(", ")})`);
      }
      continue;
    }
    out.push(null);
  }
  return out;
}
/** Las capas SHP de un zip, por nombre (sin la extensión). */
function capasShpDeZip(z: Map<string, Uint8Array>): CapaLeida[] {
  const base = (n: string) => n.replace(/\.[^./]+$/, "");
  const porNombre = new Map<string, Record<string, Uint8Array>>();
  for (const [n, d] of z) {
    const ext = (/\.([^./]+)$/.exec(n)?.[1] ?? "").toLowerCase();
    if (!["shp", "dbf", "prj", "cpg"].includes(ext)) continue;
    const k = base(n); const o = porNombre.get(k) ?? {}; o[ext] = d; porNombre.set(k, o);
  }
  const capas: CapaLeida[] = [];
  for (const [k, o] of porNombre) {
    if (!o.shp) continue;
    const avisos: string[] = [];
    const nombre = k.split("/").pop() ?? k;
    let srid: number | null = null, sridComo = "";
    if (o.prj) { srid = sridDePrj(new TextDecoder().decode(o.prj)); sridComo = srid ? "por el archivo .prj" : "el .prj no corresponde a un sistema conocido"; }
    else avisos.push("El zip no trae el .prj: el sistema de coordenadas se propone por el rango de las coordenadas.");
    const geo = esGeograficas(srid);
    let wkts = leerShp(o.shp, geo);
    if (!o.prj || srid === null) {
      const xs: number[] = [], ys: number[] = [];
      for (const w of wkts.slice(0, 500)) { const m = w && /(-?[0-9.]+) (-?[0-9.]+)/.exec(w); if (m) { xs.push(Number(m[1])); ys.push(Number(m[2])); } }
      const d = sridPorRango(xs, ys); srid = d.srid; sridComo = d.nota;
      if (esGeograficas(srid) !== geo) wkts = leerShp(o.shp, esGeograficas(srid));
    }
    const attrs: Atributos[] = o.dbf ? leerDbf(o.dbf, o.cpg) : wkts.map(() => ({}));
    if (!o.dbf) avisos.push("El zip no trae el .dbf: la capa no tiene atributos (no habrá columna llave).");
    if (o.dbf && attrs.length !== wkts.length) avisos.push(`El .shp tiene ${wkts.length} elementos y el .dbf ${attrs.length} registros: se toman los que coinciden.`);
    const filas: FilaLeida[] = [];
    let borrados = 0;
    for (let i = 0; i < Math.min(wkts.length, attrs.length); i++) {
      if (attrs[i].__borrado) { borrados++; continue; }
      filas.push({ wkt: wkts[i], atributos: attrs[i] });
    }
    if (borrados) avisos.push(`${borrados} registros marcados como borrados en el .dbf no se cargan.`);
    capas.push({ nombre, formato: "shp", srid, sridComo, columnas: columnasDe(filas), filas, tabla: false, tipos: contarTipos(filas), avisos });
  }
  return capas;
}

// =====================================================================================================================
// GeoPackage: lector propio de SQLite (solo lectura de tablas; sin índices ni WAL)
// =====================================================================================================================
class Sqlite {
  private v: DataView; private b: Uint8Array; tam: number; util: number; private dec: TextDecoder;
  constructor(buf: Uint8Array) {
    this.b = buf; this.v = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    if (new TextDecoder().decode(buf.subarray(0, 15)) !== "SQLite format 3") throw new Error("El archivo no es un GeoPackage (SQLite) válido.");
    const t = this.v.getUint16(16, false); this.tam = t === 1 ? 65536 : t;
    this.util = this.tam - buf[20];
    const enc = this.v.getUint32(56, false);
    this.dec = new TextDecoder(enc === 2 ? "utf-16le" : enc === 3 ? "utf-16be" : "utf-8");
  }
  get wal() { return this.b[18] === 2 || this.b[19] === 2; }
  private varint(p: number): [bigint, number] {
    let r = 0n;
    for (let i = 0; i < 8; i++) { const x = this.b[p + i]; r = (r << 7n) | BigInt(x & 0x7f); if (x < 0x80) return [r, i + 1]; }
    return [(r << 8n) | BigInt(this.b[p + 8]), 9];
  }
  private pagina(n: number) { return (n - 1) * this.tam; }
  /** Recorre la tabla (árbol b de la tabla) desde su página raíz; entrega [rowid, registro]. */
  *filas(raiz: number): Generator<[bigint, Uint8Array]> {
    const pila = [raiz];
    while (pila.length) {
      const pg = pila.pop()!;
      const o = this.pagina(pg), h = o + (pg === 1 ? 100 : 0), tipo = this.b[h];
      const n = this.v.getUint16(h + 3, false);
      if (tipo === 0x05) {
        const hijos: number[] = [];
        for (let i = 0; i < n; i++) hijos.push(this.v.getUint32(o + this.v.getUint16(h + 12 + i * 2, false), false));
        hijos.push(this.v.getUint32(h + 8, false));
        for (let i = hijos.length - 1; i >= 0; i--) pila.push(hijos[i]);       // en orden
      } else if (tipo === 0x0d) {
        for (let i = 0; i < n; i++) {
          let p = o + this.v.getUint16(h + 8 + i * 2, false);
          const [tamP, a] = this.varint(p); p += a;
          const [rowid, b2] = this.varint(p); p += b2;
          yield [rowid, this.carga(p, Number(tamP))];
        }
      } else throw new Error("El GeoPackage tiene una página que no se reconoce (¿está dañado?).");
    }
  }
  private carga(p: number, P: number): Uint8Array {
    const U = this.util, X = U - 35;
    if (P <= X) return this.b.subarray(p, p + P);
    const M = Math.floor(((U - 12) * 32) / 255) - 23, K = M + ((P - M) % (U - 4)), local = K <= X ? K : M;
    const out = new Uint8Array(P); out.set(this.b.subarray(p, p + local), 0);
    let hecho = local, sig = this.v.getUint32(p + local, false);
    while (hecho < P && sig) {
      const o = this.pagina(sig), cuanto = Math.min(U - 4, P - hecho);
      out.set(this.b.subarray(o + 4, o + 4 + cuanto), hecho); hecho += cuanto; sig = this.v.getUint32(o, false);
    }
    return out;
  }
  registro(r: Uint8Array): (bigint | number | string | Uint8Array | null)[] {
    const dv = new DataView(r.buffer, r.byteOffset, r.byteLength);
    const vi = (p: number): [number, number] => { let x = 0; for (let i = 0; i < 9; i++) { const c = r[p + i]; x = x * 128 + (c & 0x7f); if (c < 0x80) return [x, i + 1]; } return [x, 9]; };
    const [tamCab, a] = vi(0); let p = a; const tipos: number[] = [];
    while (p < tamCab) { const [t, n] = vi(p); tipos.push(t); p += n; }
    let d = tamCab; const out: (bigint | number | string | Uint8Array | null)[] = [];
    for (const t of tipos) {
      if (t === 0) out.push(null);
      else if (t >= 1 && t <= 6) {
        const largo = [0, 1, 2, 3, 4, 6, 8][t]; let x = 0n;
        for (let i = 0; i < largo; i++) x = (x << 8n) | BigInt(r[d + i]);
        if (r[d] & 0x80) x -= 1n << BigInt(largo * 8);
        out.push(x >= BigInt(Number.MIN_SAFE_INTEGER) && x <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(x) : x); d += largo;
      } else if (t === 7) { out.push(dv.getFloat64(d, false)); d += 8; }
      else if (t === 8) out.push(0);
      else if (t === 9) out.push(1);
      else if (t >= 12 && t % 2 === 0) { const l = (t - 12) / 2; out.push(r.subarray(d, d + l)); d += l; }
      else if (t >= 13) { const l = (t - 13) / 2; out.push(this.dec.decode(r.subarray(d, d + l))); d += l; }
      else out.push(null);
    }
    return out;
  }
}
/** Nombres de las columnas de un CREATE TABLE, y cuál es el alias del rowid (INTEGER PRIMARY KEY). */
function columnasDeCreate(sql: string): { nombres: string[]; rowid: number } {
  const ini = sql.indexOf("("), fin = sql.lastIndexOf(")");
  const cuerpo = sql.slice(ini + 1, fin), partes: string[] = [];
  let prof = 0, act = "";
  for (const ch of cuerpo) { if (ch === "(") prof++; if (ch === ")") prof--; if (ch === "," && prof === 0) { partes.push(act); act = ""; } else act += ch; }
  if (act.trim()) partes.push(act);
  const nombres: string[] = []; let rowid = -1;
  for (const p0 of partes) {
    const p = p0.trim();
    if (/^(CONSTRAINT|PRIMARY\s+KEY|UNIQUE|CHECK|FOREIGN\s+KEY)\b/i.test(p)) continue;
    const m = /^("([^"]+)"|`([^`]+)`|\[([^\]]+)\]|(\S+))\s*(.*)$/s.exec(p);
    if (!m) continue;
    const nombre = m[2] ?? m[3] ?? m[4] ?? m[5];
    const resto = m[6].trim();      // SQLite: tipo INTEGER con PRIMARY KEY (aunque lleve NOT NULL en medio) = alias del rowid
    if (/^INTEGER\b/i.test(resto) && /\bPRIMARY\s+KEY\b/i.test(resto) && !/\bPRIMARY\s+KEY\s+DESC\b/i.test(resto)) rowid = nombres.length;
    nombres.push(nombre);
  }
  return { nombres, rowid };
}
/** WKB (estándar, ISO o extendido) → WKT 2D. */
function wkbAWkt(b: Uint8Array, geograficas: boolean): string | null {
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength), r = redondeo(geograficas);
  let p = 0;
  const geom = (): string => {
    const le = b[p] === 1; p += 1;
    let t = v.getUint32(p, le); p += 4;
    let dims = 2;
    if (t & 0x80000000) dims++; if (t & 0x40000000) dims++;
    if (t & 0x20000000) p += 4;        // SRID de EWKB
    t &= 0x0fffffff;
    if (t > 1000) { dims += Math.floor(t / 1000) === 3 ? 2 : 1; t %= 1000; }
    const pt = (): string => { const x = v.getFloat64(p, le), y = v.getFloat64(p + 8, le); p += dims * 8; return fmt([x, y], r); };
    const lin = (): string => { const n = v.getUint32(p, le); p += 4; const ps: string[] = []; for (let i = 0; i < n; i++) ps.push(pt()); return "(" + ps.join(", ") + ")"; };
    const pol = (): string => { const n = v.getUint32(p, le); p += 4; const as: string[] = []; for (let i = 0; i < n; i++) as.push(lin()); return "(" + as.join(", ") + ")"; };
    const multi = (f: () => string): string => {
      const n = v.getUint32(p, le); p += 4; const xs: string[] = [];
      for (let i = 0; i < n; i++) { p += 5; xs.push(f()); }
      return "(" + xs.join(", ") + ")";
    };
    switch (t) {
      case 1: return `POINT(${pt()})`;
      case 2: return `LINESTRING${lin()}`;
      case 3: return `POLYGON${pol()}`;
      case 4: return `MULTIPOINT${multi(() => "(" + pt() + ")")}`;
      case 5: return `MULTILINESTRING${multi(lin)}`;
      case 6: return `MULTIPOLYGON${multi(pol)}`;
      default: throw new Error(`tipo de geometría ${t}`);
    }
  };
  // Los multi* traen cada parte con su propio encabezado (orden + tipo): se saltan arriba con p += 5 (asume el mismo orden de bytes y 2D en las partes).
  return geom();
}
function gpkgGeom(b: Uint8Array | null, geograficas: boolean): string | null {
  if (!b || b.length < 8) return null;
  if (b[0] !== 0x47 || b[1] !== 0x50) return wkbAWkt(b, geograficas);      // WKB suelto
  const flags = b[3];
  if (flags & 0x10) return null;                                           // geometría vacía
  const env = (flags >> 1) & 0x07;
  const largoEnv = [0, 32, 48, 48, 64][env] ?? 0;
  return wkbAWkt(b.subarray(8 + largoEnv), geograficas);
}
export function leerGpkg(buf: Uint8Array): CapaLeida[] {
  const db = new Sqlite(buf);
  const maestro: { tipo: string; nombre: string; raiz: number; sql: string }[] = [];
  for (const [, r] of db.filas(1)) { const x = db.registro(r); maestro.push({ tipo: String(x[0]), nombre: String(x[1]), raiz: Number(x[3]), sql: String(x[4] ?? "") }); }
  const tabla = (n: string) => maestro.find((m) => m.tipo === "table" && m.nombre.toLowerCase() === n.toLowerCase());
  const leerTabla = (n: string) => {
    const t = tabla(n); if (!t) return [];
    const { nombres, rowid } = columnasDeCreate(t.sql);
    const out: Record<string, unknown>[] = [];
    for (const [id, r] of db.filas(t.raiz)) {
      const x = db.registro(r), o: Record<string, unknown> = {};
      nombres.forEach((c, i) => { o[c] = i === rowid ? (typeof id === "bigint" && id <= BigInt(Number.MAX_SAFE_INTEGER) ? Number(id) : id) : x[i] ?? null; });
      out.push(o);
    }
    return { nombres, filas: out };
  };
  const cont = leerTabla("gpkg_contents"), gcol = leerTabla("gpkg_geometry_columns"), srs = leerTabla("gpkg_spatial_ref_sys");
  if (!Array.isArray(cont) && !cont.filas.length) throw new Error("El GeoPackage no trae capas (gpkg_contents vacío).");
  if (Array.isArray(cont)) throw new Error("El archivo es SQLite pero no es un GeoPackage (falta gpkg_contents).");
  const capas: CapaLeida[] = [];
  for (const c of cont.filas.filter((x) => x.data_type === "features" || x.data_type === "attributes")) {
    const nombre = String(c.table_name);
    const t = leerTabla(nombre);
    if (Array.isArray(t)) continue;
    const gc = Array.isArray(gcol) ? undefined : gcol.filas.find((g) => String(g.table_name).toLowerCase() === nombre.toLowerCase());
    const colGeom = gc ? String(gc.column_name) : null;
    const srsId = Number(gc?.srs_id ?? c.srs_id ?? 0);
    const def = Array.isArray(srs) ? undefined : srs.filas.find((s) => Number(s.srs_id) === srsId);
    let srid: number | null = null, sridComo = "";
    if (def && String(def.organization).toUpperCase() === "EPSG" && SISTEMAS.some((s) => s.srid === Number(def.organization_coordsys_id))) { srid = Number(def.organization_coordsys_id); sridComo = "por el GeoPackage (gpkg_spatial_ref_sys)"; }
    else if (def && typeof def.definition === "string") { srid = sridDePrj(def.definition); sridComo = srid ? "por la definición del sistema en el GeoPackage" : "el GeoPackage trae un sistema que no se reconoce"; }
    const avisos: string[] = [];
    if (db.wal) avisos.push("El GeoPackage está en modo WAL: si lo estaba editando en QGIS, ciérrelo antes de cargarlo para que no falten cambios.");
    const filas: FilaLeida[] = [];
    for (const f of t.filas) {
      const a: Atributos = {};
      for (const k of t.nombres) if (k !== colGeom) a[k] = f[k] instanceof Uint8Array ? null : valor(f[k]);
      let wkt: string | null = null, error: string | undefined;
      try { wkt = colGeom ? gpkgGeom(f[colGeom] as Uint8Array | null, esGeograficas(srid)) : null; } catch (e) { error = (e as Error).message; }
      filas.push({ wkt, atributos: a, error });
    }
    capas.push({ nombre, formato: "gpkg", srid, sridComo, columnas: t.nombres.filter((k) => k !== colGeom), filas, tabla: false, tipos: contarTipos(filas), avisos });
  }
  if (!capas.length) throw new Error("El GeoPackage no trae capas de elementos.");
  return capas;
}

// =====================================================================================================================
// GeoJSON y KML
// =====================================================================================================================
export function leerGeoJSON(texto: string, nombre: string): CapaLeida {
  let j: Record<string, unknown>;
  try { j = JSON.parse(texto); } catch { throw new Error("El archivo no es un GeoJSON válido."); }
  const feats = j.type === "FeatureCollection" && Array.isArray(j.features) ? (j.features as Record<string, unknown>[]) : j.type === "Feature" ? [j] : null;
  if (!feats) throw new Error("El GeoJSON debe ser una colección de elementos (FeatureCollection).");
  const crs = (j.crs as { properties?: { name?: string } } | undefined)?.properties?.name;
  const m = typeof crs === "string" ? /EPSG:{1,2}(\d{4,6})/i.exec(crs) : null;
  const srid = typeof crs === "string" && !/CRS84/i.test(crs) && m ? Number(m[1]) : 4326;
  const filas: FilaLeida[] = feats.map((f) => {
    const a: Atributos = {};
    for (const [k, x] of Object.entries((f.properties as Record<string, unknown>) ?? {})) a[k] = valor(x);
    if (f.id !== undefined && !("id" in a)) a.id = valor(f.id);
    try { return { wkt: geojsonAWkt(f.geometry as never, esGeograficas(srid)), atributos: a }; } catch (e) { return { wkt: null, atributos: a, error: (e as Error).message }; }
  });
  return { nombre, formato: "geojson", srid, sridComo: crs ? "por el «crs» del GeoJSON" : "GeoJSON sin «crs»: WGS 84 (RFC 7946)", columnas: columnasDe(filas), filas, tabla: false, tipos: contarTipos(filas), avisos: [] };
}
export function leerKml(texto: string, nombre: string): CapaLeida {
  const doc = new DOMParser().parseFromString(texto, "application/xml");
  if (doc.getElementsByTagName("parsererror").length) throw new Error("El KML no es un XML válido.");
  const hijos = (e: Element, n: string) => Array.from(e.children).filter((c) => c.localName === n);
  const coords = (e: Element | undefined): Pos[] => (e?.textContent ?? "").trim().split(/\s+/).filter(Boolean).map((t) => t.split(",").map(Number).slice(0, 2));
  const geom = (g: Element): { type: string; coordinates?: unknown; geometries?: unknown[] } | null => {
    const c = (n: string) => hijos(g, n)[0];
    switch (g.localName) {
      case "Point": return { type: "Point", coordinates: coords(c("coordinates"))[0] };
      case "LineString": return { type: "LineString", coordinates: coords(c("coordinates")) };
      case "Polygon": {
        const ext = c("outerBoundaryIs"), ints = hijos(g, "innerBoundaryIs");
        const lr = (b: Element) => coords(b.getElementsByTagNameNS("*", "coordinates")[0]);
        return { type: "Polygon", coordinates: [lr(ext), ...ints.map(lr)] };
      }
      case "MultiGeometry": {
        const gs = Array.from(g.children).map(geom).filter(Boolean) as { type: string; coordinates: unknown }[];
        const tipos = new Set(gs.map((x) => x.type));
        if (gs.length === 1) return gs[0];
        if (tipos.size === 1) { const t = gs[0].type; return { type: "Multi" + t, coordinates: gs.map((x) => x.coordinates) }; }
        return { type: "GeometryCollection", geometries: gs };
      }
      default: return null;
    }
  };
  const filas: FilaLeida[] = [];
  for (const pm of Array.from(doc.getElementsByTagNameNS("*", "Placemark"))) {
    const a: Atributos = {};
    const nm = hijos(pm, "name")[0]?.textContent?.trim(); if (nm) a.name = nm;
    for (const d of Array.from(pm.getElementsByTagNameNS("*", "Data"))) a[d.getAttribute("name") ?? "dato"] = valor(d.getElementsByTagNameNS("*", "value")[0]?.textContent?.trim() ?? null);
    for (const d of Array.from(pm.getElementsByTagNameNS("*", "SimpleData"))) a[d.getAttribute("name") ?? "dato"] = valor(d.textContent?.trim() ?? null);
    const g = Array.from(pm.children).find((c) => ["Point", "LineString", "Polygon", "MultiGeometry"].includes(c.localName));
    try { filas.push({ wkt: g ? geojsonAWkt(geom(g) as never, true) : null, atributos: a }); } catch (e) { filas.push({ wkt: null, atributos: a, error: (e as Error).message }); }
  }
  if (!filas.length) throw new Error("El KML no trae elementos (Placemark).");
  return { nombre, formato: "kml", srid: 4326, sridComo: "KML: siempre WGS 84", columnas: columnasDe(filas), filas, tabla: false, tipos: contarTipos(filas), avisos: [] };
}

// =====================================================================================================================
// CSV y Excel con X y Y
// =====================================================================================================================
const NOMBRES_X = /^(x|lon|long|longitud|longitude|este|coord_?x|x_?coord|easting|e)$/i;
const NOMBRES_Y = /^(y|lat|latitud|latitude|norte|coord_?y|y_?coord|northing|n)$/i;
function numeroDe(v: Valor): number | null {
  if (typeof v === "number") return v;
  if (typeof v !== "string") return null;
  const t = v.trim().replace(/\s/g, "");
  if (/^-?\d+(,\d+)?$/.test(t)) return Number(t.replace(",", "."));
  if (/^-?\d{1,3}(\.\d{3})+(,\d+)?$/.test(t)) return Number(t.replace(/\./g, "").replace(",", "."));
  if (/^-?\d+(\.\d+)?$/.test(t)) return Number(t);
  return null;
}
function tablaACapa(nombre: string, formato: Formato, cab: string[], filasCrudas: Valor[][]): CapaLeida {
  const vistos = new Map<string, number>();
  const columnas = cab.map((c, i) => {      // nombres vacíos o repetidos (un CSV con dos «X», por ejemplo) se vuelven únicos
    const b = (c && c.trim()) || `columna_${i + 1}`; const k = (vistos.get(b.toLowerCase()) ?? 0) + 1; vistos.set(b.toLowerCase(), k);
    return k === 1 ? b : `${b}_${k}`;
  });
  const filas: FilaLeida[] = filasCrudas.filter((r) => r.some((x) => x !== null && x !== "")).map((r) => {
    const a: Atributos = {};
    columnas.forEach((c, i) => { const x = r[i] ?? null; a[c] = typeof x === "string" && numeroDe(x) !== null && !/^0\d/.test(x.trim()) ? numeroDe(x) : x; });
    return { wkt: null, atributos: a };
  });
  const x = columnas.find((c) => NOMBRES_X.test(c.trim())) ?? null, y = columnas.find((c) => NOMBRES_Y.test(c.trim())) ?? null;
  const capa: CapaLeida = { nombre, formato, srid: null, sridComo: "", columnas, filas, tabla: true, xy: x && y ? { x, y } : null, tipos: {}, avisos: [] };
  if (!capa.xy) capa.avisos.push("No se reconocieron las columnas X y Y: elíjalas en el paso del sistema de coordenadas.");
  else { const d = proponerSridTabla(capa, capa.xy); capa.srid = d.srid; capa.sridComo = d.nota; }
  return capa;
}
export function proponerSridTabla(capa: CapaLeida, xy: { x: string; y: string }) {
  const xs: number[] = [], ys: number[] = [];
  for (const f of capa.filas.slice(0, 500)) { const a = numeroDe(f.atributos[xy.x]), b = numeroDe(f.atributos[xy.y]); if (a !== null && b !== null) { xs.push(a); ys.push(b); } }
  return sridPorRango(xs, ys);
}
/** Las filas con su geometría a partir de las columnas X y Y (CSV y Excel). Las filas sin X o Y válidas quedan con error. */
export function filasConXY(capa: CapaLeida, xy: { x: string; y: string }, srid: number | null): FilaLeida[] {
  const r = redondeo(esGeograficas(srid));
  return capa.filas.map((f) => {
    const a = numeroDe(f.atributos[xy.x]), b = numeroDe(f.atributos[xy.y]);
    if (a === null || b === null) return { ...f, wkt: null, error: "sin X o Y" };
    return { ...f, wkt: `POINT(${fmt([a, b], r)})` };
  });
}
export function leerCsv(texto: string, nombre: string): CapaLeida {
  const t = texto.replace(/^﻿/, "");
  const linea1 = t.slice(0, t.indexOf("\n") >= 0 ? t.indexOf("\n") : t.length);
  const sep = [";", "\t", ","].map((s) => [s, linea1.split(s).length] as const).sort((a, b) => b[1] - a[1])[0][0];
  const filas: string[][] = []; let fila: string[] = [], campo = "", comillas = false;
  for (let i = 0; i < t.length; i++) {
    const ch = t[i];
    if (comillas) { if (ch === '"') { if (t[i + 1] === '"') { campo += '"'; i++; } else comillas = false; } else campo += ch; continue; }
    if (ch === '"') comillas = true;
    else if (ch === sep) { fila.push(campo); campo = ""; }
    else if (ch === "\n" || ch === "\r") { if (ch === "\r" && t[i + 1] === "\n") i++; fila.push(campo); filas.push(fila); fila = []; campo = ""; }
    else campo += ch;
  }
  if (campo !== "" || fila.length) { fila.push(campo); filas.push(fila); }
  if (filas.length < 2) throw new Error("El CSV no trae filas (la primera fila son los nombres de las columnas).");
  return tablaACapa(nombre, "csv", filas[0], filas.slice(1).map((r) => r.map((x) => (x.trim() === "" ? null : x.trim()))));
}
export async function leerXlsx(buf: ArrayBuffer, nombre: string): Promise<CapaLeida> {
  const z = await leerZip(buf), dec = new TextDecoder();
  const xml = (n: string) => { const d = z.get(n); return d ? new DOMParser().parseFromString(dec.decode(d), "application/xml") : null; };
  const libro = xml("xl/workbook.xml"); if (!libro) throw new Error("El archivo no es un Excel (.xlsx) válido.");
  const hoja1 = libro.getElementsByTagNameNS("*", "sheet")[0];
  const rid = hoja1?.getAttribute("r:id") ?? hoja1?.getAttributeNS("http://schemas.openxmlformats.org/officeDocument/2006/relationships", "id");
  const rels = xml("xl/_rels/workbook.xml.rels");
  let destino = "worksheets/sheet1.xml";
  for (const r of Array.from(rels?.getElementsByTagNameNS("*", "Relationship") ?? [])) if (r.getAttribute("Id") === rid) destino = r.getAttribute("Target") ?? destino;
  const hoja = xml("xl/" + destino.replace(/^\/?xl\//, "").replace(/^\//, ""));
  if (!hoja) throw new Error("No se encontró la primera hoja del Excel.");
  const compartidos = Array.from(xml("xl/sharedStrings.xml")?.getElementsByTagNameNS("*", "si") ?? []).map((si) => Array.from(si.getElementsByTagNameNS("*", "t")).map((x) => x.textContent ?? "").join(""));
  const colIdx = (ref: string) => { const l = /^[A-Z]+/.exec(ref)?.[0] ?? "A"; let n = 0; for (const c of l) n = n * 26 + (c.charCodeAt(0) - 64); return n - 1; };
  const filas: Valor[][] = [];
  for (const row of Array.from(hoja.getElementsByTagNameNS("*", "row"))) {
    const r: Valor[] = [];
    for (const c of Array.from(row.getElementsByTagNameNS("*", "c"))) {
      const t = c.getAttribute("t"), v = c.getElementsByTagNameNS("*", "v")[0]?.textContent ?? null;
      let x: Valor = null;
      if (t === "s") x = v !== null ? compartidos[Number(v)] ?? null : null;
      else if (t === "inlineStr") x = Array.from(c.getElementsByTagNameNS("*", "t")).map((e) => e.textContent ?? "").join("");
      else if (t === "b") x = v === "1";
      else if (t === "str" || t === "e") x = v;
      else x = v === null ? null : Number(v);
      r[colIdx(c.getAttribute("r") ?? "A")] = typeof x === "string" && x.trim() === "" ? null : x;
    }
    filas.push(Array.from(r, (x) => x ?? null));
  }
  if (filas.length < 2) throw new Error("La primera hoja del Excel no trae filas (la primera fila son los nombres de las columnas).");
  return tablaACapa(nombre, "xlsx", filas[0].map((x) => String(x ?? "")), filas.slice(1));
}

// =====================================================================================================================
// Entrada única: el archivo → sus capas
// =====================================================================================================================
export async function leerArchivo(archivo: File): Promise<CapaLeida[]> {
  const n = archivo.name, ext = (/\.([^.]+)$/.exec(n)?.[1] ?? "").toLowerCase(), base = n.replace(/\.[^.]+$/, "");
  const buf = await archivo.arrayBuffer();
  if (ext === "zip") {
    const z = await leerZip(buf);
    const capas = capasShpDeZip(z);
    const gpkgs = [...z].filter(([k]) => /\.gpkg$/i.test(k));
    for (const [, d] of gpkgs) capas.push(...leerGpkg(d));
    for (const [k, d] of z) if (/\.(geo)?json$/i.test(k)) capas.push(leerGeoJSON(new TextDecoder().decode(d), k.replace(/^.*\//, "").replace(/\.[^.]+$/, "")));
    if (!capas.length) throw new Error("El zip no trae capas que se puedan leer (.shp con su .dbf, .gpkg o .geojson).");
    return capas;
  }
  if (ext === "gpkg") return leerGpkg(new Uint8Array(buf));
  if (ext === "geojson" || ext === "json") return [leerGeoJSON(new TextDecoder().decode(buf), base)];
  if (ext === "kml") return [leerKml(new TextDecoder().decode(buf), base)];
  if (ext === "kmz") {
    const z = await leerZip(buf); const k = [...z].find(([x]) => /\.kml$/i.test(x));
    if (!k) throw new Error("El KMZ no trae un .kml adentro.");
    return [leerKml(new TextDecoder().decode(k[1]), base)];
  }
  if (ext === "csv" || ext === "txt") return [leerCsv(decodificador()(new Uint8Array(buf)), base)];
  if (ext === "xlsx") return [await leerXlsx(buf, base)];
  if (ext === "shp" || ext === "dbf") throw new Error("Del shapefile se necesitan varios archivos (.shp, .dbf, .prj): comprímalos juntos en un .zip y cárguelo.");
  if (ext === "xls") throw new Error("Guarde el Excel como .xlsx (el formato .xls antiguo no se lee).");
  throw new Error("Ese tipo de archivo no se lee. Use SHP en zip, GeoPackage, GeoJSON, KML o KMZ, o CSV o Excel con X y Y.");
}

// =====================================================================================================================
// Columna llave, huella y lotes
// =====================================================================================================================
export const SIN_LLAVE = "(geometria)";
/** Cuántas filas traen la columna vacía y cuántas la repiten. */
export function revisarLlave(filas: FilaLeida[], col: string): { vacias: number; repetidas: number; unica: boolean } {
  const vistos = new Map<string, number>(); let vacias = 0;
  for (const f of filas) { const v = f.atributos[col]; const t = v === null || v === undefined ? "" : String(v).trim(); if (!t) { vacias++; continue; } vistos.set(t, (vistos.get(t) ?? 0) + 1); }
  let repetidas = 0; for (const n of vistos.values()) if (n > 1) repetidas += n;
  return { vacias, repetidas, unica: vacias === 0 && repetidas === 0 };
}
/** Propone la columna llave: la primera única con un nombre de código (codigo, id, label…), o la primera única. */
export function proponerLlave(capa: CapaLeida): string | null {
  const unicas = capa.columnas.filter((c) => revisarLlave(capa.filas, c).unica);
  // primero un código del negocio; los identificadores internos del programa (fid, objectid) al final: cambian si se vuelve a exportar
  const interna = (c: string) => /^(fid|objectid|ogc_fid|gid|ogr_fid)$/i.test(c);
  return unicas.find((c) => /^(codigo|código|cod|label|llave|key|id)$/i.test(c)) ?? unicas.find((c) => !interna(c) && /cod|label|^id_|_id$/i.test(c))
    ?? unicas.find((c) => !interna(c)) ?? unicas[0] ?? null;
}
export async function sha256Hex(datos: ArrayBuffer | Uint8Array | string): Promise<string> {
  const b = typeof datos === "string" ? new TextEncoder().encode(datos) : datos;
  const h = await crypto.subtle.digest("SHA-256", b as BufferSource);
  return [...new Uint8Array(h)].map((x) => x.toString(16).padStart(2, "0")).join("");
}
export type FilaLote = { orden: number; wkt: string | null; atributos: Atributos };
/** Reparte las filas en lotes de hasta 200 filas y ~450 KB (la Edge acepta 512 KB por lote). */
export function enLotes(filas: FilaLote[], maxFilas = 200, maxBytes = 450_000): FilaLote[][] {
  const out: FilaLote[][] = []; let act: FilaLote[] = [], tam = 2;
  for (const f of filas) {
    const t = JSON.stringify(f).length + 1;
    if (t > maxBytes) throw new Error(`El elemento ${f.orden} es demasiado grande para cargarlo (más de 450 KB): simplifique su geometría.`);
    if (act.length >= maxFilas || tam + t > maxBytes) { out.push(act); act = []; tam = 2; }
    act.push(f); tam += t;
  }
  if (act.length) out.push(act);
  return out;
}
/** Normaliza un nombre de capa del archivo para repartir la carga masiva (sin tildes, sin mayúsculas, sin prefijos comunes). */
export const normalizarNombre = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\.(shp|gpkg)$/, "").replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
