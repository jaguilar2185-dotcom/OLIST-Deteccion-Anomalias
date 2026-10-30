# OLIST en Power BI

## Abrir el reporte

1. Instalar Power BI Desktop desde Microsoft si todavía no está disponible: https://www.microsoft.com/power-platform/products/power-bi/desktop
2. Abrir `OLIST.pbip`, conservando las carpetas `OLIST.Report` y `OLIST.SemanticModel` al lado. Es un proyecto editable, no un archivo PBIX ni un reporte ya publicado.
3. Seleccionar **Actualizar** para importar los datos. El proyecto no incluye una caché de Power BI: antes de la primera actualización los visuales pueden estar vacíos.
4. Si se movió la carpeta del proyecto, abrir **Transformar datos > Administrar parámetros** y ajustar `CarpetaResultados` a la carpeta que contiene los cuatro CSV del análisis. El parámetro está configurado para la ubicación actual.
5. Navegar por las pestañas **Resumen**, **Explorar órdenes**, **Top 20** y **Evaluación**. El tema opcional `tema_OLIST.json` puede importarse desde **Vista > Temas**.

El reporte está definido con visuales nativos: tarjetas, gráficos, tablas y segmentadores. No requiere visuales externos. Las vistas de `vistas_previas` son ilustraciones basadas en los CSV reales, no capturas de Power BI ni prueba de una conexión activa.

## Actualización

Ejecutar el análisis `auditar_y_puntuar.py` cuando se necesiten nuevos scores. Después, seleccionar **Actualizar** en Power BI. Power BI importa los resultados; no entrena los modelos ni actualiza por sí mismo los CSV. No es necesario reconstruir el proyecto después de cada análisis.

Las medidas DAX del resumen responden al contexto de filtro. `Top20` es el conjunto de 20 casos de la ejecución, no un ranking dinámico después de filtrar. Las tablas de sensibilidad y estabilidad describen la ejecución completa; no están relacionadas con filtros por orden.

## Conexión opcional a SQL Server

El proyecto principal usa los CSV para funcionar sin crear `gold.order_anomaly_scoring` en SQL Server. No presupone que esa tabla exista ni vuelve a ejecutar los scripts originales.

`conexion_SQL_lectura.pbids` abre una conexión Import a servidor `JUAN`, base `OLIST_DW`. El usuario introduce su autenticación en Power BI; no se guardan contraseñas en el proyecto. Este archivo inicia una conexión, no abre las cuatro páginas del proyecto: para ellas usar `OLIST.pbip`.

`Enriquecer_desde_SQL.pq` contiene una consulta opcional para combinar el scoring local con `gold.order_anomaly_features` mediante `order_id`, conservando todas las órdenes del scoring. En el editor de Power Query del proyecto, crear una consulta en blanco llamada `OrdenesEnriquecidas` y pegar el contenido en el Editor avanzado. Expandir las columnas necesarias y verificar unicidad de `order_id` antes de sustituir los campos de los visuales. La columna anidada evita duplicar filas antes de revisar las relaciones. La consulta se entrega, pero no se ha ejecutado.

Para esa conexión utilizar una cuenta con permiso SELECT. Los archivos no contienen DROP, INSERT ni UPDATE contra la base. Si se quiere sustituir el CSV por `gold.order_anomaly_scoring`, primero hay que verificar existencia, estructura y publicación completa de esa tabla; esta entrega no la crea ni la carga.

## Alcance y comprobación

No se detectó Power BI Desktop en este equipo. Se comprueba la estructura JSON con los esquemas oficiales de Microsoft y las referencias a campos y medidas del modelo. La apertura del proyecto, la evaluación de M y DAX y el refresco en el motor de Power BI requieren verificación en Desktop; la validación de esquemas no los sustituye. El resultado de la comprobación está en `validacion/resultado.json`.

Resultado de esta entrega: **33 documentos validados sin errores de esquema ni referencias de campos ausentes**. Se revisaron visualmente las cuatro vistas previas. Esta comprobación no afirma que Desktop ya haya cargado los datos.

No se publicó el reporte en Power BI Service ni se configuró actualización programada. Para publicar y actualizar fuentes locales en el servicio deben configurarse credenciales y gateway según el entorno.

Fuentes oficiales: [Proyectos Power BI](https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-overview), [carpeta del modelo](https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-dataset), [carpeta del reporte](https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-report), [conexiones y PBIDS](https://learn.microsoft.com/en-us/power-bi/connect-data/desktop-data-sources).
