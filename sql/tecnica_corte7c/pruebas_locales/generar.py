#!/usr/bin/env python3
"""Arma el paquete SQL del Corte 7c con las huellas de la base local (redes_local en localhost:55432, con el 7a aplicado):
texto vivo de las 2 RPC que cambian → 25_reemplazos.sql, guardia, migración, ensayo; aplica y escribe huellas, verificación y reversa.
Uso: python3 -I generar.py"""
import os
import subprocess

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
MIG = ['10_esquema.sql', '26_rpc.sql', '25_reemplazos.sql', '40_permisos.sql']
NUEVAS = ['tecnica.f_remision_subida(text,text)', 'tecnica.f_qparam_editable(text)', 'public.geoportal_tec_quimico_remision_preparar(text)',
          'public.geoportal_tec_quimico_parametros(text)', 'public.geoportal_tec_quimico_parametro_fijar(text,text,numeric,text)']
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
T = {
    # la entrada acepta, opcional, la foto de la remisión (una ruta reservada por la misma persona y ya subida)
    'public.geoportal_tec_quimico_entrada(text,jsonb,text)': [
        ("""v_cant numeric; v_vence date; m tecnica.quimico_movimientos%rowtype;""", """v_cant numeric; v_vence date; m tecnica.quimico_movimientos%rowtype; v_foto text := nullif(btrim(coalesce(p_datos, '{}'::jsonb) ->> 'foto'), '');"""),
        ("""  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, lote_fabricante, vence, autor, clave_envio)
  values ('entrada',""",
         """  -- Corte 7c: la foto de la remisión es opcional; si viene, debe ser suya, estar subida, ser JPEG y no estar ya en otra entrada
  if v_foto is not null then
    perform tecnica.f_remision_subida(v_foto, v_email);
    if exists (select 1 from tecnica.quimico_movimientos x where x.remision_foto = v_foto) then perform tecnica.f_error('Esa foto ya quedó en otra entrada: tome una nueva'); end if;
  end if;
  insert into tecnica.quimico_movimientos (tipo, quimico_id, cantidad, unidad, cantidad_kg, dia, proveedor, remision, lote_fabricante, vence, remision_foto, autor, clave_envio)
  values ('entrada',"""),
        ("""nullif(btrim(d ->> 'lote'), ''), v_vence, v_email, p_clave)""", """nullif(btrim(d ->> 'lote'), ''), v_vence, v_foto, v_email, p_clave)"""),
        ("""  perform tecnica.f_auditar(v_email, 'tec_quimico_entrada', q.codigo, jsonb_build_object('movimiento_id', v_id), null);""",
         """  perform tecnica.f_auditar(v_email, 'tec_quimico_entrada', q.codigo, jsonb_build_object('movimiento_id', v_id, 'con_foto', v_foto is not null), null);"""),
    ],
    # el historial del supervisor trae la ruta de la foto (la Edge la cambia por una URL firmada de 60 s; la ruta no sale al navegador)
    'public.geoportal_tec_quimico_historial(text,text)': [
        ("""'vence', m.vence, 'motivo', m.motivo,""", """'vence', m.vence, 'remision_foto_ruta', m.remision_foto, 'motivo', m.motivo,"""),
    ],
}
CAMBIADAS = list(T)


def q(sql):
    return subprocess.run([PSQL, '-d', 'redes_local', '-AtX', '-c', sql], env=ENV, check=True, capture_output=True, text=True).stdout.strip()


def leer(n):
    return open(os.path.join(RAIZ, 'sql', n), encoding='utf-8').read()


def escribir(ruta, texto):
    open(ruta, 'w', encoding='utf-8').write(texto)


def plantilla(texto, val):
    for k, v in val.items():
        texto = texto.replace(k, v)
    assert '{{' not in texto, texto[texto.index('{{'):][:60]
    return texto


fdef = lambda f: q(f"select pg_get_functiondef('{f}'::regprocedure)").rstrip()  # noqa: E731
fmd5 = lambda f: q(f"select md5(pg_get_functiondef('{f}'::regprocedure))")  # noqa: E731

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_7a'], env=ENV, check=True, capture_output=True)
antes = {f: fdef(f) for f in CAMBIADAS}
md5_antes = {f: fmd5(f) for f in CAMBIADAS}
partes = ["""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 7c · 25 — REEMPLAZOS (create or replace, misma firma). GENERADO por pruebas_locales/generar.py:
-- cada uno es el texto del 7a con cambios exactos, aplicados una sola vez:
--   · geoportal_tec_quimico_entrada: acepta la foto de la remisión (opcional) y la guarda con la entrada;
--   · geoportal_tec_quimico_historial: cada movimiento trae la ruta de su foto (la Edge la cambia por una URL firmada).
-- ====================================================================="""]
for f in CAMBIADAS:
    t = antes[f]
    for viejo, nuevo in T[f]:
        assert t.count(viejo) == 1, (f, viejo[:80], t.count(viejo))
        t = t.replace(viejo, nuevo)
    partes.append(f'\n-- {f}\n{t};\n')
escribir(os.path.join(RAIZ, 'sql', '25_reemplazos.sql'), ''.join(partes))
v = {'{{CAMBIADAS_ANTES}}': ', '.join(f"('{f}', '{md5_antes[f]}')" for f in CAMBIADAS)}
mig = ''.join(plantilla(leer(n), v) for n in MIG)
escribir(os.path.join(RAIZ, 'migracion_tecnica_corte7c_editor.sql'), 'begin;\n' + mig + 'commit;\n')
escribir(os.path.join(RAIZ, 'ensayo_en_transaccion_tecnica_corte7c_editor.sql'), 'begin;\n' + mig + leer('70_pruebas.sql') + 'rollback;\n')
subprocess.run([PSQL, '-d', 'redes_local', '-qX', '-v', 'ON_ERROR_STOP=1', '-f', os.path.join(RAIZ, 'migracion_tecnica_corte7c_editor.sql')], env=ENV, check=True, capture_output=True)
md5_despues = {f: fmd5(f) for f in CAMBIADAS}
md5_nuevas = {f: fmd5(f) for f in NUEVAS}
v.update({'{{CAMBIADAS}}': ', '.join(f"('{f}', '{md5_antes[f]}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{CAMBIADAS_7C}}': ', '.join(f"('{f}', '{md5_despues[f]}')" for f in CAMBIADAS),
          '{{NUEVAS}}': ', '.join(f"('{f}', '{md5_nuevas[f]}')" for f in NUEVAS),
          '{{TEXTOS_ANTES}}': '\n'.join(f'{antes[f]};\nrevoke all on function {f} from public, anon, authenticated, service_role;\ngrant execute on function {f} to service_role;\n' for f in CAMBIADAS)})
pl = lambda n: plantilla(open(os.path.join(AQUI, 'plantillas', n), encoding='utf-8').read(), v)  # noqa: E731
escribir(os.path.join(RAIZ, 'huellas_solo_lectura_tecnica_corte7c_editor.sql'), pl('05_huellas_solo_lectura.sql'))
escribir(os.path.join(RAIZ, 'verificacion_tecnica_corte7c_editor.sql'), pl('80_verificacion.sql'))
escribir(os.path.join(RAIZ, 'reversa_tecnica_corte7c_editor.sql'), 'begin;\n' + pl('90_reversa.sql') + 'commit;\n')
print('redes (local, sin el 9a)', q(CONJ), '·', ' · '.join(f"{f.split('(')[0].split('.')[1]} {md5_antes[f][:8]}→{md5_despues[f][:8]}" for f in CAMBIADAS))
