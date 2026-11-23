-- =====================================================================
-- SCRR · CORTE 2 · 60 — SEMILLA (parámetros, tipos de actividad, anomalías PROVISIONALES y particiones iniciales)
-- =====================================================================
insert into scrr.parametros (clave, valor, autor, motivo)
select x.clave, x.valor::jsonb, 'sistema@emdupar.gov.co', x.motivo
  from (values
    ('lote_filas', '2000', 'Lotes de 2.000 filas (fase 0)'),
    ('tope_filas_archivo', '250000', 'Tope de filas por archivo (cartera completa ~112.000)'),
    ('tope_rechazo_pct', '5', 'Más del 5 % de filas rechazadas impide aplicar'),
    ('carga_pausada', 'false', 'Interruptor para pausar las cargas'),
    ('comodin_contrato', '99999999', 'Comodín real de cartera_suscripcion (no −1)'),
    ('ventana_dias_historial', '10', 'P7 del 22-nov: el historial diario se guarda 10 días (ventana de facturación)'),
    ('retencion_meses_pagos', '13', 'Decisión 3 del 20-nov: pagos 13 meses'),
    ('paso_dias', '7', 'Copia técnica (paso y respaldo) 7 días'),
    ('tope_salidas_suscripcion_pct', '5', 'Si más del 5 % de cartera_suscripcion no viene en el archivo, se exige confirmar con motivo'),
    ('monto_minimo_opciones', '[5000,10000,20000]', 'Embudo del 20-nov: monto mínimo'),
    ('monto_minimo_defecto', '5000', 'Embudo del 20-nov: $ 5.000 por defecto')
  ) as x(clave, valor, motivo);

insert into scrr.tipos_actividad (id, codigo, nombre, actividad_campo, seleccionable, admite_drastico, estado_resultante, orden) values
  (1, 'suspension',          'Suspensión',          'suspension', true,  false, 'suspendido', 1),
  (2, 'corte',               'Corte',               'corte',      true,  true,  'cortado',    2),
  (3, 'gestion_cobro',       'Gestión de cobro',    null,         true,  false, null,         3),
  (4, 'reinstalacion',       'Reinstalación',       'reconexion', false, false, 'activo',     4),
  (5, 'reconexion',          'Reconexión',          'reconexion', false, false, 'activo',     5),
  (6, 'reconexion_drastica', 'Reconexión drástica', 'reconexion', false, false, 'activo',     6);

-- Decisión 9 del 20-nov (los 16 de Acuo, 00040_anomalias_actividad_resultado.sql, más 17 OTRO MEDIDOR). DEFINITIVO (David, 22-nov).
insert into scrr.anomalias (codigo, nombre, provisional, fuente, orden)
select n, x, false, case when n = 17 then 'decisión 9 del 20-nov' else 'Acuo 00040 y decisión 9 del 20-nov' end, n
  from unnest(array['PAGO EFECTUADO','CLIENTE NO PERMITE','USUARIO AGRESIVO','USUARIO ABONO','ACOMETIDA NO VISIBLE','ADULTO MAYOR','MENOR DE EDAD','PREDIO SOLO',
                    'FIRMA','SIGUE SUSPENDIDO','PREDIO ENREJADO','RECLAMO EN TRAMITE','VIGILANTE NO PERMITE','DIRECCION ERRADA','OTROS','SE GESTIONA PAGO','OTRO MEDIDOR'])
       with ordinality as a(x, n);

-- Causas de los contratos con control y de los excluidos manuales (P6 del 22-nov: la misma tabla de eventos, con su causa)
insert into scrr.causas_control (id, codigo, nombre, grupo) values
  (1, 'reclamo_manual', 'Reclamo manual', 'reclamo'),
  (2, 'insolvencia', 'Proceso de insolvencia', 'control'),
  (3, 'minimo_vital', 'Mínimo vital', 'control'),
  (4, 'excluido_manual', 'Excluido manual por el supervisor', 'excluido');

-- Calendario de noviembre de 2026 (sección 3 del encargo del 20-nov): 24 ciclos con pago oportuno y fecha de suspensión. Se pueden agregar más ciclos desde la pantalla.
insert into scrr.calendario_ciclos (periodo, ciclo, pago_oportuno, fecha_suspension, autor) values
  ('202611', 15, '2026-11-12', '2026-11-13', 'sistema@emdupar.gov.co'),
  ('202611', 19, '2026-11-12', '2026-11-13', 'sistema@emdupar.gov.co'),
  ('202611', 21, '2026-11-12', '2026-11-13', 'sistema@emdupar.gov.co'),
  ('202611', 1, '2026-11-13', '2026-11-14', 'sistema@emdupar.gov.co'),
  ('202611', 20, '2026-11-13', '2026-11-14', 'sistema@emdupar.gov.co'),
  ('202611', 2, '2026-11-13', '2026-11-14', 'sistema@emdupar.gov.co'),
  ('202611', 16, '2026-11-13', '2026-11-14', 'sistema@emdupar.gov.co'),
  ('202611', 23, '2026-11-13', '2026-11-14', 'sistema@emdupar.gov.co'),
  ('202611', 22, '2026-11-13', '2026-11-14', 'sistema@emdupar.gov.co'),
  ('202611', 4, '2026-11-17', '2026-11-18', 'sistema@emdupar.gov.co'),
  ('202611', 3, '2026-11-17', '2026-11-18', 'sistema@emdupar.gov.co'),
  ('202611', 5, '2026-11-17', '2026-11-18', 'sistema@emdupar.gov.co'),
  ('202611', 12, '2026-11-18', '2026-11-19', 'sistema@emdupar.gov.co'),
  ('202611', 24, '2026-11-18', '2026-11-19', 'sistema@emdupar.gov.co'),
  ('202611', 6, '2026-11-18', '2026-11-19', 'sistema@emdupar.gov.co'),
  ('202611', 9, '2026-11-18', '2026-11-19', 'sistema@emdupar.gov.co'),
  ('202611', 17, '2026-11-19', '2026-11-20', 'sistema@emdupar.gov.co'),
  ('202611', 18, '2026-11-19', '2026-11-20', 'sistema@emdupar.gov.co'),
  ('202611', 8, '2026-11-19', '2026-11-20', 'sistema@emdupar.gov.co'),
  ('202611', 11, '2026-11-20', '2026-11-21', 'sistema@emdupar.gov.co'),
  ('202611', 7, '2026-11-20', '2026-11-21', 'sistema@emdupar.gov.co'),
  ('202611', 14, '2026-11-23', '2026-11-24', 'sistema@emdupar.gov.co'),
  ('202611', 10, '2026-11-23', '2026-11-24', 'sistema@emdupar.gov.co'),
  ('202611', 13, '2026-11-23', '2026-11-24', 'sistema@emdupar.gov.co');

insert into scrr.codigos_heredados (campo, codigo, significado) values ('estado', 3, 'efectiva'), ('estado', 4, 'inefectiva');

-- Particiones iniciales: historial desde hace 10 días hasta 45 días adelante; pagos desde hace 13 meses hasta 2 meses adelante
select scrr.f_preparar_historial((now() at time zone 'America/Bogota')::date - 10, (now() at time zone 'America/Bogota')::date + 45);
select scrr.f_preparar_pagos((date_trunc('month', now() at time zone 'America/Bogota') - interval '13 months')::date,
                             (date_trunc('month', now() at time zone 'America/Bogota') + interval '2 months')::date);
