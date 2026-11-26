#!/usr/bin/env python3
"""Pruebas de mutación de «Cuadernos de análisis» (clúster 55442 del Code B; NUNCA Supabase).
A. Código: cada mutación rompe UNA regla en el texto del ensayo local ya generado; el ensayo debe terminar con FALLAS y nombrar la prueba que la cuida
   (o, si la regla la cuida el cierre de la migración, detenerse con ese mensaje).
B. Guardia: cada mutación cambia algo vivo en una copia de la base; la migración debe negarse con su mensaje de guardia.
Correr antes generar.py. Escribe resultados/mutaciones.txt.
Uso: python3 -I mutar.py [-h]"""
import os
import re
import subprocess
import sys

if __name__ == '__main__':
    for a in sys.argv[1:]:
        if a in ('-h', '--help'):
            print(__doc__); sys.exit(0)
        print(f'Opción desconocida: {a}\n{__doc__}', file=sys.stderr); sys.exit(2)
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import generar as g

ENSAYO = g.leer(os.path.join(g.LOCAL, f'ensayo_en_transaccion_{g.NOMBRE}_local.sql'))
MIGRACION = os.path.join(g.LOCAL, f'migracion_{g.NOMBRE}_local.sql')
TMP = 'emdupar_b_cuad_mut'
SD = "language plpgsql security definer set search_path = public, analisis, pg_temp as $f$\n"

