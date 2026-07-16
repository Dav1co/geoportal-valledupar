import { useEffect, useState } from "react";
import { api, type UsuarioAdmin } from "../lib/api";

type Props = { onVolver: () => void };

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
  }, []);

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
      await cargar();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Error guardando.");
    } finally {
      setGuardando(false);
    }
  }

  async function cambiar(u: UsuarioAdmin, cambios: Partial<{ rol: string; activo: boolean }>) {
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

  return (
    <div className="panel" style={{ maxWidth: 720, margin: "24px auto", width: "100%" }}>
      <div className="panel-head">
        <span className="panel-title">Administración de usuarios</span>
        <button className="btn-link" onClick={onVolver}>Volver al mapa</button>
      </div>

      <div style={{ display: "grid", gap: 8, marginBottom: 16 }}>
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
          placeholder="Clave inicial (mín. 8 caracteres)"
          type="text"
          value={clave}
          onChange={(e) => setClave(e.target.value)}
        />
        <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
          <select className="field" value={rol} onChange={(e) => setRol(e.target.value)} style={{ flex: 1 }}>
            <option value="consulta">Consulta</option>
            <option value="admin">Administrador</option>
          </select>
          <button className="btn-sm" onClick={agregar} disabled={guardando}>
            {guardando ? "…" : "Guardar usuario"}
          </button>
        </div>
      </div>

      {error && <p className="error">{error}</p>}
      {msg && <p className="hint">{msg}</p>}
      {cargando && <p className="hint">Cargando…</p>}

      <ul className="resultados">
        {usuarios.map((u) => (
          <li key={u.email} style={{ opacity: u.activo ? 1 : 0.5 }}>
            <div
              className="resultado"
              style={{ display: "flex", flexWrap: "wrap", gap: 8, alignItems: "center", cursor: "default" }}
            >
              <span style={{ flex: "1 1 220px" }}>
                <span className="mono">{u.email}</span>
                {u.nombre ? ` · ${u.nombre}` : ""}
              </span>
              <span className="rol-tag">
                {u.rol === "admin" ? "Administrador" : "Consulta"}
              </span>
              <span style={{ display: "flex", gap: 6 }}>
                <button
                  className="btn-link"
                  onClick={() => cambiar(u, { rol: u.rol === "admin" ? "consulta" : "admin" })}
                >
                  {u.rol === "admin" ? "Hacer consulta" : "Hacer admin"}
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
              </span>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}
