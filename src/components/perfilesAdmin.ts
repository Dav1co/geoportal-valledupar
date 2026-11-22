// Administración por geoportal (encargo v2 del 22-nov-2026, §0). Lógica PURA, sin React ni red: perfil ↔ casillas, el resumen antes de guardar, el envío y la verificación.
// Administración solo decide a qué geoportal entra cada persona y con qué perfil general; lo de adentro lo decide el supervisor en el Personal de cada geoportal.
// No hay roles nuevos en la base: un perfil es solo el juego de casillas que se envía. Se envían SIEMPRE todas las casillas que el servidor lista, como booleano
// explícito (la Edge geoportal-admin reenvía cada una; el SQL ya no conserva nada en silencio con su coalesce). El error del 22-nov venía de un borrador a medias.
import type { UsuarioAdmin } from "../lib/api";

export const CASILLAS = [
  "explorar", "focalizacion", "comercial", "rutas", "dashboard",
  "campo", "dashboard_campo", "acta", "dashboard_acta", "analisis_contrato",
  "registro_tecnico", "dashboard_tecnico", "dashboard_redes",
  "aseo", "dashboard_aseo",
] as const;
export type Casilla = (typeof CASILLAS)[number];
export type Casillas = Record<Casilla, boolean>;
export type Geoportal = "comercial" | "tecnica" | "aseo";

/** Nombre de cada casilla en pantalla (resumen, «Personalizado» y «Ajustes avanzados»). */
export const NOMBRE_CASILLA: Record<Casilla, string> = {
  explorar: "Explorar", focalizacion: "Focalización", comercial: "Comercial", rutas: "Rutas", dashboard: "Dashboard",
  campo: "Formatos de campo", dashboard_campo: "Supervisor de reportes de campo", acta: "Reportar posible pérdida (acta)", dashboard_acta: "Supervisor de actas",
  analisis_contrato: "Análisis de contrato (datos personales)",
  registro_tecnico: "Registro técnico", dashboard_tecnico: "Dashboard PTAP (plantas)", dashboard_redes: "Dashboard distribución",
  aseo: "Interventoría de aseo", dashboard_aseo: "Supervisor de aseo",
};
export const MODOS: Casilla[] = ["explorar", "focalizacion", "comercial", "rutas", "dashboard"];
/** Las casillas de cada geoportal. Los modos del geovisor son de Comercial pero se marcan sueltos (§0.2); los «formularios de campo» son el resto. */
export const CASILLAS_DE: Record<Geoportal, Casilla[]> = {
  comercial: [...MODOS, "campo", "dashboard_campo", "acta", "dashboard_acta", "analisis_contrato"],
  tecnica: ["registro_tecnico", "dashboard_tecnico", "dashboard_redes"],
  aseo: ["aseo", "dashboard_aseo"],
};
export const FORMULARIOS_COMERCIAL: Casilla[] = ["campo", "dashboard_campo", "acta", "dashboard_acta", "analisis_contrato"];

// ---------- Perfiles (§0.2, §0.3, §0.4) ----------
export type PerfilFormularios = "sin" | "operario" | "supervisor";
export type PerfilTecnica = "sin" | "operario" | "sup_plantas" | "sup_distribucion" | "sup_ambas";
export type PerfilAseo = "sin" | "auditor" | "supervisor";
/** Lo que está encendido en cada perfil; todo lo demás de ese grupo va en falso. */
export const PERFILES_FORMULARIOS: Record<PerfilFormularios, { nombre: string; casillas: Casilla[] }> = {
  sin: { nombre: "Sin formularios", casillas: [] },
  operario: { nombre: "Operario comercial", casillas: ["campo", "acta", "analisis_contrato"] },
  supervisor: { nombre: "Supervisor comercial", casillas: ["campo", "dashboard_campo", "acta", "dashboard_acta", "analisis_contrato"] },
};
export const PERFILES_TECNICA: Record<PerfilTecnica, { nombre: string; casillas: Casilla[] }> = {
  sin: { nombre: "Sin acceso", casillas: [] },
  operario: { nombre: "Operario técnico", casillas: ["registro_tecnico"] },
  sup_plantas: { nombre: "Supervisor de plantas", casillas: ["registro_tecnico", "dashboard_tecnico"] },
  sup_distribucion: { nombre: "Supervisor de distribución", casillas: ["registro_tecnico", "dashboard_redes"] },
  sup_ambas: { nombre: "Supervisor de plantas y distribución", casillas: ["registro_tecnico", "dashboard_tecnico", "dashboard_redes"] },
};
export const PERFILES_ASEO: Record<PerfilAseo, { nombre: string; casillas: Casilla[] }> = {
  sin: { nombre: "Sin acceso", casillas: [] },
  auditor: { nombre: "Auditor de aseo", casillas: ["aseo"] },
  supervisor: { nombre: "Supervisor de aseo", casillas: ["aseo", "dashboard_aseo"] },
};
const GRUPO: Record<"formularios" | "tecnica" | "aseo", Casilla[]> = { formularios: FORMULARIOS_COMERCIAL, tecnica: CASILLAS_DE.tecnica, aseo: CASILLAS_DE.aseo };

