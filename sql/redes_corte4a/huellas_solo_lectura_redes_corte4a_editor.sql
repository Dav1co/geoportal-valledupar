-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 05 — HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada.
-- Generada por pruebas_locales/generar.py.
-- ANTES: «funciones de redes» dice «CORTE 3b (listo para el 4a)»; las 4 funciones de permisos «14-nov (sin cambiar)»; las 7 RPC nuevas «NO EXISTE»;
-- las 10 que se reemplazan «CORTE 3b (sin cambiar)». DESPUÉS: «CORTE 4a (aplicado)», «CORTE 4a (con dashboard_redes)», «NUEVA» y «CORTE 4a (reemplazada)».
-- Cualquier «DISTINTA», «FALTA» o «VARIAS FIRMAS»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with viv(objeto, antes, despues) as (values ('geoportal_puede', '72b422973f0627aa2bf4a966855bc980', '32f174a55b95788d3f8187b507303c2f'), ('geoportal_mis_permisos', '5cf2e4f476e6ad9b75a185a6a225fc5f', '83166fe17be58da67bbdedaae429bedb'), ('geoportal_admin_permisos', 'adc8edcc7708441dd91b584d326f297a', 'e5a90103b4a83440fd826f03266b7245'), ('geoportal_admin_listar', 'fa675b8611c5c74fb77f7853facb8479', 'd7311a32ea03cccd6c83691e63ba10bc')),
rviv as (
  select 'permisos public.' || v.objeto as objeto, max(md5(pg_get_functiondef(p.oid))) as md5,
         case when count(p.oid) = 0 then 'FALTA' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = v.antes then '14-nov (sin cambiar)'
              when max(md5(pg_get_functiondef(p.oid))) = v.despues then 'CORTE 4a (con dashboard_redes)' else 'DISTINTA' end as estado
    from viv v left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = v.objeto group by v.objeto, v.antes, v.despues),
esp(objeto, nueva) as (values ('geoportal_redes_crear_activo_bandeja', 'e8b63e82cc037a55cf8d6bbeaff2c672'), ('geoportal_redes_dano_evento', '755f6c3ac68483d28a77fb5e9eac6250'), ('geoportal_redes_dano_tercero', 'a9f7a419e54ad075a095a53cc84a2b11'), ('geoportal_redes_danos', '6916bb6e1f206bec88607808e5e7af18'), ('geoportal_redes_intervencion_evento', '1b90ab54e4a0abb2446911015fc1dc88'), ('geoportal_redes_mi_perfil', '5586014c1951c945beae56892c392c1f'), ('geoportal_redes_reportes_bot', 'a5b4ec5e0f178f04a4e94669c75dc1c6')),
rpc as (
  select 'public.' || e.objeto, max(md5(pg_get_functiondef(p.oid))),
         case when count(p.oid) = 0 then 'NO EXISTE (sin aplicar)' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = e.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end
    from esp e left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = e.objeto group by e.objeto, e.nueva),
cam(objeto, antes, despues) as (values ('geoportal_redes_crear_dano', '7e70de54924240852635815f423571d1', 'e7cac815fb0ae796fff42ade0f39419c'), ('geoportal_redes_crear_intervencion', 'adbbd14fb072761159992f54641f45e9', 'a818d3622ae5877867f2ed45cf44d0f7'), ('geoportal_redes_danos_abiertos', '3e83bbf79f79da3526bde3523c3ac5c4', '54964c68ffb7f8bf831f166779e21d8f'), ('geoportal_redes_ficha_editar', '81b34cc4069f05b0d11c0bd48c2e50aa', '5b84f4813dfa41fc146fdd6cb4c5453a'), ('geoportal_redes_formulario_dano', '099483758f22b4fe033937d14476f380', '5d4bf2d2a7131533dffcd11f2420e8ff'), ('geoportal_redes_formulario_intervencion', 'ecac88b6b115cff6a6b042167450903b', '70d3ece24b27766dbc2c38e3dfc607ea'), ('geoportal_redes_galeria', '3f96811f59b6cd31497d3d013b102205', 'a1a8c0195596e5dfadb1b7fe7f802d35'), ('geoportal_redes_perfil', '2520ff7f1def39d5ba9958dbeb7ee7cc', '501239a3a982db579ce0e06a3426fb8f'), ('geoportal_redes_preparar_dano', 'e425feacdf9066b56fc0ae971aa843e1', 'ae00663060e0b6265f32f3edc3e36053'), ('geoportal_redes_preparar_intervencion', '363488408002e09d046b842ba7861c8c', 'bda058911dc8e34799bcf3849ec90310')),
rpc2 as (
  select 'public.' || c.objeto, max(md5(pg_get_functiondef(p.oid))),
         case when count(p.oid) = 0 then 'FALTA' when count(p.oid) > 1 then 'VARIAS FIRMAS' when max(md5(pg_get_functiondef(p.oid))) = c.antes then 'CORTE 3b (sin cambiar)'
              when max(md5(pg_get_functiondef(p.oid))) = c.despues then 'CORTE 4a (reemplazada)' else 'DISTINTA' end
    from cam c left join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = c.objeto group by c.objeto, c.antes, c.despues),
conj as (
  select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) as m from pg_proc p
   where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%'))
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '45971067176a3d30286b6227f0447c0d' then 'CORTE 3b (listo para el 4a)' when '1a2be013019c9a59f1c1e0f2241661f0' then 'CORTE 4a (aplicado)' else 'DISTINTA' end as estado
union all select * from rviv
union all select * from rpc
union all select * from rpc2
union all select '1 columna ver_dashboard_redes', null, case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'geoportal_lista_blanca'
       and column_name = 'ver_dashboard_redes') then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
union all select '1 columna redes.danos.sector_num', null, case when exists (select 1 from information_schema.columns where table_schema = 'redes' and table_name = 'danos'
       and column_name = 'sector_num') then 'EXISTE (aplicado)' else 'NO EXISTE (sin aplicar)' end
order by 1;
