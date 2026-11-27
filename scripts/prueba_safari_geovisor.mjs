// [Code B] Geovisor compacto (27-nov): prueba en SAFARI del Mac por WebDriver (safaridriver), contra la revisión local de los Cuadernos
// (CUADERNOS_REVISION=1 node scripts/prueba_chrome_cuadernos.mjs …, puerto 55993; base local del Code B, nunca producción).
// Revisa: la fila única, los íconos SVG de la barra (↶ ↷ ya no son texto), el porcentaje del mapa, la pantalla completa de Safari, y que el PDF
// (con y sin pantalla completa) y la captura salgan con mapa (variedad de colores dentro del marco). Requiere «Permitir automatización remota» en Safari.
// Uso: node scripts/prueba_safari_geovisor.mjs [puerto-safaridriver] [puerto-revision] [capturas]
import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
const args = process.argv.slice(2);
if (args.some((a) => a === "-h" || a === "--help")) { console.log("Uso: node scripts/prueba_safari_geovisor.mjs [puerto-safaridriver] [puerto-revision] [capturas]"); process.exit(0); }
const rara = args.find((a) => a.startsWith("-")); if (rara) { console.error(`Opción desconocida: ${rara}`); process.exit(2); }
const SD = `http://127.0.0.1:${args[0] || 4447}`, APP = `http://127.0.0.1:${args[1] || 55993}`, CAP = args[2] || "/tmp/capturas_safari";
mkdirSync(CAP, { recursive: true });
const pausa = (ms) => new Promise((r) => setTimeout(r, ms));
const resultados = []; const ok = (n, c, d = "") => { resultados.push(!!c); console.log((c ? "OK    " : "FALLA ") + n + (c ? "" : " → " + String(d).slice(0, 400))); };
async function wd(metodo, ruta, cuerpo) {
  const r = await fetch(SD + ruta, { method: metodo, headers: { "Content-Type": "application/json" }, body: cuerpo ? JSON.stringify(cuerpo) : undefined });
  const j = await r.json(); if (!r.ok) throw new Error(`${metodo} ${ruta}: ${JSON.stringify(j.value).slice(0, 300)}`); return j.value;
}
const ses = await wd("POST", "/session", { capabilities: { alwaysMatch: { browserName: "safari" } } }), S = `/session/${ses.sessionId}`;
const js = (cuerpo, ...a) => wd("POST", `${S}/execute/sync`, { script: cuerpo, args: a });
const jsa = (cuerpo, ...a) => wd("POST", `${S}/execute/async`, { script: `const fin = arguments[arguments.length - 1]; (async () => { ${cuerpo} })().then(fin, (e) => fin({ err: String(e) }));`, args: a });
const esperar = async (cond, ms = 60000) => { const t = Date.now() + ms; for (;;) { if (await js(`return !!(${cond});`)) return true; if (Date.now() > t) return false; await pausa(300); } };
const clicReal = async (sel) => { const e = await wd("POST", `${S}/element`, { using: "css selector", value: sel }); await wd("POST", `${S}/element/${Object.values(e)[0]}/click`, {}); await pausa(250); };
const foto = async (n) => writeFileSync(join(CAP, `${n}.png`), Buffer.from(await wd("GET", `${S}/screenshot`), "base64"));
// variedad de colores de las páginas del PDF que se acaba de preparar (JPEG dentro del PDF) o de la captura descargada
const VARIEDAD = `async function variedad(blob, caja) { const bm = await createImageBitmap(blob); const c = document.createElement("canvas"); c.width = 160; c.height = 160; const x = c.getContext("2d");
  x.drawImage(bm, bm.width * caja[0], bm.height * caja[1], bm.width * (caja[2] - caja[0]), bm.height * (caja[3] - caja[1]), 0, 0, 160, 160);
  const d = x.getImageData(0, 0, 160, 160).data, s = new Set(); for (let i = 0; i < d.length; i += 4) s.add((d[i] >> 3 << 10) | (d[i + 1] >> 3 << 5) | (d[i + 2] >> 3)); return s.size; }`;
