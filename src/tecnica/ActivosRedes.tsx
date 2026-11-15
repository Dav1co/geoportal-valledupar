import { useState } from "react";
import "./ficha.css";
import { apiRedes, type ActivoCorto } from "./apiRedes";
import { ErrorTec } from "./apiTecnica";
import { FichaActivo } from "./FichaActivo";

// Entrada a la ficha de activos de redes (Corte 1b): por código (del geoportal o de la capa) o «Activos cerca de mí».
// En el 1b la abren supervisor y administrador desde Técnica. El operador llega a la ficha desde el minimapa de los formularios (Corte 2),
// y el geovisor (Corte 6) la abre tocando un elemento. La posición del celular solo viaja en el cuerpo de la consulta y no se guarda.

type Sistema = "acueducto" | "alcantarillado" | null;
const SISTEMAS: { codigo: Sistema; nombre: string }[] = [{ codigo: null, nombre: "Todos" }, { codigo: "acueducto", nombre: "Acueducto" }, { codigo: "alcantarillado", nombre: "Alcantarillado" }];
const nf = new Intl.NumberFormat("es-CO", { maximumFractionDigits: 0 });

export function ActivosRedes({ onVolver }: { onVolver: () => void }) {
  const [pila, setPila] = useState<string[]>([]);           // fichas abiertas, la última arriba (volver regresa a la anterior)
  const [codigo, setCodigo] = useState("");
  const [sistema, setSistema] = useState<Sistema>(null);
  const [cerca, setCerca] = useState<{ activos: ActivoCorto[]; radio: number } | null>(null);
  const [estado, setEstado] = useState<"" | "gps" | "buscando">("");
  const [aviso, setAviso] = useState<string | null>(null);

  const abrir = (c: string) => setPila((p) => [...p, c]);
  if (pila.length > 0) {
    return <FichaActivo key={pila[pila.length - 1]} codigo={pila[pila.length - 1]} onAbrir={abrir}
      rotuloVolver={pila.length > 1 ? `Volver a ${pila[pila.length - 2]}` : "Volver a la búsqueda"} onVolver={() => setPila((p) => p.slice(0, -1))} />;
  }

  const buscarCodigo = (e: React.FormEvent) => {
    e.preventDefault();
    let c = codigo.trim();
    if (!c) { setAviso("Escriba el código del activo."); return; }
    if (/^[a-z]{3}-\d{6}$/i.test(c)) c = c.toUpperCase();          // código del geoportal: siempre en mayúsculas (el de la capa se deja como se escribió)
    setAviso(null); abrir(c);
  };

  const buscarCerca = (radio = 30) => {
    setAviso(null);
    if (!("geolocation" in navigator)) { setAviso("Este navegador no da la ubicación. Busque por código."); return; }
    setEstado("gps");
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setEstado("buscando");
        apiRedes.cercanos(pos.coords.latitude, pos.coords.longitude, sistema, radio)
          .then((r) => setCerca({ activos: r.activos, radio: r.radio_m }))
          .catch((e) => setAviso(e instanceof ErrorTec ? (e.tipo === "permiso" ? "No tiene permiso para consultar activos." : e.message) : "No se pudo consultar."))
          .finally(() => setEstado(""));
      },
      (err) => { setEstado(""); setAviso(err.code === err.PERMISSION_DENIED ? "Sin permiso de ubicación: actívelo en el navegador o busque por código." : "No se pudo obtener la ubicación. Intente de nuevo o busque por código."); },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 30000 },
    );
  };

  return (
    <div className="red-ficha">
      <header className="red-cabeza">
        <button type="button" className="red-volver" onClick={onVolver}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M15 6l-6 6 6 6" /></svg>
          Volver a Técnica
        </button>
        <span className="red-ceja">Distribución · catastro de activos</span>
        <h1 className="red-codigo red-titulo">Ficha de activos</h1>
        <span className="red-tipo">Busque un tubo, una válvula, un pozo u otro activo de la red.</span>
      </header>
      <div className="red-cuerpo">
        <form className="red-seccion" onSubmit={buscarCodigo} aria-labelledby="red-t-cod">
          <h2 id="red-t-cod">Por código</h2>
          <div className="tec-campo">
            <label htmlFor="red-codigo">Código del activo o de la capa</label>
            <input id="red-codigo" type="text" inputMode="text" autoCapitalize="characters" autoComplete="off" maxLength={120}
              placeholder="RED-000123, V85, P1902…" value={codigo} onChange={(e) => setCodigo(e.target.value)} />
          </div>
          <button type="submit" className="tec-boton">Abrir la ficha</button>
        </form>

        <section className="red-seccion" aria-labelledby="red-t-cerca">
          <h2 id="red-t-cerca">Cerca de mí</h2>
          <div className="red-chips" role="group" aria-label="Sistema">
            {SISTEMAS.map((s) => <button key={s.nombre} type="button" className="tec-chip-form" aria-pressed={sistema === s.codigo} onClick={() => { setSistema(s.codigo); setCerca(null); }}>{s.nombre}</button>)}
          </div>
          <button type="button" className="tec-boton-sec" disabled={estado !== ""} onClick={() => buscarCerca(30)}>
            {estado === "gps" ? "Tomando la ubicación…" : estado === "buscando" ? "Buscando…" : "Buscar activos a 30 m de mí"}
          </button>
          {cerca ? (
            cerca.activos.length > 0 ? (
              <div className="red-lista" aria-label="Activos cercanos">
                {cerca.activos.map((x) => (
                  <button key={x.codigo} type="button" className="red-fila" onClick={() => abrir(x.codigo)}>
                    <span className={x.prefijo === "RED" || x.prefijo === "CON" || x.prefijo === "COL" ? "red-icono red-icono-linea" : "red-icono"} aria-hidden="true" />
                    <span className="red-fila-txt">
                      <span className="red-fila-cod">{x.codigo}</span>
                      <span className="red-fila-sub">{x.tipo}{x.clase ? ` · ${x.clase}` : ""}{x.codigo_anterior ? ` · ${x.codigo_anterior}` : ""}</span>
                    </span>
                    <span className="red-fila-estado red-dist">{nf.format(x.distancia_m ?? 0)} m</span>
                  </button>
                ))}
              </div>
            ) : (
              <div className="red-vacio">
                No hay activos a {nf.format(cerca.radio)} m.
                {cerca.radio < 100 ? <> <button type="button" className="tec-enlace" onClick={() => buscarCerca(100)}>Buscar a 100 m</button></> : null}
              </div>
            )
          ) : null}
        </section>
        {aviso ? <p className="tec-aviso tec-aviso-error red-aviso" role="alert">{aviso}</p> : null}
      </div>
    </div>
  );
}
