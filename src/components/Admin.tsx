import { useEffect, useMemo, useState } from "react";
import { api, type UsuarioAdmin, type EstadoPausa, type Accesos } from "../lib/api";
import "./admin-tecnica.css";
import "./admin-perfiles.css";
import { apiGestion, type PersonaRedes } from "../tecnica/apiRedes";
import {
  CASILLAS_DE, FORMULARIOS_COMERCIAL, MODOS, NOMBRE_CASILLA, PERFILES_ASEO, PERFILES_FORMULARIOS, PERFILES_TECNICA,
  aplicarAseo, aplicarFormularios, aplicarTecnica, avisoHorario, casillasDe, disponibles, envio, esPersonalizado, lineaUsuario, perfilDisponible, ponerCasilla, ponerModo,
  reconocer, resumen, sinNada, verificar,
  type Casilla, type Casillas, type Datos, type Geoportal, type PerfilAseo, type PerfilFormularios, type PerfilTecnica, type Resumen,
} from "./perfilesAdmin";

// Administración de usuarios (encargo v2 del 22-nov-2026). Administración solo decide a qué geoportal entra cada persona y con qué perfil general; lo de adentro
// (área, alcance, formularios, cuadrillas, actividades) lo decide el supervisor en el Personal de cada geoportal. La traducción perfil ↔ casillas es pura (perfilesAdmin.ts).
// Se envían SIEMPRE todas las casillas que el servidor lista (nada se conserva en silencio), con un resumen antes de guardar y una sola verificación después.

type Props = { onVolver: () => void };

// Técnica fase 1, Corte 4b (N-13 y §27.3): la casilla del geovisor del operador de distribución vive en Personal del Dashboard distribución.
// Aquí solo se MUESTRA (una sola casilla, en un solo lugar). Se lee de geoportal-redes, que lo vuelve a verificar (el administrador puede).
function GeovisorSoloLectura({ email }: { email: string }) {
  const [p, setP] = useState<PersonaRedes | null | undefined>(undefined);
  useEffect(() => {
    let vivo = true; setP(undefined);
    apiGestion.personal(email, "todas").then((r) => { if (vivo) setP(r.personas.find((x) => x.email === email.toLowerCase()) ?? null); }).catch(() => { if (vivo) setP(null); });
    return () => { vivo = false; };
  }, [email]);
  if (p === undefined) return null;
  const texto = !p ? "sin datos todavía (se ve cuando la persona tenga Registro técnico guardado)"
    : p.geovisor === "por_permiso" ? "completo, por su permiso de supervisor" : p.geovisor === "si" ? "sí, en solo lectura" : "no";
  return <p className="adm-aviso-tec" data-geovisor={p?.geovisor ?? "sin_dato"}>Geovisor de distribución: <strong>{texto}</strong>. Se cambia en Personal del Dashboard distribución
    {p?.area ? ` · Área: ${p.area === "ambas" ? "planta y distribución" : p.area === "distribucion" ? "distribución" : "planta"}` : ""}.</p>;
}

// ---------- Los tres renglones (Comercial, Técnica, Aseo) ----------
const PERSO = "perso";
const DESCRIPCION_FORMULARIOS: Record<PerfilFormularios, string> = {
  sin: "Sin Formatos de campo ni Análisis de contrato.",
  operario: "Reporta en Formatos de campo, registra el acta de posible pérdida y consulta contratos (Análisis de contrato, con nombre y teléfono). Sus formularios, cuadrilla y actividades los fija su supervisor en Personal.",
  supervisor: "Lo del operario, más «Supervisión y dashboard», «Actas registradas», «Actividades derivadas» y el Personal de Comercial.",
};
const DESCRIPCION_TECNICA: Record<PerfilTecnica, string> = {
  sin: "No entra a Técnica.",
  operario: "Llena los formularios que su supervisor le asigne en Personal técnico o de distribución.",
  sup_plantas: "Captura y supervisa plantas: Dashboard PTAP con Personal técnico.",
  sup_distribucion: "Captura y supervisa distribución: Dashboard distribución con su Personal.",
  sup_ambas: "Captura y supervisa plantas y distribución: los dos dashboards.",
};
const DESCRIPCION_ASEO: Record<PerfilAseo, string> = {
  sin: "No entra a Aseo.",
  auditor: "Audita rutas y registra la auditoría con fotos.",
  supervisor: "Audita y además revisa: «Supervisión y dashboard» con el Personal de aseo.",
};

