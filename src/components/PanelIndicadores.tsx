// Panel inferior de indicadores: muestra conteos de lo visible en pantalla,
// respetando los filtros del modo Comercial. Cerrado por defecto.

export type StatsComercial = {
  disponible: boolean;
  total: number;
  conDeuda: number;
  sinMedidor: number;
  consumoAlto: number; // elevado + grandes
  medicion: Record<string, number>;      // "1"|"2"|"3"
  facturacion: Record<string, number>;   // "1"|"2"|"3"|"4"|"5"
  consumo: Record<string, number>;       // cero..grandes
  mora: Record<string, number>;          // al_dia..cronica
  ciclo: Record<string, number>;
  barrio: Record<string, number>;
  semaforo: Record<string, number>;
  edadMed: Record<string, number>;
  pago: Record<string, number>;
  causal: Record<string, number>;
  deudaTotal: number;
  conMedidor: number;
  porPromedio: number;
};

const fmt = (n: number) => n.toLocaleString("es-CO");

const ET_MEDICION: Record<string, string> = {
  "1": "Con medidor", "2": "Dañado", "3": "Sin medidor",
};
const ET_FACTURACION: Record<string, string> = {
  "1": "Leído", "2": "Por promedio", "3": "Suspendido", "4": "Cortado", "5": "Pago anticipado",
};
const ET_CONSUMO: Record<string, string> = {
  cero: "Cero (0)", muy_bajo: "Muy bajo (1–6)", normal: "Normal (7–17)",
  alto: "Alto (18–32)", muy_alto: "Muy alto (33–59)", elevado: "Elevado (60–500)",
  grandes: "Grandes (>500)",
};
const ORD_CONSUMO = ["cero", "muy_bajo", "normal", "alto", "muy_alto", "elevado", "grandes"];
const ET_MORA: Record<string, string> = {
  al_dia: "Al día", leve: "Leve (1–2)", media: "Media (3–8)",
  alta: "Alta (9–60)", cronica: "Crónica (>60)",
};
const ORD_MORA = ["al_dia", "leve", "media", "alta", "cronica"];

const ET_SEMAFORO: Record<string, string> = {
  entro_deuda: "Entró a deuda", aumento: "Aumentó", mantuvo: "Mantuvo",
  abono: "Abonó", normalizo: "Normalizó",
  normalizo_financiado: "Normalizó (financ.)", al_dia: "Al día",
};
const ORD_SEMAFORO = ["entro_deuda", "aumento", "mantuvo", "abono", "normalizo", "normalizo_financiado", "al_dia"];

const ET_EDAD: Record<string, string> = {
  nuevo: "Nuevo (<5 años)", medio: "Medio (5-10)", viejo: "Viejo (10-15)",
  muy_viejo: "Muy viejo (>15)", sin_fecha: "Sin fecha",
};
const ORD_EDAD = ["nuevo", "medio", "viejo", "muy_viejo", "sin_fecha"];

const ET_PAGO: Record<string, string> = {
  reciente: "Menos de 1 mes", m1_3: "1 a 3 meses", m3_6: "3 a 6 meses",
  m6_12: "6 a 12 meses", mas_1a: "Más de un año", nunca: "Nunca ha pagado",
};
const ORD_PAGO = ["reciente", "m1_3", "m3_6", "m6_12", "mas_1a", "nunca"];

const pesos = (n: number) => {
  if (n >= 1000000000) return "$" + (n / 1000000000).toFixed(2) + " MM";
  if (n >= 1000000) return "$" + (n / 1000000).toFixed(1) + " M";
  return "$" + n.toLocaleString("es-CO");
};

