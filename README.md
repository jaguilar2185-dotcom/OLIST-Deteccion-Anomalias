# OLIST · Detección de anomalías en órdenes

Proyecto de minería de datos que integra SQL Server, Python y Power BI para identificar órdenes inusuales con Isolation Forest y Local Outlier Factor (LOF), comparar sus detecciones y priorizar la revisión humana.

## Flujo

```text
CSV OLIST → Bronze → Silver → Gold → Python (IF + LOF) → resultados → Power BI
```

SQL prepara las características; Python ejecuta los modelos; Power BI presenta los resultados persistidos en SQL. Una anomalía no implica fraude.

## Contenido

| Archivo o carpeta | Función |
|---|---|
| `sql/Proyecto_solo_etapas.sql` | Preparación y validaciones SQL; conserva solo los encabezados de etapa. |
| `ejecutar_proyecto.py` | Coordina la ejecución a partir de la configuración local. |
| `auditar_y_puntuar.py` | Preprocesamiento, IF, LOF, scoring y exportaciones. |
| `soporte_proyecto.py` | Calidad, distancia, perfiles, evaluación y publicación transaccional. |
| `inspeccion_documental.py` | Genera el contraste documental de casos seleccionados. |
| `publicar_ejecucion.py` | Publica una ejecución existente tras contrastar la fuente. |
| `verificar_ejecucion.py` | Compara resultados locales con la publicación SQL. |
| `test_proyecto.py` | Pruebas con datos sintéticos y conexiones simuladas. |
| `powerbi/` | Proyecto de informe y modelo semántico, sin caché de datos. |
| `datos/README.md` | Fuente y ubicación de datos externos. |

## Requisitos

- Windows, Python 3.11 o posterior y dependencias de `requirements_proyecto.txt`.
- SQL Server con la base `OLIST_DW` y ODBC Driver 17 for SQL Server.
- Autenticación de Windows con los permisos correspondientes.
- Power BI Desktop compatible con proyectos PBIP.

Las dependencias no están fijadas a versiones concretas. Las ejecuciones registran versiones de Python y bibliotecas en sus metadatos.

## 1. Preparar la base

Este repositorio no crea una instalación completa desde cero: la carga inicial de CSV en Bronze es externa. El SQL presupone las seis tablas Bronze de clientes, órdenes, productos, vendedores, ítems y pagos.

`sql/Proyecto_solo_etapas.sql` contiene operaciones DROP/CREATE de Silver y Gold. Revísalo y ejecútalo por etapas en una base de trabajo; no es una migración segura para repetir sobre una base con trabajo que deba conservarse. Los separadores GO crean lotes y un THROW no garantiza detener todos los lotes siguientes.

El flujo Python consume las seis tablas Silver y `gold.order_anomaly_features`. El modelo de Power BI también referencia `gold.order_anomaly_ml` y `gold.order_anomaly_scoring`. El SQL incluido prepara ML, pero no crea ni carga automáticamente la tabla scoring para un entorno nuevo. Esa inicialización queda como requisito previo y debe respetar el esquema esperado por `publicar_sql` y el modelo Power BI.

## 2. Configurar Python

Desde la carpeta del proyecto:

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install -r requirements_proyecto.txt
Copy-Item config_proyecto.example.json config_proyecto.json
```

Edita `config_proyecto.json`: reemplaza `TU_SERVIDOR`, ajusta el umbral y documenta su justificación. El archivo local se excluye de Git.

La configuración de ejemplo tiene `publicar_sql: false`: genera evidencia local sin publicar cambios SQL. La conexión utiliza autenticación de Windows; no se necesitan contraseñas en el código.

## 3. Ejecutar el análisis

```powershell
python ejecutar_proyecto.py
```

También puedes abrir `EJECUTAR_PROYECTO.cmd` con el entorno Python preparado. Los resultados se guardan en una carpeta independiente dentro de `ejecuciones/`. `ULTIMA_EJECUCION.txt` señala la última terminada.

Entre las salidas se incluyen scoring, Top 20 explicado, controles de calidad, sensibilidad de umbral, estabilidad, evaluación por estado, metadatos y una plantilla de revisión humana. La plantilla debe completarse; su generación no acredita una revisión realizada.

La distancia opcional usa coordenadas postales, Haversine y el máximo por orden; no representa una ruta vial. La integración opcional de Excel del entorno original no se incluye en esta copia portable.

## 4. Publicar y abrir Power BI

Con `publicar_sql: false`, el informe SQL no lee los CSV generados y conserva los resultados publicados anteriormente. Para actualizarlo, primero debe existir una tabla scoring compatible y con la misma cohorte. Después puede activarse `publicar_sql: true` o usarse:

```powershell
python publicar_ejecucion.py ejecuciones/NOMBRE_CARPETA --server TU_SERVIDOR
```

La publicación modifica SQL, compara la fuente y las órdenes existentes, y utiliza una transacción con rollback ante errores. Si hay geolocalización, también puede agregar y actualizar columnas geográficas de Gold.

Abre `powerbi/Dashboard_OLIST_Claro.pbip`. Conserva a su lado las carpetas `.Report` y `.SemanticModel`. En Power BI, cambia el origen `TU_SERVIDOR` por tu servidor en la configuración del origen de datos o en los pasos de conexión de Power Query y actualiza los datos. Este ajuste es independiente de `config_proyecto.json`.

El proyecto no incluye caché ni credenciales: requiere conexión a la base para cargar datos.

### Páginas del dashboard

- **Resumen:** órdenes, detecciones por modelo, consenso, prioridad y rareza.
- **Explorar órdenes:** identificación, puntajes, perfiles y filtros para investigar casos.
- **Perfiles de anomalía:** combinaciones de motivos de órdenes con prioridad ALTA o MEDIA.
- **Importes y logística:** montos, envío y tiempos por etapa y estado geográfico del cliente. BRL significa reales brasileños. El total de la orden incluye envío.

El modelo no relaciona por order_id la tabla scoring con features: los filtros de anomalías no conectan automáticamente el análisis logístico.

## Interpretación y límites

El flujo Python incluido normaliza los scores por percentil empírico y calcula su promedio. La prioridad de modelo ALTA/MEDIA/BAJA representa coincidencia de dos, uno o ningún modelo. El nivel de rareza divide el puntaje en intervalos hasta 0,25; 0,50; 0,75 y 1; no es una probabilidad. La prioridad operativa P1–P4 se exporta aparte y considera controles de calidad.

El corte inicial del 2% es exploratorio. Se analiza sensibilidad y estabilidad, pero sin etiquetas verificadas no se afirma precisión o recall. Los perfiles y desviaciones son descriptores, no causas. Se trata de un análisis retrospectivo que utiliza información de entrega; los ceros heredados de Gold pueden ocultar faltantes.

## Pruebas

```powershell
python -m unittest test_proyecto.py
```

Estas pruebas no requieren una conexión real y no certifican la carga de una base nueva ni una publicación real.

## Subir a GitHub

Crea un repositorio vacío. Para cargar desde el navegador, utiliza Add file → Upload files y arrastra **el contenido de esta carpeta**, no el ZIP. Si GitHub limita la carga, utiliza Git:

```powershell
git init
git add .
git commit -m "Agregar proyecto OLIST de detección de anomalías"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/OLIST-Deteccion-Anomalias.git
git push -u origin main
```

Reemplaza la URL por la de tu repositorio. Este paquete no se ha publicado automáticamente. No se incluye una licencia del código: el autor puede escogerla antes de distribuirlo. Los datos externos tienen sus propias condiciones de uso.
