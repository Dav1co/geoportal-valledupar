-- =====================================================================
-- COMERCIAL 21-NOV · (b) ACTAS · 90 — REVERSA
-- Quita los disparadores de campo.reportes y acta.actas (el registro vuelve a ser el de hoy), las RPC y las funciones nuevas, y desactiva los campos da_lugar.
-- Nada se borra: si hay firmas, PDF, derivadas o vínculos, sus tablas (con la protección de las firmas) y el bucket se conservan. Sin datos, se retiran.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_campo_documentos_catalogo(text,text)') is null then
    raise exception 'Las actas con firmas y PDF no están aplicadas: no hay nada que revertir';
  end if;
end $$;
drop trigger t_firmas_al_registrar on campo.reportes;
drop trigger t_derivadas_al_registrar on campo.reportes;
drop trigger t_firmas_al_registrar on acta.actas;
drop function public.geoportal_campo_documentos_catalogo(text, text);
drop function public.geoportal_campo_firma_guardar(text, text, uuid, text, text, text, text, text);
drop function public.geoportal_campo_pdf_registrar(text, text, uuid, text, integer, integer, text);
drop function public.geoportal_campo_pdf_datos(text, text, uuid, text);
drop function public.geoportal_campo_pdf_fallo(text, text, uuid, text, text);
drop function public.geoportal_campo_pdf_obtener(text, text, uuid, text);
drop function public.geoportal_campo_actas_registradas(text, jsonb, text);
drop function public.geoportal_campo_actas_registradas_descarga(text, jsonb, text);
drop function public.geoportal_campo_derivadas_abiertas(text, text, text, text);
drop function public.geoportal_campo_derivada_atender(text, bigint, text, uuid, text);
drop function public.geoportal_campo_derivada_cerrar(text, bigint, text, text, text);
drop function public.geoportal_campo_derivadas(text, jsonb, text);
drop function public.geoportal_campo_actas_abiertas(text, text, text);
drop function public.geoportal_campo_origen_vincular(text, uuid, uuid, text);
drop function campo.f_registradas_filtradas(jsonb);
drop function campo.f_derivada_json(bigint);
drop function campo.f_registradas();
drop function campo.f_autorizar_registradas(text);
drop function campo.f_autorizar_documento(text, text, uuid);
drop function campo.f_derivada_estado(bigint);
drop function campo.f_nombre_pdf(timestamptz, text, text, integer);
drop function campo.f_firmas_al_registrar_reporte();
drop function campo.f_derivadas_al_registrar();
drop function campo.f_firmas_al_registrar_acta();
drop function campo.f_documento_de(text);
drop function campo.f_formulario_de_reporte(bigint);
update campo.tipo_campos set activo = false where codigo in ('da_lugar', 'da_lugar_otra') and activo;
do $$
begin
  if exists (select 1 from campo.firmas) or exists (select 1 from campo.documentos_pdf) or exists (select 1 from campo.documento_intentos) or exists (select 1 from campo.derivadas)
     or exists (select 1 from campo.origen_vinculos) or exists (select 1 from storage.objects where bucket_id = 'actas-pdf') then
    raise notice 'Hay firmas, PDF, derivadas o vínculos: las tablas y el bucket actas-pdf se conservan (nada se borra)';
  else
    drop table campo.origen_vinculos;
    drop table campo.derivada_eventos;
    drop table campo.derivadas;
    drop table campo.derivadas_catalogo;
    drop table campo.documento_intentos;
    drop table campo.documentos_pdf;
    drop table campo.firmas;
    drop table campo.formularios_documento;
    drop function campo.f_firmas_definitivas();
    drop function campo.f_registro_existe(text, uuid);
    delete from storage.buckets where id = 'actas-pdf';
  end if;
end $$;
