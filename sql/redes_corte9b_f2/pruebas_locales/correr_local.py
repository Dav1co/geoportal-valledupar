#!/usr/bin/env python3
"""Arnés local del Corte 9b, Fase 2 (Code A, localhost:55432, base redes_local). Sobre una base como producción + el paquete del 9b (1a + 1b):
  · el ensayo (N de N … SIN FALLAS) y que no deja nada; huellas; migración; verificación; segunda migración; reversa (vuelve la huella del 9b);
  · que la Fase 2 no cambia tecnica.f_avisos ni ninguna función del 9b (1a + 1b), y que el ensayo del 9b sigue pasando con la Fase 2 puesta… no aplica: su guardia
    exige la base sin el 9b; en su lugar se repiten sus llamadas como la Edge (simulación, maniobra, cortes vigentes);
  · como las ve producción (service_role, 30 s / 8 s): alertas de presión, bandeja de sensibles, afectación y sensores; topes locales 5 s / 6 y 1 s / 6.
Uso: python3 -I correr_local.py"""
import json
import os
import re
import subprocess
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
PSQL = os.environ.get('PSQL', '/opt/homebrew/opt/postgresql@17/bin/psql')
BASE = 'redes_local'
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_9B = '895517fb68f74d6d6c20079c83bdf7c4'
AV = "select md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure))"
VIEJAS = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) from pg_proc p where p.proname in ('f_sim_grafo', 'f_sim_escenario', "
          "'f_simular_cierre', 'f_cortes_foto', 'f_cierres_vigentes', 'geoportal_redes_simulacion_cierre', 'geoportal_redes_valvula_maniobra', 'geoportal_redes_cortes_vigentes', "
          "'geoportal_redes_geovisor_mvt_cortes', 'geoportal_redes_simulacion_guardar', 'geoportal_redes_corte_regreso', 'f_param_entero')")
ADM, SD, OP = 'zt9f.arnes.adm@emdupar.gov.co', 'zt9f.arnes.dist@emdupar.gov.co', 'zt9f.arnes.op@emdupar.gov.co'
T5, T1 = 5000 / 6, 1000 / 6
res = []


def ok(nombre, cond, det=''):
    res.append((nombre, bool(cond), str(det)[:500]))
    print(('OK    ' if cond else 'FALLA ') + nombre + ('' if cond else ' → ' + str(det)[:500]), flush=True)


def psql(*args, check=False):
    return subprocess.run([PSQL, '-d', BASE, '-X', *args], env=ENV, capture_output=True, text=True, check=check)


def q(sql):
    return psql('-At', '-c', sql, check=True).stdout.strip()


def rehacer(con=''):
    subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')] + ([con] if con else []), env=ENV, check=True, capture_output=True)


def edge(sql):
    t0 = time.time()
    p = psql('-Atq', '-v', 'ON_ERROR_STOP=1', '-c', 'set role service_role', '-c', "set statement_timeout = '30s'", '-c', "set lock_timeout = '8s'", '-c', sql)
    return round((time.time() - t0) * 1000), p.stdout.strip(), (p.stderr.strip() if p.returncode else '')


def archivo(n):
    return os.path.join(RAIZ, n)


