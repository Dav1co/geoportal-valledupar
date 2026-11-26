#!/usr/bin/env python3
"""Geovisor técnico · Corte 1: escribe src/tecnica/impresion/sectores_datos.ts (la lista de los 36 SEC y el punto de cada etiqueta).

Fuente, una de dos:
  python3 -I scripts/sectores_desde_paso0.py paso0.json          el JSON de la fila «01_sectores» del paso 0 corrido en producción (una lista)
  python3 -I scripts/sectores_desde_paso0.py --local <base>      la base local (clúster 55432) con la carga del Plan Maestro (solo para trabajar
                                                                 mientras llega el paso 0; el archivo dice de dónde salió)
Comprueba: 7 sectores y 29 subsectores, cada nombre se lee («Sector N», «Subsector N.M») y, si el paso 0 lo trae, que el sector del atributo
(atributos->'modelo'->>'sector') coincide con el del nombre. Si algo no cuadra, se detiene sin escribir."""
import json
import os
import re
import subprocess
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SALIDA = os.path.join(RAIZ, "src", "tecnica", "impresion", "sectores_datos.ts")
CONSULTA = """select coalesce(jsonb_agg(jsonb_build_object('codigo', v.codigo, 'nombre', v.nombre, 'clase', v.clase, 'sector_atributo', v.atributos -> 'modelo' ->> 'sector',
  'lon_etiqueta', round(ST_X(ST_PointOnSurface(v.geom))::numeric, 6), 'lat_etiqueta', round(ST_Y(ST_PointOnSurface(v.geom))::numeric, 6)) order by v.clase, v.nombre), '[]')
  from redes.v_activo_vigente v where v.prefijo = 'SEC'"""


def leer(argv):
    if len(argv) == 3 and argv[1] == "--local":
        env = dict(os.environ, PGHOST="localhost", PGPORT="55432", PGUSER="postgres")
        out = subprocess.run(["/opt/homebrew/opt/postgresql@17/bin/psql", "-AtX", "-d", argv[2], "-c", CONSULTA], env=env, check=True, capture_output=True, text=True).stdout
        return json.loads(out), f"base LOCAL {argv[2]} (carga del Plan Maestro; reemplazar por el paso 0 de producción)"
    if len(argv) == 2 and not argv[1].startswith("-"):
        with open(argv[1], encoding="utf-8") as f:
            d = json.load(f)
        if isinstance(d, dict):
            d = d.get("01_sectores") or d.get("dato")
        return d, f"paso 0 de producción ({os.path.basename(argv[1])})"
    sys.exit(__doc__)


def main():
    filas, origen = leer(sys.argv)
    if not isinstance(filas, list):
        sys.exit("El JSON no es la lista de sectores")
    datos, malos = [], []
    for f in filas:
        n = re.sub(r"\s+", " ", str(f.get("nombre") or "")).strip()
        m = re.fullmatch(r"Subsector (\d{1,2})\.(\d{1,2})", n, re.I) or re.fullmatch(r"Sector (\d{1,2})", n, re.I)
        clase = f.get("clase")
        if not m or clase not in ("sector", "subsector") or (clase == "subsector") != n.lower().startswith("subsector"):
            malos.append(f"{f.get('codigo')}: «{n}» ({clase})")
            continue
        # 26-nov (David): el sector sale del atributo (atributos->'modelo'->>'sector', 0 vacíos en producción); el nombre queda como comprobación cruzada
        attr = str(f.get("sector_atributo") or "").strip()
        if not re.fullmatch(r"\d{1,2}", attr):
            malos.append(f"{f.get('codigo')}: sin sector en el atributo ({attr!r})")
            continue
        sector = str(int(attr))
        if str(int(m.group(1))) != sector:
            malos.append(f"{f.get('codigo')}: el nombre dice sector {int(m.group(1))} y el atributo {attr}")
        sub = f"{int(m.group(1))}.{int(m.group(2))}" if clase == "subsector" else None
        datos.append({"codigo": f["codigo"], "nombre": n, "clase": clase, "sector": sector, "sub": sub, "lon": float(f["lon_etiqueta"]), "lat": float(f["lat_etiqueta"])})
    n_sec = sum(1 for d in datos if d["clase"] == "sector")
    n_sub = len(datos) - n_sec
    if malos or n_sec != 7 or n_sub != 29:
        sys.exit("No se escribe: " + "; ".join(malos + [f"{n_sec} sectores y {n_sub} subsectores (se esperan 7 y 29)"]))
    datos.sort(key=lambda d: (d["clase"] != "sector", [int(x) for x in re.findall(r"\d+", d["nombre"])]))
    lineas = ",\n".join(f"  {{ codigo: {json.dumps(d['codigo'])}, nombre: {json.dumps(d['nombre'], ensure_ascii=False)}, clase: \"{d['clase']}\", sector: {json.dumps(d['sector'])}, sub: {json.dumps(d['sub'])}, lon: {d['lon']}, lat: {d['lat']} }}" for d in datos)
    with open(SALIDA, "w", encoding="utf-8") as f:
        f.write(f"""// GENERADO por scripts/sectores_desde_paso0.py — no editar a mano. Origen: {origen}.
// Los 36 SEC (7 sectores y 29 subsectores, Plan Maestro 2014, Anexo C): el sector sale de atributos->'modelo'->>'sector' (comprobado contra el nombre)
// y el punto de cada etiqueta es ST_PointOnSurface.
export type SectorDato = {{ codigo: string; nombre: string; clase: "sector" | "subsector"; sector: string; sub: string | null; lon: number; lat: number }};
export const ORIGEN_SECTORES = {json.dumps(origen, ensure_ascii=False)};
export const SECTORES_DATOS: SectorDato[] = [
{lineas},
];
""")
    print(f"escrito {SALIDA}: {n_sec} sectores y {n_sub} subsectores · {origen}")


if __name__ == "__main__":
    main()
