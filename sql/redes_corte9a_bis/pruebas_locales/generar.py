#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 9a-bis con las huellas reales de la base local de Code B (emdupar_b, puerto 55442):
  1) deja emdupar_b como producción (el 9a publicado y su carga); comprueba la huella y toma el texto vivo de las funciones que cambian;
  2) escribe sql/25_reemplazos.sql (texto vivo con cambios exactos, cada uno una sola vez), sql/10_esquema.sql y los _editor;
  3) aplica la migración, toma las huellas del 9a-bis y escribe 05, 80 y 90 (y sus _editor).
Uso: python3 -I generar.py     Sobre otra huella de producción: MD5_BASE=<huella> python3 -I generar.py (con la plantilla rehecha)."""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = os.environ.get('BASE_B', 'emdupar_b')
ENV = dict(os.environ, PGHOST='localhost', PGPORT=os.environ.get('PGPORT_B', '55442'), PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
assert ENV['PGPORT'] != '55432', 'El puerto 55432 es de Code A'
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_BASE = os.environ.get('MD5_BASE', '4a46069fc3c71c305c49bafd764f316e')      # producción desde la publicación del 9a (16-nov)
NUEVAS = ['redes.f_nodo_visible_id(bigint)', 'redes.f_nodo_de_activo(bigint)', 'redes.f_tramos_de_nodo(bigint)', 'redes.f_sector_en(numeric,numeric)',
          'redes.f_operador_redes(text)', 'public.geoportal_redes_sector_en(text,numeric,numeric)', 'public.geoportal_redes_nodos_clasificar_grupo(text,text,text,text)']
MIG = ['10_esquema.sql', '20_funciones.sql', '26_rpc.sql', '25_reemplazos.sql', '40_permisos.sql']
SUP_NODOS = "redes.f_supervisor(p_solicitante, 'clasifica nodos')"      # respuesta 1 de David: el supervisor de distribución y el administrador
LECTURA_NODO = ("""  select * into n from redes.v_nodo_visible where nodo_id = p_nodo;""", """  select * into n from redes.f_nodo_visible_id(p_nodo);      -- 9a-bis: por la llave del nodo (índice)""")

T = {}
# ---- la ficha: el nodo y los tramos por índice (antes recorría las vistas enteras: 4,4 s en producción); el sector hidráulico es el oficial; la referencia
#      del Plan, como los demás datos del modelo, solo para supervisor y administrador (regla del 1b; el operador ve la ficha en modo buscar)
T['redes.f_ficha(bigint,text)'] = [
    ("""           'tramos', (select count(*) from redes.v_tramo_nodos_vigente x where x.nodo_ini = n.nodo_id or x.nodo_fin = n.nodo_id))
    into v_nodo from redes.v_nodo_visible n where n.activo_id = p_activo limit 1;""",
     """           'tramos', redes.f_tramos_de_nodo(n.nodo_id))
    into v_nodo from redes.f_nodo_de_activo(p_activo) n limit 1;      -- 9a-bis: por índice"""),
    ("""from redes.v_nodo_visible n where n.nodo_id = tn.nodo_ini),""", """from redes.f_nodo_visible_id(tn.nodo_ini) n),"""),
    ("""from redes.v_nodo_visible n where n.nodo_id = tn.nodo_fin))
    into v_tramo from redes.v_tramo_nodos_vigente tn where tn.activo_id = p_activo;""",
     """from redes.f_nodo_visible_id(tn.nodo_fin) n))
    into v_tramo from redes.tramo_nodos tn join redes.activo_vigente_mat tv on tv.activo_id = tn.activo_id and tv.version = tn.version where tn.activo_id = p_activo;"""),
    ("""    -- Corte 9a: nada de esto está en la ficha oficial; se lee de las tablas de referencia y de los polígonos vigentes de sectores
    'sector_plan', case""",
     """    -- Corte 9a: se lee de las tablas de referencia y de los polígonos vigentes de sectores. 9a-bis: el sector hidráulico (por la ubicación) es el oficial
    'sector_hidraulico', case"""),
    ("""    'referencia', nullif(redes.f_ficha_referencia(p_activo), '[]'::jsonb),""",
     """    'referencia', case when v_super then nullif(redes.f_ficha_referencia(p_activo), '[]'::jsonb) end,"""),
]
T['public.geoportal_redes_tramo_nodos(text,text)'] = [(
    """                         from redes.v_tramo_nodos_vigente tn
                         cross join lateral (values ('inicio', 1, tn.nodo_ini), ('fin', 2, tn.nodo_fin)) x(rol, o, nodo)
                         join redes.v_nodo_visible n on n.nodo_id = x.nodo""",
    """                         from redes.tramo_nodos tn join redes.activo_vigente_mat tv on tv.activo_id = tn.activo_id and tv.version = tn.version      -- 9a-bis: por índice
                         cross join lateral (values ('inicio', 1, tn.nodo_ini), ('fin', 2, tn.nodo_fin)) x(rol, o, nodo)
                         cross join lateral redes.f_nodo_visible_id(x.nodo) n""")]
T['public.geoportal_redes_nodo_crear_activo(text,bigint,text,text,text,text)'] = [
    ("""  v_email text := redes.f_autorizar_admin(p_solicitante);""", f"""  v_email text := {SUP_NODOS};"""), LECTURA_NODO]
T['public.geoportal_redes_nodo_preliminar(text,bigint)'] = [
    ("""declare v_email text := redes.f_autorizar_admin(p_solicitante);""", f"""declare v_email text := {SUP_NODOS};"""), LECTURA_NODO]
T['public.geoportal_redes_nodo_clasificar(text,bigint,text,text)'] = [
    ("""declare v_email text := redes.f_autorizar_admin(p_solicitante);""", f"""declare v_email text := {SUP_NODOS};"""), LECTURA_NODO]
T['public.geoportal_redes_nodos_por_clasificar(text,text,bigint,integer)'] = [
    ("""declare v_email text := redes.f_autorizar_admin(p_solicitante);""", f"""declare v_email text := {SUP_NODOS};"""),
    ("""    'total', (select count(*) from fil),""",
     """    -- 9a-bis: los grupos que se pueden confirmar de una vez (solo «no crear activo»)
    'grupos_no_crear', coalesce((select jsonb_agg(jsonb_build_object('grupo', g.grupo, 'texto', g.texto, 'n', g.n) order by g.n desc)
                                   from (select b.sug ->> 'grupo' as grupo, min(b.sug ->> 'texto') as texto, count(*) as n from base b
                                          where b.sug ->> 'accion' = 'no_crear' and b.sug ? 'grupo' group by 1) g), '[]'::jsonb),
    'total', (select count(*) from fil),""")]
T['redes.f_pm_sugerencia(text,text,text,text)'] = [
    ("""'clase', 'propuesta_plan', 'texto', 'Tanque proyectado por el Plan (no construido): no crear activo')""",
     """'clase', 'propuesta_plan', 'grupo', 'tanque_proyectado', 'texto', 'Tanque proyectado por el Plan (no construido): no crear activo')"""),
    ("""'clase', 'propuesta_plan', 'texto', 'Válvula propuesta por el Plan (no instalada): no crear activo')""",
     """'clase', 'propuesta_plan', 'grupo', 'valvula_propuesta', 'texto', 'Válvula propuesta por el Plan (no instalada): no crear activo')"""),
    ("""'clase', 'propuesta_plan', 'texto', 'Macromedidor proyectado por el Plan (no instalado): no crear activo')""",
     """'clase', 'propuesta_plan', 'grupo', 'macro_proyectado', 'texto', 'Macromedidor proyectado por el Plan (no instalado): no crear activo')""")]
T['public.geoportal_redes_danos(text,text,integer)'] = [("""'sector_plan', (select""", """'sector_hidraulico', (select""")]
T['public.geoportal_redes_intervenciones(text,text,integer)'] = [("""'sector_plan', (select""", """'sector_hidraulico', (select""")]
T['public.geoportal_redes_contrato_tarjeta(text,text,text)'] = [(
    """    'sector_plan', (select jsonb_build_object('sector', s.sector, 'subsector', s.subsector)      -- Corte 9a: el sector del contrato es el de su tramo (por geometría)""",
    """    'sector_hidraulico', (select jsonb_build_object('sector', s.sector, 'subsector', s.subsector)      -- Corte 9a: el sector del contrato es el de su tramo (por geometría)""")]
T['public.geoportal_redes_referencia(text,text,text)'] = [
    ("""(9, 'Sector según el Plan',""", """(9, 'Sector hidráulico',"""),
    ("""jsonb_build_object('r', 'Sector según el Plan',""", """jsonb_build_object('r', 'Sector hidráulico',""")]
T['public.geoportal_redes_mi_perfil(text)'] = [(
    """                            'geovisor', redes.f_geovisor_lectura(p.email));      -- Corte 6a""",
    """                            'geovisor', redes.f_geovisor_lectura(p.email),      -- Corte 6a
                            -- 9a-bis: la Ficha de activos en modo buscar (solo lectura) también para el operador de redes
                            'ficha_buscar', p.perfil in ('admin', 'supervisor') or redes.f_operador_redes(p.email));""")]
# ---- respuesta 4 de David: el sector del daño sale de la ubicación; el número escrito a mano queda de respaldo
T['public.geoportal_redes_crear_dano(text,uuid,jsonb,text)'] = [(
    """    v_sector := (d ->> 'sector')::smallint;
  end if;
""",
    """    v_sector := (d ->> 'sector')::smallint;
  end if;
  -- 9a-bis (David, 16-nov): el formulario propone el sector hidráulico de la ubicación; si no llega ninguno, se toma de la ubicación (sin polígono, queda vacío)
  if v_sector is null then select s.sector into v_sector from redes.f_sector_en(v_lat, v_lon) s; end if;
""")]
T['public.geoportal_redes_reporte_convertir(text,uuid,jsonb)'] = [
    ("""         riesgo, causa_clase, descripcion, origen, reporte_externo_id, autor)""", """         riesgo, causa_clase, descripcion, origen, reporte_externo_id, autor, sector_num)"""),
    ("""          'bot', p_reporte, p.email);""", """          'bot', p_reporte, p.email, (select s.sector from redes.f_sector_en(v_lat, v_lon) s));      -- 9a-bis: el sector de la ubicación""")]
CAMBIADAS = list(T)


def q(sql):
    return subprocess.run([PSQL, '-d', BASE, '-AtX', '-c', sql], env=ENV, check=True, capture_output=True, text=True).stdout.strip()


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

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')], env=ENV, check=True, capture_output=True)
assert q(CONJ) == MD5_BASE, q(CONJ)
antes = {f: fdef(f) for f in CAMBIADAS}
md5_antes = {f: fmd5(f) for f in CAMBIADAS}
nota_antes = q("select nombre || '|' || nota from redes.geovisor_capas where codigo = 'sectores'").split('|', 1)

partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 9a-bis · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el del 9a publicado) con cambios exactos, aplicados una sola vez.
--   · redes.f_ficha y geoportal_redes_tramo_nodos: el nodo y los tramos por índice (la ficha tardaba 4,4 s en producción); «sector_hidraulico» (antes «sector_plan»);
--     la referencia del Plan solo para supervisor y administrador;
--   · nodos (crear el activo, ficha preliminar, clasificar y la bandeja): también el supervisor de distribución; la bandeja trae los grupos de «no crear activo»;
--   · redes.f_pm_sugerencia: el grupo de cada sugerencia de «no crear activo»;
--   · daños, intervenciones, tarjeta del contrato y tarjeta de referencia: «sector hidráulico» (el oficial);
--   · geoportal_redes_mi_perfil: «ficha_buscar» (la Ficha de activos en modo buscar para el operador de redes);
--   · crear el daño y convertir el reporte del bot: el sector sale de la ubicación si no viene escrito.
-- ====================================================================="""]
for f in CAMBIADAS:
    t = antes[f]
    for viejo, nuevo in T[f]:
        assert t.count(viejo) == 1, (f, viejo[:90], t.count(viejo))
        t = t.replace(viejo, nuevo)
    partes.append(f'\n-- {f}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))

v = {'{{MD5_BASE}}': MD5_BASE}
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte9a_bis_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte9a_bis_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
p = subprocess.run([PSQL, '-d', BASE, '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte9a_bis_editor.sql')], env=ENV, capture_output=True, text=True)
if p.returncode != 0:
    raise SystemExit(p.stderr[-3000:])
md5_bis = q(CONJ)
md5_despues = {f: fmd5(f) for f in CAMBIADAS}
md5_nuevas = {f: fmd5(f) for f in NUEVAS}
lit = lambda s: "'" + s.replace("'", "''") + "'"  # noqa: E731
v.update({'{{MD5_BIS}}': md5_bis,
          '{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_antes[f]}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{CAMBIADAS_BIS}}': ', '.join(f"('{f}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{N_CAMBIADAS}}': str(len(CAMBIADAS)),
          '{{NUEVAS}}': ', '.join(f"('{f}', '{md5_nuevas[f]}')" for f in NUEVAS),
          '{{N_NUEVAS}}': str(len(NUEVAS)),
          '{{DROPS}}': '\n'.join(f'drop function {f};' for f in reversed(NUEVAS)),
          '{{NOMBRE_CAPA_ANTES}}': lit(nota_antes[0]), '{{NOTA_CAPA_ANTES}}': lit(nota_antes[1]),
          '{{TEXTOS_ANTES}}': '\n'.join(f'{antes[f]};\nrevoke all on function {f} from public, anon, authenticated, service_role;\n'
                                        + (f'grant execute on function {f} to service_role;\n' if f.startswith('public.') else '') for f in CAMBIADAS)})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte9a_bis_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte9a_bis_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte9a_bis_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella antes (9a, producción)', MD5_BASE, '· huella 9a-bis', md5_bis)
