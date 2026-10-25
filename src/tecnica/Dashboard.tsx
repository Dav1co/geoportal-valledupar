import { useEffect, useState } from "react";
import "./dashboard.css";
import { apiDash, textoError, type Catalogo } from "./apiDashboard";
import { RegistrosRecientes } from "./RegistrosRecientes";
import { PersonalTecnico } from "./PersonalTecnico";
import { supabase } from "../lib/supabase";

// Dashboard técnico (supervisor y administrador). Las secciones salen de este registro: agregar «Estado del servicio» o «Eventos» cuando existan es registrar una sección
// con su componente; el resto de la pantalla no cambia. Las que aún no existen se muestran deshabilitadas, sin datos de ejemplo.
type Seccion = { clave: string; titulo: string; Componente?: (p: { catalogo: Catalogo }) => JSX.Element };
const SECCIONES: Seccion[] = [
  { clave: "resumen", titulo: "Resumen y eventos" },
  { clave: "registros", titulo: "Registros", Componente: RegistrosRecientes },
  { clave: "eventos", titulo: "Eventos" },
  { clave: "quimicos", titulo: "Químicos" },
  { clave: "personal", titulo: "Personal técnico", Componente: PersonalTecnico },
  { clave: "puntos", titulo: "Puntos" },
  { clave: "reportes", titulo: "Reportes" },
];

export function Dashboard({ correo, rotuloPerfil, onVolver }: { correo: string; rotuloPerfil: string; onVolver: () => void }) {
  const [activa, setActiva] = useState("registros");
  const [catalogo, setCatalogo] = useState<Catalogo | null>(null);
  const [error, setError] = useState<{ texto: string; sesion: boolean } | null>(null);
  const [intento, setIntento] = useState(0);
  useEffect(() => { let vivo = true; setError(null);
    apiDash.catalogo().then((c) => { if (vivo) setCatalogo(c); }).catch((e) => { if (vivo) setError(textoError(e)); });
    return () => { vivo = false; }; }, [intento]);
  const seccion = SECCIONES.find((s) => s.clave === activa);
  return (
    <div className="tdash">
      <div className="tdash-cab">
        <div className="tdash-ancho">
          <div className="tdash-fila">
            <h1>Dashboard técnico</h1>
            <button type="button" className="td-boton-claro" onClick={onVolver}>← Volver a mis formularios</button>
          </div>
          <div className="tdash-sesion">{correo} · {rotuloPerfil}</div>
          <nav className="tdash-tabs" aria-label="Secciones del Dashboard técnico">
            {SECCIONES.map((s) => s.Componente
              ? <button key={s.clave} type="button" className="tdash-tab" aria-current={activa === s.clave ? "page" : undefined} onClick={() => setActiva(s.clave)}>{s.titulo}</button>
              : <button key={s.clave} type="button" className="tdash-tab tdash-tab-pronto" disabled aria-disabled="true" title="Próximamente">{s.titulo}<span className="td-pronto">Próximamente</span></button>)}
          </nav>
        </div>
      </div>
      <div className="tdash-cuerpo">
        {error ? (
          <div className="td-aviso td-aviso-error" role="alert">{error.texto}{" "}
            {error.sesion ? <button type="button" className="td-enlace" onClick={() => void supabase.auth.signOut()}>Volver a iniciar sesión</button> : <button type="button" className="td-enlace" onClick={() => setIntento((x) => x + 1)}>Reintentar</button>}
          </div>
        ) : !catalogo ? <p className="td-sub" role="status">Cargando el Dashboard…</p>
          : seccion?.Componente ? <seccion.Componente catalogo={catalogo} /> : null}
      </div>
    </div>
  );
}
