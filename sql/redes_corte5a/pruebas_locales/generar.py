#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 5a con las huellas reales de la base local:
  1) rehace redes_local con lo del 4b y el doble de tecnica.puntos; toma sus huellas y el texto vivo de las 9 funciones que cambian;
  2) escribe sql/25_reemplazos.sql (texto vivo con cambios exactos, cada uno una sola vez), sql/10_esquema.sql (guardia) y los _editor de migración y ensayo;
  3) aplica la migración, toma las huellas del 5a y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py   (PostGIS local en localhost:55432)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
VIVAS = ['geoportal_puede', 'geoportal_mis_permisos', 'geoportal_admin_permisos', 'geoportal_admin_listar']
NUEVAS_RPC = ['geoportal_redes_personal_formulario']
NUEVAS_INT = ['redes.f_fusionar_ficha()', 'redes.f_candidatos_muestreo(bigint)', 'redes.f_resumen_muestreo(bigint)', 'redes.f_publicar_muestreo(bigint,text,text)',
              'redes.f_revertir_muestreo(text,text)']
MIG = ['10_esquema.sql', '20_funciones.sql', '25_reemplazos.sql', '26_rpc.sql', '40_permisos.sql']

T = {}
# ---- motor del 1a (vivo): en una recarga gana la ficha (§26.3), choques en el resumen (17c), la bandeja de nodos se conserva (17f) y la capa MUE
T['redes.f_preparar_candidatos(bigint)'] = [(
    """  create index on _cand (activo_id);
  analyze _cand;""",
    """  create index on _cand (activo_id);
  perform redes.f_fusionar_ficha();      -- Corte 5a (§26.3): en una recarga gana lo editado en la ficha; los choques quedan en _choques
  analyze _cand;""")]