// ---------- Leer lo de hoy ----------
/** Las casillas que el servidor YA lista (§0.10, R11): las que vienen como booleano en algún usuario. Las demás se muestran «no disponible» y no se envían. */
export function disponibles(usuarios: UsuarioAdmin[]): Set<Casilla> {
  return new Set(CASILLAS.filter((c) => usuarios.some((u) => typeof (u as Record<string, unknown>)[`ver_${c}`] === "boolean")));
}
/** Las casillas de un usuario tal como las lista el servidor (lo que no llega, en falso). */
export function casillasDe(u: UsuarioAdmin): Casillas {
  return Object.fromEntries(CASILLAS.map((c) => [c, (u as Record<string, unknown>)[`ver_${c}`] === true])) as Casillas;
}
export const sinNada = (): Casillas => Object.fromEntries(CASILLAS.map((c) => [c, false])) as Casillas;

/** ¿Qué perfil calza EXACTO con las casillas de un grupo? null = «Personalizado». */
function calza<P extends string>(c: Casillas, grupo: Casilla[], perfiles: Record<P, { casillas: Casilla[] }>): P | null {
  for (const [p, def] of Object.entries(perfiles) as [P, { casillas: Casilla[] }][]) if (grupo.every((x) => c[x] === def.casillas.includes(x))) return p;
  return null;
}
export type Reconocido = { formularios: PerfilFormularios | null; tecnica: PerfilTecnica | null; aseo: PerfilAseo | null };
/** Cada geoportal se reconoce por separado (§4 de la v1). null = «Personalizado» (no calza con ningún perfil). */
export function reconocer(c: Casillas): Reconocido {
  return { formularios: calza(c, GRUPO.formularios, PERFILES_FORMULARIOS), tecnica: calza(c, GRUPO.tecnica, PERFILES_TECNICA), aseo: calza(c, GRUPO.aseo, PERFILES_ASEO) };
}

// ---------- Escoger un perfil (cambia SOLO su grupo) ----------
function poner(c: Casillas, grupo: Casilla[], encendidas: Casilla[]): Casillas {
  const n = { ...c };
  for (const x of grupo) n[x] = encendidas.includes(x);
  return n;
}
export const aplicarFormularios = (c: Casillas, p: PerfilFormularios) => poner(c, GRUPO.formularios, PERFILES_FORMULARIOS[p].casillas);
export const aplicarTecnica = (c: Casillas, p: PerfilTecnica) => poner(c, GRUPO.tecnica, PERFILES_TECNICA[p].casillas);
export const aplicarAseo = (c: Casillas, p: PerfilAseo) => poner(c, GRUPO.aseo, PERFILES_ASEO[p].casillas);
/** Un modo del geovisor (casilla suelta que marca el administrador). */
export const ponerModo = (c: Casillas, modo: Casilla, v: boolean): Casillas => (MODOS.includes(modo) ? { ...c, [modo]: v } : c);
/** «Ajustes avanzados» de un renglón «Personalizado» (R6): una casilla de ESE geoportal. */
export const ponerCasilla = (c: Casillas, g: Geoportal, x: Casilla, v: boolean): Casillas => (CASILLAS_DE[g].includes(x) ? { ...c, [x]: v } : c);
/** ¿Se puede escoger el perfil? No, si necesita una casilla que el servidor todavía no lista (R11). */
export const perfilDisponible = (encendidas: Casilla[], disp: Set<Casilla>) => encendidas.every((x) => disp.has(x));

