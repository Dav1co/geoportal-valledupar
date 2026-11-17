#!/usr/bin/env python3
"""Arnés local del Corte 9b, Fase 3 (capa «Flujo del agua (modelo)»; Code A, localhost:55432, base redes_local). Sobre producción + 9b (1a + 1b) + Fase 2:
  · ensayo, huellas, migración, verificación, segunda migración y reversa; que la Fase 3 solo agrega (no cambia tecnica.f_avisos ni funciones del 9b);
  · el paquete de carga (el CSV real de la Fase 0): ensayo (no deja nada), carga, verificación, no se carga dos veces ni por quien no es administrador;
  · como lo ve producción (service_role, 30 s / 8 s): teselas, información y tarjeta, con tope local de 1 s / 6.
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
MD5_F2 = '24e62e151ff418ea6acf631572d72683'
AV = "select md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamp with time zone)'::regprocedure))"
VIEJAS = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) from pg_proc p where p.proname in ('f_sim_grafo', 'f_sim_escenario', "
          "'f_simular_cierre', 'f_cortes_foto', 'f_cierres_vigentes', 'geoportal_redes_simulacion_cierre', 'geoportal_redes_valvula_maniobra', 'geoportal_redes_cortes_vigentes', "
          "'geoportal_redes_geovisor_mvt_cortes', 'geoportal_redes_simulacion_guardar', 'geoportal_redes_corte_regreso', 'f_param_entero')")
ADM, SD, OP = 'zt9g.arnes.adm@emdupar.gov.co', 'zt9g.arnes.dist@emdupar.gov.co', 'zt9g.arnes.op@emdupar.gov.co'
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



GEN = os.path.join(RAIZ, 'carga_flujo', 'generado')
CARGA = 'carga.local@emdupar.gov.co'


def carga(nombre, quien=CARGA, stop=True):
    t0 = time.time()
    p = subprocess.run([PSQL, '-d', BASE, '-X'] + (['-v', 'ON_ERROR_STOP=1'] if stop else []) + ['-v', f'solicitante={quien}', '-f', nombre], env=dict(ENV, PGOPTIONS=''), capture_output=True, text=True, cwd=GEN)
    return round((time.time() - t0) * 1000), p


rehacer()
av0, viejas0 = q(AV), q(VIEJAS)
p = psql('-q', '-f', archivo('ensayo_en_transaccion_redes_corte9b_f3_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — SIN FALLAS', p.stderr)
ok(f'01 el ensayo termina en el ERROR esperado: {m.group(1) if m else "?"} de {m.group(2) if m else "?"} … SIN FALLAS', m and m.group(1) == m.group(2) and 'esperado' in p.stderr, p.stderr[-1500:])
print('   ' + (re.search(r'TIEMPOS[^\n]*', p.stderr) or [''])[0])
ok('02 … y no deja nada (sigue la huella de la Fase 2, no hay tablas del flujo ni la capa)',
   q(CONJ) == MD5_F2 and q("select to_regclass('redes.flujo_modelo')") == '' and q("select count(*) from redes.geovisor_capas where codigo = 'flujo_modelo'") == '0')
filas = psql('-AtF', '|', '-f', archivo('huellas_solo_lectura_redes_corte9b_f3_editor.sql')).stdout.strip().splitlines()
ok('03 las huellas antes: «FASE 2 (lista para la Fase 3)» y las 4 nuevas no existen', any('lista para la Fase 3' in f for f in filas)
   and sum('NO EXISTE (sin aplicar)' in f for f in filas) == 4 and not any('DISTINTA' in f or 'FALTA' in f for f in filas), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('migracion_redes_corte9b_f3_editor.sql'))
ok('04 la migración se aplica', p.returncode == 0, p.stderr)
ok('05 la Fase 3 SOLO AGREGA: tecnica.f_avisos y las funciones del 9b (1a + 1b) quedan con el mismo texto', q(AV) == av0 and q(VIEJAS) == viejas0)
filas = psql('-AtF', '|', '-f', archivo('huellas_solo_lectura_redes_corte9b_f3_editor.sql')).stdout.strip().splitlines()
ok('06 las huellas después: «FASE 3 (aplicada)», 4 nuevas y las tablas', any('FASE 3 (aplicada)' in f for f in filas) and sum('NUEVA (aplicada)' in f for f in filas) == 4 and any('EXISTEN (Fase 3)' in f for f in filas), '\n'.join(filas))
filas = psql('-AtF', '|', '-f', archivo('verificacion_redes_corte9b_f3_editor.sql')).stdout.strip().splitlines()
ok(f'07 la verificación: las {sum(1 for f in filas if not f.startswith("INFO"))} filas OK', filas and all(f.endswith('|OK') for f in filas if not f.startswith('INFO')), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('migracion_redes_corte9b_f3_editor.sql'))
ok('08 una segunda migración se niega', p.returncode != 0 and 'ya está aplicada' in p.stderr, p.stderr)
ok('09 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', q('select count(*) from redes.f_funciones_sin_where()') == '0')
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('{SD}', 'ZT9G arnés supervisor', 'consulta', true, true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('{OP}', 'ZT9G arnés operador', 'consulta', true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('{CARGA}', 'Carga local', 'admin', 'sin_restriccion', 'todos') on conflict do nothing")
ms, out, e = edge(f"select public.geoportal_redes_flujo_modelo('{SD}')")
ok('10 antes de cargar: la capa dice «no cargado» (con su rótulo) y la tesela sale vacía', not e and json.loads(out)['cargado'] is False and 'Modelo, no medido' in out
   and edge(f"select public.geoportal_redes_geovisor_mvt_flujo('{SD}', 'mayor', 14, 4857, 7712)")[1] == '')

# el paquete de carga
ms, p = carga('ensayo_carga_flujo_modelo.sql', stop=False)
m = re.search(r'RESULTADO: (\d+) de (\d+) comprobaciones correctas — SIN FALLAS', p.stderr)
ok(f'11 el ENSAYO de la carga (el CSV real de la Fase 0): {m.group(1) if m else "?"} de {m.group(2) if m else "?"} … SIN FALLAS ({ms} ms)', m and m.group(1) == m.group(2) and 'ENSAYO' in p.stderr, p.stderr[-900:])
ok('12 … y no deja nada cargado', q('select count(*) from redes.flujo_modelo') == '0' and q("select count(*) from redes.ref_cargas where conjunto = 'flujo_modelo'") == '0')
ms, p = carga('carga_flujo_modelo.sql', quien=SD)
ok('13 la carga se niega a quien no es administrador', 'no es de un administrador' in p.stdout and q('select count(*) from redes.flujo_modelo') == '0', p.stdout[-300:] + p.stderr[-300:])
ms, p = carga('carga_flujo_modelo.sql')
m = re.search(r'(\d+) de (\d+) comprobaciones correctas — SIN FALLAS', p.stderr)
ok(f'14 la carga real: {m.group(1) if m else "?"} de {m.group(2) if m else "?"} comprobaciones, SIN FALLAS ({ms} ms en total)', p.returncode == 0 and m and m.group(1) == m.group(2), p.stderr[-900:])
print('   ' + (re.search(r'TIEMPOS[^\n]*', p.stderr) or [''])[0])
filas = psql('-AtF', '|', '-f', os.path.join(GEN, 'verificacion_carga_flujo_modelo.sql')).stdout.strip().splitlines()
ok(f'15 la verificación de la carga: las {sum(1 for f in filas if not f.startswith("INFO"))} filas OK', filas and all(f.endswith('|OK') for f in filas if not f.startswith('INFO')), '\n'.join(filas))
print('   ' + ' | '.join(f for f in filas if f.startswith('INFO')))
ms, p = carga('carga_flujo_modelo.sql')
ok('16 una segunda carga del mismo archivo se niega (no duplica)', 'ya está cargado' in p.stdout and q("select count(*) from redes.ref_cargas where conjunto = 'flujo_modelo'") == '1', p.stdout[-300:])

# como lo ve producción
tes = q("""select t.x || ', ' || t.y from (select floor((ST_X(ST_PointOnSurface(m.geom)) + 180) / 360 * (1 << 14))::int as x,
  floor((1 - ln(tan(radians(ST_Y(ST_PointOnSurface(m.geom)))) + 1 / cos(radians(ST_Y(ST_PointOnSurface(m.geom))))) / pi()) / 2 * (1 << 14))::int as y
  from redes.activo_vigente_mat m where m.prefijo = 'RED' and not m.retirado) t group by t.x, t.y order by count(*) desc limit 1""")
med = []
for hora, z, xy in (('mayor', 14, tes), ('menor', 14, tes), ('mayor', 16, ', '.join(str(int(v) * 4 + 1) for v in tes.split(', '))), ('mayor', 13, ', '.join(str(int(v) // 2) for v in tes.split(', ')))):
    ms, out, e = edge(f"select public.geoportal_redes_geovisor_mvt_flujo('{SD}', '{hora}', {z}, {xy})")
    med.append((hora, z, ms, len(out) * 3 // 4 // 1024, e[:100]))
ok(f'17 la tesela del flujo como la Edge (service_role, 30 s / 8 s), 4 teselas: la más lenta {max(m[2] for m in med)} ms (tope local {T1:.0f} ms = 1 s / 6): {med}',
   all(not m[4] for m in med) and max(m[2] for m in med) < T1 and med[0][3] > 0, med)
ms, out, e = edge(f"select public.geoportal_redes_flujo_modelo('{SD}')")
j = json.loads(out) if not e else {}
ok(f'18 la información de la capa como la Edge ({ms} ms): {j.get("cobertura")}; horas {[h["texto"] for h in j.get("horas", [])]}', not e and ms < T1 and j['cargado'] and j['cobertura']['con_tramo'] == 8669, e)
cod = q("select a.codigo from redes.flujo_modelo f join redes.activos a on a.id = f.activo_id where f.sentido_mayor <> f.sentido_menor and 'sin_flujo' not in (f.sentido_mayor, f.sentido_menor) order by f.llave limit 1")
ms, out, e = edge(f"select public.geoportal_redes_flujo_tramo('{SD}', '{cod}')")
ok(f'19 la tarjeta de un tramo que cambia de sentido ({cod}) como la Edge ({ms} ms)', not e and ms < T1 and json.loads(out)['cambia_de_sentido'] is True, e or out)
ok('20 el operador no ve el flujo; la API no ve las tablas', edge(f"select public.geoportal_redes_flujo_modelo('{OP}')")[2] != '' and 'permission denied' in edge('select count(*) from redes.flujo_modelo')[2])
ok('21 ningún activo cambió de versión por la carga', q("select count(*) from redes.activo_versiones v where v.creado_en >= (select min(creado_en) from redes.ref_cargas where conjunto = 'flujo_modelo')") == '0')
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('encender_flujo_modelo_editor.sql'))
p2 = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('encender_flujo_modelo_editor.sql'))
ok('21b encender la capa (va de último, con el flujo cargado): queda «activa», sigue «preparada» y solo de supervisores; repetirlo no cambia nada',
   p.returncode == 0 and p2.returncode == 0 and 'activa · preparada · solo supervisores: sí' in p2.stdout
   and q("select estado || fuente || solo_completo::text || activa::text from redes.geovisor_capas where codigo = 'flujo_modelo'") == 'activapreparadatruetrue', p.stderr + p2.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('reversa_redes_corte9b_f3_editor.sql'))
ok('22 con el flujo cargado, la reversa se niega (no borra datos)', p.returncode != 0 and 'no borra datos' in p.stderr, p.stderr)
rehacer('con_f3')
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('encender_flujo_modelo_editor.sql'))
ok('22b sin el flujo cargado, encender la capa se niega (no se enciende vacía)', p.returncode != 0 and 'no está cargado' in p.stderr
   and q("select estado from redes.geovisor_capas where codigo = 'flujo_modelo'") == 'espera_dato', p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('reversa_redes_corte9b_f3_editor.sql'))
ok('23 la reversa (sin datos) se aplica: vuelve la huella de la Fase 2 y la capa queda sin uso (no borrada)',
   p.returncode == 0 and q(CONJ) == MD5_F2 and q("select activa from redes.geovisor_capas where codigo = 'flujo_modelo'") == 'f', p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo('reversa_redes_corte9b_f3_editor.sql'))
ok('24 una segunda reversa se niega', p.returncode != 0 and 'No hay nada que revertir' in p.stderr, p.stderr)
rehacer()
malas = [r for r in res if not r[1]]
print(f'\nRESULTADO: {len(res) - len(malas)} de {len(res)} — ' + ('SIN FALLAS' if not malas else f'{len(malas)} FALLA(S)'))
