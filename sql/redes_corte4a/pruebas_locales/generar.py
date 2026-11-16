#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 4a con las huellas reales de la base local:
  1) rehace redes_local con lo publicado (1a, 2, 3a, 3b) y el doble de las 4 funciones de permisos vivas; toma sus huellas y los textos vivos;
  2) escribe sql/25_reemplazos.sql: las RPC del 3b que cambian, como su texto vivo con cambios exactos (cada cambio debe aparecer una sola vez);
  3) escribe sql/10_esquema.sql (guardia) y los _editor de migración y ensayo;
  4) aplica la migración, toma las huellas del 4a y escribe 05, 80 y 90 (y sus _editor).
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
NUEVAS = ['geoportal_redes_mi_perfil', 'geoportal_redes_danos', 'geoportal_redes_dano_evento', 'geoportal_redes_dano_tercero', 'geoportal_redes_intervencion_evento',
          'geoportal_redes_reportes_bot', 'geoportal_redes_crear_activo_bandeja']
CAMBIADAS = ['geoportal_redes_formulario_dano', 'geoportal_redes_preparar_dano', 'geoportal_redes_crear_dano', 'geoportal_redes_formulario_intervencion',
             'geoportal_redes_danos_abiertos', 'geoportal_redes_preparar_intervencion', 'geoportal_redes_crear_intervencion', 'geoportal_redes_perfil',
             'geoportal_redes_galeria', 'geoportal_redes_ficha_editar']
INTERNAS_CAMBIADAS = ['redes.f_perfil_lectura(text)', 'redes.f_editor_ficha(text)']
MIG = ['10_esquema.sql', '15_permisos.sql', '24_perfiles.sql', '25_reemplazos.sql', '26_bandejas.sql', '40_permisos.sql']

CAPTURA = [("tecnica.f_autorizar_captura(", "redes.f_autorizar_captura_redes(")]
SUPER = [("tecnica.f_perfil(v_email) in ('admin', 'supervisor')", "redes.f_es_supervisor_redes(v_email)")]
SIN_EVIDENCIA_DANO = ("""  if v_n = 0 and v_super then
    if v_sinev is null or length(v_sinev) not between 10 and 300 then
      perform tecnica.f_error('Sin fotos, escriba por qué no hay evidencia fotográfica (10 a 300 caracteres), por ejemplo «llegó por la línea 116»');
    end if;
  elsif v_n < redes.f_param('min_fotos_dano')""", """  -- §25.8: nadie registra «sin evidencia fotográfica»; lo que llega sin foto entra por el reporte de anomalías
  if v_sinev is not null then
    perform tecnica.f_error('Ya no se registra «sin evidencia fotográfica»: tome al menos una foto del daño (lo que llega sin foto entra por el reporte de anomalías)');
  end if;
  if v_n < redes.f_param('min_fotos_dano')""")
SIN_EVIDENCIA_DANO_2 = ("""  elsif v_sinev is not null then
    perform tecnica.f_error('Con fotos, no marque «sin evidencia fotográfica»');
  end if;
  if v_n > 0 and (select count(distinct""", """  end if;
  if v_n > 0 and (select count(distinct""")
