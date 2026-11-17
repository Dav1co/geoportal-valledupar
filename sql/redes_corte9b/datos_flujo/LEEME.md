# Corte 9b · Fase 0 — datos del modelo (sin funciones de redes)
Copia de `paquete_fase1/corte9b/datos/`. Se rehacen con el entorno `regulatorio/analisis_plan_maestro/.venv_epanet/` (wntr 1.5.0) y la base local de Code A (solo lectura):
- `flujo_modelo.py <modeloV1.inp> <destino>` → `flujo_modelo_v1.csv` (md5 `2b0b8616697e22427f7019f766de1448`), `horas_modelo_v1.csv`, `amarre_flujo_v1.txt`.
- `segmentos_modelo.py <modeloV1.inp> <destino>` → `segmentos_modelo_v1.csv`, `valvulas_criticidad_v1.csv`, `segmentos_v1.txt`.
Entrada: `salida_geoportal/modelo_hidraulico/epanet_exportado/acueducto_existente_validado_modeloV1.inp` (md5 `2f86a1313d20e42117ab39bbc008997e`). La carga a la base es de la Fase 3.
