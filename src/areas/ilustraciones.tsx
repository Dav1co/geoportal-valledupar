// Ilustraciones vectoriales de las tarjetas de la ventana de entrada. SVG en línea: sin imágenes externas, nítidas a cualquier tamaño y de peso mínimo.
// Comercial: azul institucional del portal. Técnica: verde azulado del área técnica. Son decorativas (aria-hidden): el texto de la tarjeta dice lo mismo.
import type { ReactNode } from "react";

// ---------------------------------------------------------------------------------------------------------------- Comercial
const AZUL = "#1e5aa8", AZUL_MEDIO = "#4a90d9", AZUL_CLARO = "#bcd2ee", AZUL_FONDO = "#e8eff7", AZUL_TENUE = "#d4e0ef", TEAL = "#0f766e";

function Pin({ x, y, color }: { x: number; y: number; color: string }) {
  return (
    <g>
      <ellipse cx={x} cy={y + 1} rx={6} ry={2.2} fill="#0a2540" opacity={0.16} />
      <path d={`M${x} ${y} C${x - 3} ${y - 8} ${x - 9} ${y - 13} ${x - 9} ${y - 19} A9 9 0 1 1 ${x + 9} ${y - 19} C${x + 9} ${y - 13} ${x + 3} ${y - 8} ${x} ${y} Z`} fill={color} />
      <circle cx={x} cy={y - 19} r={3.6} fill="#fff" />
    </g>
  );
}

/** Plano de calles de la ciudad con el río y los puntos de interés. */
export function MapaComercial() {
  const horiz = [-120, -86, -52, -18, 16, 50, 84, 118, 152, 186, 220, 254];
  const vert = [-40, 10, 62, 112, 166, 214, 268, 322, 372, 420, 470];
  return (
    <svg className="area-arte" viewBox="0 0 400 170" preserveAspectRatio="xMidYMid slice" aria-hidden="true" focusable="false">
      <rect width="400" height="170" fill={AZUL_FONDO} />
      <path d="M-10 150 C 80 118, 150 178, 240 140 S 380 96, 420 112" fill="none" stroke="#c3dcf2" strokeWidth="15" strokeLinecap="round" />
      <path d="M-10 150 C 80 118, 150 178, 240 140 S 380 96, 420 112" fill="none" stroke="#d9eafa" strokeWidth="8" strokeLinecap="round" />
      <g transform="rotate(-7 200 85)" strokeLinecap="round">
        {horiz.map((y, i) => <line key={"h" + i} x1={-90} x2={490} y1={y} y2={y} stroke="#fff" strokeWidth={4} />)}
        {vert.map((x, i) => <line key={"v" + i} x1={x} x2={x} y1={-100} y2={280} stroke="#fff" strokeWidth={4} />)}
        <line x1={-90} x2={490} y1={50} y2={50} stroke={AZUL_TENUE} strokeWidth={12} />
        <line x1={-90} x2={490} y1={50} y2={50} stroke="#fff" strokeWidth={8.5} />
        <line x1={166} x2={166} y1={-100} y2={280} stroke={AZUL_TENUE} strokeWidth={12} />
        <line x1={166} x2={166} y1={-100} y2={280} stroke="#fff" strokeWidth={8.5} />
      </g>
      <path d="M262 -10 L350 180" stroke={AZUL_TENUE} strokeWidth="12" strokeLinecap="round" />
      <path d="M262 -10 L350 180" stroke="#fff" strokeWidth="8.5" strokeLinecap="round" />
      <Pin x={104} y={62} color={AZUL} />
      <Pin x={196} y={92} color={AZUL_MEDIO} />
      <Pin x={288} y={52} color={TEAL} />
      <Pin x={148} y={140} color={TEAL} />
      <Pin x={332} y={104} color={AZUL} />
      <Pin x={52} y={110} color={AZUL_MEDIO} />
    </svg>
  );
}

function Tarjeta({ x, y, w, h, children }: { x: number; y: number; w: number; h: number; children: ReactNode }) {
  return (
    <g>
      <rect x={x} y={y} width={w} height={h} rx={10} fill="#fff" stroke="#dfe7f1" />
      {children}
    </g>
  );
}

