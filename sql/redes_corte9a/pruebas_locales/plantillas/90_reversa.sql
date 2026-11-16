-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a · 90 — REVERSA (PROPUESTA; no se ha ejecutado en la base real). Generada por pruebas_locales/generar.py.
-- Deja las funciones y la vista redes.v_nodo_vigente como estaban con el 7a (texto exacto) y quita lo nuevo del 9a.
-- SE NIEGA si las funciones cambiaron después de la migración, o si YA HAY DATOS: cargas de referencia (redes.ref_cargas) o nodos clasificados
-- sin activo (eventos «clasificar»). Nada se borra: con datos cargados, lo que corresponde es apagar las capas en el geovisor (Capas al abrir) y avisar.
-- Lo que NO deshace (no se borra): los catálogos sembrados quedan desactivados (clases de SEC, capas del geovisor como «preparada» e inactivas)
-- y los 4 parámetros de presión quedan sin uso. Los activos SEC y SUM que haya cargado el motor se manejan con «Volver a la versión anterior» del Cargue.
-- =====================================================================
do $$
begin
  if to_regclass('redes.ref_cargas') is null then raise exception 'No hay nada que revertir: el Corte 9a no está aplicado'; end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_9A}}' then
    raise exception 'Las funciones cambiaron después de la migración del Corte 9a: la reversa se niega a pisarlas; avise';
  end if;
  if exists (select 1 from redes.ref_cargas) then raise exception 'Ya hay cargas de referencia del Plan Maestro: la reversa no borra datos; apague las capas y avise'; end if;
  if exists (select 1 from redes.nodo_eventos where tipo = 'clasificar') then raise exception 'Ya hay nodos clasificados sin activo: la reversa no borra hechos; avise'; end if;
end $$;

-- 1. lo nuevo
drop view redes.v_pm_por_verificar;
{{DROPS}}
drop view redes.v_ref_carga_vigente;
drop table redes.pm_campana_lecturas, redes.ref_elementos, redes.pm_alc_pozos, redes.pm_alc_conductos, redes.pm_presion_hora, redes.pm_valvulas, redes.pm_tramos, redes.pm_nodos,
           redes.ref_carga_eventos, redes.ref_cargas;

-- 2. la vista de nodos y el evento, como en el 1a
create or replace view redes.v_nodo_vigente as
{{VISTA_NODO_ANTES}};
alter table redes.nodo_eventos drop constraint nodo_eventos_clase_check;
alter table redes.nodo_eventos drop constraint nodo_eventos_tipo_check;
alter table redes.nodo_eventos add constraint nodo_eventos_tipo_check check (tipo in ('enlazar_activo', 'desenlazar', 'nota'));
alter table redes.nodo_eventos drop column clase;

-- 3. catálogos: se desactivan (no se borran)
update redes.geovisor_capas set fuente = 'preparada', estado = 'espera_dato', activa = false where codigo in ('plan_valvulas', 'pluvial', 'pluvial_2043', 'presion_modelo', 'campana_2014');
alter table redes.geovisor_capas drop constraint geovisor_capas_fuente_check;
alter table redes.geovisor_capas add constraint geovisor_capas_fuente_check check (fuente in ('tesela', 'geojson', 'preparada', 'contratos'));
update redes.geovisor_capas set nombre = 'Sectores hidráulicos', nota = 'Se ven cuando se carguen los polígonos (Cargue de capas)' where codigo = 'sectores';
update redes.capas_por_perfil set encendida = false, actualizado_en = clock_timestamp(), actualizado_por = 'reversa@redes_corte9a'
 where capa = 'sectores' and actualizado_por = 'migracion@redes_corte9a';
update redes.clases_activo set activo = false where prefijo = 'SEC' and codigo in ('sector', 'subsector');
update redes.parametros set descripcion = 'Sin uso (reversa del Corte 9a)' where clave in ('presion_baja_naranja_mca', 'presion_baja_roja_mca', 'presion_alta_naranja_mca', 'presion_alta_roja_mca');

-- 4. las funciones reemplazadas, con su texto del 7a
{{TEXTOS_ANTES}}
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte9a', 'reversa_redes_corte9a', null, jsonb_build_object('motivo', 'reversa del Corte 9a (sin datos cargados)'), null);
