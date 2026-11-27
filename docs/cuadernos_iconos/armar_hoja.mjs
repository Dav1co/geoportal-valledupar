// Arma hoja_iconos.svg a partir de iconos.json y, con --png, la rasteriza a hoja_iconos.png.
// Uso:  node armar_hoja.mjs            (solo el SVG)
//       node armar_hoja.mjs --png      (SVG + PNG con Chrome por puppeteer-core)
//       PUPPETEER_CORE=/ruta/a/puppeteer-core node armar_hoja.mjs --png
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const opciones = process.argv.slice(2);
for (const o of opciones) {
  if (o !== '--png') { console.error(`Opción desconocida: ${o}`); process.exit(2); }
}
const datos = JSON.parse(readFileSync(join(AQUI, 'iconos.json'), 'utf8'));

const ANCHO = 1800;
const MARGEN = 40;
const TINTA = '#1b2430', GRIS = '#5b6673', LINEA = '#d9dee4';
const FUENTE = 'Helvetica, Arial, sans-serif';
// Íconos que cambiaron respecto del borrador anterior: llevan la marca «corregido» en su tarjeta.
const CORREGIDOS = ['tanque', 'sumidero', 'torre', 'planta', 'falla_alcantarillado', 'sin_alcantarillado'];
const MARCA = '#D97706';
function corregido(codigo, xDer, ySup) {
  if (!CORREGIDOS.includes(codigo)) return '';
  return `<circle cx="${xDer - 62}" cy="${ySup - 3.5}" r="3.5" fill="${MARCA}"/>` +
    `<text x="${xDer}" y="${ySup}" font-family="${FUENTE}" font-size="10.5" font-weight="700" fill="${MARCA}" text-anchor="end">corregido</text>`;
}
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

// ---------- piezas ----------
const ENV_ACTIVO = 'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"';
const ENV_GLIFO = 'fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"';
const HALO = 3; // unidades que se suman al trazo para el halo blanco

// Ícono de activo con su halo, de lado `t` px, con la esquina en (x, y).
function activo(ic, color, x, y, t) {
  const halo = ic.svg
    .replace(/fill="currentColor"/g, 'fill="#fff"')
    .replace(/stroke-width="([\d.]+)"/g, (_, w) => `stroke-width="${Number(w) + HALO}"`);
  const fondo = ic.fondo ? `<g fill="#fff" stroke="#fff" stroke-width="${HALO}" stroke-linejoin="round">${ic.fondo}</g>` : '';
  return `<svg x="${x}" y="${y}" width="${t}" height="${t}" viewBox="0 0 24 24" overflow="visible">` +
    `<g fill="none" stroke="#fff" stroke-width="${2 + HALO}" stroke-linecap="round" stroke-linejoin="round">${halo}</g>` +
    fondo +
    `<g ${ENV_ACTIVO} color="${color}">${ic.svg}</g></svg>`;
}

// Pin de problema de ancho `w` px (alto w*36/28), con la esquina en (x, y).
function pin(ic, x, y, w) {
  const p = datos.problema.pin;
  return `<svg x="${x}" y="${y}" width="${w}" height="${w * 36 / 28}" viewBox="${p.viewBox}" overflow="visible">` +
    `<g color="${ic.color}">${p.svg}</g>` +
    `<g transform="${p.glifo_transform}" color="${datos.problema.glifo.color}" ${ENV_GLIFO}>${ic.glifo}</g></svg>`;
}

function texto(x, y, s, { tam = 14, color = TINTA, peso = 400, ancla = 'middle', mono = false } = {}) {
  const fam = mono ? 'Menlo, Consolas, monospace' : FUENTE;
  return `<text x="${x}" y="${y}" font-family="${fam}" font-size="${tam}" font-weight="${peso}" fill="${color}" text-anchor="${ancla}">${esc(s)}</text>`;
}

function partir(s, max) {
  const lineas = []; let act = '';
  for (const p of s.split(' ')) {
    if (act && (act + ' ' + p).length > max) { lineas.push(act); act = p; } else act = act ? act + ' ' + p : p;
  }
  if (act) lineas.push(act);
  return lineas;
}

