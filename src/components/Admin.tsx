import { useEffect, useMemo, useState } from "react";
import { api, type UsuarioAdmin, type EstadoPausa, type Accesos } from "../lib/api";
import "./admin-tecnica.css";

type Props = { onVolver: () => void };

const MODOS: [keyof UsuarioAdmin, string][] = [
  ["ver_explorar", "Explorar"],
  ["ver_focalizacion", "Focalización"],
  ["ver_comercial", "Comercial"],
  ["ver_rutas", "Rutas"],
  ["ver_dashboard", "Dashboard"],
];

// Área técnica (fase 2). Todo lo técnico se muestra SOLO si el servidor ya trae esas columnas (paquete SQL aplicado); si no, Administración es idéntica a la de siempre.
const MODOS_TECNICOS: [keyof UsuarioAdmin, string][] = [
  ["ver_registro_tecnico", "Registro técnico"],
  ["ver_dashboard_tecnico", "Dashboard técnica"],
];
type PerfilTecnico = "operador" | "supervisor";
const PERFILES_TECNICOS: Record<PerfilTecnico, { nombre: string; registro: boolean; dashboard: boolean }> = {
  operador: { nombre: "Operador técnico", registro: true, dashboard: false },
  supervisor: { nombre: "Supervisor técnico", registro: true, dashboard: true },
};
const NOMBRES_PERFIL: Record<string, string> = { operador: "Operador técnico", supervisor: "Supervisor técnico" };

/** Perfil técnico de un usuario no administrador: solo técnico (sin ningún modo comercial) con Registro técnico, con o sin Dashboard técnica. */
function perfilTecnicoDe(u: UsuarioAdmin): PerfilTecnico | null {
  if (u.rol === "admin" || u.ver_registro_tecnico !== true) return null;
  if (MODOS.some(([c]) => u[c] === true)) return null;
  return u.ver_dashboard_tecnico === true ? "supervisor" : "operador";
}

type Borrador = {
  explorar: boolean;
  focalizacion: boolean;
  comercial: boolean;
  rutas: boolean;
  dashboard: boolean;
  horario: string;
  dias: string;
  registro_tecnico?: boolean;
  dashboard_tecnico?: boolean;
};

function aBorrador(u: UsuarioAdmin, conTecnica: boolean): Borrador {
  return {
    explorar: u.ver_explorar === true,
    focalizacion: u.ver_focalizacion === true,
    comercial: u.ver_comercial === true,
    rutas: u.ver_rutas === true,
    dashboard: u.ver_dashboard === true,
    horario: u.horario ?? "laboral",
    dias: u.dias ?? "habiles",
    ...(conTecnica ? { registro_tecnico: u.ver_registro_tecnico === true, dashboard_tecnico: u.ver_dashboard_tecnico === true } : {}),
  };
}

const CAMPOS_COMERCIAL: [keyof Borrador, string][] = [
  ["explorar", "Explorar"],
  ["focalizacion", "Focalización"],
  ["comercial", "Comercial"],
  ["rutas", "Rutas"],
  ["dashboard", "Dashboard"],
];
const CAMPOS_TECNICA: [keyof Borrador, string][] = [
  ["registro_tecnico", "Registro técnico"],
  ["dashboard_tecnico", "Dashboard técnica"],
];

/** Bloque de un área con interruptor general: encendido si algún modo del bloque lo está. Al apagarlo apaga todos los modos del bloque; al encenderlo enciende `alEncender`
 *  (por defecto todos; en Comercial solo Explorar, el modo básico). */
function BloquePermisos({ titulo, campos, borrador, onCambio, tecnico, alEncender, children }: {
  titulo: string; campos: [keyof Borrador, string][]; borrador: Borrador; onCambio: (c: Partial<Borrador>) => void; tecnico?: boolean; alEncender?: (keyof Borrador)[]; children?: React.ReactNode;
}) {
  const activo = campos.some(([c]) => borrador[c] === true);
  const todos = (v: boolean) => Object.fromEntries(campos.map(([c]) => [c, v && (!alEncender || alEncender.includes(c))])) as Partial<Borrador>;
  return (
    <section className={`adm-bloque${tecnico ? " adm-bloque-tec" : ""}${activo ? " on" : ""}`} aria-label={titulo}>
      <div className="adm-bloque-cab">
        <span className="adm-bloque-tit">{titulo}</span>
        <button type="button" role="switch" aria-checked={activo} aria-label={`${titulo}: interruptor general`} className="adm-sw" onClick={() => onCambio(todos(!activo))}>
          <span className="adm-sw-bola" />
        </button>
      </div>
      <div className="adm-editor-checks">
        {campos.map(([campo, et]) => (
          <label key={String(campo)} className="adm-check">
            <input type="checkbox" checked={borrador[campo] === true} onChange={(e) => onCambio({ [campo]: e.target.checked })} />
            {et}
          </label>
        ))}
      </div>
      {children}
    </section>
  );
}

