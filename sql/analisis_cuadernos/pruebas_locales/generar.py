#!/usr/bin/env python3
"""Arma el paquete SQL de «Cuadernos de análisis» (Code B) y lo prueba en el clúster PROPIO del Code B (55442; NUNCA Supabase ni el 55432).
Base: emdupar_b_cuad_base = emdupar_b_evt (huella de redes de producción) + el bucket analisis-capturas en storage.buckets (en producción lo crea David).
Escribe las versiones _editor (guardia con la huella de técnica PUBLICADA, 838b8098…) y las locales en pruebas_locales/local/ (la misma guardia con la huella
de técnica de la base local, que no trae la PTAR y por eso no es igual a la de producción). La huella de redes es la misma en las dos.
Luego, en copias de la base: migración + verificación (todo OK), reversa sin datos (queda como antes) y con datos (conserva tablas y filas), y el ensayo
(debe terminar en el ERROR esperado SIN FALLAS y no dejar nada).
Uso: python3 -I generar.py [-h]   ·   PSQL_B=<ruta de psql_b> (por omisión, la del scratchpad de esta sesión)."""
import os
import re
import subprocess
import sys

if __name__ == '__main__':
    for _a in sys.argv[1:]:
        if _a in ('-h', '--help'):
            print(__doc__); sys.exit(0)
        print(f'Opción desconocida: {_a} (no lleva opciones; -h para el uso)', file=sys.stderr); sys.exit(2)

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(AQUI)
NOMBRE = 'analisis_cuadernos'
PSQL = os.environ.get('PSQL_B', '/private/tmp/claude-502/-Users-ddiaz-geoportal-emdupar/809ba2b2-a6ad-4744-8abf-376d19a52093/scratchpad/psql_b')
ORIGEN = 'emdupar_b_evt'
BASE = 'emdupar_b_cuad_base'
TMP = 'emdupar_b_cuad_gen'
MD5_REDES = '1ba192724c2fddcf321104700829f3cc'          # producción (corte de eventos publicado)
MD5_TECNICA_PROD = '838b80984e51cc7873a666f85d657195'   # producción, 26-nov (encargo del geovisor técnico)
HUELLA_REDES = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname)) from pg_proc p "
                "where p.pronamespace = 'redes'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_redes\\_%')")
HUELLA_TEC = ("select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.pronamespace::regnamespace::text, p.proname, p.oid::regprocedure::text)) from pg_proc p "
              "where p.prokind = 'f' and (p.pronamespace = 'tecnica'::regnamespace or (p.pronamespace = 'public'::regnamespace and p.proname like 'geoportal\\_tec\\_%'))")
FN = ("pg_proc p join pg_namespace n on n.oid = p.pronamespace where p.prokind = 'f' and (n.nspname = 'analisis' or (n.nspname = 'public' and p.proname like 'geoportal\\_analisis\\_%'))")
HUELLA_ANA = f"select md5(string_agg(md5(pg_get_functiondef(p.oid)), '' order by p.oid::regprocedure::text)) from {FN}"
N_RPC = 12
LOCAL = os.path.join(AQUI, 'local')
RES = os.path.join(RAIZ, 'resultados')

# Columnas REALES de producción de lo que el paquete solo lee (26-nov: el ensayo falló en producción con 42702 porque catastro_valledupar tiene una columna
# «zona» que el doble local no tenía, y una variable del ensayo se llamaba igual). El doble las lleva TODAS, y ninguna variable ni parámetro del paquete
# puede llamarse como una de ellas. Catastro: de la exploración del 2-nov (geoportal-consultas/exploracion_mapa_calor_cartera/salida_propietario.txt);
# de las que el doble no tenía se conoce el nombre y no el tipo: se agregan como text (zona es text en producción). Storage: las del esquema de Supabase.
COLS_CATASTRO = ('id cod_usuario geom direccion barrio otro_barrio comuna sector manzana predio zona departamento municipio codigo_catastral cod_igac cod_predio '
                 'matricula_inmobiliaria nom_edificio ubicm tipo_predio esta_predio estrato clase_uso act_eco unih uninh nro_habitantes nombre apel1 nombre_propie '
                 'apellido_propie tipo_identicacion_propie identicacion_propie email email_propie telefono telefono_propie tip_serv tipconex posee_serv serv_alc '
                 'destp_servalc factura registra des_verttim des_ptohidra nro_med desc_marca elemento_medicion diam_med diam_acom pesee_med estpto_med est_caja lectura '
                 'an_med codanommed posee_llave_pas posee_reg_cort posee_serv_ener med_energ nic_ener sector_hidra subsector_hidra unidad_hidra an_nosus anom_general '
                 'despos_fraude mantenimiento re_pr hayatencion direccion_norm').split()
