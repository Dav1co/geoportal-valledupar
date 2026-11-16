#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 5d (la línea 116) con las huellas reales de la base local de Code B (emdupar_b, puerto 55442):
  1) deja emdupar_b como producción (9a-bis publicado + lo del Corte 8); comprueba la huella y toma el texto vivo de las funciones que cambian;
  2) escribe sql/25_reemplazos.sql (texto vivo con cambios exactos, cada uno una sola vez), sql/10_esquema.sql y los _editor;
  3) aplica la migración, toma las huellas del 5d y escribe 05, 80 y 90 (y sus _editor).
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
MD5_BASE = os.environ.get('MD5_BASE', '814eac39ac5deae2943751b8c190f969')      # producción desde la publicación del 9a-bis (16-nov)
NUEVAS = ['redes.f_dir_norm(text)', 'redes.f_dir_base(text)', 'redes.f_barrio_norm(text)', 'redes.f_l116_atributos(jsonb)', 'redes.f_l116_fecha(text)',
          'redes.f_l116_candidatos(bigint)', 'redes.f_resumen_l116(bigint)', 'redes.f_publicar_l116(bigint,text,text)', 'redes.f_revertir_l116(text,text)',
          'public.geoportal_redes_l116_vincular_dano(text,bigint,text,text,text)']
TABLAS = ['redes.l116_danos', 'redes.l116_vigente', 'redes.l116_eventos', 'redes.l116_reportes']
MIG = ['10_esquema.sql', '20_funciones.sql', '26_rpc.sql', '25_reemplazos.sql', '40_permisos.sql']

