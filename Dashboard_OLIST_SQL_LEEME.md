# Dashboard conectado a OLIST_DW

Abrir `Dashboard_OLIST_SQL.pbip`, conservando las carpetas `Dashboard_OLIST_SQL.Report` y `Dashboard_SQL.SemanticModel` al lado. El modelo y la caché provienen del reporte que el usuario cargó desde SQL Server. El reporte original guardado como `Proyecto final anomalias.pbix` se conserva.

Páginas: **Resumen**, **Explorar órdenes**, **Perfiles de anomalía**, **Importes y logística**. Los filtros y gráficos de las tres primeras usan `gold.order_anomaly_scoring`. La última página analiza todas las órdenes de `gold.order_anomaly_features` y se identifica como tal: no presupone que ambas tablas ya tengan una relación configurada en el modelo.

El reporte reutiliza los resultados persistidos en SQL, que pueden diferir de la ejecución CSV anterior. Las sumas de anomaly_if/anomaly_lof cuentan órdenes marcadas; el recuento de order_id cuenta registros del scoring. Es necesario mantener una fila por orden en la tabla.

Comprobación en Power BI Desktop: las cuatro páginas cargaron datos. El resumen mostró 1.989 detecciones por modelo y 383 por consenso, frente a las 459 del CSV anterior. Se probó y restauró el filtro de consenso en la tabla. La página de perfiles se limita a ALTA/MEDIA para no presentar el perfil genérico de órdenes no marcadas como anomalía.

Seleccionar **Actualizar** en Power BI para volver a leer la base mediante la conexión existente. No se ejecutan INSERT, UPDATE, DELETE ni DROP. No se ha publicado en el servicio.

Las vistas nativas incluyen perfil_anomalia y nivel_rareza existentes en SQL. El gráfico de perfiles agrupa combinaciones completas de perfiles, no cuenta cada etiqueta por separado.