COLS_STORAGE = {'buckets': {'owner': 'uuid', 'updated_at': 'timestamptz default now()', 'avif_autodetection': 'boolean default false', 'owner_id': 'text', 'type': 'text'},
                'objects': {'updated_at': 'timestamptz default now()', 'last_accessed_at': 'timestamptz default now()',
                            'path_tokens': "text[] generated always as (string_to_array(name, '/')) stored", 'version': 'text', 'owner_id': 'text', 'user_metadata': 'jsonb',
                            'level': 'integer'}}
# Nombres declarados que coinciden con una columna real y se dejan, con su porqué.
NOMBRES_PERMITIDOS = {('20_funciones.sql', 'email'): 'parámetro OUT de analisis.f_acceso, que no lee el catastro (solo llama a redes.f_geovisor_acceso)'}


def q(sql, db):
    return subprocess.run([PSQL, '-d', db, '-AtX', '-c', sql], check=True, capture_output=True, text=True).stdout.strip()


def corre(db, archivo):
    return subprocess.run([PSQL, '-d', db, '-X', '-v', 'ON_ERROR_STOP=1', '-f', archivo], capture_output=True, text=True)


def copia(db, de=BASE):
    """Solo bases de este paquete (emdupar_b_cuad_*): nunca se borra una base que no creó este guion."""
    assert db.startswith('emdupar_b_cuad_'), db
    subprocess.run([PSQL, '-qX', '-d', 'postgres', '-c', f'drop database if exists {db}', '-c', f'create database {db} template {de}'], check=True, capture_output=True)


def leer(ruta):
    return open(ruta, encoding='utf-8').read()


def escribir(ruta, texto):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    open(ruta, 'w', encoding='utf-8').write(texto)


def plantilla(nombre, val):
    t = leer(os.path.join(AQUI, 'plantillas', nombre))
    for k, v in val.items():
        t = t.replace(k, v)
    assert '{{' not in t, (nombre, re.findall(r'\{\{[A-Z_0-9]+\}\}', t))
    return t


def sql(n):
    return leer(os.path.join(RAIZ, 'sql', n))


def preparar_base():
    assert q('show port', 'postgres') == '55442', 'no es el clúster del Code B'
    assert q(HUELLA_REDES, ORIGEN) == MD5_REDES, f'{ORIGEN} no tiene la huella de redes de producción'
    copia(BASE, ORIGEN)
    q("insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('analisis-capturas', 'analisis-capturas', false, 614400, array['image/jpeg'])", BASE)
    assert q("select count(*) from pg_namespace where nspname = 'analisis'", BASE) == '0'
    # el doble con TODAS las columnas reales (solo se agregan; BASE es una copia que crea este guion)
    for c in COLS_CATASTRO:
        q(f'alter table public.catastro_valledupar add column if not exists {c} text', BASE)
    for tabla, cols in COLS_STORAGE.items():
        for c, tipo in cols.items():
            q(f'alter table storage.{tabla} add column if not exists {c} {tipo}', BASE)
    assert q("select string_agg(attname, ' ' order by attname) from pg_attribute where attrelid = 'public.catastro_valledupar'::regclass and attnum > 0 and not attisdropped", BASE) \
        == ' '.join(sorted(COLS_CATASTRO)), 'el doble del catastro no tiene las mismas columnas que producción'
    assert q("select format_type(atttypid, atttypmod) from pg_attribute where attrelid = 'public.catastro_valledupar'::regclass and attname = 'zona'", BASE) == 'text'
    assert q(HUELLA_REDES, BASE) == MD5_REDES
    # el doble reproduce el caso de producción: una variable «zona» sin calificar sobre el catastro da 42702
    p = subprocess.run([PSQL, '-d', BASE, '-X', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose', '-c',
                        "do $$ declare zona text := '{\"type\":\"Point\",\"coordinates\":[-73.25,10.46]}'; n integer; begin "
                        "select count(*) into n from public.catastro_valledupar where st_intersects(geom, st_setsrid(st_geomfromgeojson(zona), 4326)); end $$"],
                       capture_output=True, text=True)
    assert p.returncode != 0 and '42702' in p.stderr, 'el doble del catastro no reproduce el 42702 de producción: ' + p.stderr
    return q(HUELLA_TEC, BASE)


