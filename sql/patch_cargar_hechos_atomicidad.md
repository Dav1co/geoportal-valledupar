# Patch propuesto: atomicidad de borrar_periodo + insertar

**Script objetivo:** `~/etl-emdupar/cargar_hechos.py`
**Estado:** PROPUESTO — pendiente de aprobación explícita de David.
**Origen:** hallazgo #3 de la auditoría del 2026-08-11.

## El daño, que no es hipotético

`carga_log` id 697: `202607 / cartera_contrato`, estado `error`, **0 filas**,
2026-08-08 16:27. El id 698 lo repone a las 17:23. **57 minutos con el
período borrado y vacío en producción.** El detalle del error apunta a
`insertar`. Lo mismo el 2026-08-08 00:49 con `facturacion_contratos/202605`.

El agravante: `bi.v_kpi_mes` es de modo `completo` y depende de
`cartera_contrato`. Si en la misma corrida otra de sus fuentes sí carga,
el refresco se dispara y reconstruye el KPI **leyendo la tabla vacía**.

## Las cuatro preguntas, respondidas con prueba

### 1. ¿`df.to_sql` puede compartir transacción? SÍ, probado.

pandas 2.1.4 / SQLAlchemy 2.0.25. Pasando una `Connection` en vez del
`Engine`, `to_sql` se une a la transacción abierta:

```
PRUEBA: delete + to_sql dentro de un with motor.begin(), con fallo forzado
  filas previas:      1
  tras borrar:        0
  tras insertar:      3
  excepcion: fallo simulado
  la tabla tras el rollback: NO EXISTE -> todo revertido
```

Contraprueba con el patrón actual (dos `motor.begin()` separados):

```
  excepcion: fallo simulado justo despues del delete
  filas que quedan: 0  <- el periodo quedo BORRADO Y VACIO
```

### 2. Archivos partidos `_1`/`_2`: la transacción abarca la fuente entera

Hoy el `delete` va dentro del bucle de partes, gobernado por
`primera_parte[n]`. Si `_1` falla **después** del delete, `primera_parte`
ya quedó en `False`, así que `_2` inserta **sin borrar**: el período
termina con media carga y marcado OK.

La transacción debe envolver **todas las partes de la fuente**, no cada
parte. Se invierte el anidamiento: primero el destino, luego una
transacción, y dentro el bucle de partes.

Coste: la transacción queda abierta mientras se leen los Excel de las
partes siguientes (decenas de segundos en `facturacion_contratos`). Es
aceptable porque el `DELETE`/`INSERT` toma **ROW EXCLUSIVE**, que bloquea
a otros escritores pero **no a los lectores**; y el único escritor posible
es otro cargue, que no debe correr en paralelo.

Nota para el futuro: `DESTINOS` tiene hoy un solo destino activo. Con dos
o más habría que abrir una transacción por destino con `ExitStack`.

### 3. `asegurar_tabla` (DDL) se queda FUERA de la transacción

Podría ir dentro —el DDL de Postgres es transaccional— pero **no debe**:
`ALTER TABLE ADD COLUMN` toma **ACCESS EXCLUSIVE**, que bloquea incluso
los `SELECT`. Mantenerlo dentro dejaría la tabla ilegible durante todo el
insert, que en `facturacion_contratos` son minutos.

Fuera es además seguro: es idempotente (`IF NOT EXISTS`, y solo agrega
columnas), y si falla no ha destruido nada todavía.

### 4. Una fuente fallida ya no habilita el refresco

Hoy `cargadas.add((clave, periodo))` ocurre por archivo, y
`resumen[clave]` se sobrescribe en cada vuelta: si `_1` falla y `_2`
funciona, el resumen dice **OK** y el refresco corre sobre media carga.

Se cambia a: la fuente entra en `cargadas` **solo si todas sus partes
terminaron bien**, y el estado ERROR es pegajoso.

## El diff

### a) `borrar_periodo` e `insertar` reciben la conexión, no el motor

```diff
-def borrar_periodo(motor, tabla: str, periodo: str):
-    with motor.begin() as cx:
-        existe = cx.execute(text(
-            "SELECT 1 FROM information_schema.tables WHERE table_schema=:e AND table_name=:t"),
-            {"e": ESQUEMA, "t": tabla}).fetchone()
-        if existe:
-            cx.execute(text(f'DELETE FROM {ESQUEMA}."{tabla}" WHERE periodo = :p'), {"p": periodo})
+def borrar_periodo(cx, tabla: str, periodo: str):
+    """Borra el periodo DENTRO de la transaccion que abre quien llama.
+    Recibe una Connection, no un Engine: el borrado y la insercion tienen
+    que confirmarse juntos o revertirse juntos."""
+    existe = cx.execute(text(
+        "SELECT 1 FROM information_schema.tables WHERE table_schema=:e AND table_name=:t"),
+        {"e": ESQUEMA, "t": tabla}).fetchone()
+    if existe:
+        cx.execute(text(f'DELETE FROM {ESQUEMA}."{tabla}" WHERE periodo = :p'), {"p": periodo})
```

