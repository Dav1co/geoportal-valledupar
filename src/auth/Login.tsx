import { useState } from "react";
import { supabase } from "../lib/supabase";
import { useMotivoRechazo } from "./useSession";

const DOMINIO = "@emdupar.gov.co";

// Dominios aceptados por el login.
// TODO: quitar "@gmail.com" cuando termine la prueba con el correo personal.
const DOMINIOS_PERMITIDOS = [DOMINIO, "@gmail.com"];

// Si el usuario escribe solo "ddiazrodriguez", lo completa a
// "ddiazrodriguez@emdupar.gov.co". Si ya escribió un @, lo respeta.
function normalizarCorreo(valor: string): string {
  const t = valor.trim().toLowerCase();
  if (!t) return "";
  return t.includes("@") ? t : t + DOMINIO;
}

export function Login() {
  const [email, setEmail] = useState("");
  const [clave, setClave] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [entrando, setEntrando] = useState(false);
  const motivo = useMotivoRechazo();

  async function ingresar() {
    setError(null);
    const correo = normalizarCorreo(email);

    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(correo)) {
      setError("Escribe tu usuario o tu correo completo.");
      return;
    }
    if (!DOMINIOS_PERMITIDOS.some((d) => correo.endsWith(d))) {
      setError("Solo se permite el correo institucional (" + DOMINIO + ").");
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
    if (error) {
      setError("Correo o contraseña incorrectos.");
      return;
    }
    // Si la sesión es válida pero el acceso está restringido (horario,
    // usuario inactivo), useSession la rechaza y deja el motivo aquí.
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
          Usuario o correo institucional
        </label>
        <input
          id="email"
          className="field mono"
          type="text"
          inputMode="email"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          placeholder="ddiazrodriguez"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          onKeyDown={(e) =>
            e.key === "Enter" && document.getElementById("clave")?.focus()
          }
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

        {(error || motivo) && <p className="error">{error ?? motivo}</p>}
      </div>
      <p className="login-foot">Acceso restringido · uso institucional</p>
    </div>
  );
}
