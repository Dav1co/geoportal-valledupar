-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · ACTA — 10 · GUARDIA («Acta del reporte de activo», una por punto por levantar)
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Code B). Generado por pruebas_locales/generar.py.
-- · Presupone el Corte 14 publicado completo (huella del conjunto de funciones de redes {{MD5_BASE}}).
-- · Solo agrega DOS funciones (una interna y una RPC). No crea tablas, no cambia ninguna función y no toca nada fuera de redes.
-- · Sin datos de suscriptores: «quién» es siempre un funcionario (nombre, área y cargo).
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_redes_levantar_acta(text,text,text)') is not null then raise exception 'El acta del Corte 14 ya está aplicada: deténgase y avise'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_BASE}}' then
    raise exception 'Las funciones de redes no son las del Corte 14 publicado (huella {{MD5_BASE}}): deténgase y avise';
  end if;
  if to_regclass('redes.levantar_puntos') is null or to_regprocedure('redes.f_levantar_acceso(text)') is null or to_regprocedure('campo.f_cargo_vigente(text)') is null
     or to_regclass('redes.v_personal_ficha') is null then
    raise exception 'Faltan objetos del Corte 14, del 4b o de la pasada del 14-nov de Comercial: deténgase y avise';
  end if;
end $$;
