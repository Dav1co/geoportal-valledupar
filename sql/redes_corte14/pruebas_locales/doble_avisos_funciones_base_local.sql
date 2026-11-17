-- DOBLE LOCAL (solo para las pruebas de Code B; NO se corre en producción): las funciones de apoyo del Corte 12 que usa tecnica.f_avisos y que la base local de
-- redes no trae (el doble del 12 solo tenía el texto de f_avisos, para la guardia md5). Con ellas el bloque de DISTRIBUCIÓN de f_avisos corre en local
-- (p_planta = false). En producción son las del Corte 12 publicado; el ensayo del paquete las usa tal cual.
create function tecnica.f_aparam(p_clave text) returns numeric language sql stable security definer set search_path to 'tecnica', 'pg_temp' as
$$ select valor from tecnica.aviso_parametros where clave = p_clave $$;
create function tecnica.f_cuantos(p_n bigint, p_uno text, p_varios text) returns text language sql immutable set search_path to 'pg_catalog' as
$$ select case when p_n = 1 then '1 ' || p_uno else replace(to_char(p_n, 'FM999G999G999'), ',', '.') || ' ' || p_varios end $$;
create function tecnica.f_texto_num(p_n numeric) returns text language sql immutable set search_path to 'pg_catalog' as
$$ select replace(to_char(p_n, 'FM999G999G990'), ',', '.') $$;
create function tecnica.f_texto_horas(p_h numeric) returns text language sql immutable set search_path to 'pg_catalog' as
$$ select round(p_h, 1) || ' h' $$;
revoke all on function tecnica.f_aparam(text), tecnica.f_cuantos(bigint, text, text), tecnica.f_texto_num(numeric), tecnica.f_texto_horas(numeric) from public, anon, authenticated, service_role;
