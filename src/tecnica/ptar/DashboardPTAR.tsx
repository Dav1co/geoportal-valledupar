import { useEffect, useState, type ReactNode } from "react";
import "../dashboard.css";
import "./tokens_ptar.css";
import "./ptar.css";
import { CabeceraDashboard } from "../CabeceraDashboard";
import { ErrorTec } from "../apiTecnica";
import { MapaPTAR } from "./MapaPTAR";
import { apiPtar, type AlcancesResp } from "./apiPtar";

// PTAR-2 (Code C, 21-nov): el cascarón del Dashboard PTAR (D4), en pizarra. Primera entrega: el MAPA interactivo funciona; Resumen, Registros, Eventos,
// Referencias y Reportes quedan en «Próximamente» hasta que existan los formularios (PTAR-4). «Personal técnico» = el alcance PTAP / PTAR de cada persona (D6),
// solo para el administrador. Mismo registro de secciones que el Dashboard PTAP: agregar una sección es registrarla con su componente.
type Seccion = { clave: string; titulo: string; Componente?: () => JSX.Element; soloAdmin?: boolean };
const SECCIONES: Seccion[] = [
  { clave: "mapa", titulo: "Mapa", Componente: () => <MapaPTAR instalacion="ptar" /> },
  { clave: "resumen", titulo: "Resumen" },
  { clave: "registros", titulo: "Registros" },
  { clave: "eventos", titulo: "Eventos" },
  { clave: "referencias", titulo: "Referencias" },
  { clave: "personal", titulo: "Personal técnico", Componente: () => <AlcancesPTAR />, soloAdmin: true },
  { clave: "reportes", titulo: "Reportes" },
];

export function DashboardPTAR({ correo, rotuloPerfil, admin, onVolver, selector }: { correo: string; rotuloPerfil: string; admin: boolean; onVolver: () => void; selector?: ReactNode }) {
  const [activa, setActiva] = useState("mapa");
  const pestanas = SECCIONES.map((s) => ({ clave: s.clave, titulo: s.titulo, pronto: !s.Componente || (s.soloAdmin && !admin) }));
  const seccion = SECCIONES.find((s) => s.clave === activa);
  return (
    <div className="tdash tdash-ptar" data-dashboard="ptar">
      <CabeceraDashboard titulo="Dashboard PTAR" sesion={`${correo} · ${rotuloPerfil}`} onVolver={onVolver} selector={selector} etiqueta="Secciones del Dashboard PTAR"
        pestanas={pestanas} activa={activa} onElegir={setActiva} />
      <div className="tdash-cuerpo">{seccion?.Componente ? <seccion.Componente /> : null}</div>
    </div>
  );
}

/** Alcance PTAP / PTAR de las personas (solo el administrador). Sin asignación: PTAP sí, PTAR no; el administrador tiene los dos. */
function AlcancesPTAR() {
  const [d, setD] = useState<AlcancesResp | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [vez, setVez] = useState(0);
  const [persona, setPersona] = useState("");
  const [alcance, setAlcance] = useState<"ptar" | "ptap">("ptar");
  const [accion, setAccion] = useState<"asignar" | "quitar">("asignar");
  const [motivo, setMotivo] = useState("");
  const [aviso, setAviso] = useState<{ tipo: "ok" | "error"; texto: string } | null>(null);
  const [enviando, setEnviando] = useState(false);
  useEffect(() => { let vivo = true; apiPtar.alcances().then((x) => { if (vivo) setD(x); }).catch((e) => { if (vivo) setError(e instanceof ErrorTec ? e.message : "No se pudo cargar."); }); return () => { vivo = false; }; }, [vez]);
  const enviar = async (e: React.FormEvent) => {
    e.preventDefault(); setEnviando(true); setAviso(null);
    try { const r = await apiPtar.alcance(persona.trim(), alcance, accion, motivo.trim());
          setAviso({ tipo: "ok", texto: `${r.persona}: PTAP ${r.ptap ? "sí" : "no"} · PTAR ${r.ptar ? "sí" : "no"}.` }); setMotivo(""); setVez((v) => v + 1); }
    catch (er) { setAviso({ tipo: "error", texto: er instanceof ErrorTec ? er.message : "No se pudo guardar." }); }
    finally { setEnviando(false); }
  };
  if (error) return <div className="td-aviso td-aviso-error" role="alert">{error}</div>;
  if (!d) return <p className="td-sub" role="status">Cargando…</p>;
  return (
    <div className="ptar-alcances" data-testid="ptar-alcances">
      <section className="ptar-ficha">
        <h3>Alcance PTAP y PTAR</h3>
        <p className="ptar-nota">{d.regla} Quien solo tiene la PTAR no ve el Dashboard PTAP, y al revés.</p>
        {d.personas.length === 0 ? <p className="ptar-nota">Todavía nadie tiene un alcance asignado.</p> : (
          <table><thead><tr><th>Persona</th><th>PTAP</th><th>PTAR</th></tr></thead>
            <tbody>{d.personas.map((p) => <tr key={p.persona}><td>{p.persona}</td><td>{p.ptap ? "Sí" : "No"}</td><td>{p.ptar ? "Sí" : "No"}</td></tr>)}</tbody></table>)}
      </section>
      <section className="ptar-ficha">
        <h3>Asignar o quitar un alcance</h3>
        <form onSubmit={enviar}>
          <label htmlFor="alc-persona">Correo de la persona</label>
          <input id="alc-persona" type="email" value={persona} onChange={(e) => setPersona(e.target.value)} autoComplete="off" />
          <label htmlFor="alc-alcance">Alcance</label>
          <select id="alc-alcance" value={alcance} onChange={(e) => setAlcance(e.target.value as "ptar" | "ptap")}><option value="ptar">PTAR</option><option value="ptap">PTAP</option></select>
          <label htmlFor="alc-accion">Acción</label>
          <select id="alc-accion" value={accion} onChange={(e) => setAccion(e.target.value as "asignar" | "quitar")}><option value="asignar">Asignar</option><option value="quitar">Quitar</option></select>
          <label htmlFor="alc-motivo">Motivo</label>
          <textarea id="alc-motivo" value={motivo} rows={2} maxLength={1000} onChange={(e) => setMotivo(e.target.value)} />
          <button type="submit" className="tec-boton" disabled={enviando || !persona.includes("@") || motivo.trim().length < 10}>{enviando ? "Guardando…" : "Guardar"}</button>
        </form>
        {aviso ? <p className={aviso.tipo === "ok" ? "ptar-ok" : "ptar-error"} role={aviso.tipo === "ok" ? "status" : "alert"}>{aviso.texto}</p> : null}
      </section>
    </div>
  );
}