def nombres_reales():
    """Columnas reales de lo que el paquete lee: catastro, redes.v_activo_vigente (la vista es de los paquetes de redes: la local es la de producción) y storage."""
    cols = "select string_agg(attname, ' ') from pg_attribute where attrelid = '%s'::regclass and attnum > 0 and not attisdropped"
    return {'public.catastro_valledupar': set(COLS_CATASTRO), 'redes.v_activo_vigente': set(q(cols % 'redes.v_activo_vigente', BASE).split()),
            'storage.buckets': set(q(cols % 'storage.buckets', BASE).split()), 'storage.objects': set(q(cols % 'storage.objects', BASE).split())}


def auditar_nombres():
    """Ninguna variable, parámetro ni variable de bucle del paquete se llama como una columna real de esas tablas (42702 en producción, 26-nov)."""
    reales = nombres_reales()
    archivos = [os.path.join(RAIZ, 'sql', n) for n in ('20_funciones.sql', '26_rpc.sql', '70_pruebas.sql')] + \
               [os.path.join(AQUI, 'plantillas', n) for n in sorted(os.listdir(os.path.join(AQUI, 'plantillas')))]
    choques, vistos = [], 0
    for ruta in archivos:
        t = re.sub(r'--[^\n]*', '', leer(ruta))
        decl = set()
        for m in re.finditer(r'create (?:or replace )?function\s+[\w.]+\s*\((.*?)\)\s*returns', t, re.S | re.I):
            for p in m.group(1).split(','):
                w = p.split()
                if w:
                    decl.add(w[1] if w[0].lower() in ('out', 'in', 'inout') else w[0])
        for m in re.finditer(r'\bdeclare\b(.*?)\bbegin\b', t, re.S | re.I):
            decl.update(s.split()[0] for s in m.group(1).split(';') if s.split())
        for m in re.finditer(r'\bfor\s+(\w+)(?:\s*,\s*(\w+))?\s+in\b', t, re.I):
            decl.update(x for x in m.groups() if x)
        vistos += len(decl)
        for d in sorted(decl):
            donde = [k for k, v in reales.items() if d.lower() in v]
            if donde and (os.path.basename(ruta), d.lower()) not in NOMBRES_PERMITIDOS:
                choques.append(f'{os.path.basename(ruta)}: «{d}» es columna de {", ".join(donde)}')
    assert vistos > 100, vistos
    assert not choques, 'nombres que chocan con columnas reales:\n' + '\n'.join(choques)
    return vistos


def cuerpo(val):
    return plantilla('10_esquema.sql', val) + sql('20_funciones.sql') + sql('26_rpc.sql') + plantilla('40_permisos.sql', val)


def armar(val, carpeta, sufijo):
    c = cuerpo(val)
    escribir(os.path.join(carpeta, f'migracion_{NOMBRE}{sufijo}.sql'), 'begin;\n' + c + 'commit;\n')
    escribir(os.path.join(carpeta, f'ensayo_en_transaccion_{NOMBRE}{sufijo}.sql'), 'begin;\n' + leer(os.path.join(AQUI, 'plantillas', '06_foto.sql')) + c + sql('70_pruebas.sql') + 'rollback;\n')