SALIDA_AV = "select md5(tecnica.f_avisos(true, true, '2026-11-17 15:00:00-05')::text)"
rehacer()
av0, viejas0, salida0 = q(AV), q(VIEJAS), q(SALIDA_AV)
p = psql('-q', '-f', archivo('ensayo_en_transaccion_redes_corte9b_f2_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — SIN FALLAS', p.stderr)
ok(f'01 el ensayo termina en el ERROR esperado: {m.group(1) if m else "?"} de {m.group(2) if m else "?"} … SIN FALLAS', m and m.group(1) == m.group(2) and 'esperado' in p.stderr, p.stderr[-1500:])
print('   ' + (re.search(r'TIEMPOS[^\n]*', p.stderr) or [''])[0])
ok('02 … y no deja nada (sigue la huella del 9b, no hay tablas de la Fase 2 y la capa de cortes sigue visible)',
   q(CONJ) == MD5_9B and q("select to_regclass('redes.usuarios_sensibles')") == '' and q("select activa from redes.geovisor_capas where codigo = 'cortes'") == 't')
filas = psql('-AtF', '|', '-f', archivo('huellas_solo_lectura_redes_corte9b_f2_editor.sql')).stdout.strip().splitlines()
ok('03 las huellas antes: «9b 1a + 1b (listo para la Fase 2)» y las 14 nuevas no existen', any('listo para la Fase 2' in f for f in filas)
   and sum('NO EXISTE (sin aplicar)' in f for f in filas) == 14 and not any('DISTINTA' in f or 'FALTA' in f for f in filas), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('migracion_redes_corte9b_f2_editor.sql'))
ok('04 la migración se aplica', p.returncode == 0, p.stderr)
ok('05 las funciones del 9b (1a + 1b) quedan con el mismo texto; tecnica.f_avisos cambia (aviso de presiones) y, sin presiones cargadas, devuelve exactamente lo mismo que antes',
   q(VIEJAS) == viejas0 and q(AV) != av0 and q(SALIDA_AV) == salida0)
filas = psql('-AtF', '|', '-f', archivo('huellas_solo_lectura_redes_corte9b_f2_editor.sql')).stdout.strip().splitlines()
ok('06 las huellas después: «FASE 2 (aplicada)», 14 nuevas y las tablas', any('FASE 2 (aplicada)' in f for f in filas) and sum('NUEVA (aplicada)' in f for f in filas) == 14
   and any('EXISTEN (Fase 2)' in f for f in filas), '\n'.join(filas))
filas = psql('-AtF', '|', '-f', archivo('verificacion_redes_corte9b_f2_editor.sql')).stdout.strip().splitlines()
ok(f'07 la verificación: las {sum(1 for f in filas if not f.startswith("INFO"))} filas OK', filas and all(f.endswith('|OK') for f in filas if not f.startswith('INFO')), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('migracion_redes_corte9b_f2_editor.sql'))
ok('08 una segunda migración se niega', p.returncode != 0 and 'ya está aplicada' in p.stderr, p.stderr)
ok('09 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', q('select count(*) from redes.f_funciones_sin_where()') == '0')

# como las ve producción
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('{ADM}', 'ZT9F arnés admin', 'admin', 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('{SD}', 'ZT9F arnés supervisor', 'consulta', true, true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('{OP}', 'ZT9F arnés operador', 'consulta', true, 'sin_restriccion', 'todos')")
q(f"insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('{OP}', 'asignar_formulario', 'danos_fallas', '{ADM}')")
t0 = time.time()
n = q(f"select redes.f_sensibles_proponer('{ADM}')")
ms_p = round((time.time() - t0) * 1000)
ok(f'10 la propuesta de usuarios sensibles sobre la cartera local (por psql; {ms_p} ms): {n} propuestos; la segunda vez, 0; ninguna palabra guardada es un nombre completo',
   int(n) >= 0 and q(f"select redes.f_sensibles_proponer('{ADM}')") == '0' and q("select count(*) from redes.usuarios_sensibles where palabra ~ ' .* '") == '0')
ms, out, e = edge(f"select public.geoportal_redes_sensibles('{SD}', null, null, 500)")
ok(f'11 la bandeja de sensibles como la Edge ({ms} ms; tope local {T1:.0f} ms): {json.loads(out)["totales"] if not e else e}', not e and ms < T1, e)
# presiones: una carga de modelo de prueba con 7.000 nodos (la base local no trae la del Plan Maestro)
q(f"""with c as (insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, autor) values ('pm_nodos', 'zt9f_arnes.csv', md5('zt9f-arnes'), 7000, 'ZT9F arnés', '{ADM}') returning id)
      insert into redes.pm_nodos (carga_id, llave, nombre, geom, pres_exist_min, pres_exist_max, pres_futura_min, pres_futura_max)
      select c.id, n.llave_modelo, n.nombre_modelo, n.geom, (n.id % 40), 20 + (n.id % 70), 10 + (n.id % 30), 30 + (n.id % 40) from c, redes.nodos n where n.sistema = 'acueducto' order by n.id limit 7000""")
ms, out, e = edge(f"select public.geoportal_redes_alertas_presion('{SD}')")
j = json.loads(out) if not e else {}
ok(f'12 alertas de presión como la Edge, 7.000 nodos amarrados a la red real ({ms} ms, {len(out) // 1024} kB; tope local {T1:.0f} ms): {j.get("niveles")}; por material {j.get("por_material", {}).get("n")}',
   not e and ms < T1 and j['nodos'] == 7000 and len(out) < 131072, e)


def avisos_presion():
    ms, out, e = edge(f"select public.geoportal_tec_avisos('{ADM}')")
    return ms, e, out, [a for a in (json.loads(out).get('avisos', []) if not e and out.startswith('{') else (json.loads(out) if not e else [])) if isinstance(a, dict) and a.get('clave') == 'presion_modelo']


ms, e, out, pres = avisos_presion()
ok(f'12b los Avisos del administrador como la Edge, tal como se publica (parámetro «presion_modelo_aviso» en 0; {ms} ms; tope local {T1:.0f} ms): el aviso de presiones NO sale',
   not e and ms < T1 and pres == [] and q("select valor from tecnica.aviso_parametros where clave = 'presion_modelo_aviso'") == '0', e or out[:300])
# presiones por hora para los mismos 7.000 nodos: la mínima del día cae en las horas 5 y 7 (no confiables); en las demás horas, 20 + (id % 50)
q(f"""with c as (insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, autor) values ('pm_presion_existente', 'zt9f_arnes_horas.csv', md5('zt9f-arnes-h'), 7000, 'ZT9F arnés', '{ADM}') returning id)
      insert into redes.pm_presion_hora (carga_id, llave, escenario, p_min, hora_min, p_max, hora_max, p_media, p_mediana, horas)
      select c.id, x.llave, 'existente', x.pres_exist_min, 5, x.pres_exist_max, 0, 20, 20,
             (select array_agg(case when h in (5, 7) then x.pres_exist_min else 20 + (h % 5) end order by h) from generate_series(0, 24) h)
        from c, redes.pm_nodos x where x.carga_id = redes.f_ref_vigente('pm_nodos')""")
q("analyze redes.pm_presion_hora")
todas = j['niveles']
ms, out, e = edge(f"select public.geoportal_redes_alertas_presion('{SD}')")
j = json.loads(out) if not e else {}
ok(f'12c alertas de presión con las 25 horas de los 7.000 nodos, sin las horas no confiables ({ms} ms; tope local {T1:.0f} ms): {j.get("niveles")} (con todas las horas eran {todas}); horas excluidas {j.get("horas_excluidas")}',
   not e and ms < T1 and j['horas_excluidas'] == [5, 7, 10, 12, 14] and j['niveles'] == {} and todas != {}, e)
q("update tecnica.aviso_parametros set valor = 1 where clave = 'presion_modelo_aviso'")
q(f"""insert into redes.pm_nodos (carga_id, llave, nombre, geom, pres_exist_min, pres_exist_max, pres_futura_min, pres_futura_max)
      select redes.f_ref_vigente('pm_nodos'), 'ZT9F-fuera-' || i, 'ZT9F fuera ' || i, ST_SetSRID(ST_MakePoint(-73.25, 10.46), 4326), 3, 30, 20, 40 from generate_series(1, 12) i""")
ms, e, out, pres = avisos_presion()
ok(f'12d con el parámetro en 1 (lo enciende Técnica): los Avisos como la Edge ({ms} ms; tope local {T1:.0f} ms) traen un aviso informativo «{pres[0]["titulo"] if pres else "?"}»',
   not e and ms < T1 and len(pres) == 1 and pres[0]['nivel'] == 'info' and pres[0]['n'] == 12, e or out[:300])
q("update tecnica.aviso_parametros set valor = 0 where clave = 'presion_modelo_aviso'")
ok('13 las alertas de presión son del supervisor', edge(f"select public.geoportal_redes_alertas_presion('{OP}')")[2] != '')
q("insert into redes.danos (id, codigo, clase, tipo_codigo, sistema, activo_id, lat, lon, ubicacion_origen, t_detectado, riesgo, causa_clase, autor) "
  "select gen_random_uuid(), 'DAN-999997', 'dano', 'fuga', 'acueducto', (select tn.activo_id from redes.tramo_nodos tn join redes.activo_vigente_mat m on m.activo_id = tn.activo_id and m.version = tn.version "
  "join redes.nodos a1 on a1.id = tn.nodo_ini join redes.activo_vigente_mat b1 on b1.activo_id = a1.activo_id and b1.prefijo = 'VAL' "
  "join redes.nodos a2 on a2.id = tn.nodo_fin join redes.activo_vigente_mat b2 on b2.activo_id = a2.activo_id and b2.prefijo = 'VAL' where m.cuenta_vigente order by md5(tn.activo_id::text) limit 1), "
  f"10.46, -73.25, 'mapa', now(), 'medio', 'desconocida', '{OP}'")
ms, out, e = edge(f"select public.geoportal_redes_afectacion('{OP}', 'DAN-999997')")
j = json.loads(out) if not e else {}
ok(f'14 la afectación de un daño como la Edge, por simulación ({ms} ms; tope local {T5:.0f} ms): {j.get("contratos_min")}–{j.get("contratos_max")} contratos', not e and ms < T5 and j['fuente'] == 'simulacion', e)
vals = q("select string_agg(v.codigo, ',') from redes.danos d join redes.tramo_nodos tn on tn.activo_id = d.activo_id join redes.nodos n on n.id in (tn.nodo_ini, tn.nodo_fin) "
         "join redes.activo_vigente_mat v on v.activo_id = n.activo_id where d.codigo = 'DAN-999997'").split(',')
errs = [edge(f"select public.geoportal_redes_valvula_maniobra('{OP}', '{c}', 'cerrar', 'DAN-999997')")[2] for c in vals]
ms, out, e = edge(f"select public.geoportal_redes_afectacion('{OP}', 'DAN-999997')")
j = json.loads(out) if not e else {}
ok(f'15 con sus {len(vals)} válvulas cerradas (el 1b sigue funcionando con la Fase 2): la afectación es la real ({ms} ms; tope local {T1:.0f} ms): {j.get("contratos")} contratos, {j.get("zonas")} zona',
   not any(errs) and not e and ms < T1 and j['fuente'] == 'cierre_real' and j['valvulas_cerradas'] == len(vals), errs or e)
ms, out, e = edge(f"select public.geoportal_redes_afectaciones_danos('{SD}')")
j = json.loads(out) if not e else {}
ok(f'15b los daños abiertos sin límite de fecha como la Edge ({ms} ms; tope local {T1:.0f} ms): {j.get("total")} (trae el DAN-999997)',
   not e and ms < T1 and any(f['properties']['codigo'] == 'DAN-999997' for f in j['features']) and j['total'] == len(j['features']), e)
ok('15c … y son del supervisor y del administrador: el operador no', 'Solo el supervisor' in edge(f"select public.geoportal_redes_afectaciones_danos('{OP}')")[2])
ms, out, e = edge(f"select public.geoportal_redes_sensores('{SD}')")
ok(f'16 los sensores como la Edge ({ms} ms)', not e and ms < T1 and 'sensores' in json.loads(out), e)
ok('17 la API no ve las tablas ni la vista de la Fase 2', all('permission denied' in edge(f'select count(*) from redes.{t}')[2] for t in ('usuarios_sensibles', 'v_usuario_sensible', 'sensor_lecturas', 'presion_trabajo', 'presion_horas_no_confiables')))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('reversa_redes_corte9b_f2_editor.sql'))
ok('18 con usuarios sensibles guardados, la reversa se niega (no borra datos)', int(n) == 0 or (p.returncode != 0 and 'no borra datos' in p.stderr), p.stderr)

rehacer('con_f2')
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('reversa_redes_corte9b_f2_editor.sql'))
ok('19 la reversa (sin datos) se aplica: vuelve la huella del 9b, la capa de cortes vuelve a la lista, tecnica.f_avisos vuelve a la del 1b y el parámetro del aviso queda apagado y «sin uso» (no se borra)',
   p.returncode == 0 and q("select valor = 0 and descripcion like 'Sin uso%' from tecnica.aviso_parametros where clave = 'presion_modelo_aviso'") == 't' and q("select to_regclass('redes.presion_horas_no_confiables')") == '' and q(CONJ) == MD5_9B and q("select activa from redes.geovisor_capas where codigo = 'cortes'") == 't' and q(AV) == av0, p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('reversa_redes_corte9b_f2_editor.sql'))
ok('20 una segunda reversa se niega', p.returncode != 0 and 'No hay nada que revertir' in p.stderr, p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('migracion_redes_corte9b_f2_editor.sql'))
ok('21 después de la reversa, la migración se vuelve a aplicar y deja el parámetro apagado con su descripción',
   p.returncode == 0 and q("select valor = 0 and descripcion like '0: apagado%' from tecnica.aviso_parametros where clave = 'presion_modelo_aviso'") == 't', p.stderr)
rehacer()
malas = [r for r in res if not r[1]]
print(f'\nRESULTADO: {len(res) - len(malas)} de {len(res)} — ' + ('SIN FALLAS' if not malas else f'{len(malas)} FALLA(S)'))
