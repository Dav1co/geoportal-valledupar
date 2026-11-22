// Personal de campo «solo operarios» (22-nov) en Chrome. La llama scripts/revision_admin.mjs con PRUEBA=personal (modo prueba), con el servidor de revisión ya arriba:
// la app completa por la pantalla de ingreso real → la Edge REAL geoportal-campo → las RPC del doble del Code A CON el cambio 5972d2d (256705b1…) en 55442 como service_role.
// Casos: el supervisor de campo cambia a un operario (sí) y no a otro supervisor, a un administrador ni a sí mismo (no: sin controles en pantalla y 403 si se pide igual);
// la ficha que cambia mientras está abierta (403 → aviso claro, diálogo cerrado, lista al día); el administrador cambia a un supervisor; el supervisor de actas solo lee.
// Lo guardado (y lo NO guardado) se comprueba en la base. A 390 y 1280 px, con capturas.
import { join } from "node:path";
import { mkdirSync } from "node:fs";

export async function probar({ puppeteer, CHROME, CAP, sqlq, P_WEB }) {
  mkdirSync(CAP, { recursive: true });
  const nav = await puppeteer.launch({ executablePath: CHROME, headless: "new", args: ["--no-sandbox", "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"] });
  let total = 0, fallas = 0;
  const ok = (n, c, d = "") => { total++; if (!c) fallas++; console.log(`${c ? "OK   " : "FALLA"} ${n}${c ? "" : " → " + String(d).replace(/\n/g, " ").slice(0, 500)}`); };
  const esp = (ms) => new Promise((r) => setTimeout(r, ms));
  const D = "@emdupar.gov.co";
  const SUP = "prueba.r3.sup.campo", OP = "prueba.op.comercial", OP2 = "prueba.perso.campo.sin.acta";
  const lit = (s) => `'${String(s).replace(/'/g, "''")}'`;
  const cargoDe = (e) => sqlq(`select coalesce(campo.f_cargo_vigente(${lit(e + D)}), '')`);
  const areaDe = (e) => sqlq(`select coalesce(campo.f_area_vigente(${lit(e + D)}), '')`);
  const formsDe = (e) => sqlq(`select coalesce(array_to_string(campo.f_formularios_asignados(${lit(e + D)}), ','), '')`);
  const eventos = (e) => Number(sqlq(`select count(*) from campo.personal_eventos where persona = ${lit(e + D)}`));
  const errores = [];

  async function entrar(correo, ancho) {
    const ctx = await nav.createBrowserContext(); const pg = await ctx.newPage();
    await pg.setViewport({ width: ancho, height: 900, deviceScaleFactor: ancho < 500 ? 2 : 1, isMobile: ancho < 500, hasTouch: ancho < 500 });
    pg.on("pageerror", (e) => errores.push(`${ancho} ${correo}: ${e.message}`));
    await pg.goto(`http://127.0.0.1:${P_WEB}/`); await pg.waitForSelector("input[type=password]", { timeout: 20000 });
    const [usr] = await pg.$$("input:not([type=password])"); await usr.type(correo); await pg.type("input[type=password]", "cualquiera"); await pg.keyboard.press("Enter");
    await esp(2500);
    return { pg, ctx };
  }
  const clicIncluye = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim().includes(x) && !e.disabled); if (b) { b.scrollIntoView({ block: "center" }); b.click(); return true; } return false; }, sel, t);
  const clicEn = (pg, sel, t) => pg.evaluate((s, x) => { const b = [...document.querySelectorAll(s)].find((e) => e.textContent.trim() === x && !e.disabled); if (b) { b.scrollIntoView({ block: "center" }); b.click(); return true; } return false; }, sel, t);
  async function abrirPersonal(pg, como) {
    if (como === "admin") {
      await pg.waitForFunction(() => [...document.querySelectorAll("button")].some((b) => b.textContent.startsWith("GEOPORTALCOMERCIAL")), { timeout: 20000 });
      await clicIncluye(pg, "button", "GEOPORTALCOMERCIAL");
      await pg.waitForFunction(() => [...document.querySelectorAll("button")].some((b) => b.textContent.trim() === "Formatos de campo"), { timeout: 20000 });
      await clicEn(pg, "button", "Formatos de campo");
    }
    const entrada = como === "actas" ? "Actas registradas" : "Supervisión y dashboard";
    await pg.waitForFunction((t) => [...document.querySelectorAll("button")].some((b) => b.textContent.includes(t)), { timeout: 20000 }, entrada);
    await clicIncluye(pg, "button", entrada);
    await pg.waitForFunction(() => [...document.querySelectorAll("button.rv-tab")].some((b) => b.textContent.trim() === "Personal"), { timeout: 20000 });
    await clicEn(pg, "button.rv-tab", "Personal");
    await pg.waitForSelector("[data-testid=personal] li[data-persona]", { timeout: 20000 }); await esp(600);
  }
  const ficha = (pg, e) => pg.evaluate((correo) => {
    const li = document.querySelector(`li[data-persona="${correo}"]`); if (!li) return null;
    return { editar: [...li.querySelectorAll("button")].some((b) => b.textContent.trim() === "Editar"), bloqueo: li.querySelector("[data-testid=per-bloqueo]")?.innerText ?? "", texto: li.innerText };
  }, e + D);
  const editar = async (pg, e) => {
    await pg.evaluate((correo) => { const li = document.querySelector(`li[data-persona="${correo}"]`); const b = [...li.querySelectorAll("button")].find((x) => x.textContent.trim() === "Editar"); b.scrollIntoView({ block: "center" }); b.click(); }, e + D);
    await pg.waitForSelector(".rv-modal[role=dialog]", { timeout: 10000 }); await esp(200);
  };
  const controles = (pg) => pg.evaluate(() => { const m = document.querySelector(".rv-modal"); return {
    area: !!m.querySelector("select[data-campo=area]"), cargo: !!m.querySelector("input[type=text]"), cuadrilla: !!m.querySelector("select[data-campo=cuadrilla]"),
    actividades: !!m.querySelector("[data-campo=actividades]"), formularios: [...m.querySelectorAll("fieldset legend")].some((l) => l.textContent.includes("Formularios")) }; });
  const ponerCargo = async (pg, t) => { const i = await pg.$(".rv-modal input[type=text]"); await i.click({ clickCount: 3 }); await pg.keyboard.press("Backspace"); await i.type(t); };
  const guardar = async (pg) => { await clicEn(pg, ".rv-modal button", "Guardar"); await pg.waitForFunction(() => !document.querySelector(".rv-modal[aria-label^='Editar']") || document.querySelector(".rv-modal .rv-error"), { timeout: 30000 }); await esp(900); };
  const sinDesborde = (pg) => pg.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1);
  const foto = (pg, n, ancho) => pg.screenshot({ path: join(CAP, `personal_${n}_${ancho}.png`), fullPage: ancho < 500 });
  const areas = sqlq("select string_agg(codigo, ',' order by orden, codigo) from campo.areas_comercial where activa").split(",");
  const formularioUno = sqlq("select clave from campo.f_formularios_personal() order by orden, clave limit 1");

  try {
    // ---------- 0. La regla en el servidor, pedida directamente a la Edge real (lo que pasaría si alguien salta la pantalla) ----------
    const pedir = async (quien, cuerpo) => { const r = await fetch(`http://127.0.0.1:55989/functions/v1/geoportal-campo?accion=personal_cambiar`, { method: "POST",
      headers: { Authorization: `Bearer tok-${quien}${D}`, apikey: "x", "Content-Type": "application/json" }, body: JSON.stringify(cuerpo) }); return { status: r.status, cuerpo: await r.json().catch(() => ({})) }; };
    const antes = Object.fromEntries(["prueba.sup.comercial", "prueba.admin", SUP, "prueba.caso.todo"].map((e) => [e, eventos(e)]));
    const casos = [
      ["área de otro supervisor (prueba.sup.comercial)", { persona: `prueba.sup.comercial${D}`, tipo: "fijar_area", area: areas[0] }],
      ["cargo de un administrador (prueba.admin)", { persona: `prueba.admin${D}`, tipo: "fijar_cargo", cargo: "Cargo de prueba" }],
      ["su propio cargo", { persona: `${SUP}${D}`, tipo: "fijar_cargo", cargo: "Cargo de prueba" }],
      ["formulario de otro supervisor (prueba.caso.todo)", { persona: `prueba.caso.todo${D}`, tipo: "asignar_formulario", formulario: formularioUno }],
      ["sacar de la cuadrilla a un supervisor (prueba.caso.todo)", { persona: `prueba.caso.todo${D}`, tipo: "fijar_cuadrilla", cuadrilla_id: null, motivo: "Prueba de la regla solo operarios" }],
    ];
    for (const [n, c] of casos) { const r = await pedir(SUP, c); ok(`Edge real: el supervisor de campo pide ${n} → 403`, r.status === 403, JSON.stringify(r)); }
    ok("Edge real: ninguno de esos pedidos dejó un evento en la base", Object.entries(antes).every(([e, n]) => eventos(e) === n), JSON.stringify(antes));
    ok("Edge real: hoy la Edge cambia el texto de la base por el fijo «No tiene permiso para esta acción.» (por eso la pantalla explica la regla)",
      (await pedir(SUP, casos[0][1])).cuerpo.error === "No tiene permiso para esta acción.", JSON.stringify((await pedir(SUP, casos[0][1])).cuerpo));
    ok("Edge real: la cuadrilla de prueba sigue con el supervisor adentro (nadie se oculta)", sqlq(`select coalesce(campo.f_cuadrilla_vigente('prueba.caso.todo${D}')::text, '')`) !== "");

    for (const ancho of [390, 1280]) {
      const i = ancho === 390 ? 0 : 1;
      // ---------- 1. Supervisor de campo ----------
      const { pg, ctx } = await entrar(SUP, ancho);
      await abrirPersonal(pg, "sup");
      const caja = await pg.$eval(".rv-per-cajitas", (x) => x.innerText).catch(() => "");
      ok(`[${ancho}] supervisor: «Usted puede…» dice «Solo a los operarios»`, caja.includes("Solo a los operarios:") && caja.includes("de un supervisor los cambia el administrador"), caja);
      const fOp = await ficha(pg, OP), fOp2 = await ficha(pg, OP2), fSup = await ficha(pg, "prueba.sup.comercial"), fTodo = await ficha(pg, "prueba.caso.todo"), fActas = await ficha(pg, "prueba.sup.actas"), fYo = await ficha(pg, SUP);
      ok(`[${ancho}] supervisor → operarios (${OP}, ${OP2}): con «Editar»`, fOp?.editar && fOp2?.editar && !fOp.bloqueo && !fOp2.bloqueo, JSON.stringify([fOp, fOp2]));
      for (const [n, f] of [["prueba.sup.comercial (supervisor de campo y de actas)", fSup], ["prueba.caso.todo (supervisor, en la cuadrilla)", fTodo], ["prueba.sup.actas (supervisor de actas)", fActas]])
        ok(`[${ancho}] supervisor → ${n}: visible, sin «Editar», «Es supervisor: … los cambia el administrador.»`, f && !f.editar && f.bloqueo === "Es supervisor: su área, su cargo y sus asignaciones los cambia el administrador.", JSON.stringify(f));
      ok(`[${ancho}] supervisor → sí mismo: sin «Editar», «Es su ficha: no la puede cambiar.»`, fYo && !fYo.editar && fYo.bloqueo === "Es su ficha: no la puede cambiar.", JSON.stringify(fYo));
      ok(`[${ancho}] los administradores no aparecen en Personal`, !(await ficha(pg, "prueba.admin")) && !(await ficha(pg, "prueba.admin2")));
      ok(`[${ancho}] supervisor → ${fTodo ? "la ficha de prueba.caso.todo muestra su cuadrilla" : "?"}`, (fTodo?.texto ?? "").includes("Cuadrilla de prueba Norte"), fTodo?.texto);
      ok(`[${ancho}] sin desborde horizontal`, await sinDesborde(pg));
      await foto(pg, "supervisor_lista", ancho);

      // ---------- 2. Supervisor sobre operario: sí (área, cargo y un formulario) ----------
      await editar(pg, OP);
      const c = await controles(pg);
      ok(`[${ancho}] supervisor → ${OP}: el diálogo trae área, cargo, cuadrilla, actividades y formularios`, c.area && c.cargo && c.cuadrilla && c.actividades && c.formularios, JSON.stringify(c));
      const area = areas[(i + 1) % areas.length], cargo = `Técnico de prueba ${ancho}`;
      await pg.select(".rv-modal select[data-campo=area]", area); await ponerCargo(pg, cargo);
      const nf = await pg.evaluate((cl) => { const m = document.querySelector(".rv-modal"); const l = [...m.querySelectorAll("fieldset")].find((f) => f.querySelector("legend")?.textContent.includes("Formularios"));
        const cb = [...l.querySelectorAll("label")].find((x) => !x.querySelector("input").checked); if (!cb) return null; cb.querySelector("input").click(); return cb.textContent.trim(); }, formularioUno);
      await foto(pg, "supervisor_edita_operario", ancho);
      const evAntes = eventos(OP);
      await guardar(pg);
      const avisoOk = await pg.$eval(".rv-aviso-ok", (x) => x.innerText).catch(() => "");
      ok(`[${ancho}] supervisor → ${OP}: «Cambios guardados…»`, avisoOk.includes("Cambios guardados"), avisoOk + (await pg.$eval(".rv-modal .rv-error", (x) => x.innerText).catch(() => "")));
      ok(`[${ancho}] en la base: área ${area}, cargo «${cargo}», un formulario más (${nf}) y 3 eventos`, areaDe(OP) === area && cargoDe(OP) === cargo && formsDe(OP) !== "" && eventos(OP) === evAntes + 3,
        JSON.stringify([areaDe(OP), cargoDe(OP), formsDe(OP), eventos(OP) - evAntes]));
      // historial: «Revertir» en un formulario del operario sí; en uno de un supervisor (el que el administrador le asigna en el paso 4 a 390 px) no
      const revertirDe = async (e) => {
        await pg.select(".rv-per-hist select", e + D); await esp(1200);
        return pg.evaluate(() => { const l = [...document.querySelectorAll(".rv-per-eventos li[data-evento=asignar_formulario]")];
          return { n: l.length, revertir: l.filter((x) => [...x.querySelectorAll("button")].some((b) => b.textContent.trim() === "Revertir")).length }; }); };
      const rOp = await revertirDe(OP), rSup = await revertirDe("prueba.sup.comercial");
      ok(`[${ancho}] historial de ${OP}: su formulario con «Revertir»`, rOp.n > 0 && rOp.revertir > 0, JSON.stringify(rOp));
      ok(`[${ancho}] historial de prueba.sup.comercial: ${i === 0 ? "aún sin formularios asignados" : "su formulario SIN «Revertir»"}`, i === 0 ? rSup.n === 0 : rSup.n > 0 && rSup.revertir === 0, JSON.stringify(rSup));
      await pg.select(".rv-per-hist select", "");

      // ---------- 3. La ficha cambia mientras está abierta: el operario pasa a supervisor (como si el administrador lo hiciera en Administración) ----------
      await editar(pg, OP2);
      sqlq(`update public.geoportal_lista_blanca set ver_dashboard_campo = true where email = ${lit(OP2 + D)}`);
      const ev2 = eventos(OP2), cargo2 = cargoDe(OP2), forms2 = formsDe(OP2);
      if (i === 0) await ponerCargo(pg, "Cargo que no debe quedar");
      else await pg.evaluate(() => { const m = document.querySelector(".rv-modal"); const l = [...m.querySelectorAll("fieldset")].find((f) => f.querySelector("legend")?.textContent.includes("Formularios")); l.querySelector("input[type=checkbox]").click(); });
      await guardar(pg);
      await pg.waitForSelector("[data-testid=per-rechazo]", { timeout: 10000 }).catch(() => {}); await esp(800);
      const rz = await pg.$eval("[data-testid=per-rechazo]", (x) => x.innerText).catch(() => "");
      const esperado = i === 0 ? "el área y el cargo de un supervisor o de un administrador los cambia el administrador." : "las asignaciones de un supervisor o de un administrador las hace el administrador.";
      ok(`[${ancho}] 403 por ${i === 0 ? "el cargo" : "un formulario"}: aviso claro («${esperado.slice(0, 40)}…») y «La lista se actualizó…»`, rz.includes(esperado) && rz.includes("La lista se actualizó"), rz);
      ok(`[${ancho}] el diálogo se cerró`, !(await pg.$(".rv-modal[role=dialog]")));
      const visible = await pg.$eval("[data-testid=per-rechazo]", (x) => { const r = x.getBoundingClientRect(); return r.top >= 0 && r.bottom <= window.innerHeight; }).catch(() => false);
      ok(`[${ancho}] el aviso queda a la vista (la pantalla sube hasta él)`, visible);
      const f2 = await ficha(pg, OP2);
      ok(`[${ancho}] la ficha ya sin «Editar» y con «Es supervisor…»`, f2 && !f2.editar && f2.bloqueo.startsWith("Es supervisor"), JSON.stringify(f2));
      ok(`[${ancho}] en la base no quedó nada (ni evento, ni cargo, ni formulario)`, eventos(OP2) === ev2 && cargoDe(OP2) === cargo2 && formsDe(OP2) === forms2);
      ok(`[${ancho}] sin desborde con el aviso`, await sinDesborde(pg));
      await foto(pg, "supervisor_rechazo_403", ancho);
      sqlq(`update public.geoportal_lista_blanca set ver_dashboard_campo = false where email = ${lit(OP2 + D)}`);       // vuelve a ser operario para el otro ancho
      await ctx.close();

      // ---------- 4. Administrador: cambia también a un supervisor ----------
      { const { pg, ctx } = await entrar("prueba.admin", ancho);
        await abrirPersonal(pg, "admin");
        const caja = await pg.$eval(".rv-per-cajitas", (x) => x.innerText).catch(() => "");
        ok(`[${ancho}] administrador: sin «Solo a los operarios»`, !caja.includes("Solo a los operarios") && caja.includes("Usted puede"), caja);
        const fs = await ficha(pg, "prueba.sup.comercial"), fo = await ficha(pg, OP);
        ok(`[${ancho}] administrador → supervisor y operario: los dos con «Editar»`, fs?.editar && fo?.editar && !fs.bloqueo, JSON.stringify([fs, fo]));
        await editar(pg, "prueba.sup.comercial");
        const c = await controles(pg);
        ok(`[${ancho}] administrador → supervisor: área, cargo, cuadrilla, actividades y formularios`, c.area && c.cargo && c.cuadrilla && c.actividades && c.formularios, JSON.stringify(c));
        const cargoS = `Supervisor de prueba ${ancho}`; await ponerCargo(pg, cargoS);
        if (i === 0) await pg.evaluate(() => { const m = document.querySelector(".rv-modal"); const l = [...m.querySelectorAll("fieldset")].find((f) => f.querySelector("legend")?.textContent.includes("Formularios")); l.querySelector("input[type=checkbox]").click(); });
        await guardar(pg);
        ok(`[${ancho}] administrador → supervisor: guardado; en la base el cargo «${cargoS}»`, cargoDe("prueba.sup.comercial") === cargoS, cargoDe("prueba.sup.comercial"));
        await foto(pg, "admin_lista", ancho);
        await ctx.close(); }

      // ---------- 5. Supervisor de actas (sin supervisión de campo): Personal solo lectura dentro de «Actas registradas» ----------
      { const { pg, ctx } = await entrar("prueba.sup.actas", ancho);
        await abrirPersonal(pg, "actas");
        const caja = await pg.$eval(".rv-per-cajitas", (x) => x.innerText).catch(() => "");
        const editarN = await pg.$$eval("[data-testid=personal] button", (l) => l.filter((b) => b.textContent.trim() === "Editar").length);
        ok(`[${ancho}] supervisor de actas: «Solo lectura», ningún «Editar», ningún texto por ficha`, caja.includes("Solo lectura") && editarN === 0 && !(await pg.$("[data-testid=per-bloqueo]")), caja);
        await foto(pg, "sup_actas_lectura", ancho);
        await ctx.close(); }
    }
    ok("sin errores de JavaScript en la página", errores.length === 0, errores.join(" | "));
  } catch (e) { ok("la prueba terminó sin excepción", false, e?.stack ?? e); }
  await nav.close();
  console.log(`\nRESULTADO: ${total - fallas} de ${total} — ${fallas ? fallas + " FALLA(S)" : "SIN FALLAS"}`);
  return fallas === 0;
}
