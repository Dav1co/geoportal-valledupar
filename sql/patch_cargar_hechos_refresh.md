# Refresco del tablero en cargar_hechos.py — SELECTIVO + INCREMENTAL

**Script objetivo:** `~/etl-emdupar/cargar_hechos.py`.
**Estado:** PROPUESTO — pendiente de aprobación (es script de cargue).
**Reemplaza** el bloque selectivo actual, que refresca vistas completas.

## Qué cambia respecto a lo que hay hoy

Hoy `VISTAS_TABLERO` es `{vista: {fuentes}}` y todo se refresca con
`REFRESH MATERIALIZED VIEW CONCURRENTLY`, es decir, entero.

Tras la conversión de 14_incremental.sql, **cinco de las siete son tablas** con
función de recálculo por período. El cargador debe distinguir los dos modos y,
para las de detalle, recalcular **solo los períodos que cargó**.

## 1. Declaración (reemplaza el `VISTAS_TABLERO` actual)

```python
# =====================================================================
# VISTAS DEL TABLERO (esquema bi): de qué FUENTES depende cada una y
# CÓMO se actualiza.
#   modo "completo" -> REFRESH MATERIALIZED VIEW CONCURRENTLY (histórica
#                      y barata: rehacerla entera no duele)
#   modo "periodo"  -> bi.recalcular(tabla, periodo) SOLO para los
#                      períodos cargados en esta corrida
# Al agregar una preagregada nueva, declararla aqui. Es el unico sitio.
# =====================================================================
VISTAS_TABLERO = {
    "bi.v_kpi_mes": {
        "fuentes": {"facturacion_agrupado", "recaudo_agrupado", "cartera_resumen",
                    "notas", "facturacion_contratos", "cartera_contrato"},
        "modo": "completo",
    },
    "bi.v_tarifa_referencia": {
        "fuentes": {"facturacion_contratos"}, "modo": "completo",
    },
    "bi.v_fact_detalle_dim": {
        "fuentes": {"facturacion_contratos"}, "modo": "periodo",
    },
    "bi.v_recaudo_diario_cierre": {
        "fuentes": {"recaudo_detalle"}, "modo": "periodo",
    },
    "bi.v_recaudo_detalle_dim": {
        "fuentes": {"recaudo_detalle"}, "modo": "periodo",
    },
    "bi.v_cartera_detalle_dim": {
        "fuentes": {"cartera_edades"}, "modo": "periodo",
    },
    "bi.v_cartera_contratos_dim": {
        "fuentes": {"cartera_contrato"}, "modo": "periodo",
    },
}
```

## 2. `cargadas` pasa de fuentes a pares (fuente, período)

En `procesar_periodo`, donde hoy se registra el éxito:

```python
                if cargadas is not None:
                    cargadas.add((clave, periodo))       # antes: cargadas.add(clave)
```

Es el único cambio en esa función; `periodo` ya está disponible ahí.

## 3. El bloque de refresco (reemplaza al actual)

```python
    # Refresco del tablero: SELECTIVO por fuente e INCREMENTAL por período.
    # No aplica en corridas que no escriben datos (--plan / --simular).
    if not args.sin_refresh and not args.plan and not args.simular:
        fuentes_cargadas = {f for f, _p in cargadas}
        pendientes = {v: cfg for v, cfg in VISTAS_TABLERO.items()
                      if cfg["fuentes"] & fuentes_cargadas}
        omitidas = sorted(set(VISTAS_TABLERO) - set(pendientes))

        if not cargadas:
            print("\nNingun cargue efectivo: no hay vistas que refrescar.")
        elif "geoportal" not in motores:
            print("\n[aviso] destino geoportal no conectado: quedan sin refrescar: "
                  + ", ".join(sorted(pendientes)))
            print("        reconstruccion manual: ver sql/14_incremental.sql")
        else:
            motor_geo, _fuentes = motores["geoportal"]
            print(f"\nActualizando {len(pendientes)} vista(s) del tablero "
                  f"(fuentes cargadas: {', '.join(sorted(fuentes_cargadas))})...")
            if omitidas:
                print(f"  omitidas por no depender de lo cargado: {', '.join(omitidas)}")

            for vista, cfg in sorted(pendientes.items()):
                t0 = time.time()
                try:
                    # AUTOCOMMIT: REFRESH ... CONCURRENTLY no corre en transaccion.
                    with motor_geo.connect().execution_options(
                            isolation_level="AUTOCOMMIT") as cx:
                        if cfg["modo"] == "completo":
                            cx.execute(text(
                                f"REFRESH MATERIALIZED VIEW CONCURRENTLY {vista}"))
                            print(f"  [ok] {vista} refrescada completa ({time.time()-t0:.0f}s)")
                        else:
                            # Solo los periodos de ESTA corrida cuya fuente
                            # alimenta esta vista: recalcular meses que no
                            # cambiaron es trabajo desperdiciado.
                            periodos = sorted({p for f, p in cargadas if f in cfg["fuentes"]})
                            total = 0
                            for p in periodos:
                                r = cx.execute(text(
                                    "select bi.recalcular(:t, :p)"),
                                    {"t": vista, "p": p}).scalar()
                                total += r or 0
                            print(f"  [ok] {vista}: {len(periodos)} periodo(s) "
                                  f"{', '.join(periodos)} -> {total:,} filas "
                                  f"({time.time()-t0:.0f}s)")
                except Exception as e:
                    print(f"  [x] {vista}: fallo la actualizacion: {e}")
                    print(f"      reconstruccion manual: ver sql/14_incremental.sql")
```

## Tiempos MEDIDOS (no estimados)

Recálculo de **un** período, contra el refresco completo de la misma:

| Vista | Completa | 1 período | Ahorro |
|---|---|---|---|
| `v_fact_detalle_dim` | 254 s | **52 s** | 80 % |
| `v_recaudo_detalle_dim` | ~250 s | **41 s** | 84 % |
| `v_recaudo_diario_cierre` | ~250 s | **34 s** | 86 % |
| `v_cartera_detalle_dim` | ~200 s | **31 s** | 85 % |
| `v_cartera_contratos_dim` | ~50 s | **5 s** | 90 % |
| **Subtotal detalle** | **~17 min** | **2,7 min** | |
| `v_kpi_mes` + `v_tarifa_referencia` (completas) | 44 s | 44 s | — |
| **TOTAL cargue mensual** | **~18 min** | **~3,5 min** | **80 %** |

## Verificado tras la conversión y el recálculo

Las cifras no se movieron **ni un centavo**: cartera `118.840.448.654,36`,
facturado `5.983.961.190,61`, recaudo `5.022.724.833`, suscriptores `111.579`
y `110.039`, y los conteos de filas idénticos (33.320 / 181 / 13.414 / 16.100 /
2.759). La verificación de sincronía fuente-vs-tabla devuelve cero filas.
