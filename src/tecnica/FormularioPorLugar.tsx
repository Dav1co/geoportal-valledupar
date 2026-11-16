import { useEffect, useMemo, useRef, useState } from "react";
import { apiTec, ErrorTec, type FormularioDef } from "./apiTecnica";
import { avisoDeError } from "./FormularioCaptura";
import { borrarBorrador, guardarBorrador, inicioAlAbrir, inicioAlEnviar, leerBorrador, nuevaClaveEnvio, nuevoInicio } from "./borrador";
import { ConfirmarCancelar } from "../components/ConfirmarCancelar";
import { agrupar, claveEnvioTarjeta, claveIntento, claveTexto, conDatos, cuerpoTarjeta, etiquetaCampo, lugarInicial, modoSelector, nombreLugar, textoElegirLugar, tieneLugar, type Tarjeta } from "./lugares";
import { decimalesAMostrar, formatearNumero, interpretarNumero } from "./numeros";
import { MapaMuestreo } from "./MapaMuestreo";

// Formulario de captura por «lugar» (Salida y Muestreo). Se dibuja SOLO con la definición del servidor: agrupa las variables en tarjetas (ver lugares.ts) y envía UN registro
// por tarjeta con datos (decisión D-C3-1: un envío es de un solo lugar). El operador no recibe ni ve rangos, marcas, autor ni la hora del servidor.
// Reutiliza de Entrada: números (numeros.ts), borrador local (borrador.ts), clave de envío, errores del servidor (avisoDeError) y estilos.

const dmy = (iso: string) => (/^\d{4}-\d{2}-\d{2}$/.test(iso) ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : iso);
const ISO_DIA = /^\d{4}-\d{2}-\d{2}$/;
/** Días entre dos fechas AAAA-MM-DD (b − a). */
const diasEntre = (a: string, b: string) => Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86_400_000);

/** Fecha de la muestra (Corte 0b). Solo si el servidor dice que el formulario la admite (dias_atras_max > 0 y fecha_minima válida: hoy, Muestreo). Si no, la fecha es la de hoy,
 *  de solo lectura, y el cuerpo NO lleva «fecha_muestra» (Entrada y Salida, exactamente como antes). */
