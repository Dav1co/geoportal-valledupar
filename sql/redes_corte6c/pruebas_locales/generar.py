#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 6c con las huellas reales de la base local:
  1) rehace redes_local como producción (6b + hotfix de safeupdate); comprueba la huella 8113af17… y toma el texto vivo de las funciones que cambian o se retiran;
  2) escribe sql/25_reemplazos.sql (texto vivo con cambios exactos, cada uno una sola vez), sql/10_esquema.sql (guardia) y los _editor de migración y ensayo;
  3) aplica la migración, toma las huellas del 6c y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py   (PostGIS local en localhost:55432)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
NUEVAS = ['redes.f_contrato_uso(text,text)', 'redes.f_funciones_sin_where()']
RETIRADAS = ['redes.f_refrescar_contratos_capa()', 'redes.f_contratos_capa_al_dia()']      # en este orden las vuelve a crear la reversa
MIG = ['10_esquema.sql', '26_rpc.sql', '25_reemplazos.sql', '30_retiros.sql', '40_permisos.sql']
MD5_HOTFIX = '8113af17c6bd862d62a6cbc4bc4cba1f'      # producción el 16-nov (6b + hotfix de safeupdate)
MD5_6B = 'fca28bf695d1fcfa153f1113ce821528'

T = {}
# ---- 1. configuración del geovisor: ya no rehace nada (vuelve a ser STABLE) y no informa el estado de una copia que ya no existe
T['public.geoportal_redes_geovisor(text)'] = [
    ("""\n SECURITY DEFINER\n""", """\n STABLE SECURITY DEFINER\n"""),
    ("""  if a.completo then perform redes.f_contratos_capa_al_dia(); end if;      -- Corte 6b: la capa de contratos se rehace sola si cambió la ficha o tiene más de un día\n""", ''),
    ("""    'contratos_capa', case when a.completo then (select jsonb_build_object('filas', e.filas, 'calculado_en', e.calculado_en) from redes.contratos_capa_estado e where e.id = 1) end,\n""", ''),
]
# ---- 2. tesela de contratos: al vuelo, solo con los predios de su recuadro (GiST del catastro) y, por cada uno, su ficha y su último corte de cartera por índice
T['public.geoportal_redes_geovisor_mvt_contratos(text,integer,integer,integer)'] = [
    ("""declare a record; v_env geometry; v bytea;""", """declare a record; v_env geometry; v_env4 geometry; v bytea;"""),
    ("""  select ST_AsMVT(t, 'contratos', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(c.geom, 3857), v_env, 4096, 32, true) as geom, c.contrato, coalesce(c.uso, '') as uso, c.estado,
           c.consumo_prom::real as consumo, c.medidor_anios as medidor_anios
      from redes.contratos_capa c where c.geom && ST_Transform(v_env, 4326)) t
   where t.geom is not null;""",
     """  v_env4 := ST_Transform(v_env, 4326);
  -- Corte 6c: sin copia derivada. Un punto por contrato (el predio de menor id); sin el comodín (99999999) ni el «0»; sin nombre, dirección ni deuda.
  select ST_AsMVT(t, 'contratos', 4096, 'geom') into v from (
    select ST_AsMVTGeom(ST_Transform(c.geom, 3857), v_env, 4096, 32, true) as geom, c.cod_usuario as contrato,
           coalesce(redes.f_contrato_uso(f.uso, cs.categoria), '') as uso, redes.f_estado_contrato(cs.estado) as estado,
           f.cons_prom::real as consumo, f.medidor_anios as medidor_anios
      from public.catastro_valledupar c
      left join bi_interno.ficha_contrato f on f.contrato = c.cod_usuario
      left join lateral (select s.estado, s.categoria from public.cartera_suscripcion s where s.contrato = c.cod_usuario order by s.periodo_carga desc nulls last limit 1) cs on true
     where c.geom && v_env4 and c.cod_usuario ~ '^[0-9]{1,12}$' and c.cod_usuario not in ('0', '99999999')
       and c.id = (select min(c2.id) from public.catastro_valledupar c2 where c2.cod_usuario = c.cod_usuario and c2.geom is not null)) t
   where t.geom is not null;"""),
]
# ---- 3. tarjeta del contrato: el estado y el uso se leen en el momento (cartera y ficha); «está en la capa» = tiene predio con punto en el catastro
T['public.geoportal_redes_contrato_tarjeta(text,text,text)'] = [
    ("""declare a record; c redes.contratos_capa%rowtype; cs record;""", """declare a record; cs record;"""),
    ("""  select * into c from redes.contratos_capa where contrato = v_c;
  if not found then perform tecnica.f_error('Ese contrato no está en la capa de contratos', 'P0002'); end if;""",
     """  if v_c in ('0', '99999999') or not exists (select 1 from public.catastro_valledupar cv where cv.cod_usuario = v_c and cv.geom is not null) then
    perform tecnica.f_error('Ese contrato no está en la capa de contratos', 'P0002');
  end if;"""),
    ("""    'estado', c.estado, 'estado_texto',""", """    'estado', redes.f_estado_contrato(cs.estado), 'estado_texto',"""),
    ("""    'uso', c.uso,""", """    'uso', redes.f_contrato_uso(f.uso, cs.categoria),"""),
]
CAMBIADAS = list(T)


