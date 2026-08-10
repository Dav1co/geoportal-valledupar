# Diseño: refresco INCREMENTAL por período

**Estado: PROPUESTO — no construido.** Requiere aprobación (convierte objetos
existentes y toca el script de cargue).

## El límite que obliga al cambio

**Postgres no permite refrescar parcialmente una vista materializada.**
`REFRESH MATERIALIZED VIEW` rehace siempre el contenido completo; no existe
`REFRESH … WHERE periodo = …`, ni se pueden particionar. Mientras las
preagregadas de detalle sean materializadas, cargar un mes obliga a recalcular
los seis retenidos.

Por eso la única vía real es **convertirlas en tablas** y recalcular por
período con `delete + insert` dentro de una transacción.

## Qué se convierte y qué no

| Objeto | Hoy | Propuesta | Por qué |
|---|---|---|---|
| `v_fact_detalle_dim` | matview 254 s | **tabla, 43 s/período** | detalle, 6 períodos |
| `v_recaudo_detalle_dim` | matview ~250 s | **tabla, ~40 s/período** | detalle, 6 períodos |
| `v_recaudo_diario_cierre` | matview ~250 s | **tabla, ~40 s/período** | detalle, 6 períodos |
| `v_cartera_detalle_dim` | matview ~200 s | **tabla, ~35 s/período** | detalle, 6 períodos |
| `v_cartera_contratos_dim` | matview ~50 s | **tabla, ~10 s/período** | detalle, 6 períodos |
| `v_kpi_mes` | matview 4 s | **se queda igual** | histórica (43 períodos) y ya es barata |
| `v_tarifa_referencia` | matview 40 s | **se queda igual** | solo calcula el ancla, no acumula |

**Los nombres no cambian**: pasan de vista materializada a tabla con el mismo
nombre y las mismas columnas, así que **el RPC, la Edge Function y el frontend
no se tocan**. Los índices se recrean igual (el único distinto a `create index`
sería que ya no hace falta el índice único "para CONCURRENTLY", pero conviene
conservarlo como clave natural y para el planificador).

## Cómo queda el recálculo

Una función por tabla, todas con la misma forma:

```sql
create or replace function bi.recalcular_fact_detalle_dim(p_periodo text)
returns integer
language plpgsql
as $$
declare
  n integer;
begin
  delete from bi.v_fact_detalle_dim where periodo = p_periodo;
  insert into bi.v_fact_detalle_dim
  select … from bi_interno.v_facturacion_contratos
  where periodo = p_periodo
  group by …;
  get diagnostics n = row_count;
  return n;
end $$;
```

Y un despachador único, para que el cargador no tenga que conocer los nombres:

```sql
create or replace function bi.recalcular(p_tabla text, p_periodo text)
returns integer …   -- CASE cerrado sobre las 5 tablas, sin SQL dinámico
```

**Atomicidad:** `delete + insert` corren en una sola transacción, así que quien
consulte durante el recálculo sigue viendo la versión anterior por MVCC — la
misma garantía que daba `REFRESH … CONCURRENTLY`, sin necesitar el índice
único. En ningún momento el período queda a medias.

**Bloat:** un `delete+insert` mensual sobre tablas de 2.700–33.000 filas es
despreciable; con el autovacuum por defecto basta.

## El cambio en el cargador

`VISTAS_TABLERO` pasa de declarar solo dependencias a declarar también el modo:

```python
VISTAS_TABLERO = {
    # histéricas: refresco completo, son baratas
    "bi.v_kpi_mes":            {"fuentes": {...}, "modo": "completo"},
    "bi.v_tarifa_referencia":  {"fuentes": {"facturacion_contratos"}, "modo": "completo"},
    # detalle: recálculo por período cargado
    "bi.v_fact_detalle_dim":      {"fuentes": {"facturacion_contratos"}, "modo": "periodo"},
    "bi.v_recaudo_detalle_dim":   {"fuentes": {"recaudo_detalle"},       "modo": "periodo"},
    "bi.v_recaudo_diario_cierre": {"fuentes": {"recaudo_detalle"},       "modo": "periodo"},
    "bi.v_cartera_detalle_dim":   {"fuentes": {"cartera_edades"},        "modo": "periodo"},
    "bi.v_cartera_contratos_dim": {"fuentes": {"cartera_contrato"},      "modo": "periodo"},
}
```

y `cargadas` pasa de ser un conjunto de fuentes a un conjunto de pares
`(fuente, período)` — el cargador ya sabe ambos datos en el punto donde hoy
registra el éxito. El bloque final queda:

- modo `completo` → `REFRESH MATERIALIZED VIEW CONCURRENTLY …` (como hoy)
- modo `periodo`  → `select bi.recalcular('<tabla>', '<periodo>')` una vez por
  período cargado de esa fuente

## Cuánto baja

| Escenario | Hoy | Con incremental |
|---|---|---|
| Cargue mensual normal (1 período, todas las fuentes) | **~18 min** | **~3,5 min** |
| `--solo facturacion_agrupado` | 4 s | 4 s |
| `--solo recaudo_detalle` (1 período) | ~8 min | ~1,5 min |
| Recarga histórica de 6 períodos | ~18 min | ~18 min (igual: recalcula los 6) |

El caso principal —el cargue del mes— baja **de ~18 a ~3,5 minutos**, un 80 %.
La medición base es real: recalcular `v_fact_detalle_dim` para un solo período
tarda **43 s** (index scan sobre `ix_fc_periodo`, 1,2 M filas) frente a 254 s
de la vista completa.

## Riesgos y cómo se cubren

1. **Convertir matview → tabla es un DROP + CREATE.** Se hace con las tablas
   pobladas de una vez (`create table … as select …`), así que no hay ventana
   sin datos si se ejecuta en una transacción por objeto. Aun así conviene
   correrlo fuera de horario.
2. **Una tabla puede quedar desincronizada** si alguien carga datos sin pasar
   por el cargador. Mitigación: dejar en cada archivo SQL la consulta de
   reconstrucción total (`select bi.recalcular(tabla, periodo)` en bucle sobre
   los períodos presentes en la fuente), y una verificación que compare
   períodos presentes en la fuente vs en la tabla.
3. **Un período borrado por retención** queda huérfano en la tabla. Se cubre
   añadiendo al recálculo un `delete` de los períodos que ya no existen en la
   fuente — barato y explícito.

## Alternativas descartadas

- **Particionar la materializada**: Postgres no admite particionar vistas
  materializadas.
- **Materializada con `WHERE periodo in (últimos 6)`**: no ayuda, sigue
  rehaciendo todo el contenido en cada refresh.
- **Vistas normales sin materializar**: la consulta en vivo tarda 43 s; la
  pantalla no puede pagar eso por visita.