// ---------- Nombres para la lista y el resumen ----------
export const modosDe = (c: Casillas) => MODOS.filter((m) => c[m]).map((m) => NOMBRE_CASILLA[m]);
/** El renglón de Comercial en palabras: «Supervisor comercial (Explorar, Rutas)», «Consulta (Explorar)», «Operario comercial», «Sin acceso» o «Personalizado». */
export function textoComercial(c: Casillas): string {
  const f = reconocer(c).formularios, modos = modosDe(c);
  const entre = modos.length ? ` (${modos.join(", ")})` : "";
  if (f === null) return "Personalizado" + entre;
  if (f === "sin") return modos.length ? `Consulta${entre}` : "Sin acceso";
  return PERFILES_FORMULARIOS[f].nombre + entre;
}
export function textoTecnica(c: Casillas): string { const p = reconocer(c).tecnica; return p === null ? "Personalizado" : PERFILES_TECNICA[p].nombre; }
export function textoAseo(c: Casillas): string { const p = reconocer(c).aseo; return p === null ? "Personalizado" : PERFILES_ASEO[p].nombre; }
/** La línea corta de la lista de usuarios (§6): solo los geoportales con acceso; «Administrador» o «Sin acceso» si corresponde. */
export function lineaUsuario(u: UsuarioAdmin): string {
  if (u.rol === "admin") return "Administrador";
  const c = casillasDe(u), partes: string[] = [];
  const com = textoComercial(c), tec = textoTecnica(c), ase = textoAseo(c);
  if (com !== "Sin acceso") partes.push(`Comercial: ${com}`);
  if (tec !== "Sin acceso") partes.push(`Técnica: ${tec}`);
  if (ase !== "Sin acceso") partes.push(`Aseo: ${ase}`);
  return partes.length ? partes.join(" · ") : "Sin acceso";
}
/** ¿Algún geoportal de este usuario está «Personalizado»? (para la marca de la lista y el conteo del informe) */
export function esPersonalizado(c: Casillas): Geoportal[] {
  const r = reconocer(c), g: Geoportal[] = [];
  if (r.formularios === null) g.push("comercial");
  if (r.tecnica === null) g.push("tecnica");
  if (r.aseo === null) g.push("aseo");
  return g;
}

// ---------- Resumen antes de guardar (§0.6, R7) ----------
export type Datos = { nombre: string; horario: string; dias: string; rol: string };
export type Cambio = { casilla: Casilla; geoportal: Geoportal; nombre: string; enciende: boolean };
export type Resumen = {
  /** Por geoportal: «Comercial: Supervisor comercial → Consulta (Explorar)»; solo los que cambian. */
  renglones: { geoportal: Geoportal; antes: string; despues: string }[];
  /** Lo que se apaga (rojo) y lo que se enciende (verde), casilla por casilla. */
  cambios: Cambio[];
  /** Nombre, rol, horario y días que cambian. */
  datos: { campo: keyof Datos; antes: string; despues: string }[];
  /** Avisos que el resumen debe destacar: análisis de contrato (datos personales) y modos del geovisor encendidos. */
  destacados: string[];
  vacio: boolean;
};
const TEXTO_HORARIO: Record<string, string> = { laboral: "Laboral (7:50–18:00)", extendido: "Extendido (7:00–22:00)", sin_restriccion: "Sin restricción horaria" };
const TEXTO_DIAS: Record<string, string> = { habiles: "Lunes a viernes", todos: "Todos los días" };
const TEXTO_ROL: Record<string, string> = { admin: "Administrador", consulta: "Usuario (por geoportal)" };
const geoDe = (x: Casilla): Geoportal => (CASILLAS_DE.tecnica.includes(x) ? "tecnica" : CASILLAS_DE.aseo.includes(x) ? "aseo" : "comercial");
export function resumen(antes: Casillas, despues: Casillas, dAntes: Datos, dDespues: Datos, disp: Set<Casilla>): Resumen {
  const texto: Record<Geoportal, (c: Casillas) => string> = { comercial: textoComercial, tecnica: textoTecnica, aseo: textoAseo };
  const renglones = (["comercial", "tecnica", "aseo"] as Geoportal[])
    .filter((g) => CASILLAS_DE[g].some((x) => disp.has(x) && antes[x] !== despues[x]))
    .map((g) => ({ geoportal: g, antes: texto[g](antes), despues: texto[g](despues) }));
  const cambios = CASILLAS.filter((x) => disp.has(x) && antes[x] !== despues[x]).map((x) => ({ casilla: x, geoportal: geoDe(x), nombre: NOMBRE_CASILLA[x], enciende: despues[x] }));
  const datos: Resumen["datos"] = [];
  if (dAntes.nombre.trim() !== dDespues.nombre.trim()) datos.push({ campo: "nombre", antes: dAntes.nombre.trim() || "(sin nombre)", despues: dDespues.nombre.trim() || "(sin nombre)" });
  if (dAntes.rol !== dDespues.rol) datos.push({ campo: "rol", antes: TEXTO_ROL[dAntes.rol] ?? dAntes.rol, despues: TEXTO_ROL[dDespues.rol] ?? dDespues.rol });
  if (dAntes.horario !== dDespues.horario) datos.push({ campo: "horario", antes: TEXTO_HORARIO[dAntes.horario] ?? dAntes.horario, despues: TEXTO_HORARIO[dDespues.horario] ?? dDespues.horario });
  if (dAntes.dias !== dDespues.dias) datos.push({ campo: "dias", antes: TEXTO_DIAS[dAntes.dias] ?? dAntes.dias, despues: TEXTO_DIAS[dDespues.dias] ?? dDespues.dias });
  const destacados: string[] = [];
  if (cambios.some((x) => x.casilla === "analisis_contrato" && x.enciende)) destacados.push("Recibe el Análisis de contrato: verá el nombre y el teléfono de los suscriptores.");
  const modosNuevos = cambios.filter((x) => x.enciende && MODOS.includes(x.casilla)).map((x) => x.nombre);
  if (modosNuevos.length) destacados.push(`Entra al mapa comercial (geovisor): ${modosNuevos.join(", ")}.`);
  return { renglones, cambios, datos, destacados, vacio: cambios.length === 0 && datos.length === 0 };
}