def q(sql):
    return subprocess.run([PSQL, '-d', 'redes_local', '-AtX', '-c', sql], env=ENV, check=True, capture_output=True, text=True).stdout.strip()


def leer(n):
    return open(os.path.join(RAIZ, 'sql', n), encoding='utf-8').read()


def escribir(ruta, texto):
    open(ruta, 'w', encoding='utf-8').write(texto)


def plantilla(nombre, val):
    t = open(os.path.join(AQUI, 'plantillas', nombre), encoding='utf-8').read()
    for k, v in val.items():
        t = t.replace(k, v)
    assert '{{' not in t, nombre
    return t


fdef = lambda f: q(f"select pg_get_functiondef('{f}'::regprocedure)").rstrip()  # noqa: E731
fmd5 = lambda f: q(f"select md5(pg_get_functiondef('{f}'::regprocedure))")  # noqa: E731

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_hotfix'], env=ENV, check=True, capture_output=True)
assert q(CONJ) == MD5_HOTFIX, q(CONJ)          # la huella de producción que dice el encargo
textos_antes = {f: fdef(f) for f in CAMBIADAS + RETIRADAS}
md5_antes = {f: fmd5(f) for f in CAMBIADAS}

partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 6c · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (6b + hotfix) con cambios exactos, aplicados una sola vez:
--   · geoportal_redes_geovisor: ya no rehace la capa de contratos (vuelve a ser STABLE: solo lee) ni informa el estado de la copia;
--   · geoportal_redes_geovisor_mvt_contratos: la tesela se arma al vuelo con los predios de su recuadro (catastro, ficha y último corte de cartera);
--   · geoportal_redes_contrato_tarjeta: el estado y el uso se leen en el momento; ya no depende de la copia.
-- ====================================================================="""]
for f in CAMBIADAS:
    t = textos_antes[f]
    for viejo, nuevo in T[f]:
        assert t.count(viejo) == 1, (f, viejo[:90], t.count(viejo))
        t = t.replace(viejo, nuevo)
    partes.append(f'\n-- {f}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))

v = {'{{MD5_HOTFIX}}': MD5_HOTFIX, '{{MD5_CORTE_6B}}': MD5_6B}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte6c_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte6c_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
subprocess.run([PSQL, '-d', 'redes_local', '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte6c_editor.sql')], env=ENV, check=True, capture_output=True)
md5_6c = q(CONJ)
md5_despues = {f: fmd5(f) for f in CAMBIADAS}
md5_nuevas = {f: fmd5(f) for f in NUEVAS}
v.update({'{{MD5_CORTE_6C}}': md5_6c,
          '{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_antes[f]}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{CAMBIADAS_6C}}': ', '.join(f"('{f}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{N_CAMBIADAS}}': str(len(CAMBIADAS)),
          '{{NUEVAS}}': ', '.join(f"('{f}', '{md5_nuevas[f]}')" for f in NUEVAS),
          '{{N_NUEVAS}}': str(len(NUEVAS)),
          '{{TEXTOS_ANTES}}': '\n'.join(f'{textos_antes[f]};\nrevoke all on function {f} from public, anon, authenticated, service_role;\n'
                                        + (f'grant execute on function {f} to service_role;\n' if f.startswith('public.') else '') for f in RETIRADAS + CAMBIADAS)})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte6c_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte6c_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte6c_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella antes (6b + hotfix)', MD5_HOTFIX, '· huella 6c', md5_6c)
