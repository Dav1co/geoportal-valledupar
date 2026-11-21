// Selector «Modo de trabajo» del área Comercial (rama «comercial-estilo», 20-nov-2026): la cápsula de modos de la guía visual (§5), como la de Técnica.
// Pestañas dentro de una cápsula gris; la elegida, en el color de Comercial con texto blanco. Reemplaza al desplegable; las opciones y lo que hace cada una no cambian.
// Es un grupo de opciones (radio): cambiar de modo no abre un panel debajo, cambia el mapa o abre Formatos de campo.
export type OpcionModo = { valor: string; nombre: string };

export function SelectorModoTrabajo({ opciones, valor, onCambio, id }: { opciones: OpcionModo[]; valor: string; onCambio: (v: string) => void; id?: string }) {
  function teclado(e: React.KeyboardEvent<HTMLDivElement>) {
    if (!["ArrowRight", "ArrowDown", "ArrowLeft", "ArrowUp"].includes(e.key)) return;
    e.preventDefault();
    const caja = e.currentTarget;
    const i = Math.max(0, opciones.findIndex((o) => o.valor === valor));
    const n = opciones[(i + (e.key === "ArrowRight" || e.key === "ArrowDown" ? 1 : opciones.length - 1)) % opciones.length];
    onCambio(n.valor);
    requestAnimationFrame(() => caja.querySelector<HTMLButtonElement>(`[data-modo="${n.valor}"]`)?.focus());
  }
  return (
    <div className="modo-capsula" role="radiogroup" aria-label="Modo de trabajo" id={id} onKeyDown={teclado}>
      {opciones.map((o) => (
        <button key={o.valor} type="button" role="radio" aria-checked={o.valor === valor} tabIndex={o.valor === valor ? 0 : -1} data-modo={o.valor}
          className="modo-opcion" onClick={() => onCambio(o.valor)}>{o.nombre}</button>
      ))}
    </div>
  );
}
