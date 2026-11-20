import { useEffect, useState, type ReactNode } from "react";
import "./dashboard.css";
import { apiDash, textoError, type Catalogo } from "./apiDashboard";
import { RegistrosRecientes } from "./RegistrosRecientes";
import { PersonalTecnico } from "./PersonalTecnico";
import { Resumen } from "./Resumen";
import { Eventos } from "./Eventos";
import { PuntosUbicacion } from "./PuntosUbicacion";
import { QuimicosPTAP } from "./QuimicosPTAP";
import { supabase } from "../lib/supabase";
import { CabeceraDashboard } from "./CabeceraDashboard";
import { PanelReportes } from "./reportes/PanelReportes";
import { REPORTES_PTAP } from "./reportes/catalogo";

// Pestaña «Reportes» (20-nov): una tarjeta por ítem (reportes/catalogo.ts), con la misma tarjeta de las descargas del Dashboard distribución.
function Reportes({ catalogo }: { catalogo: Catalogo }) {
  return <PanelReportes titulo="Reportes" prefijo="rep" reportes={REPORTES_PTAP} plantas={catalogo.plantas.filter((p) => p.activa).map((p) => ({ codigo: p.codigo, nombre: p.nombre }))}
    ayuda="Un reporte por ítem, en Excel o CSV: una fila por envío o registro y cada variable en su columna, con su unidad. Toque una tarjeta para elegir el periodo y la planta."
    sinPermiso="Solo el supervisor de planta o el administrador descargan reportes." />;
}

// Dashboard PTAP (antes «Dashboard técnico»; supervisor y administrador). Las secciones salen de este registro: agregar «Estado del servicio» o «Eventos» cuando existan es registrar una sección
// con su componente; el resto de la pantalla no cambia. Las que aún no existen se muestran deshabilitadas, sin datos de ejemplo.
type Seccion = { clave: string; titulo: string; Componente?: (p: { catalogo: Catalogo }) => JSX.Element };
const SECCIONES: Seccion[] = [
  { clave: "resumen", titulo: "Resumen", Componente: Resumen },
  { clave: "registros", titulo: "Registros", Componente: RegistrosRecientes },
  { clave: "eventos", titulo: "Eventos", Componente: Eventos },
  { clave: "quimicos", titulo: "Químicos", Componente: QuimicosPTAP },      // Corte 7a (§29): bodega, ficha técnica, dosis óptima y esperado contra usado
  { clave: "personal", titulo: "Personal técnico", Componente: PersonalTecnico },
  { clave: "puntos", titulo: "Puntos", Componente: PuntosUbicacion },      // Corte 5b: ubicación de los puntos de muestreo
  { clave: "reportes", titulo: "Reportes", Componente: Reportes },
];

// §34: el encabezado es el común (CabeceraDashboard), con el selector PTAP | distribución adentro.
export function Dashboard({ correo, rotuloPerfil, onVolver, selector }: { correo: string; rotuloPerfil: string; onVolver: () => void; selector?: ReactNode }) {
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
      <CabeceraDashboard titulo="Dashboard PTAP" sesion={`${correo} · ${rotuloPerfil}`} onVolver={onVolver} selector={selector} etiqueta="Secciones del Dashboard PTAP"
        pestanas={SECCIONES.map((s) => ({ clave: s.clave, titulo: s.titulo, pronto: !s.Componente }))} activa={activa} onElegir={setActiva} />
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
