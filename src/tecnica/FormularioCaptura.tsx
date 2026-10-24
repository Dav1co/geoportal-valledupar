import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "../lib/supabase";
import { apiTec, ErrorTec, type FormularioDef, type VariableDef } from "./apiTecnica";
import { comunVigente, guardarBorrador, leerBorrador, nuevaClaveEnvio, type MarcaEnviada } from "./borrador";
import { decimalesAMostrar, formatearNumero, interpretarNumero } from "./numeros";

// Formulario de captura de Técnica. Se dibuja SOLO con la definición que entrega el servidor (variables, unidades, orden, obligatoriedad, alcance, plantas):
// agregar un parámetro al catálogo lo hace aparecer sin tocar este archivo. El operador no recibe ni ve rangos, marcas, autor ni la hora del servidor.

// Encabezados de los dos bloques. NO son nombres de variables: son textos de presentación por formulario (de la maqueta). Un formulario sin entrada aquí usa los genéricos.
type TextosBloques = { porPlanta: { titulo: string; ayuda: string }; ambas: { titulo: string; ayuda: string } };
const TEXTOS_GENERICOS: TextosBloques = {
  porPlanta: { titulo: "Por planta", ayuda: "Elija la planta para la que va a registrar." },
  ambas: { titulo: "Para las dos plantas", ayuda: "Una sola medición, sin importar la planta que eligió arriba." },
};
const TEXTOS_POR_FORMULARIO: Record<string, TextosBloques> = {
  entrada: {
    porPlanta: { titulo: "Caudal de ingreso por planta", ayuda: "Elija la planta para la que va a registrar el caudal." },
    ambas: { titulo: "Calidad del agua cruda", ayuda: "Una sola medición, sin importar la planta que eligió arriba." },
  },
};

const claveCampo = (v: VariableDef, planta: string | null) => (v.alcance === "por_planta" ? `${v.codigo}@${planta ?? ""}` : v.codigo);
const dmy = (iso: string) => (/^\d{4}-\d{2}-\d{2}$/.test(iso) ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : iso);

type Aviso = { tipo: "ok" | "error" | "info"; texto: string; detalle?: string; accion?: { rotulo: string; hacer: () => void } };
type Linea = { clave: string; etiqueta: string; unidad: string; texto: string };