# (nombre, texto original, texto mutado, prueba que debe fallar o texto del cierre)
CODIGO = [
  ('sin el disparador de TRUNCATE',
   "    execute format('create trigger solo_agregar_truncate before truncate on analisis.%I for each statement execute function analisis.f_solo_agregar()', t);\n", '', '00.11'),
  ('el disparador por fila no cubre DELETE', 'before update or delete on analisis.%I for each row', 'before update on analisis.%I for each row', '08.02'),
  ('el disparador por fila no cubre UPDATE', 'before update or delete on analisis.%I for each row', 'before delete on analisis.%I for each row', '08.03'),
  ('las RPC también para authenticated', "grant execute on function %s to service_role', f.firma)", "grant execute on function %s to service_role, authenticated', f.firma)", '00.07'),
  ('sin revocar EXECUTE a public', "    execute format('revoke all on function %s from public, anon, authenticated, service_role', f.firma);\n", '', '00.07'),
  ('las internas ejecutables por service_role', "    if f.es_rpc then execute format('grant", "    if true then execute format('grant", '00.08'),
  ('una RPC sin SECURITY DEFINER', SD + 'declare a record; g geometry; v_km2 numeric; v_pred integer; v_cont integer;',
   SD.replace(' security definer', '') + 'declare a record; g geometry; v_km2 numeric; v_pred integer; v_cont integer;', '00.06'),
  ('una RPC sin search_path fijo', SD + 'declare a record; c analisis.cuadernos; v_mot text',
   SD.replace(' set search_path = public, analisis, pg_temp', '') + 'declare a record; c analisis.cuadernos; v_mot text', '00.06'),
  ('una interna sin search_path fijo', "language plpgsql set search_path = pg_catalog as $f$\nbegin\n  raise exception '%', p_mensaje", "language plpgsql as $f$\nbegin\n  raise exception '%', p_mensaje", '00.09'),
  ('sin RLS', "    execute format('alter table analisis.%I enable row level security', t);\n", '', '00.01'),
  ('service_role lee las tablas', "    execute format('revoke all on analisis.%I from public, anon, authenticated, service_role', t);", "    execute format('grant select on analisis.%I to service_role', t);", '00.02'),
  ('el Dell también escribe', 'grant select on analisis.catalogo,', 'grant select, insert on analisis.catalogo,', '00.04'),
  ('el operador entra a los cuadernos', '  if not coalesce(a.completo, false) then', '  if false then', '01.04'),
  ('cualquier supervisor edita el cuaderno ajeno', '  if p_autor and c.autor <> p_email then', '  if false then', '03.11'),
  ('sin el 409 de la versión base', '  if p_version_base <> v_ult then', '  if p_version_base > v_ult then', '03.13'),
  ('se guarda un cuaderno archivado', "  if analisis.f_archivado(c.id) then perform analisis.f_err('El cuaderno está archivado: reábralo para seguir editando', '55000'); end if;\n", '', '04.07'),
  ('la zona devuelve algo más que los dos números', "return jsonb_build_object('predios', v_pred, 'contratos', v_cont);", "return jsonb_build_object('predios', v_pred, 'contratos', v_cont, 'area_km2', v_km2);", '05.01'),
  ('sin tope de conteos por hora', "> analisis.f_parametro('zona_conteos_por_hora') then", '> 1000000 then', '05.09'),
  ('sin área máxima de la zona', "  if v_km2 > analisis.f_parametro('zona_area_max_km2') then", '  if false then', '05.04'),
  ('los contratos se cuentan repetidos', '(count(distinct c.cod_usuario) filter (', '(count(c.cod_usuario) filter (', '03.07'),
  ('sin la caja de Valledupar', '     and st_xmin(p_geom) >= -73.35 and st_xmax(p_geom) <= -73.16 and st_ymin(p_geom) >= 10.33 and st_ymax(p_geom) <= 10.56\n', '', '03.35'),
  ('el servidor no anota el sector', "where s.clase = 'sector' and st_intersects(s.geom, f.pt)", "where false and s.clase = 'sector' and st_intersects(s.geom, f.pt)", '03.03'),
  ('la mano alzada no se simplifica', "    if v_tipo = 'mano' then g := st_simplifypreservetopology(g, 0.00001); end if;", '', '03.05'),
  ('sin tope de marcas', "  if v_vigentes + v_nuevas - v_anuladas > analisis.f_parametro('marcas_por_cuaderno') then", '  if false then', '03.61'),
  ('no se comprueba que el activo real exista', " or not exists (select 1 from redes.v_activo_vigente w where w.codigo = v_act) then", ' then', '03.40'),
  ('un ícono de activo se enlaza a un activo real', "      if v_act is not null then perform analisis.f_err(v_pre || 'un ícono de activo es una propuesta y no se enlaza a un activo real'); end if;\n", '', '03.22'),
  ('las marcas anuladas siguen saliendo', '           order by mv.marca_id, mv.version desc) u\n   where not u.anulada\n$f$;', '           order by mv.marca_id, mv.version desc) u\n$f$;', '03.50'),
  ('se anula sin motivo', "      if length(v_mot) not between 5 and 300 then", '      if false then', '03.46'),
  ('se le cambia el tipo a una marca', "    if v_op = 'cambia' and v_tipo <> v_viejo.tipo then", '    if false then', '03.45'),
  ('sin tope de capturas', "  if v_n >= analisis.f_parametro('capturas_por_cuaderno') then", '  if false then', '06.19'),
  ('se confirma un archivo que no es JPEG', "  if v_mime is distinct from 'image/jpeg' then", '  if false then', '06.11'),
  ('se confirma un archivo de otro tamaño', '  if v_size <> k.bytes then', '  if false then', '06.12'),
  ('una captura sin confirmar se puede abrir', 'from analisis.capturas x join analisis.capturas_confirmadas kc on kc.captura_id = x.id where x.id = p_captura;', 'from analisis.capturas x where x.id = p_captura;', '06.09'),
  ('otro supervisor archiva el cuaderno ajeno', "  c := analisis.f_cuaderno(a.email, p_id, true);\n  if p_tipo is null", "  c := analisis.f_cuaderno(a.email, p_id);\n  if p_tipo is null", '04.01'),
  ('el cuaderno devuelve la ruta de la captura', "jsonb_build_object('id', k.id, 'titulo', k.titulo, 'extension',", "jsonb_build_object('id', k.id, 'ruta', k.ruta, 'titulo', k.titulo, 'extension',", '06.17'),
  ('una función con DELETE sin WHERE (pg-safeupdate)', "  return jsonb_build_object('predios', v_pred, 'contratos', v_cont);", "  delete from analisis.zona_consultas;\n  return jsonb_build_object('predios', v_pred, 'contratos', v_cont);",
   'DELETE/UPDATE sin WHERE'),
  ('el CHECK de la tabla deja pasar marcas fuera de Valledupar', 'constraint marca_geom_valida check (st_isvalid(geom) and analisis.f_en_valledupar(geom) and', 'constraint marca_geom_valida check (st_isvalid(geom) and', '03.64'),
  ('el CHECK de la tabla deja anular sin motivo', '  constraint marca_anulada_con_motivo check (anulada = (motivo is not null))', '  constraint marca_anulada_con_motivo check (true)', '03.66'),
]

