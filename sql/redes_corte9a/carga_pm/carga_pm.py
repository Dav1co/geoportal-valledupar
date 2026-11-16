#!/usr/bin/env python3
"""Paquete de carga del Plan Maestro 2014 — Técnica fase 1, Corte 9a. Sin dependencias (sqlite3 y csv de Python; lee los GeoPackage directamente).
Lee regulatorio/salida_geoportal/ (LEEME.md) y escribe en generado/ un paquete reproducible por psql, como la carga inicial del 1a:
  · carga_pm_todo.sql          un solo comando: guardia (md5 de cada archivo), las tablas de referencia (una transacción) y las cargas del motor
                               de «sectores» y «sumideros» con su resumen. NO publica las capas del motor.
  · publicar_pm.sql            después de revisar el resumen: publica sectores y sumideros, crea el tanque La Popa, pone el alias «Hidrante» a las
                               Torres, marca «por verificar» y comprueba todo (una transacción: si una comprobación falla, no queda nada).
  · ensayo_carga_pm.sql        lo mismo que los dos anteriores en UNA transacción que termina en ERROR a propósito («N de N … SIN FALLAS»).
  · verificacion_carga_pm.sql  solo lectura, una consulta (apta para el editor).
  · partes/                    los trozos que incluyen los anteriores.
NUNCA carga alc_catastro_* sobre alc_conductos ni alc_pozos (advertencia 4 del LEEME): el catastro entra solo como enriquecimiento, en tablas aparte.
El campo oficial «efecto» de las válvulas no se toca. Sin datos de personas.
Uso: python3 -I carga_pm.py   (no necesita base de datos)."""
import csv
import hashlib
import json
import os
import sqlite3
import struct

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.join(AQUI, 'generado')
PARTES = os.path.join(SALIDA, 'partes')
FUENTE = os.environ.get('SALIDA_GEOPORTAL', os.path.expanduser('~/geoportal-consultas/tecnica/paquete_fase1/regulatorio/salida_geoportal'))
PM = 'Plan Maestro 2014 (Contrato 033)'
LOTE_SQL = 400       # filas por insert
LOTE_MOTOR = 200     # filas por lote del motor (parámetro lote_max_filas)


