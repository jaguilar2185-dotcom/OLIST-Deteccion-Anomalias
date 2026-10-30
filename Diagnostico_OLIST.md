# Auditoría estática OLIST_DW

Se revisaron íntegramente los archivos adjuntos y se recuperó el requisito completo del chat anterior. No se ejecutó el SQL, no se entrenaron modelos con la base y no se abrió conexión a SQL Server. El contenido del código demuestra implementación, no ejecución exitosa ni existencia actual de objetos. Las cifras de 99.441 registros son expectativas, no resultados comprobados aquí.

## Hallazgos prioritarios

1. **La tabla solicitada sí está en el SQL.** `Proyecto_original.sql:4145` elimina `gold.order_anomaly_features` y la etapa 10 la reconstruye con `SELECT INTO`. No hay que renombrar `order_anomaly_ml` ni crear una vista que sustituya a la tabla: eso ocultaría la discrepancia entre los adjuntos y el diagnóstico del chat anterior.
2. **Falta una dependencia completa.** Python consulta `gold.order_anomaly_ml` (línea 79) con 13 columnas `z_*` y ocho flags. El SQL entregado no crea ese objeto, sus transformaciones logarítmicas, su imputación ni su estandarización. Ejecutar estos dos adjuntos en una base nueva no completa el flujo. Si el objeto existe en JUAN, procede de un script no incluido y aún debe auditarse.
3. **Scoring está programado, pero es destructivo.** Python, líneas 1516–1638, elimina la tabla existente, confirma el borrado, crea y confirma la tabla y confirma cada lote de inserción. Un fallo deja la tabla perdida, vacía o parcialmente cargada. No es una mera instrucción pendiente: ejecutar el Python original intenta modificar la base automáticamente. No puede inferirse si la tabla existe actualmente.
4. **El SQL completo tampoco es seguro para repetir.** Hay `DROP TABLE` de las seis tablas Silver y de Gold (líneas 166, 650, 1195, 1678, 2039, 2694 y 4145). Además, las claves foráneas creadas en una ejecución previa pueden impedir que se eliminen primero las tablas padre. Conservar Bronze no vuelve inocua la reconstrucción de Silver/Gold.
5. **Falta distancia aproximada.** `vendedor_otro_estado` es un indicador, no kilómetros, y no entra en Python. Los mínimos independientes de estado y código postal del vendedor pueden corresponder a vendedores distintos en una orden. Se requiere geolocalización agregada a una fila por prefijo postal, distancia por par vendedor–cliente y agregación por orden, evitando multiplicar ítems por los múltiples registros de geolocalización.
6. **La estabilidad declarada no está demostrada.** Python 945–1085 cambia contaminación con datos, árboles y semilla iguales. En IF esto cambia el corte/offset, no el ranking de `score_samples`; el Top 20 estable resulta esperado por construcción. Medir sensibilidad del corte por separado de estabilidad ante semillas/remuestreo y vecinos LOF.
7. **Validar no equivale a detener errores.** Python imprime duplicados, NULL e infinitos, pero continúa. Los duplicados pueden llegar a fallar recién en la PK del scoring, después de borrarlo. Las conversiones directas `CAST` de Silver pueden abortar ante valores inválidos; `TRY_CONVERT` puede producir NULL que viola columnas NOT NULL. Deben auditarse conversiones fallidas y conservarse rechazos antes de cargar.
8. **Faltantes confundidos con ceros.** Peso/volumen usan COALESCE a cero; pagos e ítems ausentes también generan ceros. Esto oculta desconocimiento y puede concentrar anomalías en órdenes canceladas/no entregadas. Conservar cobertura física y flags, definir cohorte por estado y distinguir errores de calidad de rareza de negocio. Sumar importes puede ocultar un registro negativo compensado por uno positivo: conservar controles a nivel ítem/pago.
9. **Explicación limitada.** Hay perfiles y Top 20, pero principalmente con z-scores y reglas. Adjuntar valores originales, unidades, referencia de comparación y estado de la orden. Una desviación univariada no es una atribución causal de IF/LOF; el perfil genérico multivariado requiere inspección humana.
10. **Cortes y prioridades requieren fundamento.** El 2% es un presupuesto exploratorio, no una tasa demostrada. MinMax por modelo cumple rango [0,1], pero promediarlo no asegura influencia comparable y puede ser sensible a un máximo LOF extremo. Los intervalos 0.25/0.50/0.75 son arbitrarios. Consenso no significa alta confianza estadística. No confundir el porcentaje de cada modelo con el porcentaje de intersección/unión.

## Contraste contra requisitos

