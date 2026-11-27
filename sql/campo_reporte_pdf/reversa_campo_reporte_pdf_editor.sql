-- [Code A] PDF DE «REPORTAR ANOMALÍA» (27-nov) · REVERSA (versión para el editor SQL de Supabase; generado por pruebas_locales/generar.py, no editar a mano)
begin;
-- =====================================================================
-- PDF DE «REPORTAR ANOMALÍA» (Code A, 27-nov) · 90 — REVERSA
-- Quita las 9 funciones de este paquete; la huella de campo vuelve a 9f8b8ec55fc7e1c56fdf74a5f4e7f3c4. NADA SE BORRA: campo.reporte_pdf y campo.reporte_ran (con sus filas) y los PDF del bucket
-- se conservan. Sin estas funciones, la Edge responde que la ruta no está disponible y la pantalla lo dice; no se rompe nada más.
-- =====================================================================
do $rev$
declare r record; v_n bigint;
begin
  for r in select * from (values ('campo.f_ran_numerar(uuid)', '0898fb8ef37395807d1840793995f410'), ('campo.f_ran_autorizar(text,uuid)', '2ad5312a05781ae680593c77f3567996'), ('campo.f_ran_persona(text)', '878cb032577259fc99a65a88a895e705'), ('campo.f_ran_contenido(uuid)', 'b579de2d574bd050875d0f80d1129db0'), ('campo.f_ran_destino(uuid,text)', '13b97f29ab83affef654dc8dfa662ba3'), ('campo.f_ran_mapa(numeric,numeric,numeric,numeric)', 'bb39c53123e8c511bf06315a3b07db1a'), ('public.geoportal_campo_ran_datos(text,uuid,text)', '9930d5e29c50156477392e6023319068'), ('public.geoportal_campo_ran_registrar(text,uuid,text,text,integer,integer,text)', 'e74aa08891b6578297c9ce365b1e94ee'), ('public.geoportal_campo_ran_obtener(text,uuid,text)', 'c131b87deffb9c5f32df5a61ba548f95')) x(f, m) loop
    if to_regprocedure(r.f) is null or md5(pg_get_functiondef(to_regprocedure(r.f))) is distinct from r.m then
      raise exception 'La función % no es la de este paquete (sin aplicar o cambiada después): la reversa no la pisa; deténgase y avise', r.f;
    end if;
  end loop;
  select count(*) into v_n from campo.reporte_pdf;
  raise notice 'Reversa del PDF de Reportar anomalía: % versiones de PDF quedan en campo.reporte_pdf', v_n;
end $rev$;
-- DROP (por qué y alcance): las 9 funciones las creó este paquete y nada publicado las usa. Alcance: SOLO esas 9 firmas; no toca tablas ni datos.
drop function public.geoportal_campo_ran_obtener(text, uuid, text);
drop function public.geoportal_campo_ran_registrar(text, uuid, text, text, integer, integer, text);
drop function public.geoportal_campo_ran_datos(text, uuid, text);
drop function campo.f_ran_mapa(numeric, numeric, numeric, numeric);
drop function campo.f_ran_destino(uuid, text);
drop function campo.f_ran_contenido(uuid);
drop function campo.f_ran_persona(text);
drop function campo.f_ran_autorizar(text, uuid);
drop function campo.f_ran_numerar(uuid);

commit;
