import type { FormularioDef, RegistrarCuerpo, VariableDef } from "./apiTecnica";
import { interpretarNumero } from "./numeros";

// Agrupación de las variables de un formulario por «lugar» (LÓGICA PURA, sin React; se prueba en Node). Todo sale de lo que entrega el servidor: aquí NO hay nombres de variables,
// de plantas ni de puntos. Los únicos textos escritos son los títulos de presentación de cada TIPO de punto (con uno por defecto para tipos futuros).
//   • por_planta     → una tarjeta «Por planta» con los botones de planta;
//   • ambas_plantas  → una tarjeta «Para las dos plantas» (sin selector);
//   • por_punto      → una tarjeta por tipo_punto, con un selector de punto (la unión de los puntos de sus variables).
// Un envío es de UN solo lugar (decisión D-C3-1): cada tarjeta, con su lugar elegido, se envía como un registro aparte.

export type Opcion = { codigo: string; nombre: string };
export type Tarjeta = {
  id: string;                       // «planta», «ambas» o «punto:<tipo>»
  grupo: string;                    // parte de la clave de envío: «planta», «ambas» o el tipo de punto
  clase: "planta" | "ambas" | "punto";
  numero: number;
  titulo: string; ayuda: string;
  etiquetaLugar: string;            // «Planta», «Tanque», «Punto de distribución»…
  elija: string;                    // «la planta», «el tanque», «el punto de distribución» (para «Elija …»)
  variables: VariableDef[];
  opciones: Opcion[];
};

const TIPOS_PUNTO: Record<string, { titulo: string; lugar: string; ayuda: string }> = {
  tanque: { titulo: "Tanques", lugar: "Tanque", ayuda: "Elija el tanque y escriba su medición. Un registro por tanque." },
  distribucion: { titulo: "Distribución", lugar: "Punto de distribución", ayuda: "Elija el punto de distribución y escriba su medición. Un registro por punto." },
  muestreo: { titulo: "Puntos de muestreo", lugar: "Punto de muestreo", ayuda: "Elija el punto de muestreo. Un registro por punto." },
  macromedicion: { titulo: "Macromedición", lugar: "Punto de macromedición", ayuda: "Elija el punto de macromedición. Un registro por punto." },
};
const TIPO_POR_DEFECTO = { titulo: "Por punto", lugar: "Punto", ayuda: "Elija el punto. Un registro por punto." };

/** Hasta 3 opciones: botones; más: lista desplegable. La regla es por número de opciones, no por el nombre del grupo. */
export const MAX_BOTONES = 3;
export const modoSelector = (n: number): "botones" | "lista" => (n <= MAX_BOTONES ? "botones" : "lista");

export function agrupar(def: FormularioDef): Tarjeta[] {
  const vars = [...def.variables].sort((a, b) => a.orden - b.orden);
  const out: Omit<Tarjeta, "numero">[] = [];
  const porPlanta = vars.filter((v) => v.alcance === "por_planta");
  const ambas = vars.filter((v) => v.alcance === "ambas_plantas");
  if (porPlanta.length)
    out.push({ id: "planta", grupo: "planta", clase: "planta", titulo: "Por planta", ayuda: "Elija la planta para la que va a registrar.", etiquetaLugar: "Planta", elija: "la planta", variables: porPlanta, opciones: def.plantas.map((p) => ({ codigo: p.codigo, nombre: p.nombre })) });
  if (ambas.length)
    out.push({ id: "ambas", grupo: "ambas", clase: "ambas", titulo: "Para las dos plantas", ayuda: "Una sola medición, sin importar la planta.", etiquetaLugar: "", elija: "", variables: ambas, opciones: [] });
  const nombres = new Map(def.puntos.map((p) => [p.codigo, p.nombre]));
  const tipos: string[] = [];
  for (const v of vars) if (v.alcance === "por_punto") { const t = v.tipo_punto ?? "punto"; if (!tipos.includes(t)) tipos.push(t); }
  for (const t of tipos) {
    const delTipo = vars.filter((v) => v.alcance === "por_punto" && (v.tipo_punto ?? "punto") === t);
    const codigos: string[] = [];
    for (const v of delTipo) for (const c of v.puntos ?? []) if (!codigos.includes(c)) codigos.push(c);     // unión conservando el orden que dio el servidor
    const txt = TIPOS_PUNTO[t] ?? TIPO_POR_DEFECTO;
    out.push({ id: `punto:${t}`, grupo: t, clase: "punto", titulo: txt.titulo, ayuda: txt.ayuda, etiquetaLugar: txt.lugar, elija: `el ${txt.lugar.toLowerCase()}`, variables: delTipo, opciones: codigos.map((c) => ({ codigo: c, nombre: nombres.get(c) ?? c })) });
  }
  return out.map((t, i) => ({ ...t, numero: i + 1 }));
}