# (nombre, SQL que cambia la base, texto que debe traer el rechazo de la migración)
GUARDIA = [
  ('el bucket es público', "update storage.buckets set public = true where id = 'analisis-capturas'", 'bucket analisis-capturas'),
  ('el bucket admite 5 MB', "update storage.buckets set file_size_limit = 5242880 where id = 'analisis-capturas'", 'bucket analisis-capturas'),
  ('el bucket admite PNG', "update storage.buckets set allowed_mime_types = array['image/jpeg', 'image/png'] where id = 'analisis-capturas'", 'bucket analisis-capturas'),
  ('no existe el bucket', "delete from storage.buckets where id = 'analisis-capturas'", 'bucket analisis-capturas'),
  ('cambió una función de redes', "create function redes.f_zt_mutacion() returns integer language sql as 'select 1'", 'huella de redes'),
  ('cambió una función de técnica', "create function tecnica.f_zt_mutacion() returns integer language sql as 'select 1'", 'huella de técnica'),
  ('ya existe el esquema analisis', 'create schema analisis', 'el esquema analisis ya existe'),
  ('ya hay una función geoportal_analisis_*', "create function public.geoportal_analisis_zt() returns integer language sql as 'select 1'", 'ya hay funciones'),
  ('el catastro perdió su índice GIST', 'drop index public.catastro_valledupar_geom_idx', 'índice GIST'),
]


def main():
    informe, mal = [], 0
    ruta = os.path.join(os.path.dirname(g.PSQL), 'cuad_mutado.sql')
    informe.append(f'A. CÓDIGO ({len(CODIGO)} mutaciones)')
    for nombre, antes, despues, prueba in CODIGO:
        n = ENSAYO.count(antes)
        if n != 1:
            informe.append(f'  NO APLICA  {nombre}: el texto original aparece {n} veces'); mal += 1; continue
        g.escribir(ruta, ENSAYO.replace(antes, despues))
        g.copia(TMP)
        p = g.corre(TMP, ruta)
        err = p.stderr or ''
        if prueba[0].isdigit():
            bien = p.returncode != 0 and 'FALLA(S)' in err and re.search(r'FALLA ' + re.escape(prueba) + r'\b', err) is not None
            r = re.search(r'RESULTADO: .*', err)
            det = r.group(0) if r else 'el ensayo se detuvo sin resultado: ' + err.strip()[-200:]
        else:
            bien = p.returncode != 0 and prueba in err and 'SIN FALLAS' not in err
            det = 'se detuvo en el cierre de la migración'
        informe.append(f"  {'DETECTADA ' if bien else 'NO DETECTADA'}  {nombre} → {prueba} · {det}")
        mal += 0 if bien else 1
    informe.append(f'B. GUARDIA ({len(GUARDIA)} mutaciones)')
    for nombre, cambio, texto in GUARDIA:
        g.copia(TMP)
        g.q(cambio, TMP)
        p = g.corre(TMP, MIGRACION)
        bien = p.returncode != 0 and 'GUARDIA ANÁLISIS' in (p.stderr or '') and texto in p.stderr and g.q("select count(*) from pg_proc where proname like 'geoportal\\_analisis\\_c%'", TMP) == '0'
        informe.append(f"  {'DETECTADA ' if bien else 'NO DETECTADA'}  {nombre} → «{texto}»")
        mal += 0 if bien else 1
    subprocess.run([g.PSQL, '-qX', '-d', 'postgres', '-c', f'drop database if exists {TMP}'], check=True, capture_output=True)
    os.remove(ruta)
    total = len(CODIGO) + len(GUARDIA)
    informe.append(f'RESULTADO: {total - mal} de {total} mutaciones detectadas' + (' — TODAS' if mal == 0 else f' — {mal} SIN DETECTAR'))
    g.escribir(os.path.join(g.RES, 'mutaciones.txt'), '\n'.join(informe) + '\n')
    print('\n'.join(l for l in informe if 'NO ' in l or l.startswith('RESULTADO')))
    sys.exit(1 if mal else 0)


if __name__ == '__main__':
    main()
