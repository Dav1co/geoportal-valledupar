import { useEffect, useState } from "react";
import { api, type UsuarioAdmin, type EstadoPausa } from "../lib/api";

type Props = { onVolver: () => void };

const MODOS: [keyof UsuarioAdmin, string][] = [
  ["ver_explorar", "Explorar"],
  ["ver_focalizacion", "Focalización"],
  ["ver_comercial", "Comercial"],
  ["ver_rutas", "Rutas"],
];

type Borrador = {
  explorar: boolean;
  focalizacion: boolean;
  comercial: boolean;
  rutas: boolean;
  horario: string;
  dias: string;
};

function aBorrador(u: UsuarioAdmin): Borrador {
  return {
    explorar: u.ver_explorar === true,
    focalizacion: u.ver_focalizacion === true,
    comercial: u.ver_comercial === true,
    rutas: u.ver_rutas === true,
    horario: u.horario ?? "laboral",
    dias: u.dias ?? "habiles",
  };
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
      const r = await api.admin.guardar({
        email,
        nombre: nombre || undefined,
        rol,
        activo: true,
        password: clave,
      });
      setMsg(
        r.auth === "creado"
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
    setBorrador(aBorrador(u));
  }

  async function guardarPermisos(u: UsuarioAdmin) {
    if (!borrador) return;
    setSalvando(true);
    setError(null);
    setMsg(null);
    try {
      await api.admin.permisos({ email: u.email, ...borrador });
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
            Volver al mapa
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
          </select>
          <button className="btn-sm" onClick={agregar} disabled={guardando}>
            {guardando ? "…" : "Guardar"}
          </button>
        </div>
      )}

      {error && <p className="error">{error}</p>}
      {msg && <p className="hint">{msg}</p>}
      {cargando && <p className="hint">Cargando…</p>}

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
              return (
                <tr key={u.email} className={u.activo ? "" : "adm-inactivo"}>
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
                    {esAdmin ? (
                      <span className="adm-nota">Todos los modos</span>
                    ) : permitidos.length === 0 ? (
                      <span className="adm-nota">Sin acceso</span>
                    ) : (
                      <div className="adm-etiquetas">
                        {permitidos.map(([c, et]) => (
                          <span key={String(c)} className="adm-etiqueta">
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
                        {u.horario === "extendido" ? "7:00–22:00" : "7:50–18:00"}
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

      {editando && borrador && (
        <div className="adm-editor">
          <div className="adm-editor-tit">
            Editando <span className="mono">{editando}</span>
          </div>
          <div className="adm-editor-campos">
            <div>
              <div className="adm-editor-et">Modos</div>
              <div className="adm-editor-checks">
                {(
                  [
                    ["explorar", "Explorar"],
                    ["focalizacion", "Focalización"],
                    ["comercial", "Comercial"],
                    ["rutas", "Rutas"],
                  ] as [keyof Borrador, string][]
                ).map(([campo, et]) => (
                  <label key={String(campo)} className="adm-check">
                    <input
                      type="checkbox"
                      checked={borrador[campo] === true}
                      onChange={(e) =>
                        setBorrador({ ...borrador, [campo]: e.target.checked })
                      }
                    />
                    {et}
                  </label>
                ))}
              </div>
            </div>
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