T['redes.f_resumen(bigint)'] = [
    ("""  r record;
begin""", """  r record; v_ch jsonb := '[]'::jsonb;
begin"""),
    ("""  if not found then perform tecnica.f_error('No existe esa carga'); end if;
  select count(*), count(*) filter""", """  if not found then perform tecnica.f_error('No existe esa carga'); end if;
  if c.capa_codigo = 'muestreo' then return redes.f_resumen_muestreo(p_carga); end if;      -- capa MUE (Corte 5a)
  select count(*), count(*) filter"""),
    ("""    select count(*) into v_sinmat from _cand where crea_activo and material_texto is not null and material_codigo is null;""",
     """    select count(*) into v_sinmat from _cand where crea_activo and material_texto is not null and material_codigo is null;
    -- Corte 5a: choques con la ficha (gana la ficha, §26.3) y nodos ya clasificados en la bandeja (se conservan, 17f)
    select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'campo', campo, 'ficha', valor_ficha, 'capa', valor_capa) order by codigo, campo), '[]'::jsonb) into v_ch from _choques;
    if jsonb_array_length(v_ch) > 0 then
      v_avisos := v_avisos || format('%s campos editados en la ficha vienen distintos en la capa: gana la ficha (§26.3); la lista va en «choques con la ficha»', jsonb_array_length(v_ch));
    end if;
    v_extra := v_extra || jsonb_build_object('choques_con_la_ficha', jsonb_array_length(v_ch), 'nodos_clasificados_en_la_bandeja',
      (select count(*) from _cand k join redes.v_nodo_vigente n on n.sistema = k.nodo_sistema and n.llave_modelo = k.llave
        where k.crea_nodo and not k.crea_activo and k.clase_nodo = 'por_clasificar' and n.activo_id is not null));"""),
    ("""  v_tabla := v_tabla
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '7 avisos'""", """  v_tabla := v_tabla || (select coalesce(jsonb_agg(jsonb_build_object('s', '6b choques con la ficha (gana la ficha)', 'c', (x ->> 'codigo') || ' · ' || (x ->> 'campo'),
                           'v', 'ficha «' || coalesce(x ->> 'ficha', '—') || '» / capa «' || coalesce(x ->> 'capa', '—') || '»')), '[]'::jsonb)
                           from (select x from jsonb_array_elements(v_ch) x limit 200) z);
  v_tabla := v_tabla
    || (select coalesce(jsonb_agg(jsonb_build_object('s', '7 avisos'"""),
    ("""    'lista_para_publicar', cardinality(v_bloq) = 0, 'tabla', v_tabla);""", """    'lista_para_publicar', cardinality(v_bloq) = 0, 'choques', v_ch, 'tabla', v_tabla);"""),
]
T['redes.f_publicar(bigint,text,text)'] = [
    ("""  if p_motivo is null or length(btrim(p_motivo)) < 10 then perform tecnica.f_error('Escriba el motivo de la publicación (10 caracteres o más)'); end if;""",
     """  if p_motivo is null or length(btrim(p_motivo)) < 10 then perform tecnica.f_error('Escriba el motivo de la publicación (10 caracteres o más)'); end if;
  if (select capa_codigo from redes.cargas where id = p_carga) = 'muestreo' then return redes.f_publicar_muestreo(p_carga, p_autor, p_motivo); end if;      -- capa MUE (Corte 5a)"""),
    ("""  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m, capacidad, profundidad_m,
         estado_codigo, atributos, codigo_anterior, capa_codigo, llave_capa, carga_id, huella, autor)
  select activo_id, version_nueva, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m, capacidad, profundidad_m,
         estado_codigo, atributos, codigo_anterior, capa_codigo, llave, p_carga, huella, p_autor""",
     """  -- Corte 5a: la fecha de instalación y el barrio o sector (no vienen en ninguna capa) se conservan
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m, capacidad, profundidad_m,
         estado_codigo, atributos, codigo_anterior, capa_codigo, llave_capa, carga_id, huella, autor, fecha_instalacion, barrio_sector)
  select activo_id, version_nueva, geom, nombre, clase, efecto, material_codigo, diametro_mm, longitud_m, capacidad, profundidad_m,
         estado_codigo, atributos, codigo_anterior, capa_codigo, llave, p_carga, huella, p_autor, fecha_instalacion, barrio_sector"""),
    ("""     and (o.activo_id is null or o.origen is distinct from k.origen or o.aportante_codigo is distinct from k.aportante_codigo);""",
     """     and (o.activo_id is null or o.origen is distinct from k.origen or o.aportante_codigo is distinct from k.aportante_codigo)
     and not ('origen' = any (coalesce(k.campos_ficha, '{}')));      -- Corte 5a (§26.3): el origen corregido en la ficha no lo pisa la capa"""),
    ("""  -- (g) nodos:""", """  -- Corte 5a (17f): los nodos que el administrador clasificó en la bandeja (activo enlazado con un evento) conservan su activo en la recarga
  if to_regclass('pg_temp._bandeja') is not null then drop table pg_temp._bandeja; end if;
  create temp table _bandeja on commit drop as
  select k.nodo_sistema as sistema, k.llave, n.activo_id from _cand k join redes.v_nodo_vigente n on n.sistema = k.nodo_sistema and n.llave_modelo = k.llave
   where k.crea_nodo and not k.crea_activo and k.clase_nodo = 'por_clasificar' and n.activo_id is not null;
  -- (g) nodos:"""),
    ("""          or n.activo_id is distinct from (case when k.crea_activo then k.activo_id end) or n.clase_nodo <> k.clase_nodo);""",
     """          or ((n.activo_id is distinct from (case when k.crea_activo then k.activo_id end) or n.clase_nodo <> k.clase_nodo)
              and not exists (select 1 from _bandeja b where b.sistema = k.nodo_sistema and b.llave = k.llave)));"""),
    ("""  get diagnostics v_nodos = row_count;
  analyze redes.nodos;""", """  get diagnostics v_nodos = row_count;
  -- 17f: si el nodo cambió de nombre o de posición, el nodo nuevo queda enlazado al mismo activo de la bandeja
  insert into redes.nodo_eventos (nodo_id, tipo, activo_id, motivo, autor)
  select n.id, 'enlazar_activo', b.activo_id, format('Se conserva el activo de la bandeja de nodos por clasificar en la carga %s', p_carga), p_autor
    from redes.nodos n join _bandeja b on b.sistema = n.sistema and b.llave = n.llave_modelo where n.carga_id = p_carga;
  analyze redes.nodos;"""),
]
T['redes.f_revertir(text,text,text)'] = [(
    """  if p_motivo is null or length(btrim(p_motivo)) < 10 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;""",
    """  if p_motivo is null or length(btrim(p_motivo)) < 10 then perform tecnica.f_error('Escriba el motivo (10 caracteres o más)'); end if;
  if p_capa = 'muestreo' then return redes.f_revertir_muestreo(p_autor, p_motivo); end if;      -- capa MUE (Corte 5a)""")]