# ---------- utilidades ----------
def md5(rel):
    h = hashlib.md5()
    with open(os.path.join(FUENTE, rel), 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def num(x):
    return ('%.9f' % x).rstrip('0').rstrip('.')      # como shp.py del 1a: sin ceros de más


def wkt_de_gpkg(blob):
    """Geometría de GeoPackage (cabecera GP + WKB) → WKT en 2D. Puntos, líneas, polígonos y sus «multi»."""
    assert blob[:2] == b'GP', 'no es geometría de GeoPackage'
    flags = blob[3]
    env = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}[(flags >> 1) & 7]
    d = memoryview(blob)[8 + env:]
    pos = 0

    def leer():
        nonlocal pos
        o = '<' if d[pos] == 1 else '>'
        t = struct.unpack_from(o + 'I', d, pos + 1)[0]
        pos += 5
        dims = 2 + (1 if (t // 1000 in (1, 3) or t & 0x80000000) else 0) + (1 if (t // 1000 in (2, 3) or t & 0x40000000) else 0)
        t = (t & 0xFFFF) % 1000

        def pto():
            nonlocal pos
            c = struct.unpack_from(o + 'd' * dims, d, pos)
            pos += 8 * dims
            return f'{num(c[0])} {num(c[1])}'

        def anillo():
            nonlocal pos
            n = struct.unpack_from(o + 'I', d, pos)[0]
            pos += 4
            return '(' + ','.join(pto() for _ in range(n)) + ')'

        def varios(f):
            nonlocal pos
            n = struct.unpack_from(o + 'I', d, pos)[0]
            pos += 4
            return [f() for _ in range(n)]
        if t == 1:
            return 'POINT', '(' + pto() + ')'
        if t == 2:
            return 'LINESTRING', anillo()
        if t == 3:
            return 'POLYGON', '(' + ','.join(varios(anillo)) + ')'
        if t in (4, 5, 6):
            return {4: 'MULTIPOINT', 5: 'MULTILINESTRING', 6: 'MULTIPOLYGON'}[t], '(' + ','.join(x[1] for x in varios(leer)) + ')'
        raise ValueError(f'geometría no admitida: {t}')
    tipo, cuerpo = leer()
    return tipo + cuerpo


def capa(nombre):
    """Filas de un GeoPackage de una sola capa, como diccionarios; «_wkt» es la geometría."""
    c = sqlite3.connect(os.path.join(FUENTE, 'capas', nombre + '.gpkg'))
    c.row_factory = sqlite3.Row
    out = []
    for r in c.execute(f'select * from "{nombre}" order by fid'):
        f = dict(r)
        g = f.pop('geom')
        f.pop('fid')
        f['_wkt'] = wkt_de_gpkg(g) if g else None
        out.append(f)
    c.close()
    return out


def tabla(nombre):
    with open(os.path.join(FUENTE, 'tablas', nombre + '.csv'), encoding='utf-8', newline='') as f:
        return list(csv.DictReader(f))


def vacio(v):
    return v is None or (isinstance(v, str) and v.strip() in ('', 'nan', 'None', '<NA>'))


def lit(v):
    """Literal SQL."""
    if vacio(v):
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v) if isinstance(v, int) else num(v)
    return "'" + str(v).strip().replace("'", "''") + "'"


def n_(v):          # número o nulo
    if vacio(v):
        return 'null'
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 'null'
    return 'null' if x != x else num(x)


def b_(v):          # sí/no o nulo
    if vacio(v):
        return 'null'
    return 'true' if str(v).strip().lower() in ('1', 'true', 't', 'si', 'sí', '1.0') else 'false'


def ent(v):         # entero o nulo
    return 'null' if vacio(v) else str(int(float(v)))


def txt(v):         # llave en texto: 25.0 → 25
    if vacio(v):
        return None
    if isinstance(v, float) and v == int(v):
        return str(int(v))
    s = str(v).strip()
    return s[:-2] if s.endswith('.0') and s[:-2].isdigit() else s


def rot(pares):
    """Lista rotulada para la tarjeta o la ficha: [{"r": rótulo, "v": valor}], sin los vacíos."""
    out = []
    for r, v, *u in pares:
        if vacio(v):
            continue
        if isinstance(v, float):
            v = round(v, 3)
            v = int(v) if v == int(v) else v
        if isinstance(v, str):
            v = v.strip()
            if v.upper().replace('Ó', 'O') in ('SIN OBSERVACION', 'DESCONOCIDO', 'NO APLICA'):
                continue
        e = {'r': r, 'v': v}
        if u and u[0]:
            e['u'] = u[0]
        out.append(e)
    return out


def js(o):
    return "'" + json.dumps(o, ensure_ascii=False, separators=(',', ':')).replace("'", "''") + "'::jsonb"


def geo(w):
    return 'null' if w is None else f"ST_GeomFromText('{w}', 4326)"


MANIFIESTO = []      # (conjunto, archivo, md5, filas, nota)
BLOQUES = []         # SQL de las tablas de referencia


def bloque(conjunto, archivos, tabla_sql, columnas, filas, nota=None):
    """Un conjunto = una fila de redes.ref_cargas (con el md5 de su archivo; si son varios, el md5 de sus md5) y sus filas."""
    ms = [md5(a) for a in archivos]
    m = ms[0] if len(ms) == 1 else hashlib.md5(''.join(ms).encode()).hexdigest()
    MANIFIESTO.append((conjunto, ' + '.join(archivos), m, len(filas), nota, list(zip(archivos, ms))))
    s = [f"\n-- ---------- {conjunto}: {len(filas)} filas de {' + '.join(archivos)} ----------",
         f"insert into redes.ref_cargas (conjunto, archivo, md5, filas, origen, nota, autor) values ('{conjunto}', {lit(' + '.join(archivos))}, '{m}', {len(filas)}, {lit(PM)}, {lit(nota)}, :'solicitante')"
         f" returning id as carga \\gset"]
    for i in range(0, len(filas), LOTE_SQL):
        s.append(f"insert into redes.{tabla_sql} (carga_id, {columnas}) values\n" + ',\n'.join(f"(:carga, {f})" for f in filas[i:i + LOTE_SQL]) + ';')
    BLOQUES.append('\n'.join(s))


# =====================================================================
# 1. Acueducto: nodos, tramos, válvulas y presiones por hora (referencia de modelo)
# =====================================================================
cmp_n = {txt(r['id']): r for r in tabla('comparacion_geoportal_vs_modelo_nodos')}
nodos = capa('acueducto_nodos')
assert len(nodos) == 8165 and len(cmp_n) == 8165
filas = []
for r in nodos:
    k = txt(r['llave'])
    c = cmp_n[k]
    filas.append(', '.join([lit(k), lit(r['nombre']), lit(r['tipo']), lit(c['que_es']), lit(r['zona_modelo']), lit(r['nota_modelo']), b_(r['activo_modelo']),
                            lit(c['estado_modelo_sugerido']), b_(c['estado_difiere']), n_(r['cota_m']), ent(r['n_tramos']),
                            n_(r['demanda_exist_Lps']), n_(r['demanda_futura_Lps']), b_(r['emisor_fuga_exist']),
                            n_(r['pres_exist_min_mca']), n_(r['pres_exist_max_mca']), n_(r['pres_exist_media_mca']), n_(r['pres_exist_mediana_mca']), b_(r['pres_exist_negativa_alguna_hora']),
                            n_(r['pres_futura_min_mca']), n_(r['pres_futura_max_mca']), n_(r['pres_futura_media_mca']), n_(r['pres_futura_mediana_mca']), geo(r['_wkt'])]))
bloque('pm_nodos', ['capas/acueducto_nodos.gpkg', 'tablas/comparacion_geoportal_vs_modelo_nodos.csv'], 'pm_nodos',
       'llave, nombre, tipo, que_es, zona_modelo, nota_modelo, activo_modelo, estado_modelo, estado_difiere, cota_m, n_tramos, demanda_exist_lps, demanda_futura_lps, emisor_fuga, '
       'pres_exist_min, pres_exist_max, pres_exist_media, pres_exist_mediana, pres_exist_negativa, pres_futura_min, pres_futura_max, pres_futura_media, pres_futura_mediana, geom', filas,
       'Nodos de ModeloVF que tocan alguna tubería; presión existente de modeloV1 (validado) y futura de ModeloVF. Presión de MODELO, no medida')
N_NODOS_DIF = sum(1 for r in cmp_n.values() if r['estado_difiere'] == 'True' and r['codigo'])

cmp_t = {txt(r['id']): r for r in tabla('comparacion_geoportal_vs_modelo_tramos')}
con = sqlite3.connect(os.path.join(FUENTE, 'capas', 'acueducto_tramos.gpkg'))
con.row_factory = sqlite3.Row
tramos = [dict(r) for r in con.execute('select "ID", clase_red, nota_modelo, "ZONE", "IS_ACTIVE?", frontera_sectores, "q_max_futuro_Lps", v_max_futuro_mps from acueducto_tramos order by fid')]
con.close()
assert len(tramos) == 10578 and len(cmp_t) == 10578
filas = []
for r in tramos:
    k = txt(r['ID'])
    c = cmp_t[k]
    filas.append(', '.join([lit(k), lit(r['clase_red']), lit(r['nota_modelo']), lit(r['ZONE']), b_(r['IS_ACTIVE?']), lit(c['estado_modelo_sugerido']), b_(c['estado_difiere']),
                            b_(r['frontera_sectores']), n_(r['q_max_futuro_Lps']), n_(r['v_max_futuro_mps'])]))
bloque('pm_tramos', ['capas/acueducto_tramos.gpkg', 'tablas/comparacion_geoportal_vs_modelo_tramos.csv'], 'pm_tramos',
       'llave, clase_red, nota_modelo, zona_modelo, activo_modelo, estado_modelo, estado_difiere, frontera_sectores, q_max_futuro_lps, v_max_futuro_mps', filas,
       'Solo los atributos nuevos del modelo por tramo (clase de red, estado, caudal y velocidad futuros). La capa «acueducto» NO se recarga')
N_TRAMOS_DIF = sum(1 for r in cmp_t.values() if r['estado_difiere'] == 'True')

valv = capa('acueducto_valvulas_cierre')
assert len(valv) == 730
filas = [', '.join([lit(txt(r['llave'])), lit(r['nombre']), lit(r['estado_modelo_existente']), lit(r['estado_modelo_futuro']), b_(r['estado_difiere_entre_modelos']), lit(r['estado_catastro']),
                    b_(r['estado_contradictorio']), b_(r['verificar_en_campo']), lit(r['efecto_sugerido_modelo']), ent(r['cierre_nodos_sin_agua']), n_(r['cierre_demanda_sin_agua_Lps']),
                    n_(r['diametro_mm'])]) for r in valv]
bloque('pm_valvulas', ['capas/acueducto_valvulas_cierre.gpkg'], 'pm_valvulas',
       'llave, nombre, estado_existente, estado_futuro, difiere_entre_modelos, estado_catastro, estado_contradictorio, verificar_en_campo, efecto_sugerido, cierre_nodos_sin_agua, cierre_demanda_lps, diametro_mm',
       filas, 'Válvulas de cierre «V» existentes. El estado que manda es el de modeloV1. El efecto es SUGERIDO: el oficial lo llena el supervisor')
N_VALV_VERIF = sum(1 for r in valv if r['verificar_en_campo'])

for esc, arch in (('existente', 'presiones_nodo_hora_existente'), ('futura', 'presiones_nodo_hora_futura')):
    pr = tabla(arch)
    filas = []
    for r in pr:
        horas = [r[f'p_h{h:02d}_mca'] for h in range(25)]
        if any(vacio(h) for h in horas):
            continue
        filas.append(', '.join([lit(txt(r['llave_nodo'])), f"'{esc}'", n_(r['p_min_mca']), n_(r['hora_p_min']), n_(r['p_max_mca']), n_(r['hora_p_max']), n_(r['p_media_mca']),
                                n_(r['p_mediana_horaria_mca']), "'{" + ','.join(n_(h) for h in horas) + "}'"]))
    bloque(f'pm_presion_{esc}', [f'tablas/{arch}.csv'], 'pm_presion_hora', 'llave, escenario, p_min, hora_min, p_max, hora_max, p_media, p_mediana, horas', filas, pr[0]['escenario'])

# =====================================================================
# 2. Alcantarillado: enriquecimiento con el catastro 2014 (la Alternativa 1 sigue siendo la base)
# =====================================================================
ec = tabla('enriquecimiento_alc_conductos')
assert len(ec) == 9064 and len({r['llave_capa_LABEL'] for r in ec}) == 9064
filas = []
for r in ec:
    pend = None if vacio(r['cat_Pendiente']) else round(float(r['cat_Pendiente']), 2)
    d = rot([('Sección', r['cat_Seccion']), ('Cota de rasante inicial', r['cat_CotaRasanteInicial'], 'm'), ('Cota de rasante final', r['cat_CotaRasanteFinal'], 'm'),
             ('Cota clave inicial', r['cat_CotaClaveInicial'], 'm'), ('Cota clave final', r['cat_CotaClaveFinal'], 'm'),
             ('Cota de batea inicial', r['cat_CotaBateaInicial'], 'm'), ('Cota de batea final', r['cat_CotaBateaFinal'], 'm'), ('Pendiente', pend, '%'),
             ('Observación del catastro', r['cat_Observacion']), ('Fila de la valoración de 2019', r['cat_fila_valoracion']),
             ('Material distinto del de la Alternativa 1', 'Sí' if r['material_difiere'] == 'True' else None),
             ('Diámetro distinto del de la Alternativa 1', 'Sí' if r['diametro_difiere'] == 'True' else None)])
    filas.append(', '.join([lit(r['llave_capa_LABEL']), lit(r['origen']), lit(r['cod_tubo_catastro']), lit(r['cat_material']), n_(r['cat_diametro_mm']), n_(r['cat_diametro_nominal_pulg']),
                            lit(r['cat_EstadoFisico']), lit(r['cat_EstadoOperacional']), lit(r['cat_TipoRed']), n_(r['cat_ProfundidadInicial']), n_(r['cat_ProfundidadFinal']), js(d)]))
bloque('pm_alc_conductos', ['tablas/enriquecimiento_alc_conductos.csv'], 'pm_alc_conductos',
       'llave, origen, cod_tubo_catastro, material, diametro_mm, diametro_nominal_pulg, estado_fisico, estado_operacional, tipo_red, prof_inicial_m, prof_final_m, datos', filas,
       'Catastro levantado (2013-2014) sobre los conductos de la Alternativa 1, por etiqueta y, en los tramos partidos, por geometría')
ep = tabla('enriquecimiento_alc_pozos')
assert len(ep) == 9146 and len({r['llave_capa_LABEL'] for r in ep}) == 9146
filas = []
for r in ep:
    d = rot([('Cota de rasante', r['cat_CotaRasante'], 'm'), ('Cota de fondo', r['cat_CotaFondo'], 'm'), ('Estado de la tapa', r['cat_EstadoTapa']), ('Material de la tapa', r['cat_MaterialTapa']),
             ('Tipo de cargue', r['cat_TipoCargue']), ('Estado del cargue', r['cat_EstadoCargue']), ('Cono', r['cat_Cono']), ('Estado del cono', r['cat_EstadoCono']),
             ('Material del cilindro', r['cat_MaterialCilindro']), ('Estado del cilindro', r['cat_EstadoCilindro']), ('Cámara de caída', r['cat_CamaraCaida']),
             ('Estado de los escalones', r['cat_EstadoEscalones']), ('Material de los escalones', r['cat_MaterialEscalones']), ('Estado de la cañuela', r['cat_EstadoCañuela']),
             ('Estado operacional', r['cat_EstadoOperacional']), ('Fuente de la información', r['cat_fuente_informacion']), ('Observación del catastro', r['cat_Observacion'])])
    filas.append(', '.join([lit(r['llave_capa_LABEL']), lit(r['familia_etiqueta']), b_(r['en_catastro']), lit(r['verificacion']), b_(r['verificacion'].startswith('POR VERIFICAR')),
                            lit(r['cat_EstadoPozo']), n_(r['cat_profundidad_m']), lit(r['cat_fecha_inspeccion']), js(d)]))
bloque('pm_alc_pozos', ['tablas/enriquecimiento_alc_pozos.csv'], 'pm_alc_pozos', 'llave, familia, en_catastro, verificacion, por_verificar, estado_pozo, profundidad_m, fecha_inspeccion, datos', filas,
       'Catastro levantado sobre los pozos de la Alternativa 1. MHP, MH y MHONE quedan «por verificar» (decisión de David, 16-nov)')
N_POZOS_VERIF = sum(1 for r in ep if r['verificacion'].startswith('POR VERIFICAR') and r['codigo_geoportal'])

# =====================================================================
# 3. Capas de referencia (no son activos)
# =====================================================================
COLS_REF = 'capa, llave, nombre, clase, estado, valor, datos, geom'
prop = capa('acueducto_valvulas_propuestas')
assert len(prop) == 491
filas = [', '.join(["'plan_valvulas'", lit(txt(r['llave'])), lit(r['nombre']), "'propuesta'", lit(r['estado_modelo_futuro']), n_(r['diametro_mm']),
                    js(rot([('Clase', r['clase']), ('Diámetro', r['diametro_mm'], 'mm'), ('Estado en la red futura del Plan', r['estado_modelo_futuro']), ('Tramos que conecta', r['n_tramos']),
                            ('Sector según el plano de válvulas', r['sector_segun_plano_valvulas']), ('Plancha del plano de válvulas', r['plancha_plano_valvulas'])])),
                    geo(r['_wkt'])]) for r in prop]
bloque('plan_valvulas', ['capas/acueducto_valvulas_propuestas.gpkg'], 'ref_elementos', COLS_REF, filas, 'Válvulas de sectorización PROPUESTAS por el Plan, no instaladas. Fuera de cualquier simulación')

camp = {r['llave']: r for r in capa('campana_presiones_2014')}
res = tabla('campana2014_puntos_resumen')
assert len(camp) == 11 and len(res) == 12
filas = []
for r in res:
    k = 'CAMP2014-P%02d' % int(r['punto'])
    g = camp.get(k)
    dup = (g or {}).get('serie_duplicada_con')
    d = rot([('Dirección', r['direccion']), ('Desde', r['desde']), ('Hasta', r['hasta']), ('Lecturas', int(float(r['lecturas']))),
             ('Mínima', float(r['p_min_mca']), 'm.c.a.'), ('Máxima', float(r['p_max_mca']), 'm.c.a.'), ('Media', float(r['p_media_mca']), 'm.c.a.'), ('Mediana', float(r['p_mediana_mca']), 'm.c.a.'),
             ('Hora típica de la mínima', f"{int(float(r['hora_tipica_min']))}:00 ({r['p_media_hora_min_mca']} m.c.a.)"),
             ('Hora típica de la máxima', f"{int(float(r['hora_tipica_max']))}:00 ({r['p_media_hora_max_mca']} m.c.a.)"),
             ('Lecturas por debajo de 15 m.c.a.', float(r['pct_lecturas_bajo_15_mca']), '%'), ('Lecturas por debajo de 5 m.c.a.', float(r['pct_lecturas_bajo_5_mca']), '%'),
             ('Modelo validado en el informe (mín. a máx.)', None if vacio(r['informe_modelo_min']) else f"{r['informe_modelo_min']} a {r['informe_modelo_max']} m.c.a."),
             ('Nodo del modelo más cercano', None if vacio(r['nodo_modelo_cercano']) else f"{r['nodo_modelo_cercano']} (a {r['dist_nodo_m']} m)"),
             ('Ubicación', r['fuente_ubicacion'] if g else 'Sin coordenada: el punto no está en el plano de la campaña'),
             ('Calidad del dato', f'La serie es igual a la de {dup} en los archivos originales' if not vacio(dup) else None)])
    filas.append(', '.join(["'campana_2014'", lit(k), lit(f"Punto {int(r['punto'])} · {r['direccion']}"), "'medida'", 'null', n_(r['p_media_mca']), js(d), geo(g['_wkt'] if g else None)]))
bloque('campana_2014', ['capas/campana_presiones_2014.gpkg', 'tablas/campana2014_puntos_resumen.csv'], 'ref_elementos', COLS_REF, filas,
       'Campaña de medición de presiones (31-ene a 8-feb-2014): 12 puntos, 11 con coordenada. La única presión MEDIDA')
ser = tabla('campana2014_series_15min')
cuenta = {}
filas = []
for r in ser:
    cuenta[r['llave']] = cuenta.get(r['llave'], 0) + 1
    filas.append(f"{lit(r['llave'])}, {cuenta[r['llave']]}, {lit(r['fecha_hora'])}, {n_(r['p_mca'])}")
assert set(cuenta) <= {'CAMP2014-P%02d' % i for i in range(1, 13)}
bloque('campana_2014_lecturas', ['tablas/campana2014_series_15min.csv'], 'pm_campana_lecturas', 'llave, n, cuando, p_mca', filas, 'Lecturas cada 15 min, en m.c.a.')

filas = []
for r in capa('pluvial_existente_conductos'):
    caja = None if not r['Base'] else f"{r['Base']} × {r['Altura']} m"
    filas.append(', '.join(["'pluvial'", lit('con:' + r['llave']), lit(r['llave']), "'conducto'", lit(r['EstadoFisico']), n_(r['diametro_mm']),
                            js(rot([('Elemento', 'Conducto pluvial'), ('Material', r['material']), ('Diámetro', r['diametro_mm'], 'mm'), ('Diámetro nominal', r['DiametroNominal'], 'pulg'),
                                    ('Longitud', r['longitud_m'], 'm'), ('Sección', r['Seccion']), ('Base × altura', caja), ('Estado físico', r['EstadoFisico']),
                                    ('Estado operacional', r['EstadoOperacional']), ('Tipo de red', r['TipoRed']), ('Desde', r['PozoInicial']), ('Hasta', r['PozoFinal']),
                                    ('Profundidad inicial', r['ProfundidadInicial'], 'm'), ('Profundidad final', r['ProfundidadFinal'], 'm'),
                                    ('Pendiente', None if vacio(r['Pendiente']) else round(r['Pendiente'], 2), '%'), ('Observación', r['Observacion'])])), geo(r['_wkt'])]))
n_pc = len(filas)
for r in capa('pluvial_existente_pozos'):
    filas.append(', '.join(["'pluvial'", lit('poz:' + r['llave']), lit(r['llave']), "'pozo'", lit(r['EstadoPozo']), n_(r['profundidad_m']),
                            js(rot([('Elemento', 'Pozo pluvial'), ('Estado del pozo', r['EstadoPozo']), ('Profundidad', r['profundidad_m'], 'm'), ('Cota de rasante', r['CotaRasante'], 'm'),
                                    ('Cota de fondo', r['CotaFondo'], 'm'), ('Estado de la tapa', r['EstadoTapa']), ('Material de la tapa', r['MaterialTapa']),
                                    ('Estado operacional', r['EstadoOperacional']), ('Fecha de inspección', r['fecha_inspeccion']), ('Descarga a', r['Descarga_A_']),
                                    ('Observación', r['Observacion'])])), geo(r['_wkt'])]))
assert n_pc == 686 and len(filas) == 686 + 211
bloque('pluvial', ['capas/pluvial_existente_conductos.gpkg', 'capas/pluvial_existente_pozos.gpkg'], 'ref_elementos', COLS_REF, filas, 'Red pluvial existente levantada en 2013: 686 conductos (27,0 km) y 211 pozos')

filas = []
for r in capa('pluvial_alternativa2043_conductos'):
    filas.append(', '.join(["'pluvial_2043'", lit('con:' + r['llave']), lit(f"{r['START_NODE']} → {r['STOP_NODE']}"), "'conducto'", lit(r['ESTADO']), n_(r['DIAMETER'] or None),
                            js(rot([('Elemento', 'Conducto pluvial (alternativa 2043)'), ('Estado en la alternativa', r['ESTADO']), ('Material', r['MATERIAL']),
                                    ('Diámetro', r['DIAMETER'] or None, 'mm'), ('Desde', r['START_NODE']), ('Hasta', r['STOP_NODE']),
                                    ('Cota de batea inicial', r['INV_START'], 'm'), ('Cota de batea final', r['INV_STOP'], 'm'), ('Estado operacional (existentes)', r['TIPO'])])), geo(r['_wkt'])]))
for nombre, clase, rotulo in (('pluvial_alternativa2043_pozos', 'pozo', 'Pozo pluvial (alternativa 2043)'), ('pluvial_alternativa2043_descargas', 'descarga', 'Descarga pluvial (alternativa 2043)')):
    for r in capa(nombre):
        prof = None if vacio(r['GROUNDELEV']) or vacio(r['ELEV_INV']) else round(r['GROUNDELEV'] - r['ELEV_INV'], 2)
        filas.append(', '.join(["'pluvial_2043'", lit(clase[:3] + ':' + r['llave']), lit(r['LABEL']), f"'{clase}'", 'null', n_(prof),
                                js(rot([('Elemento', rotulo), ('Cota de rasante', r['GROUNDELEV'], 'm'), ('Cota de fondo', r['ELEV_INV'], 'm'), ('Profundidad', prof, 'm')])), geo(r['_wkt'])]))
assert len(filas) == 973 + 489 + 20
bloque('pluvial_2043', ['capas/pluvial_alternativa2043_conductos.gpkg', 'capas/pluvial_alternativa2043_pozos.gpkg', 'capas/pluvial_alternativa2043_descargas.gpkg'], 'ref_elementos', COLS_REF, filas,
       'Alternativa pluvial del Plan a 2043 (modelo SewerGEMS): lo existente y lo propuesto')

# =====================================================================
# 4. Por el motor de carga: sectores (SEC) y sumideros (SUM)
# =====================================================================
ORIGEN_SEC = 'Plan Maestro 2014, Anexo C (planos de red y válvulas). Sectores PROYECTADOS por el Plan'
sec = []
for r in capa('sectores_hidraulicos'):
    sec.append({'atributos': {'llave': r['llave'], 'nombre': f"Sector {r['sector']} (Plan Maestro 2014)", 'clase': 'sector', 'estado': 'proyectado', 'sector': int(r['sector']),
                              'subsectores': r['subsectores'], 'tanque_plan': r['tanque_plan'], 'area_ha': r['area_ha'], 'origen': ORIGEN_SEC}, 'wkt': r['_wkt']})
for r in capa('subsectores_hidraulicos'):
    sec.append({'atributos': {'llave': r['llave'], 'nombre': f"Subsector {r['subsector']} (Plan Maestro 2014)", 'clase': 'subsector', 'estado': 'proyectado', 'sector': int(r['sector']),
                              'subsector': str(r['subsector']), 'area_ha': r['area_ha'], 'origen': ORIGEN_SEC}, 'wkt': r['_wkt']})
assert len(sec) == 36 and sum(1 for s in sec if s['atributos']['clase'] == 'sector') == 7
sumi = []
for r in capa('alc_catastro_sumideros'):
    a = {'llave': r['llave'], 'codigo_anterior': r['llave'], 'profundidad_m': r['profundidad_m'], 'tipo_sumidero': r['TipoSumidero'], 'estado_rejilla': r['EstadoRejilla'],
         'material_rejilla': r['MaterialRejilla'], 'estado_operacional': r['EstadoOperacional'], 'estado_fisico': r['EstadoFisico'], 'sistema_catastro': r['Sistema'],
         'fecha_inspeccion': r['fecha_inspeccion'], 'cota_rasante': r['CotaRasante'], 'cota_fondo': r['CotaFondo'], 'cuenca': r['cuenca'], 'observacion': r['Observacion'],
         'origen': 'Plan Maestro 2014: catastro de alcantarillado levantado (2013-2014)'}
    sumi.append({'atributos': {k: v for k, v in a.items() if not vacio(v)}, 'wkt': r['_wkt']})
assert len(sumi) == 484 and len({s['atributos']['llave'] for s in sumi}) == 484
for lista in (sec, sumi):
    for i, f in enumerate(lista, start=1):
        f['orden'] = i
MOTOR = []
for capa_cod, lista, arch, nota in (('sectores', sec, ['capas/sectores_hidraulicos.gpkg', 'capas/subsectores_hidraulicos.gpkg'],
                                     'Plan Maestro 2014: 7 sectores y 29 subsectores PROYECTADOS (Anexo C). No son todavía los sectores con que se opera'),
                                    ('sumideros', sumi, ['capas/alc_catastro_sumideros.gpkg'], 'Plan Maestro 2014: 484 sumideros del catastro levantado (2013-2014)')):
    texto = json.dumps(lista, ensure_ascii=False, separators=(',', ':'))
    MOTOR.append({'capa': capa_cod, 'filas': lista, 'sha': hashlib.sha256(texto.encode('utf-8')).hexdigest(), 'nota': nota, 'archivos': [(a, md5(a)) for a in arch]})

popa = [r for r in capa('acueducto_tanques_y_fuentes') if r['tipo'] == 'tanque' and not r['proyectado'] and vacio(r['codigo_geoportal'])]
assert len(popa) == 1 and 'La Popa' in popa[0]['nombre'], popa
POPA = popa[0]

# =====================================================================
# 5. Escribir el paquete
# =====================================================================
os.makedirs(PARTES, exist_ok=True)
CAB = """\\set ON_ERROR_STOP 1
\\if :{?solicitante}
\\else
  \\echo 'Falta el correo del administrador. Uso: psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO -f %s'
  \\quit
\\endif
\\pset pager off
"""
archivos_md5 = []
for m in MANIFIESTO:
    archivos_md5 += m[5]
for m in MOTOR:
    archivos_md5 += m['archivos']
archivos_md5 += [('capas/acueducto_tanques_y_fuentes.gpkg', md5('capas/acueducto_tanques_y_fuentes.gpkg'))]
lista_md5 = '\n'.join(f'--   {m}  {a}' for a, m in sorted(set(archivos_md5)))

guardia = f"""-- ---------- GUARDIA: el Corte 9a aplicado, quien carga es administrador y ningún conjunto se carga dos veces ----------
do $$
begin
  if to_regclass('redes.ref_cargas') is null or to_regprocedure('redes.f_pm_marcar_por_verificar(text)') is null then
    raise exception 'El Corte 9a no está aplicado en esta base: aplique primero su migración';
  end if;
  if exists (select 1 from redes.f_funciones_sin_where()) then raise exception 'Hay funciones con DELETE o UPDATE sin WHERE: deténgase y avise'; end if;
end $$;
select public.geoportal_es_admin(lower(:'solicitante')) as es_admin \\gset
\\if :es_admin
\\else
  \\echo 'Ese correo no es de un administrador del geoportal: la carga se detiene'
  select 1 / 0;
\\endif
select count(*) > 0 as repetido, coalesce(string_agg(v.conjunto, ', '), '') as cuales from redes.v_ref_carga_vigente v
  join (values {', '.join(f"('{m[0]}', '{m[2]}')" for m in MANIFIESTO)}) x(conjunto, md5) on x.conjunto = v.conjunto and x.md5 = v.md5 \\gset
\\if :repetido
  \\echo 'Estos conjuntos ya están cargados con el mismo archivo (md5):' :cuales
  \\echo 'No se carga nada dos veces. Si de verdad hay que repetir, anule antes esa carga (redes.ref_carga_eventos) y avise.'
  select 1 / 0;
\\endif
"""
open(os.path.join(PARTES, '10_referencia.sql'), 'w', encoding='utf-8').write(
    f"-- Corte 9a · carga del Plan Maestro · tablas de referencia. Generado por carga_pm.py. Se incluye desde carga_pm_todo.sql o ensayo_carga_pm.sql.\n{guardia}" + '\n'.join(BLOQUES)
    + "\nanalyze redes.pm_nodos; analyze redes.pm_tramos; analyze redes.pm_valvulas; analyze redes.pm_presion_hora; analyze redes.pm_alc_conductos; analyze redes.pm_alc_pozos;\n"
      "analyze redes.ref_elementos; analyze redes.pm_campana_lecturas; analyze redes.ref_cargas;\n")

s = ["-- Corte 9a · carga del Plan Maestro · cargas del motor (sectores y sumideros). Generado por carga_pm.py. No publica.\n\\set QUIET 1"]
for m in MOTOR:
    c = m['capa']
    s.append(f"select (public.geoportal_redes_carga_iniciar(:'solicitante', '{c}', '{m['sha']}', 'gpkg', 4326, 'llave', {len(m['filas'])},\n        {lit(m['nota'])}) ->> 'carga_id') as carga_{c} \\gset")
    s.append(f"\\echo '  carga de la capa «{c}»:' :carga_{c}")
    s.append('\\o /dev/null')
    for i in range(0, len(m['filas']), LOTE_MOTOR):
        t = json.dumps(m['filas'][i:i + LOTE_MOTOR], ensure_ascii=False, separators=(',', ':'))
        assert '$lote$' not in t
        s.append(f"select public.geoportal_redes_carga_lote(:'solicitante', :carga_{c}, $lote${t}$lote$::jsonb);")
    s.append('\\o')
s.append('\\unset QUIET')
for m in MOTOR:
    s.append(f"\\echo '=================== RESUMEN de «{m['capa']}» (no se ha publicado) ==================='")
    s.append(f"select r ->> 's' as seccion, r ->> 'c' as concepto, r ->> 'v' as valor from jsonb_array_elements(public.geoportal_redes_carga_resumen(:'solicitante', :carga_{m['capa']}) -> 'tabla') r;")
open(os.path.join(PARTES, '20_motor.sql'), 'w', encoding='utf-8').write('\n'.join(s) + '\n')

cap_popa = int(POPA['volumen_util_m3'])
publicar = f"""-- Corte 9a · carga del Plan Maestro · publicar y sembrar. Generado por carga_pm.py. Va dentro de una transacción (la abre quien lo incluye).
select set_config('redes.pm_solicitante', lower(:'solicitante'), true) as quien \\gset
-- 1. sectores y sumideros (las cargas abiertas de estos mismos archivos)
""" + '\n'.join(f"""select key as dato, value as valor from jsonb_each_text(public.geoportal_redes_carga_publicar(:'solicitante',
  (select id from redes.v_cargas_estado where capa_codigo = '{m['capa']}' and sha256 = '{m['sha']}' and estado = 'abierta'),
  {lit(m['nota'])})) order by 1;""" for m in MOTOR) + f"""
-- 2. el tanque La Popa: el nodo «{POPA['nombre']}» del modelo (llave {txt(POPA['llave'])}) es el tanque real, que faltaba como activo. Solo si sigue «por clasificar».
do $$
declare v_q text := current_setting('redes.pm_solicitante'); v_nodo bigint; v_r jsonb;
begin
  select nodo_id into v_nodo from redes.v_nodo_visible where sistema = 'acueducto' and llave_modelo = '{txt(POPA['llave'])}' and clase_nodo = 'por_clasificar';
  if v_nodo is null then raise notice 'El nodo del tanque La Popa ya no está por clasificar: no se crea de nuevo'; return; end if;
  v_r := public.geoportal_redes_nodo_crear_activo(v_q, v_nodo, 'TAN', null, 'Tanque La Popa (módulo existente)',
           'Plan Maestro 2014: el «{POPA['nombre']}» del modelo es el tanque La Popa real; faltaba como activo (encargo del Corte 9a)');
  perform public.geoportal_redes_ficha_editar(v_q, v_r ->> 'activo',
           jsonb_build_object('capacidad', {cap_popa}, 'origen', jsonb_build_object('origen', 'emdupar', 'nota', 'Fuente del dato: Plan Maestro 2014 (ModeloVF, «{POPA['nombre']}»; {cap_popa} m³ útiles, cota {POPA['cota_m']} m)')),
           'Plan Maestro 2014: capacidad útil del modelo ({cap_popa} m³) y fuente del dato');
  raise notice 'Tanque La Popa creado: %', v_r ->> 'activo';
end $$;
-- 3. «Torre» = hidrante: alias visible del tipo (el prefijo TOR y los códigos no cambian). Solo si no lo tiene ya.
do $$
declare v_q text := current_setting('redes.pm_solicitante');
begin
  if (select nombre_visible from redes.v_tipo_visible where prefijo = 'TOR') is distinct from 'Hidrante' then
    perform public.geoportal_redes_alias_fijar(v_q, 'tipo', 'TOR', 'Hidrante', 'Plan Maestro 2014: los nodos «Torre» son hidrantes en el modelo (confirmado por David el 16-nov)');
  end if;
end $$;
-- 4. «por verificar»: estados distintos en el modelo, válvulas por verificar en campo y pozos MHP, MH y MHONE (evento con motivo; la ficha no cambia)
select redes.f_pm_marcar_por_verificar(lower(:'solicitante')) as marcados_por_verificar;
"""
open(os.path.join(PARTES, '30_publicar.sql'), 'w', encoding='utf-8').write(publicar)

esperado = {m[0]: m[3] for m in MANIFIESTO}
n_ref = esperado['plan_valvulas'] + esperado['campana_2014'] + esperado['pluvial'] + esperado['pluvial_2043']
CHEQUEOS = f"""
  select 1, '01 las {len(MANIFIESTO)} cargas de referencia vigentes, cada una con las filas que dice su registro',
         (select count(*) from redes.v_ref_carga_vigente v join (values {', '.join(f"('{m[0]}', '{m[2]}', {m[3]})" for m in MANIFIESTO)}) x(c, m, n) on x.c = v.conjunto and x.m = v.md5 and x.n = v.filas) = {len(MANIFIESTO)},
         (select string_agg(conjunto || '=' || filas, ', ' order by conjunto) from redes.v_ref_carga_vigente)
  union all select 2, '02 acueducto: {esperado['pm_nodos']} nodos, {esperado['pm_tramos']} tramos y {esperado['pm_valvulas']} válvulas del modelo; presiones por hora {esperado['pm_presion_existente']} (existente) y {esperado['pm_presion_futura']} (futura)',
         (select count(*) from redes.pm_nodos where carga_id = redes.f_ref_vigente('pm_nodos')) = {esperado['pm_nodos']}
         and (select count(*) from redes.pm_tramos where carga_id = redes.f_ref_vigente('pm_tramos')) = {esperado['pm_tramos']}
         and (select count(*) from redes.pm_valvulas where carga_id = redes.f_ref_vigente('pm_valvulas')) = {esperado['pm_valvulas']}
         and (select count(*) from redes.pm_presion_hora where carga_id = redes.f_ref_vigente('pm_presion_existente') and escenario = 'existente') = {esperado['pm_presion_existente']}
         and (select count(*) from redes.pm_presion_hora where carga_id = redes.f_ref_vigente('pm_presion_futura') and escenario = 'futura') = {esperado['pm_presion_futura']}, null
  union all select 3, '03 todo tramo y todo nodo-activo vigente del acueducto tiene su fila de modelo (la capa no se recargó: mismas llaves)',
         not exists (select 1 from redes.activo_vigente_mat m where m.capa_codigo = 'acueducto' and not m.retirado
                      and not exists (select 1 from redes.pm_tramos t where t.llave = m.llave_capa and t.carga_id = redes.f_ref_vigente('pm_tramos')))
         and not exists (select 1 from redes.activo_vigente_mat m where m.capa_codigo = 'acueducto_nodos' and not m.retirado
                      and not exists (select 1 from redes.pm_nodos n where n.llave = m.llave_capa and n.carga_id = redes.f_ref_vigente('pm_nodos'))),
         (select count(*) from redes.activo_vigente_mat m where m.capa_codigo in ('acueducto', 'acueducto_nodos') and not m.retirado)::text || ' activos del modelo'
  union all select 4, '04 las {esperado['pm_valvulas']} válvulas del modelo son activos VAL vigentes y ninguna cambió su «efecto» oficial con la carga',
         (select count(*) from redes.pm_valvulas w join redes.activo_vigente_mat m on m.capa_codigo = 'acueducto_nodos' and m.llave_capa = w.llave and m.prefijo = 'VAL'
           where w.carga_id = redes.f_ref_vigente('pm_valvulas')) = {esperado['pm_valvulas']}
         and not exists (select 1 from redes.activo_versiones v where v.autor = current_setting('redes.pm_solicitante', true) and v.creado_en >= transaction_timestamp()
                          and exists (select 1 from redes.activos a where a.id = v.activo_id and a.prefijo = 'VAL')), null
  union all select 5, '05 alcantarillado: {esperado['pm_alc_conductos']} conductos y {esperado['pm_alc_pozos']} pozos enriquecidos; todo COL y POZ vigente de la capa tiene su fila; ningún activo de alcantarillado se retiró ni cambió de versión',
         (select count(*) from redes.pm_alc_conductos where carga_id = redes.f_ref_vigente('pm_alc_conductos')) = {esperado['pm_alc_conductos']}
         and (select count(*) from redes.pm_alc_pozos where carga_id = redes.f_ref_vigente('pm_alc_pozos')) = {esperado['pm_alc_pozos']}
         and not exists (select 1 from redes.activo_vigente_mat m where m.capa_codigo = 'alc_conductos' and not m.retirado
                          and not exists (select 1 from redes.pm_alc_conductos c where c.llave = m.llave_capa and c.carga_id = redes.f_ref_vigente('pm_alc_conductos')))
         and not exists (select 1 from redes.activo_vigente_mat m where m.capa_codigo = 'alc_pozos' and not m.retirado
                          and not exists (select 1 from redes.pm_alc_pozos c where c.llave = m.llave_capa and c.carga_id = redes.f_ref_vigente('pm_alc_pozos')))
         and not exists (select 1 from redes.activo_versiones v join redes.activos a on a.id = v.activo_id where a.prefijo in ('COL', 'POZ', 'VER') and v.creado_en >= transaction_timestamp())
         and not exists (select 1 from redes.activo_eventos e join redes.activos a on a.id = e.activo_id where a.prefijo in ('COL', 'POZ', 'VER') and e.tipo = 'retirar' and e.creado_en >= transaction_timestamp()), null
  union all select 6, '06 capas de referencia: {n_ref} elementos (491 válvulas propuestas, 12 puntos de la campaña con 11 ubicados, 897 del pluvial existente y 1.482 de la alternativa 2043) y {esperado['campana_2014_lecturas']} lecturas',
         (select count(*) from redes.ref_elementos where carga_id in (select id from redes.v_ref_carga_vigente)) = {n_ref}
         and (select count(*) from redes.ref_elementos where capa = 'campana_2014' and geom is not null and carga_id = redes.f_ref_vigente('campana_2014')) = 11
         and (select count(*) from redes.pm_campana_lecturas where carga_id = redes.f_ref_vigente('campana_2014_lecturas')) = {esperado['campana_2014_lecturas']}
         and not exists (select 1 from redes.ref_elementos e where e.geom is not null and not ST_IsValid(e.geom)), null
  union all select 7, '07 las válvulas propuestas NO son activos: ningún activo VAL nuevo y siguen «por clasificar» o como las dejó el supervisor',
         not exists (select 1 from redes.activos a where a.prefijo = 'VAL' and a.creado_en >= transaction_timestamp()), null
  union all select 8, '08 sectores: 7 sectores y 29 subsectores vigentes como SEC, en estado «Proyectado», con su número; un punto del centro de cada subsector da su sector y su subsector',
         (select count(*) filter (where m.clase = 'sector') = 7 and count(*) filter (where m.clase = 'subsector') = 29 and count(*) filter (where m.estado_codigo <> 'proyectado') = 0
            from redes.activo_vigente_mat m where m.prefijo = 'SEC' and not m.retirado and m.capa_codigo = 'sectores')
         and not exists (select 1 from redes.activo_vigente_mat m join redes.activo_versiones v on v.activo_id = m.activo_id and v.version = m.version
                          cross join lateral redes.f_sector_de(ST_PointOnSurface(m.geom)) s
                          where m.prefijo = 'SEC' and m.clase = 'subsector' and not m.retirado
                            and (s.subsector is distinct from v.atributos -> 'modelo' ->> 'subsector' or s.sector is distinct from (v.atributos -> 'modelo' ->> 'sector')::integer)),
         (select string_agg(distinct (v.atributos -> 'modelo' ->> 'sector'), ',' order by (v.atributos -> 'modelo' ->> 'sector')) from redes.activo_vigente_mat m
            join redes.activo_versiones v on v.activo_id = m.activo_id and v.version = m.version where m.prefijo = 'SEC' and not m.retirado)
  union all select 9, '09 sumideros: 484 activos SUM vigentes de la capa «sumideros»',
         (select count(*) from redes.activo_vigente_mat m where m.prefijo = 'SUM' and m.capa_codigo = 'sumideros' and not m.retirado) = 484, null
  union all select 10, '10 el tanque La Popa es un activo TAN vigente, enlazado a su nodo del modelo, con {cap_popa} m³ y la fuente «Plan Maestro 2014» en su origen',
         (select count(*) from redes.v_nodo_vigente n join redes.v_activo_vigente a on a.activo_id = n.activo_id join redes.v_activo_origen_vigente o on o.activo_id = a.activo_id
           where n.sistema = 'acueducto' and n.llave_modelo = '{txt(POPA['llave'])}' and n.clase_nodo = 'activo' and a.prefijo = 'TAN' and a.capacidad = {cap_popa} and o.nota like '%Plan Maestro 2014%') = 1, null
  union all select 11, '11 el tipo TOR se ve como «Hidrante» y conserva su prefijo y sus códigos',
         (select nombre_visible from redes.v_tipo_visible where prefijo = 'TOR') = 'Hidrante'
         and (select count(*) from redes.activo_vigente_mat where prefijo = 'TOR' and codigo like 'TOR-%') = (select count(*) from redes.activo_vigente_mat where prefijo = 'TOR'), null
  union all select 12, '12 por verificar: todo activo que señala el Plan tiene su marca con motivo y ninguna marca cambió el estado de la ficha',
         not exists (select 1 from redes.v_pm_por_verificar x where not exists (select 1 from redes.activo_eventos e where e.activo_id = x.activo_id and e.tipo = 'por_verificar' and e.motivo like 'Plan Maestro 2014:%'))
         and (select count(distinct activo_id) from redes.v_pm_por_verificar) > 0,
         'activos señalados: ' || (select count(distinct activo_id) from redes.v_pm_por_verificar) || ' (estado ' || (select count(distinct activo_id) from redes.v_pm_por_verificar where grupo = 'estado')
           || ', válvulas ' || (select count(distinct activo_id) from redes.v_pm_por_verificar where grupo = 'valvula') || ', pozos ' || (select count(distinct activo_id) from redes.v_pm_por_verificar where grupo = 'pozo')
           || '); según los archivos: estado {N_NODOS_DIF + N_TRAMOS_DIF}, válvulas {N_VALV_VERIF}, pozos {N_POZOS_VERIF}'
  union all select 13, '13 «gana la ficha»: ningún activo editado en la ficha cambió de versión por esta carga (hoy, solo VAL-000001 «V85»)',
         not exists (select 1 from redes.ficha_ediciones fe join redes.activo_versiones v on v.activo_id = fe.activo_id
                      where v.creado_en >= transaction_timestamp() and fe.creado_en < transaction_timestamp() and v.carga_id is not null), null
  union all select 14, '14 nada se borró: ningún activo retirado ni oculto por esta carga',
         not exists (select 1 from redes.activo_eventos e where e.tipo in ('retirar', 'ocultar') and e.creado_en >= transaction_timestamp()), null
  union all select 15, '15 pg-safeupdate: ninguna función con DELETE o UPDATE sin WHERE', not exists (select 1 from redes.f_funciones_sin_where()), null
"""
comprobar = f"""-- Corte 9a · carga del Plan Maestro · comprobaciones «N de N». Generado por carga_pm.py. Si alguna falla, ERROR: la transacción no queda.
create temp table _pm_r on commit drop as select * from ({CHEQUEOS}) t(n, nombre, ok, detalle);
select n, case when coalesce(ok, false) then 'OK' else 'FALLA' end as resultado, nombre, coalesce(detalle, '') as detalle from _pm_r order by n;
do $$
declare v_t integer; v_b integer; v_f text;
begin
  select count(*), count(*) filter (where coalesce(ok, false)), coalesce(string_agg('  FALLA ' || nombre || ' → ' || coalesce(detalle, ''), E'\\n' order by n) filter (where not coalesce(ok, false)), '')
    into v_t, v_b, v_f from _pm_r;
  if v_b <> v_t or coalesce(current_setting('redes.pm_ensayo', true), '') = 'si' then
    raise exception E'CARGA DEL PLAN MAESTRO · CORTE 9a%\\n%\\nRESULTADO: % de % comprobaciones correctas — %',
      case when coalesce(current_setting('redes.pm_ensayo', true), '') = 'si' then ' (ENSAYO: este ERROR es el esperado y deshace todo)' else ' (se deshace todo: no quedó nada cargado ni publicado en este paso)' end,
      v_f, v_b, v_t, case when v_b = v_t then 'SIN FALLAS' else (v_t - v_b) || ' FALLA(S)' end;
  end if;
  raise notice 'CARGA DEL PLAN MAESTRO · CORTE 9a: % de % comprobaciones correctas — SIN FALLAS', v_b, v_t;
end $$;
"""
open(os.path.join(PARTES, '40_comprobar.sql'), 'w', encoding='utf-8').write(comprobar)

titulo = "-- =====================================================================\n-- TÉCNICA · FASE 1 · CORTE 9a — %s. Generado por carga_pm/carga_pm.py.\n"
md5s = f"-- Archivos de regulatorio/salida_geoportal/ con que se generó (md5):\n{lista_md5}\n-- =====================================================================\n"
open(os.path.join(SALIDA, 'carga_pm_todo.sql'), 'w', encoding='utf-8').write(
    titulo % 'CARGA DEL PLAN MAESTRO 2014 (paso 1 de 2: NO publica las capas del motor)' +
    """-- DESPUÉS de la migración del Corte 9a. Un solo comando, desde esta carpeta (la cadena de conexión la pone usted en su terminal; no va en ningún archivo):
--   psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO_DEL_ADMINISTRADOR -f carga_pm_todo.sql
-- Qué hace: (1) las tablas de referencia del Plan Maestro, en UNA transacción (si algo falla, no queda nada); (2) abre las cargas de «sectores» (36 polígonos)
-- y «sumideros» (484) por el motor del Cargue y muestra su resumen. No toca la ficha oficial de ningún activo. Repetirlo no duplica: la guardia se niega
-- si un conjunto ya está cargado con el mismo archivo. Después: publicar_pm.sql.
""" + md5s + CAB % 'carga_pm_todo.sql' + "\\timing on\nbegin;\n\\ir partes/10_referencia.sql\ncommit;\n\\echo '=================== tablas de referencia cargadas ==================='\n"
    "select conjunto, filas, md5, archivo from redes.v_ref_carga_vigente order by conjunto;\n\\ir partes/20_motor.sql\n"
    "\\echo 'Si los dos resúmenes dicen «lista para publicar: SÍ», corra publicar_pm.sql con el mismo comando.'\n")
open(os.path.join(SALIDA, 'publicar_pm.sql'), 'w', encoding='utf-8').write(
    titulo % 'PUBLICAR LA CARGA DEL PLAN MAESTRO 2014 (paso 2 de 2)' +
    """-- Córralo SOLO después de revisar los resúmenes de carga_pm_todo.sql:
--   psql "$CADENA_EMDUPAR" -v ON_ERROR_STOP=1 -v solicitante=CORREO_DEL_ADMINISTRADOR -f publicar_pm.sql
-- En UNA transacción: publica sectores y sumideros, crea el tanque La Popa, pone el alias «Hidrante» al tipo TOR, marca «por verificar» y corre las
-- comprobaciones «N de N». Si una sola falla, termina en ERROR y no queda nada de este paso.
""" + md5s + CAB % 'publicar_pm.sql' + "\\timing on\nbegin;\n\\ir partes/30_publicar.sql\n\\ir partes/40_comprobar.sql\ncommit;\n\\echo 'Publicado. Verificación de solo lectura: verificacion_carga_pm.sql'\n")
open(os.path.join(SALIDA, 'ensayo_carga_pm.sql'), 'w', encoding='utf-8').write(
    titulo % 'ENSAYO DE LA CARGA DEL PLAN MAESTRO 2014 (no deja nada)' +
    """-- Corre los dos pasos (carga y publicación) en UNA transacción que termina en ERROR a propósito y deshace todo:
--   psql "$CADENA_EMDUPAR" -v solicitante=CORREO_DEL_ADMINISTRADOR -f ensayo_carga_pm.sql
-- Resultado esperado al final:  ERROR: CARGA DEL PLAN MAESTRO · CORTE 9a (ENSAYO…) … RESULTADO: N de N comprobaciones correctas — SIN FALLAS
-- Con «\\timing» muestra cuánto tarda cada paso en la base donde corre.
""" + md5s + CAB % 'ensayo_carga_pm.sql' + "\\timing on\nbegin;\nselect set_config('redes.pm_ensayo', 'si', true) as ensayo \\gset\n\\ir partes/10_referencia.sql\n\\ir partes/20_motor.sql\n"
    "\\ir partes/30_publicar.sql\n\\ir partes/40_comprobar.sql\nrollback;\n")
# verificación de solo lectura (después de publicar): las mismas comprobaciones que no dependen de «en esta transacción»
ver = CHEQUEOS.replace("current_setting('redes.pm_solicitante', true)", "'¬'").replace('transaction_timestamp()', "'infinity'::timestamptz")
open(os.path.join(SALIDA, 'verificacion_carga_pm.sql'), 'w', encoding='utf-8').write(
    titulo % 'VERIFICACIÓN DE LA CARGA DEL PLAN MAESTRO 2014 (solo lectura; una consulta, apta para el editor SQL web)' +
    "-- Todas las filas deben decir OK. (Las comprobaciones 04, 05, 07, 13 y 14 miran «lo hecho por la carga»: aquí solo confirman que el resto sigue en pie.)\n" + md5s +
    f"select n, case when coalesce(ok, false) then 'OK' else 'MAL' end as v, nombre as k, coalesce(detalle, '') as detalle from ({ver}) t(n, nombre, ok, detalle) order by n;\n")
tam = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(SALIDA) for f in fs)
print(f'{len(MANIFIESTO)} conjuntos de referencia · ' + ' · '.join(f'{m[0]} {m[3]}' for m in MANIFIESTO))
print(f'motor: sectores {len(sec)} · sumideros {len(sumi)} · La Popa = nodo {txt(POPA["llave"])} ({cap_popa} m³) · paquete {tam / 1e6:.1f} MB en generado/')
print(f'por verificar según los archivos: estado {N_NODOS_DIF} nodos + {N_TRAMOS_DIF} tramos, válvulas {N_VALV_VERIF}, pozos {N_POZOS_VERIF}')
