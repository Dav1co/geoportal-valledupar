// Geometría del trazador de rutas.
//
// Todo ocurre en el navegador: se recibe la ruta con sus puntos y una
// polilínea dibujada a mano, y se devuelve la numeración propuesta. No
// se escribe en la base — es una propuesta que sale del geoportal.
//
// PROYECCIÓN. Una ruta abarca ~1,5 km de radio, así que basta una
// equirectangular local: metros = grados × 111.320, con cos(lat) en X.
// El error a esa escala es inferior al 0,1 %, dos órdenes de magnitud
// por debajo del radio del corredor (15 m por defecto). Trigonometría
// esférica completa sería precisión que nadie puede usar.

export type PuntoRuta = {
  orden: number;      // consecutivo ACTUAL, tal como viene de la base
  id: number;
  contrato: string;
  x: number;          // longitud
  y: number;          // latitud
  m: number;          // metros al punto anterior en el orden actual
};

export type Vertice = { x: number; y: number };

export type Capturado = {
  contrato: string;
  id: number;
  x: number;
  y: number;
  consecutivoActual: number;
  consecutivoNuevo: number;
  tipo: "unico" | "agrupado";
  grupo: number;          // índice del grupo de coordenada
  distanciaLinea: number; // metros a la polilínea
  abscisa: number;        // metros recorridos sobre la línea hasta su proyección
};

export type ResultadoTrazado = {
  capturados: Capturado[];
  noCapturados: PuntoRuta[];   // tienen geometría, la línea no los tocó
  longitudLinea: number;       // metros
};

const GRADO_M = 111320;

/** Proyecta grados a metros locales, con el centro de la ruta como origen. */
export function proyector(puntos: { x: number; y: number }[]) {
  const latRef = puntos.length
    ? puntos.reduce((s, p) => s + p.y, 0) / puntos.length
    : 10.46; // Valledupar
  const kx = GRADO_M * Math.cos((latRef * Math.PI) / 180);
  return {
    aMetros: (p: { x: number; y: number }) => ({ x: p.x * kx, y: p.y * GRADO_M }),
  };
}

/** Distancia de un punto al segmento AB, y qué fracción del segmento recorre. */
function aSegmento(
  p: { x: number; y: number },
  a: { x: number; y: number },
  b: { x: number; y: number },
) {
  const vx = b.x - a.x, vy = b.y - a.y;
  const largo2 = vx * vx + vy * vy;
  // Segmento degenerado (dos clics en el mismo sitio): distancia al vértice.
  if (largo2 === 0) return { dist: Math.hypot(p.x - a.x, p.y - a.y), t: 0 };
  let t = ((p.x - a.x) * vx + (p.y - a.y) * vy) / largo2;
  t = Math.max(0, Math.min(1, t));   // se recorta a los extremos del segmento
  const px = a.x + t * vx, py = a.y + t * vy;
  return { dist: Math.hypot(p.x - px, p.y - py), t };
}

/** Longitud total de la polilínea, en metros. */
export function longitudLinea(linea: Vertice[]): number {
  if (linea.length < 2) return 0;
  const pr = proyector(linea);
  let total = 0;
  for (let i = 1; i < linea.length; i++) {
    const a = pr.aMetros(linea[i - 1]), b = pr.aMetros(linea[i]);
    total += Math.hypot(b.x - a.x, b.y - a.y);
  }
  return total;
}

/**
 * Captura por corredor y numera.
 *
 * REGLA DE AGRUPACIÓN: los predios que comparten coordenada exacta son la
 * misma puerta física (edificio, conjunto). En esta base eso NO es un caso
 * borde: en una ruta típica el 52 % de los predios comparte punto con otro
 * y hay hasta 46 en uno solo. Por eso:
 *   · se agrupan ANTES de numerar, y el grupo entero recibe un consecutivo;
 *   · si al menos un miembro cae dentro del corredor, entra el grupo entero.
 *     Partir un edificio daría dos consecutivos para una misma puerta.
 */