/** Mini tablero: anillo de avance, serie de área, barras de avance, columnas y barras segmentadas. */
export function PanelComercial() {
  return (
    <svg className="area-arte area-arte-panel" viewBox="0 0 400 176" aria-hidden="true" focusable="false">
      <rect width="400" height="176" rx="14" fill={AZUL_FONDO} />
      <Tarjeta x={14} y={14} w={104} h={76}>
        <circle cx={66} cy={52} r={19} fill="none" stroke={AZUL_TENUE} strokeWidth={9} />
        <circle cx={66} cy={52} r={19} fill="none" stroke={AZUL} strokeWidth={9} strokeLinecap="round" strokeDasharray="78 120" transform="rotate(-90 66 52)" />
      </Tarjeta>
      <Tarjeta x={128} y={14} w={258} h={76}>
        <rect x={142} y={27} width={34} height={4} rx={2} fill={AZUL_TENUE} />
        <rect x={142} y={35} width={22} height={4} rx={2} fill="#e3eaf4" />
        <polygon points="146,82 178,64 212,72 246,50 282,60 318,40 372,32 372,82" fill={AZUL_CLARO} opacity={0.75} />
        <polygon points="146,82 182,70 214,76 250,64 286,69 322,56 372,50 372,82" fill={AZUL} opacity={0.9} />
      </Tarjeta>
      <Tarjeta x={14} y={100} w={104} h={62}>
        {[[0.75, AZUL], [0.45, AZUL_MEDIO], [0.6, AZUL_CLARO]].map(([f, c], i) => (
          <g key={i}>
            <rect x={26} y={114 + i * 15} width={10} height={9} rx={2.5} fill={c as string} />
            <rect x={42} y={114 + i * 15} width={64} height={9} rx={4.5} fill="#e3eaf4" />
            <rect x={42} y={114 + i * 15} width={64 * (f as number)} height={9} rx={4.5} fill={c as string} />
          </g>
        ))}
      </Tarjeta>
      <Tarjeta x={128} y={100} w={122} h={62}>
        {[16, 25, 34, 25, 40, 30, 44].map((h, i) => (
          <g key={i}>
            <rect x={142 + i * 15.4} y={154 - 44} width={9} height={44} rx={2.5} fill="#e3eaf4" />
            <rect x={142 + i * 15.4} y={154 - h} width={9} height={h} rx={2.5} fill={i % 2 ? AZUL_MEDIO : AZUL} />
          </g>
        ))}
      </Tarjeta>
      <Tarjeta x={260} y={100} w={126} h={62}>
        {[0.55, 0.85, 0.4, 0.7, 0.95, 0.3, 0.6].map((f, i) => (
          <g key={i}>
            <rect x={274 + i * 15} y={110} width={8} height={42} rx={4} fill="#e3eaf4" />
            <rect x={274 + i * 15} y={110 + 42 * (1 - f)} width={8} height={42 * f} rx={4} fill={i === 4 ? AZUL : AZUL_CLARO} />
          </g>
        ))}
      </Tarjeta>
    </svg>
  );
}

// ---------------------------------------------------------------------------------------------------------------- Técnica
const T_OSC = "#0f5a53", T_MED = "#2f9e8f", T_LINEA = "#2f6f68", T_CLARO = "#cfe9e4", T_LADO_I = "#8fc4bb", T_LADO_D = "#62a79c", T_FONDO = "#eef5f4", T_AGUA = "#3aa795";

function Plataforma({ cx, cy, w }: { cx: number; cy: number; w: number }) {
  const h = w / 2, e = 7;
  return (
    <g stroke={T_LINEA} strokeWidth={1.1} strokeLinejoin="round">
      <polygon points={`${cx - w},${cy} ${cx},${cy + h} ${cx},${cy + h + e} ${cx - w},${cy + e}`} fill={T_LADO_I} />
      <polygon points={`${cx + w},${cy} ${cx},${cy + h} ${cx},${cy + h + e} ${cx + w},${cy + e}`} fill={T_LADO_D} />
      <polygon points={`${cx},${cy - h} ${cx + w},${cy} ${cx},${cy + h} ${cx - w},${cy}`} fill={T_CLARO} />
    </g>
  );
}

function Cilindro({ cx, cy, r, h, cuerpo = "#9bd0c6", tapa = T_CLARO }: { cx: number; cy: number; r: number; h: number; cuerpo?: string; tapa?: string }) {
  const ry = r * 0.5;
  return (
    <g stroke={T_LINEA} strokeWidth={1.1} strokeLinejoin="round">
      <path d={`M${cx - r} ${cy} L${cx - r} ${cy + h} A${r} ${ry} 0 0 0 ${cx + r} ${cy + h} L${cx + r} ${cy} Z`} fill={cuerpo} />
      <ellipse cx={cx} cy={cy} rx={r} ry={ry} fill={tapa} />
      <path d={`M${cx - r * 0.55} ${cy + ry * 0.9} L${cx - r * 0.55} ${cy + h + ry * 0.9}`} stroke="#fff" strokeWidth={2} opacity={0.35} fill="none" />
    </g>
  );
}

