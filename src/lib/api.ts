import { supabase, FUNCTIONS_URL } from "./supabase";

async function token(): Promise<string> {
  const { data } = await supabase.auth.getSession();
  const t = data.session?.access_token;
  if (!t) throw new Error("Sesión expirada. Vuelve a iniciar sesión.");
  return t;
}

/** Error de una llamada al servidor, con el código HTTP (0 = no hubo respuesta: sin red o sin tiempo). Sigue siendo un Error normal para quien solo lee `message`. */
export class ErrorApi extends Error {
  status: number;
  constructor(mensaje: string, status: number) {
    super(mensaje);
    this.name = "ErrorApi";
    this.status = status;
  }
}

async function call<T>(fn: string, qs: Record<string, string>, opciones?: { timeoutMs?: number }): Promise<T> {
  const url = new URL(`${FUNCTIONS_URL}/${fn}`);
  Object.entries(qs).forEach(([k, v]) => url.searchParams.set(k, v));
  const ctl = opciones?.timeoutMs ? new AbortController() : null;
  const reloj = ctl ? setTimeout(() => ctl.abort(), opciones!.timeoutMs) : null;
  try {
    let res: Response;
    try {
      res = await fetch(url.toString(), { headers: { Authorization: `Bearer ${await token()}` }, signal: ctl?.signal });
    } catch (e) {
      if (e instanceof Error && e.message.startsWith("Sesión expirada")) throw e;
      throw new ErrorApi(
        ctl?.signal.aborted ? "El servidor tardó demasiado en responder. Intente de nuevo." : "No se pudo conectar con el servidor. Revise su conexión e intente de nuevo.",
        0,
      );
    }
    let body: { error?: string } & Record<string, unknown>;
    try {
      body = await res.json();
    } catch {
      throw new ErrorApi(
        res.ok ? "El servidor respondió algo que no se pudo leer. Intente de nuevo." : `El servidor no está disponible en este momento (código ${res.status}). Intente de nuevo.`,
        ctl?.signal.aborted ? 0 : res.status,
      );
    }
    if (!res.ok) throw new ErrorApi(body.error ?? "Error en la consulta.", res.status);
    return body as T;
  } finally {
    if (reloj) clearTimeout(reloj);
  }
}

