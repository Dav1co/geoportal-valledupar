import { useEffect, useMemo, useRef, useState } from "react";
import { apiTec, ErrorTec, type FormularioDef } from "./apiTecnica";
import { avisoDeError } from "./FormularioCaptura";
import { guardarBorrador, leerBorrador, nuevaClaveEnvio } from "./borrador";
import { agrupar, claveEnvioTarjeta, claveIntento, claveTexto, conDatos, cuerpoTarjeta, etiquetaCampo, lugarInicial, modoSelector, nombreLugar, textoElegirLugar, tieneLugar, type Tarjeta } from "./lugares";
import { decimalesAMostrar, formatearNumero, interpretarNumero } from "./numeros";

// Formulario de captura por «lugar» (Salida, y luego Muestreo). Se dibuja SOLO con la definición del servidor: agrupa las variables en tarjetas (ver lugares.ts) y envía UN registro
// por tarjeta con datos (decisión D-C3-1: un envío es de un solo lugar). El operador no recibe ni ve rangos, marcas, autor ni la hora del servidor.
// Reutiliza de Entrada: números (numeros.ts), borrador local (borrador.ts), clave de envío, errores del servidor (avisoDeError) y estilos.

const dmy = (iso: string) => (/^\d{4}-\d{2}-\d{2}$/.test(iso) ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : iso);

type Estado = { tipo: "ok" | "error" | "pendiente"; texto: string; detalle?: string };
type Aviso = { tipo: "ok" | "error" | "info"; texto: string; detalle?: string; accion?: { rotulo: string; hacer: () => void } };
type Linea = { clave: string; etiqueta: string; unidad: string; texto: string };
type Intento = { base: string; huella: string };
type Conf = { tarjeta: Tarjeta; lugar: string; lineas: Linea[] };

/** Los intentos (clave base por tarjeta y lugar) y el lugar elegido de cada tarjeta de puntos viajan en el campo claveEnvio del borrador, como JSON (clave reservada «__lugares»).
 *  Un valor ilegible se ignora: sin borrador legible, las tarjetas de puntos quedan SIN lugar elegido. */
function leerExtra(s: string | undefined): { intentos: Record<string, Intento>; lugares: Record<string, string> } {
  try {
    const o = JSON.parse(s ?? "");
    if (!o || typeof o !== "object" || Array.isArray(o)) return { intentos: {}, lugares: {} };
    const { __lugares, ...intentos } = o as Record<string, unknown>;
    const lug = __lugares && typeof __lugares === "object" && !Array.isArray(__lugares) ? (__lugares as Record<string, unknown>) : {};
    return { intentos: intentos as Record<string, Intento>, lugares: Object.fromEntries(Object.entries(lug).filter(([, v]) => typeof v === "string")) as Record<string, string> };
  } catch { return { intentos: {}, lugares: {} }; }
}
/** Mensajes que valen para TODAS las tarjetas: si uno falla así, las demás no se intentan. */
const esGlobal = (e: unknown) => e instanceof ErrorTec && ["sesion", "horario", "denegado", "permiso", "red"].includes(e.tipo);

