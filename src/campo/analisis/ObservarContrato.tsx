import { useState } from "react";
import "../documentos/documentos.css";
import { apiCampo, ErrorCampo } from "../apiCampo";
import { BORRADOR_VACIO, OBSERVACIONES, RELACIONES, cuerpoObservacion, faltasObservacion, textoEnviada, type Borrador, type Contacto, type TipoObservacion } from "./observacion";

// Investigación y Análisis (Code B, 23-nov) · «Observación sobre este contrato», al final de la ficha del Análisis (no aparece con el comodín ni con un contrato no encontrado).
// Toda observación llega como AVISO al supervisor (Actas registradas → Actividades derivadas, Origen = Análisis de contrato); ninguna crea una actividad sola.
// «Actualización de datos» pide datos personales (Ley 1581), todos opcionales: se mandan una sola vez y se borran de la pantalla al enviar; quien los escribió no los
// vuelve a ver (solo el supervisor de campo y el administrador, al abrir el aviso). Nada se guarda en el navegador.
export function ObservarContrato({ contrato }: { contrato: string }) {
  const [b, setB] = useState<Borrador>(BORRADOR_VACIO);
  const [confirmar, setConfirmar] = useState(false);
  const [enviando, setEnviando] = useState(false);
  const [aviso, setAviso] = useState<{ ok: boolean; texto: string } | null>(null);
  const faltas = faltasObservacion(b);
  const poner = (p: Partial<Borrador>) => { setB((x) => ({ ...x, ...p })); setConfirmar(false); setAviso(null); };
  const ponerC = (p: Partial<Contacto>) => setB((x) => ({ ...x, contacto: { ...x.contacto, ...p } }));
  const elegida = OBSERVACIONES.find((o) => o.codigo === b.tipo);

  async function enviar() {
    if (enviando || faltas.length) return;
    setEnviando(true); setAviso(null);
    try {
      const r = await apiCampo.analisisObservar(cuerpoObservacion(contrato, b));
      setB(BORRADOR_VACIO);                                   // los datos de contacto no quedan en la pantalla
      setAviso({ ok: true, texto: textoEnviada(r) });
    } catch (e) {
      setAviso({ ok: false, texto: e instanceof ErrorCampo ? e.message : "No se pudo enviar la observación." });
    } finally { setEnviando(false); setConfirmar(false); }
  }

  return (
    <section className="tec-tarjeta ac-obs" aria-labelledby="ac-obs-tit" data-testid="observacion">
      <h3 id="ac-obs-tit">Observación sobre este contrato</h3>
      <p className="campo-sub">Llega como aviso al supervisor. No escriba nombres, cédulas ni teléfonos en los textos.</p>
      <div className="doc-opciones ac-obs-opciones" role="radiogroup" aria-label="Observación">
        {OBSERVACIONES.map((o) => (
          <label key={o.codigo} className={`doc-opcion${b.tipo === o.codigo ? " doc-opcion-on" : ""}`}>
            <input type="radio" name="ac-obs" data-obs={o.codigo} checked={b.tipo === o.codigo} onChange={() => poner({ tipo: o.codigo as TipoObservacion })} />{o.nombre}
          </label>))}
      </div>
      {elegida ? <p className="campo-sub" data-obs-ayuda>{elegida.ayuda}</p> : null}

      {b.tipo === "direccion_errada" ? (
        <div className="tec-campo">
          <label htmlFor="ac-obs-dir">Dirección correcta (opcional)</label>
          <input id="ac-obs-dir" type="text" maxLength={120} autoComplete="off" value={b.direccion} onChange={(e) => poner({ direccion: e.target.value })} />
        </div>) : null}

      {b.tipo === "otra" ? (
        <div className="tec-campo">
          <label htmlFor="ac-obs-texto">Observación (de 3 a 120 caracteres)</label>
          <textarea id="ac-obs-texto" className="campo-texto" rows={2} maxLength={120} value={b.texto} onChange={(e) => poner({ texto: e.target.value })} />
          <span className="campo-contador">{b.texto.trim().length} de 120</span>
        </div>) : null}

      {b.tipo === "actualizacion_datos" ? (
        <fieldset className="ac-obs-contacto">
          <legend>Datos de contacto (todos opcionales)</legend>
          <p className="campo-sub"><span className="ac-tag-personal">dato personal</span> Solo los verá el supervisor al abrir el aviso. No salen en listas ni descargas.</p>
          <div className="tec-campo"><label htmlFor="ac-obs-nombre">Nombre</label>
            <input id="ac-obs-nombre" type="text" maxLength={80} autoComplete="off" value={b.contacto.nombre} onChange={(e) => ponerC({ nombre: e.target.value })} /></div>
          <div className="tec-campo"><label htmlFor="ac-obs-cedula">Cédula (solo números)</label>
            <input id="ac-obs-cedula" type="text" inputMode="numeric" maxLength={10} autoComplete="off" value={b.contacto.cedula} onChange={(e) => ponerC({ cedula: e.target.value.replace(/\D/g, "") })} /></div>
          <div className="tec-campo"><label htmlFor="ac-obs-tel">Teléfono (7 o 10 números)</label>
            <input id="ac-obs-tel" type="text" inputMode="tel" maxLength={16} autoComplete="off" value={b.contacto.telefono} onChange={(e) => ponerC({ telefono: e.target.value })} /></div>
          <div className="tec-campo"><label htmlFor="ac-obs-correo">Correo</label>
            <input id="ac-obs-correo" type="text" inputMode="email" maxLength={120} autoComplete="off" spellCheck={false} value={b.contacto.correo} onChange={(e) => ponerC({ correo: e.target.value })} /></div>
          <div className="tec-campo"><label htmlFor="ac-obs-rel">Relación con el predio</label>
            <select id="ac-obs-rel" value={b.contacto.relacion} onChange={(e) => ponerC({ relacion: e.target.value })}>
              <option value="">Sin indicar</option>{RELACIONES.map((r) => <option key={r.codigo} value={r.codigo}>{r.nombre}</option>)}
            </select></div>
        </fieldset>) : null}

      {b.tipo && faltas.length ? <ul className="campo-error ac-obs-faltas" role="alert">{faltas.map((f) => <li key={f}>{f}</li>)}</ul> : null}
      {aviso ? <p className={aviso.ok ? "ac-obs-ok" : "campo-error"} role={aviso.ok ? "status" : "alert"} data-obs-aviso>{aviso.texto}</p> : null}

      {b.tipo ? (
        confirmar ? (
          <div className="ac-obs-confirmar" role="group" aria-label="Confirmar el aviso">
            <p className="campo-sub">¿Enviar el aviso «{elegida?.nombre}» del contrato {contrato} al supervisor?</p>
            <div className="ac-atajos-botones">
              <button type="button" className="tec-boton" disabled={enviando} onClick={enviar} data-obs-enviar>{enviando ? "Enviando…" : "Sí, enviar"}</button>
              <button type="button" className="tec-boton-sec" disabled={enviando} onClick={() => setConfirmar(false)}>No</button>
            </div>
          </div>
        ) : (
          <div className="ac-atajos-botones">
            <button type="button" className="tec-boton" disabled={faltas.length > 0} onClick={() => setConfirmar(true)} data-obs-pedir>Enviar al supervisor</button>
            <button type="button" className="tec-boton-sec" onClick={() => poner(BORRADOR_VACIO)}>Cancelar</button>
          </div>
        )
      ) : null}
    </section>
  );
}