T = {}
# ---- el motor del Cargue: la capa «linea_116» va por sus funciones (como la de muestreo), y su lote solo guarda las columnas que se cargan (nunca NOMBRE)
T['redes.f_lote(bigint,jsonb)'] = [(
    """  select p_carga, (e ->> 'orden')::integer, nullif(btrim(e -> 'atributos' ->> c.columna_llave), ''), e -> 'atributos', g.geom, g.error
    from jsonb_array_elements(p_filas) e
""",
    """  select p_carga, (e ->> 'orden')::integer, nullif(btrim(a.atr ->> c.columna_llave), ''), a.atr, g.geom, g.error
    from jsonb_array_elements(p_filas) e
    -- Corte 5d: de la línea 116 solo se guardan las columnas que se cargan (NOMBRE nunca llega a la base); no trae geometría (se ubica al revisar)
    cross join lateral (select case when c.capa_codigo = 'linea_116' then redes.f_l116_atributos(e -> 'atributos') else e -> 'atributos' end as atr) a
""")]
T['redes.f_resumen(bigint)'] = [(
    """  if c.capa_codigo = 'muestreo' then return redes.f_resumen_muestreo(p_carga); end if;      -- capa MUE (Corte 5a)
""",
    """  if c.capa_codigo = 'muestreo' then return redes.f_resumen_muestreo(p_carga); end if;      -- capa MUE (Corte 5a)
  if c.capa_codigo = 'linea_116' then return redes.f_resumen_l116(p_carga); end if;      -- línea 116 (Corte 5d)
""")]
T['redes.f_publicar(bigint,text,text)'] = [(
    """  if (select capa_codigo from redes.cargas where id = p_carga) = 'muestreo' then return redes.f_publicar_muestreo(p_carga, p_autor, p_motivo); end if;      -- capa MUE (Corte 5a)
""",
    """  if (select capa_codigo from redes.cargas where id = p_carga) = 'muestreo' then return redes.f_publicar_muestreo(p_carga, p_autor, p_motivo); end if;      -- capa MUE (Corte 5a)
  if (select capa_codigo from redes.cargas where id = p_carga) = 'linea_116' then return redes.f_publicar_l116(p_carga, p_autor, p_motivo); end if;      -- línea 116 (Corte 5d)
""")]
T['redes.f_revertir(text,text,text)'] = [(
    """  if p_capa = 'muestreo' then return redes.f_revertir_muestreo(p_autor, p_motivo); end if;      -- capa MUE (Corte 5a)
""",
    """  if p_capa = 'muestreo' then return redes.f_revertir_muestreo(p_autor, p_motivo); end if;      -- capa MUE (Corte 5a)
  if p_capa = 'linea_116' then return redes.f_revertir_l116(p_autor, p_motivo); end if;      -- línea 116 (Corte 5d)
""")]
T['public.geoportal_redes_cargue_capas(text)'] = [
    ("""'lector', case when c.codigo = 'muestreo' then 'muestreo' when""", """'lector', case when c.codigo = 'muestreo' then 'muestreo' when c.codigo = 'linea_116' then 'linea_116' when"""),
    ("""                 case when c.codigo = 'muestreo' then (select count(*) from tecnica.puntos p where p.tipo = 'muestreo' and p.activo)
""",
     """                 case when c.codigo = 'muestreo' then (select count(*) from tecnica.puntos p where p.tipo = 'muestreo' and p.activo)
                      when c.codigo = 'linea_116' then (select count(*) from redes.l116_vigente l where not l.oculto)      -- Corte 5d
""")]
# ---- la capa del geovisor: la línea 116 por fecha de registro, agrupada por contrato, causal y día; sin nombre, dirección ni barrio
T['public.geoportal_redes_geovisor_capa(text,text,date,date)'] = [
    ("""        v_ini timestamptz; v_fin timestamptz; v_f jsonb; v_n integer;""", """        v_ini timestamptz; v_fin timestamptz; v_f jsonb; v_n integer; v_sin integer;"""),
    ("""  else
    perform tecnica.f_error('Esa capa todavía no tiene datos', 'P0002');""",
     """  elsif p_capa = 'pqr_116' then      -- Corte 5d: la línea 116. Los repetidos del mismo contrato, causal y día van en un solo punto. Sin nombre, dirección ni barrio
    select coalesce(jsonb_agg(f order by o desc), '[]'::jsonb), count(*) into v_f, v_n from (
      select jsonb_build_object('type', 'Feature', 'geometry', jsonb_build_object('type', 'Point', 'coordinates', jsonb_build_array(round(ST_X(z.geom)::numeric, 6), round(ST_Y(z.geom)::numeric, 6))),
               'properties', jsonb_build_object('codigo', z.reportes[1]::text, 'n', z.n, 'reportes', to_jsonb(z.reportes[1:20]), 'servicio', z.servicio,
                                                'grupo_servicio', case redes.f_norm(z.servicio) when 'acueducto' then 'acueducto' when 'alcantarillado' then 'alcantarillado' else 'otros' end,
                                                'causal', z.causal, 'estado', case when z.registrados > 0 then 'registrado' else 'atendido' end, 'registrados', z.registrados,
                                                'contrato', z.contrato, 'dia', z.dia, 'cuando', z.primero, 'ultimo', z.ultimo, 'metodo', z.metodo, 'sector', z.sector, 'subsector', z.subsector,
                                                'danos', (select jsonb_agg(distinct d.codigo) from redes.l116_danos ld join redes.danos d on d.id = ld.dano_id where ld.reporte_id = any (z.ids)))) as f,
             z.ultimo as o
        from (select v.contrato, v.causal, v.dia, count(*) as n, array_agg(v.reporte order by v.fecha_registro, v.reporte) as reportes, array_agg(v.reporte_id) as ids,
                     min(v.servicio) as servicio, count(*) filter (where v.estado = 'registrado') as registrados, min(v.fecha_registro) as primero, max(v.fecha_registro) as ultimo,
                     (array_agg(v.geom order by v.fecha_registro, v.reporte))[1] as geom, (array_agg(v.metodo order by v.fecha_registro, v.reporte))[1] as metodo,
                     (array_agg(v.sector order by v.fecha_registro, v.reporte))[1] as sector, (array_agg(v.subsector order by v.fecha_registro, v.reporte))[1] as subsector
                from redes.l116_vigente v
               where not v.oculto and v.geom is not null and v.fecha_registro >= v_ini and v.fecha_registro < v_fin
               group by coalesce(v.contrato, 'R' || v.reporte), v.contrato, v.causal, v.dia) z
       order by z.ultimo desc limit v_max + 1) x;
    select count(*) into v_sin from redes.l116_vigente v where not v.oculto and v.geom is null and v.fecha_registro >= v_ini and v.fecha_registro < v_fin;
  else
    perform tecnica.f_error('Esa capa todavía no tiene datos', 'P0002');"""),
    ("""                            'recortada', v_n > v_max, 'features', v_f);""",
     """                            'recortada', v_n > v_max, 'features', v_f)
         || case when p_capa = 'pqr_116' then jsonb_build_object('sin_ubicar', v_sin) else '{}'::jsonb end;      -- Corte 5d: los del rango que no están en el mapa""")]
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
capa_antes = q("select nombre || '|' || nota || '|' || fuente || '|' || estado || '|' || por_fecha || '|' || solo_completo from redes.geovisor_capas where codigo = 'pqr_116'").split('|')

partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 5d · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto vivo (el del 9a-bis publicado) con cambios exactos, aplicados una sola vez.
--   · redes.f_lote: de la capa «linea_116» solo se guardan las columnas que se cargan (NOMBRE nunca llega a la base);
--   · redes.f_resumen, f_publicar y f_revertir: la capa «linea_116» va por sus funciones (como la de muestreo);
--   · geoportal_redes_cargue_capas: el lector «linea_116» y cuántos reportes hay;
--   · geoportal_redes_geovisor_capa: la capa «pqr_116» (línea 116) por fecha, agrupada por contrato, causal y día, y cuántos quedan sin ubicar.
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
escribir(os.path.join(RAIZ, 'migracion_redes_corte5d_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_redes_corte5d_editor.sql'), 'begin;\n' + ''.join(leer(n) for n in MIG) + leer('70_pruebas.sql') + 'rollback;\n')
p = subprocess.run([PSQL, '-d', BASE, '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_redes_corte5d_editor.sql')], env=ENV, capture_output=True, text=True)
if p.returncode != 0:
    raise SystemExit(p.stderr[-3000:])
md5_5d = q(CONJ)
md5_despues = {f: fmd5(f) for f in CAMBIADAS}
md5_nuevas = {f: fmd5(f) for f in NUEVAS}
lit = lambda s: "'" + s.replace("'", "''") + "'"  # noqa: E731
v.update({'{{MD5_5D}}': md5_5d,
          '{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_antes[f]}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{CAMBIADAS_5D}}': ', '.join(f"('{f}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{N_CAMBIADAS}}': str(len(CAMBIADAS)),
          '{{NUEVAS}}': ', '.join(f"('{f}', '{md5_nuevas[f]}')" for f in NUEVAS),
          '{{N_NUEVAS}}': str(len(NUEVAS)),
          '{{DROPS}}': '\n'.join(f'drop function {f};' for f in reversed(NUEVAS)),
          '{{DROP_TABLAS}}': 'drop table ' + ', '.join(TABLAS) + ';',
          '{{CAPA_ANTES}}': (f"nombre = {lit(capa_antes[0])}, nota = {lit(capa_antes[1])}, fuente = {lit(capa_antes[2])}, estado = {lit(capa_antes[3])}, "
                             f"por_fecha = {capa_antes[4] == 't'}, solo_completo = {capa_antes[5] == 't'}"),
          '{{TEXTOS_ANTES}}': '\n'.join(f'{antes[f]};\nrevoke all on function {f} from public, anon, authenticated, service_role;\n'
                                        + (f'grant execute on function {f} to service_role;\n' if f.startswith('public.') else '') for f in CAMBIADAS)})
for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
    escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v))
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_redes_corte5d_editor.sql'), leer('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_redes_corte5d_editor.sql'), leer('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_redes_corte5d_editor.sql'), 'begin;\n' + leer('90_reversa.sql') + 'commit;\n')
print('huella antes (9a-bis, producción)', MD5_BASE, '· huella 5d', md5_5d)