/** Clave del texto escrito: «codigo@lugar» (lugar vacío en «Para las dos plantas»). Cambiar de lugar no pierde lo escrito en el otro. */
export const claveTexto = (v: VariableDef, lugar: string) => `${v.codigo}@${lugar}`;
/** Clave de un intento de envío: una por tarjeta y lugar. */
export const claveIntento = (t: Tarjeta, lugar: string) => `${t.grupo}|${lugar}`;
const sanear = (s: string) => s.replace(/[^A-Za-z0-9_-]/g, "_");
/** Clave de envío del servidor (8–80 caracteres [A-Za-z0-9_-]): «<base>-<grupo>-<lugar>». Un reintento con la misma clave devuelve el mismo envío sin duplicar. */
export const claveEnvioTarjeta = (base: string, t: Tarjeta, lugar: string) => `${sanear(base)}-${sanear(t.grupo)}-${sanear(lugar || "todas")}`.slice(0, 80);

/** Nombre del lugar para mostrar. */
export const nombreLugar = (t: Tarjeta, lugar: string) => (t.clase === "ambas" ? "las dos plantas" : t.opciones.find((o) => o.codigo === lugar)?.nombre ?? lugar);

/** Etiqueta de un campo: por planta «Turbiedad de salida Huaricha» (como Entrada); por punto «Cloro libre · Tanque de 2.000 m³». */
export function etiquetaCampo(t: Tarjeta, v: VariableDef, lugar: string): string {
  if (t.clase === "planta") return `${v.nombre} ${nombreLugar(t, lugar)}`;
  if (t.clase === "punto") return `${v.nombre} · ${nombreLugar(t, lugar)}`;
  return v.nombre;
}

/** ¿La tarjeta tiene algo escrito para ese lugar? */
export const conDatos = (t: Tarjeta, lugar: string, textos: Record<string, string>) => t.variables.some((v) => (textos[claveTexto(v, lugar)] ?? "").trim() !== "");

/** Cuerpo de la llamada `registrar` de UNA tarjeta: solo las variables de ese grupo y ese lugar. */
export function cuerpoTarjeta(def: FormularioDef, t: Tarjeta, lugar: string, textos: Record<string, string>, hora: string): Omit<RegistrarCuerpo, "clave_envio"> {
  const valores: { variable: string; valor: number }[] = [];
  if (!tieneLugar(t, lugar)) return { formulario: def.formulario.clave, planta: null, punto: null, hora, valores };      // sin lugar elegido no sale ningún valor
  for (const v of t.variables) {
    const r = interpretarNumero(textos[claveTexto(v, lugar)] ?? "");
    if (r.tipo === "ok") valores.push({ variable: v.codigo, valor: r.valor });
  }
  return { formulario: def.formulario.clave, planta: t.clase === "planta" ? lugar : null, punto: t.clase === "punto" ? lugar : null, hora, valores };
}

/** Lugar inicial de cada tarjeta. La PLANTA queda preseleccionada (la guardada en el borrador o la primera, como en Entrada); cualquier lugar se puede QUITAR después («»). Los PUNTOS arrancan SIN lugar elegido («»):
 *  solo se restaura el que traiga un borrador (el que se había elegido o, si no, el primero con texto escrito) y siempre que siga existiendo. «Para las dos plantas» no tiene lugar. */
export function lugarInicial(t: Tarjeta, textos: Record<string, string>, preferido?: string | null): string {
  if (t.clase === "ambas") return "";
  const existe = (c?: string | null) => !!c && t.opciones.some((o) => o.codigo === c);
  if (preferido === "") return "";            // el borrador dice que la persona había QUITADO el lugar: se respeta (lo escrito sigue guardado, oculto)
  if (existe(preferido)) return preferido as string;
  const conTexto = t.opciones.find((o) => conDatos(t, o.codigo, textos))?.codigo;
  if (conTexto) return conTexto;
  return t.clase === "planta" ? t.opciones[0]?.codigo ?? "" : "";
}

/** ¿La tarjeta puede enviarse? Solo con un lugar elegido (las dos plantas no necesitan lugar). Una tarjeta SIN lugar se ignora: no cuenta como tarjeta con datos ni da error. */
export const tieneLugar = (t: Tarjeta, lugar: string) => t.clase === "ambas" || (lugar !== "" && t.opciones.some((o) => o.codigo === lugar));

/** Texto cuando todavía no se eligió el lugar: «Elija el tanque para digitar cloro libre». Sale del dato (tipo de punto y nombres de las variables). */
const minuscula = (s: string) => s.charAt(0).toLowerCase() + s.slice(1);       // «Cloro libre» → «cloro libre»; «pH de salida» queda igual
export const textoElegirLugar = (t: Tarjeta) => `Elija ${t.elija} para digitar ${t.variables.map((v) => minuscula(v.nombre)).join(" y ")}`;