```diff
-def insertar(motor, tabla: str, df: pd.DataFrame):
+def insertar(cx, tabla: str, df: pd.DataFrame):
+    """Inserta DENTRO de la transaccion de quien llama. pandas acepta una
+    Connection en `con` y se une a su transaccion (verificado con pandas
+    2.1.4 / SQLAlchemy 2.0.25)."""
     df2 = df.copy()
     for c in df2.columns:
         df2[c] = df2[c].apply(
             lambda v: None if pd.isna(v)
             else (v.isoformat(sep=" ") if hasattr(v, "isoformat") else str(v)))
         df2[c] = df2[c].astype(object).where(df2[c].notna(), None)
-    df2.to_sql(tabla, motor, schema=ESQUEMA, if_exists="append",
+    df2.to_sql(tabla, cx, schema=ESQUEMA, if_exists="append",
                index=False, chunksize=LOTE, method="multi")
```

### b) El bucle de `procesar_periodo`: destino fuera, partes dentro

Se invierte el anidamiento. Antes: `for parte → for destino → delete/insert`.
Ahora: `for destino → transaccion → for parte → delete una vez + insert`.

```diff
-        primera_parte = {n: True for n in destinos}
-        total_filas = 0
-        for ruta in sorted(candidatos):  # soporta _1, _2 (archivos partidos)
-            try:
-                df = leer_excel(ruta, fuente["hoja"])
-                df, ignoradas, faltantes = mapear_columnas(df, fuente)
-                ...
-                else:
-                    for n, m in destinos.items():
-                        asegurar_tabla(m, fuente["tabla"], df)
-                        if primera_parte[n]:
-                            borrar_periodo(m, fuente["tabla"], periodo)
-                            primera_parte[n] = False
-                        insertar(m, fuente["tabla"], df)
-                ...
-                resumen[clave] = f"OK ({total_filas:,} filas -> {nombres_dest})"
-                if cargadas is not None:
-                    cargadas.add((clave, periodo))
-            except Exception as e:
-                resumen[clave] = "ERROR"
+        total_filas = 0
+        fuente_ok = True     # se apaga en el primer fallo y no se vuelve a encender
+
+        for n, m in destinos.items():
+            if not fuente_ok:
+                break
+            try:
+                # UNA transaccion para TODA la fuente: el borrado del periodo
+                # y la insercion de todas sus partes se confirman juntos.
+                with m.begin() as cx:
+                    borrado = False
+                    for ruta in sorted(candidatos):   # _1, _2 ...
+                        df = leer_excel(ruta, fuente["hoja"])
+                        df, ignoradas, faltantes = mapear_columnas(df, fuente)
+
+                        if faltantes:
+                            # Cuarentena: se aborta la fuente ENTERA. Antes se
+                            # hacia `continue` y las demas partes entraban,
+                            # dejando el periodo incompleto y marcado OK.
+                            raise Cuarentena(ruta.name, ignoradas, faltantes)
+
+                        df["periodo"] = periodo
+                        df["archivo_origen"] = ruta.name
+                        df["fecha_carga"] = datetime.now()
+
+                        if simular:
+                            print(f"  [simulacion] {ruta.name}: {len(df):,} filas ...")
+                            continue
+
+                        # El DDL va FUERA de la transaccion a proposito:
+                        # ALTER TABLE toma ACCESS EXCLUSIVE y bloquearia
+                        # hasta los SELECT durante todo el insert.
+                        asegurar_tabla(m, fuente["tabla"], df)
+
+                        if not borrado:
+                            borrar_periodo(cx, fuente["tabla"], periodo)
+                            borrado = True
+                        insertar(cx, fuente["tabla"], df)
+
+                        total_filas += len(df)
+                        partes_ok.append((ruta.name, len(df), ignoradas))
+                # aqui la transaccion ya hizo commit: la fuente esta completa
+            except Exception as e:
+                fuente_ok = False
+                ...
+
+        if fuente_ok and not simular:
+            resumen[clave] = f"OK ({total_filas:,} filas -> {nombres_dest})"
+            if cargadas is not None:
+                cargadas.add((clave, periodo))   # solo ahora habilita el refresco
```

Nota sobre `asegurar_tabla` dentro del `with`: se llama dentro del bloque
pero **usa `m` (el Engine), no `cx`**, así que abre su propia conexión y
confirma aparte. Es deliberado, por el motivo del punto 3.

## Qué NO cambia

- El comportamiento en el camino feliz es idéntico: mismas filas, mismo
  orden, mismos registros en `carga_log`.
- `--plan` y `--simular` siguen sin escribir.
- El refresco selectivo por `VISTAS_TABLERO` no se toca; solo deja de
  dispararse cuando la fuente quedó a medias.
- Ninguna otra fuente, ninguna vista, ninguna tabla.

## Verificación propuesta tras aplicar

1. `python3 -m py_compile cargar_hechos.py`
2. `--plan` en 202607: debe listar lo mismo que hoy.
3. Prueba de fallo real sobre una tabla de juguete: cargar, forzar un
   error en el insert y comprobar que el período conserva sus filas.
4. Cargue real de una fuente chica (`facturacion_agrupado`, 130 filas) y
   comparar el conteo antes/después.
5. Respaldo previo: `cp cargar_hechos.py cargar_hechos.py.bak_atomicidad`.
