// Prueba en Chrome REAL de la compresión de las fotos en el celular (src/lib/comprimirFoto.ts y src/campo/camara.ts), a 390 px (táctil) y 1280 px.
// Mide con FOTOS REALES (las de la carpeta que se le pase: JPEG de cámara de 3.000 a 4.100 px):
//   · cámara de campo: la foto se pasa como el video de la cámara (canvas.captureStream a 1.920 × 1.080, o 2.560 × 1.440 para 2.048 px) y se toma con
//     capturarFoto, igual que en los formularios: sello primero, compresión después. «Antes» = lo que hacía el código anterior (1.600 px, JPEG 0,72).
//   · botón de archivo (remisión de químicos, foto de la ficha): comprimirArchivo sobre el JPEG original. «Antes» = el archivo original.
// Comprueba además: el sello está DENTRO de la foto comprimida, el lado largo (1.600 / 2.048), que nada se agranda y que un JPEG pequeño no se toca.
// Y la cámara real del acta (CamaraActa con 2.048 px, cámara falsa de Chrome), una cámara que NO da 2.560 × 1.440 (se usa lo que dé, sin agrandar ni fallar)
// y la regla de las fotos de detalle sobre las etiquetas REALES de los formatos de campo (campo.tipo_fotos).
// Calidad (David, 19-nov): 0,72 a 1.600 px y 0,8 a 2.048 px; los botones de archivo (documentos) a 2.048 px.
// Uso: node scripts/prueba_chrome_fotos_comprimidas.mjs <chrome> <puppeteer-core> <carpeta con fotos .jpg> [capturas]
import { createRequire } from "node:module";
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync, copyFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve, extname } from "node:path";
import { fileURLToPath } from "node:url";
import http from "node:http";

const aqui = dirname(fileURLToPath(import.meta.url)), raiz = join(aqui, "..");
const [CHROME, PUP, FOTOS] = process.argv.slice(2, 5);
if (!FOTOS) { console.error("Uso: node scripts/prueba_chrome_fotos_comprimidas.mjs <chrome> <puppeteer-core> <carpeta con fotos .jpg> [capturas]"); process.exit(2); }
const CAP = resolve(process.argv[5] || join(tmpdir(), "capturas_fotos")); mkdirSync(CAP, { recursive: true });
const ANCHOS = (process.env.ANCHOS || "390,1280").split(",").map(Number);
const puppeteer = createRequire(import.meta.url)(PUP);
const { build } = createRequire(join(raiz, "package.json"))("esbuild");
const PUERTO = 55992;