async function pdf(n) {
  await js(`delete window.__impresion; document.querySelector("[data-testid=cua-mas]").click(); setTimeout(() => document.querySelector("[data-testid=cua-pdf]").click(), 200);`);
  await esperar(`document.querySelector("[data-testid=imprimir-listo]") || document.querySelector("[data-testid=dialogo-imprimir] [role=alert]")`, 600000);
  const r = await jsa(`${VARIEDAD}
    const a = document.querySelector("[data-testid=imprimir-descargar]"); if (!a) return { err: document.querySelector("[data-testid=dialogo-imprimir]").innerText };
    const b = new Uint8Array(await (await fetch(a.href)).arrayBuffer()), v = [];
    for (let i = 0; i < b.length - 3; i++) if (b[i] === 0xff && b[i + 1] === 0xd8 && b[i + 2] === 0xff) { let j = i; while (j < b.length - 1 && !(b[j] === 0xff && b[j + 1] === 0xd9 && b[j + 2] === 0x0a)) j++;
      v.push(await variedad(new Blob([b.subarray(i, j + 2)], { type: "image/jpeg" }), [0.09, 0.06, 0.91, 0.78])); i = j; }
    let s = ""; for (let i = 0; i < b.length; i += 32768) s += String.fromCharCode(...b.subarray(i, i + 32768));
    return { v, paginas: window.__impresion?.paginas, b64: btoa(s) };`);
  if (r.b64) writeFileSync(join(CAP, `${n}.pdf`), Buffer.from(r.b64, "base64"));
  await js(`[...document.querySelectorAll("[data-testid=dialogo-imprimir] button")].find((b) => /Cerrar|Cancelar/.test(b.textContent)).click();`);
  return r;
}
async function captura() {
  await js(`document.querySelector("[data-testid=cua-mas]").click(); setTimeout(() => document.querySelector("[data-testid=cua-capturar]").click(), 200);`);
  await esperar(`document.querySelector("[data-testid=cua-captura-descargar]")`);
  await js(`window.__descargas = []; if (!HTMLAnchorElement.prototype.__orig) { HTMLAnchorElement.prototype.__orig = HTMLAnchorElement.prototype.click; HTMLAnchorElement.prototype.click = function () { if (this.download) window.__descargas.push(this.href); else this.__orig(); }; }
    document.querySelector("[data-testid=cua-captura-descargar]").click();`);
  await esperar(`document.querySelector("[data-testid=cua-captura-hecho]") || document.querySelector("[data-testid=cua-captura-error]")`);
  const r = await jsa(`${VARIEDAD} const h = window.__descargas[0]; if (!h) return { err: document.querySelector("[data-testid=cua-captura-error]")?.innerText }; const b = await (await fetch(h)).blob(); return { v: await variedad(b, [0, 0, 1, 1]), ...window.__captura };`);
  await js(`document.querySelector("[data-testid=cua-dialogo-capturar] .geo-cerrar").click();`);
  return r;
}
try {
  await wd("POST", `${S}/window/rect`, { width: 1280, height: 860, x: 0, y: 0 });
  await wd("POST", `${S}/url`, { url: `${APP}/?rol=sup` });
  await esperar(`[...document.querySelectorAll("button")].some((b) => b.textContent.trim().startsWith("Geovisor técnico"))`);
  await js(`[...document.querySelectorAll("button")].find((b) => b.textContent.trim().startsWith("Geovisor técnico")).click();`);
  await esperar(`document.querySelector(".geo-mapa")?.__mapa && document.querySelector("[data-testid=cuadernos]")`);
  await js(`const m = document.querySelector(".geo-mapa").__mapa; m.jumpTo({ center: [-73.2532, 10.4631], zoom: 15.5 });`);
  await esperar(`(() => { const m = document.querySelector(".geo-mapa").__mapa; return m.loaded() && m.areTilesLoaded(); })()`); await pausa(800);
  const ua = await js(`return navigator.userAgent;`);
  ok(`S01 Safari de verdad (${/Version\/([\d.]+)/.exec(ua)?.[1] ?? "?"}) abre el geovisor del supervisor`, /Safari/.test(ua) && !/Chrome/.test(ua), ua);
  const fila = await js(`const v = [...document.querySelectorAll(".geo-barra button")].filter((b) => b.offsetParent !== null); return { tops: [...new Set(v.map((b) => Math.round(b.getBoundingClientRect().top)))].length, alto: Math.round(document.querySelector(".geo-barra").getBoundingClientRect().height), b: v.map((b) => Math.round(b.getBoundingClientRect().height)) };`);
  ok(`S02 una sola fila (${fila.alto} px) con botones de 36 px`, fila.tops === 1 && fila.alto <= 46 && fila.b.every((h) => h >= 36 && h <= 38), JSON.stringify(fila));
  // cuaderno nuevo en edición
  await js(`document.querySelector("[data-testid=cuadernos]").click();`); await esperar(`document.querySelector("[data-testid=cua-nuevo]")`);
  await js(`document.querySelector("[data-testid=cua-nuevo]").click();`); await esperar(`document.querySelector("#cua-n-titulo")`);
  await js(`const e = document.querySelector("#cua-n-titulo"); Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(e, "ZTCUA Safari " + Date.now()); e.dispatchEvent(new Event("input", { bubbles: true })); document.querySelector("[data-testid=cua-crear]").click();`);
  await esperar(`window.__cuaderno?.modo === "editar"`);
  const iconos = await js(`return ["cua-h-problema", "cua-h-postit", "cua-deshacer-paso", "cua-rehacer-paso"].map((id) => { const b = document.querySelector("[data-testid=" + id + "]"); return { svg: !!b.querySelector("svg path"), texto: b.textContent.trim() }; });`);
  ok(`S03 la barra vertical lleva íconos SVG (↶ ↷ ya no son caracteres de texto)`, iconos.every((i) => i.svg && i.texto === ""), JSON.stringify(iconos));
  const pct = await js(`const r = document.querySelector(".geo-cuerpo").getBoundingClientRect(); return Math.round(100 * (Math.min(r.bottom, innerHeight) - r.top) / innerHeight);`);
  const alto = await js(`return innerHeight;`);
  ok(`S04 con el cuaderno en Editar el mapa ocupa ${pct} % de la ventana de Safari (${alto} px de alto, con la barra azul de la página)`, pct >= 80, pct);
  await js(`document.querySelector("[data-testid=cua-h-referencia]").click();`);
  await js(`const m = document.querySelector(".geo-mapa").__mapa; m.fire("click", { point: m.project([-73.2532, 10.4631]), lngLat: { lng: -73.2532, lat: 10.4631 }, originalEvent: new MouseEvent("click") });`);
  await pausa(400); await js(`document.querySelector("[data-testid=cua-ficha] .geo-cerrar")?.click();`);
  await foto("s04_editar_1280");
  // PDF y captura SIN pantalla completa
  let r = await pdf("safari_normal");
  ok(`S05 PDF del cuaderno en Safari: ${r.paginas} páginas, todas con mapa (${(r.v ?? []).join(", ")} colores)`, r.paginas === 3 && r.v?.length === 3 && r.v.every((v) => v > 25), JSON.stringify({ ...r, b64: undefined }));
  let k = await captura();
  ok(`S06 captura en Safari con mapa (${k.v} colores, ${k.ancho} × ${k.alto} px)`, k.v > 25, JSON.stringify(k));
  // pantalla completa (clic real: Safari pide un gesto del usuario)
  await clicReal("[data-testid=pantalla-completa]"); await pausa(1500);
  const fc = await js(`const d = document; return { el: (d.fullscreenElement || d.webkitFullscreenElement)?.className ?? null, modo: d.querySelector(".geo").dataset.completa ?? "", pct: (() => { const r = d.querySelector(".geo-cuerpo").getBoundingClientRect(); return Math.round(100 * r.height / innerHeight); })() };`);
  ok(`S07 ⛶ en Safari: pantalla completa del navegador (${fc.modo}); el mapa ocupa ${fc.pct} %`, fc.modo === "api" && /geo/.test(fc.el ?? "") && fc.pct >= 97, JSON.stringify(fc));
  await foto("s07_completa_1280");
  r = await pdf("safari_completa");
  ok(`S08 PDF en pantalla completa de Safari: ${r.paginas} páginas con mapa (${(r.v ?? []).join(", ")})`, r.paginas === 3 && r.v?.length === 3 && r.v.every((v) => v > 25), JSON.stringify({ ...r, b64: undefined }));
  k = await captura();
  ok(`S09 captura en pantalla completa de Safari con mapa (${k.v} colores)`, k.v > 25, JSON.stringify(k));
  const sigue = await js(`return document.querySelector(".geo").dataset.completa ?? "";`);
  ok(`S10 sigue en pantalla completa después de imprimir y capturar`, sigue === "api", sigue);
  await clicReal("[data-testid=salir-completa]"); await pausa(1200);
  ok(`S11 el botón de salir deja la pantalla completa y vuelve la fila`, await js(`return !document.querySelector(".geo").dataset.completa && !document.fullscreenElement && !document.webkitFullscreenElement && document.querySelector(".geo-barra").offsetParent != null;`));
  await js(`document.querySelector(".geo-volver").click();`); await pausa(400);
  ok(`S12 con el cambio sin guardar, salir sigue preguntando (Guardar, Salir sin guardar o Cancelar)`, await js(`return !!document.querySelector("[data-testid=cua-dialogo-salir]");`));
  await js(`document.querySelector("[data-testid=cua-salir-sin]").click();`);
} catch (e) { ok("la prueba de Safari terminó", false, e.message); }
finally { await wd("DELETE", S).catch(() => {}); }
const mal = resultados.filter((x) => !x).length;
console.log(`\nRESULTADO: ${resultados.length - mal} de ${resultados.length}${mal ? "" : " — SIN FALLAS"}`); process.exit(mal ? 1 : 0);