function Anillo({ pct, color, titulo, detalle }: {
  pct: number; color: string; titulo: string; detalle: string;
}) {
  return (
    <div className="pi-anillo">
      <svg viewBox="0 0 42 42" width="76" height="76">
        <circle cx="21" cy="21" r="15.9" fill="none" stroke="#e1e0d9" strokeWidth="5" />
        <circle cx="21" cy="21" r="15.9" fill="none" stroke={color} strokeWidth="5"
          strokeDasharray={`${pct} ${100 - pct}`} strokeDashoffset="25" strokeLinecap="round" />
        <text x="21" y="23.5" textAnchor="middle" fontSize="9" fontWeight="600" fill="#12263a">{pct}%</text>
      </svg>
      <div>
        <div className="pi-anillo-tit">{titulo}</div>
        <div className="pi-anillo-det">{detalle}</div>
      </div>
    </div>
  );
}

// Una barra de conteo (etiqueta, valor, proporción respecto al máximo del grupo)
function Barra({ etiqueta, valor, max, color }: {
  etiqueta: string; valor: number; max: number; color?: string;
}) {
  const pct = max > 0 ? Math.round((valor / max) * 100) : 0;
  return (
    <div className="pi-barra">
      <span className="pi-barra-et">{etiqueta}</span>
      <span className="pi-barra-track">
        <span className="pi-barra-fill" style={{ width: `${pct}%`, background: color }} />
      </span>
      <span className="pi-barra-val">{fmt(valor)}</span>
    </div>
  );
}

// Grupo de barras a partir de un objeto {clave: conteo}, en un orden dado
function Grupo({ titulo, datos, orden, etiquetas, color }: {
  titulo: string;
  datos: Record<string, number>;
  orden: string[];
  etiquetas: Record<string, string>;
  color?: string;
}) {
  const filas = orden
    .map((k) => ({ k, v: datos[k] ?? 0 }))
    .filter((f) => f.v > 0);
  const max = Math.max(1, ...filas.map((f) => f.v));
  return (
    <div className="pi-grupo">
      <h4 className="pi-grupo-titulo">{titulo}</h4>
      {filas.length === 0 ? (
        <p className="pi-vacio">Sin datos en pantalla</p>
      ) : (
        filas.map((f) => (
          <Barra key={f.k} etiqueta={etiquetas[f.k] ?? f.k} valor={f.v} max={max} color={color} />
        ))
      )}
    </div>
  );
}

// Top-N de un objeto {clave: conteo} (para barrio y ciclo, que tienen muchos valores)
function GrupoTop({ titulo, datos, n, prefijo }: {
  titulo: string; datos: Record<string, number>; n: number; prefijo?: string;
}) {
  const filas = Object.entries(datos)
    .map(([k, v]) => ({ k, v }))
    .sort((a, b) => b.v - a.v);
  const top = filas.slice(0, n);
  const resto = filas.slice(n);
  const restoTotal = resto.reduce((s, f) => s + f.v, 0);
  const max = Math.max(1, ...top.map((f) => f.v));
  return (
    <div className="pi-grupo">
      <h4 className="pi-grupo-titulo">{titulo}</h4>
      {top.length === 0 ? (
        <p className="pi-vacio">Sin datos en pantalla</p>
      ) : (
        <>
          {top.map((f) => (
            <Barra key={f.k} etiqueta={`${prefijo ?? ""}${f.k}`} valor={f.v} max={max} />
          ))}
          {resto.length > 0 && (
            <p className="pi-mas">y {fmt(resto.length)} más ({fmt(restoTotal)} predios)</p>
          )}
        </>
      )}
    </div>
  );
}

