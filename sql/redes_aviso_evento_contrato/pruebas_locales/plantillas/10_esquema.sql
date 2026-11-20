-- =====================================================================
-- TÉCNICA · FASE 1 · AVISO DE EVENTO POR CONTRATO (primera regla de choque) · 10 — GUARDIA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code A). Generado por pruebas_locales/generar.py.
-- Fuente: encargo de David del 19-nov: dado un contrato, decir si HOY está dentro de un evento de suspensión abierto. Solo avisa; no bloquea nada.
-- · Presupone «Mis reportes» publicado: huella del conjunto de funciones de redes {{MD5_BASE}}.
-- · SOLO AGREGA 3 funciones de lectura (1 RPC). No reemplaza ninguna, no crea tablas ni índices y no cambia quién declara o ve los eventos.
-- · La regla de «a quién afecta» es la del Corte 15 (redes.f_evento_contratos): el contrato está en el evento si el tramo al que está amarrado
--   (redes.contrato_tramo) toca la zona del evento, o si el evento es de toda la ciudad. La zona de un evento por planta es la de sus sectores al declararlo.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_redes_evento_contrato(text,text)') is not null or to_regprocedure('redes.f_eventos_del_contrato(text)') is not null
     or to_regprocedure('redes.f_evento_contrato_acceso(text)') is not null then
    raise exception 'El aviso de evento por contrato ya está aplicado: deténgase y avise';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_BASE}}' then
    raise exception 'Las funciones de redes no son las de «Mis reportes» publicado (huella {{MD5_BASE}}): deténgase y avise';
  end if;
  if to_regclass('redes.eventos_suspension') is null or to_regclass('redes.v_evento_suspension') is null or to_regclass('redes.contrato_tramo') is null
     or to_regprocedure('redes.f_eventos_abiertos()') is null or to_regprocedure('redes.f_evento_franja(text,timestamptz,text,timestamptz)') is null
     or to_regprocedure('public.geoportal_puede(text,text)') is null or to_regprocedure('public.geoportal_estado_acceso(text)') is null then
    raise exception 'Faltan tablas o funciones del Corte 15 o del acceso: deténgase y avise';
  end if;
end $$;
