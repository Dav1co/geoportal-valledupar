#!/usr/bin/env python3
"""[Code B] Rehace el doble local de producción para el paquete campo_inv_analisis. NUNCA Supabase.

Parte del doble con la huella de campo publicada (261bed3c…) y le copia, tal cual, el catálogo de
campo que devuelve `consulta_produccion_doble_editor.sql` corrida por David en producción:
formularios y grupos (con sus id), los campos, fotos y causales de la Investigación de ubicación,
actividades, catálogo de derivadas, formularios con documento y secuencias. Después corre la misma
consulta contra el doble y compara fila por fila: la estructura (5), los md5 (6), las huellas (7) y
los nombres libres (8) deben ser iguales; los conteos (4) solo se informan, salvo los registros de la
Investigación, que deben ser iguales.

Uso:
  python3 rehacer_doble.py --csv produccion_doble.csv [--base doble.sql] [--db emdupar_b_inv_doble]

Solo borra (DROP DATABASE) una base que este mismo guion creó: la reconoce por su comentario.
Porqué y alcance del DROP: rehacer el doble desde cero en cada corrida; alcance, la base `--db` y
nada más, solo si su comentario es el que pone este guion. Cualquier otra base con ese nombre → error.
Dentro de la base, el catálogo se reescribe con session_replication_role = replica (sin disparadores
de protección): es un doble que se arma desde un volcado, no datos reales.
"""
import argparse, csv, json, os, re, subprocess, sys, tempfile
from datetime import datetime, timezone

AQUI = os.path.dirname(os.path.abspath(__file__))
CONSULTA = os.path.join(AQUI, '..', 'consulta_produccion_doble_editor.sql')
BASE_DOBLE = os.path.expanduser('~/geoportal-consultas/campo/admin_perfiles_22nov/doble_admin_4a/doble_admin_permisos_4a_con_cargo_supervisor.sql')
PSQL = '/opt/homebrew/opt/postgresql@17/bin/psql'
MARCA = 'creada por rehacer_doble.py (Code B, campo_inv_analisis)'


def psql(db, *args, entrada=None, ok=True):
    env = dict(os.environ, PGHOST='localhost', PGPORT=os.environ.get('PGPORT_B', '55442'), PGUSER='postgres')
    r = subprocess.run([PSQL, '-X', '-v', 'ON_ERROR_STOP=1', '-d', db, *args], input=entrada, text=True, capture_output=True, env=env)
    if ok and r.returncode != 0:
        sys.exit(f'psql falló ({db}):\n{r.stderr[-3000:]}')
    return r


