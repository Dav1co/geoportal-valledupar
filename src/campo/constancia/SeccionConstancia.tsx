import { activa, type ConfigConstancia, type ValorConstancia } from "./logica";
import "../acta/acta.css";
import "./constancia.css";

/** Sección opcional «Constancia por correo» (plegable). Solo aparece si el documento envía constancia. Sin la casilla marcada no se envía nada, aunque haya correo escrito.
 *  El texto de tratamiento de datos viene de la base (jurídica lo ajusta sin migrar). Toques de 44 px, teclado de correo y numérico. */
export function SeccionConstancia({ config, valor, onCambio, bloqueado }: {
  config: ConfigConstancia | null; valor: ValorConstancia; onCambio: (c: Partial<ValorConstancia>) => void; bloqueado?: boolean;
}) {
  if (!activa(config)) return null;
  return (
    <details className="constancia" open={valor.autoriza}>
      <summary className="constancia-resumen">Constancia por correo (opcional)</summary>
      <div className="constancia-cuerpo">
        <p className="campo-sub">Si la persona lo autoriza, recibirá una constancia de este registro. No es el acta: el acta física firmada es el documento con valor probatorio.</p>
        <label className="constancia-casilla">
          <input type="checkbox" checked={valor.autoriza} disabled={bloqueado} onChange={(e) => onCambio({ autoriza: e.target.checked })} />
          <span>Autorizo a EMDUPAR a enviarme la constancia de este registro</span>
        </label>
        <p className="constancia-texto" role="note">{config.texto}</p>
        {valor.autoriza && (
          <>
            <div className="acta-campo">
              <label className="campo-etiqueta" htmlFor="constancia-correo">Correo electrónico</label>
              <input id="constancia-correo" className="acta-input constancia-input" type="email" inputMode="email" autoComplete="off" autoCapitalize="none" maxLength={254} value={valor.correo} disabled={bloqueado} onChange={(e) => onCambio({ correo: e.target.value })} />
            </div>
            <div className="acta-campo">
              <label className="campo-etiqueta" htmlFor="constancia-celular">Celular (opcional, 10 dígitos)</label>
              <input id="constancia-celular" className="acta-input constancia-input" type="tel" inputMode="numeric" autoComplete="off" maxLength={14} value={valor.celular} disabled={bloqueado} onChange={(e) => onCambio({ celular: e.target.value })} />
            </div>
            <div className="acta-campo">
              <label className="campo-etiqueta" htmlFor="constancia-parte">¿A quién va la constancia?</label>
              <select id="constancia-parte" className="acta-input constancia-input" value={valor.parte} disabled={bloqueado} onChange={(e) => onCambio({ parte: e.target.value })}>
                <option value="">Seleccione…</option>
                {config.partes.map((p) => <option key={p.codigo} value={p.codigo}>{p.nombre}</option>)}
              </select>
            </div>
          </>
        )}
      </div>
    </details>
  );
}
