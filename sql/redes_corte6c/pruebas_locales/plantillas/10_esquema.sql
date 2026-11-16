-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 10 — GUARDIA
-- PROPUESTA. No se ha ejecutado en la base real (solo en el PostGIS local de Homebrew). Generado por pruebas_locales/generar.py.
-- Fuente: encargo_code_corte6c_contratos_capa.md (16-nov): la capa de contratos sale de la petición.
-- · Presupone el 6b MÁS el hotfix de pg-safeupdate (huella del conjunto de funciones de redes {{MD5_HOTFIX}}).
-- · La tesela de contratos se arma AL VUELO, solo con los predios de su recuadro, con los índices que ya existen en Comercial (no se crea ninguno):
--   GiST de catastro_valledupar.geom, catastro por cod_usuario, ficha_contrato por contrato y cartera_suscripcion por contrato.
-- · Lee (no escribe) lo vivo de Comercial: public.catastro_valledupar, public.cartera_suscripcion y bi_interno.ficha_contrato. Nada de eso cambia.
-- · ⚠ Se reemplazan 3 RPC del 6b (geoportal_redes_geovisor, _geovisor_mvt_contratos y _contrato_tarjeta), con su texto exacto en la reversa.
-- · ⚠ Se retiran la copia derivada (redes.contratos_capa y redes.contratos_capa_estado) y las 2 funciones que la rehacían. No guardaban hechos:
--   eran una copia que se recalculaba entera; la reversa las vuelve a crear vacías.
-- =====================================================================
do $$
begin
  if to_regclass('redes.contratos_capa') is null or to_regprocedure('redes.f_refrescar_contratos_capa()') is null then
    raise exception 'No está la capa derivada del Corte 6b (o el Corte 6c ya está aplicado): deténgase y avise';
  end if;
  if (select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p
       where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\_redes\_%')) <> '{{MD5_HOTFIX}}' then
    raise exception 'Las funciones de redes no son las del Corte 6b con el hotfix de safeupdate (o el Corte 6c ya está aplicado): deténgase y avise';
  end if;
  -- lo vivo que se lee
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'catastro_valledupar' and column_name in ('id', 'cod_usuario', 'direccion', 'barrio', 'geom')) <> 5
     or (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'cartera_suscripcion'
          and column_name in ('contrato', 'estado', 'nombre', 'direccion', 'barrio', 'categoria', 'periodo_carga')) <> 7
     or (select count(*) from information_schema.columns where table_schema = 'bi_interno' and table_name = 'ficha_contrato'
          and column_name in ('contrato', 'periodo_ultimo', 'uso', 'consumo_meses', 'cons_prom', 'meses_con_lectura', 'medidor_anios')) <> 7 then
    raise exception 'Las tablas de Comercial (catastro, cartera diaria o ficha del contrato) no tienen las columnas esperadas: deténgase y avise';
  end if;
  -- los índices de Comercial con los que la tesela responde rápido (no se crean aquí: si falta alguno, se avisa)
  if not exists (select 1 from pg_index x join pg_class i on i.oid = x.indexrelid join pg_am am on am.oid = i.relam
                  where x.indrelid = 'public.catastro_valledupar'::regclass and am.amname = 'gist' and pg_get_indexdef(i.oid) ~ '\(geom\)') then
    raise exception 'Falta el índice espacial (GiST) de catastro_valledupar.geom: deténgase y avise';
  end if;
  if not exists (select 1 from pg_index x where x.indrelid = 'public.catastro_valledupar'::regclass and x.indisvalid and x.indpred is null
                  and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(cod_usuario( text_pattern_ops)?[,)]') then
    raise exception 'Falta el índice de catastro_valledupar por cod_usuario: deténgase y avise';
  end if;
  if not exists (select 1 from pg_index x where x.indrelid = 'public.cartera_suscripcion'::regclass and x.indisvalid and x.indpred is null
                  and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(contrato[,)]') then
    raise exception 'Falta el índice de cartera_suscripcion por contrato: deténgase y avise';
  end if;
  if not exists (select 1 from pg_index x where x.indrelid = 'bi_interno.ficha_contrato'::regclass and x.indisvalid and pg_get_indexdef(x.indexrelid) ~ 'USING btree \(contrato[,)]') then
    raise exception 'Falta el índice de bi_interno.ficha_contrato por contrato: deténgase y avise';
  end if;
end $$;