# ---- §28.1: el supervisor y el administrador con tope (72 h y 30 días)
T['public.geoportal_redes_formulario_intervencion(text)'] = [
    ("""'dias_atras_max', case when v_perfil in ('admin', 'supervisor') then null else redes.f_param('itv_dias_atras_max') end,""",
     """'dias_atras_max', case when v_perfil in ('admin', 'supervisor') then redes.f_param('itv_dias_atras_max_supervisor') else redes.f_param('itv_dias_atras_max') end,"""),
    ("""'max_horas', case when v_perfil in ('admin', 'supervisor') then null else redes.f_param('itv_max_horas') end,""",
     """'max_horas', redes.f_param('itv_max_horas'),"""),
]
T['public.geoportal_redes_crear_intervencion(text,uuid,jsonb,text)'] = [
    ("""  if not v_super and v_t_ini < v_ahora - make_interval(days => redes.f_param('itv_dias_atras_max')::integer) then
    perform tecnica.f_error(format('El inicio no puede ser de hace más de %s días', redes.f_param('itv_dias_atras_max')::integer));""",
     """  -- §28.1 (Corte 5a): nadie registra sin tope. El supervisor y el administrador, hasta itv_dias_atras_max_supervisor días atrás; el operador, itv_dias_atras_max
  if v_t_ini < v_ahora - make_interval(days => redes.f_param(case when v_super then 'itv_dias_atras_max_supervisor' else 'itv_dias_atras_max' end)::integer) then
    perform tecnica.f_error(format('El inicio no puede ser de hace más de %s días', redes.f_param(case when v_super then 'itv_dias_atras_max_supervisor' else 'itv_dias_atras_max' end)::integer));"""),
    ("""  if not v_super and v_t_fin - v_t_ini > make_interval(hours => redes.f_param('itv_max_horas')::integer) then
    perform tecnica.f_error(format('Una intervención dura hasta %s horas: si duró más, la registra el supervisor desde el escritorio', redes.f_param('itv_max_horas')::integer));""",
     """  if v_t_fin - v_t_ini > make_interval(hours => redes.f_param('itv_max_horas')::integer) then      -- §28.1: el mismo tope para todos
    perform tecnica.f_error(format('Una intervención dura hasta %s horas: una obra larga se registra en varias intervenciones, cada una con su foto', redes.f_param('itv_max_horas')::integer));"""),
]
# ---- §28.5: las cuadrillas también las crea el supervisor de distribución
T['public.geoportal_redes_cuadrilla_fijar(text,bigint,text,boolean,text)'] = [(
    """declare v_email text := redes.f_autorizar_admin(p_solicitante);""",
    """declare v_email text := redes.f_supervisor(p_solicitante, 'crean o cambian las cuadrillas (§28.5: también el supervisor de distribución)');""")]
T['public.geoportal_redes_catalogo(text)'] = [(
    """return jsonb_build_object('puede_editar', public.geoportal_es_admin(v_email),""",
    """return jsonb_build_object('puede_editar', public.geoportal_es_admin(v_email), 'puede_cuadrillas', true,      -- §28.5""")]
