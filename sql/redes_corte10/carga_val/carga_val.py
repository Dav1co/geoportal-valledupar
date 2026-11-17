#!/usr/bin/env python3
"""Paquete de carga del inventario regulatorio — Técnica fase 1, Corte 10. Necesita openpyxl (solo para leer el libro de Excel).
Lee regulatorio/Valoracion_Tecnica_Valledupar_04122019.xlsx y regulatorio/salida_geoportal/tablas/ y escribe en generado/ un paquete reproducible por psql:
  · carga_valoracion.sql              un solo comando, UNA transacción: guardia, la valoración (3 hojas con sus totales), el amarre de cada activo con su
                                      fila y las comprobaciones «N de N». Si una comprobación falla, no queda nada.
  · ensayo_carga_valoracion.sql       lo mismo, pero termina en ERROR a propósito («N de N … SIN FALLAS») y deshace todo.
  · verificacion_carga_valoracion.sql solo lectura, una consulta (apta para el editor).
  · partes/                           los trozos que incluyen los anteriores.
La valoración es de REFERENCIA (propuesta de 2019): la ficha oficial de los activos no se toca; ninguna versión de activo se crea. Sin datos de personas.
El amarre se puede volver a generar y cargar: queda una carga nueva (conjunto «val_amarre») y vale la última.
Uso: python3 -I carga_val.py   (no necesita base de datos)."""
import csv
import datetime
import hashlib
import os

import openpyxl

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.join(AQUI, 'generado')
PARTES = os.path.join(SALIDA, 'partes')
REG = os.environ.get('REGULATORIO', os.path.expanduser('~/geoportal-consultas/tecnica/paquete_fase1/regulatorio'))
LIBRO = 'Valoracion_Tecnica_Valledupar_04122019.xlsx'
CSV_ACU = 'salida_geoportal/tablas/corte10_tramos_acueducto_fila_valoracion.csv'
CSV_ALC = 'salida_geoportal/tablas/enriquecimiento_alc_conductos.csv'
CSV_PUN = 'salida_geoportal/tablas/corte10_activos_puntuales.csv'
ORIGEN = 'Valoración Técnica 2019 (Res. CRA 688 de 2014), propuesta'
HOJAS = [('acueducto', 'ACUEDUCTO', 'acueducto', 0), ('alcantarillado', 'ALCANTARILLADO', 'alcantarillado', 1), ('alcantarillado_2', 'ALCANTARILLADO (2)', 'alcantarillado', 1)]
LOTE = 500
TOL = 0.02      # la misma tolerancia del parámetro valoracion_tolerancia_pct (2 %)