export function FormularioCaptura({ def, uid, onGuardado }: { def: FormularioDef; uid: string; onGuardado: () => void }) {
  const clave = def.formulario.clave;
  const textosB = TEXTOS_POR_FORMULARIO[clave] ?? TEXTOS_GENERICOS;
  const variables = useMemo(() => [...def.variables].sort((a, b) => a.orden - b.orden), [def.variables]);
  const porPlanta = variables.filter((v) => v.alcance === "por_planta");
  const ambas = variables.filter((v) => v.alcance === "ambas_plantas");
  const nombrePlanta = useCallback((c: string | null) => def.plantas.find((p) => p.codigo === c)?.nombre ?? "", [def.plantas]);

  // Estado inicial: el borrador de este equipo (si es de esta persona y de hoy) o los valores propuestos por el servidor.
  const inicial = useMemo(() => leerBorrador(clave, uid, def.fecha_hoy), []); // eslint-disable-line react-hooks/exhaustive-deps
  const [planta, setPlanta] = useState<string | null>(inicial?.planta ?? def.plantas[0]?.codigo ?? null);
  const [hora, setHora] = useState<string>(inicial?.hora ?? def.hora_propuesta);
  const [textos, setTextos] = useState<Record<string, string>>(inicial?.textos ?? {});
  const [comunEnviada, setComunEnviada] = useState<MarcaEnviada | null>(inicial?.comunEnviada ?? null);
  const [errores, setErrores] = useState<Record<string, string>>({});
  const [fase, setFase] = useState<"editando" | "confirmando" | "enviando">("editando");
  const [aviso, setAviso] = useState<Aviso | null>(inicial ? { tipo: "info", texto: "Se recuperó lo que había escrito antes en este equipo. Revíselo antes de guardar." } : null);
  const [lineas, setLineas] = useState<Linea[]>([]);

  const intento = useRef<{ clave: string; huella: string }>({ clave: inicial?.claveEnvio ?? nuevaClaveEnvio(), huella: "" });
  const enviando = useRef(false);
  const reponerHora = useRef(false);
  const refTitulo = useRef<HTMLHeadingElement>(null);
  const refConfirmacion = useRef<HTMLHeadingElement>(null);

  // Si el servidor entrega una definición nueva (p. ej. tras guardar), la hora propuesta se actualiza solo cuando acabamos de guardar.
  useEffect(() => {
    if (reponerHora.current) { setHora(def.hora_propuesta); reponerHora.current = false; }
  }, [def.hora_propuesta, def.fecha_hoy]);

  // Borrador local (con una pequeña espera para no escribir en cada tecla). guardarBorrador decide qué conservar: sin texto y sin marca vigente, nada.
  useEffect(() => {
    const t = setTimeout(() => {
      guardarBorrador(clave, { uid, dia: def.fecha_hoy, planta, hora, textos, claveEnvio: intento.current.clave, comunEnviada });
    }, 400);
    return () => clearTimeout(t);
  }, [clave, uid, def.fecha_hoy, planta, hora, textos, comunEnviada]);

  // El plegado del bloque «Para las dos plantas» CADUCA a los 45 minutos: se revisa al volver a la pantalla (pestaña visible, foco) y cada 30 s.
  const vencerComun = useCallback((): boolean => {
    let vencio = false;
    setComunEnviada((m) => { if (m && !comunVigente(m)) { vencio = true; return null; } return m; });
    return vencio;
  }, []);
  useEffect(() => {
    const revisar = () => { if (document.visibilityState !== "hidden") vencerComun(); };
    const reloj = setInterval(revisar, 30_000);
    document.addEventListener("visibilitychange", revisar);
    window.addEventListener("focus", revisar);
    return () => { clearInterval(reloj); document.removeEventListener("visibilitychange", revisar); window.removeEventListener("focus", revisar); };
  }, [vencerComun]);

  useEffect(() => { if (fase === "confirmando") refConfirmacion.current?.focus(); }, [fase]);

  const cambiar = (k: string, valor: string) => {
    setTextos((t) => ({ ...t, [k]: valor }));
    if (errores[k]) setErrores((e) => { const n = { ...e }; delete n[k]; return n; });
    if (aviso && aviso.tipo !== "info") setAviso(null);
  };

  /** Revisa lo escrito. Devuelve los errores por campo y las líneas que se confirmarán. Ningún valor se rechaza por su magnitud. */
  function revisar() {
    const err: Record<string, string> = {};
    const out: Linea[] = [];
    if (!/^\d{2}:\d{2}$/.test(hora)) err["__hora"] = "Escriba la hora de la muestra.";
    for (const v of variables) {
      if (v.alcance === "ambas_plantas" && comunVigente(comunEnviada)) continue;     // bloque ya enviado (y vigente): no se vuelve a pedir
      const k = claveCampo(v, planta);
      const r = interpretarNumero(textos[k] ?? "");
      if (r.tipo === "vacio") { if (v.obligatoria) err[k] = "Escriba el valor."; continue; }
      if (r.tipo === "error") { err[k] = r.motivo; continue; }
      const dec = decimalesAMostrar(v.decimales, r.decimales);
      out.push({ clave: k, etiqueta: v.alcance === "por_planta" ? `${v.nombre} ${nombrePlanta(planta)}` : v.nombre, unidad: v.unidad, texto: formatearNumero(r.valor, dec) });
    }
    if (Object.keys(err).length === 0 && out.length === 0) err["__general"] = "Escriba al menos un valor.";
    return { err, out };
  }

  function guardar() {
    if (comunEnviada && !comunVigente(comunEnviada)) {
      setComunEnviada(null);
      setAviso({ tipo: "info", texto: "Pasaron más de 45 minutos desde que envió la calidad del agua cruda. El bloque «Para las dos plantas» volvió a aparecer: llénelo de nuevo o déjelo vacío si no hay una medición nueva." });
      return;
    }
    const { err, out } = revisar();
    setErrores(err);
    if (Object.keys(err).length > 0) {
      setAviso({ tipo: "error", texto: err["__general"] ?? "Revise los campos marcados antes de guardar." });
      const primero = Object.keys(err).find((k) => !k.startsWith("__")) ?? (err["__hora"] ? "__hora" : null);
      if (primero) setTimeout(() => document.getElementById(primero === "__hora" ? "tec-hora" : `tec-c-${primero}`)?.focus(), 0);
      return;
    }
    setAviso(null);
    setLineas(out);
    setFase("confirmando");
  }

  function cuerpoDelEnvio() {
    const valores: { variable: string; valor: number }[] = [];
    for (const v of variables) {
      if (v.alcance === "ambas_plantas" && comunVigente(comunEnviada)) continue;
      const r = interpretarNumero(textos[claveCampo(v, planta)] ?? "");
      if (r.tipo === "ok") valores.push({ variable: v.codigo, valor: r.valor });
    }
    const llevaPlanta = valores.some((x) => porPlanta.some((v) => v.codigo === x.variable));
    return { formulario: clave, planta: llevaPlanta ? planta : null, hora, valores };
  }

  async function enviar() {
    if (enviando.current) return;                 // doble toque
    enviando.current = true;
    setFase("enviando");
    setAviso(null);
    const base = cuerpoDelEnvio();
    // Un reintento (red caída, sin respuesta) lleva la MISMA clave; si la persona cambió algo, la clave es nueva para que el servidor no devuelva el envío anterior.
    const huella = JSON.stringify(base);
    if (intento.current.huella !== huella) intento.current = { clave: intento.current.huella === "" ? intento.current.clave : nuevaClaveEnvio(), huella };
    try {
      const r = await apiTec.registrar({ ...base, clave_envio: intento.current.clave });
      const incluyoComun = base.valores.some((x) => ambas.some((v) => v.codigo === x.variable));
      setTextos((t) => {
        const n = { ...t };
        for (const v of variables) {
          if (v.alcance === "por_planta") { if (base.planta) delete n[claveCampo(v, base.planta)]; }
          else if (incluyoComun) delete n[v.codigo];
        }
        return n;
      });
      if (incluyoComun) setComunEnviada({ hora: base.hora, ts: Date.now() });
      intento.current = { clave: nuevaClaveEnvio(), huella: "" };
      reponerHora.current = true;
      const otraFecha = r.fecha_muestra && r.fecha_muestra !== def.fecha_hoy ? ` Quedó con la fecha ${dmy(r.fecha_muestra)}, porque la muestra es de antes de la medianoche.` : "";
      setAviso({
        tipo: "ok",
        texto: r.duplicado ? "Este registro ya estaba guardado; no se duplicó." : "Registro guardado.",
        detalle: `${r.guardados} ${r.guardados === 1 ? "valor guardado" : "valores guardados"} · muestra de las ${base.hora}.${otraFecha}`,
      });
      setErrores({});
      onGuardado();
      setTimeout(() => refTitulo.current?.scrollIntoView?.({ block: "start" }), 0);
    } catch (e) {
      setAviso(avisoDeError(e, guardar));
    } finally {
      enviando.current = false;
      setFase("editando");
    }
  }

  const bloqueado = fase === "enviando";
  const campo = (v: VariableDef) => {
    const k = claveCampo(v, planta);
    const etiqueta = v.alcance === "por_planta" ? `${v.nombre} ${nombrePlanta(planta)}` : v.nombre;
    const err = errores[k];
    return (
      <div className="tec-campo" key={k}>
        <label htmlFor={`tec-c-${k}`}>{etiqueta}{v.obligatoria ? <span className="tec-oblig"> (obligatorio)</span> : null}</label>
        <div className="tec-entrada">
          <input
            id={`tec-c-${k}`} type="text" inputMode="decimal" autoComplete="off" autoCapitalize="off" spellCheck={false} maxLength={24} placeholder="0"
            value={textos[k] ?? ""} disabled={bloqueado} aria-invalid={err ? true : undefined} aria-describedby={err ? `tec-e-${k}` : undefined}
            onChange={(e) => cambiar(k, e.target.value)}
          />
          <span className="tec-unidad">{v.unidad}</span>
        </div>
        {err ? <span id={`tec-e-${k}`} className="tec-error">{err}</span> : null}
      </div>
    );
  };

  if (def.plantas.length === 0 && porPlanta.length > 0) {
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
          <h2 id="tec-confirma-tit" ref={refConfirmacion} tabIndex={-1}>Va a guardar</h2>
          <p className="tec-sub">Muestra de hoy, {dmy(def.fecha_hoy)}, a las {hora}.</p>
          <ul className="tec-lista-conf">
            {lineas.map((l) => (
              <li key={l.clave}><span>{l.etiqueta}</span><strong className="tec-num">{l.texto} {l.unidad}</strong></li>
            ))}
          </ul>
          <p className="tec-sub">Verifique cada valor y su unidad. Una vez guardado, solo su supervisor puede corregirlo.</p>
          <div className="tec-acciones">
            <button type="button" className="tec-boton" onClick={enviar}>Confirmar y guardar</button>
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

          {porPlanta.length > 0 && (
            <div className="tec-bloque">
              <div>
                <div className="tec-bloque-tit">{textosB.porPlanta.titulo}</div>
                <div className="tec-ayuda">{textosB.porPlanta.ayuda}</div>
              </div>
              <div className="tec-plantas" role="group" aria-label="Planta">
                {def.plantas.map((p) => (
                  <button key={p.codigo} type="button" className="tec-planta" aria-pressed={planta === p.codigo} disabled={bloqueado} onClick={() => setPlanta(p.codigo)}>{p.nombre}</button>
                ))}
              </div>
              {porPlanta.map(campo)}
            </div>
          )}

          {ambas.length > 0 && (comunVigente(comunEnviada) ? (
            <div className="tec-comun tec-comun-plegado">
              <div>
                <div className="tec-bloque-tit">{textosB.ambas.titulo}</div>
                <div className="tec-ayuda">Ya enviada a las {comunEnviada.hora}. No hace falta repetirla para la otra planta. (Reaparece completa a los 45 minutos.)</div>
              </div>
              <button type="button" className="tec-boton-sec" disabled={bloqueado} onClick={() => setComunEnviada(null)}>Registrar de nuevo</button>
            </div>
          ) : (
            <div className="tec-comun">
              <div>
                <div className="tec-bloque-fila"><div className="tec-bloque-tit">{textosB.ambas.titulo}</div><span className="tec-chip">Para las dos plantas</span></div>
                <div className="tec-ayuda">{textosB.ambas.ayuda}</div>
              </div>
              {ambas.map(campo)}
            </div>
          ))}

          {aviso ? (
            <div className={`tec-aviso tec-aviso-${aviso.tipo}`} role={aviso.tipo === "error" ? "alert" : "status"}>
              <strong>{aviso.texto}</strong>
              {aviso.detalle ? <div>{aviso.detalle}</div> : null}
              {aviso.accion ? <button type="button" className="tec-boton-sec" onClick={aviso.accion.hacer}>{aviso.accion.rotulo}</button> : null}
            </div>
          ) : null}

          <button type="button" className="tec-boton" onClick={guardar} disabled={bloqueado} aria-busy={bloqueado}>{bloqueado ? "Guardando…" : "Guardar registro"}</button>
          <p className="tec-ayuda">Los valores se guardan tal como los escribe. Si algo quedó mal registrado, avise a su supervisor.</p>
        </>
      )}
      {fase === "enviando" && <div className="tec-aviso tec-aviso-info" role="status">Guardando… no cierre esta pantalla.</div>}
    </section>
  );
}