// Fondo que simula la foto satelital.
function satelital(x, y, w, h, id) {
  return `<defs><filter id="${id}" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">` +
    `<feTurbulence type="fractalNoise" baseFrequency="0.012 0.02" numOctaves="4" seed="7" result="r"/>` +
    `<feColorMatrix in="r" type="matrix" values="0.22 0 0 0 0.10  0 0.24 0 0 0.15  0 0 0.18 0 0.09  0 0 0 0 1"/>` +
    `</filter><clipPath id="${id}c"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="10"/></clipPath></defs>` +
    `<g clip-path="url(#${id}c)"><rect x="${x}" y="${y}" width="${w}" height="${h}" fill="#44503f"/>` +
    `<rect x="${x}" y="${y}" width="${w}" height="${h}" filter="url(#${id})"/>` +
    // unas «vías» y «techos» para dar contraste real
    `<path d="M${x} ${y + h * 0.42}L${x + w} ${y + h * 0.30}" stroke="#6f736b" stroke-width="14" opacity="0.6"/>` +
    `<path d="M${x + w * 0.31} ${y}L${x + w * 0.36} ${y + h}M${x + w * 0.72} ${y}L${x + w * 0.69} ${y + h}" stroke="#666a62" stroke-width="10" opacity="0.55"/>` +
    Array.from({ length: 26 }, (_, i) => {
      const rx = x + ((i * 97 + 31) % 1000) / 1000 * (w - 60), ry = y + ((i * 211 + 57) % 1000) / 1000 * (h - 40);
      const col = ['#7d766b', '#6b5d50', '#8c897f', '#4d4a42', '#7a4a3a'][i % 5];
      return `<rect x="${rx.toFixed(1)}" y="${ry.toFixed(1)}" width="${34 + (i * 13) % 30}" height="${22 + (i * 7) % 22}" fill="${col}" opacity="0.6"/>`;
    }).join('') + `</g>`;
}

// ---------- hoja ----------
const partes = [];
let y = MARGEN;

partes.push(texto(MARGEN, y + 30, 'Cuadernos de análisis — hoja de íconos (para aprobar)', { tam: 34, peso: 700, ancla: 'start' }));
y += 58;
partes.push(texto(MARGEN, y, `Fuente: iconos.json · ${datos.version} · cada ícono se muestra grande y a tamaño real, sobre blanco y sobre un fondo que simula la foto satelital.${CORREGIDOS.length ? ' · Punto naranja = corregido en este borrador.' : ''}`, { tam: 15, color: GRIS, ancla: 'start' }));
y += 34;

// ===== A) Activo =====
const A = datos.activo;
partes.push(`<line x1="${MARGEN}" y1="${y}" x2="${ANCHO - MARGEN}" y2="${y}" stroke="${LINEA}" stroke-width="2"/>`);
y += 38;
partes.push(texto(MARGEN, y, 'A) Activo', { tam: 26, peso: 700, ancla: 'start' }));
partes.push(texto(MARGEN + 130, y, '12 pictogramas, una sola forma por tipo; el color indica el sistema', { tam: 15, color: GRIS, ancla: 'start' }));
// leyenda de colores
let lx = ANCHO - MARGEN - 430;
for (const c of A.colores) {
  partes.push(`<rect x="${lx}" y="${y - 15}" width="18" height="18" rx="4" fill="${c.color}"/>`);
  partes.push(texto(lx + 26, y, `${c.nombre} ${c.color}`, { tam: 15, ancla: 'start' }));
  lx += 215;
}
y += 26;

