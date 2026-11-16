-- Corte 9a · carga del Plan Maestro · publicar y sembrar. Generado por carga_pm.py. Va dentro de una transacción (la abre quien lo incluye).
select set_config('redes.pm_solicitante', lower(:'solicitante'), true) as quien \gset
-- 1. sectores y sumideros (las cargas abiertas de estos mismos archivos)
select key as dato, value as valor from jsonb_each_text(public.geoportal_redes_carga_publicar(:'solicitante',
  (select id from redes.v_cargas_estado where capa_codigo = 'sectores' and sha256 = 'a0f30ef676d57671484df5f79ac990c97f9e2ba513d11dfc6dfacf8e94a1b761' and estado = 'abierta'),
  'Plan Maestro 2014: 7 sectores y 29 subsectores PROYECTADOS (Anexo C). No son todavía los sectores con que se opera')) order by 1;
select key as dato, value as valor from jsonb_each_text(public.geoportal_redes_carga_publicar(:'solicitante',
  (select id from redes.v_cargas_estado where capa_codigo = 'sumideros' and sha256 = 'afc7815f2ca8cb3493f65476b6fe063584e60fd48c5da75c74cf5a721c989d6a' and estado = 'abierta'),
  'Plan Maestro 2014: 484 sumideros del catastro levantado (2013-2014)')) order by 1;
-- 2. el tanque La Popa: el nodo «Módulo Existente La Popa» del modelo (llave 21978) es el tanque real, que faltaba como activo. Solo si sigue «por clasificar».
do $$
declare v_q text := current_setting('redes.pm_solicitante'); v_nodo bigint; v_r jsonb;
begin
  select nodo_id into v_nodo from redes.v_nodo_visible where sistema = 'acueducto' and llave_modelo = '21978' and clase_nodo = 'por_clasificar';
  if v_nodo is null then raise notice 'El nodo del tanque La Popa ya no está por clasificar: no se crea de nuevo'; return; end if;
  v_r := public.geoportal_redes_nodo_crear_activo(v_q, v_nodo, 'TAN', null, 'Tanque La Popa (módulo existente)',
           'Plan Maestro 2014: el «Módulo Existente La Popa» del modelo es el tanque La Popa real; faltaba como activo (encargo del Corte 9a)');
  perform public.geoportal_redes_ficha_editar(v_q, v_r ->> 'activo',
           jsonb_build_object('capacidad', 3938, 'origen', jsonb_build_object('origen', 'emdupar', 'nota', 'Fuente del dato: Plan Maestro 2014 (ModeloVF, «Módulo Existente La Popa»; 3938 m³ útiles, cota 212.43 m)')),
           'Plan Maestro 2014: capacidad útil del modelo (3938 m³) y fuente del dato');
  raise notice 'Tanque La Popa creado: %', v_r ->> 'activo';
end $$;
-- 3. «Torre» = hidrante: alias visible del tipo (el prefijo TOR y los códigos no cambian). Solo si no lo tiene ya.
do $$
declare v_q text := current_setting('redes.pm_solicitante');
begin
  if (select nombre_visible from redes.v_tipo_visible where prefijo = 'TOR') is distinct from 'Hidrante' then
    perform public.geoportal_redes_alias_fijar(v_q, 'tipo', 'TOR', 'Hidrante', 'Plan Maestro 2014: los nodos «Torre» son hidrantes en el modelo (confirmado por David el 16-nov)');
  end if;
end $$;
-- 4. «por verificar»: estados distintos en el modelo, válvulas por verificar en campo y pozos MHP, MH y MHONE (evento con motivo; la ficha no cambia)
select redes.f_pm_marcar_por_verificar(lower(:'solicitante')) as marcados_por_verificar;
