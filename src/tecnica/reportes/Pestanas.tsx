import { useEffect, useState } from "react";
import type { Catalogo } from "../apiDashboard";
import { apiQuimicos } from "../apiQuimicos";
import { apiGestion } from "../apiRedes";
import { REPORTES_DISTRIBUCION, REPORTES_PTAP, type FuenteFiltro, type Opcion } from "./catalogo";
import { PanelReportes, type Listas } from "./PanelReportes";

// Las dos pestañas: «Reportes» del Dashboard PTAP y «Descargas» del Dashboard distribución. Cada una junta las listas de sus filtros (de lo que el dashboard
// ya tiene, o de una ruta que ya existe) y usa la tarjeta común. Si una lista no carga, su filtro queda en «Todos…» y la tarjeta lo dice.

/** Dashboard PTAP: plantas, puntos y zonas del catálogo del dashboard; los químicos, de «quimicos_catalogo» (la ruta de la pestaña Químicos). */
export function ReportesPTAP({ catalogo }: { catalogo: Catalogo }) {
  const [quimicos, setQuimicos] = useState<Opcion[] | null>(null);
  const [error, setError] = useState<FuenteFiltro[]>([]);
  useEffect(() => {
    let vivo = true;
    apiQuimicos.catalogo().then((c) => { if (vivo) setQuimicos(c.quimicos.filter((q) => q.activo).map((q) => ({ codigo: q.codigo, nombre: q.nombre }))); })
      .catch(() => { if (vivo) setError(["quimicos"]); });
    return () => { vivo = false; };
  }, []);
  const listas: Listas = {
    plantas: catalogo.plantas.filter((x) => x.activa).map((x) => ({ codigo: x.codigo, nombre: x.nombre })),
    puntos: catalogo.puntos.filter((x) => x.activo).map((x) => ({ codigo: x.codigo, nombre: `${x.codigo} · ${x.nombre}` })),
    zonas: catalogo.zonas.map((z) => ({ codigo: z, nombre: z.charAt(0).toUpperCase() + z.slice(1) })),
    quimicos: quimicos ?? [],
  };
  return <PanelReportes titulo="Reportes" prefijo="rep" reportes={REPORTES_PTAP} listas={listas} listasConError={error}
    ayuda="Un reporte por ítem, en Excel o CSV: una fila por envío o registro y cada variable en su columna, con su unidad. Toque una tarjeta para elegir el periodo y los filtros."
    sinPermiso="Solo el supervisor de planta o el administrador descargan reportes." />;
}

/** Dashboard distribución: los tipos de activo, del catálogo de redes (la ruta de la pestaña Catálogo). El sector se escribe (número). */
export function DescargasDistribucion() {
  const [tipos, setTipos] = useState<Opcion[] | null>(null);
  const [error, setError] = useState<FuenteFiltro[]>([]);
  useEffect(() => {
    let vivo = true;
    apiGestion.catalogo().then((c) => { if (vivo) setTipos(c.tipos.filter((t) => t.activo).map((t) => ({ codigo: t.prefijo, nombre: `${t.nombre_visible || t.nombre} (${t.prefijo})` })).sort((a, b) => a.nombre.localeCompare(b.nombre, "es"))); })
      .catch(() => { if (vivo) setError(["tipos_activo"]); });
    return () => { vivo = false; };
  }, []);
  return <PanelReportes titulo="Descargas" prefijo="dsc" reportes={REPORTES_DISTRIBUCION} listas={{ tipos_activo: tipos ?? [] }} listasConError={error}
    ayuda="Una descarga por formulario, en Excel o CSV: una fila por registro y cada dato en su columna. Toque una tarjeta para elegir el periodo y los filtros."
    sinPermiso="Solo el supervisor de distribución o el administrador descargan." />;
}
