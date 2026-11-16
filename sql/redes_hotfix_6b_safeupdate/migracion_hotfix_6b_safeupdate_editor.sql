-- HOTFIX 6b · safeupdate — MIGRACIÓN (después del ensayo 3 de 3).
begin;
do $$
declare
  c text[][] := array[
    ['redes.f_refrescar_vigente()',          'delete from redes.activo_vigente_mat;', 'delete from redes.activo_vigente_mat where true;'],
    ['redes.f_recalcular_contrato_tramo()',  'delete from redes.contrato_tramo;',     'delete from redes.contrato_tramo where true;'],
    ['redes.f_refrescar_contratos_capa()',   'delete from redes.contratos_capa;',     'delete from redes.contratos_capa where true;'],
    ['redes.f_candidatos_muestreo(bigint)',  'else ''igual'' end;',                   'else ''igual'' end where true;'],
    ['redes.f_preparar_candidatos(bigint)',  'else ''cambiado'' end;',                'else ''cambiado'' end where true;']];
  i int; d text; n int;
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
     <> 'fca28bf695d1fcfa153f1113ce821528' then
    raise exception 'Las funciones de redes no son las del Corte 6b (o el arreglo ya está aplicado): deténgase y avise';
  end if;
  for i in 1 .. array_length(c, 1) loop
    d := pg_get_functiondef(c[i][1]::regprocedure);
    n := (length(d) - length(replace(d, c[i][2], ''))) / length(c[i][2]);
    if n <> 1 then raise exception '% : se esperaba 1 vez «%» y está % veces: deténgase y avise', c[i][1], c[i][2], n; end if;
    execute replace(d, c[i][2], c[i][3]);
  end loop;
end $$;
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('migracion@redes_hotfix_6b', 'migracion_redes_hotfix_6b_safeupdate', null,
        jsonb_build_object('funciones', jsonb_build_array('redes.f_refrescar_vigente', 'redes.f_recalcular_contrato_tramo', 'redes.f_refrescar_contratos_capa',
                           'redes.f_candidatos_muestreo', 'redes.f_preparar_candidatos'), 'cambio', 'where true (pg-safeupdate)'), null);
commit;
select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as conjunto_nuevo from pg_proc p
 where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');