# ---- §28.2: los formularios de distribución salen de redes.formularios_distribucion
T['public.geoportal_redes_personal(text,text,text)'] = [
    ("""'formularios', jsonb_build_array(jsonb_build_object('clave', 'danos_fallas', 'nombre', 'Reportar daño o falla'), jsonb_build_object('clave', 'mantenimiento', 'nombre', 'Registrar intervención')),""",
     """'formularios', coalesce((select jsonb_agg(jsonb_build_object('clave', fd.clave, 'nombre', fd.nombre) order by fd.orden) from redes.formularios_distribucion fd where fd.activo), '[]'::jsonb),      -- §28.2"""),
    ("""'formularios', to_jsonb(array_remove(array[case when tecnica.f_formulario_asignado(p.email, 'danos_fallas') then 'danos_fallas' end,
                                                          case when tecnica.f_formulario_asignado(p.email, 'mantenimiento') then 'mantenimiento' end], null)),""",
     """'formularios', coalesce((select jsonb_agg(fd.clave order by fd.orden) from redes.formularios_distribucion fd where fd.activo and tecnica.f_formulario_asignado(p.email, fd.clave)), '[]'::jsonb),"""),
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
nombre = lambda f: f.split('(')[0].split('.')[1]  # noqa: E731

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_4b'], env=ENV, check=True, capture_output=True)
md5_4b = q(CONJ)
assert md5_4b == '55668dddf263065b5eb90aeb3001a3b7', md5_4b          # la huella del 4b que dice la bitácora
viv = dict(l.split('|') for l in q("select proname || '|' || md5(pg_get_functiondef(oid)) from pg_proc where pronamespace = 'public'::regnamespace and proname in ("
                                     + ', '.join(f"'{n}'" for n in VIVAS) + ")").splitlines())
textos_4b = {f: fdef(f) for f in CAMBIADAS}
md5_cam_4b = {f: fmd5(f) for f in CAMBIADAS}

partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5a · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- es el texto vivo de cada una con cambios exactos, cada uno aplicado una sola vez:
--   · motor del 1a (f_preparar_candidatos, f_resumen, f_publicar, f_revertir): en una recarga gana lo editado en la ficha y los choques salen en el
--     resumen (§26.3, 17c); la fecha de instalación y el barrio se conservan; el origen corregido en la ficha no se pisa; los nodos clasificados en la
--     bandeja conservan su activo (17f); la capa MUE va por sus propias funciones (20);
--   · §28.1: el supervisor y el administrador ya no registran sin tope (72 h por intervención y hasta 30 días atrás);
--   · §28.2: los formularios de Personal salen de redes.formularios_distribucion; §28.5: las cuadrillas también las crea el supervisor de distribución.
-- =====================================================================
"""]
for f in CAMBIADAS:
    t = textos_4b[f]
    for viejo, nuevo in T[f]:
        assert t.count(viejo) == 1, (f, viejo[:90], t.count(viejo))
        t = t.replace(viejo, nuevo)
    partes.append(f'\n-- {f}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))

v = {'{{MD5_CORTE_4B}}': md5_4b, '{{MD5_V_DANO}}': q("select md5(pg_get_viewdef('redes.v_dano'::regclass, true))"),
     '{{MD5_V_EPICRISIS}}': q("select md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true))"),
     '{{VIVAS_4A}}': ', '.join(f"('{n}', '{viv[n]}')" for n in VIVAS)}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte5a_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte5a_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
subprocess.run([PSQL, '-d', 'redes_local', '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte5a_editor.sql')], env=ENV, check=True, capture_output=True)
md5_5a = q(CONJ)
md5_cam_5a = {f: fmd5(f) for f in CAMBIADAS}
nue = {n: q(f"select md5(pg_get_functiondef(oid)) from pg_proc where pronamespace = 'public'::regnamespace and proname = '{n}'") for n in NUEVAS_RPC}
firma_nueva = {n: q(f"select oid::regprocedure from pg_proc where pronamespace = 'public'::regnamespace and proname = '{n}'") for n in NUEVAS_RPC}
v.update({'{{MD5_CORTE_5A}}': md5_5a,
          '{{RPC_NUEVAS}}': ', '.join(f"('{n}', '{m}')" for n, m in sorted(nue.items())),
          '{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_cam_4b[f]}', '{md5_cam_5a[f]}')" for f in CAMBIADAS),
          '{{CAMBIADAS_5A}}': ', '.join(f"('{f}', '{md5_cam_5a[f]}')" for f in CAMBIADAS),
          '{{N_CAMBIADAS}}': str(len(CAMBIADAS)),
          '{{TEXTOS_4B}}': '\n'.join(f'{textos_4b[f]};\n' for f in CAMBIADAS),
          '{{DROPS}}': '\n'.join([f'drop function {firma_nueva[n]};' for n in NUEVAS_RPC] + [f'drop function {f};' for f in NUEVAS_INT])})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte5a_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte5a_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte5a_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella 4b', md5_4b, '· huella 5a', md5_5a)
