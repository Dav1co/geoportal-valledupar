#!/usr/bin/env python3
"""Arnés local del Corte 8 (reportes compartidos con Comercial). Base: campo_local en el clúster propio (localhost:55434): los paquetes de campo de Comercial hasta la
pasada del 14-nov (21 huellas vivas comprobadas), el Corte 1 real de Técnica de planta y el doble de la vista del 6b. Resultado «N de N».
huellas antes · ensayo (ERROR esperado, sin rastro) · migración · verificación · guardia · huellas después · reversa (deja todo como estaba, texto por texto) ·
migrar de nuevo · las RPC como las ve producción (service_role, statement_timeout 30 s y lock_timeout 8 s) · reversa con datos (se niega).
Uso: python3 -I correr_local.py   → escribe ../resultados/sql_local.txt"""
import json
import os
import re
import subprocess
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55434', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
BD = 'campo_local'
EDGE = ['-c', 'set role service_role', '-c', "set statement_timeout = '30s'", '-c', "set lock_timeout = '8s'"]
SEP = '-- ====================================================================='
res = []


def archivo(nombre):
    p = subprocess.run([PSQL, '-d', BD, '-X', '-v', 'ON_ERROR_STOP=1', '-f', nombre], env=ENV, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def q(sql):
    p = subprocess.run([PSQL, '-d', BD, '-AtX', '-c', sql], env=ENV, capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else 'ERROR: ' + p.stderr.strip()


def edge(sql):
    t = time.time()
    p = subprocess.run([PSQL, '-d', BD, '-AtqX', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', *EDGE, '-c', sql], env=ENV, capture_output=True, text=True)
    return (p.stdout.strip() if p.returncode == 0 else 'ERROR: ' + p.stderr.strip()), time.time() - t, p.returncode != 0


def reg(nombre, ok, detalle=''):
    res.append((nombre, bool(ok), detalle))
    print(('OK   ' if ok else 'FALLA'), nombre, ('· ' + detalle if detalle else ''), flush=True)


ED = lambda n: os.path.join(RAIZ, n)  # noqa: E731
consulta = lambda n: open(ED(n), encoding='utf-8').read().split(SEP, 2)[2].strip().rstrip(';')  # noqa: E731
huellas = lambda: q(f"select string_agg(objeto || '=' || estado, E'\\n') from ({consulta('huellas_solo_lectura_tecnica_corte8_editor.sql')}) h")  # noqa: E731
FOTO = ("select string_agg(pg_get_functiondef(p.oid), E'\\n' order by n.nspname, p.proname, p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace "
        "where n.nspname in ('campo', 'tecnica', 'salida', 'acta') or (n.nspname = 'public' and p.proname like 'geoportal\\_%')")
ESTADO = (f"select md5(({FOTO}) || '|' || (select string_agg(table_schema || '.' || table_name || '.' || column_name || coalesce(column_default, ''), ',' order by table_schema, table_name, column_name) from information_schema.columns "
          "where table_schema in ('campo', 'tecnica', 'redes')) || '|' || (select string_agg(pg_get_constraintdef(oid), ',' order by conname) from pg_constraint where contypid = 'tecnica.formulario_clave'::regtype) "
          "|| '|' || pg_get_viewdef('redes.v_reportes_comercial'::regclass, true))")

subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh'), 'solo_base'], env=ENV, check=True, capture_output=True)
antes = q(ESTADO)
tipos0 = q("select count(*) || '|' || md5(string_agg(codigo || nombre || activo || orden, ',' order by id)) from campo.tipos_reporte")
reg('00 base local: campo de Comercial hasta la pasada del 14-nov (huellas vivas comprobadas al armarla), Corte 1 de Técnica y la vista vacía del 6b', len(antes) == 32 and tipos0.startswith('26|'), f'{tipos0.split("|")[0]} tipos')
h = huellas()
reg('01 huellas antes: 2 «VIVA (sin cambiar)», 3 «FIRMA ESPERADA», 6 «NO EXISTE», columna «NO EXISTE», dominio «7 CLAVES», vista «VACÍA»',
    h.count('VIVA (sin cambiar)') == 2 and h.count('FIRMA ESPERADA') == 3 and h.count('NO EXISTE (sin aplicar)') == 7 and '7 CLAVES (sin aplicar)' in h and 'VACÍA (6b, sin aplicar)' in h
    and 'DISTINTA' not in h and 'FALTA' not in h, h.replace('\n', ' | ')[:500])
c, out = archivo(ED('ensayo_en_transaccion_tecnica_corte8_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — (.*)', out)
reg('02 ensayo: ERROR esperado, N de N SIN FALLAS', c != 0 and m and m.group(1) == m.group(2) and 'SIN FALLAS' in m.group(3), m.group(0) if m else out[-600:])
reg('03 el ensayo no deja rastro: funciones, columnas, dominio, vista y catálogo como estaban', q(ESTADO) == antes and q("select count(*) from public.geoportal_lista_blanca where email like 'prueba.tec8.%'") == '0'
    and q("select count(*) || '|' || md5(string_agg(codigo || nombre || activo || orden, ',' order by id)) from campo.tipos_reporte") == tipos0)
c, out = archivo(ED('migracion_tecnica_corte8_editor.sql'))
reg('04 migración', c == 0, '' if c == 0 else out[-400:])
despues = q(ESTADO)
filas = [x for x in q(consulta('verificacion_tecnica_corte8_editor.sql')).split('\n') if x]
reg('05 verificación: 9 OK y 2 INFO', len(filas) == 11 and sum(x.endswith('|OK') for x in filas) == 9, ' | '.join(x for x in filas if not x.endswith('|OK'))[:300])
c, out = archivo(ED('migracion_tecnica_corte8_editor.sql'))
reg('06 guardia: migrar dos veces se niega', c != 0 and 'ya está aplicado' in out, out.strip().split('\n')[0][:160])
h = huellas()
reg('07 huellas después: 2 «CORTE 8 (reemplazada)», 6 «NUEVA», columna «EXISTE», «9 CLAVES», vista «CORTE 8», 28 tipos',
    h.count('CORTE 8 (reemplazada)') == 2 and h.count('NUEVA (aplicada)') == 6 and 'EXISTE (aplicado)' in h and '9 CLAVES (aplicado)' in h and 'CORTE 8 (aplicada)' in h and '=28 · ' in h, h.replace('\n', ' | ')[-330:])
reg('08 los 26 tipos que había no cambiaron; los 2 nuevos van al final de «red_acueducto», activos',
    q("select count(*) || '|' || md5(string_agg(codigo || nombre || activo || orden, ',' order by id)) from campo.tipos_reporte where codigo not in ('fuga_acometida', 'caja_medidor_danada')") == tipos0
    and q("select string_agg(t.nombre || ':' || t.activo, ' · ' order by t.orden) from campo.tipos_reporte t where t.codigo in ('fuga_acometida', 'caja_medidor_danada')") == 'Fuga en acometida:true · Caja de medidor dañada:true')
c, out = archivo(ED('reversa_tecnica_corte8_editor.sql'))
sin_tipos = q(ESTADO) == antes
reg('09 reversa vacía: funciones, columnas, dominio y vista exactamente como antes; los 2 tipos nuevos no se borran, quedan desactivados', c == 0 and sin_tipos
    and q("select string_agg(codigo || ':' || activo, ',' order by codigo) from campo.tipos_reporte where codigo in ('fuga_acometida', 'caja_medidor_danada')") == 'caja_medidor_danada:false,fuga_acometida:false', out[-300:] if c else '')
c, out = archivo(ED('migracion_tecnica_corte8_editor.sql'))
reg('10 migrar de nuevo después de la reversa: mismo resultado (los 2 tipos ya existen y no se duplican; siguen desactivados hasta reactivarlos en el Catálogo)', c == 0 and q(ESTADO) == despues
    and q("select count(*) from campo.tipos_reporte") == '28', out[-300:] if c else '')
q("update campo.tipos_reporte set activo = true where codigo in ('fuga_acometida', 'caja_medidor_danada')")

# ---------- como las ve producción: la Edge geoportal-campo llama con service_role, 30 s y 8 s ----------
OP, REP = 'arnes.tec8@emdupar.gov.co', 'arnes.rep8@emdupar.gov.co'
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('{OP}', 'Arnés Técnica', 'consulta', true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_campo, horario, dias) values ('{REP}', 'Arnés Comercial', 'consulta', true, 'sin_restriccion', 'todos')")
q(f"insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('{OP}', 'asignar_formulario', 'anomalia_compartida', '{OP}')")
out, s, mal = edge(f"select public.geoportal_campo_tec_formulario('{OP}')")
f = json.loads(out) if not mal else {}
cods = sorted(t['codigo'] for g in f.get('grupos', []) for t in g['tipos'])
reg('11 Edge (service_role, 30 s y 8 s): el formulario desde Técnica trae los tipos del reporte general, con los 2 nuevos, y ningún formato de actividad', not mal and 'fuga_acometida' in cods and 'caja_medidor_danada' in cods
    and 'revision_previa' not in cods and 'suspension' not in cods and f.get('area') == 'tecnica' and s < 2, f'{len(cods)} tipos · {s * 1000:.0f} ms' + (out[:200] if mal else ''))
out, s, mal = edge(f"select public.geoportal_campo_tec_preparar_subida('{OP}', 1, '127.0.0.1', null)")
pr = json.loads(out) if not mal else {}
if not mal:
    q(f"""insert into storage.objects (bucket_id, name, metadata) values ('campo-fotos', '{pr["fotos"][0]["ruta"]}', '{{"size": 150000, "mimetype": "image/jpeg"}}')""")
fotos = json.dumps([{'orden': 1, 'ruta': pr['fotos'][0]['ruta'], 'tomada_en': '2026-11-16T15:00:00-05:00'}]) if not mal else '[]'
out, s2, mal2 = edge(f"select public.geoportal_campo_tec_crear_reporte('{OP}', '{pr.get('reporte_id')}', 'fuga_acometida', null, 'Arnés: fuga en la acometida', null, 10.45, -73.25, 6, false, '{fotos}'::jsonb, '127.0.0.1')")
reg('12 Edge: preparar la subida y crear «Fuga en acometida» desde Técnica: queda en campo.reportes con el área «tecnica»', not mal and not mal2 and json.loads(out).get('area') == 'tecnica'
    and q(f"select area || '|' || autor from campo.reportes where id = '{pr.get('reporte_id')}'") == f'tecnica|{OP}' and s + s2 < 3, f'{(s + s2) * 1000:.0f} ms' + (out[:300] if mal2 else ''))
out, _, mal = edge(f"select public.geoportal_campo_crear_reporte('{OP}', gen_random_uuid(), 'fuga_acometida', null, 'Arnés: por la puerta de Comercial', null, 10.45, -73.25, 6, false, 'campo', '[]'::jsonb)")
reg('13 Edge: la misma persona de Técnica, por la RPC de Comercial (otra transacción, sin la marca): 42501', mal and '42501' in out, out[:120])
out, s, mal = edge(f"select public.geoportal_campo_preparar_subida('{REP}', 1, 'campo', '127.0.0.1', null)")
pr2 = json.loads(out) if not mal else {}
if not mal:
    q(f"""insert into storage.objects (bucket_id, name, metadata) values ('campo-fotos', '{pr2["fotos"][0]["ruta"]}', '{{"size": 150000, "mimetype": "image/jpeg"}}')""")
fotos2 = json.dumps([{'orden': 1, 'ruta': pr2['fotos'][0]['ruta'], 'tomada_en': '2026-11-16T15:00:00-05:00'}]) if not mal else '[]'
out, _, mal2 = edge(f"select public.geoportal_campo_crear_reporte('{REP}', '{pr2.get('reporte_id')}', 'caja_medidor_danada', null, 'Arnés: caja dañada', '123456', 10.451, -73.251, 6, false, 'campo', '{fotos2}'::jsonb, '127.0.0.1')")
reg('14 Edge: Comercial crea «Caja de medidor dañada» como siempre: área nula y la respuesta de antes (sin «area»)', not mal and not mal2 and 'area' not in json.loads(out)
    and q(f"select area is null from campo.reportes where id = '{pr2.get('reporte_id')}'") == 't', out[:300] if mal2 else '')
out, _, mal = edge('select count(*) from redes.v_reportes_comercial')
reg('15 la API no lee la vista del geovisor; por dentro trae los 2 reportes (Técnica sin contrato en rojo; Comercial con contrato en azul), sin el contrato ni la descripción', mal
    and q("select string_agg(area || ':' || con_contrato || ':' || tipo, ' · ' order by area) from redes.v_reportes_comercial") == 'comercial:true:Caja de medidor dañada · tecnica:false:Fuga en acometida'
    and q("select count(*) from redes.v_reportes_comercial v where to_jsonb(v)::text ~ '123456|Arnés'") == '0', q("select string_agg(area || ':' || con_contrato || ':' || tipo, ' · ' order by area) from redes.v_reportes_comercial"))
filas = [x for x in q(consulta('verificacion_tecnica_corte8_editor.sql')).split('\n') if x]
reg('16 verificación con datos: 9 OK', sum(x.endswith('|OK') for x in filas) == 9, ' | '.join(filas[-2:])[:300])
c, out = archivo(ED('reversa_tecnica_corte8_editor.sql'))
reg('17 reversa con datos: se niega (ya hay reportes hechos desde Técnica) y no cambia nada', c != 0 and 'se niega' in out and q(ESTADO) == despues, out.strip().split('\n')[0][:160])

ok = sum(1 for _, b, _ in res if b)
texto = '\n'.join(('OK    ' if b else 'FALLA ') + n + ((' · ' + d) if d else '') for n, b, d in res)
texto += f'\n\nRESULTADO: {ok} de {len(res)} — ' + ('SIN FALLAS' if ok == len(res) else f'{len(res) - ok} FALLA(S)') + '\n'
open(os.path.join(RAIZ, 'resultados', 'sql_local.txt'), 'w', encoding='utf-8').write(texto)
print(f'\nRESULTADO: {ok} de {len(res)}')
