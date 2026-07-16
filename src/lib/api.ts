import { supabase, FUNCTIONS_URL } from "./supabase";

async function token(): Promise<string> {
  const { data } = await supabase.auth.getSession();
  const t = data.session?.access_token;
  if (!t) throw new Error("Sesión expirada. Vuelve a iniciar sesión.");
  return t;
}

async function call<T>(fn: string, qs: Record<string, string>): Promise<T> {
  const url = new URL(`${FUNCTIONS_URL}/${fn}`);
  Object.entries(qs).forEach(([k, v]) => url.searchParams.set(k, v));
  const res = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${await token()}` },
  });
  const body = await res.json();
  if (!res.ok) throw new Error(body.error ?? "Error en la consulta.");
  return body as T;
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
};

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

export const api = {
  buscar: (q: string) =>
    call<{ resultados: PredioResumen[] }>("geoportal-buscar", { q }),
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
  rutasLista: () =>
    call<{ rutas: RutaItem[] }>("geoportal-rutas-lista", {}),
  ruta: (ruta: string) =>
    call<{ ruta: DetalleRuta }>("geoportal-ruta", { ruta }),
  admin: {
    perfil: () =>
      call<{ es_admin: boolean }>("geoportal-admin", { accion: "perfil" }),
    listar: () =>
      call<{ usuarios: UsuarioAdmin[] }>("geoportal-admin", { accion: "listar" }),
    guardar: (u: {
      email: string;
      nombre?: string;
      rol: string;
      activo: boolean;
      password?: string;
    }) =>
      callPost<{ ok: boolean; auth: string }>(
        "geoportal-admin",
        { accion: "guardar" },
        u,
      ),
  },
};