async function callPost<T>(
  fn: string,
  qs: Record<string, string>,
  body: unknown,
): Promise<T> {
  const url = new URL(`${FUNCTIONS_URL}/${fn}`);
  Object.entries(qs).forEach(([k, v]) => url.searchParams.set(k, v));
  const res = await fetch(url.toString(), {
    method: "POST",
    headers: {
      Authorization: `Bearer ${await token()}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const b = await res.json();
  if (!res.ok) throw new Error(b.error ?? "Error en la consulta.");
  return b as T;
}

export type PredioResumen = {
  id: number;
  cod_usuario: string | null;
  direccion: string | null;
  gps_x: number;
  gps_y: number;
};

export type MedidorResumen = {
  id: number;
  cod_usuario: string | null;
  serial_medidor: string | null;
  direccion: string | null;
  gps_x: number;
  gps_y: number;
};

export type ResumenApilado = {
  id: number;
  cod_usuario: string | null;
  direccion: string | null;
};

export type UsuarioAdmin = {
  email: string;
  nombre: string | null;
  rol: string;
  activo: boolean;
  creado_en: string;
  ver_explorar: boolean;
  ver_focalizacion: boolean;
  ver_comercial: boolean;
  ver_rutas: boolean;
  ver_dashboard: boolean;
  horario: string;
  dias: string;
  // Fase 2 (paquete técnico): solo llegan si el paquete SQL ya se aplicó; Administración detecta su presencia y, si faltan, se comporta como siempre.
  ver_registro_tecnico?: boolean;
  ver_dashboard_tecnico?: boolean;
};

/** Respuesta de geoportal-admin?accion=perfil (la misma que valida la sesión en useSession). */
export type PerfilResp = { es_admin: boolean; permisos?: { explorar: boolean; focalizacion: boolean; comercial: boolean; rutas: boolean; dashboard: boolean } };

export type RutaItem = { ruta: string; ciclo: string; predios: number };

export type PuntoRuta = {
  orden: number; id: number; contrato: string;
  x: number; y: number; m: number;
};
export type MetricasRuta = {
  predios: number; distancia_total: number;
  paso_min: number; paso_prom: number; paso_mediana: number;
  paso_p90: number; paso_p95: number; paso_max: number;
  largos: number; muy_largos: number; extremos: number;
};
export type DetalleRuta = {
  ruta: string;
  puntos: PuntoRuta[];
  metricas: MetricasRuta;
};

export type ExportaResp = {
  ok: boolean;
  total: number;
  limite: number;
  contratos: string[];
};

export type ExportaArgs = {
  ids?: number[];
  medicion?: string;
  facturacion?: string;
  consumo?: string;
  cartera?: string;
  ciclo?: string;
  barrio?: string;
  consumoMax?: string;
};

export type BarrioHallado = { id: number; nombre: string; caja: [number, number, number, number] };

export type EstadoPausa = { pausado: boolean; pausado_por: string | null; pausado_en: string | null; afectados: number };

export type ActivoAhora = { email: string; ultima: string; minutos: number; acciones: number; ip: string | null };
export type IngresoLog = { email: string; cuando: string; ip: string | null; resultado: string };
export type Accesos = { activos: ActivoAhora[]; ingresos: IngresoLog[] };

export const api = {
  exportarContratos: (args: ExportaArgs) =>
    callPost<ExportaResp>("geoportal-exportar", {}, args),
  buscar: (q: string) =>
    call<{ resultados: PredioResumen[] }>("geoportal-buscar", { q }),
  buscarMedidor: (q: string) =>
    call<{ resultados: MedidorResumen[] }>("geoportal-buscar-medidor", { q }),
  buscarDireccion: (q: string, fuente: string) =>
    call<{ resultados: PredioResumen[] }>("geoportal-buscar-direccion", { q, fuente }),
  detalle: (id: number) =>
    call<{ predio: Record<string, unknown> }>("geoportal-predio", {
      id: String(id),
    }),
  resumen: (ids: number[]) =>
    call<{ predios: ResumenApilado[] }>("geoportal-predio", {
      ids: ids.join(","),
    }),
  barrios: () =>
    call<{ barrios: string[] }>("geoportal-barrios", {}),
  buscarBarrio: (q: string) =>
    call<{ barrios: BarrioHallado[] }>("geoportal-buscar-barrio", { q }),
  causales: () =>
    call<{ causales: string[] }>("geoportal-causales", {}),
  bi: (vista: string, filtros?: Record<string, string>) =>
    callPost<{ datos: Record<string, unknown>[] }>("geoportal-bi", {}, { vista, filtros }),
  rutasLista: () =>
    call<{ rutas: RutaItem[] }>("geoportal-rutas-lista", {}),
  ruta: (ruta: string) =>
    call<{ ruta: DetalleRuta }>("geoportal-ruta", { ruta }),
  admin: {
    perfil: () =>
      call<PerfilResp>("geoportal-admin", { accion: "perfil" }, { timeoutMs: 20000 }),   // sin límite, un servidor que no responde dejaba la pantalla en «Cargando…» para siempre
    listar: () =>
      call<{ usuarios: UsuarioAdmin[] }>("geoportal-admin", { accion: "listar" }),
    pausa: () =>
      call<{ pausa: EstadoPausa }>("geoportal-admin", { accion: "pausa" }),
    accesos: (dias = 7) =>
      call<{ accesos: Accesos }>("geoportal-admin", { accion: "accesos", dias: String(dias) }),
    pausaSet: (pausar: boolean) =>
      callPost<{ pausa: EstadoPausa }>("geoportal-admin", { accion: "pausa_set" }, { pausar }),
    permisos: (p: {
      email: string;
      explorar: boolean;
      focalizacion: boolean;
      comercial: boolean;
      rutas: boolean;
      dashboard: boolean;
      horario: string;
      dias: string;
      registro_tecnico?: boolean;   // fase 2: si no se informa, el servidor deja el permiso como está
      dashboard_tecnico?: boolean;
    }) =>
      callPost<{ guardado: boolean }>(
        "geoportal-admin",
        { accion: "permisos" },
        p,
      ),
    guardar: (u: {
      email: string;
      nombre?: string;
      rol: string;
      activo: boolean;
      password?: string;
      perfil_tecnico?: "operador" | "supervisor";   // fase 2: alta o conversión en una sola operación
    }) =>
      callPost<{ ok: boolean; auth: string }>(
        "geoportal-admin",
        { accion: "guardar" },
        u,
      ),
  },
};