def main():
    md5_tec_local = preparar_base()
    n_nombres = auditar_nombres()
    v_prod = {'{{MD5_REDES}}': MD5_REDES, '{{MD5_TECNICA}}': MD5_TECNICA_PROD}
    v_local = {'{{MD5_REDES}}': MD5_REDES, '{{MD5_TECNICA}}': md5_tec_local}
    armar(v_prod, RAIZ, '_editor')
    armar(v_local, LOCAL, '_local')
    for n in ('10_esquema.sql', '40_permisos.sql'):                      # las partes con guardia, ya con las huellas de producción, junto a las demás
        escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, v_prod))

    # migración local → firmas y md5 de lo nuevo, para la verificación y la reversa
    copia(TMP)
    p = corre(TMP, os.path.join(LOCAL, f'migracion_{NOMBRE}_local.sql'))
    if p.returncode != 0:
        raise SystemExit('La migración local falló:\n' + p.stderr[-3000:])
    assert q(HUELLA_REDES, TMP) == MD5_REDES and q(HUELLA_TEC, TMP) == md5_tec_local, 'el paquete no debe cambiar las huellas de redes ni de técnica'
    firmas = q(f"select string_agg(p.oid::regprocedure::text, '|' order by p.oid::regprocedure::text) from {FN}", TMP).split('|')
    rpc = [f for f in firmas if f.startswith('geoportal_analisis_')]
    internas = [f for f in firmas if f.startswith('analisis.')]
    assert len(rpc) == N_RPC and len(rpc) + len(internas) == len(firmas), firmas
    md5s = {f: q(f"select md5(pg_get_functiondef('{f}'::regprocedure))", TMP) for f in firmas}
    md5_ana = q(HUELLA_ANA, TMP)
    extra = {'{{MD5_ANALISIS}}': md5_ana, '{{FIRMAS}}': ', '.join(f"'{f}'" for f in firmas), '{{CASOS}}': ' '.join(f"when '{f}' then '{m}'" for f, m in md5s.items()),
             '{{N_FUNC}}': str(len(firmas)), '{{DROPS_RPC}}': '\n'.join(f'drop function public.{f};' for f in rpc),
             '{{DROPS_INTERNAS}}': '\n'.join(f'  drop function {f};' for f in internas if not f.startswith('analisis.f_cuaderno('))}
    for val, carpeta, suf in ((v_prod, RAIZ, '_editor'), (v_local, LOCAL, '_local')):
        vv = dict(val, **extra)
        escribir(os.path.join(carpeta, f'huellas_solo_lectura_{NOMBRE}{suf}.sql'), plantilla('05_huellas_solo_lectura.sql', vv))
        escribir(os.path.join(carpeta, f'verificacion_{NOMBRE}{suf}.sql'), plantilla('80_verificacion.sql', vv))
        escribir(os.path.join(carpeta, f'reversa_{NOMBRE}{suf}.sql'), 'begin;\n' + plantilla('90_reversa.sql', vv) + 'commit;\n')
    for n in ('05_huellas_solo_lectura.sql', '80_verificacion.sql', '90_reversa.sql'):
        escribir(os.path.join(RAIZ, 'sql', n), plantilla(n, dict(v_prod, **extra)))

    informe = []
    # 1. verificación tras la migración
    p = corre(TMP, os.path.join(LOCAL, f'verificacion_{NOMBRE}_local.sql'))
    informe += ['== verificación tras la migración (local)', p.stdout.strip()]
    assert p.returncode == 0 and 'REVISAR' not in p.stdout and p.stdout.count('| OK') == 12, p.stdout + p.stderr
    # 2. migrar dos veces: la guardia se niega
    p = corre(TMP, os.path.join(LOCAL, f'migracion_{NOMBRE}_local.sql'))
    assert p.returncode != 0 and 'el esquema analisis ya existe' in p.stderr, p.stderr
    informe += ['== segunda migración sobre la misma base: la guardia se niega (esperado)']
    # 3. reversa sin datos: queda como antes y se puede volver a migrar
    p = corre(TMP, os.path.join(LOCAL, f'reversa_{NOMBRE}_local.sql'))
    assert p.returncode == 0 and 'sin datos' in p.stderr, p.stderr
    assert q("select count(*) from pg_namespace where nspname = 'analisis'", TMP) == '0' and q(f'select count(*) from {FN}', TMP) == '0'
    assert q(HUELLA_REDES, TMP) == MD5_REDES and q(HUELLA_TEC, TMP) == md5_tec_local
    assert corre(TMP, os.path.join(LOCAL, f'migracion_{NOMBRE}_local.sql')).returncode == 0, 'tras la reversa sin datos debe poder migrarse otra vez'
    informe += ['== reversa sin datos: sin esquema ni funciones; redes y técnica iguales; se volvió a migrar']
    # 4. reversa con datos: conserva tablas y filas, quita solo las RPC
    sup = q("select email from public.geoportal_lista_blanca where rol = 'admin' and coalesce(activo, true) order by email limit 1", TMP)
    q(f"select public.geoportal_analisis_cuaderno_crear('{sup}', 'ZTCUAD reversa con datos')", TMP)
    p = corre(TMP, os.path.join(LOCAL, f'reversa_{NOMBRE}_local.sql'))
    assert p.returncode == 0 and 'hay datos' in p.stderr, p.stderr
    assert q("select count(*) from analisis.cuadernos", TMP) == '1' and q("select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname like 'geoportal\\_analisis\\_%'", TMP) == '0'
    assert q("select count(*) from pg_trigger g join pg_class c on c.oid = g.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'analisis' and not g.tgisinternal", TMP) == '22'
    informe += ['== reversa con un cuaderno: quita las 12 RPC y conserva las 11 tablas, la fila y los 22 disparadores']
    # 5. ensayo (en una copia limpia; termina en el ERROR esperado y no deja nada)
    copia(TMP)
    p = corre(TMP, os.path.join(LOCAL, f'ensayo_en_transaccion_{NOMBRE}_local.sql'))
    res = (p.stderr or '').strip()
    fin = res[res.index('PRUEBAS DE ANÁLISIS'):] if 'PRUEBAS DE ANÁLISIS' in res else res[-3000:]
    informe += ['== ensayo (local)', fin]
    assert p.returncode != 0 and 'SIN FALLAS' in res, fin
    assert q("select count(*) from pg_namespace where nspname = 'analisis'", TMP) == '0', 'el ensayo dejó algo'
    assert q("select count(*) from public.geoportal_lista_blanca where email like 'prueba.cuad.%'", TMP) == '0' and q("select count(*) from storage.objects where bucket_id = 'analisis-capturas'", TMP) == '0'
    subprocess.run([PSQL, '-qX', '-d', 'postgres', '-c', f'drop database if exists {TMP}'], check=True, capture_output=True)
    resumen = (f'huella de redes {MD5_REDES} (no cambia) · técnica PRODUCCIÓN {MD5_TECNICA_PROD} (guardia del _editor; no cambia) · técnica local {md5_tec_local} (no cambia) · '
               f'huella de análisis {md5_ana} · {len(firmas)} funciones ({N_RPC} RPC y {len(internas)} internas)')
    informe.insert(0, f'== nombres: {n_nombres} variables y parámetros del paquete revisados contra las columnas REALES de catastro_valledupar ({len(COLS_CATASTRO)}), '
                      'redes.v_activo_vigente, storage.buckets y storage.objects: ninguno coincide (salvo los permitidos: ' + '; '.join(f'{k[1]} — {v}' for k, v in NOMBRES_PERMITIDOS.items()) + ')')
    informe.insert(0, resumen)
    escribir(os.path.join(RES, 'sql_local.txt'), '\n'.join(informe) + '\n')
    print(resumen)
    print(re.search(r'RESULTADO: .*', res).group(0))


if __name__ == '__main__':
    main()