| Requisito | Evidencia en adjuntos / estado |
|---|---|
| Integrar seis tablas | Implementado en Silver/Gold; falta verificar ejecución y resultados |
| Una fila por orden | Ítems y pagos preagregados correctamente; controles de unicidad presentes, falta evidencia de resultados y restricción Gold |
| Montos, freight, ítems, vendedores, pagos, cuotas, ratio, peso/volumen, tiempos | Implementados en Gold, con limitaciones de faltantes y precisión temporal |
| Distancia aproximada | Pendiente; otro estado no la sustituye |
| Log y estandarización documentada | Dependencia ausente del SQL; Python original presupone columnas preparadas |
| Negativos, fechas, duplicados y huérfanos | Consultas presentes en Silver/Gold; no hay resultados adjuntos ni bloqueo integral de carga |
| Tabla order_anomaly_features | Creación explícita presente; existencia real sin verificar |
| Al menos dos métodos | IF y LOF implementados; ejecución sin verificar |
| Contaminación/corte justificado | 2% y escenarios presentes; justificación operativa y estabilidad pendientes |
| Scoring normalizado por order_id | Implementado en Python; persistencia destructiva, resultado sin verificar |
| Top 20 explicados y perfiles | Implementación parcial; completar magnitudes originales y revisión humana |
| Evaluación sin etiquetas | Coincidencia presente; estabilidad deficiente, falta validación documentada con reglas |
| Protocolo de revisión | Priorización por modelos presente; faltan responsables, acciones y cierre |

## Archivos entregados y alcance de la corrección

- `auditar_y_puntuar.py`: reemplazo seguro del flujo de scoring. Lee únicamente `gold.order_anomaly_features`, elimina la dependencia ausente de `order_anomaly_ml`, valida claves y finitud, transforma con log con signo, imputa medianas y estandariza. Registra parámetros. Exporta scoring, Top 20 con valores originales, sensibilidad de umbral, estabilidad por semillas IF/vecinos LOF y metadatos. No contiene DDL ni inserciones y cierra la conexión tras leer. Conviene usar una cuenta con permiso SELECT exclusivamente.
- Usa percentiles empíricos por modelo y su promedio para priorizar dentro de la cohorte; cambia deliberadamente la normalización original. Los empates se promedian. No es probabilidad, no garantiza extremos exactos 0/1 y no es comparable automáticamente entre ejecuciones. El 2% sigue siendo provisional.
- Los tres mayores z-scores son descriptores verificables; no se presentan como explicación causal. Este reemplazo aún no calcula distancia ni recupera faltantes que Gold ya convirtió en cero. No resuelve toda la ingeniería de datos pendiente.
- `scoring_ddl_propuesto_NO_EJECUTADO.sql`: propuesta de creación compatible con el CSV corregido; se detiene si el objeto existe. No reemplaza ni carga registros. El nombre solicitado se conserva. El DDL no se ejecutó.
- Los dos archivos `*_original` son copias de los adjuntos sin correcciones, para trazabilidad. No ejecutar sus bloques de reconstrucción.

## Secuencia pendiente

1. Inspeccionar, con permisos de lectura, existencia y estructura de `gold.order_anomaly_features`, `gold.order_anomaly_ml` y `gold.order_anomaly_scoring`. Obtener recuentos, claves y resultados de controles; no tomar los números del chat como evidencia nueva.
2. Recuperar el script ausente de ML si se conserva ese diseño. Alternativamente usar el reemplazo local, que parte de features y documenta el preprocesamiento. No ejecutar el SQL completo para resolver una sola tabla faltante.
3. Corregir cobertura física y geográfica en una propuesta de transformación separada; documentar cohorte, estados y tratamiento de anomalías de calidad. Los tiempos actuales usan DATEDIFF HOUR/DAY: cuentan fronteras de calendario, no duración fraccionaria exacta.
4. Ejecutar posteriormente el análisis de lectura, revisar CSV/metadata y comparar la carga de revisión al 1%, 2%, 3% y 5%. Agregar comparación del Top 20 entre métodos y reglas con tasas en marcadas/no marcadas; no confundir estas medidas con precisión o recall sin etiquetas.
5. Para publicar scoring en SQL en una fase autorizada: validar el CSV completo, cargar a staging, verificar unicidad, cobertura, rangos y consistencia; publicar en una transacción con rollback ante error, sin borrar primero el resultado vigente. Conservar identificador de ejecución, fecha, versiones de librerías, parámetros y snapshot/fingerprint de entrada. El DDL adjunto solo propone el contrato de la tabla, no implementa esa publicación.
6. Revisar los 20 casos reales y registrar decisión humana. No hay casos ni scores reales calculados en esta auditoría.

## Protocolo operativo propuesto

| Prioridad | Caso y responsable | Acción / evidencia de cierre |
|---|---|---|
| P1 | Importe negativo, diferencia financiera material o secuencia imposible; Finanzas / Calidad | Contrastar comprobantes y fechas, validar corrección; no esperar consenso de modelos |
| P2 | Consenso IF/LOF con alto impacto monetario o logístico; Operaciones | Revisar pedido, entrega, embalaje y cargos; documentar causa y acción |
| P3 | Un solo modelo o combinación rara válida; analista | Revisar contexto, estado y magnitudes; clasificar como válido, error o requiere investigación |

Determinar materialidad financiera con el negocio y capacidad diaria de revisión. Toda decisión debe guardar order_id, ejecución, responsable, evidencia, resolución y fecha. Una anomalía no implica fraude.

## Verificación realizada

Revisión estática de los adjuntos y compilación sintáctica del Python corregido, sin ejecutar su función principal. No se validaron conectividad, dependencias instaladas, rendimiento de LOF ni resultados contra OLIST_DW. No se hicieron cambios en la base.