export function trazar(
  puntos: PuntoRuta[],
  linea: Vertice[],
  radioM: number,
): ResultadoTrazado {
  if (linea.length < 2) {
    return { capturados: [], noCapturados: [...puntos], longitudLinea: 0 };
  }

  const pr = proyector([...puntos, ...linea]);
  const lineaM = linea.map(pr.aMetros);

  // Abscisa acumulada del inicio de cada segmento.
  const acum: number[] = [0];
  for (let i = 1; i < lineaM.length; i++) {
    acum[i] = acum[i - 1] + Math.hypot(
      lineaM[i].x - lineaM[i - 1].x, lineaM[i].y - lineaM[i - 1].y);
  }
  const largoTotal = acum[acum.length - 1];

  // Cada predio contra la línea: distancia mínima y dónde proyecta.
  const medidos = puntos.map((p) => {
    const pm = pr.aMetros(p);
    let mejor = Infinity, abscisa = 0;
    for (let i = 1; i < lineaM.length; i++) {
      const { dist, t } = aSegmento(pm, lineaM[i - 1], lineaM[i]);
      if (dist < mejor) {
        mejor = dist;
        abscisa = acum[i - 1] + t * (acum[i] - acum[i - 1]);
      }
    }
    return { p, dist: mejor, abscisa };
  });

  // Agrupar por coordenada exacta. La clave es el texto de las dos
  // coordenadas: si vienen del mismo origen son idénticas bit a bit.
  const grupos = new Map<string, typeof medidos>();
  for (const m of medidos) {
    const k = `${m.p.x},${m.p.y}`;
    const g = grupos.get(k);
    if (g) g.push(m); else grupos.set(k, [m]);
  }

  // Un grupo entra si CUALQUIERA de sus miembros cae en el corredor.
  // Su abscisa es la del miembro que proyecta más cerca del inicio, para
  // que el edificio se numere donde el lector lo encuentra primero.
  const dentro: { miembros: typeof medidos; abscisa: number; dist: number }[] = [];
  const fuera: PuntoRuta[] = [];
  for (const g of grupos.values()) {
    const alguno = g.some((m) => m.dist <= radioM);
    if (alguno) {
      dentro.push({
        miembros: g,
        abscisa: Math.min(...g.map((m) => m.abscisa)),
        dist: Math.min(...g.map((m) => m.dist)),
      });
    } else {
      for (const m of g) fuera.push(m.p);
    }
  }

  // Orden: abscisa sobre la línea. Los que caen a lado y lado a la misma
  // altura empatan, y se desempatan por distancia al inicio de la línea.
  dentro.sort((a, b) => a.abscisa - b.abscisa || a.dist - b.dist);

  const capturados: Capturado[] = [];
  dentro.forEach((g, i) => {
    const tipo = g.miembros.length > 1 ? "agrupado" : "unico";
    for (const m of g.miembros) {
      capturados.push({
        contrato: m.p.contrato,
        id: m.p.id,
        x: m.p.x,
        y: m.p.y,
        consecutivoActual: m.p.orden,
        consecutivoNuevo: i + 1,   // el grupo entero comparte el consecutivo
        tipo,
        grupo: i,
        distanciaLinea: Math.round(m.dist * 10) / 10,
        abscisa: Math.round(m.abscisa),
      });
    }
  });

  return { capturados, noCapturados: fuera, longitudLinea: Math.round(largoTotal) };
}

/**
 * Renumera tras un ajuste manual, respetando el orden de los grupos que
 * quedan y saltando los excluidos. Se numera por GRUPO, no por predio.
 */
export function renumerar(capturados: Capturado[], excluidos: Set<string>): Capturado[] {
  const vivos = capturados.filter((c) => !excluidos.has(c.contrato));
  const ordenGrupos: number[] = [];
  for (const c of vivos) if (!ordenGrupos.includes(c.grupo)) ordenGrupos.push(c.grupo);
  const nuevo = new Map(ordenGrupos.map((g, i) => [g, i + 1]));
  // Un grupo puede quedar con un solo miembro tras excluir a los demás:
  // deja de ser "agrupado" y pasa a "unico".
  const cuenta = new Map<number, number>();
  for (const c of vivos) cuenta.set(c.grupo, (cuenta.get(c.grupo) ?? 0) + 1);
  return vivos.map((c) => ({
    ...c,
    consecutivoNuevo: nuevo.get(c.grupo) ?? 0,
    tipo: (cuenta.get(c.grupo) ?? 1) > 1 ? "agrupado" : "unico",
  }));
}

/** Mueve un grupo una posición arriba o abajo en el orden. */
export function moverGrupo(capturados: Capturado[], grupo: number, dir: -1 | 1): Capturado[] {
  const orden: number[] = [];
  for (const c of capturados) if (!orden.includes(c.grupo)) orden.push(c.grupo);
  const i = orden.indexOf(grupo);
  const j = i + dir;
  if (i < 0 || j < 0 || j >= orden.length) return capturados;
  [orden[i], orden[j]] = [orden[j], orden[i]];
  const pos = new Map(orden.map((g, k) => [g, k]));
  return [...capturados].sort(
    (a, b) => (pos.get(a.grupo) ?? 0) - (pos.get(b.grupo) ?? 0),
  );
}

/** CSV con las TRES columnas exactas del entregable. */
export function aCSV(capturados: Capturado[]): string {
  const filas = capturados.map(
    (c) => `${c.contrato},${c.consecutivoNuevo},${c.tipo === "agrupado" ? "agrupado" : "único"}`,
  );
  return ["contrato,consecutivo_nuevo_ruta,tipo", ...filas].join("\n");
}
