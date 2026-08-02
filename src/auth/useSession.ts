import { useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "../lib/supabase";
import { api } from "../lib/api";

// Motivo por el que se rechazó una sesión válida (fuera de horario,
// usuario no autorizado). El Login lo muestra bajo el formulario.
let motivoRechazo: string | null = null;
const oyentes = new Set<(m: string | null) => void>();

export function setMotivoRechazo(m: string | null) {
  motivoRechazo = m;
  oyentes.forEach((f) => f(m));
}

export function useMotivoRechazo() {
  const [m, setM] = useState<string | null>(motivoRechazo);
  useEffect(() => {
    oyentes.add(setM);
    return () => {
      oyentes.delete(setM);
    };
  }, []);
  return m;
}

export function useSession() {
  const [session, setSession] = useState<Session | null>(null);
  const [cargando, setCargando] = useState(true);

  useEffect(() => {
    let vivo = true;

    // Una sesión de Supabase no basta: el usuario puede estar fuera de
    // horario o sin autorización. Se confirma contra el servidor antes
    // de dejarlo entrar.
    async function validar(s: Session | null) {
      if (!s) {
        if (vivo) {
          setSession(null);
          setCargando(false);
        }
        return;
      }
      try {
        await api.admin.perfil();
        if (!vivo) return;
        setMotivoRechazo(null);
        setSession(s);
      } catch (e) {
        const msg =
          e instanceof Error && e.message
            ? e.message
            : "No tienes acceso al geoportal en este momento.";
        setMotivoRechazo(msg);
        await supabase.auth.signOut();
        if (!vivo) return;
        setSession(null);
      } finally {
        if (vivo) setCargando(false);
      }
    }

    supabase.auth.getSession().then(({ data }) => validar(data.session));

    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => {
      if (!s) {
        if (vivo) setSession(null);
        return;
      }
      validar(s);
    });

    return () => {
      vivo = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  return { session, cargando };
}