FECHA = re.compile(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?([+-]\d{2}(:?\d{2})?|Z)$')


def _norm(x):
    """Las fechas se comparan en UTC (el editor de Supabase muestra UTC; el clúster local, hora de Colombia)."""
    if isinstance(x, dict):
        return {k: _norm(v) for k, v in x.items()}
    if isinstance(x, list):
        return [_norm(v) for v in x]
    if isinstance(x, str) and FECHA.match(x):
        t = x.replace(' ', 'T').replace('Z', '+00:00')
        if re.search(r'[+-]\d{2}$', t):
            t += ':00'
        return datetime.fromisoformat(t).astimezone(timezone.utc).isoformat()
    return x


def igual(p, d):
    if p == d:
        return True
    try:
        return _norm(json.loads(p)) == _norm(json.loads(d))
    except (ValueError, TypeError):
        return False


def leer_csv(ruta):
    with open(ruta, encoding='utf-8-sig', newline='') as f:
        filas = list(csv.reader(f))
    if filas and [c.strip().lower() for c in filas[0]] == ['k', 'v']:
        filas = filas[1:]
    d = {}
    for k, v in filas:
        if k in d:
            sys.exit(f'Clave repetida en el CSV: {k}')
        d[k] = v
    return d


APLICAR = r"""
begin;
set local session_replication_role = replica;
create schema zz_doble;
create table zz_doble.prod (k text primary key, v text);
\copy zz_doble.prod from '@CSV@' with (format csv, header true)

-- 0. El CSV trae lo que hace falta
do $$ begin
  if not exists (select 1 from zz_doble.prod where k = '1 tipos_reporte investigacion_ubicacion') then
    raise exception 'El CSV no trae la Investigación de ubicación';
  end if;
end $$;

create table zz_doble.tipos as
  select (v::jsonb ->> 'id')::bigint as id, v::jsonb ->> 'codigo' as codigo, v::jsonb as j
    from zz_doble.prod where k like '1 tipos\_reporte %';

-- 1. Mapa id local → id de producción, por código
create table zz_doble.mapa as
  select l.id as local_id, p.id as prod_id from campo.tipos_reporte l join zz_doble.tipos p on p.codigo = l.codigo where l.id <> p.id;
-- Los formularios que solo existen en el doble y chocan con un id de producción se mueven lejos
insert into zz_doble.mapa
  select l.id, 900000 + l.id from campo.tipos_reporte l
   where not exists (select 1 from zz_doble.tipos p where p.codigo = l.codigo) and exists (select 1 from zz_doble.tipos p where p.id = l.id);

-- 2. Renumerar los hijos (dos pasos, para que no choquen)
do $$ declare r record; begin
  for r in select c.conrelid::regclass as t, a.attname as col
             from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
            where c.contype = 'f' and c.confrelid = 'campo.tipos_reporte'::regclass loop
    execute format('update %s x set %I = -m.prod_id from zz_doble.mapa m where x.%I = m.local_id', r.t, r.col, r.col);
    execute format('update %s set %I = -%I where %I < 0', r.t, r.col, r.col, r.col);
  end loop;
end $$;

-- 3. Formularios y grupos: los de producción, tal cual (los que solo existen en el doble se conservan)
create table zz_doble.solo_doble as
  select l.* from campo.tipos_reporte l where not exists (select 1 from zz_doble.tipos p where p.codigo = l.codigo);
update zz_doble.solo_doble s set id = m.prod_id from zz_doble.mapa m where s.id = m.local_id;
delete from campo.tipos_reporte where true;
insert into campo.tipos_reporte overriding system value
  select (jsonb_populate_record(null::campo.tipos_reporte, j)).* from zz_doble.tipos;
insert into campo.tipos_reporte overriding system value select * from zz_doble.solo_doble;

create table zz_doble.solo_doble_grupos as
  select g.* from campo.grupos_reporte g
   where not exists (select 1 from zz_doble.prod p where p.k like '1 grupos\_reporte %' and p.v::jsonb ->> 'codigo' = g.codigo);
update zz_doble.solo_doble_grupos set id = 900000 + id
 where id in (select (v::jsonb ->> 'id')::bigint from zz_doble.prod where k like '1 grupos\_reporte %');
delete from campo.grupos_reporte where true;
insert into campo.grupos_reporte overriding system value
  select (jsonb_populate_record(null::campo.grupos_reporte, v::jsonb)).* from zz_doble.prod where k like '1 grupos\_reporte %';
insert into campo.grupos_reporte overriding system value select * from zz_doble.solo_doble_grupos;

-- 4. Campos, fotos y causales de la Investigación: los de producción
delete from campo.tipo_campos where tipo_id = (select id from zz_doble.tipos where codigo = 'investigacion_ubicacion');
-- Los campos y fotos de OTROS formularios que ocupan un id de la Investigación en producción se apartan
-- (la identidad pasa un momento a «by default» para poder mover el id, y vuelve a «always»)
alter table campo.tipo_campos alter column id set generated by default;
alter table campo.tipo_fotos alter column id set generated by default;
update campo.tipo_campos set id = 900000 + id where id in (select (v::jsonb ->> 'id')::bigint from zz_doble.prod where k like '2 tipo\_campos INV %');
update campo.tipo_fotos set id = 900000 + id
 where tipo_id <> (select id from zz_doble.tipos where codigo = 'investigacion_ubicacion')
   and id in (select (v::jsonb ->> 'id')::bigint from zz_doble.prod where k like '2 tipo\_fotos INV %');
alter table campo.tipo_campos alter column id set generated always;
alter table campo.tipo_fotos alter column id set generated always;
insert into campo.tipo_campos overriding system value
  select (jsonb_populate_record(null::campo.tipo_campos, v::jsonb)).* from zz_doble.prod where k like '2 tipo\_campos INV %';
delete from campo.tipo_fotos where tipo_id = (select id from zz_doble.tipos where codigo = 'investigacion_ubicacion');
insert into campo.tipo_fotos overriding system value
  select (jsonb_populate_record(null::campo.tipo_fotos, v::jsonb)).* from zz_doble.prod where k like '2 tipo\_fotos INV %';
delete from campo.causales_tipos where tipo_id = (select id from zz_doble.tipos where codigo = 'investigacion_ubicacion');
insert into campo.causales_tipos
  select (jsonb_populate_record(null::campo.causales_tipos, v::jsonb)).* from zz_doble.prod where k like '2 causales\_tipos INV %';

-- 5. Actividades, catálogo de derivadas y formularios con documento: los de producción (el autor viene omitido)
delete from campo.actividades where true;
insert into campo.actividades
  select (jsonb_populate_record(null::campo.actividades, v::jsonb || '{"autor":"migracion@geoportal"}')).* from zz_doble.prod where k like '3 actividades %';
delete from campo.derivadas_catalogo where true;
insert into campo.derivadas_catalogo
  select (jsonb_populate_record(null::campo.derivadas_catalogo, v::jsonb || '{"autor":"migracion@geoportal"}')).* from zz_doble.prod where k like '3 derivadas\_catalogo %';
delete from campo.formularios_documento where true;
insert into campo.formularios_documento
  select (jsonb_populate_record(null::campo.formularios_documento, v::jsonb || '{"autor":"migracion@geoportal"}')).* from zz_doble.prod where k like '3 formularios\_documento %';

-- 6. Secuencias
do $$ declare s_ text; n_ text; v_ text; begin
  for s_ in select unnest(string_to_array((select p.v from zz_doble.prod p where p.k = '4 secuencias (último valor)'), ', ')) loop
    n_ := split_part(s_, '=', 1); v_ := split_part(s_, '=', 2);
    if v_ <> 'sin usar' then perform setval(n_, v_::bigint, true); end if;
  end loop;
end $$;

-- 6b. Permisos de las tablas como en producción (fila «5 clase, RLS y permisos»; el dueño no se toca)
do $$ declare r record; it text; rol text; pr text; ps text[]; begin
  for r in select substr(k, length('5 clase, RLS y permisos ') + 1) as t, v from zz_doble.prod where k like '5 clase, RLS y permisos %'
           union all
           select 'campo.reporte_datos_sensibles', v from zz_doble.prod where k = '8 campo.reporte_datos_sensibles (el patrón que se copia)' loop
    if to_regclass(r.t) is null then continue; end if;
    execute format('revoke all on %s from public, anon, authenticated, service_role, homelab_lectura, dell_envios', r.t);
    if r.v like '%acl (por omisión)' then continue; end if;
    foreach it in array (substring(r.v from 'acl (.*)$'))::text[] loop
      rol := split_part(it, '=', 1); pr := split_part(split_part(it, '=', 2), '/', 1);
      if rol = 'postgres' or rol = '' then continue; end if;
      ps := array[]::text[];
      if pr like '%r%' then ps := ps || 'select'::text; end if;
      if pr like '%a%' then ps := ps || 'insert'::text; end if;
      if pr like '%w%' then ps := ps || 'update'::text; end if;
      if pr like '%d%' then ps := ps || 'delete'::text; end if;
      if pr like '%D%' then ps := ps || 'truncate'::text; end if;
      if pr like '%x%' then ps := ps || 'references'::text; end if;
      if pr like '%t%' then ps := ps || 'trigger'::text; end if;
      execute format('grant %s on %s to %I', array_to_string(ps, ', '), r.t, rol);
    end loop;
    if (substring(r.v from 'rls (true|false)'))::boolean then execute format('alter table %s enable row level security', r.t);
    else execute format('alter table %s disable row level security', r.t); end if;
  end loop;
end $$;

-- 7. Ningún hijo huérfano (con replica no se comprobaron las llaves)
do $$ declare r record; huerfanos bigint; total bigint := 0; begin
  for r in select c.conrelid::regclass as t, c.confrelid::regclass as p, a.attname as col, b.attname as pcol
             from pg_constraint c
             join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
             join pg_attribute b on b.attrelid = c.confrelid and b.attnum = c.confkey[1]
            where c.contype = 'f' and c.connamespace = 'campo'::regnamespace and array_length(c.conkey, 1) = 1 loop
    execute format('select count(*) from %s x where x.%I is not null and not exists (select 1 from %s y where y.%I = x.%I)', r.t, r.col, r.p, r.pcol, r.col) into huerfanos;
    if huerfanos > 0 then raise warning 'huérfanos en %.%: %', r.t, r.col, huerfanos; total := total + huerfanos; end if;
  end loop;
  if total > 0 then raise exception 'El doble quedó con % filas huérfanas', total; end if;
end $$;

-- Porqué y alcance del DROP: el esquema auxiliar zz_doble lo creó este mismo bloque; se quita para que el doble quede igual a producción.
drop schema zz_doble cascade;
commit;
"""


def igualar_checks(db, prod):
    """Un CHECK que dice lo mismo pero quedó escrito con otra forma (p. ej. ((a AND b) AND c) frente a (a AND b AND c))
    se rehace en el doble con el texto exacto de producción, porque la guardia compara el texto.
    Porqué y alcance del DROP CONSTRAINT: igualar el texto; alcance, esa restricción, en el doble y en esta corrida."""
    sql = []
    for k, v in prod.items():
        if not k.startswith('5 restricciones ') or v == 'NINGUNA':
            continue
        t = k[len('5 restricciones '):]
        r = psql(db, '-At', '-F', '\t', '-c', f"select conname, contype, pg_get_constraintdef(oid) from pg_constraint where conrelid = to_regclass('{t}')")
        local = {l.split('\t')[0]: (l.split('\t')[1], l.split('\t')[2]) for l in r.stdout.splitlines() if l}
        for item in v.split(' | '):
            nombre, _, defin = item.partition(' ')
            if nombre in local and local[nombre][0] == 'c' and local[nombre][1] != defin and defin.startswith('CHECK '):
                # PostgreSQL aplana «(a AND b) AND c» al leerlo; la forma anidada de producción viene de un BETWEEN.
                # Se reescribe «((x >= A) AND (x <= B))» como «(x BETWEEN A AND B)» para que el árbol quede igual.
                defin = re.sub(r'\(\((.+?) >= (\d+)\) AND \(\1 <= (\d+)\)\)', r'(\1 BETWEEN \2 AND \3)', defin)
                sql.append(f'alter table {t} drop constraint {nombre}, add constraint {nombre} {defin};')
    if sql:
        psql(db, '-q', entrada='begin;\n' + '\n'.join(sql) + '\ncommit;\n')
        print(f'CHECK rehechos con el texto de producción: {len(sql)}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--csv', required=True)
    ap.add_argument('--base', default=BASE_DOBLE)
    ap.add_argument('--db', default='emdupar_b_inv_doble')
    a = ap.parse_args()  # argparse rechaza las opciones que no conoce
    if not a.db.startswith('emdupar_b_inv'):
        sys.exit('La base debe empezar por emdupar_b_inv (bases del Code B para este paquete).')
    prod = leer_csv(a.csv)

    r = psql('postgres', '-Atc', f"select coalesce(shobj_description(oid, 'pg_database'), '') from pg_database where datname = '{a.db}'")
    if r.stdout.strip() or r.stdout == '\n':
        if r.stdout.strip() != MARCA:
            sys.exit(f'La base {a.db} ya existe y no la creó este guion: no la toco.')
        psql('postgres', '-qc', f'drop database {a.db}')
    psql('postgres', '-qc', f'create database {a.db}')
    psql('postgres', '-qc', f"comment on database {a.db} is '{MARCA}'")
    r = psql(a.db, '-q', '-f', a.base, ok=False)
    errores = [l for l in r.stderr.splitlines() if 'ERROR' in l]
    if errores:
        sys.exit('El doble base no cargó limpio:\n' + '\n'.join(errores[:10]))

    # Roles que producción usa en los permisos y que el doble base no trae (los roles son del clúster 55442 del Code B)
    psql(a.db, '-qc', "do $$ begin if not exists (select 1 from pg_roles where rolname = 'homelab_lectura') then create role homelab_lectura nologin; end if; end $$")
    ruta = os.path.abspath(a.csv)
    if "'" in ruta:
        sys.exit('La ruta del CSV no puede llevar comillas.')
    psql(a.db, '-q', entrada=APLICAR.replace('@CSV@', ruta))
    igualar_checks(a.db, prod)

    with tempfile.NamedTemporaryFile('w+', suffix='.csv', delete=False) as t:
        salida = t.name
    r = psql(a.db, '--csv', '-c', 'begin read only', '-f', CONSULTA)
    with open(salida, 'w', encoding='utf-8') as f:
        f.write(r.stdout.split('\n', 1)[1] if r.stdout.startswith('BEGIN') else r.stdout)
    doble = leer_csv(salida)

    claves = sorted(set(prod) | set(doble))
    iguales, distintas, informadas = 0, [], []
    for k in claves:
        p, d = prod.get(k, '(falta)'), doble.get(k, '(falta)')
        if k.startswith('4 ') and k != '4 registros de la Investigación':
            informadas.append(f'  {k}: producción {p} · doble {d}')
            continue
        if igual(p, d):
            iguales += 1
        else:
            distintas.append(f'  {k}\n    producción: {p[:400]}\n    doble:      {d[:400]}')
    n = iguales + len(distintas)
    print(f'Doble {a.db}: {iguales} de {n} filas iguales a producción' + (' · SIN DIFERENCIAS' if not distintas else f' · {len(distintas)} DISTINTAS'))
    for x in distintas:
        print(x)
    if informadas:
        print('Solo informadas (conteos):')
        print('\n'.join(informadas))
    sys.exit(1 if distintas else 0)


if __name__ == '__main__':
    main()