const COLS_A = 6, CW_A = (ANCHO - 2 * MARGEN) / COLS_A, CH_A = 232;
A.iconos.forEach((ic, i) => {
  const cx = MARGEN + (i % COLS_A) * CW_A, cy = y + Math.floor(i / COLS_A) * CH_A;
  const m = cx + CW_A / 2;
  partes.push(`<rect x="${cx + 8}" y="${cy + 6}" width="${CW_A - 16}" height="${CH_A - 12}" rx="10" fill="#fff" stroke="${LINEA}"/>`);
  partes.push(corregido(ic.codigo, cx + CW_A - 18, cy + 24));
  // grandes (72 px)
  partes.push(activo(ic, A.colores[0].color, m - 72 - 18, cy + 26, 72));
  partes.push(activo(ic, A.colores[1].color, m + 18, cy + 26, 72));
  // tamaño real (24 px)
  partes.push(activo(ic, A.colores[0].color, m - 24 - 42, cy + 118, 24));
  partes.push(activo(ic, A.colores[1].color, m + 42, cy + 118, 24));
  partes.push(texto(m, cy + 135, '24 px', { tam: 11, color: GRIS }));
  partes.push(texto(m, cy + 174, ic.nombre, { tam: 17, peso: 700 }));
  partes.push(texto(m, cy + 194, ic.codigo, { tam: 13, color: GRIS, mono: true }));
  partes.push(texto(m, cy + 212, ic.forma, { tam: 11.5, color: GRIS }));
});
y += 2 * CH_A + 14;

// fila sobre «foto satelital»
const HS_A = 190;
partes.push(texto(MARGEN, y + 4, 'Sobre la foto satelital (para ver el halo): arriba a 48 px, abajo a tamaño real (24 px)', { tam: 14, color: GRIS, ancla: 'start' }));
y += 16;
partes.push(satelital(MARGEN, y, ANCHO - 2 * MARGEN, HS_A, 'satA'));
const CW_S = (ANCHO - 2 * MARGEN) / 12;
A.iconos.forEach((ic, i) => {
  const m = MARGEN + i * CW_S + CW_S / 2;
  partes.push(activo(ic, A.colores[0].color, m - 48 - 8, y + 22, 48));
  partes.push(activo(ic, A.colores[1].color, m + 8, y + 22, 48));
  partes.push(activo(ic, A.colores[0].color, m - 24 - 12, y + 100, 24));
  partes.push(activo(ic, A.colores[1].color, m + 12, y + 100, 24));
  partes.push(`<text x="${m}" y="${y + 166}" font-family="${FUENTE}" font-size="13" font-weight="700" fill="#fff" text-anchor="middle" stroke="#000" stroke-opacity="0.55" stroke-width="3" paint-order="stroke">${esc(ic.nombre)}</text>`);
});
y += HS_A + 44;

// ===== B) Problema =====
const B = datos.problema;
partes.push(`<line x1="${MARGEN}" y1="${y}" x2="${ANCHO - MARGEN}" y2="${y}" stroke="${LINEA}" stroke-width="2"/>`);
y += 38;
partes.push(texto(MARGEN, y, 'B) Problema', { tam: 26, peso: 700, ancla: 'start' }));
partes.push(texto(MARGEN + 170, y, '9 pines en forma de gota, color propio, borde blanco y glifo blanco', { tam: 15, color: GRIS, ancla: 'start' }));
y += 26;

const CW_B = (ANCHO - 2 * MARGEN) / 9, CH_B = 284;
B.iconos.forEach((ic, i) => {
  const cx = MARGEN + i * CW_B, m = cx + CW_B / 2;
  partes.push(`<rect x="${cx + 6}" y="${y + 6}" width="${CW_B - 12}" height="${CH_B - 12}" rx="10" fill="#fff" stroke="${LINEA}"/>`);
  partes.push(corregido(ic.codigo, cx + CW_B - 14, y + 22));
  partes.push(pin(ic, m - 36 - 22, y + 24, 72));          // grande: 72 × 92,6
  partes.push(pin(ic, m + 36, y + 24 + 92.6 - 36, 28));     // tamaño real: 28 × 36
  partes.push(texto(m + 50, y + 132, '28×36', { tam: 11, color: GRIS }));
  const ls = partir(ic.nombre, 21);
  ls.forEach((l, k) => partes.push(texto(m, y + 158 + k * 18, l, { tam: 15, peso: 700 })));
  const yb = y + 158 + ls.length * 18;
  partes.push(texto(m, yb + 2, ic.codigo, { tam: 12, color: GRIS, mono: true }));
  partes.push(`<rect x="${m - 46}" y="${yb + 12}" width="13" height="13" rx="3" fill="${ic.color}"/>`);
  partes.push(texto(m - 28, yb + 23, ic.color, { tam: 12, color: GRIS, ancla: 'start', mono: true }));
  partes.push(texto(m, y + CH_B - 14, ic.forma, { tam: 11.5, color: GRIS }));
});
y += CH_B + 14;

