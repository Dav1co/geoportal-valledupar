import { useState } from "react";
import { supabase } from "../lib/supabase";

export function Login() {
  const [email, setEmail] = useState("");
  const [clave, setClave] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [entrando, setEntrando] = useState(false);

  async function ingresar() {
    setError(null);
    const correo = email.trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(correo)) {
      setError("Escribe un correo válido.");
      return;
    }
    if (!clave) {
      setError("Escribe tu contraseña.");
      return;
    }
    setEntrando(true);
    const { error } = await supabase.auth.signInWithPassword({
      email: correo,
      password: clave,
    });
    setEntrando(false);
    if (error) setError("Correo o contraseña incorrectos.");
  }

  return (
    <div className="login">
      <div className="login-panel">
        <div className="brand">
          <span className="brand-mark">◆</span>
          <div>
            <div className="brand-name">Geoportal Catastral</div>
            <div className="brand-sub">EMDUPAR S.A. E.S.P.</div>
          </div>
        </div>

        <label className="field-label" htmlFor="email">
          Correo institucional
        </label>
        <input
          id="email"
          className="field mono"
          type="email"
          placeholder="nombre@emdupar.gov.co"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && document.getElementById("clave")?.focus()}
          autoComplete="username"
        />

        <label className="field-label" htmlFor="clave" style={{ marginTop: 12 }}>
          Contraseña
        </label>
        <input
          id="clave"
          className="field"
          type="password"
          placeholder="••••••••"
          value={clave}
          onChange={(e) => setClave(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && ingresar()}
          autoComplete="current-password"
        />

        <button className="btn" onClick={ingresar} disabled={entrando}>
          {entrando ? "Ingresando…" : "Ingresar"}
        </button>

        {error && <p className="error">{error}</p>}
      </div>
      <p className="login-foot">Acceso restringido · uso institucional</p>
    </div>
  );
}
