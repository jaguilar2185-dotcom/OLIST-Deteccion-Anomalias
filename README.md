# OLIST — versión del archivo Minería Datos.rar

Este repositorio fue actualizado con los archivos proporcionados en `Minería Datos.rar`. Esta versión sustituye al paquete anterior; el historial de Git conserva la entrega previa.

## Archivos principales

- `Proyecto original.sql`: SQL original del archivo recibido.
- `Proyecto final`: segunda versión SQL incluida, conservada con su nombre original sin extensión.
- `Proyecto mineria original.py`: implementación original de Python.
- `auditar_y_puntuar.py`: alternativa que lee Gold y exporta resultados locales; no escribe en SQL.
- `Dashboard_OLIST_SQL.pbip`: informe conectado al modelo `Dashboard_SQL.SemanticModel`; conservar las carpetas junto al archivo.
- `Dashboard_SQL.pbip`: segundo proyecto SQL incluido.
- `PowerBI_OLIST/OLIST.pbip`: proyecto alternativo basado en CSV. Sus instrucciones están en `PowerBI_OLIST/LEEME.md`.
- `resultados/`: metadatos, sensibilidad, estabilidad y Top 20 incluidos en el archivo recibido. Son resultados de esa ejecución, no una ejecución nueva de esta actualización.

## Requisitos y uso

SQL Server con `OLIST_DW`, ODBC Driver 17 for SQL Server, Python con numpy, pandas, pyodbc y scikit-learn, y Power BI Desktop compatible con PBIP.

```powershell
python -m pip install -r requirements.txt
python auditar_y_puntuar.py --server TU_SERVIDOR --output resultados
```

El análisis presupone `gold.order_anomaly_features` existente. La conexión SQL de los proyectos recibidos apunta al servidor `JUAN`: ajustarla en Power Query o en la configuración del origen. No se incluyen contraseñas.

Para usar el proyecto CSV, generar primero los resultados y ajustar `CarpetaResultados` en Power BI. El scoring completo no se incluye en Git por su tamaño; se genera con el comando anterior. El análisis local no publica automáticamente esos resultados en el dashboard SQL.

Los SQL y el Python original pueden modificar o reconstruir tablas: revisar sus instrucciones antes de ejecutarlos. La actualización del repositorio no ejecutó los análisis ni modificó la base.

## Archivos excluidos de la carga

Se omitieron dependencias instaladas, cachés `.pbi`, bytecode, metadatos `.platform`, esquemas auxiliares de validación, la carpeta `outputs/` y los archivos mayores de 5 MB (`resultados/order_anomaly_scoring.csv` y `resultados/reporte_input.json`). El Excel y sus exportaciones siguen disponibles en el RAR original. No se alteraron los archivos fuente recibidos, salvo la actualización del `.gitignore`; se añadieron este README y `requirements.txt`.

La generación Excel del archivo recibido depende de un entorno específico y llama a `preparar_reporte.py`, que no viene incluido en el RAR; por ello no se presenta como ejecutable desde una instalación nueva.

Una anomalía indica un caso para revisión, no fraude confirmado. Consulta también `Dashboard_OLIST_SQL_LEEME.md`, `Diagnostico_OLIST.md` y `PowerBI_OLIST/LEEME.md` para conocer el alcance de cada variante; esos documentos se conservan tal como venían en el archivo y pueden describir versiones históricas.
