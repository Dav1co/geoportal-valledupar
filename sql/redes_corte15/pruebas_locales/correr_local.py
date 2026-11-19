#!/usr/bin/env python3
"""Arnés local del Corte 15 «Evento de suspensión» (Code A, localhost:55432, base redes_local = producción al 18-nov, huella 63d91763…, con los CHECK, llaves y
disparadores de sus migraciones):
  · el ensayo (N de N … SIN FALLAS, con TIEMPOS) y que no deja nada; huellas; migración; verificación; segunda migración; reversa limpia y vuelta a aplicar;
  · que solo reemplaza tecnica.f_avisos y redes.f_publicar_l116: ninguna otra función anterior cambia de texto;
  · como la ve producción (service_role, 30 s / 8 s) con perfiles sintéticos sobre LA RED REAL de la base (35.781 activos, 104 mil contratos con tramo): un sector
    sintético que cubre toda la red, declarar, la asociación de un reporte del bot, de un daño por formulario, de un reporte del formato de campo y de una carga de
    la 116, avisos, detalle, cierre, y una publicación REAL de la 116 (por el motor del Cargue) con los 2.500 reportes que cerró el evento otra vez en «Registrado»;
  · que la reversa SE NIEGA cuando ya hay eventos (no borra hechos).
Tope local de cada llamada: 1 s / 6 (producción es unas 6 veces más lenta).
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
NOMBRE = 'redes_corte15'
ENV = dict(os.environ, PGHOST='localhost', PGPORT='55432', PGUSER='postgres', PGOPTIONS='-c client_min_messages=warning')
CONJ = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
        "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
MD5_ANTES = '63d917635b33e3696f28a3b0e579c002'
AVISOS = "select md5(pg_get_functiondef('tecnica.f_avisos(boolean,boolean,timestamptz)'::regprocedure))"
PUBLICAR = "select md5(pg_get_functiondef('redes.f_publicar_l116(bigint,text,text)'::regprocedure))"
N_NUEVAS = 36
# todas las funciones anteriores menos las dos que se reemplazan (tecnica.f_avisos y redes.f_publicar_l116) y las nuevas
VIEJAS = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) from pg_proc p "
          "where (p.pronamespace in ('redes'::regnamespace, 'tecnica'::regnamespace, 'campo'::regnamespace) or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_%')) "
          "and p.prokind = 'f' and not (p.pronamespace = 'tecnica'::regnamespace and p.proname = 'f_avisos') and not (p.pronamespace = 'redes'::regnamespace and p.proname = 'f_publicar_l116') "
          "and not (p.pronamespace = 'redes'::regnamespace and (p.proname like 'f\\_evento%' or p.proname in ('f_sin_agua_para_avisos', 'f_reporte_externo_recibir_evento'))) "
          "and not (p.pronamespace = 'public'::regnamespace and (p.proname like 'geoportal\\_redes\\_evento%' or p.proname = 'geoportal_redes_planta_sectores_fijar'))")
ADM, SD, SP, OP, NA = ('zt15.arnes.adm@emdupar.gov.co', 'zt15.arnes.dist@emdupar.gov.co', 'zt15.arnes.planta@emdupar.gov.co', 'zt15.arnes.op@emdupar.gov.co', 'zt15.arnes.nada@emdupar.gov.co')
T1 = 1000 / 6
res = []


def ok(nombre, cond, det=''):
    res.append((nombre, bool(cond), str(det)[:600]))
    print(('OK    ' if cond else 'FALLA ') + nombre + ('' if cond else ' → ' + str(det)[:600]), flush=True)


def psql(*args, check=False):
    return subprocess.run([PSQL, '-d', BASE, '-X', *args], env=ENV, capture_output=True, text=True, check=check)


def q(sql):
    return psql('-At', '-c', sql, check=True).stdout.strip()


def rehacer(con=''):
    subprocess.run(['sh', os.path.join(AQUI, 'rehacer_base.sh')] + ([con] if con else []), env=ENV, check=True, capture_output=True)


def edge(sql):
    """Como la llama la Edge: rol de la API y los topes de producción."""
    t0 = time.time()
    p = psql('-Atq', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-c', 'set role service_role', '-c', "set statement_timeout = '30s'", '-c', "set lock_timeout = '8s'", '-c', sql)
    return round((time.time() - t0) * 1000), p.stdout.strip(), (p.stderr.strip() if p.returncode else '')


def interna(sql):
    """Lo que no llama la Edge (el bot del Dell, la publicación de una carga): como dueño, midiendo el tiempo."""
    t0 = time.time()
    p = psql('-Atq', '-v', 'ON_ERROR_STOP=1', '-c', "set statement_timeout = '30s'", '-c', sql)
    return round((time.time() - t0) * 1000), p.stdout.strip(), (p.stderr.strip() if p.returncode else '')


def lit(o):
    return "'" + json.dumps(o, ensure_ascii=False).replace("'", "''") + "'::jsonb"


def archivo(n):
    return os.path.join(RAIZ, n)


def js(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


rehacer()
viejas0, avisos0, pub0, aud0 = q(VIEJAS), q(AVISOS), q(PUBLICAR), q('select count(*) from public.geoportal_auditoria')
tipos0 = q("select count(*) from campo.tipos_reporte")
p = psql('-q', '-f', archivo(f'ensayo_en_transaccion_{NOMBRE}_editor.sql'))
m = re.search(r'RESULTADO: (\d+) de (\d+) pruebas correctas — SIN FALLAS', p.stderr)
ok(f'01 el ensayo termina en el ERROR esperado: {m.group(1) if m else "?"} de {m.group(2) if m else "?"} … SIN FALLAS', m and m.group(1) == m.group(2) and 'esperado' in p.stderr, p.stderr[-1500:])
for linea in re.findall(r'TIEMPOS[^\n]*', p.stderr):
    print('   ' + linea)
ok('02 … y no deja nada (siguen la huella anterior, tecnica.f_avisos y redes.f_publicar_l116; no están las tablas ni el tipo sin_agua, ni un reporte, ni una carga, ni una fila de auditoría)',
   q(CONJ) == MD5_ANTES and q(AVISOS) == avisos0 and q(PUBLICAR) == pub0 and q('select count(*) from campo.reportes') == '0' and q("select count(*) from redes.cargas where capa_codigo = 'linea_116'") == '0' and q("select coalesce(to_regclass('redes.eventos_suspension')::text, '')") == '' and q("select count(*) from campo.tipos_reporte") == tipos0
   and q('select count(*) from redes.reportes_externos') == '0' and q('select count(*) from redes.danos') == '0' and q('select count(*) from public.geoportal_auditoria') == aud0)
filas = psql('-AtF', '|', '-f', archivo(f'huellas_solo_lectura_{NOMBRE}_editor.sql')).stdout.strip().splitlines()
ok(f'03 las huellas antes: «CORRECCIÓN DEL 9b (lista para el 15)», f_avisos «LA DEL CORTE 14», f_publicar_l116 «LA PUBLICADA (Corte 5d)», {N_NUEVAS} nuevas que no existen, las 4 publicadas igual y las tablas «NO EXISTEN»',
   any('lista para el 15' in f for f in filas) and any('LA DEL CORTE 14' in f for f in filas) and sum('NO EXISTE (sin aplicar)' in f for f in filas) == N_NUEVAS
   and sum('LA PUBLICADA' in f for f in filas) == 5 and sum('LA PUBLICADA (Corte 5d)' in f for f in filas) == 1 and any('NO EXISTEN (sin aplicar)' in f for f in filas) and not any('DISTINTA' in f or 'FALTA' in f for f in filas), '\n'.join(filas)[-1500:])
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'migracion_{NOMBRE}_editor.sql'))
ok('04 la migración se aplica', p.returncode == 0, p.stderr)
ok('05 SOLO reemplaza tecnica.f_avisos y redes.f_publicar_l116: ninguna otra función anterior de redes, tecnica, campo ni public.geoportal_* cambió de texto',
   q(VIEJAS) == viejas0 and q(AVISOS) != avisos0 and q(PUBLICAR) != pub0)
filas = psql('-AtF', '|', '-f', archivo(f'huellas_solo_lectura_{NOMBRE}_editor.sql')).stdout.strip().splitlines()
ok(f'06 las huellas después: «CORTE 15 (aplicado)», f_avisos y f_publicar_l116 «CORTE 15 (reemplazada)», {N_NUEVAS} nuevas y las tablas «EXISTEN»', any('CORTE 15 (aplicado)' in f for f in filas)
   and sum('CORTE 15 (reemplazada)' in f for f in filas) == 2 and sum('NUEVA (aplicada)' in f for f in filas) == N_NUEVAS and any('|EXISTEN' in f for f in filas) and not any('DISTINTA' in f or 'FALTA' in f for f in filas), '\n'.join(filas)[-900:])
filas = psql('-AtF', '|', '-f', archivo(f'verificacion_{NOMBRE}_editor.sql')).stdout.strip().splitlines()
ok(f'07 la verificación: las {sum(1 for f in filas if not f.startswith("INFO"))} filas OK', filas and all(f.endswith('|OK') for f in filas if not f.startswith('INFO')), '\n'.join(filas))
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'migracion_{NOMBRE}_editor.sql'))
ok('08 una segunda migración se niega', p.returncode != 0 and 'ya está aplicado' in p.stderr, p.stderr)
ok('09 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', q('select count(*) from redes.f_funciones_sin_where()') == '0')
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'reversa_{NOMBRE}_editor.sql'))
ok('10 la reversa (sin eventos) se aplica: vuelven la huella anterior, tecnica.f_avisos y redes.f_publicar_l116 con su texto exacto; las demás funciones siguen igual; «sin_agua» queda desactivado (no se borra); campo.reportes queda sin el disparador',
   p.returncode == 0 and q(CONJ) == MD5_ANTES and q(AVISOS) == avisos0 and q(PUBLICAR) == pub0 and q(VIEJAS) == viejas0 and q("select activo from campo.tipos_reporte where codigo = 'sin_agua'") == 'f'
   and q("select count(*) from pg_trigger where tgname = 't_evento_asociar'") == '0', p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'reversa_{NOMBRE}_editor.sql'))
ok('11 una segunda reversa se niega', p.returncode != 0 and 'No hay nada que revertir' in p.stderr, p.stderr)
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'migracion_{NOMBRE}_editor.sql'))
ok('12 después de la reversa, la migración se vuelve a aplicar: «sin_agua» activo otra vez y los parámetros con su descripción',
   p.returncode == 0 and q("select activo from campo.tipos_reporte where codigo = 'sin_agua'") == 't'
   and q("select count(*) from redes.parametros where clave like 'evento\\_%' and descripcion like 'Evento de suspensión%'") == '5', p.stderr)

# ---------- como la ve producción: perfiles sintéticos sobre la red real ----------
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, horario, dias) values ('{ADM}', 'ZT15 arnés admin', 'admin', 'sin_restriccion', 'todos'), ('{NA}', 'ZT15 arnés sin Técnica', 'consulta', 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_redes, horario, dias) values ('{SD}', 'ZT15 arnés supervisor de distribución', 'consulta', true, true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, ver_dashboard_tecnico, horario, dias) values ('{SP}', 'ZT15 arnés supervisor de planta', 'consulta', true, true, 'sin_restriccion', 'todos')")
q(f"insert into public.geoportal_lista_blanca (email, nombre, rol, ver_registro_tecnico, horario, dias) values ('{OP}', 'ZT15 arnés operador', 'consulta', true, 'sin_restriccion', 'todos')")
q(f"insert into tecnica.personal_tecnico_eventos (persona, tipo_evento, formulario, autor) values ('{OP}', 'asignar_formulario', 'danos_fallas', '{ADM}')")
# un sector sintético que cubre toda la red real (la base local no trae los 36 sectores de producción)
SEC = q(f"""do $$ declare v_cons bigint; v_id bigint; begin
  update redes.consecutivos set ultimo = ultimo + 1 where prefijo = 'SEC' returning ultimo into v_cons;
  insert into redes.activos (codigo, prefijo, origen_alta, creado_por) values ('SEC-' || lpad(v_cons::text, 6, '0'), 'SEC', 'carga', '{ADM}') returning id into v_id;
  insert into redes.activo_versiones (activo_id, version, geom, nombre, clase, estado_codigo, atributos, huella, autor)
  select v_id, 1, ST_SetSRID(ST_Extent(m.geom)::geometry, 4326), 'ZT15 sector de toda la red', 'sector', 'en_operacion', '{{}}'::jsonb, md5('zt15'), '{ADM}' from redes.activo_vigente_mat m where m.prefijo = 'RED' and m.sistema = 'acueducto';
  insert into redes.activo_origen (activo_id, version, origen, nota, autor) values (v_id, 1, 'emdupar', 'ZT15 sector sintético del arnés', '{ADM}');
  perform redes.f_mat_refrescar_uno(v_id);