/** Lista en solo lectura de las casillas encendidas de un grupo «Personalizado», y sus «Ajustes avanzados» (R6) plegados. */
function Personalizado({ geoportal, casillas, c, disp, onCambio }: { geoportal: Geoportal; casillas: Casilla[]; c: Casillas; disp: Set<Casilla>; onCambio: (n: Casillas) => void }) {
  const activas = casillas.filter((x) => c[x]);
  return (
    <div className="adm-perso" data-personalizado={geoportal}>
      <p className="adm-perso-lista">Tiene hoy: <strong>{activas.length ? activas.map((x) => NOMBRE_CASILLA[x]).join(" · ") : "ninguna"}</strong>. No calza con un perfil: escoja uno para simplificar. Si guarda sin tocarlo, queda tal cual.</p>
      <details className="adm-avanzado">
        <summary>Ajustes avanzados</summary>
        <div className="adm-avanzado-casillas">
          {casillas.map((x) => (
            <label key={x} className="adm-check">
              <input type="checkbox" checked={c[x]} disabled={!disp.has(x)} data-casilla={x} onChange={(e) => onCambio(ponerCasilla(c, geoportal, x, e.target.checked))} />
              {NOMBRE_CASILLA[x]}{disp.has(x) ? "" : " (no disponible)"}
            </label>
          ))}
        </div>
      </details>
    </div>
  );
}

function Renglones({ c, original, disp, email, onCambio }: { c: Casillas; original: Casillas; disp: Set<Casilla>; email: string | null; onCambio: (n: Casillas) => void }) {
  const r = reconocer(c), r0 = reconocer(original);
  // «Personalizado» se ofrece en el selector solo si así estaba al abrir; volver a elegirlo restaura las casillas de ese grupo como estaban
  const restaurar = (grupo: Casilla[]) => { const n = { ...c }; for (const x of grupo) n[x] = original[x]; onCambio(n); };
  const hay = (g: Casilla[]) => g.some((x) => disp.has(x));
  const tecnica = CASILLAS_DE.tecnica, aseo = CASILLAS_DE.aseo;
  return (
    <div className="adm-renglones">
      <section className="adm-renglon adm-renglon-com" data-renglon="comercial" aria-label="Geoportal Comercial">
        <h3 className="adm-renglon-tit">Comercial</h3>
        <div className="adm-renglon-parte">
          <div className="adm-editor-et">Modos del geovisor (mapa comercial)</div>
          <div className="adm-modos">
            {MODOS.map((m) => (
              <label key={m} className="adm-check">
                <input type="checkbox" checked={c[m]} data-modo={m} onChange={(e) => onCambio(ponerModo(c, m, e.target.checked))} />
                {NOMBRE_CASILLA[m]}
              </label>
            ))}
          </div>
        </div>
        {hay(FORMULARIOS_COMERCIAL) ? (
          <div className="adm-renglon-parte">
            <label className="adm-editor-et" htmlFor="adm-sel-formularios">Formularios de campo</label>
            <select id="adm-sel-formularios" className="adm-sel adm-sel-perfil" data-perfil="formularios" value={r.formularios ?? PERSO}
              onChange={(e) => (e.target.value === PERSO ? restaurar(FORMULARIOS_COMERCIAL) : onCambio(aplicarFormularios(c, e.target.value as PerfilFormularios)))}>
              {(Object.keys(PERFILES_FORMULARIOS) as PerfilFormularios[]).map((p) => (
                <option key={p} value={p} disabled={!perfilDisponible(PERFILES_FORMULARIOS[p].casillas, disp)}>{PERFILES_FORMULARIOS[p].nombre}</option>
              ))}
              {r0.formularios === null ? <option value={PERSO}>Personalizado (como está hoy)</option> : null}
            </select>
            {r.formularios === null
              ? <Personalizado geoportal="comercial" casillas={FORMULARIOS_COMERCIAL} c={c} disp={disp} onCambio={onCambio} />
              : <p className="adm-renglon-desc">{DESCRIPCION_FORMULARIOS[r.formularios]}{r.formularios === "sin" && MODOS.some((m) => c[m]) ? " Con modos marcados es «Consulta»: solo el mapa." : ""}</p>}
          </div>
        ) : <p className="adm-renglon-desc">Formularios de campo: no disponible en este servidor.</p>}
      </section>

      <section className="adm-renglon adm-renglon-tec" data-renglon="tecnica" aria-label="Geoportal Técnica">
        <h3 className="adm-renglon-tit">Técnica</h3>
        {hay(tecnica) ? (
          <div className="adm-renglon-parte">
            <label className="adm-editor-et" htmlFor="adm-sel-tecnica">Perfil</label>
            <select id="adm-sel-tecnica" className="adm-sel adm-sel-perfil" data-perfil="tecnica" value={r.tecnica ?? PERSO}
              onChange={(e) => (e.target.value === PERSO ? restaurar(tecnica) : onCambio(aplicarTecnica(c, e.target.value as PerfilTecnica)))}>
              {(Object.keys(PERFILES_TECNICA) as PerfilTecnica[]).map((p) => (
                <option key={p} value={p} disabled={!perfilDisponible(PERFILES_TECNICA[p].casillas, disp)}>{PERFILES_TECNICA[p].nombre}{perfilDisponible(PERFILES_TECNICA[p].casillas, disp) ? "" : " (no disponible)"}</option>
              ))}
              {r0.tecnica === null ? <option value={PERSO}>Personalizado (como está hoy)</option> : null}
            </select>
            {r.tecnica === null
              ? <Personalizado geoportal="tecnica" casillas={tecnica} c={c} disp={disp} onCambio={onCambio} />
              : <p className="adm-renglon-desc">{DESCRIPCION_TECNICA[r.tecnica]}{r.tecnica !== "sin" ? " El alcance PTAR, el área y los formularios se fijan en Personal técnico." : ""}</p>}
            {email && disp.has("dashboard_redes") && c.registro_tecnico ? <GeovisorSoloLectura email={email} /> : null}
          </div>
        ) : <p className="adm-renglon-desc">No disponible en este servidor.</p>}
      </section>

      <section className="adm-renglon adm-renglon-aseo" data-renglon="aseo" aria-label="Geoportal Aseo">
        <h3 className="adm-renglon-tit">Aseo</h3>
        {hay(aseo) ? (
          <div className="adm-renglon-parte">
            <label className="adm-editor-et" htmlFor="adm-sel-aseo">Perfil</label>
            <select id="adm-sel-aseo" className="adm-sel adm-sel-perfil" data-perfil="aseo" value={r.aseo ?? PERSO}
              onChange={(e) => (e.target.value === PERSO ? restaurar(aseo) : onCambio(aplicarAseo(c, e.target.value as PerfilAseo)))}>
              {(Object.keys(PERFILES_ASEO) as PerfilAseo[]).map((p) => <option key={p} value={p} disabled={!perfilDisponible(PERFILES_ASEO[p].casillas, disp)}>{PERFILES_ASEO[p].nombre}</option>)}
              {r0.aseo === null ? <option value={PERSO}>Personalizado (como está hoy)</option> : null}
            </select>
            {r.aseo === null ? <Personalizado geoportal="aseo" casillas={aseo} c={c} disp={disp} onCambio={onCambio} /> : <p className="adm-renglon-desc">{DESCRIPCION_ASEO[r.aseo]}</p>}
          </div>
        ) : <p className="adm-renglon-desc">No disponible en este servidor.</p>}
      </section>
    </div>
  );
}

