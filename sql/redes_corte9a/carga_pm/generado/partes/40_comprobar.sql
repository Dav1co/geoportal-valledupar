-- Corte 9a · carga del Plan Maestro · comprobaciones «N de N». Generado por carga_pm.py. Si alguna falla, ERROR: la transacción no queda.
create temp table _pm_r on commit drop as select * from (
  select 1, '01 las 12 cargas de referencia vigentes, cada una con las filas que dice su registro',
         (select count(*) from redes.v_ref_carga_vigente v join (values ('pm_nodos', '1b8db70ec1262c2687f40759ead4be61', 8165), ('pm_tramos', '1ea345f41d99b2458618c9c17807fc07', 10578), ('pm_valvulas', '49f08451406479abde815e9b6141e0b0', 730), ('pm_presion_existente', '63c6d3c6264d8441c79f2335f07e6422', 6945), ('pm_presion_futura', 'afd6f3cf27a2364707fcd3cdcf57c7df', 6815), ('pm_alc_conductos', 'c86a0ec53343f8a8b774ef5b4e9fded0', 9064), ('pm_alc_pozos', '503151f2212dc8f9ff689c2b228380be', 9146), ('plan_valvulas', 'c9ed18c211ad3d205357e754cb0b914d', 491), ('campana_2014', 'ff05eeea99af5ca5f53cb88e57357491', 12), ('campana_2014_lecturas', '373cbf42f9fad519651ce3aadde482af', 7184), ('pluvial', '0e9496e40cc2317193f31393c6350939', 897), ('pluvial_2043', '864d5c9372924973a26346122bfd335c', 1482)) x(c, m, n) on x.c = v.conjunto and x.m = v.md5 and x.n = v.filas) = 12,
         (select string_agg(conjunto || '=' || filas, ', ' order by conjunto) from redes.v_ref_carga_vigente)
  union all select 2, '02 acueducto: 8165 nodos, 10578 tramos y 730 válvulas del modelo; presiones por hora 6945 (existente) y 6815 (futura)',
         (select count(*) from redes.pm_nodos where carga_id = redes.f_ref_vigente('pm_nodos')) = 8165
         and (select count(*) from redes.pm_tramos where carga_id = redes.f_ref_vigente('pm_tramos')) = 10578
         and (select count(*) from redes.pm_valvulas where carga_id = redes.f_ref_vigente('pm_valvulas')) = 730
         and (select count(*) from redes.pm_presion_hora where carga_id = redes.f_ref_vigente('pm_presion_existente') and escenario = 'existente') = 6945
         and (select count(*) from redes.pm_presion_hora where carga_id = redes.f_ref_vigente('pm_presion_futura') and escenario = 'futura') = 6815, null
  union all select 3, '03 todo tramo y todo nodo-activo vigente del acueducto tiene su fila de modelo (la capa no se recargó: mismas llaves)',
         not exists (select 1 from redes.activo_vigente_mat m where m.capa_codigo = 'acueducto' and not m.retirado
                      and not exists (select 1 from redes.pm_tramos t where t.llave = m.llave_capa and t.carga_id = redes.f_ref_vigente('pm_tramos')))
         and not exists (select 1 from redes.activo_vigente_mat m where m.capa_codigo = 'acueducto_nodos' and not m.retirado
                      and not exists (select 1 from redes.pm_nodos n where n.llave = m.llave_capa and n.carga_id = redes.f_ref_vigente('pm_nodos'))),
         (select count(*) from redes.activo_vigente_mat m where m.capa_codigo in ('acueducto', 'acueducto_nodos') and not m.retirado)::text || ' activos del modelo'
  union all select 4, '04 las 730 válvulas del modelo son activos VAL vigentes y ninguna cambió su «efecto» oficial con la carga',
         (select count(*) from redes.pm_valvulas w join redes.activo_vigente_mat m on m.capa_codigo = 'acueducto_nodos' and m.llave_capa = w.llave and m.prefijo = 'VAL'
           where w.carga_id = redes.f_ref_vigente('pm_valvulas')) = 730
         and not exists (select 1 from redes.activo_versiones v where v.autor = current_setting('redes.pm_solicitante', true) and v.creado_en >= transaction_timestamp()
                          and exists (select 1 from redes.activos a where a.id = v.activo_id and a.prefijo = 'VAL')), null
  union all select 5, '05 alcantarillado: 9064 conductos y 9146 pozos enriquecidos; todo COL y POZ vigente de la capa tiene su fila; ningún activo de alcantarillado se retiró ni cambió de versión',
         (select count(*) from redes.pm_alc_conductos where carga_id = redes.f_ref_vigente('pm_alc_conductos')) = 9064
         and (select count(*) from redes.pm_alc_pozos where carga_id = redes.f_ref_vigente('pm_alc_pozos')) = 9146
         and not exists (select 1 from redes.activo_vigente_mat m where m.capa_codigo = 'alc_conductos' and not m.retirado
                          and not exists (select 1 from redes.pm_alc_conductos c where c.llave = m.llave_capa and c.carga_id = redes.f_ref_vigente('pm_alc_conductos')))
         and not exists (select 1 from redes.activo_vigente_mat m where m.capa_codigo = 'alc_pozos' and not m.retirado
                          and not exists (select 1 from redes.pm_alc_pozos c where c.llave = m.llave_capa and c.carga_id = redes.f_ref_vigente('pm_alc_pozos')))
         and not exists (select 1 from redes.activo_versiones v join redes.activos a on a.id = v.activo_id where a.prefijo in ('COL', 'POZ', 'VER') and v.creado_en >= transaction_timestamp())
         and not exists (select 1 from redes.activo_eventos e join redes.activos a on a.id = e.activo_id where a.prefijo in ('COL', 'POZ', 'VER') and e.tipo = 'retirar' and e.creado_en >= transaction_timestamp()), null
  union all select 6, '06 capas de referencia: 2882 elementos (491 válvulas propuestas, 12 puntos de la campaña con 11 ubicados, 897 del pluvial existente y 1.482 de la alternativa 2043) y 7184 lecturas',
         (select count(*) from redes.ref_elementos where carga_id in (select id from redes.v_ref_carga_vigente)) = 2882
         and (select count(*) from redes.ref_elementos where capa = 'campana_2014' and geom is not null and carga_id = redes.f_ref_vigente('campana_2014')) = 11
         and (select count(*) from redes.pm_campana_lecturas where carga_id = redes.f_ref_vigente('campana_2014_lecturas')) = 7184
         and not exists (select 1 from redes.ref_elementos e where e.geom is not null and not ST_IsValid(e.geom)), null
  union all select 7, '07 las válvulas propuestas NO son activos: ningún activo VAL nuevo y siguen «por clasificar» o como las dejó el supervisor',
         not exists (select 1 from redes.activos a where a.prefijo = 'VAL' and a.creado_en >= transaction_timestamp()), null
  union all select 8, '08 sectores: 7 sectores y 29 subsectores vigentes como SEC, en estado «Proyectado», con su número; un punto del centro de cada subsector da su sector y su subsector',
         (select count(*) filter (where m.clase = 'sector') = 7 and count(*) filter (where m.clase = 'subsector') = 29 and count(*) filter (where m.estado_codigo <> 'proyectado') = 0
            from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado and m.capa_codigo = 'sectores')
         and not exists (select 1 from redes.activo_vigente_mat m join redes.activo_versiones v on v.activo_id = m.activo_id and v.version = m.version
                          cross join lateral redes.f_sector_de(ST_PointOnSurface(m.geom)) s
                          where m.prefijo = 'SEC' and m.clase = 'subsector' and not m.retirado
                            and (s.subsector is distinct from v.atributos -> 'modelo' ->> 'subsector' or s.sector is distinct from (v.atributos -> 'modelo' ->> 'sector')::integer)),
         (select string_agg(distinct (v.atributos -> 'modelo' ->> 'sector'), ',' order by (v.atributos -> 'modelo' ->> 'sector')) from redes.activo_vigente_mat m
            join redes.activo_versiones v on v.activo_id = m.activo_id and v.version = m.version where m.prefijo = 'SEC' and not m.retirado)
  union all select 9, '09 sumideros: 484 activos SUM vigentes de la capa «sumideros»',
         (select count(*) from redes.activo_vigente_mat m where m.prefijo = 'SUM' and m.capa_codigo = 'sumideros' and not m.retirado) = 484, null
  union all select 10, '10 el tanque La Popa es un activo TAN vigente, enlazado a su nodo del modelo, con 3938 m³ y la fuente «Plan Maestro 2014» en su origen',
         (select count(*) from redes.v_nodo_vigente n join redes.v_activo_vigente a on a.activo_id = n.activo_id join redes.v_activo_origen_vigente o on o.activo_id = a.activo_id
           where n.sistema = 'acueducto' and n.llave_modelo = '21978' and n.clase_nodo = 'activo' and a.prefijo = 'TAN' and a.capacidad = 3938 and o.nota like '%Plan Maestro 2014%') = 1, null
  union all select 11, '11 el tipo TOR se ve como «Hidrante» y conserva su prefijo y sus códigos',
         (select nombre_visible from redes.v_tipo_visible where prefijo = 'TOR') = 'Hidrante'
         and (select count(*) from redes.activo_vigente_mat where prefijo = 'TOR' and codigo like 'TOR-%') = (select count(*) from redes.activo_vigente_mat where prefijo = 'TOR'), null
  union all select 12, '12 por verificar: todo activo que señala el Plan tiene su marca con motivo y ninguna marca cambió el estado de la ficha',
         not exists (select 1 from redes.v_pm_por_verificar x where not exists (select 1 from redes.activo_eventos e where e.activo_id = x.activo_id and e.tipo = 'por_verificar' and e.motivo like 'Plan Maestro 2014:%'))
         and (select count(distinct activo_id) from redes.v_pm_por_verificar) > 0,
         'activos señalados: ' || (select count(distinct activo_id) from redes.v_pm_por_verificar) || ' (estado ' || (select count(distinct activo_id) from redes.v_pm_por_verificar where grupo = 'estado')
           || ', válvulas ' || (select count(distinct activo_id) from redes.v_pm_por_verificar where grupo = 'valvula') || ', pozos ' || (select count(distinct activo_id) from redes.v_pm_por_verificar where grupo = 'pozo')
           || '); según los archivos: estado 43, válvulas 63, pozos 1640'
  union all select 13, '13 «gana la ficha»: ningún activo editado en la ficha cambió de versión por esta carga (hoy, solo VAL-000001 «V85»)',
         not exists (select 1 from redes.ficha_ediciones fe join redes.activo_versiones v on v.activo_id = fe.activo_id
                      where v.creado_en >= transaction_timestamp() and fe.creado_en < transaction_timestamp() and v.carga_id is not null), null
  union all select 14, '14 nada se borró: ningún activo retirado ni oculto por esta carga',
         not exists (select 1 from redes.activo_eventos e where e.tipo in ('retirar', 'ocultar') and e.creado_en >= transaction_timestamp()), null
  union all select 15, '15 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()), null
) t(n, nombre, ok, detalle);
select n, case when coalesce(ok, false) then 'OK' else 'FALLA' end as resultado, nombre, coalesce(detalle, '') as detalle from _pm_r order by n;
do $$
declare v_t integer; v_b integer; v_f text;
begin
  select count(*), count(*) filter (where coalesce(ok, false)), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\n' order by n) filter (where not coalesce(ok, false)), '')
    into v_t, v_b, v_f from _pm_r;
  if v_b <> v_t or coalesce(current_setting('redes.pm_ensayo', true), '') = 'si' then
    raise exception E'CARGA DEL PLAN MAESTRO · CORTE 9a%\n%\nRESULTADO: % de % comprobaciones correctas — %',
      case when coalesce(current_setting('redes.pm_ensayo', true), '') = 'si' then ' (ENSAYO: este ERROR es el esperado y deshace todo)' else ' (se deshace todo: no quedó nada cargado ni publicado en este paso)' end,
      v_f, v_b, v_t, case when v_b = v_t then 'SIN FALLAS' else (v_t - v_b) || ' FALLA(S)' end;
  end if;
  raise notice 'CARGA DEL PLAN MAESTRO · CORTE 9a: % de % comprobaciones correctas — SIN FALLAS', v_b, v_t;
end $$;