export function rangoFecha(def: FormularioDef): { min: string; max: string; dias: number } | null {
  const dias = typeof def.dias_atras_max === "number" && Number.isInteger(def.dias_atras_max) ? def.dias_atras_max : 0;
  if (dias <= 0 || typeof def.fecha_minima !== "string" || !ISO_DIA.test(def.fecha_minima) || !ISO_DIA.test(def.fecha_hoy) || def.fecha_minima > def.fecha_hoy) return null;
  return { min: def.fecha_minima, max: def.fecha_hoy, dias };
}
/** La fecha inicial: la del borrador si sigue dentro del rango; si no, hoy. */
export function fechaInicial(guardada: string | null | undefined, r: { min: string; max: string } | null, hoy: string): string {
  return r && typeof guardada === "string" && ISO_DIA.test(guardada) && guardada >= r.min && guardada <= r.max ? guardada : hoy;
}
/** Texto de la fecha para la confirmación y los avisos: «hoy, 15/11/2026», «ayer, 14/11/2026» o «el 12/11/2026 (hace 3 días)». */
export function textoFecha(fecha: string, hoy: string): string {
  const n = diasEntre(fecha, hoy);
  if (n === 0) return `hoy, ${dmy(fecha)}`;
  if (n === 1) return `ayer, ${dmy(fecha)}`;
  return `el ${dmy(fecha)} (hace ${n} días)`;
}

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
  const rango = useMemo(() => rangoFecha(def), [def]);
  // Fecha de la muestra elegida (solo con rango). Se conserva tras guardar (un lote de resultados del laboratorio suele ser del mismo día); «Descartar borrador» la vuelve a hoy.
  const [fecha, setFecha] = useState<string>(() => fechaInicial(inicial?.fecha, rango, def.fecha_hoy));
  // Hora de inicio del formulario abierto: TODAS sus tarjetas la heredan (decisión 12). Cambia solo cuando se guardan todas con éxito o al descartar.
  const [inicio, setInicio] = useState<string>(() => inicioAlAbrir(inicial?.inicio));
  const extra = useMemo(() => leerExtra(inicial?.claveEnvio), []); // eslint-disable-line react-hooks/exhaustive-deps
  // Planta preseleccionada (la del borrador o la primera, como Entrada). Tanques y puntos: SIN lugar elegido, salvo el que traiga el borrador.
  const [lugares, setLugares] = useState<Record<string, string>>(() => Object.fromEntries(tarjetas.map((t) => [t.id, lugarInicial(t, inicial?.textos ?? {}, extra.lugares[t.id] ?? (t.clase === "planta" ? inicial?.planta : null))])));
  const [estados, setEstados] = useState<Record<string, Estado>>({});          // por claveIntento(tarjeta, lugar)
  const [errores, setErrores] = useState<Record<string, string>>({});
  const [descartando, setDescartando] = useState(false);       // panel «¿Descartar lo escrito?»
  const [fase, setFase] = useState<"editando" | "confirmando" | "enviando">("editando");
  const [conf, setConf] = useState<Conf[]>([]);
  const [aviso, setAviso] = useState<Aviso | null>(inicial ? { tipo: "info", texto: "Se recuperó lo que había escrito antes en este equipo. Revíselo antes de guardar." } : null);

  const intentos = useRef<Record<string, Intento>>(extra.intentos);
  const enviando = useRef(false);
  const hayTexto = Object.values(textos).some((x) => typeof x === "string" && x.trim() !== "");
  // «Descartar borrador»: no hay consecutivo ni nada nuevo en el servidor. Las tarjetas que YA se guardaron no se tocan (el aviso lo dice). Se conserva la planta elegida.
  function descartar() {
    const guardadas = Object.values(estados).filter((e) => e.tipo === "ok").length;
    setTextos({}); setErrores({}); setEstados({}); setHora(def.hora_propuesta); setFecha(def.fecha_hoy); setDescartando(false);
    setLugares((l) => Object.fromEntries(tarjetas.map((x) => [x.id, x.clase === "planta" ? l[x.id] ?? "" : lugarInicial(x, {}, null)])));
    intentos.current = {};
    setInicio(nuevoInicio());
    borrarBorrador(clave);
    setAviso({ tipo: "info", texto: "Se descartó lo escrito en este equipo.", detalle: guardadas > 0 ? `${guardadas === 1 ? "Una tarjeta ya estaba guardada y no se afecta" : `${guardadas} tarjetas ya estaban guardadas y no se afectan`}.` : "Lo ya guardado en el servidor no se tocó." });
  }
  const reponerHora = useRef(false);
  const refTitulo = useRef<HTMLHeadingElement>(null);
  const refConfirmacion = useRef<HTMLHeadingElement>(null);

  useEffect(() => { if (reponerHora.current) { setHora(def.hora_propuesta); reponerHora.current = false; } }, [def.hora_propuesta, def.fecha_hoy]);
  // Si la definición se recarga con otro rango (cambió el día), una fecha que quedó fuera vuelve a hoy.
  useEffect(() => { setFecha((f) => fechaInicial(f, rango, def.fecha_hoy)); }, [rango, def.fecha_hoy]);
  useEffect(() => { if (fase === "confirmando") refConfirmacion.current?.focus(); }, [fase]);

  // Borrador local (misma mecánica que Entrada). Clave de los textos = «codigo@lugar»: cambiar de lugar no pierde lo escrito en el otro.
  useEffect(() => {
    const t = setTimeout(() => {
      const planta = tarjetas.find((x) => x.clase === "planta");
      guardarBorrador(clave, { uid, dia: def.fecha_hoy, planta: planta ? lugares[planta.id] ?? null : null, hora, textos, claveEnvio: JSON.stringify({ ...intentos.current, __lugares: Object.fromEntries(tarjetas.filter((x) => x.clase !== "ambas").map((x) => [x.id, lugares[x.id] ?? ""])) }), comunEnviada: null, inicio, ...(rango ? { fecha } : {}) });
    }, 400);
    return () => clearTimeout(t);
  }, [clave, uid, def.fecha_hoy, tarjetas, lugares, hora, textos, inicio, rango, fecha]);

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
    if (rango) {
      if (!ISO_DIA.test(fecha)) err["__fecha"] = "Elija la fecha de la muestra.";
      else if (fecha > rango.max) err["__fecha"] = "La fecha de la muestra no puede ser futura.";
      else if (fecha < rango.min) err["__fecha"] = `La fecha de la muestra puede ser hasta ${rango.dias} días atrás (desde el ${dmy(rango.min)}).`;
    }
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
      const primero = err["__fecha"] ? "__fecha" : err["__hora"] ? "__hora" : Object.keys(err).find((k) => !k.startsWith("__")) ?? null;
      if (primero) setTimeout(() => document.getElementById(primero === "__fecha" ? "tec-fecha" : primero === "__hora" ? "tec-hora" : `tec-c-${primero}`)?.focus(), 0);
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
    const ini = inicioAlEnviar(inicio);           // el mismo para todas las tarjetas de este envío y para sus reintentos
    if (ini !== inicio) setInicio(ini);
    for (const { tarjeta: t, lugar } of lista) {
      const ci = claveIntento(t, lugar);
      if (corte) { setEstados((s) => ({ ...s, [ci]: { tipo: "pendiente", texto: "No se envió.", detalle: "Se detuvo el envío por el problema anterior. Lo escrito se conserva; reintente." } })); fallas++; continue; }
      // Con rango (Muestreo) la fecha viaja SIEMPRE, también si es hoy: lo guardado es lo que la persona vio en la confirmación. Va en la huella: cambiar la fecha = clave nueva.
      const base = { ...cuerpoTarjeta(def, t, lugar, textos, hora), ...(rango ? { fecha_muestra: fecha } : {}) };
      const huella = JSON.stringify(base);
      const previo = intentos.current[ci];
      // Mismo contenido = misma clave (reintento seguro); si la persona cambió algo, clave nueva para que el servidor no devuelva el envío anterior.
      if (!previo || previo.huella !== huella) intentos.current[ci] = { base: nuevaClaveEnvio(), huella };
      try {
        const r = await apiTec.registrar({ ...base, clave_envio: claveEnvioTarjeta(intentos.current[ci].base, t, lugar), inicio_dispositivo: ini });
        setTextos((x) => { const n = { ...x }; for (const v of t.variables) delete n[claveTexto(v, lugar)]; return n; });
        delete intentos.current[ci];
        hechos.push(`${t.clase === "ambas" ? t.titulo : nombreLugar(t, lugar)}: ${r.guardados} ${r.guardados === 1 ? "valor" : "valores"}${r.duplicado ? " (ya estaba guardado)" : ""}`);
        setEstados((s) => ({ ...s, [ci]: { tipo: "ok", texto: r.duplicado ? "Ya estaba guardado; no se duplicó." : "Guardado.", detalle: `${r.guardados} ${r.guardados === 1 ? "valor guardado" : "valores guardados"} · muestra ${rango ? `tomada ${textoFecha(r.fecha_muestra ?? fecha, def.fecha_hoy)}, a las ${base.hora}` : `de las ${base.hora}`}.` } }));
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
      setInicio(nuevoInicio());                   // todo guardado: lo siguiente que se escriba es otro formulario abierto
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
              <span>{o.nombre}</span>{o.codigo !== lugar && conDatos(t, o.codigo, textos) ? <span className="tec-con-datos">con datos</span> : null}
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
        {t.clase === "punto" && t.grupo === "muestreo" && t.opciones.length > 0 ? (
          // Corte 5b: el minimapa de los puntos de muestreo, sincronizado con la lista (tocar un punto lo elige; elegirlo en la lista lo resalta)
          <MapaMuestreo opciones={t.opciones} lugar={lugar} bloqueado={bloqueado} onElegir={(c) => setLugares((x) => ({ ...x, [t.id]: c }))} />
        ) : null}
        {selector(t)}
        {t.clase !== "ambas" && t.opciones.length > 0 && !tieneLugar(t, lugar) ? <p className="tec-elegir" data-testid="elegir-lugar">{textoElegirLugar(t)}</p> : null}
        {tieneLugar(t, lugar) ? t.variables.map((v) => campo(t, v)) : null}
        {st ? (
          <div className={`tec-estado tec-estado-${st.tipo}`} role={st.tipo === "error" ? "alert" : "status"}>
            <strong>{st.texto}</strong>
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
          {rango ? (
            <p className="tec-sub" data-testid="conf-fecha">Muestra tomada <strong>{textoFecha(fecha, def.fecha_hoy)}</strong>, a las {hora}. Se registra hoy, {dmy(def.fecha_hoy)}. Se guarda un registro por cada lugar.</p>
          ) : (
            <p className="tec-sub">Muestra de hoy, {dmy(def.fecha_hoy)}, a las {hora}. Se guarda un registro por cada lugar.</p>
          )}
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
          {rango ? (
            <div className="tec-campo">
              <label htmlFor="tec-fecha">Fecha de la muestra</label>
              <input id="tec-fecha" type="date" value={fecha} min={rango.min} max={rango.max} required disabled={bloqueado}
                aria-invalid={errores["__fecha"] ? true : undefined} aria-describedby="tec-fecha-ayuda"
                onChange={(e) => { setFecha(e.target.value); if (errores["__fecha"]) setErrores((x) => { const n = { ...x }; delete n["__fecha"]; return n; }); }} />
              <span id="tec-fecha-ayuda" className="tec-ayuda">El día en que se tomó la muestra: hoy o hasta {rango.dias} días atrás (desde el {dmy(rango.min)}), porque los resultados del laboratorio llegan después. No puede ser futura.</span>
              {fecha !== def.fecha_hoy && ISO_DIA.test(fecha) && !errores["__fecha"] ? <span className="tec-ayuda tec-pista" data-testid="fecha-pasada">Muestra tomada {textoFecha(fecha, def.fecha_hoy)}.</span> : null}
              {errores["__fecha"] ? <span className="tec-error">{errores["__fecha"]}</span> : null}
            </div>
          ) : (
            <div className="tec-campo">
              <label htmlFor="tec-fecha">Fecha de la muestra</label>
              <input id="tec-fecha" type="text" readOnly value={`Hoy · ${dmy(def.fecha_hoy)}`} className="tec-solo-lectura" />
              <span className="tec-ayuda">Solo se puede registrar el día de hoy.</span>
            </div>
          )}
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
          {hayTexto && !descartando ? <button type="button" className="btn-cancelar" onClick={() => setDescartando(true)} disabled={bloqueado}>Descartar borrador</button> : null}
          {descartando ? (
            <ConfirmarCancelar titulo="¿Descartar lo escrito?" rotuloConfirmar="Sí, descartar"
              mensaje="Se borra lo escrito en este equipo (el borrador). Lo que ya guardó en el servidor no se toca."
              onConfirmar={descartar} onSeguir={() => setDescartando(false)} />
          ) : null}
          <p className="tec-ayuda">Todos los campos son opcionales: se guarda un registro por cada tarjeta con datos. Los valores se guardan tal como los escribe. Si algo quedó mal registrado, avise a su supervisor.</p>
        </>
      )}
      {fase === "enviando" && <div className="tec-aviso tec-aviso-info" role="status">Guardando… no cierre esta pantalla.</div>}
    </section>
  );
}