export function FormularioPorLugar({ def, uid, onGuardado }: { def: FormularioDef; uid: string; onGuardado: () => void }) {
  const clave = def.formulario.clave;
  const tarjetas = useMemo(() => agrupar(def), [def]);

  const inicial = useMemo(() => leerBorrador(clave, uid, def.fecha_hoy), []); // eslint-disable-line react-hooks/exhaustive-deps
  const [textos, setTextos] = useState<Record<string, string>>(inicial?.textos ?? {});
  const [hora, setHora] = useState<string>(inicial?.hora ?? def.hora_propuesta);
  const extra = useMemo(() => leerExtra(inicial?.claveEnvio), []); // eslint-disable-line react-hooks/exhaustive-deps
  // Planta preseleccionada (la del borrador o la primera, como Entrada). Tanques y puntos: SIN lugar elegido, salvo el que traiga el borrador.
  const [lugares, setLugares] = useState<Record<string, string>>(() => Object.fromEntries(tarjetas.map((t) => [t.id, lugarInicial(t, inicial?.textos ?? {}, extra.lugares[t.id] ?? (t.clase === "planta" ? inicial?.planta : null))])));
  const [estados, setEstados] = useState<Record<string, Estado>>({});          // por claveIntento(tarjeta, lugar)
  const [errores, setErrores] = useState<Record<string, string>>({});
  const [fase, setFase] = useState<"editando" | "confirmando" | "enviando">("editando");
  const [conf, setConf] = useState<Conf[]>([]);
  const [aviso, setAviso] = useState<Aviso | null>(inicial ? { tipo: "info", texto: "Se recuperó lo que había escrito antes en este equipo. Revíselo antes de guardar." } : null);

  const intentos = useRef<Record<string, Intento>>(extra.intentos);
  const enviando = useRef(false);
  const reponerHora = useRef(false);
  const refTitulo = useRef<HTMLHeadingElement>(null);
  const refConfirmacion = useRef<HTMLHeadingElement>(null);

  useEffect(() => { if (reponerHora.current) { setHora(def.hora_propuesta); reponerHora.current = false; } }, [def.hora_propuesta, def.fecha_hoy]);
  useEffect(() => { if (fase === "confirmando") refConfirmacion.current?.focus(); }, [fase]);

  // Borrador local (misma mecánica que Entrada). Clave de los textos = «codigo@lugar»: cambiar de lugar no pierde lo escrito en el otro.
  useEffect(() => {
    const t = setTimeout(() => {
      const planta = tarjetas.find((x) => x.clase === "planta");
      guardarBorrador(clave, { uid, dia: def.fecha_hoy, planta: planta ? lugares[planta.id] ?? null : null, hora, textos, claveEnvio: JSON.stringify({ ...intentos.current, __lugares: Object.fromEntries(tarjetas.filter((x) => x.clase !== "ambas").map((x) => [x.id, lugares[x.id] ?? ""])) }), comunEnviada: null });
    }, 400);
    return () => clearTimeout(t);
  }, [clave, uid, def.fecha_hoy, tarjetas, lugares, hora, textos]);

  const lugarDe = (t: Tarjeta) => lugares[t.id] ?? "";

  const cambiar = (t: Tarjeta, k: string, valor: string) => {
    setTextos((x) => ({ ...x, [k]: valor }));
    setErrores((e) => { if (!e[k]) return e; const n = { ...e }; delete n[k]; return n; });
    setEstados((s) => { const ci = claveIntento(t, lugarDe(t)); if (!s[ci]) return s; const n = { ...s }; delete n[ci]; return n; });
    if (aviso && aviso.tipo !== "info") setAviso(null);
  };

  /** Revisa lo escrito en el lugar elegido de cada tarjeta. Ningún valor se rechaza por su magnitud. */
  function revisar() {
    const err: Record<string, string> = {}; const out: Conf[] = []; let otros = "";
    if (!/^\d{2}:\d{2}$/.test(hora)) err["__hora"] = "Escriba la hora de la muestra.";
    for (const t of tarjetas) {
      const lugar = lugarDe(t);
      // Datos escritos para OTRO lugar de la misma tarjeta: no se envían hasta elegirlo (se avisa).
      for (const o of t.opciones) if (o.codigo !== lugar && conDatos(t, o.codigo, textos)) otros += `${otros ? "; " : ""}${t.etiquetaLugar.toLowerCase()} ${o.nombre}`;
      if (!tieneLugar(t, lugar)) continue;       // tarjeta sin lugar elegido: se ignora (no cuenta como tarjeta con datos ni da error)
      const lineas: Linea[] = [];
      for (const v of t.variables) {
        const k = claveTexto(v, lugar);
        const r = interpretarNumero(textos[k] ?? "");
        if (r.tipo === "vacio") { if (v.obligatoria) err[k] = "Escriba el valor."; continue; }
        if (r.tipo === "error") { err[k] = r.motivo; continue; }
        lineas.push({ clave: k, etiqueta: etiquetaCampo(t, v, lugar), unidad: v.unidad, texto: formatearNumero(r.valor, decimalesAMostrar(v.decimales, r.decimales)) });
      }
      if (lineas.length) out.push({ tarjeta: t, lugar, lineas });
    }
    if (Object.keys(err).length === 0 && out.length === 0) err["__general"] = "Escriba al menos un valor.";
    return { err, out, otros };
  }

  function guardar() {
    const { err, out, otros } = revisar();
    setErrores(err);
    if (Object.keys(err).length > 0) {
      setAviso({ tipo: "error", texto: err["__general"] ?? "Revise los campos marcados antes de guardar." });
      const primero = Object.keys(err).find((k) => !k.startsWith("__")) ?? (err["__hora"] ? "__hora" : null);
      if (primero) setTimeout(() => document.getElementById(primero === "__hora" ? "tec-hora" : `tec-c-${primero}`)?.focus(), 0);
      return;
    }
    setAviso(otros ? { tipo: "info", texto: `También hay datos escritos para otro lugar (${otros}). No se envían hasta que lo elija.` } : null);
    setConf(out);
    setFase("confirmando");
  }

  /** Envía las tarjetas indicadas, UNA llamada por tarjeta (reintentable con su propia clave). No es atómico entre tarjetas. */
  async function enviarTarjetas(lista: { tarjeta: Tarjeta; lugar: string }[]) {
    lista = lista.filter((x) => tieneLugar(x.tarjeta, x.lugar));       // nunca sale un valor de una tarjeta sin lugar elegido (ni con un borrador recuperado)
    if (lista.length === 0 || enviando.current) return;           // nada que enviar, o doble toque
    enviando.current = true;
    setFase("enviando");
    setAviso(null);
    const hechos: string[] = []; let fallas = 0; let corte = false;
    for (const { tarjeta: t, lugar } of lista) {
      const ci = claveIntento(t, lugar);
      if (corte) { setEstados((s) => ({ ...s, [ci]: { tipo: "pendiente", texto: "No se envió.", detalle: "Se detuvo el envío por el problema anterior. Lo escrito se conserva; reintente." } })); fallas++; continue; }
      const base = cuerpoTarjeta(def, t, lugar, textos, hora);
      const huella = JSON.stringify(base);
      const previo = intentos.current[ci];
      // Mismo contenido = misma clave (reintento seguro); si la persona cambió algo, clave nueva para que el servidor no devuelva el envío anterior.
      if (!previo || previo.huella !== huella) intentos.current[ci] = { base: nuevaClaveEnvio(), huella };
      try {
        const r = await apiTec.registrar({ ...base, clave_envio: claveEnvioTarjeta(intentos.current[ci].base, t, lugar) });
        setTextos((x) => { const n = { ...x }; for (const v of t.variables) delete n[claveTexto(v, lugar)]; return n; });
        delete intentos.current[ci];
        hechos.push(`${t.clase === "ambas" ? t.titulo : nombreLugar(t, lugar)}: ${r.guardados} ${r.guardados === 1 ? "valor" : "valores"}${r.duplicado ? " (ya estaba guardado)" : ""}`);
        setEstados((s) => ({ ...s, [ci]: { tipo: "ok", texto: r.duplicado ? "Ya estaba guardado; no se duplicó." : "Guardado.", detalle: `${r.guardados} ${r.guardados === 1 ? "valor guardado" : "valores guardados"} · muestra de las ${base.hora}.` } }));
      } catch (e) {
        fallas++;
        const a = avisoDeError(e);
        setEstados((s) => ({ ...s, [ci]: { tipo: "error", texto: `No se pudo guardar: ${a.texto}`, detalle: a.detalle } }));
        if (esGlobal(e)) corte = true;
      }
    }
    enviando.current = false;
    setFase("editando");
    if (hechos.length) {
      onGuardado();
      if (fallas === 0) reponerHora.current = true;
    }
    if (fallas === 0) {
      setAviso({ tipo: "ok", texto: hechos.length === 1 ? "Registro guardado." : `${hechos.length} registros guardados.`, detalle: hechos.join(" · ") });
      setErrores({});
      setTimeout(() => refTitulo.current?.scrollIntoView?.({ block: "start" }), 0);
    } else {
      setAviso({ tipo: "error", texto: hechos.length ? `Se guardaron ${hechos.length} de ${lista.length} registros.` : "No se guardó ningún registro.", detalle: "Revise las tarjetas marcadas: lo que no se guardó se conserva y se puede reintentar." });
    }
  }

  const reintentar = (t: Tarjeta) => { if (tieneLugar(t, lugarDe(t))) void enviarTarjetas([{ tarjeta: t, lugar: lugarDe(t) }]); };

  const bloqueado = fase === "enviando";

  // ---- piezas de la pantalla ----
  const campo = (t: Tarjeta, v: Tarjeta["variables"][number]) => {
    const lugar = lugarDe(t); const k = claveTexto(v, lugar); const err = errores[k];
    return (
      <div className="tec-campo" key={k}>
        <label htmlFor={`tec-c-${k}`}>{etiquetaCampo(t, v, lugar)}{v.obligatoria ? <span className="tec-oblig"> (obligatorio)</span> : null}</label>
        <div className="tec-entrada">
          <input id={`tec-c-${k}`} type="text" inputMode="decimal" autoComplete="off" autoCapitalize="off" spellCheck={false} maxLength={24} placeholder="0"
            value={textos[k] ?? ""} disabled={bloqueado} aria-invalid={err ? true : undefined} aria-describedby={err ? `tec-e-${k}` : undefined} onChange={(e) => cambiar(t, k, e.target.value)} />
          <span className="tec-unidad">{v.unidad}</span>
        </div>
        {err ? <span id={`tec-e-${k}`} className="tec-error">{err}</span> : null}
      </div>
    );
  };

  const selector = (t: Tarjeta) => {
    if (t.clase === "ambas") return null;
    const lugar = lugarDe(t);
    if (t.opciones.length === 0) return <p className="tec-error-caja" role="alert">No hay {t.clase === "planta" ? "plantas" : "puntos"} disponibles para esta tarjeta. Avise a su supervisor.</p>;
    const etiqueta = t.etiquetaLugar;
    if (modoSelector(t.opciones.length) === "botones") {
      return (
        <div className="tec-lugares" role="group" aria-label={etiqueta}>
          {t.opciones.map((o) => (
            <button key={o.codigo} type="button" className="tec-planta tec-lugar" aria-pressed={lugar === o.codigo} disabled={bloqueado} onClick={() => setLugares((x) => ({ ...x, [t.id]: x[t.id] === o.codigo ? "" : o.codigo }))}>
              <span>{lugar === o.codigo ? <span aria-hidden="true">✔ </span> : null}{o.nombre}</span>{o.codigo !== lugar && conDatos(t, o.codigo, textos) ? <span className="tec-con-datos">con datos</span> : null}
            </button>
          ))}
          {lugar !== "" ? <span className="tec-ayuda tec-pista">Toque de nuevo para quitar</span> : null}
        </div>
      );
    }
    return (
      <div className="tec-campo">
        <label htmlFor={`tec-sel-${t.id}`}>{etiqueta}</label>
        <select id={`tec-sel-${t.id}`} value={lugar} disabled={bloqueado} onChange={(e) => setLugares((x) => ({ ...x, [t.id]: e.target.value }))}>
          <option value="">{`Elija ${t.elija}…`}</option>
          {t.opciones.map((o) => <option key={o.codigo} value={o.codigo}>{o.nombre}{o.codigo !== lugar && conDatos(t, o.codigo, textos) ? " — con datos" : ""}</option>)}
        </select>
      </div>
    );
  };

  const tarjeta = (t: Tarjeta) => {
    const lugar = lugarDe(t); const st = estados[claveIntento(t, lugar)];
    return (
      <section className="tec-grupo" key={t.id} aria-labelledby={`tec-g-${t.id}`}>
        <div>
          <h2 id={`tec-g-${t.id}`} className="tec-bloque-tit">{t.numero} · {t.titulo}</h2>
          <div className="tec-ayuda">{t.ayuda}</div>
        </div>
        {selector(t)}
        {t.clase !== "ambas" && t.opciones.length > 0 && !tieneLugar(t, lugar) ? <p className="tec-elegir" data-testid="elegir-lugar">{textoElegirLugar(t)}</p> : null}
        {tieneLugar(t, lugar) ? t.variables.map((v) => campo(t, v)) : null}
        {st ? (
          <div className={`tec-estado tec-estado-${st.tipo}`} role={st.tipo === "error" ? "alert" : "status"}>
            <strong>{st.tipo === "ok" ? "✔ " : st.tipo === "error" ? "✖ " : "… "}{st.texto}</strong>
            {st.detalle ? <div>{st.detalle}</div> : null}
            {st.tipo !== "ok" ? <button type="button" className="tec-boton-sec" disabled={bloqueado} onClick={() => reintentar(t)}>Reintentar</button> : null}
          </div>
        ) : null}
      </section>
    );
  };

  if (def.plantas.length === 0 && tarjetas.some((t) => t.clase === "planta")) {
    return <section className="tec-tarjeta"><p className="tec-error-caja" role="alert">Este formulario necesita plantas y todavía no hay ninguna activa. Avise a su supervisor.</p></section>;
  }

  return (
    <section className="tec-tarjeta" aria-labelledby="tec-titulo-form">
      <div>
        <h1 id="tec-titulo-form" ref={refTitulo} tabIndex={-1}>{def.formulario.nombre}</h1>
        <p className="tec-sub">{def.formulario.descripcion}</p>
      </div>

      {fase === "confirmando" ? (
        <div className="tec-confirma" role="group" aria-labelledby="tec-confirma-tit">
          <h2 id="tec-confirma-tit" ref={refConfirmacion} tabIndex={-1}>Va a guardar {conf.length === 1 ? "1 registro" : `${conf.length} registros`}</h2>
          <p className="tec-sub">Muestra de hoy, {dmy(def.fecha_hoy)}, a las {hora}. Se guarda un registro por cada lugar.</p>
          {conf.map((c) => (
            <div key={claveIntento(c.tarjeta, c.lugar)}>
              <div className="tec-conf-lugar">{c.tarjeta.titulo}{c.tarjeta.clase === "ambas" ? "" : ` · ${nombreLugar(c.tarjeta, c.lugar)}`}</div>
              <ul className="tec-lista-conf">
                {c.lineas.map((l) => <li key={l.clave}><span>{l.etiqueta}</span><strong className="tec-num">{l.texto} {l.unidad}</strong></li>)}
              </ul>
            </div>
          ))}
          {aviso && aviso.tipo === "info" ? <div className="tec-aviso tec-aviso-info" role="status"><strong>{aviso.texto}</strong></div> : null}
          <p className="tec-sub">Verifique cada valor y su unidad. Una vez guardado, solo su supervisor puede corregirlo.</p>
          <div className="tec-acciones">
            <button type="button" className="tec-boton" onClick={() => void enviarTarjetas(conf.map((c) => ({ tarjeta: c.tarjeta, lugar: c.lugar })))}>Confirmar y guardar</button>
            <button type="button" className="tec-boton-sec" onClick={() => setFase("editando")}>Corregir</button>
          </div>
        </div>
      ) : (
        <>
          <div className="tec-campo">
            <label htmlFor="tec-fecha">Fecha de la muestra</label>
            <input id="tec-fecha" type="text" readOnly value={`Hoy · ${dmy(def.fecha_hoy)}`} className="tec-solo-lectura" />
            <span className="tec-ayuda">Solo se puede registrar el día de hoy.</span>
          </div>
          <div className="tec-campo">
            <label htmlFor="tec-hora">Hora de la muestra</label>
            <input id="tec-hora" type="time" value={hora} disabled={bloqueado} aria-invalid={errores["__hora"] ? true : undefined}
              onChange={(e) => { setHora(e.target.value); if (errores["__hora"]) setErrores((x) => { const n = { ...x }; delete n["__hora"]; return n; }); }} />
            <span className="tec-ayuda">Se propone la hora actual menos 15 minutos. Puede ajustarla.</span>
            {errores["__hora"] ? <span className="tec-error">{errores["__hora"]}</span> : null}
          </div>

          {tarjetas.map(tarjeta)}

          {aviso ? (
            <div className={`tec-aviso tec-aviso-${aviso.tipo}`} role={aviso.tipo === "error" ? "alert" : "status"}>
              <strong>{aviso.texto}</strong>
              {aviso.detalle ? <div>{aviso.detalle}</div> : null}
              {aviso.accion ? <button type="button" className="tec-boton-sec" onClick={aviso.accion.hacer}>{aviso.accion.rotulo}</button> : null}
            </div>
          ) : null}

          <button type="button" className="tec-boton" onClick={guardar} disabled={bloqueado} aria-busy={bloqueado}>{bloqueado ? "Guardando…" : "Guardar registro"}</button>
          <p className="tec-ayuda">Todos los campos son opcionales: se guarda un registro por cada tarjeta con datos. Los valores se guardan tal como los escribe. Si algo quedó mal registrado, avise a su supervisor.</p>
        </>
      )}
      {fase === "enviando" && <div className="tec-aviso tec-aviso-info" role="status">Guardando… no cierre esta pantalla.</div>}
    </section>
  );
}