function Horario({ horario, dias, onCambio }: { horario: string; dias: string; onCambio: (h: string, d: string) => void }) {
  return (
    <div className="adm-horario">
      <label className="adm-campo-et">Horario
        <select className="adm-sel" data-campo="horario" value={horario} onChange={(e) => onCambio(e.target.value, dias)}>
          <option value="laboral">Laboral (7:50–18:00)</option>
          <option value="extendido">Extendido (7:00–22:00)</option>
          <option value="sin_restriccion">Sin restricción horaria</option>
        </select>
      </label>
      <label className="adm-campo-et">Días
        <select className="adm-sel" data-campo="dias" value={dias} onChange={(e) => onCambio(horario, e.target.value)}>
          <option value="habiles">Lunes a viernes</option>
          <option value="todos">Todos los días</option>
        </select>
      </label>
    </div>
  );
}

const NOMBRE_GEO: Record<Geoportal, string> = { comercial: "Comercial", tecnica: "Técnica", aseo: "Aseo" };
const ETIQUETA_DATO: Record<keyof Datos, string> = { nombre: "Nombre", rol: "Tipo de cuenta", horario: "Horario", dias: "Días" };
/** El resumen antes de guardar (§0.6): por geoportal, lo que se apaga en rojo y lo que se enciende en verde, y el nombre, el tipo de cuenta, el horario y los días. */
function PanelResumen({ r, titulo, extra, onConfirmar, onVolver, ocupado }: { r: Resumen; titulo: string; extra?: string; onConfirmar: () => void; onVolver: () => void; ocupado: boolean }) {
  return (
    <section className="adm-resumen" data-testid="adm-resumen" aria-label="Resumen antes de guardar">
      <h3 className="adm-resumen-tit">{titulo}</h3>
      {extra ? <p className="adm-resumen-extra">{extra}</p> : null}
      {r.vacio ? <p className="adm-resumen-vacio">No hay cambios: guardar no cambia nada.</p> : null}
      {r.renglones.map((g) => (
        <div key={g.geoportal} className="adm-resumen-geo" data-geoportal={g.geoportal}>
          <div className="adm-resumen-linea"><strong>{NOMBRE_GEO[g.geoportal]}:</strong> {g.antes} → <strong>{g.despues}</strong></div>
          <ul className="adm-resumen-cambios">
            {r.cambios.filter((x) => x.geoportal === g.geoportal).map((x) => (
              <li key={x.casilla} className={x.enciende ? "adm-enciende" : "adm-apaga"} data-cambio={x.enciende ? "enciende" : "apaga"} data-casilla={x.casilla}>
                <span aria-hidden="true">{x.enciende ? "+" : "−"}</span> {x.enciende ? "Se enciende" : "Se apaga"}: {x.nombre}
              </li>
            ))}
          </ul>
        </div>
      ))}
      {r.datos.length ? (
        <ul className="adm-resumen-datos">
          {r.datos.map((d) => <li key={d.campo} data-dato={d.campo}><strong>{ETIQUETA_DATO[d.campo]}:</strong> {d.antes} → <strong>{d.despues}</strong></li>)}
        </ul>
      ) : null}
      {r.destacados.map((t) => <p key={t} className="adm-resumen-destacado" role="note">{t}</p>)}
      <div className="adm-resumen-botones">
        <button type="button" className="btn-sm" onClick={onConfirmar} disabled={ocupado}>{ocupado ? "Guardando…" : "Confirmar"}</button>
        <button type="button" className="btn-link" onClick={onVolver} disabled={ocupado}>Volver</button>
      </div>
    </section>
  );
}

