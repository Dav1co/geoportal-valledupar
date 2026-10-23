import { useEffect, useRef, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "../lib/supabase";
import { api, ErrorApi, type PerfilResp } from "../lib/api";

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
  const [perfil, setPerfil] = useState<PerfilResp | null>(null);
  const [cargando, setCargando] = useState(true);
  // Fallo PASAJERO al pedir el perfil (sin red, sin tiempo, servidor caído): no se cierra la sesión; se ofrece reintentar. Un rechazo (401, 403 u otro 4xx) sí cierra la sesión.
  const [errorPerfil, setErrorPerfil] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);
  const perfilRef = useRef<PerfilResp | null>(null);

  useEffect(() => {
    let vivo = true;

    // Una sesión de Supabase no basta: el usuario puede estar fuera de
    // horario o sin autorización. Se confirma contra el servidor antes
    // de dejarlo entrar.
    async function validar(s: Session | null) {
      if (!s) {
        if (vivo) {
          setSession(null);
          perfilRef.current = null;
          setPerfil(null);
          setErrorPerfil(null);
          setCargando(false);
        }
        return;
      }
      try {
        // La respuesta del perfil ya no se descarta: App la usa para decidir qué ve el usuario (una sola petición).
        const p = await api.admin.perfil();
        if (!vivo) return;
        setMotivoRechazo(null);
        // Mismo contenido = mismo objeto: las revalidaciones (cambio de token, foco de la pestaña) no provocan renders ni mueven al usuario de pantalla.
        setPerfil((previo) => {
          const nuevo = previo && JSON.stringify(previo) === JSON.stringify(p) ? previo : p;
          perfilRef.current = nuevo;
          return nuevo;
        });
        setErrorPerfil(null);
        setSession(s);
      } catch (e) {
        if (e instanceof ErrorApi && (e.status === 0 || e.status >= 500)) {
          if (!vivo) return;
          // Con perfil ya cargado, una revalidación fallida por red no saca al usuario de lo que está haciendo.
          if (perfilRef.current === null) {
            setSession(s);
            setErrorPerfil(e.message);
          }
          return;
        }
        const msg =
          e instanceof Error && e.message
            ? e.message
            : "No tienes acceso al geoportal en este momento.";
        setMotivoRechazo(msg);
        await supabase.auth.signOut();
        if (!vivo) return;
        setSession(null);
        perfilRef.current = null;
        setPerfil(null);
        setErrorPerfil(null);
      } finally {
        if (vivo) setCargando(false);
      }
    }

    supabase.auth.getSession().then(({ data }) => validar(data.session));

    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => {
      if (!s) {
        if (vivo) {
          setSession(null);
          perfilRef.current = null;
          setPerfil(null);
          setErrorPerfil(null);
        }
        return;
      }
      validar(s);
    });

    return () => {
      vivo = false;
      sub.subscription.unsubscribe();
    };
  }, [intento]);

  /** Vuelve a pedir el perfil (botón «Reintentar»). */
  const reintentar = () => {
    setErrorPerfil(null);
    setIntento((i) => i + 1);
  };

  return { session, perfil, cargando, errorPerfil, reintentar };
}
