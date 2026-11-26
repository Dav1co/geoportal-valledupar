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
N_RPC = 11
LOCAL = os.path.join(AQUI, 'local')
RES = os.path.join(RAIZ, 'resultados')


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
    return q(HUELLA_TEC, BASE)


def cuerpo(val):
    return plantilla('10_esquema.sql', val) + sql('20_funciones.sql') + sql('26_rpc.sql') + plantilla('40_permisos.sql', val)


def armar(val, carpeta, sufijo):
    c = cuerpo(val)
    escribir(os.path.join(carpeta, f'migracion_{NOMBRE}{sufijo}.sql'), 'begin;\n' + c + 'commit;\n')
    escribir(os.path.join(carpeta, f'ensayo_en_transaccion_{NOMBRE}{sufijo}.sql'), 'begin;\n' + leer(os.path.join(AQUI, 'plantillas', '06_foto.sql')) + c + sql('70_pruebas.sql') + 'rollback;\n')


def main():
    md5_tec_local = preparar_base()
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
    assert q("select count(*) from pg_trigger g join pg_class c on c.oid = g.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'analisis' and not g.tgisinternal", TMP) == '20'
    informe += ['== reversa con un cuaderno: quita las 11 RPC y conserva las 10 tablas, la fila y los 20 disparadores']
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
    informe.insert(0, resumen)
    escribir(os.path.join(RES, 'sql_local.txt'), '\n'.join(informe) + '\n')
    print(resumen)
    print(re.search(r'RESULTADO: .*', res).group(0))


if __name__ == '__main__':
    main()
