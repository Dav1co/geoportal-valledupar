-- HOTFIX 6b · safeupdate — REVERSA (vuelve al texto del 6b).
begin;
do $$
declare
  c text[][] := array[
    ['redes.f_refrescar_vigente()',          'delete from redes.activo_vigente_mat where true;', 'delete from redes.activo_vigente_mat;'],
    ['redes.f_recalcular_contrato_tramo()',  'delete from redes.contrato_tramo where true;', 'delete from redes.contrato_tramo;'],
    ['redes.f_refrescar_contratos_capa()',   'delete from redes.contratos_capa where true;', 'delete from redes.contratos_capa;'],
    ['redes.f_candidatos_muestreo(bigint)',  'else ''igual'' end where true;', 'else ''igual'' end;'],
    ['redes.f_preparar_candidatos(bigint)',  'else ''cambiado'' end where true;', 'else ''cambiado'' end;']];
  i int; d text; n int;
begin
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
     <> '8113af17c6bd862d62a6cbc4bc4cba1f' then
    raise exception 'Las funciones de redes no son las del hotfix: deténgase y avise';
  end if;
  for i in 1 .. array_length(c, 1) loop
    d := pg_get_functiondef(c[i][1]::regprocedure);
    n := (length(d) - length(replace(d, c[i][2], ''))) / length(c[i][2]);
    if n <> 1 then raise exception '% : se esperaba 1 vez «%» y está % veces: deténgase y avise', c[i][1], c[i][2], n; end if;
    execute replace(d, c[i][2], c[i][3]);
  end loop;
end $$;
commit;
