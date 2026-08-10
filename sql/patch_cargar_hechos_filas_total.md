# Patch propuesto: descartar filas de TOTAL sin etiqueta

**Script objetivo:** `~/etl-emdupar/cargar_hechos.py`.
**Estado:** PROPUESTO — pendiente de aprobación (es script de cargue).
**No urgente:** con la Capa 1 corregida las cifras ya salen bien; esto limpia
el ORIGEN para que el problema no vuelva con períodos nuevos.

## El problema

Los archivos de `FACTURACION_PERIODO_AGRUPADO` de 202309, 202310 y 202311
traen al final una fila con la suma de todo lo facturado, **sin la palabra
"TOTAL"**: concepto, año y mes vienen vacíos y solo está el valor.

El cargador ya descarta filas de total, pero solo las que se identifican:

```python
    # descarta filas de totales al final
    if len(df) and df.iloc[:, 0].astype(str).str.upper().str.startswith("TOTAL").any():
        df = df[~df.iloc[:, 0].astype(str).str.upper().str.startswith("TOTAL")]
```

Esa condición mira la **primera columna** y exige que empiece por "TOTAL".
En estos archivos la primera columna está vacía, así que la fila pasa.

Efecto: sumaba ~5.400 M por mes y **duplicaba la facturación** de esos tres
meses (10.852 M contra los ~5.100 M reales), hundiendo el % de recaudo de 2023
de 78,6 % a 62,5 %.

## El cambio

En `_leer_con()`, justo después del descarte actual de filas "TOTAL":

```python
    # Filas de TOTAL sin etiqueta: algunos archivos traen la suma al final
    # con las columnas de identificacion vacias y solo el valor. Una fila
    # sin NINGUNA columna de texto con contenido no es un registro: es un
    # total. Verificado en FACTURACION_PERIODO_AGRUPADO 202309/10/11.
    if len(df):
        texto = df.select_dtypes(include=["object"])
        if len(texto.columns):
            sin_texto = texto.apply(
                lambda fila: fila.astype(str).str.strip().isin(["", "nan", "None"]).all(),
                axis=1,
            )
            if sin_texto.any():
                print(f"    [aviso] {int(sin_texto.sum())} fila(s) sin datos de texto "
                      f"descartadas (probable fila de totales)")
                df = df[~sin_texto]
```

**Por qué esta regla y no adivinar la forma del total:** una fila de datos real
siempre trae al menos un campo de texto con contenido — el concepto, el
nombre, la causal, el contrato. Una fila donde *todas* las columnas de texto
están vacías y solo hay números no es un registro; es un total. Es la misma
lógica que ya aplica la Capa 1 ("un concepto sin número no es un concepto"),
solo que aplicada en el origen y de forma genérica para todas las fuentes.

El `print` deja rastro en el log del cargue: si algún archivo empieza a perder
filas legítimas, se ve de inmediato en vez de descubrirse meses después.

## Alcance verificado

Búsqueda amplia sobre las tres fuentes agrupadas, no solo por concepto vacío
sino por **participación en el total** (una fila que pese ≥ 40 % del período es
sospechosa de ser la suma):

| Fuente | Hallazgo |
|---|---|
| `facturacion_agrupado` | **3 filas** — 202309, 202310, 202311, cada una exactamente el **50,0 %** del período: la firma inequívoca de una fila de total que duplica el mes |
| `recaudo_agrupado` | Solo "SERVICIO ALCANTARILLADO" con 40–41 % en tres meses de 2024 — **es un concepto legítimo**, coherente con que alcantarillado sea ~40 % del recaudo. No es fila de total. |
| `cartera_resumen` | **Ninguna** |

Es decir: el problema estaba acotado a esos tres archivos. Pero como el formato
puede repetirse en cualquier entrega futura, el filtro en el cargador es lo que
evita que vuelva a entrar.

## Recarga

**No hace falta recargar los tres períodos de 2023 ahora**: la Capa 1 ya los
excluye y las cifras salen bien. Cuando se toque el cargador por otra razón,
recargarlos deja también el origen limpio:

```bash
python3 cargar_hechos.py --desde 202309 --hasta 202311 \
  --solo facturacion_agrupado --sin-refresh
```
