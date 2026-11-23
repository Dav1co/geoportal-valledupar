// Salidas de una lista de campo (selección o retorno): Excel e impresión. EXCEPCIÓN ESCRITA (P2 del 22-nov): llevan nombre y dirección para la visita,
// nunca teléfono, correo ni identificación; el servidor registra cada salida antes de entregar las filas.
import type { Lista } from "./apiScrr";
import { fecha, fechaHora, pesos } from "./formato";

const esc = (s: unknown) => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const titulo = (l: Lista) => `${l.actividad}${l.ciclo ? ` · ciclo ${l.ciclo}` : ""} · cartera del ${fecha(l.fecha_dato)}`;

export async function descargarExcel(l: Lista) {
  const { LibroXlsx } = await import("../tecnica/xlsx");
  const libro = new LibroXlsx({ hoja: "Lista", anchos: [7, 13, 20, 30, 34, 22, 6, 12, 12, 10, 14, 34],
    encabezados: ["Orden", "Contrato", "Actividad", "Nombre", "Dirección", "Barrio", "Ciclo", "Ruta", "Reparto", "Facturas vencidas", "Saldo pendiente", "Observación del sistema"],
    leame: [["Lista", titulo(l)], ["Generada", `${fechaHora(l.generada_en)} por ${l.autor}`],
            ["Datos personales", "Lleva nombre y dirección del suscriptor solo para la visita de campo (excepción escrita de David, 22-nov). No se reenvía ni se publica; la descarga quedó registrada."],
            ["Deuda", "Saldo pendiente y facturas vencidas del día de la cartera usada."]] });
  await libro.agregarFilas(l.filas.map((f) => [f.orden, f.contrato, f.actividad ?? l.actividad, f.nombre, f.direccion, f.barrio, f.ciclo === null ? null : String(f.ciclo), f.ruta, f.codigo_reparto,
                                                f.facturas_vencidas, Number(f.saldo_pendiente), f.marca]));
  const url = URL.createObjectURL(await libro.finalizar());
  const a = document.createElement("a"); a.href = url; a.download = `lista_${l.actividad_codigo}${l.ciclo ? `_ciclo${l.ciclo}` : ""}_${l.fecha_dato}.xlsx`; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}

/** La ventana se abre en el mismo toque (si no, el navegador la bloquea) y aquí se llena. */
export function imprimir(l: Lista, w: Window) {
  w.document.write(`<!doctype html><html lang="es"><head><meta charset="utf-8"><title>${esc(titulo(l))}</title>
<style>body{font-family:Arial,Helvetica,sans-serif;font-size:11px;margin:12mm}h1{font-size:15px;margin:0 0 4px}p{margin:0 0 8px;color:#333}
table{border-collapse:collapse;width:100%}th,td{border:1px solid #999;padding:3px 4px;text-align:left;vertical-align:top}th{background:#eee}td.n{text-align:right}
@page{size:landscape;margin:10mm}</style></head><body>
<h1>${esc(titulo(l))}</h1>
<p>Generada ${esc(fechaHora(l.generada_en))} por ${esc(l.autor)} · ${l.filas.length} contratos · Uso exclusivo de la visita de campo (impresión registrada).</p>
<table><thead><tr><th>#</th><th>Contrato</th><th>Actividad</th><th>Nombre</th><th>Dirección</th><th>Barrio</th><th>Ruta</th><th>Reparto</th><th>Vencidas</th><th>Saldo</th><th>Observación</th><th>Resultado</th></tr></thead><tbody>
${l.filas.map((f) => `<tr><td>${f.orden}</td><td>${esc(f.contrato)}</td><td>${esc(f.actividad ?? l.actividad)}</td><td>${esc(f.nombre)}</td><td>${esc(f.direccion)}</td><td>${esc(f.barrio)}</td><td>${esc(f.ruta)}</td><td>${esc(f.codigo_reparto)}</td><td class="n">${f.facturas_vencidas}</td><td class="n">${esc(pesos(f.saldo_pendiente))}</td><td>${esc(f.marca)}</td><td></td></tr>`).join("")}
</tbody></table><script>window.onload=function(){window.print()}</script></body></html>`);
  w.document.close();
}