const dir = mkdtempSync(join(tmpdir(), "ui_fotos_"));
const fotos = readdirSync(FOTOS).filter((f) => /\.jpe?g$/i.test(f)).sort();
for (const f of fotos) copyFileSync(join(FOTOS, f), join(dir, f));
await build({
  stdin: { resolveDir: raiz, loader: "tsx", contents: `
    import React from "react"; import { createRoot } from "react-dom/client";
    import "./src/styles/app.css"; import "./src/tecnica/tokens.css"; import "./src/tecnica/tecnica.css"; import "./src/campo/campo.css";
    import { capturarFoto, esFotoDeDetalle, ladoPara } from "./src/campo/camara.ts";
    import { comprimirArchivo, LADO_FOTO_DETALLE_PX } from "./src/lib/comprimirFoto.ts";
    import { CamaraActa } from "./src/campo/acta/CamaraActa.tsx";
    const SELLO = ["19/11/2026, 10:42:13 a. m. · hora del celular", "10.47659, -73.28544 · ± 5 m"];
    // el «antes» de la cámara: el código anterior (1.600 px, JPEG 0,72), con el mismo sello
    async function anterior(video) {
      const w = video.videoWidth, h = video.videoHeight, k = Math.min(1, 1600 / Math.max(w, h)), c = document.createElement("canvas");
      c.width = Math.round(w * k); c.height = Math.round(h * k); const x = c.getContext("2d"); x.drawImage(video, 0, 0, c.width, c.height);
      const px = Math.max(14, Math.round(c.width * 0.026)); x.font = "600 " + px + "px sans-serif"; x.textBaseline = "top";
      const fr = SELLO.length * Math.round(px * 1.35) + Math.round(px * 0.7); x.fillStyle = "rgba(0,0,0,0.62)"; x.fillRect(0, c.height - fr, c.width, fr);
      x.fillStyle = "#fff"; SELLO.forEach((t, i) => x.fillText(t, Math.round(px * 0.5), c.height - fr + Math.round(px * 0.35) + i * Math.round(px * 1.35)));
      return new Promise((ok) => c.toBlob(ok, "image/jpeg", 0.72));
    }
    /** La foto como video de cámara: recortada a 16:9 en un lienzo de w × h, servida por captureStream. */
    async function comoCamara(url, w, h) {
      const img = await createImageBitmap(await (await fetch(url)).blob(), { imageOrientation: "from-image" });
      const c = document.createElement("canvas"); c.width = w; c.height = h; const x = c.getContext("2d");
      const k = Math.max(w / img.width, h / img.height); x.drawImage(img, (w - img.width * k) / 2, (h - img.height * k) / 2, img.width * k, img.height * k);
      const v = document.createElement("video"); v.muted = true; v.playsInline = true; v.srcObject = c.captureStream(5);
      const pintar = setInterval(() => x.drawImage(img, (w - img.width * k) / 2, (h - img.height * k) / 2, img.width * k, img.height * k), 100);
      await v.play(); await new Promise((r) => setTimeout(r, 400)); return { v, fin: () => { clearInterval(pintar); v.srcObject.getTracks().forEach((t) => t.stop()); img.close(); } };
    }
    /** ¿La franja del sello está en la foto? Lee la foto ya comprimida y mira que abajo esté oscuro y con texto claro. */
    async function selloDentro(blob) {
      const b = await createImageBitmap(blob); const c = document.createElement("canvas"); c.width = b.width; c.height = b.height; const x = c.getContext("2d"); x.drawImage(b, 0, 0);
      const px = Math.max(14, Math.round(b.width * 0.026)), alto = SELLO.length * Math.round(px * 1.35) + Math.round(px * 0.7);
      const d = x.getImageData(0, b.height - alto, Math.round(b.width * 0.6), alto).data; let oscuros = 0, claros = 0;
      for (let i = 0; i < d.length; i += 4) { const l = (d[i] + d[i + 1] + d[i + 2]) / 3; if (l < 90) oscuros++; else if (l > 200) claros++; }
      const n = d.length / 4; return { ancho: b.width, alto: b.height, oscuros: oscuros / n, claros: claros / n };
    }
    window.medir = async (nombre, ladoMayor) => {
      const url = "/" + nombre, original = await (await fetch(url)).blob(), dims = await createImageBitmap(original);
      const r = { nombre, original: original.size, original_lado: Math.max(dims.width, dims.height) }; dims.close();
      const [w, h] = ladoMayor > 1600 ? [2560, 1440] : [1920, 1080];
      const cam = await comoCamara(url, w, h);
      try {
        r.antes_camara = (await anterior(cam.v)).size;
        const t0 = performance.now(); const f = await capturarFoto(cam.v, SELLO, 1572864 * 2, ladoMayor); r.ms_camara = Math.round(performance.now() - t0);
        r.despues_camara = f.blob.size; r.calidad = f.calidad; r.lado = Math.max(f.ancho, f.alto); r.sello = await selloDentro(f.blob);
        if (window.__guardar) window.__guardar[nombre + "_" + ladoMayor] = f.blob;
      } finally { cam.fin(); }
      if (ladoMayor > 1600) { const a = await comprimirArchivo(original, 5 * 1048576, ladoMayor); r.despues_archivo = a.blob.size; r.lado_archivo = a.lado; r.calidad_archivo = a.calidad; }
      return r;
    };
    window.casos = async () => {
      const out = {};
      // un video chico (1.280 × 720) no se agranda
      const c = document.createElement("canvas"); c.width = 1280; c.height = 720; const x = c.getContext("2d"); x.fillStyle = "#6a8"; x.fillRect(0, 0, 1280, 720);
      const v = document.createElement("video"); v.muted = true; v.srcObject = c.captureStream(5); await v.play(); await new Promise((r) => setTimeout(r, 300));
      const f = await capturarFoto(v, SELLO, 1572864, LADO_FOTO_DETALLE_PX); out.chico = { ancho: f.ancho, alto: f.alto }; v.srcObject.getTracks().forEach((t) => t.stop());
      // un JPEG pequeño de archivo se sube tal cual (mismo objeto)
      const p = document.createElement("canvas"); p.width = 800; p.height = 600; p.getContext("2d").fillStyle = "#468"; p.getContext("2d").fillRect(0, 0, 800, 600);
      const peq = await new Promise((ok) => p.toBlob(ok, "image/jpeg", 0.8)); const pr = await comprimirArchivo(peq, 1572864);
      out.pequeno = { igual: pr.blob === peq, sin_cambios: pr.sin_cambios, bytes: peq.size };
      // un PNG pequeño SÍ se pasa a JPEG (se sube como image/jpeg)
      const png = await new Promise((ok) => p.toBlob(ok, "image/png")); const pp = await comprimirArchivo(png, 1572864); out.png = { tipo: pp.blob.type, sin_cambios: pp.sin_cambios };
      // las etiquetas REALES de foto de los formatos de campo (campo.tipo_fotos, paquete del Paso D): cuáles van a 2.048 px
      const REALES = [["medidor_nuevo", "Medidor nuevo, con serial y lectura"], ["medidor_retirado", "Medidor retirado, con serial y lectura"], ["medidor_instalado", "Medidor instalado, con serial y lectura"],
        ["medidor_lectura_inicial", "Medidor con lectura inicial"], ["medidor_lectura_serial", "Medidor con lectura y serial"], ["sello_instalado", "Sello instalado"], ["estado_sello_corte", "Estado del sello o del corte"],
        ["antes", "Antes del corte"], ["punto_corte", "Punto de corte"], ["tapon_retiro", "Tapón o retiro"], ["acometida_terminada", "Acometida terminada"], ["punto_conexion", "Punto de conexión a la red"],
        ["sitio_terminado", "Sitio terminado"], ["fachada_nomenclatura", "Fachada con nomenclatura"], ["predio_lote", "Predio o lote"], ["vecino_referencia", "Vecino o referencia"], ["recorrido", "Recorrido de la acometida"],
        ["servicio_restablecido", "Servicio restablecido"], ["evidencia", "Evidencia de lo revisado"], ["valvula_cerrada", "Válvula cerrada"]];
      out.a2048 = REALES.filter(([c, n]) => ladoPara(c, n) === 2048).map(([c]) => c);
      out.placa = esFotoDeDetalle("placa_equipo") && esFotoDeDetalle("x", "Placa del vehículo") && ladoPara("x", "Placa de la bomba") === 2048;
      return out;
    };
    // la cámara REAL del acta (CamaraActa, cámara falsa de Chrome) con 2.048 px
    const q = new URLSearchParams(location.search);
    // una cámara que NO tiene 2.560 × 1.440: entrega 1.280 × 720 aunque se le pida más (como un celular modesto). Se reemplaza getUserMedia antes de abrir el acta.
    if (q.get("chica")) navigator.mediaDevices.getUserMedia = async (c) => { window.__pedido = JSON.stringify(c.video); const k = document.createElement("canvas"); k.width = 1280; k.height = 720;
      const x = k.getContext("2d"); setInterval(() => { x.fillStyle = "#7a9"; x.fillRect(0, 0, 1280, 720); x.fillStyle = "#234"; x.fillRect(100 + (Date.now() / 10 % 300), 200, 200, 200); }, 50); return k.captureStream(10); };
    if (q.get("acta")) createRoot(document.getElementById("raiz")).render(<CamaraActa rotulo="Hallazgo" maxBytes={1572864} ladoMayor={Number(q.get("acta"))} sello={() => SELLO}
      onFoto={async (f) => { const b = await createImageBitmap(f.blob); window.__acta = { ancho: b.width, alto: b.height, bytes: f.blob.size }; }} onCerrar={() => {}} />);
    window.__listo = true;` },
  bundle: true, platform: "browser", format: "esm", outdir: dir, entryNames: "paquete", jsx: "automatic", logLevel: "error",
  loader: { ".css": "css", ".png": "dataurl", ".svg": "dataurl" }, define: { "import.meta.env.VITE_SUPABASE_URL": '"http://sim.local"', "import.meta.env.VITE_SUPABASE_ANON_KEY": '"x"', "process.env.NODE_ENV": '"production"' },
});
writeFileSync(join(dir, "index.html"), `<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="paquete.css"></head><body style="margin:0"><div id="raiz"></div><script type="module" src="paquete.js"></script></body></html>`);
const srv = http.createServer((req, res) => {
  const f = decodeURIComponent(new URL(req.url, "http://x").pathname.slice(1)) || "index.html";
  try { const b = readFileSync(join(dir, f)); res.writeHead(200, { "Content-Type": { ".js": "text/javascript", ".css": "text/css", ".html": "text/html", ".jpg": "image/jpeg", ".jpeg": "image/jpeg" }[extname(f).toLowerCase()] ?? "application/octet-stream" }); res.end(b); }
  catch { res.writeHead(404); res.end(); }
});
await new Promise((r) => srv.listen(PUERTO, "127.0.0.1", r));

