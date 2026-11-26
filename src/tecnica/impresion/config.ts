// Geovisor técnico · Corte 1 (26-nov, encargo único del geovisor): UN SOLO archivo con los textos, las extensiones de impresión y los colores de los sectores.
// Las extensiones son las del encargo (consulta de solo lectura en producción del 26-nov), en EPSG:4326, y se les suma el margen al imprimir.
// Para cambiar un texto o una extensión, se cambia aquí (lo leen la pantalla, la impresión y las pruebas).

export type Extension = { oeste: number; sur: number; este: number; norte: number };
export type PaginaImpresion = {
  clave: "total" | "urbano";
  nombre: string;                 // va al final del título: «… — Total»
  extension: Extension;
  /** Zoom del mapa con que se dibuja la página (la tesela de la red: completa desde z14, nodos desde z15). */
  zoom: number;
  /** Etiquetas que lleva la página. */
  etiquetas: { sectores: boolean; subsectores: boolean };
  /** Paso de la cuadrícula de coordenadas del borde, en grados. */
  pasoGrados: number;
  ubicacion: boolean;             // mapa de ubicación pequeño (solo la Urbana)
};

export const MARGEN_EXTENSION = 0.03;      // 3 % por lado

export const PAGINAS: PaginaImpresion[] = [
  { clave: "total", nombre: "Total", zoom: 14, etiquetas: { sectores: true, subsectores: false }, pasoGrados: 0.02, ubicacion: false,
    // O: red vigente · S: borde sur de la PTAR · E: red vigente · N: barrio más al norte
    extension: { oeste: -73.29679, sur: 10.38185, este: -73.21382, norte: 10.50684 } },
  { clave: "urbano", nombre: "Urbano", zoom: 15, etiquetas: { sectores: true, subsectores: true }, pasoGrados: 0.01, ubicacion: true,
    // el 96 % central de los predios del catastro (percentiles 2 y 98)
    extension: { oeste: -73.28887, sur: 10.42540, este: -73.22844, norte: 10.49198 } },
];

/** Notas de la temática «Edad» (David, 26-nov): en producción ningún tramo tiene fecha de instalación y la edad sale de la fecha regulatoria de la valoración. */
export const NOTAS_EDAD = {
  regulatoria: "Edad según fecha regulatoria de la valoración cuando no hay fecha de instalación",
  sinInstalacion: "Ningún tramo tiene fecha de instalación cargada",
};

export const TEXTOS_IMPRESION = {
  lugar: "Valledupar, Cesar",
  referencia: "WGS 84 (EPSG:4326)",
  fuente: "Fuente: Geoportal EMDUPAR",
  sinSatelital: "La foto satelital no se pudo exportar: se usó el mapa de calles.",
  atribucionCalles: "Mapa base © colaboradores de OpenStreetMap",
  atribucionSatelital: "Foto satelital: Esri, Maxar, Earthstar Geographics",
  boton: "Imprimir / PDF",
};

/** Nombre de la temática activa, tal como va en el título del PDF. */
export const TEMATICA: Record<string, string> = {
  tipo: "Tipo de activo", material: "Material de tuberías", edad: "Antigüedad de tuberías", diametro: "Diámetro de tuberías",
  afectaciones: "Afectaciones", remuneracion: "Remuneración",
};

// ---------------- Sectores hidráulicos (Plan Maestro 2014, Anexo C) ----------------
// 7 colores que no chocan con los de la red (azul del acueducto, café del alcantarillado, morado de tecnología).
export const COLOR_SECTOR: Record<string, string> = {
  "1": "#C2185B", "2": "#00897B", "3": "#3949AB", "4": "#827717", "5": "#E64A19", "6": "#546E7A", "7": "#8E24AA",
};
export const COLOR_SECTOR_SIN = "#6D28D9";      // un SEC cuyo nombre no se puede leer (no debería pasar: la prueba lo vigila)
export const ESTILO_SECTOR = { rellenoSector: 0.18, rellenoSubsector: 0.06, bordeSector: 2.4, bordeSubsector: 1.2, punteado: [3, 2] as [number, number] };
export const ZOOM_ETIQUETA = { sector: 13.5, subsector: 15 };