SECTOR_DANO = [
    ("""  -- tamaño, afectación, riesgo y causa
""", """  -- §25.1: el sector es un número entero del 1 al 100 (hoy 1 a 7). El texto viejo (sector_texto) ya no se llena.
  if d -> 'sector' is not null and jsonb_typeof(d -> 'sector') <> 'null' then
    if jsonb_typeof(d -> 'sector') <> 'number' or (d ->> 'sector') !~ '^[0-9]{1,3}$' or (d ->> 'sector')::integer not between 1 and 100 then
      perform tecnica.f_error('El sector es un número entero del 1 al 100');
    end if;
    v_sector := (d ->> 'sector')::smallint;
  end if;
  -- tamaño, afectación, riesgo y causa
"""),
    ("""t_inicio_dano, t_detectado, inicio_en, inicio_origen, tipo_rotura, largo_afectado_m, presion_mca, usuarios_sin_servicio, sector_texto,""",
     """t_inicio_dano, t_detectado, inicio_en, inicio_origen, tipo_rotura, largo_afectado_m, presion_mca, usuarios_sin_servicio, sector_texto, sector_num,"""),
    ("""          nullif(btrim(coalesce(d ->> 'sector', '')), ''), d ->> 'riesgo',""", """          null, v_sector, d ->> 'riesgo',"""),
    ("""v_sinev text := nullif(btrim(coalesce(d ->> 'sin_evidencia_motivo', '')), '');
begin""", """v_sinev text := nullif(btrim(coalesce(d ->> 'sin_evidencia_motivo', '')), '');
  v_sector smallint;
begin"""),
]
TRANSFORMA = {
    'geoportal_redes_formulario_dano': CAPTURA,
    'geoportal_redes_preparar_dano': CAPTURA + [("""  v_min := case when tecnica.f_perfil(v_email) in ('admin', 'supervisor') then 0 else redes.f_param('min_fotos_dano')::integer end;""",
                                                  """  v_min := redes.f_param('min_fotos_dano')::integer;      -- §25.8: al menos una foto, para todos""")],
    'geoportal_redes_crear_dano': CAPTURA + SUPER + [SIN_EVIDENCIA_DANO, SIN_EVIDENCIA_DANO_2] + SECTOR_DANO,
    'geoportal_redes_formulario_intervencion': CAPTURA + [
        ("""declare v_email text := redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento'); v_perfil text := tecnica.f_perfil(v_email);""",
         """declare v_email text := redes.f_autorizar_captura_redes(p_solicitante, 'mantenimiento');
        v_perfil text := case when public.geoportal_es_admin(v_email) then 'admin' when redes.f_es_supervisor_redes(v_email) then 'supervisor' else 'operador' end;"""),
        ("""                                 'min_fotos', case when v_perfil in ('admin', 'supervisor') then 0 else redes.f_param('min_fotos_itv') end,
                                 'puede_sin_fotos', v_perfil in ('admin', 'supervisor'),""",
         """                                 'min_fotos', redes.f_param('min_fotos_itv'), 'puede_sin_fotos', false,"""),      # §25.8: al menos una foto, para todos
    ],
    'geoportal_redes_danos_abiertos': CAPTURA,
    'geoportal_redes_preparar_intervencion': CAPTURA + [("""  v_min := case when tecnica.f_perfil(v_email) in ('admin', 'supervisor') then 0 else redes.f_param('min_fotos_itv')::integer end;""",
                                                          """  v_min := redes.f_param('min_fotos_itv')::integer;      -- §25.8: al menos una foto, para todos""")],
    'geoportal_redes_crear_intervencion': CAPTURA + [
        ("""  v_super := tecnica.f_perfil(v_email) in ('admin', 'supervisor');""", """  v_super := redes.f_es_supervisor_redes(v_email);"""),
        ("""  if v_nf = 0 then
    if not v_super then perform tecnica.f_error(format('Tome al menos %s foto de la intervención', redes.f_param('min_fotos_itv')::integer)); end if;
    if v_sinev is null or length(v_sinev) not between 10 and 300 then
      perform tecnica.f_error('Sin fotos, escriba por qué no hay evidencia fotográfica (10 a 300 caracteres)');
    end if;
  elsif v_nf < redes.f_param('min_fotos_itv') and not v_super then
    perform tecnica.f_error(format('Tome al menos %s foto de la intervención', redes.f_param('min_fotos_itv')::integer));
  elsif v_sinev is not null then
    perform tecnica.f_error('Con fotos, no marque «sin evidencia fotográfica»');
  end if;""", """  -- §25.8: nadie registra «sin evidencia fotográfica» (ni el supervisor ni el administrador); siempre al menos una foto
  if v_sinev is not null then
    perform tecnica.f_error('Ya no se registra «sin evidencia fotográfica»: tome al menos una foto de la intervención');
  end if;
  if v_nf < redes.f_param('min_fotos_itv') then
    perform tecnica.f_error(format('Tome al menos %s foto de la intervención', redes.f_param('min_fotos_itv')::integer));
  end if;"""),
    ],
    # §26.1: la galería y la foto principal también para el operador (lectura auditada y URL de 60 s); §26.2: el supervisor de distribución edita, el origen solo el administrador
    'geoportal_redes_perfil': [
        ("""  v_super := p.perfil in ('admin', 'supervisor'); v_edita := p.perfil = 'admin';""", """  v_super := true; v_edita := p.perfil in ('admin', 'supervisor');      -- §26: fotos para todos; edita el supervisor de distribución"""),
        ("""  if v_edita then
    select * into o from redes.v_activo_origen_vigente where activo_id = v_id;""", """  if v_edita then
    if p.perfil = 'admin' then select * into o from redes.v_activo_origen_vigente where activo_id = v_id; end if;      -- el origen solo el administrador"""),
        ("""      'max_bytes_foto', redes.f_param('max_bytes_foto_perfil')) end));""", """      'max_bytes_foto', redes.f_param('max_bytes_foto_perfil'), 'puede_origen', p.perfil = 'admin') end));"""),
    ],
    'geoportal_redes_galeria': [("""declare v_email text := redes.f_supervisor(p_solicitante, 'ven la galería de fotos del activo');""",
                                 """declare v_email text := (redes.f_perfil_lectura(p_solicitante)).email;""")],      # §26.1: también el operador (la lectura queda auditada)
    'geoportal_redes_ficha_editar': [("""  if jsonb_typeof(c) <> 'object' or c = '{}'::jsonb then perform tecnica.f_error('No hay cambios'); end if;""",
                                      """  if jsonb_typeof(c) <> 'object' or c = '{}'::jsonb then perform tecnica.f_error('No hay cambios'); end if;
  if c ? 'origen' and not public.geoportal_es_admin(v_email) then raise exception 'El origen del activo solo lo corrige el administrador' using errcode = '42501'; end if;      -- §26.2""")],
}


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


