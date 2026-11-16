# Corte 9a — Integración del Plan Maestro 2014 (paquete SQL y carga)

El detalle (qué se hizo, decisiones, pruebas, orden de publicación y preguntas) está en `~/geoportal-consultas/tecnica/paquete_fase1/corte9a/ENTRADA_BITACORA.md`.

- **Parte de:** el 7a publicado (conjunto de funciones de redes `79f184a4fe37ed2baa67dac7f3dd9b3c`). **Deja:** la huella que dice `huellas_solo_lectura_redes_corte9a_editor.sql`.
- **Orden:** huellas → ensayo (ERROR esperado, «N de N … SIN FALLAS») → migración → verificación → huellas; después, la carga por psql desde `carga_pm/generado/`:
  `ensayo_carga_pm.sql` (ERROR esperado) → `carga_pm_todo.sql` → revisar los dos resúmenes → `publicar_pm.sql` → `verificacion_carga_pm.sql`.
- **Para regenerar sobre otra huella de producción:** rehacer la plantilla local con esa base y correr `MD5_BASE=<huella> python3 -I pruebas_locales/generar.py`; luego `python3 -I pruebas_locales/correr_local.py`.
- **Para regenerar la carga** (si cambia `regulatorio/salida_geoportal/`): `python3 -I carga_pm/carga_pm.py`. `generado/partes/10_referencia.sql` (17 MB) no va en git; va en la carpeta de entrega.
- **Base local:** clúster propio de Code B (puerto 55442, bases `emdupar_b*`); `pruebas_locales/rehacer_base.sh` se niega a tocar el puerto 55432 (Code A).