function Torre({ cx, cy }: { cx: number; cy: number }) {   // cy = centro de la plataforma
  const base = cy - 3, tanque = cy - 52;
  return (
    <g>
      <Plataforma cx={cx} cy={cy} w={26} />
      <g stroke={T_LINEA} strokeWidth={1.6} strokeLinecap="round">
        <line x1={cx - 11} y1={base - 3} x2={cx - 7} y2={tanque + 13} />
        <line x1={cx + 11} y1={base - 3} x2={cx + 7} y2={tanque + 13} />
        <line x1={cx - 4} y1={base + 4} x2={cx - 3} y2={tanque + 16} />
        <line x1={cx + 4} y1={base + 4} x2={cx + 3} y2={tanque + 16} />
        <line x1={cx - 10} y1={base - 14} x2={cx + 10} y2={base - 20} strokeWidth={1.1} />
        <line x1={cx + 10} y1={base - 14} x2={cx - 10} y2={base - 20} strokeWidth={1.1} />
      </g>
      <Cilindro cx={cx} cy={tanque} r={15} h={14} cuerpo={T_MED} tapa="#8fd0c4" />
      <path d={`M${cx - 15} ${tanque} L${cx} ${tanque - 9} L${cx + 15} ${tanque} A15 7.5 0 0 1 ${cx - 15} ${tanque} Z`} fill={T_LADO_D} stroke={T_LINEA} strokeWidth={1.1} strokeLinejoin="round" />
    </g>
  );
}

function Tuberia({ d }: { d: string }) {
  return (
    <g fill="none" strokeLinecap="round" strokeLinejoin="round">
      <path d={d} stroke={T_LINEA} strokeWidth={9} />
      <path d={d} stroke={T_CLARO} strokeWidth={5.5} />
    </g>
  );
}

function Marca({ x, y, tipo }: { x: number; y: number; tipo: "gota" | "engranaje" }) {
  return (
    <g>
      <circle cx={x} cy={y} r={9} fill={T_OSC} stroke="#fff" strokeWidth={2} />
      {tipo === "gota"
        ? <path d={`M${x} ${y - 5} C${x + 3.4} ${y - 1} ${x + 4.4} ${y + 0.6} ${x + 4.4} ${y + 2} A4.4 4.4 0 0 1 ${x - 4.4} ${y + 2} C${x - 4.4} ${y + 0.6} ${x - 3.4} ${y - 1} ${x} ${y - 5} Z`} fill="#fff" />
        : <g fill="none" stroke="#fff" strokeWidth={1.6}><circle cx={x} cy={y} r={2.6} /><circle cx={x} cy={y} r={4.8} strokeDasharray="2.2 1.9" /></g>}
    </g>
  );
}

/** Balsas de la planta de tratamiento sobre una plataforma isométrica (2 x 2 celdas de agua). */
function Balsas({ cx, cy, w }: { cx: number; cy: number; w: number }) {
  const h = w / 2, e = 7;
  const N: [number, number] = [cx, cy - h], E: [number, number] = [cx + w, cy], W: [number, number] = [cx - w, cy];
  const p = (u: number, v: number) => `${(N[0] + u * (E[0] - N[0]) + v * (W[0] - N[0])).toFixed(1)},${(N[1] + u * (E[1] - N[1]) + v * (W[1] - N[1])).toFixed(1)}`;
  const celdas: ReactNode[] = [];
  [0, 1].forEach((i) => [0, 1].forEach((j) => {
    const m = 0.07, u0 = i * 0.5 + m, u1 = (i + 1) * 0.5 - m, v0 = j * 0.5 + m, v1 = (j + 1) * 0.5 - m;
    celdas.push(<polygon key={`${i}${j}`} points={`${p(u0, v0)} ${p(u1, v0)} ${p(u1, v1)} ${p(u0, v1)}`} fill={(i + j) % 2 ? T_AGUA : T_MED} stroke={T_LINEA} strokeWidth={0.9} />);
  }));
  return (
    <g stroke={T_LINEA} strokeWidth={1.1} strokeLinejoin="round">
      <polygon points={`${cx - w},${cy} ${cx},${cy + h} ${cx},${cy + h + e} ${cx - w},${cy + e}`} fill={T_LADO_I} />
      <polygon points={`${cx + w},${cy} ${cx},${cy + h} ${cx},${cy + h + e} ${cx + w},${cy + e}`} fill={T_LADO_D} />
      <polygon points={`${cx},${cy - h} ${cx + w},${cy} ${cx},${cy + h} ${cx - w},${cy}`} fill={T_CLARO} />
      {celdas}
    </g>
  );
}

