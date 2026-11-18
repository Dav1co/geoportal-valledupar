#!/usr/bin/env python3
"""Arma el paquete SQL del acta del Corte 14 con las huellas reales de la base local de Code B (puerto 55442).
Parte de emdupar_b_14base + la migración del Corte 14 (producción con el 14 publicado: huella 1a9ef250…). Solo agrega dos funciones.
Uso: python3 -I generar.py     Sobre otra huella: MD5_BASE=<huella> python3 -I generar.py"""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = os.environ.get('BASE_B', 'emdupar_b14a')
ENV = dict(os.environ, PGHOST='localhost', PGPORT=os.environ.get('PGPORT_B', '55442'), PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
assert ENV['PGPORT'] != '55432', 'El puerto 55432 es de Code A'
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_BASE = os.environ.get('MD5_BASE', '1a9ef250a74fb01962f463d98834cc4a')      # el Corte 14 publicado completo
NUEVAS = ['redes.f_levantar_funcionario(text,text)', 'public.geoportal_redes_levantar_acta(text,text,text)']
MIG = ['10_guardia.sql', '26_rpc.sql', '40_permisos.sql']


def q(sql, base=None):
    return subprocess.run([PSQL, '-d', base or BASE, '-AtX', '-c', sql], env=ENV, check=True, capture_output=True, text=True).stdout.strip()


def leer(n):
    return open(os.path.join(RAIZ, 'sql', n), encoding='utf-8').read()


def escribir(ruta, texto):
    open(ruta, 'w', encoding='utf-8').write(texto)


subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=dict(ENV, BASE_B=BASE), check=True, capture_output=True)
assert q(CONJ) == MD5_BASE, q(CONJ)
guardia = open(os.path.join(AQUI, '10_guardia.plantilla.sql'), encoding='utf-8').read().replace('{{MD5_BASE}}', MD5_BASE)
escribir(os.path.join(RAIZ, 'sql', '10_guardia.sql'), guardia)
escribir(os.path.join(RAIZ, 'migracion_redes_corte14_acta_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte14_acta_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
p = subprocess.run([PSQL, '-d', BASE, '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte14_acta_editor.sql')], env=ENV, capture_output=True, text=True)
if p.returncode != 0:
    raise SystemExit(p.stderr[-3000:])
md5_fin = q(CONJ)
nuevas = ', '.join(f"('{f}', '{q(chr(115) + 'elect md5(pg_get_functiondef(' + chr(39) + f + chr(39) + '::regprocedure))')}')" for f in NUEVAS)
conj_sql = CONJ.replace('\\\\', '\\')
huellas = f"""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · ACTA — 05 · HUELLAS DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). No escribe nada. Generada por generar.py.
-- ANTES: «funciones de redes» dice «CORTE 14 (listo para el acta)» y las 2 nuevas «NO EXISTE». DESPUÉS: «ACTA (aplicada)» y 2 «NUEVA».
-- Cualquier «DISTINTA» o «FALTA»: no aplique nada y avise (copie la huella que salió).
-- =====================================================================
with nue(firma, nueva) as (values {nuevas}),
conj as ({conj_sql.replace('select md5', 'select md5', 1).replace(' from pg_proc p', ' as m from pg_proc p', 1)})
select '0 funciones de redes (conjunto)' as objeto, (select m from conj) as md5,
       case (select m from conj) when '{MD5_BASE}' then 'CORTE 14 (listo para el acta)' when '{md5_fin}' then 'ACTA (aplicada)' else 'DISTINTA' end as estado
union all select '1 ' || n.firma, md5(pg_get_functiondef(to_regprocedure(n.firma))),
       case when to_regprocedure(n.firma) is null then 'NO EXISTE (sin aplicar)' when md5(pg_get_functiondef(to_regprocedure(n.firma))) = n.nueva then 'NUEVA (aplicada)' else 'DISTINTA' end from nue n
union all select '2 objetos que usa (puntos por levantar, Personal de distribución y cargo de Comercial)', null,
       case when to_regclass('redes.levantar_puntos') is not null and to_regclass('redes.v_personal_ficha') is not null and to_regprocedure('campo.f_cargo_vigente(text)') is not null then 'ESTÁN' else 'FALTA' end
order by 1;
"""
verif = f"""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · ACTA — 80 · VERIFICACIÓN DE SOLO LECTURA (una sola consulta; apta para el editor SQL web). Todas las filas deben decir OK.
-- Nota: después del acta, la fila 03 de la verificación del Corte 14 deja de valer (el conjunto de funciones cambió).
-- =====================================================================
select k, v from (
  select 1 as o, '01 la RPC del acta: security definer, search_path fijo, solo service_role' as k,
         case when (select count(*) from pg_proc p where p.oid = 'public.geoportal_redes_levantar_acta(text,text,text)'::regprocedure and p.prosecdef and p.proconfig is not null
                     and has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and not has_function_privilege('authenticated', p.oid, 'execute')
                     and not exists (select 1 from aclexplode(p.proacl) x where x.grantee = 0)) = 1 then 'OK' else 'MAL' end as v
  union all select 2, '02 ninguna función interna de redes la ejecuta la API (incluida la nueva)',
         case when not exists (select 1 from pg_proc p where p.pronamespace = 'redes'::regnamespace
                                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))) then 'OK' else 'MAL' end
  union all select 3, '03 huellas md5 de las 2 nuevas y del conjunto de funciones de redes con el acta',
         case when (select count(*) from (values {nuevas}) c(f, m) where md5(pg_get_functiondef(to_regprocedure(c.f))) = c.m) = 2
               and ({conj_sql}) = '{md5_fin}' then 'OK' else 'MAL' end
  union all select 4, '04 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE',
         coalesce((select 'MAL: ' || string_agg(distinct funcion, ', ') from redes.f_funciones_sin_where()), 'OK')
) t order by o;
"""
reversa = f"""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 14 · ACTA — 90 · REVERSA (PROPUESTA). Quita las 2 funciones nuevas. No hay datos que borrar.
-- SE NIEGA si alguna función de redes cambió después de la migración.
-- =====================================================================
do $$
begin
  if to_regprocedure('public.geoportal_redes_levantar_acta(text,text,text)') is null then raise exception 'No hay nada que revertir: el acta no está aplicada'; end if;
  if ({conj_sql}) <> '{md5_fin}' then
    raise exception 'Las funciones cambiaron después de la migración del acta: la reversa se niega a pisarlas; avise';
  end if;
end $$;
drop function public.geoportal_redes_levantar_acta(text, text, text);
drop function redes.f_levantar_funcionario(text, text);
insert into public.geoportal_auditoria (email, accion, referencia, detalle, ip)
values ('reversa@redes_corte14_acta', 'reversa_redes_corte14_acta', null, jsonb_build_object('motivo', 'reversa del acta del Corte 14'), null);
"""
escribir(os.path.join(RAIZ, 'sql', '05_huellas_solo_lectura.sql'), huellas)
escribir(os.path.join(RAIZ, 'sql', '80_verificacion.sql'), verif)
escribir(os.path.join(RAIZ, 'sql', '90_reversa.sql'), reversa)
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte14_acta_editor.sql'), huellas)
escribir(os.path.join(RAIZ, 'verificacion_redes_corte14_acta_editor.sql'), verif)
escribir(os.path.join(RAIZ, 'reversa_redes_corte14_acta_editor.sql'), 'begin;\n' + reversa + 'commit;\n')
print('huella antes (Corte 14)', MD5_BASE, '· huella con el acta', md5_fin)