/** Traduce el fallo del servidor a un aviso para la persona. Siempre aclara que lo escrito se conserva. */
export function avisoDeError(e: unknown, reintentar?: () => void): Aviso {
  if (!(e instanceof ErrorTec)) return { tipo: "error", texto: "Ocurrió un error inesperado. Lo que escribió se conserva; intente de nuevo." };
  const conserva = "Lo que escribió se conserva en este equipo.";
  switch (e.tipo) {
    case "red":
      return { tipo: "error", texto: `${e.message} Revise su conexión e intente de nuevo.`, detalle: `${conserva} Si el registro ya había llegado, no se duplicará.` };
    case "sesion":
      return { tipo: "error", texto: "Su sesión venció. Inicie sesión de nuevo para guardar.", detalle: `${conserva} Al volver a entrar con su cuenta lo recuperará.`, accion: { rotulo: "Volver a iniciar sesión", hacer: () => { void supabase.auth.signOut(); } } };
    case "horario":
      return { tipo: "error", texto: e.message, detalle: `Su cuenta no tiene habilitado el servicio en este momento. ${conserva} Avise a su supervisor o al administrador para que le habiliten el acceso en este horario y vuelva a intentar.`, accion: reintentar ? { rotulo: "Revisar y reintentar", hacer: reintentar } : undefined };
    case "denegado":
      return { tipo: "error", texto: "Su cuenta ya no está autorizada en el geoportal.", detalle: `${conserva} Hable con el administrador.` };
    case "permiso":
      return { tipo: "error", texto: e.message, detalle: `${conserva} Si debería tener este formulario, avise a su supervisor.` };
    case "servidor":
      return { tipo: "error", texto: "El servidor no pudo completar la operación.", detalle: `${conserva} Intente de nuevo en unos minutos.` };
    default:
      return { tipo: "error", texto: e.message };
  }
}
