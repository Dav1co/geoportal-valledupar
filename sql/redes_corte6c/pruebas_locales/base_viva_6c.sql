-- DOBLE LOCAL (solo pruebas; NO va en la migración): lo que producción tiene y la base local no traía.
-- · El índice de catastro por cod_usuario (vivo: idx_catastro_cod_usuario) y la llave de la ficha ya estaban en el doble del 6b.
-- · El rol authenticator con sus topes, como en Supabase: las peticiones de la API entran por él y cambian a service_role.
--   (pg-safeupdate no se carga en local: lo cubre la comprobación estática redes.f_funciones_sin_where.)
create index if not exists idx_catastro_cod_usuario on public.catastro_valledupar (cod_usuario);
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then create role authenticator noinherit; end if;
end $$;
grant service_role to authenticator;
alter role authenticator set lock_timeout = '8s';
alter role service_role set statement_timeout = '30s';
alter role authenticated set statement_timeout = '8s';
analyze public.catastro_valledupar;
