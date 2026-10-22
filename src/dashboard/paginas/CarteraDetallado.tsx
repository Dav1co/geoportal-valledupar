import { useEffect, useMemo, useState } from "react";
import { biCache } from "../cacheBi";
import { comoCarteraEdadDim, type CarteraEdadDim } from "../tipos";
import { SinDatos } from "../SinDatos";
import { PanelFiltros, TODOS, type DefFiltro } from "../PanelFiltros";
import { MarcaFiltro, Plegable, usePlegables } from "../Plegable";
import { ZonaMapaCartera } from "./CarteraMapa";
import { normalizarFiltrosCartera, useEstadoSesion } from "../memoriaSesion";
import { ESTRATOS_FILTRO, USOS_FILTRO, periodosDe } from "../edadCarteraCalculo";
import { ROTULO } from "../rotulos";
import { AntiguedadEdad, MetodologiaEdad, PanoramaEdad, UsoEstratoEdad } from "./CarteraEdad";
import { CarteraCicloBarrio } from "./CarteraCicloBarrio";
import { ZonaMovimientoMora, ZonaSuspensionesCortes } from "./CarteraMora";
import { ZonaCarteraConcepto } from "./CarteraConcepto";

// Cartera desagregada, en zonas como Pérdidas:
//  1. Panorama (abierta): fichas y mezcla por tramo de edad.
//  2. Antigüedad (abierta al entrar): las 19 etiquetas de edad y su evolución.
//  3. Por uso y estrato · 4. Por ciclo y barrio (lo que ya existía) · 5. Metodología: plegables cerrados que no montan ni consultan hasta abrirse.
// La dimensión de edad (v_cartera_edad_dim) se trae UNA vez con todos los períodos (biCache) y alimenta las zonas 1 a 3. Los filtros de uso y
// estrato son compartidos por todas las zonas y se recuerdan durante la sesión de la pestaña, por período; comuna, barrio y ciclo viven en la zona 4.

type Props = { periodo: string; onIrAPeriodo?: (p: string) => void };

// Al cambiar de período se reinicia la pantalla (clave = período): el estado recordado es por período y no se arrastra de uno a otro.
export function CarteraDetallado(props: Props) {
  return <CarteraDetalladoPeriodo key={props.periodo} {...props} />;
}

const PLEGABLES = ["cd-mapa", "cd-antig", "cd-uso", "cd-mov", "cd-scrr", "cd-conc", "cd-ciclo", "cd-metod"];
const PLEGABLES_INICIAL = { "cd-antig": true };
const FILTROS_VACIO = { uso: TODOS, subcategoria: TODOS };