def md5s(nombres, esquema='public'):
    filas = [l.split('|') for l in q(f"select proname || '|' || md5(pg_get_functiondef(oid)) from pg_proc where pronamespace = '{esquema}'::regnamespace and proname in ("
                                     + ', '.join(f"'{n}'" for n in nombres) + ") order by 1").splitlines()]
    assert len(filas) == len(nombres), filas
    return dict(filas)


fdef = lambda firma: q(f"select pg_get_functiondef('{firma}'::regprocedure)").rstrip()  # noqa: E731
firma = lambda n: q(f"select oid::regprocedure from pg_proc where pronamespace = 'public'::regnamespace and proname = '{n}'")  # noqa: E731

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_3b'], env=ENV, check=True, capture_output=True)
md5_3b = q(CONJ)
viv = md5s(VIVAS)
textos_3b = {n: fdef(firma(n)) for n in CAMBIADAS}
textos_int_3b = {f: fdef(f) for f in INTERNAS_CAMBIADAS}
textos_vivas = {n: fdef(firma(n)) for n in VIVAS}
firmas_vivas = {n: firma(n) for n in VIVAS}
cam_3b = md5s(CAMBIADAS)

# 25: los reemplazos (texto vivo del 3b con los cambios exactos)
partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 4a · 25 — REEMPLAZOS DE RPC DEL 3b (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- es el texto vivo de cada una con cambios exactos, cada uno aplicado una sola vez:
--   · captura con redes.f_autorizar_captura_redes (el supervisor de distribución pasa sin el formulario asignado);
--   · «supervisor» = administrador o supervisor de distribución (redes.f_es_supervisor_redes), no el de planta;
--   · §25.8: nadie registra «sin evidencia fotográfica»; siempre al menos una foto (daño e intervención);
--   · §25.1: el sector del daño es un número del 1 al 100 (columna nueva sector_num);
--   · §26.1: la galería y la foto principal también para el operador; §26.2: edita el supervisor de distribución; el origen solo el administrador.
-- =====================================================================
"""]
for n in CAMBIADAS:
    t = textos_3b[n]
    for viejo, nuevo in TRANSFORMA[n]:
        assert t.count(viejo) >= 1, (n, viejo[:80])
        if viejo in ('tecnica.f_autorizar_captura(',):
            t = t.replace(viejo, nuevo)
        else:
            assert t.count(viejo) == 1, (n, viejo[:80], t.count(viejo))
            t = t.replace(viejo, nuevo)
    assert 'tecnica.f_autorizar_captura(' not in t and "tecnica.f_perfil(v_email) in ('admin', 'supervisor')" not in t, n
    partes.append(f'\n-- {n}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))

v = {'{{MD5_CORTE_3B}}': md5_3b, '{{MD5_V_DANO}}': q("select md5(pg_get_viewdef('redes.v_dano'::regclass, true))"),
     '{{MD5_V_EPICRISIS}}': q("select md5(pg_get_viewdef('redes.v_epicrisis'::regclass, true))")}
v.update({'{{MD5_' + n.upper() + '}}': viv[n] for n in VIVAS})
escribir(os.path.join(RAIZ, 'sql', '10_esquema.sql'), plantilla('10_esquema.sql', v))
escribir(os.path.join(RAIZ, 'migracion_redes_corte4a_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte4a_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
subprocess.run([PSQL, '-d', 'redes_local', '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte4a_editor.sql')], env=ENV, check=True, capture_output=True)
md5_4a = q(CONJ)
viv_4a = md5s(VIVAS)
nue, cam_4a = md5s(NUEVAS), md5s(CAMBIADAS)
v.update({'{{MD5_CORTE_4A}}': md5_4a,
          '{{VIVAS}}': ', '.join(f"('{n}', '{viv[n]}', '{viv_4a[n]}')" for n in VIVAS),
          '{{RPC_NUEVAS}}': ', '.join(f"('{n}', '{m}')" for n, m in sorted(nue.items())),
          '{{RPC_CAMBIADAS}}': ', '.join(f"('{n}', '{cam_3b[n]}', '{cam_4a[n]}')" for n in sorted(CAMBIADAS)),
          '{{RPC_TODAS_4A}}': ', '.join(f"('{n}', '{m}')" for n, m in sorted({**nue, **cam_4a}.items())),
          '{{VIVAS_4A}}': ', '.join(f"('{n}', '{viv_4a[n]}')" for n in VIVAS),
          '{{TEXTOS_RPC_3B}}': '\n'.join(f'{textos_3b[n]};\n' for n in CAMBIADAS),
          '{{TEXTOS_INTERNAS_3B}}': '\n'.join(f'{t};\n' for t in textos_int_3b.values()),
          '{{FIRMA_ADMIN_PERMISOS_4A}}': firma('geoportal_admin_permisos'),
          '{{TEXTO_PUEDE}}': textos_vivas['geoportal_puede'] + ';', '{{TEXTO_MIS_PERMISOS}}': textos_vivas['geoportal_mis_permisos'] + ';',
          '{{TEXTO_ADMIN_PERMISOS}}': textos_vivas['geoportal_admin_permisos'] + ';', '{{TEXTO_ADMIN_LISTAR}}': textos_vivas['geoportal_admin_listar'] + ';',
          '{{FIRMA_ADMIN_PERMISOS_VIVA}}': firmas_vivas['geoportal_admin_permisos']})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte4a_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte4a_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte4a_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella 3b', md5_3b, '· huella 4a', md5_4a, '· permisos vivos', viv)