/** Red de agua en perspectiva isométrica: torres, tanques, planta de tratamiento y tuberías (todas en las direcciones de la cuadrícula). */
export function RedTecnica() {
  const lineas: ReactNode[] = [];
  for (let k = -8; k <= 14; k++) {
    lineas.push(<line key={"a" + k} x1={-20 + k * 60} y1={-10} x2={-20 + k * 60 + 460} y2={-10 + 230} stroke="#dfeae8" strokeWidth={1} />);
    lineas.push(<line key={"b" + k} x1={420 - k * 60 + 60} y1={-10} x2={420 - k * 60 + 60 - 460} y2={-10 + 230} stroke="#dfeae8" strokeWidth={1} />);
  }
  return (
    <svg className="area-arte" viewBox="0 0 400 200" preserveAspectRatio="xMidYMid slice" aria-hidden="true" focusable="false">
      <rect width="400" height="200" fill={T_FONDO} />
      {lineas}
      <g transform="translate(10 12) scale(0.94)">
      {/* tuberías por el suelo, bajo los edificios: torre 1 - cruce 1 - cruce 2 - torre 2; cruce 1 - tanques; cruce 2 - cruce 3 - tanques; torre 2 - balsas */}
      <Tuberia d="M80 100 L130 125 L190 95 L250 65" />
      <Tuberia d="M130 125 L50 165" />
      <Tuberia d="M190 95 L270 135 L330 165" />
      <Tuberia d="M250 65 L310 95 L352 74" />
      <Plataforma cx={50} cy={165} w={42} />
      <Cilindro cx={36} cy={142} r={12} h={22} cuerpo={T_LADO_I} />
      <Cilindro cx={64} cy={150} r={10} h={14} cuerpo={T_MED} tapa="#8fd0c4" />
      <Cilindro cx={50} cy={160} r={8} h={9} cuerpo="#b5c9c6" />
      <Torre cx={80} cy={100} />
      <Torre cx={250} cy={65} />
      <Balsas cx={352} cy={74} w={40} />
      <Plataforma cx={330} cy={165} w={40} />
      <Cilindro cx={316} cy={136} r={14} h={26} cuerpo={T_MED} tapa="#8fd0c4" />
      <Cilindro cx={346} cy={144} r={12} h={20} cuerpo={T_OSC} tapa="#7fc0b4" />
      <Marca x={130} y={125} tipo="gota" />
      <Marca x={190} y={95} tipo="engranaje" />
      <Marca x={270} y={135} tipo="gota" />
      <Marca x={310} y={95} tipo="engranaje" />
      </g>
    </svg>
  );
}

function Manometro({ cx, cy, r = 11, aguja = -30 }: { cx: number; cy: number; r?: number; aguja?: number }) {
  return (
    <g>
      <circle cx={cx} cy={cy} r={r} fill="#fff" stroke={T_LINEA} strokeWidth={2.2} />
      <path d={`M${cx - r * 0.65} ${cy + r * 0.2} A${r * 0.68} ${r * 0.68} 0 0 1 ${cx + r * 0.65} ${cy + r * 0.2}`} fill="none" stroke={T_AGUA} strokeWidth={2.4} strokeLinecap="round" />
      <line x1={cx} y1={cy + 1} x2={cx + r * 0.6 * Math.sin((aguja * Math.PI) / 180)} y2={cy + 1 - r * 0.6 * Math.cos((aguja * Math.PI) / 180)} stroke={T_OSC} strokeWidth={1.8} strokeLinecap="round" />
      <circle cx={cx} cy={cy + 1} r={1.8} fill={T_OSC} />
    </g>
  );
}

function Valvula({ x, y }: { x: number; y: number }) {
  return (
    <g stroke={T_LINEA} strokeWidth={1.4} strokeLinejoin="round">
      <polygon points={`${x - 6},${y - 5} ${x},${y} ${x - 6},${y + 5}`} fill={T_CLARO} />
      <polygon points={`${x + 6},${y - 5} ${x},${y} ${x + 6},${y + 5}`} fill={T_CLARO} />
      <line x1={x} y1={y} x2={x} y2={y - 8} />
      <line x1={x - 4} y1={y - 8} x2={x + 4} y2={y - 8} />
    </g>
  );
}