def md5(rel):
    h = hashlib.md5()
    with open(os.path.join(REG, rel), 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def lit(x):
    if x is None or x == '':
        return 'null'
    if isinstance(x, bool):
        return 'true' if x else 'false'
    if isinstance(x, (int, float)):
        return repr(round(x, 6)) if isinstance(x, float) else str(x)
    if isinstance(x, (datetime.datetime, datetime.date)):
        return "'" + x.strftime('%Y-%m-%d') + "'"
    return "'" + str(x).replace("'", "''") + "'"


def limpio(x):
    return ' '.join(str(x).split()) if x is not None and str(x).strip() != '' else None


def numero(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def leer_csv(rel):
    with open(os.path.join(REG, rel), encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


# ---------- 1. El libro ----------
wb = openpyxl.load_workbook(os.path.join(REG, LIBRO), data_only=True)
resumen = {limpio(r[0]): (r[1], r[2]) for r in wb['RESUMEN'].iter_rows(values_only=True) if r[0] and isinstance(r[1], (int, float))}
notas = {}      # (hoja, n) → nota del análisis del Plan Maestro (corte10_activos_puntuales.csv)
obs_previa = ''
for r in leer_csv(CSV_PUN):
    if r['observacion'].strip().rstrip('.') == 'Ídem':      # el análisis abrevia: se escribe completa la observación de la fila anterior
        r['observacion'] = obs_previa
    obs_previa = r['observacion']
    clave = r['fila_valoracion_n'].strip()
    hoja = 'alcantarillado_2' if clave.startswith('ALC') else 'acueducto'
    rango = clave.replace('ALC', '').strip().split('-')
    texto = (r['activo_de_la_red_con_que_se_amarra'].strip() + '. ' + r['observacion'].strip())[:590]
    for n in range(int(rango[0]), int(rango[-1]) + 1):
        notas[(hoja, n)] = texto

FILAS = []      # dicts
TOTALES = {}
for hoja, nombre_hoja, servicio, d in HOJAS:
    ws = wb[nombre_hoja]
    filas = []
    for r in ws.iter_rows(min_row=2, values_only=True):
        nombre = limpio(r[1])
        if nombre is None:
            continue      # filas numeradas y vacías al final de la hoja
        car = limpio(r[7 + d])
        cant = numero(r[8 + d])
        mayus = nombre.upper()
        material = diam = None
        if mayus.startswith('TUBERIA'):
            clase, unidad, material, diam = 'tuberia', 'm', mayus.replace('TUBERIA', '').strip(), numero(car)
        elif mayus.startswith('VALVULA'):
            clase, unidad, diam = 'valvula', 'un', numero(car)
        elif mayus.startswith('HIDRANTE'):
            clase, unidad = 'hidrante', 'un'
        elif mayus.startswith('TERRENO'):
            clase, unidad = 'terreno', None
        elif mayus.startswith(('PLANTA', 'PTAR', 'BOCATOMA', 'DESARENADOR', 'PREDECANTADOR')):
            clase, unidad = 'puntual', ('L/s' if cant is not None else None)
        elif mayus.startswith('TANQUE'):
            clase, unidad = 'puntual', 'm³'
        elif mayus.startswith(('ADUCCI', 'COLECTOR')):
            clase, unidad = 'otro', 'm'
        else:
            clase, unidad = 'otro', ('un' if cant is not None else None)
        n = int(r[0])
        nota = notas.get((hoja, n)) or (notas.get(('alcantarillado_2', n + 29)) if hoja == 'alcantarillado' and clase != 'tuberia' and clase != 'terreno' else None)
        filas.append(dict(hoja=hoja, n=n, nombre=nombre, subsistema=limpio(r[3 + d]), actividad=limpio(r[4 + d]), tipo_activo=limpio(r[5 + d]), vida_util=numero(r[6 + d]),
                          caracteristica=car, cantidad=cant, unidad=unidad, precio_unitario=numero(r[9 + d]), valor_total=numero(r[10 + d]),
                          anio_operacion=int(r[11 + d]) if r[11 + d] else None, fecha_operacion=r[12 + d], fecha_tarifa=r[13 + d], tiempo_operacion=numero(r[14 + d]),
                          vida_remanente=numero(r[15 + d]), valor_remanente=numero(r[16 + d]), depreciacion_anual=numero(r[17 + d]), clase=clase, material=material, diametro_pulg=diam,
                          nota=nota))
    bcr0, dep = resumen[nombre_hoja]
    suma_rem = sum(f['valor_remanente'] or 0 for f in filas)
    assert abs(suma_rem - bcr0) < 1, (hoja, suma_rem, bcr0)      # el BCR0 del RESUMEN es la suma del valor remanente de la hoja
    TOTALES[hoja] = dict(nombre_hoja=nombre_hoja, servicio=servicio, filas=len(filas), bcr0=bcr0, valor_total=sum(f['valor_total'] or 0 for f in filas), depreciacion_anual=dep)
    FILAS += filas
assert [TOTALES[h]['filas'] for h in ('acueducto', 'alcantarillado', 'alcantarillado_2')] == [59, 39, 68], TOTALES
por_hoja = lambda h: [f for f in FILAS if f['hoja'] == h]  # noqa: E731
fila_n = lambda h, nombre: next(f['n'] for f in por_hoja(h) if f['nombre'].upper().startswith(nombre))  # noqa: E731
N_HUARICHA, N_GOTA, N_PEDREGOSA, N_POPA, N_HIDRANTES = (fila_n('acueducto', x) for x in ('PLANTA HUARICHA', 'PLANTA GOTA', 'TANQUE LA PEDREGOSA', 'TANQUE LA POPA', 'HIDRANTES'))

# ---------- 2. Los amarres por archivo ----------
SIT = {'con fila': 'con_fila', 'con fila; marcar aparte (fuera de servicio)': 'aparte_fuera_servicio', 'con fila; marcar aparte (SIVA)': 'aparte_siva',
       'proyectado: no entra': 'proyectado', 'sin fila en la valoración': 'sin_fila'}
AM = []      # (codigo, hoja, n, cantidad, situacion, nota)
for r in leer_csv(CSV_ACU):
    sit = SIT[r['valoracion_amarre']]
    proyectado = r['clase_red'].startswith('proyectado')
    if proyectado:
        sit = 'proyectado'
    nota = None if r['clase_red'] == 'existente activo' else 'En el modelo del Plan Maestro: ' + r['clase_red']
    largo = float(r['LENGTH'] or 0)
    if '+' in r['fila_valoracion_n'] and sit not in ('proyectado', 'sin_fila'):
        # la valoración repite una fila (AC de 24 pulgadas, filas 40 y 41): el tramo se amarra a las dos y su longitud se reparte en proporción a la de cada fila
        ns = [int(x) for x in r['fila_valoracion_n'].split('+')]
        cant = {n: next(f['cantidad'] for f in por_hoja('acueducto') if f['n'] == n) for n in ns}
        for n in ns:
            AM.append((r['codigo_geoportal'], 'acueducto', n, round(largo * cant[n] / sum(cant.values()), 3), sit,
                       'La valoración repite esta fila (' + ' y '.join(str(x) for x in ns) + '): la longitud del tramo se reparte entre las dos'))
        continue
    n = int(float(r['fila_valoracion_n'])) if r['fila_valoracion_n'] and sit not in ('proyectado', 'sin_fila') else None
    AM.append((r['codigo_geoportal'], 'acueducto', n, largo, sit, nota))
n_acu = len({a[0] for a in AM})
tub2 = {f['n']: f for f in por_hoja('alcantarillado_2') if f['clase'] == 'tuberia'}
tub1 = {(f['material'], f['diametro_pulg']): f['n'] for f in por_hoja('alcantarillado') if f['clase'] == 'tuberia'}
ALT1 = {'Reemplazar': 'Alternativa 1 del Plan Maestro: por reemplazar', 'Eliminar': 'Alternativa 1 del Plan Maestro: por eliminar'}
n_alc = 0
for r in leer_csv(CSV_ALC):
    n2 = int(float(r['cat_fila_valoracion_n'])) if r['cat_fila_valoracion_n'] else None
    largo = float(r['alt1_LONGITUD_m'] or 0)
    n_alc += 1
    if r['alt1_ESTADO'] == 'Proyectado':
        for h in ('alcantarillado', 'alcantarillado_2'):
            AM.append((r['codigo_geoportal'], h, None, largo, 'proyectado', None))
        continue
    nota = ALT1.get(r['alt1_ESTADO'])
    AM.append((r['codigo_geoportal'], 'alcantarillado_2', n2, largo, 'con_fila' if n2 else 'sin_fila', nota))
    n1 = tub1.get((tub2[n2]['material'], tub2[n2]['diametro_pulg'])) if n2 else None
    AM.append((r['codigo_geoportal'], 'alcantarillado', n1, largo, 'con_fila' if n1 else 'sin_fila', nota))
assert (n_acu, n_alc) == (10578, 9064), (n_acu, n_alc)


def calzan(hoja):
    """Cuántas filas de tubería de la hoja calzan con lo que suma el amarre de archivo (lo mismo que comprueba la carga en la base)."""
    red = {}
    for _, h, n, cant, _, _ in AM:
        if h == hoja and n is not None:
            red[n] = red.get(n, 0) + cant
    tub = [f for f in por_hoja(hoja) if f['clase'] == 'tuberia']
    return sum(1 for f in tub if abs(red.get(f['n'], 0) - (f['cantidad'] or 0)) <= (f['cantidad'] or 0) * TOL), len(tub)


CALZA = {h: calzan(h) for h in ('acueducto', 'alcantarillado', 'alcantarillado_2')}

# ---------- 3. El SQL ----------
M = {a: md5(a) for a in (LIBRO, CSV_ACU, CSV_ALC, CSV_PUN)}
MD5_AM = hashlib.md5((M[CSV_ACU] + M[CSV_ALC]).encode()).hexdigest()
COLS = ['hoja', 'n', 'nombre', 'subsistema', 'actividad', 'tipo_activo', 'vida_util', 'caracteristica', 'cantidad', 'unidad', 'precio_unitario', 'valor_total', 'anio_operacion',
        'fecha_operacion', 'fecha_tarifa', 'tiempo_operacion', 'vida_remanente', 'valor_remanente', 'depreciacion_anual', 'clase', 'material', 'diametro_pulg', 'nota']
nota_val = '; '.join(f"{t['nombre_hoja']}: {t['filas']} filas, BCR0 {t['bcr0']:,.0f}".replace(',', '.') for t in TOTALES.values())
p10 = [f"""-- Corte 10 · carga del inventario regulatorio · 1. la valoración ({len(FILAS)} filas de 3 hojas). Generado por carga_val.py.
insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, nota, autor)
values ('valoracion', {lit(LIBRO)}, '{M[LIBRO]}', {len(FILAS)}, {lit(ORIGEN)}, {lit(nota_val)}, lower(:'solicitante')) returning id as val \\gset
insert into redes.val_hojas (carga_id, hoja, nombre_hoja, servicio, filas, bcr0, valor_total, depreciacion_anual) values
""" + ',\n'.join(f"(:val, '{h}', {lit(t['nombre_hoja'])}, '{t['servicio']}', {t['filas']}, {t['bcr0']!r}, {t['valor_total']!r}, {t['depreciacion_anual']!r})" for h, t in TOTALES.items()) + ';']
for i in range(0, len(FILAS), LOTE):
    p10.append(f"insert into redes.val_filas (carga_id, {', '.join(COLS)}) values\n" + ',\n'.join('(:val, ' + ', '.join(lit(f[c]) for c in COLS) + ')' for f in FILAS[i:i + LOTE]) + ';')

p20 = [f"""-- Corte 10 · carga del inventario regulatorio · 2. el amarre de cada activo con su fila. Generado por carga_val.py.
-- Tramos de acueducto ({n_acu}) y conductos de alcantarillado ({n_alc}, en las dos hojas) vienen del análisis del Plan Maestro, por el código del activo.
-- Hidrantes, válvulas, tanques y planta se amarran aquí, con lo que hay en la base. No se crea ninguna versión de activo: la ficha oficial no cambia.
insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, nota, autor)
values ('val_amarre', {lit(CSV_ACU.replace('salida_geoportal/', '') + ' + ' + CSV_ALC.replace('salida_geoportal/', ''))}, '{MD5_AM}', {n_acu + n_alc}, {lit(ORIGEN)},
        'Amarre por material y diámetro (análisis del Plan Maestro 2014). Las filas son los tramos y conductos de los dos archivos; los puntuales (hidrantes, válvulas, tanques y planta) se amarran en la base al cargar',
        lower(:'solicitante')) returning id as am \\gset
create temp table _am (codigo text not null, hoja text not null, n integer, cantidad numeric not null, situacion text not null, nota text) on commit drop;"""]
for i in range(0, len(AM), LOTE):
    p20.append('insert into _am values\n' + ',\n'.join('(' + ', '.join(lit(x) for x in a) + ')' for a in AM[i:i + LOTE]) + ';')
p20.append(f"""analyze _am;
-- los códigos del análisis que ya no son activos (debe dar cero: lo exige la comprobación 04)
select count(*) as am_sin_activo from _am t where not exists (select 1 from redes.activos a where a.codigo = t.codigo) \\gset
select set_config('redes.val_am_sin_activo', :'am_sin_activo', true) as codigos_sin_activo;
insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion, nota)
select :am, :val, a.id, t.hoja, t.n, t.cantidad, t.situacion, t.nota from _am t join redes.activos a on a.codigo = t.codigo;
-- hidrantes: uno a uno con la fila «HIDRANTES» (la valoración dice 259)
insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion, nota)
select :am, :val, m.activo_id, 'acueducto', {N_HIDRANTES}, 1, 'con_fila', null from redes.activo_vigente_mat m where m.prefijo in ('TOR', 'HID') and not m.retirado;
-- válvulas de cierre del modelo: por diámetro, con la fila «válvula de cheque» de ese diámetro (duda para David: de 3" a 8" la cantidad de la valoración parece metros)
insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion, nota)
select :am, :val, m.activo_id, 'acueducto', f.n, 1, case when f.n is null then 'sin_fila' else 'con_fila' end,
       case when f.n is null then 'Válvula de ' || round(w.diametro_mm / 25.4) || ' pulgadas: la valoración no tiene fila de ese diámetro' end
  from redes.activo_vigente_mat m
  join redes.pm_valvulas w on w.llave = m.llave_capa and w.carga_id = redes.f_ref_vigente('pm_valvulas')
  left join redes.val_filas f on f.carga_id = :val and f.hoja = 'acueducto' and f.clase = 'valvula' and f.diametro_pulg = round(w.diametro_mm / 25.4)
 where m.prefijo = 'VAL' and m.capa_codigo = 'acueducto_nodos' and not m.retirado;
-- la planta (un solo activo para las dos filas: Huaricha y Gota Fría) y los tanques La Pedregosa y La Popa
insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion, nota)
select :am, :val, m.activo_id, 'acueducto', x.n, 1, 'con_fila', x.nota
  from redes.activo_vigente_mat m
  join (values ('PTA', '17212', null, {N_HUARICHA}, 'Un solo activo (nodo «PTAP» del modelo) para las dos plantas'),
               ('PTA', '17212', null, {N_GOTA}, 'Un solo activo (nodo «PTAP» del modelo) para las dos plantas'),
               ('TAN', '6696', null, {N_PEDREGOSA}, null),
               ('TAN', null, 'la popa', {N_POPA}, null)) x(prefijo, llave, nombre, n, nota)
    on m.prefijo = x.prefijo and ((x.llave is not null and m.capa_codigo = 'acueducto_nodos' and m.llave_capa = x.llave) or (x.nombre is not null and lower(m.nombre) like '%' || x.nombre || '%'))
 where not m.retirado;
-- lo demás que vino de las capas cargadas y es de un tipo que la valoración cubre: «sin fila» (un activo creado después no entra aquí: queda «fuera de la valoración 2019»)
insert into redes.val_amarre (carga_id, val_carga_id, activo_id, hoja, n, cantidad, situacion, nota)
select :am, :val, m.activo_id, h.hoja, null, coalesce(m.longitud_m, 1), 'sin_fila', 'No corresponde a ninguna fila de la valoración'
  from redes.activo_vigente_mat m
  join redes.activos a on a.id = m.activo_id and a.origen_alta = 'carga'
  join (values ('acueducto', 'acueducto'), ('alcantarillado', 'alcantarillado'), ('alcantarillado', 'alcantarillado_2')) h(sistema, hoja) on h.sistema = m.sistema
 where not m.retirado and m.prefijo = any (redes.f_val_prefijos())
   and not exists (select 1 from redes.val_amarre x where x.carga_id = :am and x.activo_id = m.activo_id and x.hoja = h.hoja);
analyze redes.val_amarre;
-- las teselas del geovisor cambian (la edad de los activos sin fecha de instalación): se sube su versión
select redes.f_subir_tesela('acueducto'), redes.f_subir_tesela('alcantarillado');""")

ca, ta = CALZA['acueducto']
c2, t2 = CALZA['alcantarillado_2']
c1, t1 = CALZA['alcantarillado']
red_fila = """(select count(*) from redes.val_filas f
            left join (select am.n, sum(am.cantidad) as red from redes.val_amarre am join redes.activo_vigente_mat m on m.activo_id = am.activo_id and not m.retirado and not m.oculto
                        where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja = '%s' and am.n is not null group by am.n) r on r.n = f.n
           where f.carga_id = redes.f_ref_vigente('valoracion') and f.hoja = '%s' and f.clase = 'tuberia'
             and abs(coalesce(r.red, 0) - coalesce(f.cantidad, 0)) <= coalesce(f.cantidad, 0) * redes.f_param('valoracion_tolerancia_pct') / 100)"""
p30 = f"""-- Corte 10 · carga del inventario regulatorio · 3. comprobaciones «N de N». Generado por carga_val.py. Si alguna falla, ERROR: la transacción no queda.
select set_config('redes.val_solicitante', lower(:'solicitante'), true) as quien \\gset
do $$
declare v_q text := current_setting('redes.val_solicitante'); v_t0 timestamptz; v_ms1 numeric; v_ms2 numeric; v_ms3 numeric; v_j jsonb; v_f jsonb; v_id bigint; v_cod text;
        v_z integer := floor(redes.f_param('geovisor_zoom_red_completa'))::integer; v_x integer; v_y integer; v_mvt text;
begin
  create temp table _val_r (n integer, nombre text, ok boolean, detalle text) on commit drop;
  -- la conciliación, como la pide la pantalla (con los topes de la Edge)
  v_t0 := clock_timestamp(); v_j := public.geoportal_redes_valoracion(v_q); v_ms1 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  -- la ficha de un tramo amarrado
  select am.activo_id, a.codigo into v_id, v_cod from redes.val_amarre am join redes.activos a on a.id = am.activo_id join redes.activo_vigente_mat m on m.activo_id = am.activo_id and not m.retirado
   where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja = 'acueducto' and am.situacion = 'con_fila' and a.prefijo = 'RED' order by am.activo_id limit 1;
  v_t0 := clock_timestamp(); v_f := redes.f_ficha(v_id, 'admin'); v_ms2 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  -- la tesela con más red, al zoom desde el que se ve toda
  select t.x, t.y into v_x, v_y from (
    select floor((ST_X(ST_PointOnSurface(m.geom)) + 180) / 360 * (1 << v_z))::integer as x,
           floor((1 - ln(tan(radians(ST_Y(ST_PointOnSurface(m.geom)))) + 1 / cos(radians(ST_Y(ST_PointOnSurface(m.geom))))) / pi()) / 2 * (1 << v_z))::integer as y
      from redes.activo_vigente_mat m where m.prefijo in ('RED', 'COL') and not m.retirado) t group by t.x, t.y order by count(*) desc limit 1;
  v_t0 := clock_timestamp(); v_mvt := public.geoportal_redes_geovisor_mvt(v_q, v_z, v_x, v_y); v_ms3 := round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  insert into _val_r values
  (1, '01 la valoración vigente es la de este paquete: 3 hojas con 59, 39 y 68 filas',
      (select md5 from redes.v_ref_carga_vigente where conjunto = 'valoracion') = '{M[LIBRO]}'
      and (select string_agg(h.hoja || '=' || (select count(*) from redes.val_filas f where f.carga_id = h.carga_id and f.hoja = h.hoja), ',' order by h.hoja)
             from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion')) = 'acueducto=59,alcantarillado=39,alcantarillado_2=68',
      (select string_agg(h.hoja || '=' || h.filas, ', ' order by h.hoja) from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion'))),
  (2, '02 el BCR0 de cada hoja (hoja RESUMEN) es la suma del valor remanente de sus filas: acueducto 101.061 millones, alcantarillado 138.548 y alcantarillado (2) 176.452',
      not exists (select 1 from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion')
                   and abs(h.bcr0 - (select sum(coalesce(f.valor_remanente, 0)) from redes.val_filas f where f.carga_id = h.carga_id and f.hoja = h.hoja)) >= 1)
      and (select string_agg(round(h.bcr0 / 1e6)::text, ',' order by h.hoja) from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion')) = '101061,138548,176452',
      (select string_agg(h.nombre_hoja || ' ' || round(h.bcr0 / 1e6) || ' millones', ' · ' order by h.hoja) from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion'))),
  (3, '03 la hoja de alcantarillado que vale es «ALCANTARILLADO (2)» (parámetro valoracion_hoja_alcantarillado = 2; la otra queda de referencia)',
      redes.f_val_hoja_alc() = 'alcantarillado_2' and v_j ->> 'hoja_alcantarillado' = 'alcantarillado_2', redes.f_val_hoja_alc()),
  (4, '04 los {n_acu} tramos y los {n_alc} conductos del análisis son activos de la base (por su código) y quedaron amarrados',
      current_setting('redes.val_am_sin_activo')::integer = 0
      and (select count(*) from redes.val_amarre am where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja = 'acueducto'
            and exists (select 1 from redes.activos a where a.id = am.activo_id and a.prefijo in ('RED', 'CON'))) >= {n_acu}
      and (select count(distinct am.activo_id) from redes.val_amarre am where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja = 'alcantarillado_2') >= {n_alc},
      current_setting('redes.val_am_sin_activo') || ' código(s) del análisis sin activo'),
  (5, '05 acueducto: las filas de tubería que calzan con la red (±2 %) son las del análisis ({ca} de {ta}, una más o una menos)',
      abs({red_fila % ('acueducto', 'acueducto')} - {ca}) <= 1,
      {red_fila % ('acueducto', 'acueducto')} || ' de {ta} calzan'),
  (6, '06 alcantarillado (2): las filas de tubería que calzan con la red (±2 %) son las del análisis con el catastro ({c2} de {t2}, una más o una menos)',
      abs({red_fila % ('alcantarillado_2', 'alcantarillado_2')} - {c2}) <= 1,
      {red_fila % ('alcantarillado_2', 'alcantarillado_2')} || ' de {t2} calzan (hoja de referencia «ALCANTARILLADO»: {c1} de {t1} en el análisis)'),
  (7, '07 hidrantes: todos los vigentes amarrados a la fila «HIDRANTES» (la valoración dice 259)',
      (select count(*) from redes.activo_vigente_mat m where m.prefijo in ('TOR', 'HID') and not m.retirado) > 0
      and not exists (select 1 from redes.activo_vigente_mat m where m.prefijo in ('TOR', 'HID') and not m.retirado
                       and not exists (select 1 from redes.val_amarre am where am.carga_id = redes.f_ref_vigente('val_amarre') and am.activo_id = m.activo_id and am.n = {N_HIDRANTES})),
      (select count(*) from redes.val_amarre am where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja = 'acueducto' and am.n = {N_HIDRANTES})::text || ' hidrantes en la red'),
  (8, '08 válvulas: las 730 de cierre del modelo tienen su amarre por diámetro (con fila, o «sin fila» si la valoración no trae ese diámetro)',
      (select count(*) from redes.val_amarre am join redes.activos a on a.id = am.activo_id and a.prefijo = 'VAL' join redes.activo_vigente_mat m on m.activo_id = a.id
        where am.carga_id = redes.f_ref_vigente('val_amarre') and exists (select 1 from redes.pm_valvulas w where w.llave = m.llave_capa and w.carga_id = redes.f_ref_vigente('pm_valvulas'))) = 730,
      (select count(*) filter (where am.n is not null) || ' con fila · ' || count(*) filter (where am.n is null) || ' sin fila'
         from redes.val_amarre am join redes.activos a on a.id = am.activo_id and a.prefijo = 'VAL' where am.carga_id = redes.f_ref_vigente('val_amarre'))),
  (9, '09 puntuales uno a uno: la planta con sus dos filas (Huaricha y Gota Fría), La Pedregosa y La Popa con la suya',
      (select count(*) from redes.val_amarre am join redes.activos a on a.id = am.activo_id where am.carga_id = redes.f_ref_vigente('val_amarre') and a.prefijo = 'PTA' and am.n in ({N_HUARICHA}, {N_GOTA})) = 2
      and (select count(*) from redes.val_amarre am join redes.activos a on a.id = am.activo_id where am.carga_id = redes.f_ref_vigente('val_amarre') and a.prefijo = 'TAN' and am.n = {N_PEDREGOSA}) = 1
      and (select count(*) from redes.val_amarre am join redes.activos a on a.id = am.activo_id where am.carga_id = redes.f_ref_vigente('val_amarre') and a.prefijo = 'TAN' and am.n = {N_POPA}) = 1,
      (select string_agg(a.codigo || '→' || am.n, ', ' order by am.n) from redes.val_amarre am join redes.activos a on a.id = am.activo_id
        where am.carga_id = redes.f_ref_vigente('val_amarre') and a.prefijo in ('PTA', 'TAN') and am.n is not null)),
  (10, '10 la ficha oficial no cambió: ninguna versión de activo ni evento se creó con la carga',
      not exists (select 1 from redes.activo_versiones v where v.creado_en >= transaction_timestamp())
      and not exists (select 1 from redes.activo_eventos e where e.creado_en >= transaction_timestamp()), null),
  (11, '11 la ficha de un tramo amarrado trae «Inventario regulatorio» para el administrador (remunerado, con su fila) y NO la trae para el operador',
      (v_f -> 'regulatorio' ->> 'remunerado')::boolean and jsonb_array_length(v_f -> 'regulatorio' -> 'filas') = 1 and (v_f -> 'regulatorio' ->> 'fuente') like '%propuesta%'
      and not (redes.f_ficha(v_id, 'operador') ? 'regulatorio'),
      v_cod || ': ' || (v_f -> 'regulatorio' -> 'filas' -> 0 ->> 'nombre') || ' ' || (v_f -> 'regulatorio' -> 'filas' -> 0 ->> 'caracteristica') || '"'),
  (12, '12 la conciliación responde con las 3 hojas y sus filas, y dice cuáles filas no tienen activos y cuáles activos no tienen fila',
      (v_j ->> 'cargada')::boolean and jsonb_array_length(v_j -> 'hojas') = 3 and jsonb_array_length(v_j -> 'filas') = {len(FILAS)}
      and exists (select 1 from jsonb_array_elements(v_j -> 'filas') x where (x ->> 'activos')::integer = 0) and jsonb_array_length(v_j -> 'sin_fila') > 0,
      (select count(*) filter (where (x ->> 'activos')::integer = 0) || ' filas sin activos (las 3 hojas) · ' from jsonb_array_elements(v_j -> 'filas') x)
      || (select coalesce(sum((x ->> 'activos')::integer), 0) from jsonb_array_elements(v_j -> 'sin_fila') x) || ' activos sin fila'),
  (13, '13 TIEMPOS: la conciliación, la ficha y la tesela más cargada, cada una en menos de 5 s',
      greatest(v_ms1, v_ms2, v_ms3) < 5000,
      format('TIEMPOS: conciliación %s ms · ficha de %s %s ms · tesela %s/%s/%s %s ms (%s kB)', v_ms1, v_cod, v_ms2, v_z, v_x, v_y, v_ms3, round(length(v_mvt) * 0.75 / 1024))),
  (14, '14 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()), null);
end $$;
do $$
declare v_t integer; v_b integer; v_f text; v_i text;
begin
  select count(*), count(*) filter (where coalesce(ok, false)), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\\n' order by n) filter (where not coalesce(ok, false)), ''),
         string_agg('  ' || lpad(n::text, 2, '0') || ' ' || coalesce(detalle, ''), E'\\n' order by n) filter (where detalle is not null and coalesce(ok, false))
    into v_t, v_b, v_f, v_i from _val_r;
  if v_b <> v_t or coalesce(current_setting('redes.val_ensayo', true), '') = 'si' then
    raise exception E'CARGA DEL INVENTARIO REGULATORIO · CORTE 10%\\n%\\n%\\nRESULTADO: % de % comprobaciones correctas — %',
      case when coalesce(current_setting('redes.val_ensayo', true), '') = 'si' then ' (ENSAYO: este ERROR es el esperado y deshace todo)' else ' (se deshace todo: no quedó nada cargado)' end,
      v_f, v_i, v_b, v_t, case when v_b = v_t then 'SIN FALLAS' else (v_t - v_b) || ' FALLA(S)' end;
  end if;
  raise notice E'CARGA DEL INVENTARIO REGULATORIO · CORTE 10\\n%\\n% de % comprobaciones correctas — SIN FALLAS', v_i, v_b, v_t;
end $$;
"""

md5s = '\n'.join(f'--   {m}  {a}' for a, m in M.items())
CAB = """-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 — %s. Generado por carga_val/carga_val.py.
%s
-- Archivos de paquete_fase1/regulatorio/ con que se generó (md5):
%s
-- =====================================================================
\\set ON_ERROR_STOP 1
\\if :{?solicitante}
\\else
  \\echo 'Falta el correo del administrador. Uso: psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO -f %s'
  \\quit
\\endif
\\pset pager off
\\timing on
begin;
set local statement_timeout = 0;
do $$
begin
  if to_regclass('redes.val_filas') is null or to_regprocedure('public.geoportal_redes_valoracion(text)') is null then raise exception 'Falta la migración del Corte 10: deténgase y avise'; end if;
end $$;
select public.geoportal_es_admin(lower(:'solicitante')) as es_admin \\gset
\\if :es_admin
\\else
  \\echo 'Ese correo no es de un administrador del geoportal: no se carga nada.'
  rollback;
  \\quit
\\endif
select exists (select 1 from redes.v_ref_carga_vigente where conjunto = 'valoracion' and md5 = '%s') as ya_cargada \\gset
\\if :ya_cargada
  \\echo 'Esta valoración ya está cargada y vigente (mismo archivo): no se carga de nuevo.'
  rollback;
  \\quit
\\endif
"""
os.makedirs(PARTES, exist_ok=True)


def escribir(nombre, texto):
    with open(os.path.join(SALIDA, nombre), 'w', encoding='utf-8') as f:
        f.write(texto)


escribir('partes/10_valoracion.sql', '\n'.join(p10) + '\n')
escribir('partes/20_amarre.sql', '\n'.join(p20) + '\n')
escribir('partes/30_comprobar.sql', p30)
INC = "\\ir partes/10_valoracion.sql\n\\ir partes/20_amarre.sql\n\\ir partes/30_comprobar.sql\n"
escribir('carga_valoracion.sql', CAB % (
    'CARGA DEL INVENTARIO REGULATORIO (la Valoración Técnica 2019 y el amarre de cada activo con su fila)',
    """-- DESPUÉS de la migración del Corte 10 y de su verificación. Un solo comando, desde esta carpeta (la cadena de conexión la pone usted en su terminal):
--   psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO_DEL_ADMINISTRADOR -f carga_valoracion.sql
-- Todo va en UNA transacción: si una comprobación falla, no queda nada. No cambia la ficha oficial de ningún activo. Repetirlo no duplica (la guardia se niega).
-- Al final muestra «N de N comprobaciones correctas — SIN FALLAS» con los TIEMPOS.""", md5s, 'carga_valoracion.sql', M[LIBRO]) + INC + "commit;\n\\echo 'Inventario regulatorio cargado. Corra ahora verificacion_carga_valoracion.sql.'\n")
escribir('ensayo_carga_valoracion.sql', CAB % (
    'ENSAYO DE LA CARGA DEL INVENTARIO REGULATORIO (no deja nada)',
    """-- Corre toda la carga en UNA transacción que termina en ERROR a propósito y deshace todo:
--   psql "$CADENA_EMDUPAR" -v solicitante=CORREO_DEL_ADMINISTRADOR -f ensayo_carga_valoracion.sql
-- Resultado esperado al final:  ERROR: CARGA DEL INVENTARIO REGULATORIO · CORTE 10 (ENSAYO…) … RESULTADO: N de N comprobaciones correctas — SIN FALLAS
-- Copie la línea TIEMPOS: son los tiempos medidos en la base donde corre (la comprobación 13 falla si alguno pasa de 5 s).""", md5s, 'ensayo_carga_valoracion.sql', M[LIBRO])
    + "select set_config('redes.val_ensayo', 'si', true) as ensayo \\gset\n" + INC + "rollback;\n")
escribir('verificacion_carga_valoracion.sql', f"""-- =====================================================================
-- TÉCNICA · FASE 1 · CORTE 10 — VERIFICACIÓN DE LA CARGA DEL INVENTARIO REGULATORIO (solo lectura, una consulta; apta para el editor SQL web).
-- Generado por carga_val/carga_val.py. Todas las filas deben decir OK (las INFO son informativas).
-- =====================================================================
select k, v from (
  select 1 as o, '01 la valoración vigente es la de este paquete ({LIBRO})' as k,
         case when (select md5 from redes.v_ref_carga_vigente where conjunto = 'valoracion') = '{M[LIBRO]}' then 'OK' else 'MAL' end as v
  union all select 2, '02 3 hojas con 59, 39 y 68 filas, y su BCR0 cuadra con la suma del valor remanente',
         case when (select string_agg(h.hoja || '=' || (select count(*) from redes.val_filas f where f.carga_id = h.carga_id and f.hoja = h.hoja), ',' order by h.hoja)
                      from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion')) = 'acueducto=59,alcantarillado=39,alcantarillado_2=68'
               and not exists (select 1 from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion')
                                and abs(h.bcr0 - (select sum(coalesce(f.valor_remanente, 0)) from redes.val_filas f where f.carga_id = h.carga_id and f.hoja = h.hoja)) >= 1) then 'OK' else 'MAL' end
  union all select 3, '03 el amarre vigente es el de este paquete y se hizo contra la valoración vigente',
         case when (select md5 from redes.v_ref_carga_vigente where conjunto = 'val_amarre') = '{MD5_AM}'
               and not exists (select 1 from redes.val_amarre am where am.carga_id = redes.f_ref_vigente('val_amarre') and am.val_carga_id <> redes.f_ref_vigente('valoracion')) then 'OK' else 'MAL' end
  union all select 4, '04 ningún activo cambió de versión por la carga (la ficha oficial no se toca)',
         case when not exists (select 1 from redes.activo_versiones v join redes.ref_cargas c on c.conjunto = 'val_amarre' and c.id = redes.f_ref_vigente('val_amarre')
                                where v.autor = c.autor and v.creado_en between c.creado_en - interval '1 minute' and c.creado_en + interval '5 minutes') then 'OK' else 'REVISAR' end
  union all select 5, 'INFO hoja de alcantarillado que vale · BCR0 por hoja (millones)',
         redes.f_val_hoja_alc() || ' · ' || (select string_agg(h.nombre_hoja || ' ' || round(h.bcr0 / 1e6), ' · ' order by h.hoja) from redes.val_hojas h where h.carga_id = redes.f_ref_vigente('valoracion'))
  union all select 6, 'INFO amarre (hojas vigentes): activos con fila · sin fila · proyectados',
         (select count(distinct am.activo_id) filter (where am.n is not null) || ' · ' || count(distinct am.activo_id) filter (where am.situacion = 'sin_fila') || ' · '
                 || count(distinct am.activo_id) filter (where am.situacion = 'proyectado')
            from redes.val_amarre am where am.carga_id = redes.f_ref_vigente('val_amarre') and am.hoja in ('acueducto', redes.f_val_hoja_alc()))
) t order by o;
""")
print(f'valoración: {len(FILAS)} filas ({", ".join(h + "=" + str(t["filas"]) for h, t in TOTALES.items())}) · amarre de archivo: {len(AM)} filas ({n_acu} tramos, {n_alc} conductos × 2 hojas)')
print('calzan (±2 %) con el amarre de archivo:', CALZA)
for n in sorted(os.listdir(SALIDA)) + ['partes/' + x for x in sorted(os.listdir(PARTES))]:
    p = os.path.join(SALIDA, n)
    if os.path.isfile(p):
        print(f'  {os.path.getsize(p):>9} {n}')