// ---------- Estado de una edición ----------
type Edicion = {
  modo: "editar" | "hacer_consulta";
  email: string;
  original: Casillas; c: Casillas;
  nombre0: string; nombre: string; horario0: string; horario: string; dias0: string; dias: string;
  rol0: string; activo: boolean;
  paso: "editar" | "resumen";
};
type Alta = { email: string; nombre: string; clave: string; tipo: "usuario" | "admin"; c: Casillas; horario: string; dias: string; paso: "editar" | "resumen" };
const altaVacia = (): Alta => ({ email: "", nombre: "", clave: "", tipo: "usuario", c: sinNada(), horario: "laboral", dias: "habiles", paso: "editar" });
const DOMINIO = "@emdupar.gov.co";
const normalizar = (e: string) => { const t = e.trim().toLowerCase(); return t.includes("@") ? t : t + DOMINIO; };
const mensaje = (e: unknown, otro: string) => (e instanceof Error ? e.message : otro);

export function Admin({ onVolver }: Props) {
  const [usuarios, setUsuarios] = useState<UsuarioAdmin[]>([]);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [alta, setAlta] = useState<Alta | null>(null);
  const [ed, setEd] = useState<Edicion | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [pausa, setPausa] = useState<EstadoPausa | null>(null);
  const [cambiandoPausa, setCambiandoPausa] = useState(false);
  const [pestana, setPestana] = useState<"usuarios" | "accesos">("usuarios");
  const [accesos, setAccesos] = useState<Accesos | null>(null);
  const [cargandoAcc, setCargandoAcc] = useState(false);
  // Las casillas que el servidor ya lista (R11): las demás se muestran «no disponible» y no se envían.
  const disp = useMemo(() => disponibles(usuarios), [usuarios]);
  // El editor va debajo de la lista: al abrirlo (o pasar al resumen) se lleva a la vista
  const claveEd = ed ? `${ed.email}|${ed.modo}|${ed.paso}` : "";
  useEffect(() => { if (claveEd) document.querySelector("[data-testid=adm-editor]")?.scrollIntoView?.({ block: "start" }); }, [claveEd]);

  async function cargar(): Promise<UsuarioAdmin[]> {
    setCargando(true);
    setError(null);
    try {
      const { usuarios } = await api.admin.listar();
      setUsuarios(usuarios);
      return usuarios;
    } catch (e) {
      setError(mensaje(e, "Error cargando usuarios."));
      return [];
    } finally {
      setCargando(false);
    }
  }

  useEffect(() => {
    cargar();
    api.admin.pausa().then((r) => setPausa(r.pausa)).catch(() => {});
  }, []);

  async function cargarAccesos() {
    setCargandoAcc(true);
    try {
      const r = await api.admin.accesos(7);
      setAccesos(r.accesos);
    } catch {
      setError("No se pudieron cargar los accesos.");
    } finally {
      setCargandoAcc(false);
    }
  }

  useEffect(() => {
    if (pestana === "accesos") cargarAccesos();
  }, [pestana]);

  async function cambiarPausa(activar: boolean) {
    if (activar) {
      const n = pausa?.afectados ?? 0;
      if (!window.confirm(
        "Se va a suspender el acceso de " + n + " usuarios de consulta.\n\n" +
        "Los administradores seguiran entrando. Ningun perfil se modifica: " +
        "al reactivar, todos vuelven como estaban.\n\nContinuar?"
      )) return;
    }
    setCambiandoPausa(true);
    setError(null);
    try {
      const r = await api.admin.pausaSet(activar);
      setPausa(r.pausa);
      setMsg(activar ? "Acceso suspendido." : "Acceso restablecido.");
    } catch {
      setError("No se pudo cambiar el estado del acceso.");
    } finally {
      setCambiandoPausa(false);
    }
  }

  // ---------- Editar y «Hacer consulta» (R10) ----------
  function abrir(u: UsuarioAdmin, modo: Edicion["modo"]) {
    setError(null); setMsg(null); setAlta(null);
    if (ed && ed.email === u.email && ed.modo === modo) { setEd(null); return; }
    const c = casillasDe(u), nombre = u.nombre && u.nombre !== u.email ? u.nombre : "";
    setEd({ modo, email: u.email, original: c, c, nombre0: nombre, nombre, horario0: u.horario ?? "laboral", horario: u.horario ?? "laboral", dias0: u.dias ?? "habiles", dias: u.dias ?? "habiles",
            rol0: u.rol, activo: u.activo, paso: "editar" });
  }
  const rolFinal = (e: Edicion) => (e.modo === "hacer_consulta" ? "consulta" : e.rol0);
  const resumenDe = (e: Edicion) => (rolFinal(e) === "admin"
    ? resumen(e.original, e.original, { nombre: e.nombre0, horario: "", dias: "", rol: e.rol0 }, { nombre: e.nombre.trim() || e.nombre0, horario: "", dias: "", rol: e.rol0 }, disp)
    : resumen(e.original, e.c, { nombre: e.nombre0, horario: e.horario0, dias: e.dias0, rol: e.rol0 }, { nombre: e.nombre.trim() || e.nombre0, horario: e.horario, dias: e.dias, rol: rolFinal(e) }, disp));

  async function confirmarEdicion(e: Edicion) {
    setOcupado(true); setError(null); setMsg(null);
    const sigueAdmin = rolFinal(e) === "admin";
    const cambiaNombre = e.nombre.trim() !== "" && e.nombre.trim() !== e.nombre0.trim();
    const cambiaRol = rolFinal(e) !== e.rol0;
    let permisosOk = false;
    try {
      // 1. Las casillas (un administrador que sigue siéndolo no las usa: no se envían)
      if (!sigueAdmin) { await api.admin.permisos(envio(e.email, e.c, e.horario, e.dias, disp)); permisosOk = true; }
      // 2. El nombre y el tipo de cuenta, por `guardar`: siempre con el rol y el estado que corresponden (sin rol degradaría a un administrador) y nunca con perfil_tecnico
      if (cambiaNombre || cambiaRol) {
        try { await api.admin.guardar({ email: e.email, nombre: cambiaNombre ? e.nombre.trim() : undefined, rol: rolFinal(e), activo: e.activo }); }
        catch (x) {
          const falta = [cambiaNombre ? "el nombre" : "", cambiaRol ? "el cambio de tipo de cuenta" : ""].filter(Boolean).join(" ni ");
          setError(`${permisosOk ? "Los permisos se guardaron, pero no se guardó " : "No se guardó "}${falta}: ${mensaje(x, "error")}. ${permisosOk ? "El cambio quedó a medias: vuelva a abrir y guarde de nuevo." : ""}`.trim());
          await cargar(); setEd(null); return;
        }
      }
      // 3. Una sola verificación: se relee y se compara cada casilla enviada, el nombre, el rol, el horario, los días y el estado
      const lista = await cargar();
      const leido = lista.find((x) => x.email === e.email);
      const faltas = verificar(e.email, sigueAdmin && leido ? casillasDe(leido) : e.c,
        { nombre: e.nombre, horario: sigueAdmin ? e.horario0 : e.horario, dias: sigueAdmin ? e.dias0 : e.dias, rol: rolFinal(e), activo: e.activo }, disp, lista, { nombre: cambiaNombre });
      if (faltas.length) { setError(`El servidor no aplicó: ${faltas.join(", ")} (${e.email}).`); setEd(null); return; }
      setMsg(`Cambios guardados para ${e.email}.`);
      setEd(null);
    } catch (x) {
      // permisos rechazado (p. ej. el 409 de la compuerta de aislamiento): el texto de la Edge, tal cual; no se cambió nada
      setError(mensaje(x, "No se pudo guardar."));
      setEd({ ...e, paso: "editar" });
    } finally {
      setOcupado(false);
    }
  }

  // ---------- Nuevo usuario (§0.8, R9) ----------
  function validarAlta(a: Alta): string | null {
    const correo = normalizar(a.email);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(correo)) return "Escribe un correo válido.";
    if (usuarios.some((u) => u.email === correo)) return "Ese usuario ya existe: use Editar o Nueva clave.";
    if (a.clave.length < 8) return "La clave debe tener al menos 8 caracteres.";
    return null;
  }
  const resumenAlta = (a: Alta) => resumen(sinNada(), a.tipo === "admin" ? sinNada() : a.c, { nombre: "", horario: "", dias: "", rol: "" },
    { nombre: a.nombre, horario: a.tipo === "admin" ? "" : a.horario, dias: a.tipo === "admin" ? "" : a.dias, rol: a.tipo === "admin" ? "admin" : "consulta" }, disp);

  async function confirmarAlta(a: Alta) {
    const correo = normalizar(a.email);
    const v = validarAlta(a); if (v) { setError(v); setAlta({ ...a, paso: "editar" }); return; }
    setOcupado(true); setError(null); setMsg(null);
    let paso = "crear la cuenta";
    try {
      if (a.tipo === "admin") {
        const r = await api.admin.guardar({ email: correo, nombre: a.nombre.trim() || undefined, rol: "admin", activo: true, password: a.clave });
        paso = "verificar";
        const faltas = verificar(correo, sinNada(), { nombre: a.nombre, horario: "", dias: "", rol: "admin", activo: true }, new Set(), await cargar(), { nombre: !!a.nombre.trim() });
        if (faltas.length) { setError(`El servidor no aplicó: ${faltas.join(", ")} (${correo}).`); return; }
        setMsg(`Administrador ${correo} ${r.auth === "creado" ? "creado" : "agregado"} con su clave.`); setAlta(null); return;
      }
      // 1. Se crea INACTIVO (sin perfil técnico): mientras no tenga sus permisos, no entra
      await api.admin.guardar({ email: correo, nombre: a.nombre.trim() || undefined, rol: "consulta", activo: false, password: a.clave });
      // 2. Sus permisos: todas las casillas, explícitas
      paso = "guardar sus permisos";
      await api.admin.permisos(envio(correo, a.c, a.horario, a.dias, disp));
      paso = "verificar sus permisos";
      let faltas = verificar(correo, a.c, { nombre: a.nombre, horario: a.horario, dias: a.dias, rol: "consulta", activo: false }, disp, await cargar(), { nombre: !!a.nombre.trim() });
      if (faltas.length) { setError(`El servidor no aplicó: ${faltas.join(", ")} (${correo}). La cuenta quedó INACTIVA: corríjala con Editar y actívela.`); setAlta(null); return; }
      // 3. Se activa
      paso = "activarlo";
      await api.admin.guardar({ email: correo, rol: "consulta", activo: true });
      const lista = await cargar();
      faltas = verificar(correo, a.c, { nombre: a.nombre, horario: a.horario, dias: a.dias, rol: "consulta", activo: true }, disp, lista);
      if (faltas.length) { setError(`El servidor no aplicó: ${faltas.join(", ")} (${correo}). La cuenta quedó INACTIVA.`); setAlta(null); return; }
      const u = lista.find((x) => x.email === correo);
      setMsg(`Usuario ${correo} creado y activo${u ? `: ${lineaUsuario(u)}` : ""}.`);
      setAlta(null);
    } catch (x) {
      setError(`No se pudo ${paso}: ${mensaje(x, "error")}.${paso === "crear la cuenta" ? "" : " La cuenta quedó INACTIVA: corríjala con Editar y actívela."}`);
      await cargar();
      setAlta(paso === "crear la cuenta" ? { ...a, paso: "editar" } : null);
    } finally {
      setOcupado(false);
    }
  }

  async function cambiar(u: UsuarioAdmin, cambios: Partial<{ rol: string; activo: boolean }>) {
    setMsg(null);
    setError(null);
    try {
      await api.admin.guardar({ email: u.email, rol: cambios.rol ?? u.rol, activo: cambios.activo ?? u.activo });
      await cargar();
    } catch (e) {
      setError(mensaje(e, "Error guardando."));
    }
  }

  function nuevaClave(u: UsuarioAdmin) {
    const c = window.prompt(`Nueva clave para ${u.email} (mínimo 8 caracteres):`);
    if (!c) return;
    if (c.length < 8) {
      setError("La clave debe tener al menos 8 caracteres.");
      return;
    }
    setError(null);
    api.admin
      .guardar({ email: u.email, rol: u.rol, activo: u.activo, password: c })
      .then(() => setMsg(`Clave actualizada para ${u.email}.`))
      .catch((e) => setError(mensaje(e, "Error.")));
  }

  const totalAdmin = usuarios.filter((u) => u.rol === "admin").length;
  const nPerso = usuarios.filter((u) => u.rol !== "admin" && esPersonalizado(casillasDe(u)).length > 0).length;

  return (
    <div className="adm">
      {pausa && (
        <div className={"adm-pausa" + (pausa.pausado ? " activa" : "")}>
          <div>
            <strong>
              {pausa.pausado ? "Acceso suspendido" : "Acceso normal"}
            </strong>
            <p className="adm-pausa-txt">
              {pausa.pausado
                ? "Los " + pausa.afectados + " usuarios de consulta no pueden entrar. " +
                  "Suspendido por " + (pausa.pausado_por ?? "") +
                  (pausa.pausado_en
                    ? " el " + new Date(pausa.pausado_en).toLocaleString("es-CO")
                    : "") + "."
                : "Los " + pausa.afectados + " usuarios de consulta entran con su horario habitual."}
            </p>
          </div>
          <button
            className={pausa.pausado ? "btn-sm" : "btn-sm btn-peligro"}
            disabled={cambiandoPausa}
            onClick={() => cambiarPausa(!pausa.pausado)}
          >
            {cambiandoPausa
              ? "..."
              : pausa.pausado ? "Restablecer acceso" : "Suspender acceso"}
          </button>
        </div>
      )}
      <div className="adm-cab">
        <div>
          <h2 className="adm-titulo">Administración de usuarios</h2>
          <p className="adm-sub">
            {usuarios.length} usuarios · {totalAdmin} administradores{nPerso ? ` · ${nPerso} con algún geoportal «Personalizado»` : ""}
          </p>
        </div>
        <div className="adm-cab-acciones">
          <button className="btn-sm" onClick={() => { setError(null); setMsg(null); setEd(null); setAlta(alta ? null : altaVacia()); }}>
            {alta ? "Cancelar" : "Nuevo usuario"}
          </button>
          <button className="btn-link" onClick={onVolver}>
            Volver
          </button>
        </div>
      </div>

      {alta && (
        <div className="adm-nuevo adm-alta" data-testid="adm-alta">
          <div className="adm-alta-datos">
            <input className="field" placeholder="correo@emdupar.gov.co" value={alta.email} data-campo="correo" onChange={(e) => setAlta({ ...alta, email: e.target.value, paso: "editar" })} />
            <input className="field" placeholder="Nombre (opcional)" value={alta.nombre} data-campo="nombre" onChange={(e) => setAlta({ ...alta, nombre: e.target.value, paso: "editar" })} />
            <input className="field" placeholder="Clave inicial (mín. 8)" type="text" value={alta.clave} data-campo="clave" onChange={(e) => setAlta({ ...alta, clave: e.target.value, paso: "editar" })} />
            <select className="field" value={alta.tipo} data-campo="tipo" onChange={(e) => setAlta({ ...alta, tipo: e.target.value as Alta["tipo"], paso: "editar" })}>
              <option value="usuario">Usuario (acceso por geoportal)</option>
              <option value="admin">Administrador (entra a todo)</option>
            </select>
          </div>
          {alta.tipo === "usuario" && alta.paso === "editar" ? (
            <>
              <Renglones c={alta.c} original={sinNada()} disp={disp} email={null} onCambio={(c) => setAlta({ ...alta, c })} />
              <Horario horario={alta.horario} dias={alta.dias} onCambio={(horario, dias) => setAlta({ ...alta, horario, dias })} />
              {avisoHorario(alta.c, alta.horario, alta.dias) ? <p className="adm-aviso-horario" role="alert">{avisoHorario(alta.c, alta.horario, alta.dias)}</p> : null}
            </>
          ) : null}
          {alta.paso === "editar" ? (
            <div className="adm-resumen-botones">
              <button type="button" className="btn-sm" onClick={() => { const v = validarAlta(alta); if (v) { setError(v); return; } setError(null); setAlta({ ...alta, paso: "resumen" }); }}>Revisar y crear</button>
            </div>
          ) : (
            <PanelResumen r={resumenAlta(alta)} titulo={`Crear ${normalizar(alta.email)}`} ocupado={ocupado}
              extra={alta.tipo === "admin" ? "Será administrador: entra a todos los geoportales." : "Se crea inactivo, se guardan sus permisos, se verifican y solo entonces se activa."}
              onConfirmar={() => void confirmarAlta(alta)} onVolver={() => setAlta({ ...alta, paso: "editar" })} />
          )}
        </div>
      )}

      {error && <p className="error" role="alert">{error}</p>}
      {msg && <p className="hint" role="status">{msg}</p>}
      {cargando && <p className="hint">Cargando…</p>}

      <div className="adm-pestanas">
        <button
          className={"adm-pest" + (pestana === "usuarios" ? " activa" : "")}
          onClick={() => setPestana("usuarios")}
        >Usuarios</button>
        <button
          className={"adm-pest" + (pestana === "accesos" ? " activa" : "")}
          onClick={() => setPestana("accesos")}
        >Accesos</button>
      </div>

      {pestana === "accesos" && (
        <div className="adm-accesos">
          <div className="adm-acc-cab">
            <strong>Activos ahora</strong>
            <button className="btn-sm" onClick={cargarAccesos} disabled={cargandoAcc}>
              {cargandoAcc ? "..." : "Actualizar"}
            </button>
          </div>
          {!accesos || accesos.activos.length === 0 ? (
            <p className="hint">Nadie con actividad en los últimos 15 minutos.</p>
          ) : (
            <table className="adm-tabla">
              <thead><tr><th>Usuario</th><th>Hace</th><th>Acciones</th><th>IP</th></tr></thead>
              <tbody>
                {accesos.activos.map((a) => (
                  <tr key={a.email}>
                    <td>{a.email}</td>
                    <td>{a.minutos === 0 ? "ahora" : a.minutos + " min"}</td>
                    <td>{a.acciones}</td>
                    <td className="mono">{a.ip ?? "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

          <div className="adm-acc-cab" style={{ marginTop: 18 }}>
            <strong>Ingresos de los últimos 7 días</strong>
          </div>
          {!accesos || accesos.ingresos.length === 0 ? (
            <p className="hint">Sin ingresos registrados en el período.</p>
          ) : (
            <table className="adm-tabla">
              <thead><tr><th>Usuario</th><th>Cuándo</th><th>IP</th><th>Resultado</th></tr></thead>
              <tbody>
                {accesos.ingresos.map((g, i) => (
                  <tr key={i}>
                    <td>{g.email}</td>
                    <td>{new Date(g.cuando).toLocaleString("es-CO")}</td>
                    <td className="mono">{g.ip ?? "—"}</td>
                    <td>
                      <span className={"acc-res" + (g.resultado === "ok" ? " ok" : " no")}>
                        {g.resultado === "ok" ? "Entró"
                          : g.resultado === "pausado" ? "Rechazado: suspendido"
                          : g.resultado === "fuera_horario" ? "Rechazado: fuera de horario"
                          : "Rechazado"}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {pestana === "usuarios" && (
      <div className="adm-tabla-caja">
        <table className="adm-tabla">
          <thead>
            <tr>
              <th className="adm-c-usuario">Usuario</th>
              <th className="adm-c-modos">Acceso</th>
              <th className="adm-c-acceso">Horario</th>
              <th className="adm-c-acciones">Acciones</th>
            </tr>
          </thead>
          <tbody>
            {usuarios.map((u) => {
              const esAdmin = u.rol === "admin";
              const perso = esAdmin ? [] : esPersonalizado(casillasDe(u));
              return (
                <tr key={u.email} className={u.activo ? "" : "adm-inactivo"} data-usuario={u.email}>
                  <td>
                    {u.nombre && u.nombre !== u.email ? (
                      <>
                        <div className="adm-nombre">
                          {u.nombre}
                          {esAdmin && <span className="adm-tag-admin">Admin</span>}
                        </div>
                        <div className="adm-correo">{u.email}</div>
                      </>
                    ) : (
                      <div className="adm-correo adm-correo-solo">
                        {u.email}
                        {esAdmin && <span className="adm-tag-admin">Admin</span>}
                      </div>
                    )}
                    {!u.activo && <div className="adm-estado">Inactivo</div>}
                  </td>
                  <td>
                    <span className={"adm-linea" + (perso.length ? " adm-linea-perso" : "")} data-linea>{lineaUsuario(u)}</span>
                  </td>
                  <td>
                    {esAdmin ? (
                      <span className="adm-nota">Sin restricción</span>
                    ) : (
                      <span className="adm-acceso">
                        {u.horario === "sin_restriccion"
                          ? "Sin restricción horaria"
                          : u.horario === "extendido" ? "7:00–22:00" : "7:50–18:00"}
                        <br />
                        {u.dias === "todos" ? "Todos los días" : "Lunes a viernes"}
                      </span>
                    )}
                  </td>
                  <td className="adm-c-acciones">
                    <button className="btn-link" onClick={() => abrir(u, "editar")}>
                      {ed?.email === u.email && ed.modo === "editar" ? "Cerrar" : "Editar"}
                    </button>
                    {esAdmin ? (
                      <button className="btn-link" onClick={() => abrir(u, "hacer_consulta")}>
                        {ed?.email === u.email && ed.modo === "hacer_consulta" ? "Cerrar" : "Hacer consulta"}
                      </button>
                    ) : (
                      <button className="btn-link" onClick={() => { if (window.confirm(`¿Hacer administrador a ${u.email}? Entrará a todos los geoportales.`)) void cambiar(u, { rol: "admin" }); }}>
                        Hacer admin
                      </button>
                    )}
                    <button
                      className="btn-link"
                      onClick={() => cambiar(u, { activo: !u.activo })}
                    >
                      {u.activo ? "Desactivar" : "Activar"}
                    </button>
                    <button className="btn-link" onClick={() => nuevaClave(u)}>
                      Nueva clave
                    </button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      )}

      {ed && (
        <div className="adm-editor" data-testid="adm-editor" data-modo={ed.modo}>
          <div className="adm-editor-tit">
            {ed.modo === "hacer_consulta" ? "Hacer consulta: " : "Editando "}<span className="mono">{ed.email}</span>
          </div>
          {ed.paso === "editar" ? (
            <>
              <label className="adm-campo-et adm-campo-nombre">Nombre
                <input className="field" value={ed.nombre} data-campo="nombre" placeholder="Nombre de la persona" onChange={(e) => setEd({ ...ed, nombre: e.target.value })} />
              </label>
              {ed.nombre0 && !ed.nombre.trim() ? <p className="adm-renglon-desc">El nombre no se puede dejar vacío: se conserva «{ed.nombre0}».</p> : null}
              {rolFinal(ed) === "admin" ? (
                <p className="adm-renglon-desc adm-nota-admin">Es administrador: entra a todos los geoportales, sin horario. Para darle perfiles por geoportal, use «Hacer consulta».</p>
              ) : (
                <>
                  {ed.modo === "hacer_consulta" ? <p className="adm-resumen-extra">Hoy es administrador. Escoja a qué geoportales entra como usuario: al confirmar deja de ser administrador.</p> : null}
                  <Renglones c={ed.c} original={ed.original} disp={disp} email={ed.email} onCambio={(c) => setEd({ ...ed, c })} />
                  <Horario horario={ed.horario} dias={ed.dias} onCambio={(horario, dias) => setEd({ ...ed, horario, dias })} />
                  {avisoHorario(ed.c, ed.horario, ed.dias) ? <p className="adm-aviso-horario" role="alert">{avisoHorario(ed.c, ed.horario, ed.dias)}</p> : null}
                </>
              )}
              <div className="adm-resumen-botones">
                <button type="button" className="btn-sm" onClick={() => { setError(null); setMsg(null); setEd({ ...ed, paso: "resumen" }); }}>Revisar cambios</button>
                <button type="button" className="btn-link" onClick={() => setEd(null)}>Cancelar</button>
              </div>
            </>
          ) : (
            <PanelResumen r={resumenDe(ed)} titulo={`Cambios para ${ed.email}`} ocupado={ocupado} onConfirmar={() => void confirmarEdicion(ed)} onVolver={() => setEd({ ...ed, paso: "editar" })} />
          )}
        </div>
      )}
    </div>
  );
}