const HS_B = 200;
partes.push(texto(MARGEN, y + 4, 'Sobre la foto satelital: pin a 56×72 y a tamaño real (28×36)', { tam: 14, color: GRIS, ancla: 'start' }));
y += 16;
partes.push(satelital(MARGEN, y, ANCHO - 2 * MARGEN, HS_B, 'satB'));
B.iconos.forEach((ic, i) => {
  const m = MARGEN + i * CW_B + CW_B / 2;
  partes.push(pin(ic, m - 56 - 6, y + 24, 56));
  partes.push(pin(ic, m + 22, y + 24 + 72 - 36, 28));
  const ls = partir(ic.nombre, 24);
  ls.forEach((l, k) => partes.push(`<text x="${m}" y="${y + 128 + k * 16}" font-family="${FUENTE}" font-size="12.5" font-weight="700" fill="#fff" text-anchor="middle" stroke="#000" stroke-opacity="0.55" stroke-width="3" paint-order="stroke">${esc(l)}</text>`));
});
y += HS_B + 30;

partes.push(texto(MARGEN, y, 'Los códigos son los del catálogo del servidor. Los glifos y pictogramas usan currentColor: el color se fija desde fuera.', { tam: 13, color: GRIS, ancla: 'start' }));
y += MARGEN - 10;

const ALTO = Math.ceil(y);
const svg = `<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="${ANCHO}" height="${ALTO}" viewBox="0 0 ${ANCHO} ${ALTO}">\n<rect width="${ANCHO}" height="${ALTO}" fill="#ffffff"/>\n${partes.join('\n')}\n</svg>\n`;
writeFileSync(join(AQUI, 'hoja_iconos.svg'), svg);
console.log(`hoja_iconos.svg: ${ANCHO}×${ALTO}`);

if (opciones.includes('--png')) {
  const ruta = process.env.PUPPETEER_CORE ||
    '/private/tmp/claude-502/-Users-ddiaz-geoportal-emdupar/18c6e11f-b53c-4394-b832-e18de396652c/scratchpad/pp/node_modules/puppeteer-core';
  const mod = await import(pathToFileURL(join(ruta, 'lib/esm/puppeteer/puppeteer-core.js')).href);
  const puppeteer = mod.default ?? mod;
  const nav = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true });
  const pag = await nav.newPage();
  await pag.setViewport({ width: ANCHO, height: ALTO, deviceScaleFactor: 1 });
  await pag.setContent(`<html><body style="margin:0;background:#fff">${svg.replace(/^<\?xml[^>]*>\n/, '')}</body></html>`);
  await pag.screenshot({ path: join(AQUI, 'hoja_iconos.png'), clip: { x: 0, y: 0, width: ANCHO, height: ALTO } });
  // Recortes de revisión (opcionales): REVISION=/carpeta → ampliaciones ×3 por franjas.
  if (process.env.REVISION) {
    await pag.setViewport({ width: ANCHO, height: ALTO, deviceScaleFactor: 3 });
    const paso = 600;
    for (let yy = 0, n = 0; yy < ALTO; yy += 300) {
      for (let xx = 0; xx < ANCHO; xx += paso, n++) {
        await pag.screenshot({ path: join(process.env.REVISION, `rev_${String(yy).padStart(4, '0')}_${xx}.png`), clip: { x: xx, y: yy, width: paso, height: Math.min(300, ALTO - yy) } });
      }
    }
  }
  await nav.close();
  console.log('hoja_iconos.png listo');
}