function CarteraDetalladoPeriodo({ periodo, onIrAPeriodo }: Props) {
  const [filas, setFilas] = useState<CarteraEdadDim[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const pl = usePlegables(PLEGABLES_INICIAL, `cartera.${periodo}.plegables`, PLEGABLES);
  const [valores, setValores] = useEstadoSesion<Record<string, string>>(`cartera.${periodo}.filtros`, FILTROS_VACIO, normalizarFiltrosCartera);

  function cargar() {
    setError(null);
    setFilas(null);
    biCache("v_cartera_edad_dim")
      .then((r) => setFilas((r.datos ?? []).map(comoCarteraEdadDim)))
      .catch((e: Error) => setError(e.message));
  }
  useEffect(cargar, []);

  const filtros: DefFiltro[] = useMemo(
    () => [
      { id: "uso", etiqueta: "Uso", opciones: USOS_FILTRO.map((u) => u.nombre) },
      {
        id: "subcategoria",
        etiqueta: "Estrato",
        visible: (v) => v.uso === TODOS || v.uso === "Residencial",
        opciones: ESTRATOS_FILTRO.map((e) => e.nombre),
        ayuda: "Solo con uso Todos o Residencial",
      },
    ],
    [],
  );
  const cambiarValores = (v: Record<string, string>) => setValores({ uso: v.uso ?? TODOS, subcategoria: v.subcategoria ?? TODOS });
  const limpiar = () => setValores(FILTROS_VACIO);

  if (error) {
    return (
      <div className="dash-estado">
        <p>No se pudo cargar la {ROTULO.carteraDesagregada.toLowerCase()}: {error}</p>
        <button className="dash-boton" onClick={cargar}>Reintentar</button>
      </div>
    );
  }
  if (!filas) return <div className="dash-estado">Cargando la edad de la cartera…</div>;
  const disponibles = periodosDe(filas);
  if (!disponibles.includes(periodo)) {
    return <SinDatos periodo={periodo} fuente="cartera por edad (detalle de cartera)" disponibles={disponibles} onIr={onIrAPeriodo} />;
  }

  const marca = <MarcaFiltro valores={valores} />;
  const uso = valores.uso ?? TODOS;
  const estrato = valores.subcategoria ?? TODOS;

  return (
    <div className="dash-con-panel">
      <PanelFiltros filtros={filtros} valores={valores} onCambio={cambiarValores} />
      <div className="dash-con-panel-cuerpo">
        <h2 className="dash-zona">Panorama de la cartera</h2>
        <PanoramaEdad filas={filas} periodo={periodo} uso={uso} estrato={estrato} onLimpiar={limpiar} />

        <h2 className="dash-zona">Mapa de calor</h2>
        <Plegable id="cd-mapa" diferido titulo="Mapa de calor de la cartera" marca={<span className="dash-sin-filtro">No depende de los filtros de uso y estrato</span>} abierto={!!pl.abiertos["cd-mapa"]} onCambio={(o) => pl.cambiar("cd-mapa", o)}>
          <ZonaMapaCartera periodo={periodo} />
        </Plegable>

        <h2 className="dash-zona">Edad de la cartera</h2>
        <Plegable id="cd-antig" titulo="Antigüedad (vejez): etiquetas de edad y evolución" marca={marca} abierto={!!pl.abiertos["cd-antig"]} onCambio={(o) => pl.cambiar("cd-antig", o)}>
          <AntiguedadEdad filas={filas} periodo={periodo} uso={uso} estrato={estrato} />
        </Plegable>
        <Plegable id="cd-uso" diferido titulo="Por uso y estrato" marca={marca} abierto={!!pl.abiertos["cd-uso"]} onCambio={(o) => pl.cambiar("cd-uso", o)}>
          <UsoEstratoEdad filas={filas} periodo={periodo} uso={uso} estrato={estrato} />
        </Plegable>

        <h2 className="dash-zona">Mora y suspensiones</h2>
        <Plegable id="cd-mov" diferido titulo="Movimiento de la mora" marca={marca} abierto={!!pl.abiertos["cd-mov"]} onCambio={(o) => pl.cambiar("cd-mov", o)}>
          <ZonaMovimientoMora periodo={periodo} uso={uso} estrato={estrato} onLimpiar={limpiar} />
        </Plegable>
        <Plegable id="cd-scrr" diferido titulo="Suspensiones y cortes (SCRR)" marca={marca} abierto={!!pl.abiertos["cd-scrr"]} onCambio={(o) => pl.cambiar("cd-scrr", o)}>
          <ZonaSuspensionesCortes periodo={periodo} uso={uso} estrato={estrato} onLimpiar={limpiar} />
        </Plegable>

        <h2 className="dash-zona">Composición por concepto</h2>
        <Plegable id="cd-conc" diferido titulo="Cartera por concepto" marca={marca} abierto={!!pl.abiertos["cd-conc"]} onCambio={(o) => pl.cambiar("cd-conc", o)}>
          <ZonaCarteraConcepto periodo={periodo} uso={uso} estrato={estrato} onLimpiar={limpiar} />
        </Plegable>

        <h2 className="dash-zona">Ciclo y barrio</h2>
        <Plegable id="cd-ciclo" diferido titulo="Por ciclo y barrio (barrios, antigüedad no financiada, foco de cobranza y ciclo)" marca={marca} abierto={!!pl.abiertos["cd-ciclo"]} onCambio={(o) => pl.cambiar("cd-ciclo", o)}>
          <div className="dash-aviso">
            Esta zona usa los tramos de la tabla de ciclo y barrio, que lee las etiquetas como <b>límite inferior</b> (su «Más de 360 días» incluye
            la etiqueta 360). Las zonas de edad de arriba usan la lectura provisional de límites superiores, por eso las cifras de «Más de 360 días»
            difieren entre ambas zonas. La lectura de los límites sigue pendiente de confirmar; el total y la cartera financiada son los mismos.
          </div>
          <CarteraCicloBarrio
            periodo={periodo}
            uso={uso}
            subcategoria={estrato}
            onCambioCompartidos={(u, s) => setValores({ uso: u, subcategoria: s })}
          />
        </Plegable>

        <h2 className="dash-zona">Metodología</h2>
        <Plegable id="cd-metod" diferido titulo="Metodología y sustento" abierto={!!pl.abiertos["cd-metod"]} onCambio={(o) => pl.cambiar("cd-metod", o)}>
          <MetodologiaEdad />
        </Plegable>
      </div>
    </div>
  );
}