export function PanelIndicadores({ stats, abierto, onToggle }: {
  stats: StatsComercial;
  abierto: boolean;
  onToggle: () => void;
}) {
  return (
    <div className={`panel-ind ${abierto ? "panel-ind-abierto" : ""}`}>
      <button className="pi-toggle" onClick={onToggle}>
        {abierto ? "▾ Ocultar indicadores" : "▴ Ver indicadores de lo visible"}
      </button>

      {abierto && (
        <div className="pi-cuerpo">
          {!stats.disponible ? (
            <p className="pi-lejos">Acércate (zoom 15+) para ver los indicadores de lo que hay en pantalla.</p>
          ) : (
            <>
              {/* Tarjetas */}
              <div className="pi-tarjetas">
                <div className="pi-tarjeta">
                  <div className="pi-t-num">{fmt(stats.total)}</div>
                  <div className="pi-t-lbl">Predios en pantalla</div>
                </div>
                <div className="pi-tarjeta">
                  <div className="pi-t-num rojo">{fmt(stats.conDeuda)}</div>
                  <div className="pi-t-lbl">Con deuda</div>
                </div>
                <div className="pi-tarjeta">
                  <div className="pi-t-num ambar">{fmt(stats.sinMedidor)}</div>
                  <div className="pi-t-lbl">Sin medidor</div>
                </div>
                <div className="pi-tarjeta">
                  <div className="pi-t-num">{fmt(stats.consumoAlto)}</div>
                  <div className="pi-t-lbl">Consumo elevado/grandes</div>
                </div>
              </div>

              {/* Cifra destacada, medidor y anillo */}
              <div className="pi-destacados">
                <div className="pi-destacado">
                  <div className="pi-d-num">{pesos(stats.deudaTotal)}</div>
                  <div className="pi-d-lbl">Cartera de los predios en pantalla</div>
                </div>
                {(() => {
                  const conDato = Object.values(stats.medicion).reduce((a, b) => a + b, 0);
                  const pct = conDato > 0 ? Math.round((stats.conMedidor / conDato) * 100) : 0;
                  return (
                    <div className="pi-destacado">
                      <div className="pi-medidor-cab">
                        <span className="pi-medidor-pct">{pct}%</span>
                        <span className="pi-d-lbl">con medidor en buen estado</span>
                      </div>
                      <div className="pi-medidor-riel">
                        <div className="pi-medidor-relleno" style={{ width: `${pct}%` }} />
                      </div>
                      <div className="pi-d-nota">Sobre {fmt(conDato)} predios con dato de medición</div>
                    </div>
                  );
                })()}
                {(() => {
                  const conFact = Object.values(stats.facturacion).reduce((a, b) => a + b, 0);
                  const pct = conFact > 0 ? Math.round((stats.porPromedio / conFact) * 100) : 0;
                  return (
                    <Anillo pct={pct} color="#f57c00" titulo="Facturado por promedio"
                      detalle={`${fmt(stats.porPromedio)} de ${fmt(conFact)} sin lectura real`} />
                  );
                })()}
              </div>

              {/* Desgloses */}
              <div className="pi-grupos">
                <Grupo titulo="Semáforo de cartera" datos={stats.semaforo} orden={ORD_SEMAFORO} etiquetas={ET_SEMAFORO} color="#8e24aa" />
                <Grupo titulo="Edad del medidor" datos={stats.edadMed} orden={ORD_EDAD} etiquetas={ET_EDAD} color="#f57c00" />
                <Grupo titulo="Último pago" datos={stats.pago} orden={ORD_PAGO} etiquetas={ET_PAGO} color="#1565c0" />
                <GrupoTop titulo="Causales de lectura (top 6)" datos={stats.causal} n={6} />
                <Grupo titulo="Medición" datos={stats.medicion} orden={["1","2","3"]} etiquetas={ET_MEDICION} color="#1e5aa8" />
                <Grupo titulo="Facturación" datos={stats.facturacion} orden={["1","2","3","4","5"]} etiquetas={ET_FACTURACION} color="#1e5aa8" />
                <Grupo titulo="Consumo del mes" datos={stats.consumo} orden={ORD_CONSUMO} etiquetas={ET_CONSUMO} color="#2e7d32" />
                <Grupo titulo="Cartera (mora)" datos={stats.mora} orden={ORD_MORA} etiquetas={ET_MORA} color="#d32f2f" />
                <GrupoTop titulo="Ciclos (top 6)" datos={stats.ciclo} n={6} prefijo="Ciclo " />
                <GrupoTop titulo="Barrios (top 6)" datos={stats.barrio} n={6} />
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
}