// ---------- Envío y verificación (§5 de la v1, §0.7) ----------
export type EnvioPermisos = { email: string; horario: string; dias: string; explorar: boolean; focalizacion: boolean; comercial: boolean; rutas: boolean; dashboard: boolean } & Partial<Casillas>;
/** El cuerpo de la ruta `permisos`: TODAS las casillas que el servidor lista, como booleano explícito; ninguna que no liste (R11). Los 5 modos van siempre (la Edge los exige). */
export function envio(email: string, c: Casillas, horario: string, dias: string, disp: Set<Casilla>): EnvioPermisos {
  const e: EnvioPermisos = { email, horario, dias, explorar: c.explorar === true, focalizacion: c.focalizacion === true, comercial: c.comercial === true, rutas: c.rutas === true, dashboard: c.dashboard === true };
  for (const x of CASILLAS) if (disp.has(x)) e[x] = c[x] === true;
  return e;
}
/** Compara lo enviado con lo que el servidor devuelve al releer (`listar`): cada casilla, y el nombre, el rol, el horario, los días y si está activo. Devuelve lo que NO quedó. */
export function verificar(email: string, c: Casillas, d: Datos & { activo?: boolean }, disp: Set<Casilla>, lista: UsuarioAdmin[], opciones: { nombre?: boolean } = {}): string[] {
  const u = lista.find((x) => x.email === email.trim().toLowerCase());
  if (!u) return ["el usuario no aparece en la lista"];
  const leido = casillasDe(u), faltas: string[] = [];
  for (const x of CASILLAS) if ((MODOS.includes(x) || disp.has(x)) && leido[x] !== c[x]) faltas.push(`${NOMBRE_CASILLA[x]} (${c[x] ? "encender" : "apagar"})`);
  if (u.rol !== d.rol) faltas.push(`rol (${TEXTO_ROL[d.rol] ?? d.rol})`);
  if (u.rol !== "admin" && (u.horario ?? "laboral") !== d.horario) faltas.push(`horario (${TEXTO_HORARIO[d.horario] ?? d.horario})`);
  if (u.rol !== "admin" && (u.dias ?? "habiles") !== d.dias) faltas.push(`días (${TEXTO_DIAS[d.dias] ?? d.dias})`);
  if (opciones.nombre && (u.nombre ?? "").trim() !== d.nombre.trim()) faltas.push("nombre");
  if (typeof d.activo === "boolean" && u.activo !== d.activo) faltas.push(d.activo ? "activar la cuenta" : "desactivar la cuenta");
  return faltas;
}

// ---------- Avisos de horario (los de siempre; no cambian nada) ----------
/** Quien trabaja de noche o en fin de semana (campo, acta, aseo, Técnica) con horario laboral o días hábiles queda cortado fuera de ese horario. */
export function avisoHorario(c: Casillas, horario: string, dias: string): string | null {
  if (horario === "sin_restriccion" && dias === "todos") return null;
  const areas = [
    ...(c.campo || c.dashboard_campo || c.acta || c.dashboard_acta ? ["los formularios de campo"] : []),
    ...(c.registro_tecnico || c.dashboard_tecnico || c.dashboard_redes ? ["Técnica (opera todos los días a cualquier hora)"] : []),
    ...(c.aseo || c.dashboard_aseo ? ["Aseo (hay turnos de madrugada y de noche)"] : []),
  ];
  if (!areas.length) return null;
  return `Con el horario ${(TEXTO_HORARIO[horario] ?? horario).toLowerCase()} y ${(TEXTO_DIAS[dias] ?? dias).toLowerCase()}, esta persona no podrá trabajar fuera de ese horario en ${areas.join(", ")}. Si trabaja de noche o en fin de semana, elija «Sin restricción horaria» y «Todos los días». El horario no se cambia solo.`;
}
