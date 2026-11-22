// La prueba en Chrome de la Administración por geoportal (encargo v2, 22-nov). La llama scripts/revision_admin.mjs (modo prueba) con el servidor de revisión ya arriba:
// la app completa por la pantalla de ingreso real → la Edge REAL geoportal-admin → las RPC reales del doble del Code A (b1ca98db…) en 55442 como service_role.
// Cada caso se comprueba también en la base (lo que quedó guardado), no solo en pantalla. A 390 y 1280 px, con capturas. Usuarios: los prueba.* del doble.
import { join } from "node:path";
import { mkdirSync } from "node:fs";

export async function probar({ puppeteer, CHROME, CAP, ANTES, sqlq, P_WEB }) {
  mkdirSync(CAP, { recursive: true });
  const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
  let total = 0, fallas = 0;
  const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " → " + String(d).replace(/\n/g, " ").slice(0, 500)}`); };
  const esp = (ms) => new Promise((r) => setTimeout(r, ms));
  const D = "@emdupar.gov.co";
  const fila = (e) => sqlq(`select row_to_json(x) from (select rol, activo, nombre, horario, dias, ver_explorar, ver_focalizacion, ver_comercial, ver_rutas, ver_dashboard, ver_campo, ver_dashboard_campo, ver_acta, ver_dashboard_acta,
    ver_analisis_contrato, ver_registro_tecnico, ver_dashboard_tecnico, ver_dashboard_redes, ver_aseo, ver_dashboard_aseo from public.geoportal_lista_blanca where email = '${e}${D}') x`);
  const enBase = (e) => { const t = fila(e); return t ? JSON.parse(t) : null; };
  const errores = [];
  async function entrarAdmin(ancho) {
    const ctx = await nav.createBrowserContext(); const pg = await ctx.newPage();
    await pg.setViewport({ width: ancho, height: 900, deviceScaleFactor: ancho < 500 ? 2 : 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
    pg.on("pageerror", (e) => errores.push(`${ancho}: ${e.message}`));
    pg.on("dialog", (d) => d.accept());
    await pg.goto(`http://127.0.0.1:${P_WEB}/`); await pg.waitForSelector("input[type=password]", { timeout: 20000 });
    const [usr] = await pg.$$("input:not([type=password])"); await usr.type("prueba.admin"); await pg.type("input[type=password]", "cualquiera"); await pg.keyboard.press("Enter");
    await pg.waitForFunction(() => [...document.querySelectorAll("button")].some((b) => b.textContent.trim() === "Administración"), { timeout: 20000 });
    await pg.evaluate(() => [...document.querySelectorAll("button")].find((b) => b.textContent.trim() === "Administración").click());
    await pg.waitForSelector("tr[data-usuario], .adm-tabla tbody tr", { timeout: 20000 }); await esp(500);
    return { pg, ctx };
  }
  const txt = (pg, sel) => pg.$eval(sel, (e) => e.innerText).catch(() => "");
  const clic = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim() === x && !e.disabled); if (b) { b.scrollIntoView({ block: "center" }); b.click(); return true; } return false; }, sel, t);
  const accion = (pg, e, t) => pg.evaluate((correo, x) => { const r = [...document.querySelectorAll("tr")].find((f) => f.innerText.includes(correo)); const b = r && [...r.querySelectorAll("button")].find((y) => y.textContent.trim() === x); if (b) b.click(); return !!b; }, e + D, t);
  const linea = (pg, e) => pg.evaluate((correo) => [...document.querySelectorAll("tr")].find((f) => f.innerText.includes(correo))?.querySelector("[data-linea]")?.innerText ?? "", e + D);
  const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
  const foto = (pg, n, ancho) => pg.screenshot({ path: join(CAP, `${ANTES ? "antes" : "despues"}_${n}_${ancho}.png`), fullPage: ancho < 500 });
  const revisar = async (pg) => { await clic(pg, "button", "Revisar cambios"); await pg.waitForSelector("[data-testid=adm-resumen]", { timeout: 10000 }); await esp(200); };
  const confirmar = async (pg) => { await clic(pg, "[data-testid=adm-resumen] button", "Confirmar"); await pg.waitForFunction(() => !document.querySelector("[data-testid=adm-resumen]") || document.querySelector("p.error"), { timeout: 30000 }); await esp(600); };
  const aviso = (pg) => pg.evaluate(() => ({ error: document.querySelector("p.error")?.innerText ?? "", msg: document.querySelector("p.hint[role=status]")?.innerText ?? "" }));

  try {
    if (ANTES) {
      // Solo capturas de la pantalla de siempre (main): la lista y el editor de lsilva (caso mixto) y de un «Personalizado»
      for (const ancho of [390, 1280]) {
        const { pg, ctx } = await entrarAdmin(ancho);
        await foto(pg, "lista", ancho);
        await accion(pg, "prueba.caso.mixto", "Editar"); await esp(600); await foto(pg, "editar_caso_mixto", ancho);
        await accion(pg, "prueba.caso.mixto", "Cerrar"); await accion(pg, "prueba.perso.sup.sin.registro", "Editar"); await esp(600); await foto(pg, "editar_personalizado", ancho);
        await ctx.close();
      }
      console.log(`Capturas de «antes» en ${CAP}`); await nav.close(); return true;
    }

    for (const ancho of [390, 1280]) {
      const T = `[${ancho}]`, primera = ancho === 390;
      let { pg, ctx } = await entrarAdmin(ancho);

      // ---- A. La lista: una línea por persona ----
      ok(`${T} lista: lsilva (caso mixto) = «Comercial: Consulta (Explorar) · Técnica: Supervisor de plantas · Aseo: Supervisor de aseo»`,
        (await linea(pg, "prueba.caso.mixto")) === (primera ? "Comercial: Consulta (Explorar) · Técnica: Supervisor de plantas · Aseo: Supervisor de aseo" : "Comercial: Consulta (Explorar) · Técnica: Supervisor de plantas y distribución · Aseo: Supervisor de aseo"), await linea(pg, "prueba.caso.mixto"));
      ok(`${T} lista: anieto (todo) = Supervisor comercial con los 5 modos · plantas y distribución · Supervisor de aseo`, (await linea(pg, "prueba.caso.todo")).startsWith("Comercial: Supervisor comercial (Explorar, Focalización, Comercial, Rutas, Dashboard) · Técnica: Supervisor de plantas y distribución"), await linea(pg, "prueba.caso.todo"));
      ok(`${T} lista: administrador, solo Técnica, solo Aseo, sin acceso`, (await linea(pg, "prueba.admin")) === "Administrador" && (await linea(pg, "prueba.op.tecnico")) === "Técnica: Operario técnico"
        && (await linea(pg, "prueba.auditor.aseo")) === "Aseo: Auditor de aseo" && (await linea(pg, "prueba.sin.acceso")) === "Sin acceso");
      // los 4 «perso» del doble y prueba.r3.sup.campo (solo en la copia: supervisor de campo SIN dashboard_acta no calza con ningún perfil v2, cuyo Supervisor lleva el acta)
      const perso = await pg.$$eval("tr", (l) => l.filter((f) => f.querySelector(".adm-linea-perso")).map((f) => f.innerText.match(/prueba\.[a-z0-9.]+/)?.[0]).sort());
      ok(`${T} lista: los «Personalizado» se marcan: los 4 del doble y prueba.r3.sup.campo`, JSON.stringify(perso) === JSON.stringify(["prueba.perso.campo.sin.acta", "prueba.perso.consulta.analisis", "prueba.perso.solo.dashboard.aseo", "prueba.perso.sup.sin.registro", "prueba.r3.sup.campo"]), JSON.stringify(perso));
      ok(`${T} lista: no desborda`, await sinDesborde(pg));
      ok(`${T} lista: la línea de acceso y los botones se ven dentro de la pantalla (en el celular, cada fila es una tarjeta)`, await pg.evaluate((c) => {
        const f = [...document.querySelectorAll("tr")].find((x) => x.innerText.includes(c)); const l = f.querySelector("[data-linea]").getBoundingClientRect(), b = [...f.querySelectorAll("button")].map((x) => x.getBoundingClientRect());
        return l.width > 0 && l.right <= window.innerWidth && b.length === 4 && b.every((r) => r.width > 0 && r.right <= window.innerWidth); }, "prueba.caso.mixto@emdupar.gov.co"));
      await foto(pg, "lista", ancho);

      // ---- B. lsilva: cambiar SOLO Técnica; el resumen; guardar; volver a abrir y queda igual ----
      if (primera) {
        const antes = enBase("prueba.caso.mixto");
        await accion(pg, "prueba.caso.mixto", "Editar"); await pg.waitForSelector("[data-testid=adm-editor] select[data-perfil=tecnica]");
        ok(`${T} editar lsilva: preselecciona Sin formularios + Explorar, Supervisor de plantas y Supervisor de aseo`, await pg.evaluate(() => document.querySelector("select[data-perfil=formularios]").value === "sin" && document.querySelector("input[data-modo=explorar]").checked
          && document.querySelector("select[data-perfil=tecnica]").value === "sup_plantas" && document.querySelector("select[data-perfil=aseo]").value === "supervisor"));
        await foto(pg, "editar_caso_mixto", ancho);
        await pg.select("select[data-perfil=tecnica]", "sup_ambas"); await revisar(pg);
        const r = await txt(pg, "[data-testid=adm-resumen]");
        ok(`${T} resumen lsilva: «Técnica: Supervisor de plantas → Supervisor de plantas y distribución», solo enciende el Dashboard distribución (verde) y no apaga nada`,
          r.includes("Supervisor de plantas → Supervisor de plantas y distribución") && (await pg.$$eval("[data-cambio=enciende]", (l) => l.map((x) => x.dataset.casilla))).join() === "dashboard_redes" && (await pg.$$("[data-cambio=apaga]")).length === 0, r);
        await foto(pg, "resumen_caso_mixto", ancho);
        await confirmar(pg);
        const a1 = await aviso(pg), despues = enBase("prueba.caso.mixto");
        ok(`${T} guardar lsilva: «Cambios guardados» y en la base solo cambió ver_dashboard_redes (Explorar, el aseo y el análisis como estaban)`, a1.msg.includes("Cambios guardados") && !a1.error
          && Object.keys(antes).every((k) => k === "ver_dashboard_redes" ? despues[k] === true : despues[k] === antes[k]), JSON.stringify([a1, despues]));
        await accion(pg, "prueba.caso.mixto", "Editar"); await pg.waitForSelector("[data-testid=adm-editor] select[data-perfil=tecnica]");
        ok(`${T} volver a abrir lsilva: Técnica en «Supervisor de plantas y distribución»; sin cambios el resumen dice «No hay cambios»`, await pg.evaluate(() => document.querySelector("select[data-perfil=tecnica]").value === "sup_ambas"));
        await revisar(pg); ok(`${T} ida y vuelta: «No hay cambios: guardar no cambia nada»`, (await txt(pg, "[data-testid=adm-resumen]")).includes("No hay cambios"));
        await confirmar(pg); ok(`${T} guardar sin cambios no cambia la base`, JSON.stringify(enBase("prueba.caso.mixto")) === JSON.stringify(despues));
      }

      // ---- C. Error simulado de un permiso no aplicado (el caso del 22-nov): se quita analisis_contrato del cuerpo; el SQL conserva el viejo ----
      if (primera) {
        await pg.setRequestInterception(true);
        const quitar = (req) => { if (req.url().includes("geoportal-admin") && req.url().includes("accion=permisos") && req.method() === "POST") { const b = JSON.parse(req.postData()); delete b.analisis_contrato; req.continue({ postData: JSON.stringify(b) }); } else req.continue(); };
        pg.on("request", quitar);
        await accion(pg, "prueba.caso.todo", "Editar"); await pg.waitForSelector("select[data-perfil=formularios]");
        await pg.select("select[data-perfil=formularios]", "sin"); await revisar(pg); await confirmar(pg);
        const a = await aviso(pg);
        ok(`${T} permiso no aplicado: un solo aviso «El servidor no aplicó: Análisis de contrato … (apagar)» con la lista exacta`, /^El servidor no aplicó: Análisis de contrato \(datos personales\) \(apagar\) \(prueba\.caso\.todo@/.test(a.error), a.error);
        await foto(pg, "error_no_aplicado", ancho);
        pg.off("request", quitar); await pg.setRequestInterception(false);
        // dejarlo como estaba (todo)
        await accion(pg, "prueba.caso.todo", "Editar"); await pg.waitForSelector("select[data-perfil=formularios]"); await pg.select("select[data-perfil=formularios]", "supervisor"); await revisar(pg); await confirmar(pg);
        ok(`${T} anieto vuelve a Supervisor comercial (análisis en la base)`, enBase("prueba.caso.todo").ver_analisis_contrato === true && enBase("prueba.caso.todo").ver_dashboard_acta === true);
      }

      // ---- D. «Personalizado»: solo lectura, «Ajustes avanzados» y guardar sin tocar ----
      {
        const e = "prueba.perso.campo.sin.acta";
        await accion(pg, e, "Editar"); await pg.waitForSelector("[data-personalizado=comercial]");
        ok(`${T} Personalizado: Comercial muestra «Tiene hoy: Formatos de campo», el selector en «Personalizado (como está hoy)» y los ajustes plegados`,
          (await txt(pg, "[data-personalizado=comercial]")).includes("Tiene hoy: Formatos de campo") && await pg.evaluate(() => document.querySelector("select[data-perfil=formularios]").value === "perso" && !document.querySelector(".adm-avanzado").open));
        await pg.evaluate(() => { const d = document.querySelector("[data-personalizado=comercial] .adm-avanzado"); d.open = true; });
        await esp(150); await foto(pg, "personalizado_avanzado", ancho);
        if (primera) {
          await pg.click("[data-personalizado=comercial] input[data-casilla=analisis_contrato]"); await esp(100);
          await revisar(pg);
          ok(`${T} Ajustes avanzados: encender solo el análisis → verde y destacado (datos personales), sigue «Personalizado»`, (await pg.$$eval("[data-cambio=enciende]", (l) => l.map((x) => x.dataset.casilla))).join() === "analisis_contrato" && (await txt(pg, "[data-testid=adm-resumen]")).includes("nombre y el teléfono"));
          await foto(pg, "resumen_avanzado", ancho);
          await confirmar(pg);
          ok(`${T} Ajustes avanzados guardados: campo y análisis en la base, nada más del grupo`, (() => { const b = enBase(e); return b.ver_campo && b.ver_analisis_contrato && !b.ver_acta && !b.ver_dashboard_campo && b.ver_explorar; })(), fila(e));
        } else {
          await clic(pg, "button", "Cancelar");
        }
        const e2 = "prueba.perso.solo.dashboard.aseo", b0 = fila(e2);
        await accion(pg, e2, "Editar"); await pg.waitForSelector("[data-personalizado=aseo]");
        await revisar(pg); await confirmar(pg);
        ok(`${T} Personalizado guardado sin tocar: la base no cambia (sigue dashboard_aseo sin aseo)`, fila(e2) === b0 && (await aviso(pg)).msg.includes("Cambios guardados"), fila(e2));
      }

      // ---- E. Nuevo usuario con un correo que ya existe: se rechaza sin llamar al servidor ----
      {
        await clic(pg, "button", "Nuevo usuario"); await pg.waitForSelector("[data-testid=adm-alta]");
        const llamadas = []; const mira = (r) => { if (r.url().includes("geoportal-admin") && r.method() === "POST") llamadas.push(r.url()); }; pg.on("request", mira);
        await pg.type("[data-testid=adm-alta] input[data-campo=correo]", "prueba.op.comercial"); await pg.type("[data-testid=adm-alta] input[data-campo=clave]", "clave-larga-1");
        await clic(pg, "button", "Revisar y crear"); await esp(300);
        ok(`${T} Nuevo usuario con correo existente: «Ese usuario ya existe: use Editar o Nueva clave.» y ninguna llamada al servidor`, (await aviso(pg)).error === "Ese usuario ya existe: use Editar o Nueva clave." && llamadas.length === 0 && enBase("prueba.op.comercial").rol === "consulta", JSON.stringify(llamadas));
        await foto(pg, "nuevo_existente", ancho);
        pg.off("request", mira);
        // ---- F. Nuevo usuario de verdad: inactivo → permisos → verificar → activo ----
        const nuevo = `prueba.nuevo.${ancho}`;
        await pg.evaluate(() => { const i = document.querySelector("[data-testid=adm-alta] input[data-campo=correo]"); const s = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set; s.call(i, ""); i.dispatchEvent(new Event("input", { bubbles: true })); });
        await pg.type("[data-testid=adm-alta] input[data-campo=correo]", nuevo); await pg.type("[data-testid=adm-alta] input[data-campo=nombre]", "Prueba Nuevo");
        await pg.select("[data-testid=adm-alta] select[data-perfil=tecnica]", "operario"); await pg.select("[data-testid=adm-alta] select[data-perfil=aseo]", "auditor");
        await pg.select("[data-testid=adm-alta] select[data-campo=horario]", "sin_restriccion"); await pg.select("[data-testid=adm-alta] select[data-campo=dias]", "todos");
        await foto(pg, "nuevo_renglones", ancho);
        await clic(pg, "button", "Revisar y crear"); await pg.waitForSelector("[data-testid=adm-resumen]"); await foto(pg, "nuevo_resumen", ancho);
        const pasos = []; const mira2 = (r) => { if (r.url().includes("geoportal-admin") && r.method() === "POST") pasos.push(`${new URL(r.url()).searchParams.get("accion")}:${JSON.parse(r.postData()).activo ?? "-"}:${"perfil_tecnico" in JSON.parse(r.postData()) ? "PT" : ""}`); }; pg.on("request", mira2);
        await confirmar(pg); pg.off("request", mira2);
        const b = enBase(nuevo);
        ok(`${T} Nuevo usuario: guardar inactivo → permisos → guardar activo, sin perfil_tecnico`, JSON.stringify(pasos) === JSON.stringify(["guardar:false:", "permisos:-:", "guardar:true:"]), JSON.stringify(pasos));
        ok(`${T} Nuevo usuario en la base: activo, Operario técnico + Auditor de aseo, SIN Explorar (el alta por omisión lo daba), horario sin restricción`, !!b && b.activo && b.rol === "consulta" && b.ver_registro_tecnico && b.ver_aseo && !b.ver_explorar && !b.ver_dashboard_tecnico && !b.ver_analisis_contrato && b.horario === "sin_restriccion" && b.nombre === "Prueba Nuevo", JSON.stringify(b));
        ok(`${T} Nuevo usuario: el mensaje dice cómo quedó`, (await aviso(pg)).msg.includes("creado y activo: Técnica: Operario técnico · Aseo: Auditor de aseo"), (await aviso(pg)).msg);
      }

      // ---- G. «Hacer consulta» (R10): abre los renglones y el resumen antes de cambiar el rol ----
      if (primera) {
        await accion(pg, "prueba.admin2", "Hacer consulta"); await pg.waitForSelector("[data-testid=adm-editor][data-modo=hacer_consulta] select[data-perfil=formularios]");
        ok(`${T} Hacer consulta: no cambia nada todavía (sigue administrador en la base)`, enBase("prueba.admin2").rol === "admin");
        await pg.select("select[data-perfil=formularios]", "operario"); await revisar(pg);
        const r = await txt(pg, "[data-testid=adm-resumen]");
        ok(`${T} Hacer consulta: el resumen dice «Tipo de cuenta: Administrador → Usuario» y lo que se enciende`, r.includes("Tipo de cuenta: Administrador → Usuario (por geoportal)") && r.includes("Se enciende: Formatos de campo"), r);
        await foto(pg, "hacer_consulta_resumen", ancho);
        await confirmar(pg);
        const b = enBase("prueba.admin2");
        ok(`${T} Hacer consulta: rol consulta, Operario comercial (campo, acta, análisis) y nada más`, b.rol === "consulta" && b.ver_campo && b.ver_acta && b.ver_analisis_contrato && !b.ver_explorar && !b.ver_registro_tecnico, JSON.stringify(b));
        ok(`${T} la lista ya lo muestra como «Comercial: Operario comercial»`, (await linea(pg, "prueba.admin2")) === "Comercial: Operario comercial", await linea(pg, "prueba.admin2"));
      }

      // ---- H. Compuerta de aislamiento: el 409 de la Edge, tal cual, y no cambia nada ----
      if (!primera) {
        sqlq("update public.geoportal_config set aislamiento_tecnica_ok = false where id = 1");
        const b0 = fila("prueba.sin.acceso");
        await accion(pg, "prueba.sin.acceso", "Editar"); await pg.waitForSelector("select[data-perfil=aseo]");
        await pg.select("select[data-perfil=aseo]", "auditor"); await revisar(pg); await confirmar(pg);
        const a = await aviso(pg);
        ok(`${T} compuerta apagada: el 409 de la Edge se muestra tal cual y la base no cambia`, a.error === "Antes de dar permisos de aseo debe verificarse el bloqueo de las funciones comerciales." && fila("prueba.sin.acceso") === b0, a.error);
        await foto(pg, "compuerta_409", ancho);
        sqlq("update public.geoportal_config set aislamiento_tecnica_ok = true where id = 1");
        await clic(pg, "button", "Cancelar");
      }

      // ---- I. Editar un administrador: solo el nombre ----
      if (!primera) {
        await accion(pg, "prueba.admin", "Editar"); await pg.waitForSelector("[data-testid=adm-editor] input[data-campo=nombre]");
        ok(`${T} editar un administrador: sin renglones, con la nota de «Hacer consulta»`, !(await pg.$("[data-testid=adm-editor] [data-renglon]")) && (await txt(pg, "[data-testid=adm-editor]")).includes("Es administrador"));
        await pg.type("[data-testid=adm-editor] input[data-campo=nombre]", "Administración de Prueba"); await revisar(pg); await confirmar(pg);
        const b = enBase("prueba.admin");
        ok(`${T} el nombre se guarda con el rol y el estado actuales (sigue administrador y activo)`, b.rol === "admin" && b.activo && b.nombre.endsWith("Administración de Prueba") && (await aviso(pg)).msg.includes("Cambios guardados"), JSON.stringify(b));
      }
      ok(`${T} nada desborda a lo ancho`, await sinDesborde(pg));
      await ctx.close();
    }
    ok("sin errores de JavaScript en la página", errores.length === 0, errores.join(" | "));
  } catch (e) { total++; fallas++; console.log("FALLA  excepción:", e?.stack?.slice(0, 800)); }
  await nav.close();
  console.log(`\nRESULTADO: ${total - fallas} de ${total} — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}   (capturas en ${CAP})`);
  return fallas === 0;
}
