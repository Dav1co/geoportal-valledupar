-- =====================================================================
-- PDF DE «REPORTAR ANOMALÍA» (Code A, 27-nov) · 90 — REVERSA
-- Quita las 8 funciones de este paquete; la huella de campo vuelve a {{HUELLA_CAMPO}}. NADA SE BORRA: campo.reporte_pdf (con sus filas) y los PDF del bucket
-- se conservan. Sin estas funciones, la Edge responde que la ruta no está disponible y la pantalla lo dice; no se rompe nada más.
-- =====================================================================
do $rev$
declare r record; v_n bigint;
begin
  for r in select * from (values {{MD5_NUEVAS}}) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la de este paquete (sin aplicar o cambiada después): la reversa no la pisa; deténgase y avise', r.f;
    end if;
  end loop;
  select count(*) into v_n from campo.reporte_pdf;
  raise notice 'Reversa del PDF de Reportar anomalía: % versiones de PDF quedan en campo.reporte_pdf', v_n;
end $rev$;
-- DROP (por qué y alcance): las 8 funciones las creó este paquete y nada publicado las usa. Alcance: SOLO esas 8 firmas; no toca tablas ni datos.
drop function public.geoportal_campo_ran_obtener(text, uuid, text);
drop function public.geoportal_campo_ran_registrar(text, uuid, text, text, integer, integer, text);
drop function public.geoportal_campo_ran_datos(text, uuid, text);
drop function campo.f_ran_mapa(numeric, numeric, numeric, numeric);
drop function campo.f_ran_destino(uuid, text);
drop function campo.f_ran_contenido(uuid);
drop function campo.f_ran_persona(text);
drop function campo.f_ran_autorizar(text, uuid);
