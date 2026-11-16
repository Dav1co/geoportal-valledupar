-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 10 — GUARDIA Y COLUMNAS NUEVAS
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew).
-- Fuente: 02 fila 4, §16, §25 y §26 de la bitácora, y lo pospuesto de los Cortes 2, 3a y 3b.
-- · Presupone el 3b aplicado (huella del conjunto de funciones de redes, de v_dano y de v_epicrisis).
-- · ⚠ Toca las 4 funciones de permisos VIVAS (15): exige su huella md5 del 14-nov (paquete de Análisis de contrato). Si alguna cambió, se detiene
--   y dice la huella que encontró, para revisarla antes de seguir.
-- · Columnas nuevas (nada se borra): public.geoportal_lista_blanca.ver_dashboard_redes (15) y redes.danos.sector_num (aquí).
-- =====================================================================
do $$
declare v_esp jsonb := jsonb_build_object('geoportal_puede', '72b422973f0627aa2bf4a966855bc980', 'geoportal_mis_permisos', '5cf2e4f476e6ad9b75a185a6a225fc5f',
                                          'geoportal_admin_permisos', 'adc8edcc7708441dd91b584d326f297a', 'geoportal_admin_listar', 'fa675b8611c5c74fb77f7853facb8479');
        k text; v_n integer; v_m text;
begin
  if to_regclass('redes.ficha_ediciones') is null then raise exception 'Falta el Corte 3b: aplíquelo antes'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '45971067176a3d30286b6227f0447c0d' then
    raise exception 'Las funciones de redes no son las del Corte 3b (o el Corte 4a ya está aplicado): deténgase y avise';
  end if;
  if md5(pg_get_viewdef('redes.v_dano'::regclass, true)) <> 'bee1b39d753fc55ae7cb85a3952896fb' or md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true)) <> 'a1e45ec72cb5b254a67698111994746a' then
    raise exception 'Las vistas v_dano o v_epicrisis no son las del 3b: deténgase y avise';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'geoportal_lista_blanca' and column_name = 'ver_dashboard_redes')
     or exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name = 'danos' and column_name = 'sector_num') then
    raise exception 'ver_dashboard_redes o sector_num ya existen: el Corte 4a parece aplicado';
  end if;
  for k in select jsonb_object_keys(v_esp) loop
    select count(*), max(md5(pg_get_functiondef(p.oid))) into v_n, v_m from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = k;
    if v_n <> 1 then raise exception 'GUARDIA: public.% tiene % firmas (se esperaba 1)', k, v_n; end if;
    if v_m <> v_esp ->> k then raise exception 'GUARDIA: public.% cambió desde el 14-nov (huella % y se esperaba %). No se aplica nada: avise.', k, v_m, v_esp ->> k; end if;
  end loop;
  if to_regprocedure('public.geoportal_aislamiento_verificado()') is null then raise exception 'Falta public.geoportal_aislamiento_verificado()'; end if;
end $$;

-- §25.1: el sector del daño es un número entero del 1 al 100 (hoy 1 a 7). sector_texto se queda (no se borra) y deja de llenarse.
alter table redes.danos add column sector_num smallint check (sector_num between 1 and 100);
comment on column redes.danos.sector_num is 'Sector hidráulico del daño: número del 1 al 100 (David, 15-nov 20:00). Reemplaza en la pantalla a sector_texto, que queda sin uso y sin borrar.';
comment on column redes.danos.sector_texto is 'Sin uso desde el Corte 4a (el sector pasó a sector_num, número del 1 al 100). No se borra: nada se borra.';