export function Admin({ onVolver }: Props) {
  const [usuarios, setUsuarios] = useState<UsuarioAdmin[]>([]);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  // Formulario de nuevo usuario
  const [email, setEmail] = useState("");
  const [nombre, setNombre] = useState("");
  const [clave, setClave] = useState("");
  const [rol, setRol] = useState("consulta");
  const [guardando, setGuardando] = useState(false);
  const [abierto, setAbierto] = useState(false);

  // Edición de permisos
  const [editando, setEditando] = useState<string | null>(null);
  const [borrador, setBorrador] = useState<Borrador | null>(null);
  const [salvando, setSalvando] = useState(false);
  const [pausa, setPausa] = useState<EstadoPausa | null>(null);
  const [cambiandoPausa, setCambiandoPausa] = useState(false);
  const [pestana, setPestana] = useState<"usuarios" | "accesos">("usuarios");
  const [accesos, setAccesos] = useState<Accesos | null>(null);
  const [cargandoAcc, setCargandoAcc] = useState(false);
  // ¿El servidor ya trae los permisos técnicos? Si no, no se muestra nada técnico.
  const conTecnica = useMemo(() => usuarios.some((u) => typeof u.ver_registro_tecnico === "boolean"), [usuarios]);

  async function cargar() {
    setCargando(true);
    setError(null);
    try {
      const { usuarios } = await api.admin.listar();
      setUsuarios(usuarios);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error cargando usuarios.");
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

  // Defensa contra una publicación a medias: si la Edge o la base todavía no aplican los permisos técnicos, el servidor los ignoraría en silencio.
  // Tras guardar se vuelve a leer el usuario y se comprueba que quedó como se pidió.
  async function verificarTecnico(correo: string, registro: boolean, dashboard: boolean): Promise<boolean> {
    const { usuarios: lista } = await api.admin.listar();
    const u = lista.find((x) => x.email === correo.toLowerCase());
    const ok = !!u && (u.ver_registro_tecnico === true) === registro && (u.ver_dashboard_tecnico === true) === dashboard;
    if (!ok) setError("El servidor no aplicó los permisos técnicos de " + correo + ". Falta aplicar el paquete técnico (base y Edge) antes de usar esta opción.");
    setUsuarios(lista);
    return ok;
  }

  async function agregar() {
    setMsg(null);
    if (!email.includes("@")) {
      setError("Escribe un correo válido.");
      return;
    }
    if (clave.length < 8) {
      setError("La clave debe tener al menos 8 caracteres.");
      return;
    }
    setGuardando(true);
    setError(null);
    try {
      const perfilTec = rol === "operador" || rol === "supervisor" ? (rol as PerfilTecnico) : undefined;
      const r = await api.admin.guardar({
        email,
        nombre: nombre || undefined,
        rol: perfilTec ? "consulta" : rol,
        activo: true,
        password: clave,
        ...(perfilTec ? { perfil_tecnico: perfilTec } : {}),
      });
      if (perfilTec && !(await verificarTecnico(email, PERFILES_TECNICOS[perfilTec].registro, PERFILES_TECNICOS[perfilTec].dashboard))) return;
      setMsg(
        perfilTec
          ? `Usuario ${email} ${r.auth === "creado" ? "creado" : "actualizado"} como ${PERFILES_TECNICOS[perfilTec].nombre}: solo ${perfilTec === "operador" ? "Registro técnico" : "Registro técnico y Dashboard técnica"}, con los modos comerciales apagados.`
          : r.auth === "creado"
            ? `Usuario ${email} creado con su clave.`
            : `Usuario ${email} actualizado (clave nueva).`,
      );
      setEmail("");
      setNombre("");
      setClave("");
      setRol("consulta");
      setAbierto(false);
      await cargar();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error guardando.");
    } finally {
      setGuardando(false);
    }
  }

  function abrirEdicion(u: UsuarioAdmin) {
    setError(null);
    setMsg(null);
    if (editando === u.email) {
      setEditando(null);
      setBorrador(null);
      return;
    }
    setEditando(u.email);
    setBorrador(aBorrador(u, conTecnica));
  }

  async function guardarPermisos(u: UsuarioAdmin) {
    if (!borrador) return;
    setSalvando(true);
    setError(null);
    setMsg(null);
    try {
      await api.admin.permisos({ email: u.email, ...borrador });
      if (conTecnica && !(await verificarTecnico(u.email, borrador.registro_tecnico === true, borrador.dashboard_tecnico === true))) return;
      setMsg(`Permisos actualizados para ${u.email}.`);
      setEditando(null);
      setBorrador(null);
      await cargar();
    } catch (e) {
      setError(e instanceof Error ? e.message : "No se pudo guardar.");
    } finally {
      setSalvando(false);
    }
  }

  async function cambiar(
    u: UsuarioAdmin,
    cambios: Partial<{ rol: string; activo: boolean }>,
  ) {
    setMsg(null);
    setError(null);
    try {
      await api.admin.guardar({
        email: u.email,
        rol: cambios.rol ?? u.rol,
        activo: cambios.activo ?? u.activo,
      });
      await cargar();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error guardando.");
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
      .catch((e) => setError(e instanceof Error ? e.message : "Error."));
  }

  const totalAdmin = usuarios.filter((u) => u.rol === "admin").length;

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
            {usuarios.length} usuarios · {totalAdmin} administradores
          </p>
        </div>
        <div className="adm-cab-acciones">
          <button className="btn-sm" onClick={() => setAbierto((v) => !v)}>
            {abierto ? "Cancelar" : "Nuevo usuario"}
          </button>
          <button className="btn-link" onClick={onVolver}>
            Volver
          </button>
        </div>
      </div>

      {abierto && (
        <div className="adm-nuevo">
          <input
            className="field"
            placeholder="correo@emdupar.gov.co"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
          <input
            className="field"
            placeholder="Nombre (opcional)"
            value={nombre}
            onChange={(e) => setNombre(e.target.value)}
          />
          <input
            className="field"
            placeholder="Clave inicial (mín. 8)"
            type="text"
            value={clave}
            onChange={(e) => setClave(e.target.value)}
          />
          <select
            className="field"
            value={rol}
            onChange={(e) => setRol(e.target.value)}
          >
            <option value="consulta">Consulta</option>
            <option value="admin">Administrador</option>
            {conTecnica && <option value="operador">Operador técnico (solo Registro técnico)</option>}
            {conTecnica && <option value="supervisor">Supervisor técnico (Registro técnico y Dashboard técnica)</option>}
          </select>
          <button className="btn-sm" onClick={agregar} disabled={guardando}>
            {guardando ? "…" : "Guardar"}
          </button>
        </div>
      )}

      {error && <p className="error">{error}</p>}
      {msg && <p className="hint">{msg}</p>}
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
              <th className="adm-c-modos">Modos</th>
              <th className="adm-c-acceso">Acceso</th>
              <th className="adm-c-acciones">Acciones</th>
            </tr>
          </thead>
          <tbody>
            {usuarios.map((u) => {
              const esAdmin = u.rol === "admin";
              const permitidos = MODOS.filter(([c]) => u[c] === true);
              const tecnicos = MODOS_TECNICOS.filter(([c]) => u[c] === true);
              const perfilTec = perfilTecnicoDe(u);
              return (
                <tr key={u.email} className={u.activo ? "" : "adm-inactivo"}>
                  <td>
                    {u.nombre && u.nombre !== u.email ? (
                      <>
                        <div className="adm-nombre">
                          {u.nombre}
                          {esAdmin && <span className="adm-tag-admin">Admin</span>}
                          {perfilTec && <span className="adm-tag-perfil">{NOMBRES_PERFIL[perfilTec]}</span>}
                        </div>
                        <div className="adm-correo">{u.email}</div>
                      </>
                    ) : (
                      <div className="adm-correo adm-correo-solo">
                        {u.email}
                        {esAdmin && <span className="adm-tag-admin">Admin</span>}
                        {perfilTec && <span className="adm-tag-perfil">{NOMBRES_PERFIL[perfilTec]}</span>}
                      </div>
                    )}
                    {!u.activo && <div className="adm-estado">Inactivo</div>}
                  </td>
                  <td>
                    {esAdmin ? (
                      <span className="adm-nota">Todos los modos</span>
                    ) : permitidos.length === 0 && tecnicos.length === 0 ? (
                      <span className="adm-nota">Sin acceso</span>
                    ) : (
                      <div className="adm-etiquetas">
                        {permitidos.map(([c, et]) => (
                          <span key={String(c)} className="adm-etiqueta">
                            {et}
                          </span>
                        ))}
                        {tecnicos.map(([c, et]) => (
                          <span key={String(c)} className="adm-etiqueta adm-etiqueta-tec">
                            {et}
                          </span>
                        ))}
                      </div>
                    )}
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
                    <button className="btn-link" onClick={() => abrirEdicion(u)}>
                      {editando === u.email ? "Cerrar" : "Editar"}
                    </button>
                    <button
                      className="btn-link"
                      onClick={() =>
                        cambiar(u, { rol: esAdmin ? "consulta" : "admin" })
                      }
                    >
                      {esAdmin ? "Hacer consulta" : "Hacer admin"}
                    </button>
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

      {editando && borrador && (
        <div className="adm-editor">
          <div className="adm-editor-tit">
            Editando <span className="mono">{editando}</span>
          </div>
          <div className="adm-editor-campos">
            <div className="adm-bloques">
              <BloquePermisos
                titulo="Geoportal Comercial"
                campos={CAMPOS_COMERCIAL}
                alEncender={["explorar"]}
                borrador={borrador}
                onCambio={(c) => setBorrador({ ...borrador, ...c })}
              />
              {conTecnica && (
                <BloquePermisos
                  titulo="Geoportal Técnica"
                  tecnico
                  campos={CAMPOS_TECNICA}
                  borrador={borrador}
                  onCambio={(c) => setBorrador({ ...borrador, ...c })}
                >
                  <select
                    className="adm-sel adm-perfil-rapido"
                    value=""
                    aria-label="Aplicar un perfil técnico"
                    onChange={(e) => {
                      const p = e.target.value as PerfilTecnico | "";
                      if (!p) return;
                      setBorrador({ explorar: false, focalizacion: false, comercial: false, rutas: false, dashboard: false, horario: "sin_restriccion", dias: "todos",
                                    registro_tecnico: PERFILES_TECNICOS[p].registro, dashboard_tecnico: PERFILES_TECNICOS[p].dashboard });
                    }}
                  >
                    <option value="">Aplicar perfil…</option>
                    <option value="operador">Operador técnico</option>
                    <option value="supervisor">Supervisor técnico</option>
                  </select>
                  {(borrador.registro_tecnico || borrador.dashboard_tecnico) && (
                    <p className="adm-aviso-tec">
                      {CAMPOS_COMERCIAL.some(([c]) => borrador[c] === true)
                        ? "Con modos comerciales y técnicos verá las dos áreas y la ventana de entrada."
                        : "Solo verá el área técnica: entra directo, sin mapa ni datos comerciales."}
                      {(borrador.horario !== "sin_restriccion" || borrador.dias !== "todos") &&
                        " El área técnica opera todos los días a cualquier hora: con este horario el acceso se corta fuera de él."}
                    </p>
                  )}
                </BloquePermisos>
              )}
            </div>
            {![...CAMPOS_COMERCIAL, ...(conTecnica ? CAMPOS_TECNICA : [])].some(([c]) => borrador[c] === true) && (
              <p className="adm-aviso-tec">Sin ningún modo asignado: al ingresar verá «Sin módulos asignados».</p>
            )}
            <div>
              <div className="adm-editor-et">Horario</div>
              <select
                className="adm-sel"
                value={borrador.horario}
                onChange={(e) =>
                  setBorrador({ ...borrador, horario: e.target.value })
                }
              >
                <option value="laboral">Laboral</option>
                <option value="extendido">Extendido</option>
                <option value="sin_restriccion">Sin restricción horaria</option>
              </select>
            </div>
            <div>
              <div className="adm-editor-et">Días</div>
              <select
                className="adm-sel"
                value={borrador.dias}
                onChange={(e) => setBorrador({ ...borrador, dias: e.target.value })}
              >
                <option value="habiles">Lunes a viernes</option>
                <option value="todos">Todos los días</option>
              </select>
            </div>
            <button
              className="btn-sm"
              disabled={salvando}
              onClick={() => {
                const u = usuarios.find((x) => x.email === editando);
                if (u) guardarPermisos(u);
              }}
            >
              {salvando ? "…" : "Guardar cambios"}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
