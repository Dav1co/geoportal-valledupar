-- HOTFIX 6b · safeupdate — ENSAYO. Termina SIEMPRE en ERROR (deshace todo). Esperado: «ENSAYO HOTFIX: 3 de 3 … SIN FALLAS».
-- Causa: las sesiones de la API (rol authenticator) cargan pg-safeupdate, que rechaza DELETE y UPDATE sin WHERE.
-- 5 funciones de redes los tenían; la del 6b tumba el geovisor (supervisor y administrador). Arreglo: «where true», nada más.
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
do $$
declare ok int := 0; n int; v text;
begin
  if (select count(*) from pg_proc p where p.oid in ('redes.f_refrescar_vigente()'::regprocedure, 'redes.f_recalcular_contrato_tramo()'::regprocedure,
        'redes.f_refrescar_contratos_capa()'::regprocedure, 'redes.f_candidatos_muestreo(bigint)'::regprocedure, 'redes.f_preparar_candidatos(bigint)'::regprocedure)
        and pg_get_functiondef(p.oid) like '%where true;%') = 5 then ok := ok + 1; end if;
  n := redes.f_refrescar_contratos_capa();
  if n > 100000 then ok := ok + 1; end if;
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) into v from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%');
  if v <> 'fca28bf695d1fcfa153f1113ce821528' then ok := ok + 1; end if;
  raise exception 'ENSAYO HOTFIX: % de 3 pruebas correctas — %  (capa de contratos: % filas; conjunto nuevo: %)',
    ok, case when ok = 3 then 'SIN FALLAS' else 'CON FALLAS' end, n, v;
end $$;
