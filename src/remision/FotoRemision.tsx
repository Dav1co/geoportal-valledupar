import { useEffect, useState } from "react";
import "../tecnica/tokens.css";
import "./remision.css";
import { supabase } from "../lib/supabase";
import { ErrorTec } from "../tecnica/apiTecnica";
import { fotoRemision } from "../tecnica/reportes/apiReportes";

// La foto de una remisión de químicos (contrato del Code A, §2.5): pide `reporte_remision_foto` con el número del movimiento y muestra la foto con la URL
// firmada de 60 s. Solo supervisor de planta y administrador (lo decide el servidor, que además deja la consulta en la auditoría). Sin sesión, lo dice.
type Estado = { fase: "cargando" } | { fase: "foto"; url: string; vence: number } | { fase: "aviso"; texto: string; sesion?: boolean };

export function FotoRemision() {
  const movimiento = new URLSearchParams(window.location.search).get("movimiento") ?? "";
  const valido = /^\d{1,15}$/.test(movimiento);
  const [e, setE] = useState<Estado>({ fase: "cargando" });
  const [vez, setVez] = useState(0);
  useEffect(() => {
    if (!valido) { setE({ fase: "aviso", texto: "El enlace no trae un número de movimiento válido. Vuelva a abrirlo desde el Excel." }); return; }
    let vivo = true; setE({ fase: "cargando" });
    (async () => {
      const { data } = await supabase.auth.getSession();
      if (!data.session) { if (vivo) setE({ fase: "aviso", sesion: true, texto: "Para ver la foto, inicie sesión en el geoportal en este navegador y vuelva a abrir el enlace." }); return; }
      try { const r = await fotoRemision(movimiento); if (vivo) setE({ fase: "foto", url: r.url, vence: r.vence_en_s }); }
      catch (x) {
        if (!vivo) return;
        const t = x instanceof ErrorTec ? (x.tipo === "permiso" ? "Solo el supervisor de planta o el administrador ven la foto de la remisión." : x.tipo === "sesion" ? "Su sesión venció. Inicie sesión en el geoportal y vuelva a abrir el enlace." : x.message)
          : "No se pudo cargar la foto.";
        setE({ fase: "aviso", texto: t, sesion: x instanceof ErrorTec && x.tipo === "sesion" });
      }
    })();
    return () => { vivo = false; };
  }, [movimiento, valido, vez]);
  return (
    <div className="rem tec-modo-plantas">
      <header className="rem-cab"><div className="rem-ancho"><h1>Foto de la remisión</h1>{valido ? <p>Movimiento {movimiento} · Entrada de químicos</p> : null}</div></header>
      <main className="rem-ancho rem-cuerpo">
        {e.fase === "cargando" ? <p className="rem-ayuda" role="status">Cargando la foto…</p> : null}
        {e.fase === "aviso" ? (
          <div className="rem-aviso" role="alert"><p>{e.texto}</p>
            {e.sesion ? <a className="rem-boton" href="./">Ir al geoportal</a> : valido ? <button type="button" className="rem-boton-sec" onClick={() => setVez((v) => v + 1)}>Reintentar</button> : null}</div>
        ) : null}
        {e.fase === "foto" ? <>
          <img className="rem-foto" src={e.url} alt={`Foto de la remisión del movimiento ${movimiento}`}
            onError={() => setE({ fase: "aviso", texto: "La foto no se pudo mostrar (el enlace firmado pudo vencer). Toque «Reintentar»." })} />
          <p className="rem-ayuda">El acceso a la foto dura {e.vence} segundos y queda registrado. Si se vence, vuelva a abrir el enlace desde el Excel o toque «Reintentar».</p>
          <div className="rem-botones"><a className="rem-boton" href={e.url} target="_blank" rel="noopener noreferrer">Abrir en tamaño completo</a>
            <button type="button" className="rem-boton-sec" onClick={() => setVez((v) => v + 1)}>Reintentar</button></div>
        </> : null}
      </main>
    </div>
  );
}