end $$; select codigo from redes.activo_vigente_mat where nombre = 'ZT15 sector de toda la red'""").splitlines()[-1]      # (la primera línea es el «DO»)
q("insert into redes.usuarios_sensibles (contrato, tipo, palabra, origen, autor) select ct.contrato, 'hospital', null, 'manual', '%s' from redes.contrato_tramo ct order by md5(ct.contrato) limit 240" % ADM)
q("insert into redes.usuario_sensible_eventos (contrato, accion, tipo, motivo, autor) select contrato, 'confirmar', 'hospital', 'ZT15 sensible sintético del arnés', '%s' from redes.usuarios_sensibles" % ADM)
contratos = int(q('select count(*) from redes.contrato_tramo'))
ms, out, e = edge(f"select public.geoportal_redes_evento_catalogo('{SD}')")
ok(f'13 el catálogo como la Edge ({ms} ms; tope local {T1:.0f} ms): trae el sector sintético y los 15 tipos', not e and ms < T1 and SEC in out and len(js(out).get('tipos', [])) == 15, e or out[:200])
ms, out, e = edge(f"select public.geoportal_redes_evento_vista_previa('{SD}', {lit({'alcance': 'sectores', 'sectores': [SEC]})})")
vp = js(out)
ok(f'14 la vista previa de toda la red como la Edge ({ms} ms): {vp.get("contratos")} contratos y {vp.get("sensibles")} usuarios sensibles confirmados', not e and ms < T1 and vp.get('contratos') == contratos and vp.get('sensibles') == 240, e or out[:300])
hace = q("select to_char(now() - interval '20 minutes', 'YYYY-MM-DD\"T\"HH24:MI:SSOF')")
luego = q("select to_char(now() + interval '3 hours', 'YYYY-MM-DD\"T\"HH24:MI:SSOF')")
ms, out, e = edge(f"select public.geoportal_redes_evento_declarar('{SD}', {lit({'alcance': 'sectores', 'sectores': [SEC], 'causa': 'ZT15 daño grande del arnés', 'desde': hace, 'regreso': luego})})")
ev = js(out)
EVS = ev.get('codigo')
ok(f'15 DECLARAR como la Edge ({ms} ms): {EVS}, {ev.get("contratos")} contratos, {ev.get("sensibles")} sensibles', not e and ms < T1 and EVS and ev['contratos'] == contratos and ev['sensibles'] == 240, e or out[:300])
centro = js(q("select jsonb_build_object('lat', round(ST_Y(ST_Centroid(geom))::numeric, 6), 'lon', round(ST_X(ST_Centroid(geom))::numeric, 6)) from redes.activo_vigente_mat where codigo = '%s'" % SEC))
ms, out, e = interna(f"select redes.f_reporte_externo_recibir_evento({lit({'radicado': 'ZT15-A001', 'canal': 'telegram', 'tipo': 'sin_agua', **centro})})")
b = js(out)
ok(f'16 BOT: un «sin agua» nuevo se asocia solo ({ms} ms con la conexión; tope 1 s en producción → local {T1:.0f} ms) y recibe «{b.get("mensaje")}»',
   not e and ms < T1 and b.get('evento') == EVS and str(b.get('mensaje', '')).startswith('Ya sabemos del corte en tu sector. Regreso estimado: '), e or out[:300])
ok('17 … la API no puede llamar la función del bot ni las internas (42501); su permiso para el Dell va en otro paquete',
   '42501' in edge("select redes.f_reporte_externo_recibir_evento('{}'::jsonb)")[2] and '42501' in edge("select * from redes.f_eventos_abiertos()")[2])
# un daño por formulario, con las RPC publicadas, sobre un tramo real
tramo = js(q("select jsonb_build_object('codigo', m.codigo, 'lat', round(ST_Y(ST_PointOnSurface(m.geom))::numeric, 6), 'lon', round(ST_X(ST_PointOnSurface(m.geom))::numeric, 6)) "
             "from redes.activo_vigente_mat m where m.codigo = 'RED-000077'"))
_, out, e = edge(f"select public.geoportal_redes_preparar_dano('{OP}', 1)")
prep = js(out)
if prep:
    q(f"insert into storage.objects (bucket_id, name, metadata) values ('redes-evidencias', '{prep['fotos'][0]['ruta']}', '{{\"size\": 300000, \"mimetype\": \"image/jpeg\"}}')")
ahora5 = q("select to_char(now() - interval '5 minutes', 'YYYY-MM-DD\"T\"HH24:MI:SSOF')")
ms, out, e = edge("select public.geoportal_redes_crear_dano('%s', '%s', %s)" % (OP, prep.get('dano_id'), lit({
    'clase': 'dano', 'tipo': 'fuga', 'sistema': 'acueducto', 'ubicacion_origen': 'mapa', 'activo': tramo.get('codigo'), 'lat': tramo.get('lat'), 'lon': tramo.get('lon'),
    't_detectado': ahora5, 'tipo_rotura': 'parcial', 'riesgo': 'medio', 'causa_clase': 'desconocida', 'fotos': [{'n': 1, 'momento': 'dano', 'ruta': prep.get('fotos', [{}])[0].get('ruta')}]})))
dan = js(out).get('codigo')
ok(f'18 DAÑO: el operador reporta un daño dentro de la zona como la Edge ({ms} ms): se crea ({dan}) y queda asociado, con la nota; sigue «Reportado»',
   not e and ms < T1 and dan and q(f"select count(*) from redes.evento_suspension_reportes r join redes.danos d on d.id = r.dano_id where d.codigo = '{dan}'") == '1'
   and q(f"select estado from redes.v_dano where codigo = '{dan}'") == 'reportado', e or out[:300])
# un «sin agua» del formato de campo hecho desde Comercial (la fila que deja geoportal_campo_crear_reporte), en el centro de la zona
ms, out, e = interna("insert into campo.reportes (id, tipo_id, lat, lon, origen, autor) select gen_random_uuid(), t.id, %s, %s, 'campo', 'zt15.arnes.comercial@emdupar.gov.co' "
                     "from campo.tipos_reporte t where t.codigo = 'sin_agua' returning id" % (centro.get('lat'), centro.get('lon')))
CAMPO = out.splitlines()[0] if out else ''
ok(f'18b FORMATO DE CAMPO: un «sin agua» hecho desde Comercial dentro de la zona ({ms} ms con la conexión) se guarda, queda asociado y recibe la nota; sigue «Reportado»',
   not e and ms < T1 and q(f"select count(*) from redes.evento_suspension_reportes where origen = 'campo' and ref = '{CAMPO}'") == '1'
   and q(f"select estado from campo.v_reportes_estado where id = '{CAMPO}'") == 'reportado' and q(f"select count(*) from campo.reporte_eventos where reporte_id = '{CAMPO}' and tipo_evento = 'nota'") == '1', e or out[:300])
# una carga de la 116: 5.000 reportes nuevos en una sentencia (como al publicar), sobre contratos reales con su tramo
q(f"insert into redes.cargas (capa_codigo, sha256, formato, srid_origen, columna_llave, filas_esperadas, nota, autor) values ('acueducto', md5('zt15-arnes-a') || md5('zt15-arnes-b'), 'shp', 4326, 'ID', 1, 'ZT15 carga del arnés', '{ADM}')")
ms, out, e = interna(f"""with r as (
    insert into redes.l116_reportes (reporte, fecha_registro, servicio, causal, contrato, carga_id)
    select 970000000 + row_number() over (), clock_timestamp(), 'Acueducto', case when row_number() over () % 2 = 0 then 'Sin servicio de agua' else 'Fuga en el medidor' end, x.contrato, (select max(id) from redes.cargas)
      from (select ct.contrato from redes.contrato_tramo ct where ct.contrato ~ '^[0-9]{{1,15}}$' order by md5(ct.contrato) limit 5000) x
    returning id, contrato)
  insert into redes.l116_eventos (reporte_id, tipo, estado, metodo, geom, carga_id, motivo, autor)
  select r.id, 'alta', 'registrado', 'contrato', ST_PointOnSurface(m.geom), (select max(id) from redes.cargas), 'ZT15 carga del arnés', '{ADM}'
    from r join redes.contrato_tramo ct on ct.contrato = r.contrato join redes.activo_vigente_mat m on m.activo_id = ct.activo_id""")
n116 = int(q("select count(*) from redes.evento_suspension_reportes where origen = 'l116'"))
ok(f'19 LÍNEA 116: una carga de 5.000 reportes nuevos en una sentencia ({ms} ms en total, {ms / 5000:.3f} ms por reporte): asocia los {n116} «sin agua» y ninguna «fuga en el medidor»',
   not e and ms < 1000 and n116 == 2500, e)
q("insert into redes.l116_vigente (reporte_id, reporte, fecha_registro, dia, servicio, causal, contrato, estado, estado_desde, metodo, geom) "
  "select l.id, l.reporte, l.fecha_registro, (l.fecha_registro at time zone 'America/Bogota')::date, l.servicio, l.causal, l.contrato, 'registrado', l.fecha_registro, 'contrato', e.geom "
  "from redes.l116_reportes l join redes.l116_eventos e on e.reporte_id = l.id and e.tipo = 'alta'")
ms, out, e = edge(f"select public.geoportal_tec_avisos('{SD}')")
av = [a for a in js(out).get('avisos', []) if a['clave'].startswith('evento_suspension_')]
ok(f'20 AVISOS como la Edge ({ms} ms): UN aviso por el evento, con sus {av[0]["n"] if av else "?"} reportes asociados', not e and ms < T1 * 2 and len(av) == 1 and av[0]['n'] == 2503, e or out[:300])
ms, out, e = edge(f"select public.geoportal_redes_eventos_vigentes('{OP}')")
vig = js(out)
ok(f'21 los eventos vigentes como la Edge, para el operador ({ms} ms): la zona y la franja; sin datos de suscriptores',
   not e and ms < T1 and len(vig.get('eventos', [])) == 1 and vig['eventos'][0]['zona_geojson']['type'] == 'MultiPolygon' and not re.search(r'suscriptor|tel[eé]fono|direcci[oó]n|@emdupar', out, re.I), e or out[:300])
ms, out, e = edge(f"select public.geoportal_redes_evento('{SD}', '{EVS}')")
det = js(out)
ok(f'22 el detalle como la Edge ({ms} ms): lista 200 de {det.get("reportes", {}).get("total")} asociados y los {len(det.get("sensibles_lista", []))} sensibles (contrato y tipo, sin nombre)',
   not e and ms < T1 * 2 and len(det.get('asociados', [])) == 200 and len(det.get('sensibles_lista', [])) == 240 and set(det['sensibles_lista'][0]) == {'contrato', 'tipo'}
   and not re.search(r'suscriptor|tel[eé]fono|direcci[oó]n|@emdupar', out, re.I), e or out[:300])
ok('23 quién: el operador no declara ni ve el detalle; el supervisor de planta no cierra un evento por sectores; alguien sin Técnica no ve nada (42501)',
   '42501' in edge(f"select public.geoportal_redes_evento('{OP}', '{EVS}')")[2] and '42501' in edge(f"select public.geoportal_redes_evento_cerrar('{SP}', '{EVS}', 'ZT15 ya volvió el agua')")[2]
   and '42501' in edge(f"select public.geoportal_redes_eventos_vigentes('{NA}')")[2])
p = psql('-q', '-v', 'ON_ERROR_STOP=1', '-f', archivo(f'reversa_{NOMBRE}_editor.sql'))
ok('24 con eventos declarados, la reversa SE NIEGA (no borra hechos) y no cambia nada', p.returncode != 0 and 'no borra hechos' in p.stderr and q(f"select count(*) from redes.eventos_suspension") == '1', p.stderr)
ms, out, e = edge(f"select public.geoportal_redes_evento_cerrar('{SD}', '{EVS}', 'ZT15 reparado: fin de la prueba del arnés')")
ce = js(out)
ok(f'25 CERRAR EN BLOQUE como la Edge ({ms} ms): {ce.get("cerrados")}; el daño sigue abierto', not e and ms < T1 * 2 and ce.get('cerrados') == {'bot': 1, 'l116': 2500, 'campo': 1} and ce.get('danos_siguen_abiertos') == 1
   and q(f"select estado from redes.v_dano where codigo = '{dan}'") == 'reportado' and q("select count(*) from redes.l116_vigente where estado = 'atendido'") == '2500'
   and q(f"select estado from campo.v_reportes_estado where id = '{CAMPO}'") == 'atendido', e or out[:300])
ms, out, e = interna(f"select redes.f_reporte_externo_recibir_evento({lit({'radicado': 'ZT15-A002', 'canal': 'telegram', 'tipo': 'sin_agua', **centro})})")
ok(f'26 después del cierre, un «sin agua» nuevo ya no se asocia ({ms} ms) y sale en el aviso de «sin agua sin evento»',
   not e and js(out).get('evento') is None and any(a['clave'] == 'sin_agua_sin_evento' for a in js(edge(f"select public.geoportal_tec_avisos('{SD}')")[1]).get('avisos', [])), e or out[:300])
# ---------- una publicación REAL de la línea 116 como la Edge (iniciar, lotes de 200, resumen y publicar): el archivo trae otra vez en «Registrado» los 2.500
# reportes que cerró el evento, y los otros 2.500 («fuga en el medidor», que no estaban en el evento) en «Atendido»
reps = q("select string_agg(reporte || ':' || estado, ',' order by reporte) from redes.l116_vigente").split(',')
fecha = q("select to_char((now() at time zone 'America/Bogota') - interval '2 minutes', 'YYYY-MM-DD HH24:MI:SS')")
filas116 = [{'orden': i + 1, 'wkt': None, 'atributos': {'REPORTE': int(r.split(':')[0]), 'ESTADO': 'Registrado' if r.endswith(':atendido') else 'Atendido', 'FECHA_REGISTRO': fecha, 'CONTRATO': '0',
                                                         'DIRECCION': 'CL ZT15 1 2 3', 'BARRIO': 'ZT15', 'COMUNA': 'COMUNA 5', 'DESC_CAUSAL': 'Sin servicio de agua', 'SERVICIO': 'Acueducto'}}
            for i, r in enumerate(reps)]
ms, out, e = edge(f"select public.geoportal_redes_cargue_iniciar('{SD}', 'linea_116', md5('zt15-arnes-116') || md5('zt15-arnes-116b'), 'xlsx', 4326, 'reporte', {len(filas116)}, 'ZT15 archivo del arnés')")
CARGA = js(out).get('carga_id')
ms_lote = 0
for k in range(0, len(filas116), 200):
    ms, out, e2 = edge(f"select public.geoportal_redes_carga_lote('{SD}', {CARGA}, {lit(filas116[k:k + 200])})")
    ms_lote, e = max(ms_lote, ms), e or e2
ms_res, out, e2 = edge(f"select public.geoportal_redes_carga_resumen('{SD}', {CARGA})")
res116 = js(out)
ms_pub, out, e3 = edge(f"select public.geoportal_redes_carga_publicar('{SD}', {CARGA}, 'ZT15 carga del arnés después del cierre del evento')")
pub = js(out)
ok(f'27 PUBLICACIÓN REAL de la 116 como la Edge, después del cierre (5.000 filas; lote más lento {ms_lote} ms, resumen {ms_res} ms, publicar {ms_pub} ms; tope local 1 s): '
   f'{pub.get("conservados_por_evento")} conservados por el evento y {pub.get("cambios_estado")} cambios de estado normales',
   not (e or e2 or e3) and res116.get('lista_para_publicar') is True and pub.get('conservados_por_evento') == 2500 and pub.get('cambios_estado') == 2500 and max(ms_lote, ms_res, ms_pub) < 1000, (e or e2 or e3 or out)[:400])
ok('28 … ninguno de los 2.500 que cerró el evento revivió (siguen «Atendido»), cada uno con la diferencia anotada en su historial; los otros 2.500 pasaron a «Atendido» como siempre',
   q("select count(*) from redes.l116_vigente where estado = 'atendido'") == '5000'
   and q("select count(*) from redes.l116_eventos where tipo = 'estado' and estado = 'atendido' and estado_antes = 'atendido' and carga_id is null and motivo like 'La carga %conserva «Atendido»%" + str(EVS) + "'") == '2500'
   and q(f"select count(*) from redes.l116_eventos where tipo = 'estado' and estado = 'atendido' and estado_antes = 'registrado' and carga_id = {CARGA}") == '2500')
rehacer()
malas = [r for r in res if not r[1]]
print(f'\nRESULTADO: {len(res) - len(malas)} de {len(res)} — ' + ('SIN FALLAS' if not malas else f'{len(malas)} FALLA(S)'))