function TanqueFrontal({ x, y, w, h, nivel }: { x: number; y: number; w: number; h: number; nivel: number }) {
  const ry = w * 0.2, agua = (h - ry) * nivel;
  return (
    <g stroke={T_LINEA} strokeWidth={1.8} strokeLinejoin="round">
      <path d={`M${x} ${y} L${x} ${y + h} A${w / 2} ${ry} 0 0 0 ${x + w} ${y + h} L${x + w} ${y} Z`} fill="#e3eeed" />
      <path d={`M${x} ${y + h - agua} L${x} ${y + h} A${w / 2} ${ry} 0 0 0 ${x + w} ${y + h} L${x + w} ${y + h - agua} A${w / 2} ${ry} 0 0 1 ${x} ${y + h - agua} Z`} fill={T_AGUA} />
      <ellipse cx={x + w / 2} cy={y} rx={w / 2} ry={ry} fill="#f7fbfa" />
      {[0.25, 0.5, 0.75].map((f) => <line key={f} x1={x + w - 7} x2={x + w - 1} y1={y + h * f} y2={y + h * f} strokeWidth={1.2} />)}
    </g>
  );
}

function MiniTarjeta({ x, y, w, h, children }: { x: number; y: number; w: number; h: number; children: ReactNode }) {
  return (
    <g>
      <rect x={x} y={y} width={w} height={h} rx={9} fill="#fff" stroke="#d6e4e2" />
      {children}
    </g>
  );
}

/** Mini tablero técnico: esquema de proceso con tanques, válvulas y manómetros, más series de medición. */
export function PanelTecnico() {
  return (
    <svg className="area-arte area-arte-panel" viewBox="0 0 400 176" aria-hidden="true" focusable="false">
      <rect width="400" height="176" rx="14" fill={T_FONDO} />
      <MiniTarjeta x={10} y={10} w={96} h={72}>
        <rect x={20} y={20} width={26} height={4} rx={2} fill="#9fb3b0" />
        <polygon points="22,72 38,56 52,62 68,44 84,54 96,40 96,72" fill="#b6ddd5" />
        <polygon points="22,72 40,64 54,68 70,56 86,62 96,54 96,72" fill={T_MED} />
      </MiniTarjeta>
      <MiniTarjeta x={10} y={92} w={96} h={74}>
        <Tuberia d="M20 118 L66 118" />
        <Tuberia d="M20 144 L66 144" />
        <Valvula x={38} y={118} />
        <Valvula x={38} y={144} />
        <Manometro cx={82} cy={118} r={10} aguja={25} />
        <Manometro cx={82} cy={144} r={10} aguja={-30} />
      </MiniTarjeta>
      <MiniTarjeta x={114} y={10} w={172} h={156}>
        <Tuberia d="M124 62 L168 62" />
        <Tuberia d="M168 74 L140 74 L140 142 L204 142" />
        <Tuberia d="M190 80 L190 118 L204 118" />
        <TanqueFrontal x={168} y={22} w={44} h={58} nivel={0.62} />
        <TanqueFrontal x={204} y={94} w={58} h={62} nivel={0.78} />
        <Valvula x={140} y={106} />
        <Valvula x={176} y={142} />
        <Manometro cx={132} cy={44} r={10} aguja={25} />
        <Manometro cx={276} cy={116} r={9} aguja={-20} />
        <Manometro cx={276} cy={142} r={9} aguja={30} />
      </MiniTarjeta>
      <MiniTarjeta x={294} y={10} w={96} h={46}>
        <polygon points="304,50 320,30 336,40 352,24 368,36 380,26 380,50" fill="#b6ddd5" />
        <polygon points="304,50 322,42 338,46 354,36 370,44 380,40 380,50" fill={T_MED} />
      </MiniTarjeta>
      <MiniTarjeta x={294} y={64} w={96} h={46}>
        {[10, 18, 13, 22, 16, 25].map((h, i) => <rect key={i} x={304 + i * 14.5} y={102 - h} width={8} height={h} rx={2.5} fill={i % 2 ? T_AGUA : T_MED} />)}
      </MiniTarjeta>
      <MiniTarjeta x={294} y={118} w={96} h={48}>
        {[0.5, 0.8, 0.35, 0.65, 0.9].map((f, i) => (
          <g key={i}>
            <rect x={306 + i * 16} y={126} width={8} height={32} rx={4} fill="#e3eeed" />
            <rect x={306 + i * 16} y={126 + 32 * (1 - f)} width={8} height={32 * f} rx={4} fill={i === 3 ? T_OSC : T_MED} />
          </g>
        ))}
      </MiniTarjeta>
    </svg>
  );
}
