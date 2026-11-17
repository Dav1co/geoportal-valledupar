// Corte 14: un aviso («activos por levantar») pide abrir la pestaña Por verificar ya en el filtro «Otros activos por levantamiento».
let pedido = false;
export function pedirLevantar() { pedido = true; try { window.dispatchEvent(new Event("lev-pedir")); } catch { /* sin eventos: se toma al montar */ } }
export function tomarPedidoLevantar(): boolean { const p = pedido; pedido = false; return p; }