const resultados = []; const ok = (n, c, d = "") => { resultados.push({ n, c: !!c, d: String(d).slice(0, 600) }); console.log((c ? "OK    " : "FALLA ") + n + (c ? "" : " → " + String(d).slice(0, 500))); };
const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-first-run", "--use-fake-ui-for-media-stream", "--use-fake-device-for-media-stream"] });
await nav.defaultBrowserContext().overridePermissions(`http://127.0.0.1:${PUERTO}`, ["camera"]);
const errores = [];
const kb = (b) => `${Math.round(b / 1024)} KB`;
const tabla = [];
for (const ancho of ANCHOS) {
  const A = (t) => `${ancho} · ${t}`;
  let p = await nav.newPage(); await p.setViewport(ancho < 600 ? { width: ancho, height: 844, isMobile: true, hasTouch: true, deviceScaleFactor: 2 } : { width: ancho, height: 900 });
  p.on("pageerror", (e) => errores.push(e.message));
  await p.goto(`http://127.0.0.1:${PUERTO}/`); await p.waitForFunction(() => window.__listo === true);
  const filas = [];
  for (const f of fotos) for (const lado of [1600, 2048]) filas.push(await p.evaluate((f, l) => window.medir(f, l), f, lado));
  if (ancho === ANCHOS[0]) tabla.push(...filas);
  const c16 = filas.filter((r) => r.lado <= 1600 && r.original_lado), c20 = filas.filter((r, i) => i % 2 === 1);
  ok(A(`C1 cámara a 1.600 px: lado largo 1.600, JPEG 0,72 (como estaba) y peso ≤ 500 KB en las ${fotos.length} fotos`), filas.filter((r, i) => i % 2 === 0).every((r) => r.lado === 1600 && r.calidad === 0.72 && r.despues_camara <= 500 * 1024),
    filas.filter((r, i) => i % 2 === 0).map((r) => `${r.nombre}:${r.lado}px ${kb(r.despues_camara)} q${r.calidad}`).join(" · "));
  ok(A("C2 cámara a 2.048 px (acta de Comercial, medidor y placas): lado largo 2.048, JPEG 0,8 (o menos, hasta 0,65, para llegar a 500 KB)"), c20.every((r) => r.lado === 2048 && [0.8, 0.72, 0.65].includes(r.calidad) && (r.despues_camara <= 500 * 1024 || r.calidad === 0.65)) && c20.some((r) => r.calidad === 0.8),
    c20.map((r) => `${r.nombre}:${r.lado}px ${kb(r.despues_camara)} q${r.calidad}`).join(" · "));
  ok(A("C3 el sello está DENTRO de la foto comprimida (franja oscura abajo con texto claro), en todas"), filas.every((r) => r.sello.oscuros > 0.45 && r.sello.claros > 0.01), filas.map((r) => `${r.nombre}:${r.sello.oscuros.toFixed(2)}/${r.sello.claros.toFixed(3)}`).join(" "));
  ok(A("C4 nunca baja de 0,65 (el piso); a 1.600 px nunca pasa de 0,72"), filas.every((r) => r.calidad >= 0.65) && filas.filter((r, i) => i % 2 === 0).every((r) => r.calidad <= 0.72), filas.map((r) => r.calidad).join(","));
  ok(A("C5 botón de archivo (documentos: remisión de químicos, foto de la ficha): las fotos de 3.000 a 4.100 px quedan en 2.048 px, por debajo del original y nunca por debajo de 0,65"), c20.every((r) => r.lado_archivo === 2048 && r.despues_archivo < r.original && r.calidad_archivo >= 0.65),
    c20.map((r) => `${r.nombre}:${kb(r.original)}→${kb(r.despues_archivo)} q${r.calidad_archivo}`).join(" · "));
  const cs = await p.evaluate(() => window.casos());
  ok(A("C6 un video chico (1.280 × 720) no se agranda aunque se pidan 2.048 px"), cs.chico.ancho === 1280 && cs.chico.alto === 720, JSON.stringify(cs.chico));
  ok(A("C7 un JPEG pequeño de archivo se sube tal cual (el mismo archivo, «sin cambios»); un PNG pequeño sí se pasa a JPEG"), cs.pequeno.igual && cs.pequeno.sin_cambios && cs.png.tipo === "image/jpeg" && !cs.png.sin_cambios, JSON.stringify(cs));
  ok(A("C8 de las 20 etiquetas reales de foto de los formatos de campo, van a 2.048 px las 7 del medidor y del sello; y «placa» también entra en la regla"),
    cs.a2048.join(",") === "medidor_nuevo,medidor_retirado,medidor_instalado,medidor_lectura_inicial,medidor_lectura_serial,sello_instalado,estado_sello_corte" && cs.placa, cs.a2048.join(","));
  await p.close();
  // la cámara REAL del acta con 2.048 px (cámara falsa de Chrome, que entrega el tamaño pedido)
  p = await nav.newPage(); await p.setViewport(ancho < 600 ? { width: ancho, height: 844, isMobile: true, hasTouch: true, deviceScaleFactor: 2 } : { width: ancho, height: 900 });
  p.on("pageerror", (e) => errores.push(e.message));
  await p.goto(`http://127.0.0.1:${PUERTO}/?acta=2048`); await p.waitForFunction(() => window.__listo === true);
  await p.waitForFunction(() => { const b = document.querySelector(".campo-capturar"); return b && !b.disabled; }, { timeout: 30000 });
  const video = await p.evaluate(() => { const v = document.querySelector("video"); return { w: v.videoWidth, h: v.videoHeight }; });
  await p.click(".campo-capturar"); await p.waitForFunction(() => !!window.__acta, { timeout: 30000 });
  const acta = await p.evaluate(() => window.__acta);
  ok(A("C9 la cámara del acta pide un video grande (2.560 × 1.440) y guarda la foto a 2.048 px de lado largo"), video.w === 2560 && video.h === 1440 && Math.max(acta.ancho, acta.alto) === 2048 && acta.bytes <= 1572864, JSON.stringify({ video, acta }));
  await p.screenshot({ path: join(CAP, `camara_acta_${ancho}.png`) });
  await p.close();
  // un celular que NO da 2.560 × 1.440: la cámara abre igual, usa lo que hay (1.280 × 720) y guarda a ese tamaño, sin agrandar
  p = await nav.newPage(); await p.setViewport(ancho < 600 ? { width: ancho, height: 844, isMobile: true, hasTouch: true, deviceScaleFactor: 2 } : { width: ancho, height: 900 });
  p.on("pageerror", (e) => errores.push(e.message));
  await p.goto(`http://127.0.0.1:${PUERTO}/?acta=2048&chica=1`); await p.waitForFunction(() => window.__listo === true);
  await p.waitForFunction(() => { const b = document.querySelector(".campo-capturar"); return b && !b.disabled; }, { timeout: 30000 });
  await p.click(".campo-capturar"); await p.waitForFunction(() => !!window.__acta, { timeout: 30000 });
  const chica = await p.evaluate(() => ({ acta: window.__acta, pedido: window.__pedido, error: document.querySelector(".campo-camara-error")?.innerText ?? null }));
  ok(A("C10 si el celular no da 2.560 × 1.440 (solo 1.280 × 720): pide 2.560 × 1.440 como IDEAL (no exige), la cámara abre sin error y la foto queda de 1.280 × 720, sin agrandar"),
    /"width":\{"ideal":2560\}/.test(chica.pedido) && !/"min"|"exact"/.test(chica.pedido) && chica.error === null && chica.acta.ancho === 1280 && chica.acta.alto === 720, JSON.stringify(chica));
  await p.close();
}
ok("Z1 sin errores de JavaScript", errores.length === 0, errores.join(" | "));
await nav.close(); srv.close();
console.log("\nPESOS (fotos reales; «cámara» = la foto como video de la cámara; «archivo» = el JPEG original elegido con el botón)");
console.log("foto | original | lado orig. | cámara antes (1.600 px, 0,72) | cámara 1.600 px (0,72) | cámara 2.048 px | calidad | archivo 2.048 px | calidad");
for (let i = 0; i < tabla.length; i += 2) { const a = tabla[i], b = tabla[i + 1];
  console.log(`${a.nombre} | ${kb(a.original)} | ${a.original_lado} | ${kb(a.antes_camara)} | ${kb(a.despues_camara)} | ${kb(b.despues_camara)} | ${b.calidad} | ${kb(b.despues_archivo)} | ${b.calidad_archivo}`); }
const bien = resultados.filter((r) => r.c).length;
console.log(`RESULTADO: ${bien} de ${resultados.length} — ${bien === resultados.length ? "SIN FALLAS" : resultados.length - bien + " FALLA(S)"}`);
process.exit(bien === resultados.length ? 0 : 1);
