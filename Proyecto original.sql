/* ============================================================================
 PROYECTO OLIST - SCRIPT MAESTRO (BRONZE YA CARGADO)
 BASE: OLIST_DW

 No crea, elimina, vacía ni recarga tablas Bronze.
 Ejecutar en SQL Server Management Studio desde el comienzo para construir
 las etapas Silver, Gold y el dataset para Machine Learning.

 IMPORTANTE: Este script no ejecuta Python. Las consultas de scoring final
 están desactivadas y deben ejecutarse DESPUÉS de Proyecto minería.py.
 Antes de ejecutar todo, revisar instrucciones DROP/CREATE de Silver y Gold:
 podrían reemplazar objetos ya existentes en esos esquemas.
============================================================================ */
USE OLIST_DW;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'bronze')
    THROW 51000, 'Falta el esquema bronze en OLIST_DW.', 1;
GO

/* VERIFICAR LAS SIETE TABLAS BRONZE ANTES DE PROCESAR */
IF OBJECT_ID(N'bronze.olist_customers_dataset',N'U') IS NULL OR
   OBJECT_ID(N'bronze.olist_order_items_dataset',N'U') IS NULL OR
   OBJECT_ID(N'bronze.olist_order_payments_dataset',N'U') IS NULL OR
   OBJECT_ID(N'bronze.olist_orders_dataset',N'U') IS NULL OR
   OBJECT_ID(N'bronze.olist_products_dataset',N'U') IS NULL OR
   OBJECT_ID(N'bronze.olist_sellers_dataset',N'U') IS NULL
    THROW 51001, 'Falta una o mas tablas Bronze; no continuar.', 1;
GO

/* ==================== 02 EN ADELANTE - SILVER / GOLD / ML ==================== */

/* ============================================================================
   PROYECTO OLIST - MINERÍA DE DATOS / DETECCIÓN DE ANOMALÍAS
   SCRIPT SQL CONSOLIDADO

   Orden lógico:
   Bronze -> Silver -> Validación -> Gold -> Calidad -> Dataset ML
          -> NULL -> Estandarización -> Python (externo) -> Validación scoring

   IMPORTANTE:
   - Este archivo consolida los scripts SQL entregados por el usuario.
   - El entrenamiento Isolation Forest + LOF se realiza en Proyecto minería.py,
     por lo que no forma parte de este archivo SQL.
   - La validación final requiere que Python haya creado
     gold.order_anomaly_scoring.
   - El archivo "Preparar los datos Null.sql" se conserva al final como
     referencia, pero está DESACTIVADO porque duplica una etapa cubierta de
     forma más completa por "anomalias valores faltantes tratamiento.sql".
============================================================================ */



/* ========================================================================
   ETAPA: 00 - Verificación de esquemas
   ARCHIVO ORIGINAL: Proyecto Etapas.sql
========================================================================= */

USE OLIST_DW;
GO

SELECT name AS Esquema
FROM sys.schemas
WHERE name IN ('bronze', 'silver', 'gold');
GO


/* ========================================================================
   ETAPA: 01 - Cantidad de datos en Bronze
   ARCHIVO ORIGINAL: Cantidad de datos.sql
========================================================================= */

USE OLIST_DW;
GO

SELECT 'customers' AS tabla, COUNT(*) AS registros
FROM bronze.olist_customers_dataset

UNION ALL

SELECT 'orders', COUNT(*)
FROM bronze.olist_orders_dataset

UNION ALL

SELECT 'order_items', COUNT(*)
FROM bronze.olist_order_items_dataset

UNION ALL

SELECT 'products', COUNT(*)
FROM bronze.olist_products_dataset

UNION ALL

SELECT 'sellers', COUNT(*)
FROM bronze.olist_sellers_dataset

UNION ALL

SELECT 'order_payments', COUNT(*)
FROM bronze.olist_order_payments_dataset;
GO


/* ========================================================================
   ETAPA: 02 - Silver Customers
   ARCHIVO ORIGINAL: Proyecto costumers silver.sql
========================================================================= */

/* ============================================================
   PROYECTO OLIST - CAPA SILVER
   TABLA: CUSTOMERS
   ============================================================

   OBJETIVO:
   Transformar la información de clientes almacenada en la
   capa Bronze y crear una tabla Silver limpia y preparada
   para análisis.

   PROCESO:
   1. Seleccionar la base de datos OLIST_DW.
   2. Crear la tabla silver.customers.
   3. Limpiar los datos provenientes de Bronze.
   4. Validar la cantidad de registros.
   5. Ejecutar controles de calidad.
   6. Crear la clave primaria.
   7. Verificar la clave primaria.

   ORIGEN:
   bronze.olist_customers_dataset

   DESTINO:
   silver.customers
   ============================================================ */


/* ============================================================
   PASO 1: SELECCIONAR LA BASE DE DATOS
   ============================================================

   USE indica a SQL Server que las siguientes instrucciones
   deben ejecutarse dentro de la base de datos OLIST_DW.
   ============================================================ */

USE OLIST_DW;
GO


/* ============================================================
   PASO 2: ELIMINAR SILVER.CUSTOMERS SI YA EXISTE
   ============================================================

   DROP TABLE IF EXISTS permite volver a ejecutar todo el
   proceso desde cero.

   Si silver.customers existe, SQL Server la elimina.
   Si no existe, continúa sin producir un error.

   IMPORTANTE:
   Esto solamente elimina la tabla Silver.
   La tabla original de Bronze NO se modifica.
   ============================================================ */

DROP TABLE IF EXISTS silver.customers;
GO


/* ============================================================
   PASO 3: CREAR LA TABLA SILVER.CUSTOMERS
   ============================================================

   Aquí definimos la estructura que tendrá la información
   de clientes en la capa Silver.

   En Silver los datos comienzan a tener una estructura
   controlada para posteriormente relacionarlos con las
   demás tablas.
   ============================================================ */

CREATE TABLE silver.customers
(
    /* --------------------------------------------------------
       customer_id
       Identificador del cliente utilizado en las órdenes.

       NOT NULL significa que este campo es obligatorio.
       -------------------------------------------------------- */
    customer_id NVARCHAR(50) NOT NULL,


    /* --------------------------------------------------------
       customer_unique_id
       Identificador que permite reconocer al mismo cliente
       aunque tenga diferentes compras u órdenes.

       NOT NULL porque esperamos que todos los clientes
       tengan este identificador.
       -------------------------------------------------------- */
    customer_unique_id NVARCHAR(50) NOT NULL,


    /* --------------------------------------------------------
       customer_zip_code_prefix
       Prefijo del código postal del cliente.

       Se mantiene como texto porque funciona como un código
       geográfico, no como una cantidad matemática.

       NULL indica que se permite un valor faltante.
       -------------------------------------------------------- */
    customer_zip_code_prefix NVARCHAR(10) NULL,


    /* --------------------------------------------------------
       customer_city
       Ciudad correspondiente al cliente.
       -------------------------------------------------------- */
    customer_city NVARCHAR(100) NULL,


    /* --------------------------------------------------------
       customer_state
       Código del estado de Brasil.

       Ejemplos:
       SP = São Paulo
       RJ = Rio de Janeiro
       MG = Minas Gerais
       -------------------------------------------------------- */
    customer_state NVARCHAR(10) NULL
);
GO


/* ============================================================
   PASO 4: CARGAR LOS DATOS DE BRONZE HACIA SILVER
   ============================================================

   INSERT INTO indica la tabla donde vamos a almacenar
   los datos transformados.

   En este caso:

   ORIGEN:
       bronze.olist_customers_dataset

   DESTINO:
       silver.customers
   ============================================================ */

INSERT INTO silver.customers
(
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
)

SELECT

    /* --------------------------------------------------------
       LTRIM:
       elimina espacios ubicados al inicio.

       RTRIM:
       elimina espacios ubicados al final.

       NULLIF:
       convierte una cadena vacía ('') en NULL.

       Ejemplo:

       '   ABC123   '
              ↓
       'ABC123'

       Si tenemos:
       ''

       se transforma en:
       NULL
       -------------------------------------------------------- */

    NULLIF(LTRIM(RTRIM(customer_id)), ''),

    NULLIF(LTRIM(RTRIM(customer_unique_id)), ''),

    NULLIF(LTRIM(RTRIM(customer_zip_code_prefix)), ''),

    NULLIF(LTRIM(RTRIM(customer_city)), ''),

    NULLIF(LTRIM(RTRIM(customer_state)), '')

FROM bronze.olist_customers_dataset;
GO


/* ============================================================
   PASO 5: VALIDAR CANTIDAD DE REGISTROS BRONZE
   ============================================================

   COUNT(*) cuenta todas las filas existentes en la tabla
   original.

   En nuestro caso obtuvimos:

   99,441 registros.

   Este valor sirve como punto de control para comprobar
   que no perdimos registros durante la transformación.
   ============================================================ */

SELECT
    COUNT(*) AS registros_bronze
FROM bronze.olist_customers_dataset;
GO


/* ============================================================
   PASO 6: VALIDAR CANTIDAD DE REGISTROS SILVER
   ============================================================

   Ahora contamos las filas de la tabla Silver.

   Esperamos obtener la misma cantidad que en Bronze:

   Bronze = 99,441
   Silver = 99,441

   Si ambos valores coinciden, sabemos que la transformación
   no eliminó registros.
   ============================================================ */

SELECT
    COUNT(*) AS registros_silver
FROM silver.customers;
GO


/* ============================================================
   PASO 7: REVISIÓN VISUAL DE LOS DATOS
   ============================================================

   TOP 10 muestra una pequeña muestra de la tabla.

   Esto permite revisar visualmente que:
   - Los identificadores estén correctos.
   - Las ciudades se hayan cargado.
   - Los estados estén presentes.
   - Las columnas estén en el orden esperado.
   ============================================================ */

SELECT TOP 10 *
FROM silver.customers;
GO


/* ============================================================
   CONTROLES DE CALIDAD DE DATOS
   ============================================================

   Ahora comenzamos a medir formalmente la calidad de
   silver.customers.

   Estas consultas nos ayudan a cumplir con el requisito
   del proyecto relacionado con reglas medibles de:

   - Completitud
   - Unicidad
   - Validez
   - Consistencia
   - Integridad
   ============================================================ */


/* ============================================================
   CONTROL DE CALIDAD 1: CUSTOMER_ID NULOS
   ============================================================

   OBJETIVO:
   Validar la COMPLETITUD del identificador del cliente.

   customer_id es fundamental porque posteriormente permitirá
   relacionar customers con orders.

   RESULTADO OBTENIDO:
   0 registros nulos.

   INTERPRETACIÓN:
   Todos los registros poseen customer_id.
   ============================================================ */

SELECT
    COUNT(*) AS customer_id_nulos
FROM silver.customers
WHERE customer_id IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 2: CUSTOMER_UNIQUE_ID NULOS
   ============================================================

   OBJETIVO:
   Verificar que todos los clientes tengan su identificador
   único de cliente.

   RESULTADO OBTENIDO:
   0 registros nulos.
   ============================================================ */

SELECT
    COUNT(*) AS customer_unique_id_nulos
FROM silver.customers
WHERE customer_unique_id IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 3: CUSTOMER_ID DUPLICADOS
   ============================================================

   OBJETIVO:
   Validar la UNICIDAD de customer_id.

   GROUP BY agrupa registros que tienen el mismo customer_id.

   COUNT(*) calcula cuántas veces aparece cada identificador.

   HAVING COUNT(*) > 1 muestra únicamente los identificadores
   que aparecen más de una vez.

   RESULTADO OBTENIDO:
   0 filas.

   INTERPRETACIÓN:
   No existen customer_id duplicados.

   Por esta razón podemos utilizar customer_id como
   clave primaria.
   ============================================================ */

SELECT
    customer_id,
    COUNT(*) AS cantidad
FROM silver.customers
GROUP BY customer_id
HAVING COUNT(*) > 1;
GO


/* ============================================================
   CONTROL DE CALIDAD 4: REVISAR LOS ESTADOS
   ============================================================

   OBJETIVO:
   Analizar la VALIDEZ de customer_state.

   Se agrupan los clientes según el estado y se cuenta
   cuántos registros existen para cada código.

   Ejemplos encontrados:
   AC
   AL
   AM
   AP
   BA
   CE
   DF
   ES
   GO
   MG
   etc.

   Esto permite identificar códigos inesperados o incorrectos.
   ============================================================ */

SELECT
    customer_state,
    COUNT(*) AS cantidad
FROM silver.customers
GROUP BY customer_state
ORDER BY customer_state;
GO


/* ============================================================
   CONTROL DE CALIDAD 5: CÓDIGO POSTAL NULO
   ============================================================

   OBJETIVO:
   Medir la COMPLETITUD del código postal.

   Se cuentan todos los registros donde
   customer_zip_code_prefix sea NULL.

   RESULTADO OBTENIDO:
   0 registros nulos.
   ============================================================ */

SELECT
    COUNT(*) AS codigo_postal_nulo
FROM silver.customers
WHERE customer_zip_code_prefix IS NULL;
GO


/* ============================================================
   PASO 8: CREAR LA CLAVE PRIMARIA
   ============================================================

   Una vez comprobamos que:

   - customer_id no tiene valores NULL.
   - customer_id no tiene duplicados.

   podemos definirlo como PRIMARY KEY.

   Una clave primaria garantiza que cada registro tenga
   un identificador único.

   PK_silver_customers es simplemente el nombre que le damos
   a la restricción.

   IMPORTANTE:
   Si esta clave ya fue creada anteriormente, NO debes volver
   a ejecutar este bloque porque SQL Server indicará:

   "Table 'customers' already has a primary key defined on it."

   En tu base actualmente YA existe.
   ============================================================ */

ALTER TABLE silver.customers
ADD CONSTRAINT PK_silver_customers
PRIMARY KEY (customer_id);
GO


/* ============================================================
   PASO 9: VERIFICAR LA CLAVE PRIMARIA
   ============================================================

   Esta consulta utiliza las tablas internas del sistema de
   SQL Server para identificar qué clave primaria tiene
   silver.customers y sobre qué columna está definida.

   sys.key_constraints:
   contiene información de restricciones como Primary Keys.

   sys.index_columns:
   identifica las columnas que forman parte del índice
   asociado a la clave primaria.

   sys.columns:
   permite obtener el nombre de la columna.

   OBJECT_ID('silver.customers'):
   identifica internamente nuestra tabla.

   kc.type = 'PK':
   limita el resultado únicamente a Primary Keys.

   RESULTADO QUE YA OBTUVIMOS:

   nombre_clave          columna
   -------------------   -----------
   PK_silver_customers   customer_id

   Esto confirma que customer_id es correctamente la
   clave primaria de silver.customers.
   ============================================================ */

SELECT
    kc.name AS nombre_clave,
    c.name AS columna

FROM sys.key_constraints kc

JOIN sys.index_columns ic
    ON kc.parent_object_id = ic.object_id
    AND kc.unique_index_id = ic.index_id

JOIN sys.columns c
    ON ic.object_id = c.object_id
    AND ic.column_id = c.column_id

WHERE kc.parent_object_id = OBJECT_ID('silver.customers')
  AND kc.type = 'PK';
GO


/* ========================================================================
   ETAPA: 03 - Silver Orders
   ARCHIVO ORIGINAL: Proyecto orders silver.sql
========================================================================= */

/* ============================================================
   PROYECTO OLIST - CAPA SILVER
   TABLA: ORDERS
   ============================================================

   OBJETIVO:
   Transformar la información de órdenes almacenada en Bronze
   y crear una tabla Silver limpia, tipificada y preparada
   para análisis y Machine Learning.

   ORIGEN:
   bronze.olist_orders_dataset

   DESTINO:
   silver.orders

   PROCESO:
   1. Seleccionar la base OLIST_DW.
   2. Crear silver.orders.
   3. Limpiar y transformar los datos.
   4. Validar cantidad de registros.
   5. Revisar valores NULL.
   6. Revisar duplicados.
   7. Revisar estados.
   8. Validar consistencia de fechas.
   9. Crear clave primaria.
   10. Crear relación con customers.
   ============================================================ */


/* ============================================================
   PASO 1: SELECCIONAR BASE DE DATOS
   ============================================================ */

USE OLIST_DW;
GO


/* ============================================================
   PASO 2: ELIMINAR SILVER.ORDERS SI YA EXISTE
   ============================================================

   Esto permite ejecutar nuevamente el proceso desde cero.

   IMPORTANTE:
   Solo elimina silver.orders.
   NO modifica bronze.olist_orders_dataset.
   ============================================================ */

DROP TABLE IF EXISTS silver.orders;
GO


/* ============================================================
   PASO 3: CREAR LA TABLA SILVER.ORDERS
   ============================================================

   Aquí definimos una estructura más controlada que la
   utilizada en la capa Bronze.

   order_id:
   identificador único de cada orden.

   customer_id:
   identificador del cliente que realizó la orden.

   order_status:
   estado de la orden.

   Los demás campos corresponden a diferentes momentos
   del proceso logístico.
   ============================================================ */

CREATE TABLE silver.orders
(
    /* Identificador único de la orden */
    order_id NVARCHAR(50) NOT NULL,

    /* Cliente asociado a la orden */
    customer_id NVARCHAR(50) NOT NULL,

    /* Estado de la orden */
    order_status NVARCHAR(50) NOT NULL,

    /* Fecha y hora en que el cliente realizó la compra */
    order_purchase_timestamp DATETIME2 NULL,

    /* Fecha y hora en que fue aprobado el pago */
    order_approved_at DATETIME2 NULL,

    /* Fecha en que la orden fue entregada al transportista */
    order_delivered_carrier_date DATETIME2 NULL,

    /* Fecha en que la orden fue entregada al cliente */
    order_delivered_customer_date DATETIME2 NULL,

    /* Fecha estimada de entrega */
    order_estimated_delivery_date DATETIME2 NULL
);
GO


/* ============================================================
   PASO 4: CARGAR Y LIMPIAR LOS DATOS DE BRONZE
   ============================================================

   INSERT INTO:
   indica dónde almacenaremos los datos.

   SELECT:
   obtiene los datos desde Bronze.

   Para los campos de texto usamos:

   LTRIM = elimina espacios a la izquierda.
   RTRIM = elimina espacios a la derecha.
   NULLIF = convierte cadenas vacías en NULL.

   Las fechas ya fueron importadas como DATETIME2, por lo que
   podemos trasladarlas directamente.

   IMPORTANTE:
   Algunas fechas pueden legítimamente ser NULL.

   Por ejemplo, una orden cancelada podría no tener fecha
   de entrega al cliente.
   ============================================================ */

INSERT INTO silver.orders
(
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
)

SELECT
    NULLIF(LTRIM(RTRIM(order_id)), ''),
    NULLIF(LTRIM(RTRIM(customer_id)), ''),
    NULLIF(LTRIM(RTRIM(order_status)), ''),

    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date

FROM bronze.olist_orders_dataset;
GO


/* ============================================================
   PASO 5: COMPARAR CANTIDAD DE REGISTROS
   ============================================================

   Primero contamos Bronze.
   Después contamos Silver.

   Según la carga que ya realizamos, Bronze tiene:

   99,441 registros.

   Silver debería conservar la misma cantidad.
   ============================================================ */

SELECT
    COUNT(*) AS registros_bronze
FROM bronze.olist_orders_dataset;
GO


SELECT
    COUNT(*) AS registros_silver
FROM silver.orders;
GO


/* ============================================================
   PASO 6: REVISAR UNA MUESTRA
   ============================================================

   TOP 10 nos permite verificar visualmente que la
   transformación se realizó correctamente.
   ============================================================ */

SELECT TOP 10 *
FROM silver.orders;
GO


/* ============================================================
   CONTROL DE CALIDAD 1
   VALIDAR ORDER_ID NULOS
   ============================================================

   REGLA:
   Toda orden debe tener un identificador.

   Esta prueba mide COMPLETITUD.

   Resultado esperado:
   0
   ============================================================ */

SELECT
    COUNT(*) AS order_id_nulos
FROM silver.orders
WHERE order_id IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 2
   VALIDAR CUSTOMER_ID NULOS
   ============================================================

   REGLA:
   Toda orden debe estar asociada con un cliente.

   También corresponde a una validación de COMPLETITUD.

   Resultado esperado:
   0
   ============================================================ */

SELECT
    COUNT(*) AS customer_id_nulos
FROM silver.orders
WHERE customer_id IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 3
   BUSCAR ORDER_ID DUPLICADOS
   ============================================================

   Cada order_id debería representar una sola orden.

   GROUP BY:
   agrupa los registros por order_id.

   HAVING COUNT(*) > 1:
   muestra únicamente IDs repetidos.

   Esta prueba mide UNICIDAD.

   Resultado esperado:
   ninguna fila.
   ============================================================ */

SELECT
    order_id,
    COUNT(*) AS cantidad
FROM silver.orders
GROUP BY order_id
HAVING COUNT(*) > 1;
GO


/* ============================================================
   CONTROL DE CALIDAD 4
   REVISAR LOS ESTADOS DE LAS ÓRDENES
   ============================================================

   Aquí veremos los diferentes valores existentes en
   order_status y cuántas órdenes existen por cada uno.

   En Olist podemos encontrar estados como:

   delivered
   shipped
   canceled
   unavailable
   invoiced
   processing
   approved
   created

   Esta validación ayuda a evaluar VALIDEZ y CONSISTENCIA.
   ============================================================ */

SELECT
    order_status,
    COUNT(*) AS cantidad
FROM silver.orders
GROUP BY order_status
ORDER BY order_status;
GO


/* ============================================================
   CONTROL DE CALIDAD 5
   VALIDAR FECHA DE COMPRA NULA
   ============================================================

   Toda orden debería tener una fecha en la que fue creada.

   Resultado esperado:
   0
   ============================================================ */

SELECT
    COUNT(*) AS fecha_compra_nula
FROM silver.orders
WHERE order_purchase_timestamp IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 6
   ANALIZAR FECHAS DE APROBACIÓN NULAS
   ============================================================

   IMPORTANTE:

   Aquí NO debemos asumir automáticamente que un NULL es
   un error.

   Algunas órdenes pueden estar canceladas o no haber
   completado el proceso de aprobación.

   Por eso primero medimos los NULL.
   ============================================================ */

SELECT
    COUNT(*) AS fecha_aprobacion_nula
FROM silver.orders
WHERE order_approved_at IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 7
   FECHA DE ENTREGA AL TRANSPORTISTA NULA
   ============================================================

   Algunas órdenes canceladas o incompletas pueden no haber
   llegado nunca al transportista.

   Por eso estos NULL deben analizarse y no eliminarse
   automáticamente.
   ============================================================ */

SELECT
    COUNT(*) AS fecha_transportista_nula
FROM silver.orders
WHERE order_delivered_carrier_date IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 8
   FECHA DE ENTREGA AL CLIENTE NULA
   ============================================================

   Una orden que todavía no fue entregada, fue cancelada
   o quedó incompleta puede no tener esta fecha.
   ============================================================ */

SELECT
    COUNT(*) AS fecha_entrega_cliente_nula
FROM silver.orders
WHERE order_delivered_customer_date IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 9
   VALIDAR CONSISTENCIA TEMPORAL
   ============================================================

   Buscamos casos donde la fecha de entrega al cliente sea
   ANTERIOR a la fecha de compra.

   Eso sería temporalmente inconsistente.

   Resultado esperado:
   0 registros.
   ============================================================ */

SELECT
    COUNT(*) AS entregas_antes_de_compra
FROM silver.orders
WHERE order_delivered_customer_date
      < order_purchase_timestamp;
GO


/* ============================================================
   CONTROL DE CALIDAD 10
   APROBACIÓN ANTERIOR A LA COMPRA
   ============================================================

   Normalmente una orden debería comprarse antes de ser
   aprobada.

   Buscamos registros potencialmente inconsistentes.
   ============================================================ */

SELECT
    COUNT(*) AS aprobaciones_antes_de_compra
FROM silver.orders
WHERE order_approved_at < order_purchase_timestamp;
GO


/* ============================================================
   CONTROL DE CALIDAD 11
   ENTREGA AL CLIENTE ANTES DEL TRANSPORTISTA
   ============================================================

   Lógicamente:

   transportista -> cliente

   Por lo tanto buscamos registros donde aparezca:

   cliente -> transportista

   lo cual podría representar un problema de calidad.
   ============================================================ */

SELECT
    COUNT(*) AS entrega_cliente_antes_transportista
FROM silver.orders
WHERE order_delivered_customer_date
      < order_delivered_carrier_date;
GO


/* ============================================================
   CONTROL DE CALIDAD 12
   VALIDAR INTEGRIDAD REFERENCIAL CON CUSTOMERS
   ============================================================

   Esta es una prueba MUY IMPORTANTE.

   Queremos comprobar que todos los customer_id utilizados
   en orders realmente existan en silver.customers.

   LEFT JOIN:
   conserva todas las órdenes.

   WHERE c.customer_id IS NULL:
   muestra las órdenes cuyo cliente NO fue encontrado.

   Esta prueba mide INTEGRIDAD REFERENCIAL.

   Resultado esperado:
   0
   ============================================================ */

SELECT
    COUNT(*) AS ordenes_sin_cliente
FROM silver.orders o
LEFT JOIN silver.customers c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;
GO


/* ============================================================
   PASO 7: CREAR PRIMARY KEY
   ============================================================

   Después de haber comprobado que order_id:

   - No tiene NULL.
   - No tiene duplicados.

   podemos establecerlo como clave primaria.

   Esto garantiza que cada orden sea única.
   ============================================================ */

ALTER TABLE silver.orders
ADD CONSTRAINT PK_silver_orders
PRIMARY KEY (order_id);
GO


/* ============================================================
   PASO 8: CREAR FOREIGN KEY
   ============================================================

   Ahora creamos una relación formal entre:

   silver.orders.customer_id
                ↓
   silver.customers.customer_id

   Esto significa que SQL Server no permitirá una orden
   cuyo customer_id no exista en customers.

   Esta restricción garantiza INTEGRIDAD REFERENCIAL.
   ============================================================ */

ALTER TABLE silver.orders
ADD CONSTRAINT FK_silver_orders_customers
FOREIGN KEY (customer_id)
REFERENCES silver.customers(customer_id);
GO


/* ============================================================
   PASO 9: VERIFICAR PRIMARY KEY
   ============================================================ */

SELECT
    kc.name AS nombre_clave,
    c.name AS columna
FROM sys.key_constraints kc

JOIN sys.index_columns ic
    ON kc.parent_object_id = ic.object_id
    AND kc.unique_index_id = ic.index_id

JOIN sys.columns c
    ON ic.object_id = c.object_id
    AND ic.column_id = c.column_id

WHERE kc.parent_object_id = OBJECT_ID('silver.orders')
  AND kc.type = 'PK';
GO


/* ============================================================
   PASO 10: VERIFICAR FOREIGN KEY
   ============================================================

   Esta consulta permite comprobar que la relación entre
   orders y customers fue creada correctamente.
   ============================================================ */

SELECT
    fk.name AS nombre_foreign_key,
    OBJECT_NAME(fk.parent_object_id) AS tabla_origen,
    COL_NAME(
        fkc.parent_object_id,
        fkc.parent_column_id
    ) AS columna_origen,

    OBJECT_NAME(fk.referenced_object_id) AS tabla_destino,

    COL_NAME(
        fkc.referenced_object_id,
        fkc.referenced_column_id
    ) AS columna_destino

FROM sys.foreign_keys fk

JOIN sys.foreign_key_columns fkc
    ON fk.object_id = fkc.constraint_object_id

WHERE fk.parent_object_id = OBJECT_ID('silver.orders');
GO


/* ========================================================================
   ETAPA: 04 - Silver Products
   ARCHIVO ORIGINAL: Proyectos products silver.sql
========================================================================= */

/* ============================================================
   TABLA SILVER: PRODUCTS
   Proyecto: OLIST

   Objetivo:
   Tomar los productos cargados en Bronze y crear una tabla
   Silver limpia y preparada para análisis.

   Tabla origen:
   bronze.olist_products_dataset

   Tabla destino:
   silver.products
   ============================================================ */

USE OLIST_DW;
GO


/* ============================================================
   1. ELIMINAR LA TABLA SILVER SI YA EXISTE

   Esto permite volver a ejecutar el proceso desde cero sin que
   SQL Server genere el error "There is already an object named".
   ============================================================ */

DROP TABLE IF EXISTS silver.products;
GO


/* ============================================================
   2. CREAR LA TABLA SILVER.PRODUCTS

   product_id:
   Identificador único del producto.

   product_category_name:
   Categoría original del producto.

   product_name_lenght:
   Cantidad de caracteres del nombre del producto.

   product_description_lenght:
   Cantidad de caracteres de la descripción.

   product_photos_qty:
   Cantidad de fotografías asociadas al producto.

   product_weight_g:
   Peso del producto en gramos.

   product_length_cm:
   Largo del producto en centímetros.

   product_height_cm:
   Alto del producto en centímetros.

   product_width_cm:
   Ancho del producto en centímetros.

   IMPORTANTE:
   Los campos distintos de product_id permiten NULL porque
   el dataset Olist puede contener información incompleta.
   ============================================================ */

CREATE TABLE silver.products
(
    product_id NVARCHAR(50) NOT NULL,

    product_category_name NVARCHAR(100) NULL,

    product_name_lenght INT NULL,

    product_description_lenght INT NULL,

    product_photos_qty INT NULL,

    product_weight_g DECIMAL(18,2) NULL,

    product_length_cm DECIMAL(18,2) NULL,

    product_height_cm DECIMAL(18,2) NULL,

    product_width_cm DECIMAL(18,2) NULL
);
GO


/* ============================================================
   3. CARGAR LOS DATOS DESDE BRONZE HACIA SILVER

   Para los campos de texto usamos:

   LTRIM  = elimina espacios a la izquierda.
   RTRIM  = elimina espacios a la derecha.
   NULLIF = convierte una cadena vacía '' en NULL.

   Los campos numéricos se trasladan a Silver.
   ============================================================ */

INSERT INTO silver.products
(
    product_id,
    product_category_name,
    product_name_lenght,
    product_description_lenght,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
)
SELECT
    NULLIF(LTRIM(RTRIM(product_id)), ''),
    NULLIF(LTRIM(RTRIM(product_category_name)), ''),

    product_name_lenght,
    product_description_lenght,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm

FROM bronze.olist_products_dataset;
GO


/* ============================================================
   4. COMPARAR LA CANTIDAD DE REGISTROS

   Bronze y Silver deberían tener la misma cantidad de registros.
   En tu carga inicial vimos 32,951 productos.
   ============================================================ */

SELECT COUNT(*) AS registros_bronze
FROM bronze.olist_products_dataset;

SELECT COUNT(*) AS registros_silver
FROM silver.products;
GO


/* ============================================================
   5. MOSTRAR UNA MUESTRA DE LOS DATOS

   Permite comprobar visualmente que los datos se cargaron.
   ============================================================ */

SELECT TOP 10 *
FROM silver.products;
GO


/* ============================================================
   6. VALIDAR PRODUCT_ID NULOS

   product_id será nuestra clave primaria.
   Por eso no puede contener valores NULL.

   Resultado esperado: 0
   ============================================================ */

SELECT COUNT(*) AS product_id_nulos
FROM silver.products
WHERE product_id IS NULL;
GO


/* ============================================================
   7. BUSCAR PRODUCT_ID DUPLICADOS

   Cada product_id debe identificar un único producto.

   Si la consulta no devuelve filas significa que no existen
   identificadores duplicados.
   ============================================================ */

SELECT
    product_id,
    COUNT(*) AS cantidad
FROM silver.products
GROUP BY product_id
HAVING COUNT(*) > 1;
GO


/* ============================================================
   8. VALIDAR CATEGORÍAS NULAS

   Aquí queremos conocer cuántos productos no tienen categoría.

   IMPORTANTE:
   Encontrar NULL aquí no necesariamente significa que debemos
   eliminar el producto. Primero medimos la calidad del dato.
   ============================================================ */

SELECT COUNT(*) AS categoria_nula
FROM silver.products
WHERE product_category_name IS NULL;
GO


/* ============================================================
   9. REVISAR LAS CATEGORÍAS

   Agrupa los productos por categoría y muestra cuántos productos
   existen en cada una.

   Esto también permite detectar categorías extrañas o problemas
   de calidad.
   ============================================================ */

SELECT
    product_category_name,
    COUNT(*) AS cantidad
FROM silver.products
GROUP BY product_category_name
ORDER BY cantidad DESC;
GO


/* ============================================================
   10. VALIDAR PESO NULO

   El peso será importante posteriormente para nuestros análisis.
   ============================================================ */

SELECT COUNT(*) AS peso_nulo
FROM silver.products
WHERE product_weight_g IS NULL;
GO


/* ============================================================
   11. VALIDAR PESOS NEGATIVOS

   Un producto no debería tener un peso inferior a cero.

   Resultado esperado: 0
   ============================================================ */

SELECT COUNT(*) AS peso_negativo
FROM silver.products
WHERE product_weight_g < 0;
GO


/* ============================================================
   12. VALIDAR PESO CERO

   No necesariamente eliminaremos estos registros.

   Primero queremos conocer si existen productos registrados
   con peso igual a cero.
   ============================================================ */

SELECT COUNT(*) AS peso_cero
FROM silver.products
WHERE product_weight_g = 0;
GO


/* ============================================================
   13. VALIDAR DIMENSIONES NULAS

   Revisamos por separado largo, alto y ancho.

   Estas dimensiones posteriormente nos permitirán calcular
   el volumen de los productos.
   ============================================================ */

SELECT COUNT(*) AS largo_nulo
FROM silver.products
WHERE product_length_cm IS NULL;

SELECT COUNT(*) AS alto_nulo
FROM silver.products
WHERE product_height_cm IS NULL;

SELECT COUNT(*) AS ancho_nulo
FROM silver.products
WHERE product_width_cm IS NULL;
GO


/* ============================================================
   14. VALIDAR DIMENSIONES NEGATIVAS

   Ninguna dimensión física debería ser menor que cero.

   Resultado esperado: 0
   ============================================================ */

SELECT COUNT(*) AS dimensiones_negativas
FROM silver.products
WHERE product_length_cm < 0
   OR product_height_cm < 0
   OR product_width_cm < 0;
GO


/* ============================================================
   15. VALIDAR DIMENSIONES EN CERO

   Revisamos si existen productos donde alguna de las dimensiones
   físicas sea igual a cero.
   ============================================================ */

SELECT COUNT(*) AS dimensiones_cero
FROM silver.products
WHERE product_length_cm = 0
   OR product_height_cm = 0
   OR product_width_cm = 0;
GO


/* ============================================================
   16. VALIDAR CANTIDAD DE FOTOS NEGATIVA

   Una cantidad de fotografías negativa sería un dato inválido.

   Resultado esperado: 0
   ============================================================ */

SELECT COUNT(*) AS fotos_negativas
FROM silver.products
WHERE product_photos_qty < 0;
GO


/* ============================================================
   17. MOSTRAR PRODUCTOS CON INFORMACIÓN INCOMPLETA

   Esta consulta nos permite inspeccionar algunos productos
   donde falte categoría, peso o dimensiones.

   NO estamos eliminando esos productos.
   Solo estamos revisando la calidad del dataset.
   ============================================================ */

SELECT TOP 20
    product_id,
    product_category_name,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
FROM silver.products
WHERE product_category_name IS NULL
   OR product_weight_g IS NULL
   OR product_length_cm IS NULL
   OR product_height_cm IS NULL
   OR product_width_cm IS NULL;
GO


/* ============================================================
   18. VALIDAR PRODUCTOS DE ORDER_ITEMS QUE NO EXISTEN EN PRODUCTS

   silver.order_items contiene product_id.

   Aquí verificamos que todos esos identificadores tengan un
   producto correspondiente en silver.products.

   Resultado esperado: 0

   Esta validación es MUY IMPORTANTE antes de crear posteriormente
   la Foreign Key.
   ============================================================ */

SELECT COUNT(*) AS items_sin_producto
FROM silver.order_items oi
LEFT JOIN silver.products p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;
GO


/* ============================================================
   19. CREAR LA CLAVE PRIMARIA

   product_id identifica de forma única cada producto.

   Solo debemos ejecutar esto después de comprobar:

   - product_id nulos = 0
   - product_id duplicados = ninguna fila
   ============================================================ */

ALTER TABLE silver.products
ADD CONSTRAINT PK_silver_products
PRIMARY KEY (product_id);
GO


/* ============================================================
   20. COMPROBAR LA CLAVE PRIMARIA

   Esta consulta consulta los metadatos de SQL Server y nos
   confirma qué columna forma la Primary Key de products.

   Resultado esperado:

   nombre_clave          columna
   -------------------   ----------
   PK_silver_products    product_id
   ============================================================ */

SELECT
    kc.name AS nombre_clave,
    c.name AS columna
FROM sys.key_constraints kc

JOIN sys.index_columns ic
    ON kc.parent_object_id = ic.object_id
    AND kc.unique_index_id = ic.index_id

JOIN sys.columns c
    ON ic.object_id = c.object_id
    AND ic.column_id = c.column_id

WHERE kc.parent_object_id = OBJECT_ID('silver.products')
  AND kc.type = 'PK';
GO

USE OLIST_DW;
GO

-- ============================================================
-- VALIDAR LA CLAVE PRIMARIA DE SILVER.PRODUCTS
-- ============================================================

-- Consulta las restricciones de tipo Primary Key (PK)
-- asociadas específicamente a la tabla silver.products.

SELECT
    kc.name AS nombre_clave,   -- Nombre asignado a la clave primaria
    c.name AS columna          -- Columna que forma parte de la PK
FROM sys.key_constraints kc

-- Relacionamos la clave con el índice que SQL Server
-- crea internamente para implementar la Primary Key.
JOIN sys.index_columns ic
    ON kc.parent_object_id = ic.object_id
    AND kc.unique_index_id = ic.index_id

-- Obtenemos el nombre de la columna correspondiente.
JOIN sys.columns c
    ON ic.object_id = c.object_id
    AND ic.column_id = c.column_id

-- Indicamos que únicamente queremos revisar silver.products.
WHERE kc.parent_object_id = OBJECT_ID('silver.products')

-- PK significa Primary Key.
AND kc.type = 'PK';
GO


/* ========================================================================
   ETAPA: 05 - Silver Sellers
   ARCHIVO ORIGINAL: Proyecto sellers silver.sql
========================================================================= */

/* ============================================================
   PROYECTO OLIST
   CAPA SILVER - TABLA SELLERS

   OBJETIVO:
   Tomar los datos originales de:
       bronze.olist_sellers_dataset

   Limpiarlos y almacenarlos en:
       silver.sellers

   PROCESO:
   1. Eliminar silver.sellers si ya existe.
   2. Crear la tabla Silver.
   3. Limpiar y cargar los datos desde Bronze.
   4. Comparar cantidad de registros.
   5. Revisar los datos cargados.
   6. Validar valores NULL.
   7. Buscar seller_id duplicados.
   8. Revisar estados.
   9. Crear la clave primaria.
   10. Verificar la clave primaria.
   ============================================================ */


-- ============================================================
-- 1. SELECCIONAR LA BASE DE DATOS
-- ============================================================

-- Indicamos que todo el código se ejecutará
-- dentro de la base de datos OLIST_DW.

USE OLIST_DW;
GO


-- ============================================================
-- 2. ELIMINAR SILVER.SELLERS SI YA EXISTE
-- ============================================================

-- Esto nos permite volver a ejecutar el proceso completo
-- sin recibir el error:
-- "There is already an object named 'sellers'".

DROP TABLE IF EXISTS silver.sellers;
GO


-- ============================================================
-- 3. CREAR LA TABLA SILVER.SELLERS
-- ============================================================

-- Creamos la estructura donde almacenaremos
-- los vendedores ya procesados.

CREATE TABLE silver.sellers
(
    -- Identificador único del vendedor.
    -- No permitimos NULL porque posteriormente será la PK.
    seller_id NVARCHAR(50) NOT NULL,

    -- Prefijo del código postal del vendedor.
    -- Lo almacenamos como texto para evitar problemas
    -- con códigos postales y conversiones innecesarias.
    seller_zip_code_prefix NVARCHAR(10) NULL,

    -- Ciudad donde se encuentra el vendedor.
    seller_city NVARCHAR(100) NULL,

    -- Estado de Brasil donde se encuentra el vendedor.
    seller_state NVARCHAR(10) NULL
);
GO


-- ============================================================
-- 4. CARGAR Y LIMPIAR LOS DATOS DE BRONZE A SILVER
-- ============================================================

-- Insertamos los datos provenientes de la tabla Bronze.

INSERT INTO silver.sellers
(
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
)
SELECT

    -- LTRIM elimina espacios al inicio.
    -- RTRIM elimina espacios al final.
    -- NULLIF convierte una cadena vacía '' en NULL.
    NULLIF(LTRIM(RTRIM(seller_id)), ''),

    NULLIF(LTRIM(RTRIM(
        CAST(seller_zip_code_prefix AS NVARCHAR(10))
    )), ''),

    NULLIF(LTRIM(RTRIM(seller_city)), ''),

    NULLIF(LTRIM(RTRIM(seller_state)), '')

FROM bronze.olist_sellers_dataset;
GO


-- ============================================================
-- 5. COMPARAR REGISTROS BRONZE VS SILVER
-- ============================================================

-- Primero contamos cuántos vendedores existen
-- en el archivo original cargado en Bronze.

SELECT
    COUNT(*) AS registros_bronze
FROM bronze.olist_sellers_dataset;
GO


-- Ahora contamos cuántos vendedores llegaron a Silver.

SELECT
    COUNT(*) AS registros_silver
FROM silver.sellers;
GO


-- Los dos resultados deberían coincidir.
-- En tu carga original de OLIST esperamos aproximadamente:
--
-- registros_bronze = 3095
-- registros_silver = 3095


-- ============================================================
-- 6. VISUALIZAR UNA MUESTRA
-- ============================================================

-- Mostramos los primeros 10 registros para comprobar
-- visualmente que la información fue cargada correctamente.

SELECT TOP 10 *
FROM silver.sellers;
GO


-- ============================================================
-- 7. VALIDAR SELLER_ID NULOS
-- ============================================================

-- seller_id será nuestra clave primaria.
-- Por lo tanto, no puede contener valores NULL.

SELECT
    COUNT(*) AS seller_id_nulos
FROM silver.sellers
WHERE seller_id IS NULL;
GO


-- Resultado esperado:
--
-- seller_id_nulos
-- ---------------
-- 0


-- ============================================================
-- 8. VALIDAR SELLER_ID DUPLICADOS
-- ============================================================

-- Agrupamos por seller_id.
-- HAVING COUNT(*) > 1 muestra únicamente vendedores
-- cuyo identificador aparece más de una vez.

SELECT
    seller_id,
    COUNT(*) AS cantidad
FROM silver.sellers
GROUP BY seller_id
HAVING COUNT(*) > 1;
GO


-- Resultado esperado:
--
-- No deberían aparecer registros.
--
-- Si no aparece ninguna fila significa que cada seller_id
-- identifica únicamente a un vendedor.


-- ============================================================
-- 9. VALIDAR CÓDIGOS POSTALES NULOS
-- ============================================================

-- Revisamos si existen vendedores sin código postal.

SELECT
    COUNT(*) AS codigo_postal_nulo
FROM silver.sellers
WHERE seller_zip_code_prefix IS NULL;
GO


-- No necesariamente sería un error encontrar NULL.
-- Esta consulta solamente nos permite conocer
-- la calidad de los datos.


-- ============================================================
-- 10. VALIDAR CIUDADES NULAS
-- ============================================================

-- Contamos vendedores que no tienen ciudad informada.

SELECT
    COUNT(*) AS ciudad_nula
FROM silver.sellers
WHERE seller_city IS NULL;
GO


-- ============================================================
-- 11. VALIDAR ESTADOS NULOS
-- ============================================================

-- Contamos vendedores que no tienen estado informado.

SELECT
    COUNT(*) AS estado_nulo
FROM silver.sellers
WHERE seller_state IS NULL;
GO


-- ============================================================
-- 12. REVISAR DISTRIBUCIÓN DE VENDEDORES POR ESTADO
-- ============================================================

-- Agrupamos los vendedores por seller_state.
-- Esto permite comprobar que los códigos de estado
-- tengan valores razonables.

SELECT
    seller_state,
    COUNT(*) AS cantidad
FROM silver.sellers
GROUP BY seller_state
ORDER BY seller_state;
GO


-- Por ejemplo deberían aparecer códigos como:
--
-- SP
-- RJ
-- MG
-- PR
-- SC
-- RS
--
-- entre otros estados de Brasil.


-- ============================================================
-- 13. REVISAR LOS ESTADOS CON MÁS VENDEDORES
-- ============================================================

-- Esta consulta es adicional y nos permite observar
-- dónde se concentra la mayor cantidad de vendedores.

SELECT TOP 10
    seller_state,
    COUNT(*) AS cantidad_vendedores
FROM silver.sellers
GROUP BY seller_state
ORDER BY COUNT(*) DESC;
GO


-- ============================================================
-- 14. CREAR CLAVE PRIMARIA
-- ============================================================

-- seller_id identifica de manera única a cada vendedor.
--
-- Como previamente comprobamos:
-- 1. Que no existan NULL.
-- 2. Que no existan duplicados.
--
-- podemos utilizarlo como Primary Key.

ALTER TABLE silver.sellers
ADD CONSTRAINT PK_silver_sellers
PRIMARY KEY (seller_id);
GO


-- ============================================================
-- 15. VERIFICAR QUE LA CLAVE PRIMARIA FUE CREADA
-- ============================================================

-- Consultamos los metadatos internos de SQL Server
-- para comprobar qué Primary Key tiene silver.sellers.

SELECT
    kc.name AS nombre_clave,
    c.name AS columna

FROM sys.key_constraints kc

-- Relacionamos la restricción con su índice.
JOIN sys.index_columns ic
    ON kc.parent_object_id = ic.object_id
    AND kc.unique_index_id = ic.index_id

-- Obtenemos la columna asociada al índice.
JOIN sys.columns c
    ON ic.object_id = c.object_id
    AND ic.column_id = c.column_id

-- Solamente queremos consultar silver.sellers.
WHERE kc.parent_object_id = OBJECT_ID('silver.sellers')

-- PK = Primary Key.
AND kc.type = 'PK';
GO


-- ============================================================
-- RESULTADO ESPERADO
-- ============================================================

-- Deberíamos obtener:
--
-- nombre_clave        columna
-- ------------------  ---------
-- PK_silver_sellers   seller_id
--
-- Con esto confirmamos que seller_id quedó establecido
-- correctamente como clave primaria.


/* ========================================================================
   ETAPA: 06 - Silver Order Items
   ARCHIVO ORIGINAL: Proyecto orders items silver.sql
========================================================================= */

/* ============================================================
   PROYECTO OLIST - CAPA SILVER
   TABLA: ORDER_ITEMS
   ============================================================

   OBJETIVO:
   Transformar los detalles de productos incluidos en cada
   orden desde la capa Bronze hacia Silver.

   ORIGEN:
   bronze.olist_order_items_dataset

   DESTINO:
   silver.order_items

   Esta tabla contiene una fila por ITEM dentro de una orden.

   Por ejemplo:

   order_id     order_item_id
   --------     -------------
   ORDEN001          1
   ORDEN001          2
   ORDEN001          3
   ORDEN002          1

   Una misma orden puede tener varios productos.

   PROCESO:
   1. Crear silver.order_items.
   2. Limpiar los identificadores.
   3. Tipificar los datos.
   4. Validar cantidad de registros.
   5. Revisar NULL.
   6. Revisar duplicados.
   7. Validar precios y freight.
   8. Validar integridad con orders.
   9. Crear clave primaria compuesta.
   10. Crear Foreign Key con orders.
   ============================================================ */


USE OLIST_DW;
GO


/* ============================================================
   PASO 1: ELIMINAR LA TABLA SI YA EXISTE
   ============================================================

   Esto permite volver a ejecutar el proceso completo.

   NO elimina ni modifica la tabla Bronze.
   ============================================================ */

DROP TABLE IF EXISTS silver.order_items;
GO


/* ============================================================
   PASO 2: CREAR SILVER.ORDER_ITEMS
   ============================================================ */

CREATE TABLE silver.order_items
(
    /* --------------------------------------------------------
       Identificador de la orden.

       Una orden puede aparecer varias veces porque puede
       contener varios artículos.
       -------------------------------------------------------- */
    order_id NVARCHAR(50) NOT NULL,


    /* --------------------------------------------------------
       Número consecutivo del artículo dentro de la orden.

       Ejemplo:

       Orden A - item 1
       Orden A - item 2
       Orden A - item 3
       -------------------------------------------------------- */
    order_item_id INT NOT NULL,


    /* Identificador del producto comprado */
    product_id NVARCHAR(50) NOT NULL,


    /* Identificador del vendedor del producto */
    seller_id NVARCHAR(50) NOT NULL,


    /* Fecha límite que tenía el vendedor para realizar envío */
    shipping_limit_date DATETIME2 NULL,


    /* Precio del producto */
    price DECIMAL(18,2) NULL,


    /* Costo del transporte/flete */
    freight_value DECIMAL(18,2) NULL
);
GO


/* ============================================================
   PASO 3: CARGAR BRONZE -> SILVER
   ============================================================

   Para los identificadores:

   LTRIM = elimina espacios iniciales.
   RTRIM = elimina espacios finales.
   NULLIF = convierte texto vacío en NULL.

   Los valores monetarios se convierten explícitamente
   a DECIMAL(18,2).

   Esto es preferible a FLOAT para valores monetarios porque
   DECIMAL mantiene una precisión decimal controlada.
   ============================================================ */

INSERT INTO silver.order_items
(
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    price,
    freight_value
)

SELECT
    NULLIF(LTRIM(RTRIM(order_id)), ''),

    CAST(order_item_id AS INT),

    NULLIF(LTRIM(RTRIM(product_id)), ''),

    NULLIF(LTRIM(RTRIM(seller_id)), ''),

    shipping_limit_date,

    CAST(price AS DECIMAL(18,2)),

    CAST(freight_value AS DECIMAL(18,2))

FROM bronze.olist_order_items_dataset;
GO


/* ============================================================
   PASO 4: COMPARAR CANTIDAD DE REGISTROS
   ============================================================

   En nuestra carga Bronze obtuvimos:

   112,650 registros.

   Silver debería conservar exactamente la misma cantidad.
   ============================================================ */

SELECT
    COUNT(*) AS registros_bronze
FROM bronze.olist_order_items_dataset;
GO


SELECT
    COUNT(*) AS registros_silver
FROM silver.order_items;
GO


/* ============================================================
   PASO 5: REVISAR UNA MUESTRA
   ============================================================ */

SELECT TOP 10 *
FROM silver.order_items;
GO


/* ============================================================
   CONTROL DE CALIDAD 1
   ORDER_ID NULO
   ============================================================

   REGLA:
   Todo item debe pertenecer a una orden.

   DIMENSIÓN:
   Completitud.

   RESULTADO ESPERADO:
   0
   ============================================================ */

SELECT
    COUNT(*) AS order_id_nulos
FROM silver.order_items
WHERE order_id IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 2
   ORDER_ITEM_ID NULO
   ============================================================

   Cada artículo debe tener su consecutivo dentro de la orden.

   RESULTADO ESPERADO:
   0
   ============================================================ */

SELECT
    COUNT(*) AS order_item_id_nulos
FROM silver.order_items
WHERE order_item_id IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 3
   PRODUCT_ID NULO
   ============================================================

   Cada item debería identificar el producto vendido.

   RESULTADO ESPERADO:
   0
   ============================================================ */

SELECT
    COUNT(*) AS product_id_nulos
FROM silver.order_items
WHERE product_id IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 4
   SELLER_ID NULO
   ============================================================

   Cada item debería estar asociado a un vendedor.

   RESULTADO ESPERADO:
   0
   ============================================================ */

SELECT
    COUNT(*) AS seller_id_nulos
FROM silver.order_items
WHERE seller_id IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 5
   SHIPPING_LIMIT_DATE NULO
   ============================================================

   Medimos la completitud de la fecha límite de envío.
   ============================================================ */

SELECT
    COUNT(*) AS shipping_limit_date_nulos
FROM silver.order_items
WHERE shipping_limit_date IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 6
   PRICE NULO
   ============================================================

   Todo item debería tener un precio.

   RESULTADO ESPERADO:
   0
   ============================================================ */

SELECT
    COUNT(*) AS price_nulos
FROM silver.order_items
WHERE price IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 7
   FREIGHT_VALUE NULO
   ============================================================

   Comprobamos si existen artículos sin información
   correspondiente al costo del transporte.
   ============================================================ */

SELECT
    COUNT(*) AS freight_nulos
FROM silver.order_items
WHERE freight_value IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 8
   BUSCAR DUPLICADOS
   ============================================================

   IMPORTANTE:

   order_id por sí solo NO puede ser la Primary Key porque
   una orden puede tener varios items.

   La combinación:

       order_id + order_item_id

   debería ser única.

   Ejemplo:

   ORDEN01 + 1
   ORDEN01 + 2
   ORDEN01 + 3

   son registros diferentes.

   Pero:

   ORDEN01 + 1
   ORDEN01 + 1

   sería un duplicado.

   DIMENSIÓN:
   Unicidad.

   RESULTADO ESPERADO:
   ninguna fila.
   ============================================================ */

SELECT
    order_id,
    order_item_id,
    COUNT(*) AS cantidad
FROM silver.order_items
GROUP BY
    order_id,
    order_item_id
HAVING COUNT(*) > 1;
GO


/* ============================================================
   CONTROL DE CALIDAD 9
   PRECIOS NEGATIVOS
   ============================================================

   Un precio negativo no tendría sentido para este dataset.

   DIMENSIÓN:
   Validez / rango.

   RESULTADO ESPERADO:
   0
   ============================================================ */

SELECT
    COUNT(*) AS precios_negativos
FROM silver.order_items
WHERE price < 0;
GO


/* ============================================================
   CONTROL DE CALIDAD 10
   FREIGHT NEGATIVO
   ============================================================

   El costo de transporte tampoco debería ser negativo.

   DIMENSIÓN:
   Validez / rango.

   RESULTADO ESPERADO:
   0
   ============================================================ */

SELECT
    COUNT(*) AS freight_negativo
FROM silver.order_items
WHERE freight_value < 0;
GO


/* ============================================================
   CONTROL DE CALIDAD 11
   PRECIOS IGUALES A CERO
   ============================================================

   Un valor cero no necesariamente debe eliminarse.

   Primero lo medimos.

   Si existen registros, posteriormente analizamos si son
   válidos o representan anomalías.
   ============================================================ */

SELECT
    COUNT(*) AS precios_cero
FROM silver.order_items
WHERE price = 0;
GO


/* ============================================================
   CONTROL DE CALIDAD 12
   FREIGHT IGUAL A CERO
   ============================================================

   Freight = 0 puede ser perfectamente válido.

   Por ejemplo, podría representar envío gratuito.

   Por lo tanto NO lo consideramos automáticamente un error.
   Solo medimos cuántos casos existen.
   ============================================================ */

SELECT
    COUNT(*) AS freight_cero
FROM silver.order_items
WHERE freight_value = 0;
GO


/* ============================================================
   CONTROL DE CALIDAD 13
   INTEGRIDAD REFERENCIAL CON ORDERS
   ============================================================

   Verificamos que cada order_id existente en order_items
   tenga una orden correspondiente en silver.orders.

   LEFT JOIN:
   conserva todos los order_items.

   WHERE o.order_id IS NULL:
   identifica items sin una orden existente.

   DIMENSIÓN:
   Integridad referencial.

   RESULTADO ESPERADO:
   0
   ============================================================ */

SELECT
    COUNT(*) AS items_sin_orden
FROM silver.order_items oi

LEFT JOIN silver.orders o
    ON oi.order_id = o.order_id

WHERE o.order_id IS NULL;
GO


/* ============================================================
   CONTROL DE CALIDAD 14
   CANTIDAD DE ÓRDENES REPRESENTADAS
   ============================================================

   COUNT(DISTINCT order_id) indica cuántas órdenes diferentes
   aparecen en order_items.

   No necesariamente tiene que ser igual a 99,441 porque
   puede haber órdenes canceladas o no disponibles que nunca
   llegaron a tener items registrados.
   ============================================================ */

SELECT
    COUNT(DISTINCT order_id) AS ordenes_con_items
FROM silver.order_items;
GO


/* ============================================================
   CONTROL EXPLORATORIO
   NÚMERO DE ITEMS POR ORDEN
   ============================================================

   Esta consulta permite comenzar a entender la granularidad
   de la tabla.

   Una orden puede tener uno o múltiples items.

   Posteriormente esta información se utilizará para crear
   la variable Gold:

       numero_items
   ============================================================ */

SELECT TOP 20
    order_id,
    COUNT(*) AS numero_items
FROM silver.order_items
GROUP BY order_id
ORDER BY COUNT(*) DESC;
GO


/* ============================================================
   CONTROL EXPLORATORIO
   NÚMERO DE VENDEDORES POR ORDEN
   ============================================================

   Una orden puede contener productos vendidos por diferentes
   vendedores.

   Esta información posteriormente permitirá crear:

       numero_vendedores
   ============================================================ */

SELECT TOP 20
    order_id,
    COUNT(DISTINCT seller_id) AS numero_vendedores
FROM silver.order_items
GROUP BY order_id
ORDER BY COUNT(DISTINCT seller_id) DESC;
GO


/* ============================================================
   PASO 6
   CREAR PRIMARY KEY COMPUESTA
   ============================================================

   En esta tabla NO utilizamos únicamente order_id.

   La clave primaria estará formada por:

       order_id
       +
       order_item_id

   Esto se denomina:

       PRIMARY KEY COMPUESTA

   La combinación de ambas columnas identifica de manera
   única cada item de cada orden.
   ============================================================ */

ALTER TABLE silver.order_items
ADD CONSTRAINT PK_silver_order_items
PRIMARY KEY
(
    order_id,
    order_item_id
);
GO


/* ============================================================
   PASO 7
   CREAR FOREIGN KEY CON ORDERS
   ============================================================

   Ahora establecemos formalmente la relación:

   silver.order_items.order_id
                 ↓
   silver.orders.order_id

   Esto garantiza que no puedan existir items asociados
   a órdenes inexistentes.
   ============================================================ */

ALTER TABLE silver.order_items
ADD CONSTRAINT FK_silver_order_items_orders
FOREIGN KEY (order_id)
REFERENCES silver.orders(order_id);
GO


/* ============================================================
   PASO 8
   VERIFICAR PRIMARY KEY
   ============================================================

   Como la PK tiene dos columnas, esta consulta debería
   devolver:

   PK_silver_order_items     order_id
   PK_silver_order_items     order_item_id
   ============================================================ */

SELECT
    kc.name AS nombre_clave,
    c.name AS columna

FROM sys.key_constraints kc

JOIN sys.index_columns ic
    ON kc.parent_object_id = ic.object_id
    AND kc.unique_index_id = ic.index_id

JOIN sys.columns c
    ON ic.object_id = c.object_id
    AND ic.column_id = c.column_id

WHERE kc.parent_object_id =
      OBJECT_ID('silver.order_items')

  AND kc.type = 'PK'

ORDER BY ic.key_ordinal;
GO


/* ============================================================
   PASO 9
   VERIFICAR FOREIGN KEY
   ============================================================ */

SELECT
    fk.name AS nombre_foreign_key,

    OBJECT_NAME(fk.parent_object_id)
        AS tabla_origen,

    COL_NAME(
        fkc.parent_object_id,
        fkc.parent_column_id
    ) AS columna_origen,

    OBJECT_NAME(fk.referenced_object_id)
        AS tabla_destino,

    COL_NAME(
        fkc.referenced_object_id,
        fkc.referenced_column_id
    ) AS columna_destino

FROM sys.foreign_keys fk

JOIN sys.foreign_key_columns fkc
    ON fk.object_id = fkc.constraint_object_id

WHERE fk.parent_object_id =
      OBJECT_ID('silver.order_items');
GO


/* ========================================================================
   ETAPA: 07 - Silver Order Payments
   ARCHIVO ORIGINAL: Proyecto Pyments silver.sql
========================================================================= */

/* ============================================================
   PROYECTO OLIST
   CAPA SILVER - TABLA ORDER_PAYMENTS

   ORIGEN:
       bronze.olist_order_payments_dataset

   DESTINO:
       silver.order_payments

   OBJETIVO:
   Limpiar y preparar la información de pagos.

   RELACIONES:
       order_payments.order_id
                    ↓
              orders.order_id

   CLAVE PRIMARIA:
       order_id + payment_sequential

   Esto es una CLAVE PRIMARIA COMPUESTA porque una orden
   puede tener más de un pago.
   ============================================================ */


-- ============================================================
-- 1. SELECCIONAR LA BASE DE DATOS
-- ============================================================

USE OLIST_DW;
GO


-- ============================================================
-- 2. ELIMINAR SILVER.ORDER_PAYMENTS SI YA EXISTE
-- ============================================================

-- Esto permite volver a ejecutar todo el proceso desde cero
-- si necesitamos corregir o reconstruir la tabla.

DROP TABLE IF EXISTS silver.order_payments;
GO


-- ============================================================
-- 3. CREAR LA TABLA SILVER.ORDER_PAYMENTS
-- ============================================================

CREATE TABLE silver.order_payments
(
    -- Identificador de la orden.
    -- Permitirá relacionar el pago con silver.orders.
    order_id NVARCHAR(50) NOT NULL,

    -- Número secuencial del pago dentro de una orden.
    -- Una misma orden puede tener pago 1, pago 2, etc.
    payment_sequential INT NOT NULL,

    -- Tipo o método de pago.
    -- Ejemplos:
    -- credit_card
    -- boleto
    -- voucher
    -- debit_card
    payment_type NVARCHAR(50) NULL,

    -- Cantidad de cuotas utilizadas para realizar el pago.
    payment_installments INT NULL,

    -- Valor monetario del pago.
    -- Usamos DECIMAL en Silver en lugar de FLOAT porque
    -- estamos trabajando con valores monetarios.
    payment_value DECIMAL(18,2) NULL
);
GO


-- ============================================================
-- 4. CARGAR DATOS DE BRONZE A SILVER
-- ============================================================

INSERT INTO silver.order_payments
(
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
)
SELECT

    -- Eliminamos espacios al inicio/final.
    -- Si hubiera una cadena vacía, NULLIF la convierte en NULL.
    NULLIF(LTRIM(RTRIM(order_id)), ''),

    -- Convertimos el secuencial del pago a entero.
    TRY_CONVERT(INT, payment_sequential),

    -- Limpiamos el texto correspondiente al tipo de pago.
    NULLIF(LTRIM(RTRIM(payment_type)), ''),

    -- Convertimos las cuotas a entero.
    TRY_CONVERT(INT, payment_installments),

    -- Convertimos el valor del pago a DECIMAL.
    -- Esto es más apropiado para importes monetarios que FLOAT.
    TRY_CONVERT(DECIMAL(18,2), payment_value)

FROM bronze.olist_order_payments_dataset;
GO


-- ============================================================
-- 5. COMPARAR CANTIDAD DE REGISTROS
-- ============================================================

-- Cantidad original en Bronze.

SELECT
    COUNT(*) AS registros_bronze
FROM bronze.olist_order_payments_dataset;
GO


-- Cantidad después de pasar a Silver.

SELECT
    COUNT(*) AS registros_silver
FROM silver.order_payments;
GO


-- En tu carga inicial de OLIST teníamos:
-- 103886 registros en Bronze.
--
-- Por lo tanto esperamos que Silver conserve:
-- 103886 registros.


-- ============================================================
-- 6. MOSTRAR LOS PRIMEROS 10 PAGOS
-- ============================================================

SELECT TOP 10 *
FROM silver.order_payments;
GO


-- ============================================================
-- 7. VALIDAR ORDER_ID NULOS
-- ============================================================

-- order_id no puede ser NULL porque formará parte
-- de la clave primaria y de la relación con orders.

SELECT
    COUNT(*) AS order_id_nulos
FROM silver.order_payments
WHERE order_id IS NULL;
GO


-- Resultado esperado:
-- 0


-- ============================================================
-- 8. VALIDAR PAYMENT_SEQUENTIAL NULOS
-- ============================================================

-- payment_sequential tampoco puede ser NULL porque
-- será la segunda columna de la clave primaria compuesta.

SELECT
    COUNT(*) AS payment_sequential_nulos
FROM silver.order_payments
WHERE payment_sequential IS NULL;
GO


-- Resultado esperado:
-- 0


-- ============================================================
-- 9. BUSCAR DUPLICADOS EN LA FUTURA CLAVE PRIMARIA
-- ============================================================

-- IMPORTANTE:
--
-- order_id puede repetirse.
--
-- Eso NO es un error porque una orden puede tener varios pagos.
--
-- Lo que NO puede repetirse es la combinación:
--
-- order_id + payment_sequential

SELECT
    order_id,
    payment_sequential,
    COUNT(*) AS cantidad
FROM silver.order_payments
GROUP BY
    order_id,
    payment_sequential
HAVING COUNT(*) > 1;
GO


-- Resultado esperado:
-- 0 filas.
--
-- Si no aparece ningún registro podremos utilizar
-- ambas columnas como clave primaria compuesta.


-- ============================================================
-- 10. VALIDAR PAYMENT_TYPE NULOS
-- ============================================================

SELECT
    COUNT(*) AS payment_type_nulos
FROM silver.order_payments
WHERE payment_type IS NULL;
GO


-- ============================================================
-- 11. REVISAR LOS TIPOS DE PAGO
-- ============================================================

-- Nos permite conocer los métodos de pago presentes
-- en el conjunto de datos.

SELECT
    payment_type,
    COUNT(*) AS cantidad
FROM silver.order_payments
GROUP BY payment_type
ORDER BY COUNT(*) DESC;
GO


-- Aquí deberían aparecer valores como:
--
-- credit_card
-- boleto
-- voucher
-- debit_card
-- not_defined


-- ============================================================
-- 12. VALIDAR CUOTAS NULAS
-- ============================================================

SELECT
    COUNT(*) AS cuotas_nulas
FROM silver.order_payments
WHERE payment_installments IS NULL;
GO


-- ============================================================
-- 13. BUSCAR CUOTAS NEGATIVAS
-- ============================================================

-- Una cantidad negativa de cuotas sería un dato inconsistente.

SELECT
    COUNT(*) AS cuotas_negativas
FROM silver.order_payments
WHERE payment_installments < 0;
GO


-- Resultado esperado:
-- 0


-- ============================================================
-- 14. BUSCAR PAGOS CON 0 CUOTAS
-- ============================================================

-- No los eliminamos.
-- Únicamente queremos saber cuántos existen.

SELECT
    COUNT(*) AS cuotas_cero
FROM silver.order_payments
WHERE payment_installments = 0;
GO


-- ============================================================
-- 15. VALIDAR PAYMENT_VALUE NULOS
-- ============================================================

SELECT
    COUNT(*) AS valor_pago_nulo
FROM silver.order_payments
WHERE payment_value IS NULL;
GO


-- ============================================================
-- 16. BUSCAR VALORES DE PAGO NEGATIVOS
-- ============================================================

-- Un pago negativo sería un dato que deberíamos investigar.

SELECT
    COUNT(*) AS pagos_negativos
FROM silver.order_payments
WHERE payment_value < 0;
GO


-- Resultado esperado:
-- 0


-- ============================================================
-- 17. BUSCAR PAGOS IGUALES A CERO
-- ============================================================

-- Los detectamos, pero no los eliminamos automáticamente.

SELECT
    COUNT(*) AS pagos_cero
FROM silver.order_payments
WHERE payment_value = 0;
GO


-- ============================================================
-- 18. VALIDAR QUE TODOS LOS PAGOS TENGAN UNA ORDEN
-- ============================================================

-- Esta validación es MUY IMPORTANTE antes de crear
-- la Foreign Key.
--
-- Buscamos pagos cuyo order_id no exista en silver.orders.

SELECT
    COUNT(*) AS pagos_sin_orden
FROM silver.order_payments p

LEFT JOIN silver.orders o
    ON p.order_id = o.order_id

WHERE o.order_id IS NULL;
GO


-- Resultado esperado:
-- 0
--
-- Si obtenemos 0 significa que todos los pagos
-- pertenecen a una orden existente.


-- ============================================================
-- 19. VER ÓRDENES QUE TIENEN MÁS DE UN PAGO
-- ============================================================

-- Esto demuestra por qué order_id por sí solo
-- NO puede ser la Primary Key de esta tabla.

SELECT TOP 20
    order_id,
    COUNT(*) AS numero_pagos
FROM silver.order_payments
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;
GO


-- ============================================================
-- 20. CREAR CLAVE PRIMARIA COMPUESTA
-- ============================================================

-- Ahora sí utilizamos:
--
-- order_id + payment_sequential
--
-- como una sola clave primaria lógica.

ALTER TABLE silver.order_payments
ADD CONSTRAINT PK_silver_order_payments
PRIMARY KEY
(
    order_id,
    payment_sequential
);
GO


-- ============================================================
-- 21. CREAR FOREIGN KEY HACIA SILVER.ORDERS
-- ============================================================

-- Creamos la relación:
--
-- order_payments.order_id
--          ↓
-- orders.order_id

ALTER TABLE silver.order_payments
ADD CONSTRAINT FK_silver_order_payments_orders
FOREIGN KEY (order_id)
REFERENCES silver.orders(order_id);
GO


-- ============================================================
-- 22. VERIFICAR LA PRIMARY KEY
-- ============================================================

-- Como la clave es compuesta, esperamos obtener DOS FILAS:
--
-- order_id
-- payment_sequential

SELECT
    kc.name AS nombre_clave,
    c.name AS columna
FROM sys.key_constraints kc

JOIN sys.index_columns ic
    ON kc.parent_object_id = ic.object_id
    AND kc.unique_index_id = ic.index_id

JOIN sys.columns c
    ON ic.object_id = c.object_id
    AND ic.column_id = c.column_id

WHERE kc.parent_object_id =
      OBJECT_ID('silver.order_payments')

AND kc.type = 'PK'

ORDER BY ic.key_ordinal;
GO


-- ============================================================
-- 23. VERIFICAR LA FOREIGN KEY
-- ============================================================

-- Esta consulta nos permite comprobar que order_payments
-- quedó relacionado correctamente con orders.

SELECT
    fk.name AS nombre_foreign_key,

    OBJECT_NAME(fk.parent_object_id)
        AS tabla_origen,

    COL_NAME(
        fkc.parent_object_id,
        fkc.parent_column_id
    ) AS columna_origen,

    OBJECT_NAME(fk.referenced_object_id)
        AS tabla_destino,

    COL_NAME(
        fkc.referenced_object_id,
        fkc.referenced_column_id
    ) AS columna_destino

FROM sys.foreign_keys fk

JOIN sys.foreign_key_columns fkc
    ON fk.object_id = fkc.constraint_object_id

WHERE fk.parent_object_id =
      OBJECT_ID('silver.order_payments');
GO


/* ========================================================================
   ETAPA: 08 - Validación integral Silver
   ARCHIVO ORIGINAL: Proyecto validacion silver.sql
========================================================================= */

/*====================================================================
 PROYECTO OLIST
 VALIDACIÓN INTEGRAL DE LA CAPA SILVER

 Base de datos: OLIST_DW

 Objetivo:
 Verificar que las 6 tablas de la capa Silver quedaron correctamente
 construidas después del proceso de limpieza realizado desde Bronze.

 Tablas que vamos a validar:
   1. silver.customers
   2. silver.orders
   3. silver.order_items
   4. silver.products
   5. silver.sellers
   6. silver.order_payments

 Validaremos:
   - Cantidad de registros
   - Claves primarias (PK)
   - Claves foráneas (FK)
   - Registros huérfanos
   - Integridad general de los datos
====================================================================*/


/*====================================================================
 0. SELECCIONAR LA BASE DE DATOS
====================================================================*/

USE OLIST_DW;
GO


/*====================================================================
 1. VALIDAR QUE EXISTAN LAS 6 TABLAS SILVER

 OBJECT_ID busca el objeto dentro de SQL Server.

 Si la tabla existe:
     OBJECT_ID devuelve un identificador.

 Si no existe:
     devuelve NULL.

 El resultado esperado es:
     EXISTE para las 6 tablas.
====================================================================*/

SELECT
    'silver.customers' AS tabla,
    CASE
        WHEN OBJECT_ID('silver.customers', 'U') IS NOT NULL
            THEN 'EXISTE'
        ELSE 'NO EXISTE'
    END AS estado

UNION ALL

SELECT
    'silver.orders',
    CASE
        WHEN OBJECT_ID('silver.orders', 'U') IS NOT NULL
            THEN 'EXISTE'
        ELSE 'NO EXISTE'
    END

UNION ALL

SELECT
    'silver.order_items',
    CASE
        WHEN OBJECT_ID('silver.order_items', 'U') IS NOT NULL
            THEN 'EXISTE'
        ELSE 'NO EXISTE'
    END

UNION ALL

SELECT
    'silver.products',
    CASE
        WHEN OBJECT_ID('silver.products', 'U') IS NOT NULL
            THEN 'EXISTE'
        ELSE 'NO EXISTE'
    END

UNION ALL

SELECT
    'silver.sellers',
    CASE
        WHEN OBJECT_ID('silver.sellers', 'U') IS NOT NULL
            THEN 'EXISTE'
        ELSE 'NO EXISTE'
    END

UNION ALL

SELECT
    'silver.order_payments',
    CASE
        WHEN OBJECT_ID('silver.order_payments', 'U') IS NOT NULL
            THEN 'EXISTE'
        ELSE 'NO EXISTE'
    END;
GO


/*====================================================================
 2. CONTAR LOS REGISTROS DE CADA TABLA SILVER

 COUNT(*) cuenta todas las filas existentes en cada tabla.

 Esto permite comprobar que las tablas contienen información y
 comparar posteriormente Silver contra Bronze.
====================================================================*/

SELECT 'customers' AS tabla, COUNT(*) AS registros
FROM silver.customers

UNION ALL

SELECT 'orders', COUNT(*)
FROM silver.orders

UNION ALL

SELECT 'order_items', COUNT(*)
FROM silver.order_items

UNION ALL

SELECT 'products', COUNT(*)
FROM silver.products

UNION ALL

SELECT 'sellers', COUNT(*)
FROM silver.sellers

UNION ALL

SELECT 'order_payments', COUNT(*)
FROM silver.order_payments;
GO


/*====================================================================
 3. COMPARAR LA CANTIDAD DE REGISTROS BRONZE VS SILVER

 Esto nos permite comprobar que durante la transformación no
 desaparecieron registros accidentalmente.

 En nuestro proceso Silver principalmente limpiamos:
   - espacios
   - cadenas vacías
   - tipos de datos
   - valores NULL
   - claves
   - relaciones

 Por lo tanto, esperamos conservar las cantidades originales.
====================================================================*/

SELECT
    'customers' AS tabla,

    (SELECT COUNT(*)
     FROM bronze.olist_customers_dataset) AS registros_bronze,

    (SELECT COUNT(*)
     FROM silver.customers) AS registros_silver

UNION ALL

SELECT
    'orders',

    (SELECT COUNT(*)
     FROM bronze.olist_orders_dataset),

    (SELECT COUNT(*)
     FROM silver.orders)

UNION ALL

SELECT
    'order_items',

    (SELECT COUNT(*)
     FROM bronze.olist_order_items_dataset),

    (SELECT COUNT(*)
     FROM silver.order_items)

UNION ALL

SELECT
    'products',

    (SELECT COUNT(*)
     FROM bronze.olist_products_dataset),

    (SELECT COUNT(*)
     FROM silver.products)

UNION ALL

SELECT
    'sellers',

    (SELECT COUNT(*)
     FROM bronze.olist_sellers_dataset),

    (SELECT COUNT(*)
     FROM silver.sellers)

UNION ALL

SELECT
    'order_payments',

    (SELECT COUNT(*)
     FROM bronze.olist_order_payments_dataset),

    (SELECT COUNT(*)
     FROM silver.order_payments);
GO


/*====================================================================
 4. VALIDAR LAS CLAVES PRIMARIAS DE SILVER

 Una PRIMARY KEY identifica de manera única cada registro.

 sys.key_constraints:
     contiene las restricciones PK creadas.

 sys.tables:
     permite identificar la tabla.

 sys.schemas:
     permite identificar el esquema.

 Resultado esperado:
     customers
     orders
     order_items
     products
     sellers
     order_payments
====================================================================*/

SELECT
    s.name AS esquema,
    t.name AS tabla,
    kc.name AS nombre_clave_primaria
FROM sys.key_constraints kc

INNER JOIN sys.tables t
    ON kc.parent_object_id = t.object_id

INNER JOIN sys.schemas s
    ON t.schema_id = s.schema_id

WHERE
    kc.type = 'PK'
    AND s.name = 'silver'

ORDER BY
    t.name;
GO


/*====================================================================
 5. MOSTRAR LAS COLUMNAS QUE FORMAN CADA PRIMARY KEY

 Esto es especialmente importante porque tenemos claves simples
 y claves compuestas.

 Por ejemplo:

 customers
     customer_id

 orders
     order_id

 order_items
     order_id + order_item_id

 order_payments
     order_id + payment_sequential
====================================================================*/

SELECT
    s.name AS esquema,
    t.name AS tabla,
    kc.name AS nombre_clave,
    c.name AS columna,
    ic.key_ordinal AS posicion_clave

FROM sys.key_constraints kc

INNER JOIN sys.tables t
    ON kc.parent_object_id = t.object_id

INNER JOIN sys.schemas s
    ON t.schema_id = s.schema_id

INNER JOIN sys.index_columns ic
    ON kc.parent_object_id = ic.object_id
    AND kc.unique_index_id = ic.index_id

INNER JOIN sys.columns c
    ON ic.object_id = c.object_id
    AND ic.column_id = c.column_id

WHERE
    kc.type = 'PK'
    AND s.name = 'silver'

ORDER BY
    t.name,
    ic.key_ordinal;
GO


/*====================================================================
 6. VALIDAR TODAS LAS FOREIGN KEYS DE SILVER

 Las FOREIGN KEY establecen las relaciones entre las tablas.

 Ejemplos:

 orders.customer_id
          ↓
 customers.customer_id


 order_items.order_id
          ↓
 orders.order_id


 order_payments.order_id
          ↓
 orders.order_id
====================================================================*/

SELECT
    fk.name AS nombre_foreign_key,

    OBJECT_SCHEMA_NAME(fk.parent_object_id)
        AS esquema_origen,

    OBJECT_NAME(fk.parent_object_id)
        AS tabla_origen,

    COL_NAME(
        fkc.parent_object_id,
        fkc.parent_column_id
    ) AS columna_origen,

    OBJECT_SCHEMA_NAME(fk.referenced_object_id)
        AS esquema_destino,

    OBJECT_NAME(fk.referenced_object_id)
        AS tabla_destino,

    COL_NAME(
        fkc.referenced_object_id,
        fkc.referenced_column_id
    ) AS columna_destino

FROM sys.foreign_keys fk

INNER JOIN sys.foreign_key_columns fkc
    ON fk.object_id = fkc.constraint_object_id

WHERE
    OBJECT_SCHEMA_NAME(fk.parent_object_id) = 'silver'

ORDER BY
    tabla_origen,
    nombre_foreign_key;
GO


/*====================================================================
 7. VALIDAR ÓRDENES SIN CLIENTE

 Comprobamos que todo customer_id utilizado por orders exista
 realmente en silver.customers.

 Resultado esperado:
     0

 Si devuelve 0:
     no existen órdenes huérfanas.
====================================================================*/

SELECT
    COUNT(*) AS ordenes_sin_cliente
FROM silver.orders o

LEFT JOIN silver.customers c
    ON o.customer_id = c.customer_id

WHERE c.customer_id IS NULL;
GO


/*====================================================================
 8. VALIDAR ITEMS SIN ORDEN

 Cada item debe pertenecer a una orden existente.

 Resultado esperado:
     0
====================================================================*/

SELECT
    COUNT(*) AS items_sin_orden
FROM silver.order_items oi

LEFT JOIN silver.orders o
    ON oi.order_id = o.order_id

WHERE o.order_id IS NULL;
GO


/*====================================================================
 9. VALIDAR ITEMS CON PRODUCTOS INEXISTENTES

 Cada product_id utilizado en order_items debería existir
 en silver.products.

 Resultado esperado:
     0
====================================================================*/

SELECT
    COUNT(*) AS items_sin_producto
FROM silver.order_items oi

LEFT JOIN silver.products p
    ON oi.product_id = p.product_id

WHERE p.product_id IS NULL;
GO


/*====================================================================
 10. VALIDAR ITEMS CON VENDEDORES INEXISTENTES

 Cada seller_id utilizado en order_items debería existir
 en silver.sellers.

 Resultado esperado:
     0
====================================================================*/

SELECT
    COUNT(*) AS items_sin_vendedor
FROM silver.order_items oi

LEFT JOIN silver.sellers s
    ON oi.seller_id = s.seller_id

WHERE s.seller_id IS NULL;
GO


/*====================================================================
 11. VALIDAR PAGOS SIN ORDEN

 Cada pago debe corresponder a una orden existente.

 Ya realizamos esta validación individualmente y obtuvimos 0,
 pero ahora la incorporamos a la validación integral.

 Resultado esperado:
     0
====================================================================*/

SELECT
    COUNT(*) AS pagos_sin_orden
FROM silver.order_payments op

LEFT JOIN silver.orders o
    ON op.order_id = o.order_id

WHERE o.order_id IS NULL;
GO


/*====================================================================
 12. VALIDAR DUPLICADOS EN CUSTOMERS

 customer_id es PRIMARY KEY.

 Por lo tanto, no debe existir ningún customer_id repetido.

 Resultado esperado:
     0 filas.
====================================================================*/

SELECT
    customer_id,
    COUNT(*) AS cantidad
FROM silver.customers

GROUP BY
    customer_id

HAVING COUNT(*) > 1;
GO


/*====================================================================
 13. VALIDAR DUPLICADOS EN ORDERS

 order_id identifica de manera única una orden.

 Resultado esperado:
     0 filas.
====================================================================*/

SELECT
    order_id,
    COUNT(*) AS cantidad
FROM silver.orders

GROUP BY
    order_id

HAVING COUNT(*) > 1;
GO


/*====================================================================
 14. VALIDAR DUPLICADOS EN ORDER_ITEMS

 Aquí la clave es COMPUESTA:

     order_id
     +
     order_item_id

 Puede existir un mismo order_id varias veces porque una orden
 puede tener varios productos.

 Lo que NO puede repetirse es exactamente la combinación:

     order_id + order_item_id

 Resultado esperado:
     0 filas.
====================================================================*/

SELECT
    order_id,
    order_item_id,
    COUNT(*) AS cantidad
FROM silver.order_items

GROUP BY
    order_id,
    order_item_id

HAVING COUNT(*) > 1;
GO


/*====================================================================
 15. VALIDAR DUPLICADOS EN PRODUCTS

 product_id debe ser único.

 Resultado esperado:
     0 filas.
====================================================================*/

SELECT
    product_id,
    COUNT(*) AS cantidad
FROM silver.products

GROUP BY
    product_id

HAVING COUNT(*) > 1;
GO


/*====================================================================
 16. VALIDAR DUPLICADOS EN SELLERS

 seller_id debe ser único.

 Resultado esperado:
     0 filas.
====================================================================*/

SELECT
    seller_id,
    COUNT(*) AS cantidad
FROM silver.sellers

GROUP BY
    seller_id

HAVING COUNT(*) > 1;
GO


/*====================================================================
 17. VALIDAR DUPLICADOS EN ORDER_PAYMENTS

 Una orden puede tener más de un pago.

 Por eso NO utilizamos únicamente order_id como PK.

 La identificación del pago está formada por:

     order_id
     +
     payment_sequential

 Resultado esperado:
     0 filas.
====================================================================*/

SELECT
    order_id,
    payment_sequential,
    COUNT(*) AS cantidad
FROM silver.order_payments

GROUP BY
    order_id,
    payment_sequential

HAVING COUNT(*) > 1;
GO


/*====================================================================
 18. VALIDACIÓN GENERAL DE RELACIONES

 Esta consulta resume las principales relaciones del modelo.

 Idealmente todos estos indicadores deben devolver 0.
====================================================================*/

SELECT
    'Ordenes sin cliente' AS validacion,
    COUNT(*) AS cantidad

FROM silver.orders o

LEFT JOIN silver.customers c
    ON o.customer_id = c.customer_id

WHERE c.customer_id IS NULL


UNION ALL


SELECT
    'Items sin orden',
    COUNT(*)

FROM silver.order_items oi

LEFT JOIN silver.orders o
    ON oi.order_id = o.order_id

WHERE o.order_id IS NULL


UNION ALL


SELECT
    'Items sin producto',
    COUNT(*)

FROM silver.order_items oi

LEFT JOIN silver.products p
    ON oi.product_id = p.product_id

WHERE p.product_id IS NULL


UNION ALL


SELECT
    'Items sin vendedor',
    COUNT(*)

FROM silver.order_items oi

LEFT JOIN silver.sellers s
    ON oi.seller_id = s.seller_id

WHERE s.seller_id IS NULL


UNION ALL


SELECT
    'Pagos sin orden',
    COUNT(*)

FROM silver.order_payments op

LEFT JOIN silver.orders o
    ON op.order_id = o.order_id

WHERE o.order_id IS NULL;
GO


/*====================================================================
 19. RESUMEN FINAL DE LAS 6 TABLAS

 Esta última consulta muestra de manera sencilla las tablas y
 cantidades con las que terminamos la capa Silver.

 Será útil posteriormente cuando construyamos Gold.
====================================================================*/

SELECT
    'silver.customers' AS tabla,
    COUNT(*) AS registros
FROM silver.customers

UNION ALL

SELECT
    'silver.orders',
    COUNT(*)
FROM silver.orders

UNION ALL

SELECT
    'silver.order_items',
    COUNT(*)
FROM silver.order_items

UNION ALL

SELECT
    'silver.products',
    COUNT(*)
FROM silver.products

UNION ALL

SELECT
    'silver.sellers',
    COUNT(*)
FROM silver.sellers

UNION ALL

SELECT
    'silver.order_payments',
    COUNT(*)
FROM silver.order_payments;
GO


/* ========================================================================
   ETAPA: 09 - Revisión de tipos de datos
   ARCHIVO ORIGINAL: Proyecto tipos de datos.sql
========================================================================= */

USE OLIST_DW;
GO

/*====================================================================
 PROYECTO 2 - DETECCIÓN DE ANOMALÍAS
 PASO 1 DE GOLD

 OBJETIVO:
 Revisar las columnas y tipos de datos disponibles en las 6 tablas
 Silver antes de construir gold.order_anomaly_features.

 IMPORTANTE:
 En este paso NO modificamos datos.
 Solamente consultamos la estructura existente.
====================================================================*/


/*====================================================================
 1. CUSTOMERS

 Nos interesa especialmente:
 - Identificación del cliente
 - Código postal
 - Ciudad
 - Estado

 Estos datos servirán posteriormente para variables geográficas.
====================================================================*/

SELECT
    COLUMN_NAME AS columna,
    DATA_TYPE AS tipo_dato
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'silver'
  AND TABLE_NAME = 'customers'
ORDER BY ORDINAL_POSITION;
GO


/*====================================================================
 2. ORDERS

 Esta será la tabla principal del modelo porque queremos obtener
 UNA FILA POR ORDEN.

 Nos interesan:
 - order_id
 - customer_id
 - estado
 - fecha de compra
 - aprobación
 - despacho
 - entrega
 - fecha estimada

 Con estas fechas calcularemos tiempos logísticos.
====================================================================*/

SELECT
    COLUMN_NAME AS columna,
    DATA_TYPE AS tipo_dato
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'silver'
  AND TABLE_NAME = 'orders'
ORDER BY ORDINAL_POSITION;
GO


/*====================================================================
 3. ORDER_ITEMS

 Aquí tenemos el detalle de los productos incluidos en cada orden.

 Nos interesa:
 - order_id
 - producto
 - vendedor
 - precio
 - freight
 - fecha límite de envío

 Esta tabla tiene VARIAS filas por orden.

 Por eso después tendremos que AGRUPARLA por order_id antes de
 combinarla con orders.
====================================================================*/

SELECT
    COLUMN_NAME AS columna,
    DATA_TYPE AS tipo_dato
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'silver'
  AND TABLE_NAME = 'order_items'
ORDER BY ORDINAL_POSITION;
GO


/*====================================================================
 4. PRODUCTS

 Aquí están las características físicas de los productos.

 Nos interesa especialmente:
 - categoría
 - peso
 - largo
 - alto
 - ancho

 Con estas variables podremos calcular:
 - peso agregado de la orden
 - volumen aproximado
====================================================================*/

SELECT
    COLUMN_NAME AS columna,
    DATA_TYPE AS tipo_dato
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'silver'
  AND TABLE_NAME = 'products'
ORDER BY ORDINAL_POSITION;
GO


/*====================================================================
 5. SELLERS

 Contiene información geográfica del vendedor.

 Nos interesa:
 - seller_id
 - código postal
 - ciudad
 - estado

 Esto permitirá comparar la ubicación del vendedor con la
 ubicación del cliente.
====================================================================*/

SELECT
    COLUMN_NAME AS columna,
    DATA_TYPE AS tipo_dato
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'silver'
  AND TABLE_NAME = 'sellers'
ORDER BY ORDINAL_POSITION;
GO


/*====================================================================
 6. ORDER_PAYMENTS

 Una orden puede tener uno o varios registros de pago.

 Nos interesa:
 - order_id
 - secuencia de pago
 - tipo de pago
 - número de cuotas
 - valor pagado

 Después tendremos que AGRUPAR estos registros por order_id para
 mantener una sola fila por orden.
====================================================================*/

SELECT
    COLUMN_NAME AS columna,
    DATA_TYPE AS tipo_dato
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'silver'
  AND TABLE_NAME = 'order_payments'
ORDER BY ORDINAL_POSITION;
GO


/* ========================================================================
   ETAPA: 10 - Construcción tabla Gold de características
   ARCHIVO ORIGINAL: Proyecto tabla gold.sql
========================================================================= */

USE OLIST_DW;
GO

/*====================================================================
 PROYECTO 2 - DETECCIÓN DE ANOMALÍAS
 CAPA GOLD

 TABLA:
 gold.order_anomaly_features

 OBJETIVO:
 Construir el dataset analítico que posteriormente utilizaremos para
 detectar órdenes con comportamientos atípicos.

 GRANULARIDAD:
 UNA FILA = UNA ORDEN (order_id)

 FUENTES SILVER:
 - silver.orders
 - silver.customers
 - silver.order_items
 - silver.products
 - silver.sellers
 - silver.order_payments
====================================================================*/


/*====================================================================
 PASO 1. ELIMINAR LA TABLA GOLD SI YA EXISTE

 Esto nos permite volver a ejecutar el script durante el desarrollo
 sin obtener el error "table already exists".
====================================================================*/

DROP TABLE IF EXISTS gold.order_anomaly_features;
GO


/*====================================================================
 PASO 2. AGREGAR INFORMACIÓN DE PRODUCTOS E ITEMS

 IMPORTANTE:

 order_items NO tiene una fila por orden.

 Ejemplo:

 order_id     item
 --------     ----
 A001           1
 A001           2
 A001           3

 Si hiciéramos un JOIN directamente, tendríamos varias filas para
 A001.

 Por eso agrupamos primero por order_id.

 También unimos PRODUCTS porque allí se encuentran:
 - peso
 - largo
 - alto
 - ancho

 Estas variables pueden ayudar a identificar órdenes físicamente
 atípicas.
====================================================================*/

WITH items_agregados AS
(
    SELECT
        oi.order_id,

        /*------------------------------------------------------------
          Cantidad total de items de la orden
        ------------------------------------------------------------*/
        COUNT(*) AS numero_items,


        /*------------------------------------------------------------
          Cantidad de productos diferentes
        ------------------------------------------------------------*/
        COUNT(DISTINCT oi.product_id) AS numero_productos_distintos,


        /*------------------------------------------------------------
          Cantidad de vendedores involucrados en la orden
        ------------------------------------------------------------*/
        COUNT(DISTINCT oi.seller_id) AS numero_vendedores,


        /*------------------------------------------------------------
          Suma del precio de todos los productos
        ------------------------------------------------------------*/
        SUM(oi.price) AS precio_productos,


        /*------------------------------------------------------------
          Suma del costo de transporte
        ------------------------------------------------------------*/
        SUM(oi.freight_value) AS freight_total,


        /*------------------------------------------------------------
          Peso total aproximado de los productos de la orden

          Si algún producto no tiene peso, COALESCE lo convierte
          temporalmente en 0 para realizar la suma.
        ------------------------------------------------------------*/
        SUM(
            COALESCE(p.product_weight_g, 0)
        ) AS peso_total_g,


        /*------------------------------------------------------------
          Volumen total aproximado.

          Volumen =
          largo × alto × ancho

          La unidad resultante será cm³.
        ------------------------------------------------------------*/
        SUM(
            COALESCE(p.product_length_cm, 0) *
            COALESCE(p.product_height_cm, 0) *
            COALESCE(p.product_width_cm, 0)
        ) AS volumen_total_cm3

    FROM silver.order_items oi

    /*--------------------------------------------------------------
      Relacionamos cada item con su producto para obtener sus
      características físicas.
    --------------------------------------------------------------*/
    LEFT JOIN silver.products p
        ON oi.product_id = p.product_id

    /*--------------------------------------------------------------
      Dejamos finalmente UNA FILA POR ORDEN.
    --------------------------------------------------------------*/
    GROUP BY oi.order_id
),


/*====================================================================
 PASO 3. AGREGAR LOS PAGOS

 order_payments tampoco tiene necesariamente una fila por orden.

 Una orden puede tener varios registros de pago.

 Ejemplo:

 Orden     Pago
 A001      tarjeta
 A001      voucher

 Por eso también debemos agrupar antes de unirla con orders.
====================================================================*/

pagos_agregados AS
(
    SELECT
        op.order_id,


        /*------------------------------------------------------------
          Número de registros de pago asociados con la orden
        ------------------------------------------------------------*/
        COUNT(*) AS numero_pagos,


        /*------------------------------------------------------------
          Número de tipos de pago diferentes utilizados
        ------------------------------------------------------------*/
        COUNT(DISTINCT op.payment_type) AS tipos_pago_distintos,


        /*------------------------------------------------------------
          Mayor número de cuotas encontrado en la orden.

          Puede ser útil para detectar órdenes con financiamiento
          inusual.
        ------------------------------------------------------------*/
        MAX(op.payment_installments) AS max_cuotas,


        /*------------------------------------------------------------
          Valor total registrado en payments
        ------------------------------------------------------------*/
        SUM(op.payment_value) AS monto_pagado

    FROM silver.order_payments op

    GROUP BY op.order_id
),


/*====================================================================
 PASO 4. IDENTIFICAR INFORMACIÓN DEL VENDEDOR

 Una orden puede tener múltiples vendedores.

 Para disponer de una referencia geográfica sencilla tomamos
 información del vendedor cuando la orden tiene items asociados.

 NOTA:
 Esto NO calcula todavía una distancia geográfica real.
====================================================================*/

vendedor_orden AS
(
    SELECT
        oi.order_id,

        /*------------------------------------------------------------
          Cuando existen varios vendedores utilizamos MIN únicamente
          para obtener una referencia reproducible.

          numero_vendedores, calculado anteriormente, nos permitirá
          saber si la orden realmente tiene más de uno.
        ------------------------------------------------------------*/
        MIN(s.seller_state) AS seller_state_referencia,

        MIN(s.seller_zip_code_prefix) AS seller_zip_referencia

    FROM silver.order_items oi

    LEFT JOIN silver.sellers s
        ON oi.seller_id = s.seller_id

    GROUP BY oi.order_id
)


/*====================================================================
 PASO 5. CONSTRUIR LA TABLA GOLD

 ORDERS será nuestra tabla base porque el objetivo del proyecto
 consiste en analizar anomalías a nivel de orden.

 Cada registro de orders generará como máximo una fila en Gold.
====================================================================*/

SELECT

    /*==============================================================
      IDENTIFICADORES
    ================================================================*/

    o.order_id,

    o.customer_id,


    /*==============================================================
      INFORMACIÓN DE LA ORDEN
    ================================================================*/

    o.order_status,

    o.order_purchase_timestamp,

    o.order_approved_at,

    o.order_delivered_carrier_date,

    o.order_delivered_customer_date,

    o.order_estimated_delivery_date,


    /*==============================================================
      INFORMACIÓN DEL CLIENTE
    ================================================================*/

    c.customer_state,

    c.customer_zip_code_prefix,


    /*==============================================================
      INFORMACIÓN DEL VENDEDOR DE REFERENCIA
    ================================================================*/

    vo.seller_state_referencia,

    vo.seller_zip_referencia,


    /*==============================================================
      VARIABLES ECONÓMICAS
    ================================================================*/

    COALESCE(ia.precio_productos, 0)
        AS precio_productos,

    COALESCE(ia.freight_total, 0)
        AS freight_total,


    /*--------------------------------------------------------------
      Costo total de productos + transporte
    --------------------------------------------------------------*/

    COALESCE(ia.precio_productos, 0)
    +
    COALESCE(ia.freight_total, 0)
        AS monto_total_orden,


    /*--------------------------------------------------------------
      Monto registrado en la tabla de pagos
    --------------------------------------------------------------*/

    COALESCE(pa.monto_pagado, 0)
        AS monto_pagado,


    /*==============================================================
      CARACTERÍSTICAS DE LA ORDEN
    ================================================================*/

    COALESCE(ia.numero_items, 0)
        AS numero_items,

    COALESCE(ia.numero_productos_distintos, 0)
        AS numero_productos_distintos,

    COALESCE(ia.numero_vendedores, 0)
        AS numero_vendedores,

    COALESCE(pa.numero_pagos, 0)
        AS numero_pagos,

    COALESCE(pa.tipos_pago_distintos, 0)
        AS tipos_pago_distintos,

    COALESCE(pa.max_cuotas, 0)
        AS max_cuotas,


    /*==============================================================
      VARIABLES FÍSICAS
    ================================================================*/

    COALESCE(ia.peso_total_g, 0)
        AS peso_total_g,

    COALESCE(ia.volumen_total_cm3, 0)
        AS volumen_total_cm3,


    /*==============================================================
      VARIABLE PARA DETECTAR FREIGHT DESPROPORCIONADO

      freight / precio de productos

      Ejemplo:

      Productos = 100
      Freight   = 20

      Resultado = 0.20

      Significa que el transporte representa aproximadamente
      el 20 % del precio de los productos.
    ================================================================*/

    CASE
        WHEN ia.precio_productos > 0
        THEN
            CAST(ia.freight_total AS DECIMAL(18,4))
            /
            NULLIF(
                CAST(ia.precio_productos AS DECIMAL(18,4)),
                0
            )
        ELSE NULL
    END AS proporcion_freight_precio,


    /*==============================================================
      TIEMPO: COMPRA -> APROBACIÓN

      Resultado expresado en HORAS.
    ================================================================*/

    CASE
        WHEN o.order_approved_at IS NOT NULL
        THEN DATEDIFF(
            HOUR,
            o.order_purchase_timestamp,
            o.order_approved_at
        )
        ELSE NULL
    END AS horas_compra_aprobacion,


    /*==============================================================
      TIEMPO: COMPRA -> TRANSPORTISTA
    ================================================================*/

    CASE
        WHEN o.order_delivered_carrier_date IS NOT NULL
        THEN DATEDIFF(
            HOUR,
            o.order_purchase_timestamp,
            o.order_delivered_carrier_date
        )
        ELSE NULL
    END AS horas_compra_transportista,


    /*==============================================================
      TIEMPO: TRANSPORTISTA -> CLIENTE
    ================================================================*/

    CASE
        WHEN o.order_delivered_carrier_date IS NOT NULL
         AND o.order_delivered_customer_date IS NOT NULL
        THEN DATEDIFF(
            HOUR,
            o.order_delivered_carrier_date,
            o.order_delivered_customer_date
        )
        ELSE NULL
    END AS horas_transporte_cliente,


    /*==============================================================
      TIEMPO TOTAL COMPRA -> ENTREGA

      Una duración extremadamente alta podría ser indicio de una
      anomalía logística.
    ================================================================*/

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
        THEN DATEDIFF(
            HOUR,
            o.order_purchase_timestamp,
            o.order_delivered_customer_date
        )
        ELSE NULL
    END AS horas_compra_entrega,


    /*==============================================================
      DIFERENCIA ENTRE ENTREGA REAL Y ENTREGA ESTIMADA

      NEGATIVO = llegó antes de lo esperado
      0        = mismo día
      POSITIVO = llegó después de lo esperado
    ================================================================*/

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
         AND o.order_estimated_delivery_date IS NOT NULL
        THEN DATEDIFF(
            DAY,
            o.order_estimated_delivery_date,
            o.order_delivered_customer_date
        )
        ELSE NULL
    END AS dias_retraso_entrega,


    /*==============================================================
      VARIABLE GEOGRÁFICA SIMPLE

      0 = cliente y vendedor de referencia están en el mismo estado
      1 = están en estados diferentes

      Esto NO representa distancia en kilómetros.
    ================================================================*/

    CASE
        WHEN c.customer_state IS NULL
          OR vo.seller_state_referencia IS NULL
            THEN NULL

        WHEN c.customer_state = vo.seller_state_referencia
            THEN 0

        ELSE 1

    END AS vendedor_otro_estado


/*====================================================================
 INTO crea físicamente nuestra nueva tabla Gold.
====================================================================*/

INTO gold.order_anomaly_features


/*====================================================================
 ORDERS ES LA TABLA PRINCIPAL
====================================================================*/

FROM silver.orders o


/*====================================================================
 Agregamos datos del cliente.
====================================================================*/

LEFT JOIN silver.customers c
    ON o.customer_id = c.customer_id


/*====================================================================
 Agregamos las métricas previamente calculadas de los items.
====================================================================*/

LEFT JOIN items_agregados ia
    ON o.order_id = ia.order_id


/*====================================================================
 Agregamos las métricas de pagos.
====================================================================*/

LEFT JOIN pagos_agregados pa
    ON o.order_id = pa.order_id


/*====================================================================
 Agregamos información geográfica del vendedor.
====================================================================*/

LEFT JOIN vendedor_orden vo
    ON o.order_id = vo.order_id;

GO

USE OLIST_DW;
GO

/*==============================================================
 VALIDACIÓN DE LA TABLA GOLD
 gold.order_anomaly_features
==============================================================*/


/*--------------------------------------------------------------
 1. CONTAR REGISTROS DE GOLD

 Esperado: 99.441 registros.
--------------------------------------------------------------*/
SELECT COUNT(*) AS registros_gold
FROM gold.order_anomaly_features;
GO


/*--------------------------------------------------------------
 2. VERIFICAR DUPLICADOS DE order_id

 Como Gold debe tener UNA FILA POR ORDEN,
 esta consulta debe devolver 0 filas.
--------------------------------------------------------------*/
SELECT
    order_id,
    COUNT(*) AS cantidad
FROM gold.order_anomaly_features
GROUP BY order_id
HAVING COUNT(*) > 1;
GO


/*--------------------------------------------------------------
 3. VERIFICAR ÓRDENES DE SILVER QUE NO LLEGARON A GOLD

 Esperado: 0.
--------------------------------------------------------------*/
SELECT COUNT(*) AS ordenes_silver_sin_gold
FROM silver.orders o
LEFT JOIN gold.order_anomaly_features g
    ON o.order_id = g.order_id
WHERE g.order_id IS NULL;
GO


/*--------------------------------------------------------------
 4. VERIFICAR order_id NULOS

 Esperado: 0.
--------------------------------------------------------------*/
SELECT COUNT(*) AS order_id_nulos
FROM gold.order_anomaly_features
WHERE order_id IS NULL;
GO


/*--------------------------------------------------------------
 5. REVISAR LAS 20 ÓRDENES DE MAYOR VALOR

 Esto ya empieza a ser interesante para nuestro análisis
 de anomalías.
--------------------------------------------------------------*/
SELECT TOP 20
    order_id,
    monto_total_orden,
    precio_productos,
    freight_total,
    proporcion_freight_precio,
    numero_items,
    numero_vendedores,
    numero_pagos,
    max_cuotas,
    peso_total_g,
    volumen_total_cm3,
    horas_compra_entrega,
    dias_retraso_entrega,
    vendedor_otro_estado
FROM gold.order_anomaly_features
ORDER BY monto_total_orden DESC;
GO


/*--------------------------------------------------------------
 6. RESUMEN DE LAS VARIABLES PRINCIPALES

 Nos permitirá conocer los rangos de los datos antes de
 aplicar detección de anomalías.
--------------------------------------------------------------*/
SELECT
    MIN(monto_total_orden) AS monto_minimo,
    MAX(monto_total_orden) AS monto_maximo,
    AVG(monto_total_orden) AS monto_promedio,

    MIN(freight_total) AS freight_minimo,
    MAX(freight_total) AS freight_maximo,
    AVG(freight_total) AS freight_promedio,

    MIN(numero_items) AS items_minimo,
    MAX(numero_items) AS items_maximo,
    AVG(CAST(numero_items AS DECIMAL(18,2))) AS items_promedio,

    MIN(numero_vendedores) AS vendedores_minimo,
    MAX(numero_vendedores) AS vendedores_maximo,

    MIN(numero_pagos) AS pagos_minimo,
    MAX(numero_pagos) AS pagos_maximo,

    MIN(max_cuotas) AS cuotas_minimas,
    MAX(max_cuotas) AS cuotas_maximas

FROM gold.order_anomaly_features;
GO


/* ========================================================================
   ETAPA: 11 - Validaciones de calidad Gold
   ARCHIVO ORIGINAL: Proyecto  validaciones calidad.sql
========================================================================= */

USE OLIST_DW;
GO

/*====================================================================
 PROYECTO 2 - DETECCIÓN DE ANOMALÍAS
 VALIDACIONES DE CALIDAD SOBRE GOLD

 Tabla:
 gold.order_anomaly_features

 Objetivo:
 Identificar valores imposibles o sospechosos ANTES de entrenar
 los modelos de detección de anomalías.

 IMPORTANTE:
 Un registro sospechoso NO se elimina automáticamente.
 Primero se identifica y posteriormente se decide si representa:
   - error de calidad
   - comportamiento válido pero inusual
   - posible anomalía de negocio
====================================================================*/


/*====================================================================
 1. MONTOS NEGATIVOS

 Un precio, freight o pago negativo sería sospechoso.
====================================================================*/

SELECT
    SUM(CASE WHEN precio_productos < 0 THEN 1 ELSE 0 END)
        AS precios_negativos,

    SUM(CASE WHEN freight_total < 0 THEN 1 ELSE 0 END)
        AS freight_negativo,

    SUM(CASE WHEN monto_total_orden < 0 THEN 1 ELSE 0 END)
        AS montos_totales_negativos,

    SUM(CASE WHEN monto_pagado < 0 THEN 1 ELSE 0 END)
        AS pagos_negativos

FROM gold.order_anomaly_features;
GO


/*====================================================================
 2. ÓRDENES CON MONTO TOTAL = 0

 No necesariamente son errores.

 Queremos saber cuántas existen para posteriormente revisar
 su estado y determinar por qué tienen valor cero.
====================================================================*/

SELECT COUNT(*) AS ordenes_monto_cero
FROM gold.order_anomaly_features
WHERE monto_total_orden = 0;
GO


/*====================================================================
 3. REVISAR LAS ÓRDENES CON MONTO CERO

 Aquí veremos si corresponden, por ejemplo, a órdenes canceladas
 o a órdenes que nunca llegaron a tener items.
====================================================================*/

SELECT
    order_status,
    COUNT(*) AS cantidad
FROM gold.order_anomaly_features
WHERE monto_total_orden = 0
GROUP BY order_status
ORDER BY cantidad DESC;
GO


/*====================================================================
 4. ÓRDENES SIN ITEMS

 numero_items = 0 puede ser perfectamente explicable dependiendo
 del estado de la orden.

 No eliminamos nada todavía.
====================================================================*/

SELECT
    order_status,
    COUNT(*) AS cantidad
FROM gold.order_anomaly_features
WHERE numero_items = 0
GROUP BY order_status
ORDER BY cantidad DESC;
GO


/*====================================================================
 5. ÓRDENES SIN PAGOS

 Igual que con los items, queremos conocer su estado.
====================================================================*/

SELECT
    order_status,
    COUNT(*) AS cantidad
FROM gold.order_anomaly_features
WHERE numero_pagos = 0
GROUP BY order_status
ORDER BY cantidad DESC;
GO


/*====================================================================
 6. APROBACIÓN ANTES DE LA COMPRA

 Lógica esperada:

 compra --> aprobación

 Por tanto:

 order_approved_at < order_purchase_timestamp

 sería una inconsistencia temporal.
====================================================================*/

SELECT COUNT(*) AS aprobaciones_antes_compra
FROM gold.order_anomaly_features
WHERE order_approved_at < order_purchase_timestamp;
GO


/*====================================================================
 7. ENTREGA AL TRANSPORTISTA ANTES DE LA COMPRA

 Esto sería temporalmente incoherente.
====================================================================*/

SELECT COUNT(*) AS transportista_antes_compra
FROM gold.order_anomaly_features
WHERE order_delivered_carrier_date < order_purchase_timestamp;
GO


/*====================================================================
 8. ENTREGA AL CLIENTE ANTES DE LA COMPRA

 Esto sería una inconsistencia muy clara.
====================================================================*/

SELECT COUNT(*) AS entrega_cliente_antes_compra
FROM gold.order_anomaly_features
WHERE order_delivered_customer_date < order_purchase_timestamp;
GO


/*====================================================================
 9. ENTREGA AL CLIENTE ANTES DE PASAR AL TRANSPORTISTA

 Secuencia lógica esperada:

 compra
    ↓
 transportista
    ↓
 cliente

 Buscamos casos que rompan esta secuencia.
====================================================================*/

SELECT COUNT(*) AS cliente_antes_transportista
FROM gold.order_anomaly_features
WHERE order_delivered_customer_date <
      order_delivered_carrier_date;
GO


/*====================================================================
 10. APROBACIÓN DESPUÉS DE ENTREGA AL CLIENTE

 Sería una secuencia temporal sospechosa.
====================================================================*/

SELECT COUNT(*) AS aprobacion_despues_entrega
FROM gold.order_anomaly_features
WHERE order_approved_at >
      order_delivered_customer_date;
GO


/*====================================================================
 11. FREIGHT MAYOR QUE EL PRECIO DE LOS PRODUCTOS

 IMPORTANTE:

 Esto NO significa que sea un error.

 Para nuestro proyecto puede ser precisamente una anomalía
 interesante: "freight desproporcionado".
====================================================================*/

SELECT COUNT(*) AS freight_mayor_precio
FROM gold.order_anomaly_features
WHERE freight_total > precio_productos
  AND precio_productos > 0;
GO


/*====================================================================
 12. VER LOS CASOS CON FREIGHT MÁS DESPROPORCIONADO

 Estos casos serán muy útiles posteriormente para explicar
 las anomalías encontradas por Machine Learning.
====================================================================*/

SELECT TOP 20

    order_id,
    order_status,

    precio_productos,
    freight_total,

    proporcion_freight_precio,

    numero_items,
    numero_vendedores,

    peso_total_g,
    volumen_total_cm3,

    customer_state,
    seller_state_referencia

FROM gold.order_anomaly_features

WHERE precio_productos > 0

ORDER BY proporcion_freight_precio DESC;
GO


/*====================================================================
 13. DIFERENCIA ENTRE MONTO DE LA ORDEN Y MONTO PAGADO

 Normalmente esperamos que:

 precio productos + freight
 sea cercano al monto registrado en payments.

 Creamos únicamente una consulta de diagnóstico.
====================================================================*/

SELECT TOP 20

    order_id,

    monto_total_orden,

    monto_pagado,

    ABS(monto_total_orden - monto_pagado)
        AS diferencia_pago,

    numero_pagos,

    tipos_pago_distintos

FROM gold.order_anomaly_features

ORDER BY ABS(monto_total_orden - monto_pagado) DESC;
GO


/*====================================================================
 14. CONTAR ÓRDENES CON DIFERENCIA ENTRE MONTO Y PAGO

 Utilizamos una tolerancia de 0.01 para evitar diferencias
 insignificantes de decimales.
====================================================================*/

SELECT COUNT(*) AS ordenes_diferencia_pago
FROM gold.order_anomaly_features
WHERE ABS(monto_total_orden - monto_pagado) > 0.01;
GO


/*====================================================================
 15. RESUMEN DE VALIDACIONES

 Esta consulta nos permite obtener varios controles importantes
 en una sola tabla.
====================================================================*/

SELECT
    'Monto total negativo' AS validacion,
    COUNT(*) AS cantidad
FROM gold.order_anomaly_features
WHERE monto_total_orden < 0

UNION ALL

SELECT
    'Monto total cero',
    COUNT(*)
FROM gold.order_anomaly_features
WHERE monto_total_orden = 0

UNION ALL

SELECT
    'Orden sin items',
    COUNT(*)
FROM gold.order_anomaly_features
WHERE numero_items = 0

UNION ALL

SELECT
    'Orden sin pagos',
    COUNT(*)
FROM gold.order_anomaly_features
WHERE numero_pagos = 0

UNION ALL

SELECT
    'Aprobacion antes de compra',
    COUNT(*)
FROM gold.order_anomaly_features
WHERE order_approved_at < order_purchase_timestamp

UNION ALL

SELECT
    'Transportista antes de compra',
    COUNT(*)
FROM gold.order_anomaly_features
WHERE order_delivered_carrier_date < order_purchase_timestamp

UNION ALL

SELECT
    'Cliente antes de compra',
    COUNT(*)
FROM gold.order_anomaly_features
WHERE order_delivered_customer_date < order_purchase_timestamp

UNION ALL

SELECT
    'Cliente antes de transportista',
    COUNT(*)
FROM gold.order_anomaly_features
WHERE order_delivered_customer_date <
      order_delivered_carrier_date

UNION ALL

SELECT
    'Freight mayor que precio',
    COUNT(*)
FROM gold.order_anomaly_features
WHERE freight_total > precio_productos
  AND precio_productos > 0

UNION ALL

SELECT
    'Diferencia monto vs pago',
    COUNT(*)
FROM gold.order_anomaly_features
WHERE ABS(monto_total_orden - monto_pagado) > 0.01;
GO
USE OLIST_DW;
GO
USE OLIST_DW;
GO

/* ============================================================
   PROYECTO 2 - DETECCIÓN DE ANOMALÍAS
   CREACIÓN DEL DATASET PARA MACHINE LEARNING

   ORIGEN:
       gold.order_anomaly_features

   DESTINO:
       gold.order_anomaly_ml

   OBJETIVOS:
   1. Conservar una fila por orden.
   2. Identificar valores faltantes.
   3. Sustituir NULL mediante medianas.
   4. Aplicar transformaciones logarítmicas.
   5. Estandarizar variables mediante Z-Score.
   6. Generar indicadores de calidad.
   7. Preparar datos para Isolation Forest y LOF.
   ============================================================ */

SET NOCOUNT ON;
GO

/* ============================================================
   PASO 1. VALIDAR TABLA DE ORIGEN
   ============================================================ */

IF OBJECT_ID('gold.order_anomaly_features', 'U') IS NULL
BEGIN
    THROW 51000,
        'No existe gold.order_anomaly_features.',
        1;
END;
GO

/* ============================================================
   PASO 2. VALIDAR QUE NO EXISTAN ÓRDENES DUPLICADAS
   ============================================================ */

IF EXISTS (
    SELECT order_id
    FROM gold.order_anomaly_features
    GROUP BY order_id
    HAVING COUNT(*) > 1
)
BEGIN
    THROW 51001,
        'Existen order_id duplicados en la tabla origen.',
        1;
END;
GO

/* ============================================================
   PASO 3. EVITAR SOBRESCRIBIR UNA TABLA EXISTENTE
   ============================================================ */

IF OBJECT_ID('gold.order_anomaly_ml', 'U') IS NOT NULL
BEGIN
    THROW 51002,
        'gold.order_anomaly_ml ya existe. No se modificó.',
        1;
END;
GO

/* ============================================================
   PASO 4. PREPARAR VARIABLES
   ============================================================ */

;WITH datos_originales AS
(
    SELECT
        order_id,

        CAST(monto_total_orden AS FLOAT)
            AS monto_total_orden,

        CAST(freight_total AS FLOAT)
            AS freight_total,

        CAST(proporcion_freight_precio AS FLOAT)
            AS proporcion_freight_precio,

        CAST(numero_items AS FLOAT)
            AS numero_items,

        CAST(numero_vendedores AS FLOAT)
            AS numero_vendedores,

        CAST(numero_pagos AS FLOAT)
            AS numero_pagos,

        CAST(max_cuotas AS FLOAT)
            AS max_cuotas,

        CAST(peso_total_g AS FLOAT)
            AS peso_total_g,

        CAST(volumen_total_cm3 AS FLOAT)
            AS volumen_total_cm3,

        CAST(horas_compra_entrega AS FLOAT)
            AS horas_compra_entrega,

        CAST(dias_retraso_entrega AS FLOAT)
            AS dias_retraso_entrega,

        CAST(monto_pagado AS FLOAT)
            AS monto_pagado,

        CAST(tipos_pago_distintos AS FLOAT)
            AS tipos_pago_distintos,

        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date

    FROM gold.order_anomaly_features
),

/* ============================================================
   PASO 5. CALCULAR MEDIANAS
   ============================================================ */

medianas AS
(
    SELECT
        d.*,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY proporcion_freight_precio
            ) OVER ()
            AS mediana_proporcion,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY horas_compra_entrega
            ) OVER ()
            AS mediana_horas,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY dias_retraso_entrega
            ) OVER ()
            AS mediana_retraso

    FROM datos_originales d
),

/* ============================================================
   PASO 6. IMPUTAR VALORES Y GENERAR BANDERAS
   ============================================================ */

datos_preparados AS
(
    SELECT
        order_id,

        monto_total_orden,
        freight_total,

        COALESCE(
            proporcion_freight_precio,
            mediana_proporcion,
            0
        ) AS proporcion_freight_precio,

        numero_items,
        numero_vendedores,
        numero_pagos,
        max_cuotas,
        peso_total_g,
        volumen_total_cm3,

        COALESCE(
            horas_compra_entrega,
            mediana_horas,
            0
        ) AS horas_compra_entrega,

        COALESCE(
            dias_retraso_entrega,
            mediana_retraso,
            0
        ) AS dias_retraso_entrega,

        monto_pagado,
        tipos_pago_distintos,

        /* Diferencia entre pagos y valor de orden */

        monto_pagado - monto_total_orden
            AS diferencia_pago,

        /* Indicadores de calidad */

        CAST(
            CASE
                WHEN proporcion_freight_precio IS NULL
                THEN 1 ELSE 0
            END AS TINYINT
        ) AS flag_sin_proporcion_freight,

        CAST(
            CASE
                WHEN horas_compra_entrega IS NULL
                THEN 1 ELSE 0
            END AS TINYINT
        ) AS flag_sin_tiempo_entrega,

        CAST(
            CASE
                WHEN dias_retraso_entrega IS NULL
                THEN 1 ELSE 0
            END AS TINYINT
        ) AS flag_sin_retraso_entrega,

        CAST(
            CASE
                WHEN numero_items = 0
                THEN 1 ELSE 0
            END AS TINYINT
        ) AS flag_sin_items,

        CAST(
            CASE
                WHEN numero_pagos = 0
                THEN 1 ELSE 0
            END AS TINYINT
        ) AS flag_sin_pago,

        CAST(
            CASE
                WHEN freight_total > monto_total_orden * 0.5
                     AND monto_total_orden > 0
                THEN 1 ELSE 0
            END AS TINYINT
        ) AS flag_freight_alto,

        CAST(
            CASE
                WHEN ABS(monto_pagado - monto_total_orden) > 1
                THEN 1 ELSE 0
            END AS TINYINT
        ) AS flag_diferencia_pago,

        CAST(
            CASE
                WHEN order_approved_at < order_purchase_timestamp
                  OR order_delivered_carrier_date
                     < order_purchase_timestamp
                  OR order_delivered_customer_date
                     < order_purchase_timestamp
                  OR (
                      order_delivered_carrier_date IS NOT NULL
                      AND order_delivered_customer_date
                          < order_delivered_carrier_date
                  )
                THEN 1 ELSE 0
            END AS TINYINT
        ) AS flag_fecha_incoherente

    FROM medianas
),

/* ============================================================
   PASO 7. TRANSFORMACIONES LOGARÍTMICAS
   ============================================================ */

transformaciones AS
(
    SELECT
        *,

        LOG(1 + CASE
            WHEN monto_total_orden > 0
            THEN monto_total_orden
            ELSE 0
        END) AS log_monto_total,

        LOG(1 + CASE
            WHEN freight_total > 0
            THEN freight_total
            ELSE 0
        END) AS log_freight,

        LOG(1 + CASE
            WHEN peso_total_g > 0
            THEN peso_total_g
            ELSE 0
        END) AS log_peso,

        LOG(1 + CASE
            WHEN volumen_total_cm3 > 0
            THEN volumen_total_cm3
            ELSE 0
        END) AS log_volumen

    FROM datos_preparados
),

/* ============================================================
   PASO 8. CALCULAR ESTADÍSTICAS PARA Z-SCORE
   ============================================================ */

estadisticas AS
(
    SELECT
        *,

        AVG(log_monto_total) OVER ()
            AS media_monto,
        STDEV(log_monto_total) OVER ()
            AS desv_monto,

        AVG(log_freight) OVER ()
            AS media_freight,
        STDEV(log_freight) OVER ()
            AS desv_freight,

        AVG(proporcion_freight_precio) OVER ()
            AS media_proporcion,
        STDEV(proporcion_freight_precio) OVER ()
            AS desv_proporcion,

        AVG(numero_items) OVER ()
            AS media_items,
        STDEV(numero_items) OVER ()
            AS desv_items,

        AVG(numero_vendedores) OVER ()
            AS media_vendedores,
        STDEV(numero_vendedores) OVER ()
            AS desv_vendedores,

        AVG(numero_pagos) OVER ()
            AS media_pagos,
        STDEV(numero_pagos) OVER ()
            AS desv_pagos,

        AVG(max_cuotas) OVER ()
            AS media_cuotas,
        STDEV(max_cuotas) OVER ()
            AS desv_cuotas,

        AVG(log_peso) OVER ()
            AS media_peso,
        STDEV(log_peso) OVER ()
            AS desv_peso,

        AVG(log_volumen) OVER ()
            AS media_volumen,
        STDEV(log_volumen) OVER ()
            AS desv_volumen,

        AVG(horas_compra_entrega) OVER ()
            AS media_horas,
        STDEV(horas_compra_entrega) OVER ()
            AS desv_horas,

        AVG(dias_retraso_entrega) OVER ()
            AS media_retraso,
        STDEV(dias_retraso_entrega) OVER ()
            AS desv_retraso,

        AVG(diferencia_pago) OVER ()
            AS media_diferencia,
        STDEV(diferencia_pago) OVER ()
            AS desv_diferencia,

        AVG(tipos_pago_distintos) OVER ()
            AS media_tipos,
        STDEV(tipos_pago_distintos) OVER ()
            AS desv_tipos

    FROM transformaciones
)

/* ============================================================
   PASO 9. CREAR TABLA FINAL
   ============================================================ */

SELECT
    order_id,

    COALESCE(
        (log_monto_total - media_monto)
        / NULLIF(desv_monto, 0), 0
    ) AS z_log_monto_total,

    COALESCE(
        (log_freight - media_freight)
        / NULLIF(desv_freight, 0), 0
    ) AS z_log_freight,

    COALESCE(
        (proporcion_freight_precio - media_proporcion)
        / NULLIF(desv_proporcion, 0), 0
    ) AS z_proporcion_freight_precio,

    COALESCE(
        (numero_items - media_items)
        / NULLIF(desv_items, 0), 0
    ) AS z_numero_items,

    COALESCE(
        (numero_vendedores - media_vendedores)
        / NULLIF(desv_vendedores, 0), 0
    ) AS z_numero_vendedores,

    COALESCE(
        (numero_pagos - media_pagos)
        / NULLIF(desv_pagos, 0), 0
    ) AS z_numero_pagos,

    COALESCE(
        (max_cuotas - media_cuotas)
        / NULLIF(desv_cuotas, 0), 0
    ) AS z_max_cuotas,

    COALESCE(
        (log_peso - media_peso)
        / NULLIF(desv_peso, 0), 0
    ) AS z_log_peso,

    COALESCE(
        (log_volumen - media_volumen)
        / NULLIF(desv_volumen, 0), 0
    ) AS z_log_volumen,

    COALESCE(
        (horas_compra_entrega - media_horas)
        / NULLIF(desv_horas, 0), 0
    ) AS z_horas_compra_entrega,

    COALESCE(
        (dias_retraso_entrega - media_retraso)
        / NULLIF(desv_retraso, 0), 0
    ) AS z_dias_retraso_entrega,

    COALESCE(
        (diferencia_pago - media_diferencia)
        / NULLIF(desv_diferencia, 0), 0
    ) AS z_diferencia_pago,

    COALESCE(
        (tipos_pago_distintos - media_tipos)
        / NULLIF(desv_tipos, 0), 0
    ) AS z_tipos_pago_distintos,

    flag_freight_alto,
    flag_diferencia_pago,
    flag_sin_items,
    flag_sin_pago,
    flag_fecha_incoherente,
    flag_sin_proporcion_freight,
    flag_sin_tiempo_entrega,
    flag_sin_retraso_entrega

INTO gold.order_anomaly_ml

FROM estadisticas;
GO

/* ============================================================
   PASO 10. VALIDAR RESULTADOS
   ============================================================ */

SELECT
    COUNT(*) AS Total_Ordenes,
    COUNT(DISTINCT order_id) AS Ordenes_Unicas
FROM gold.order_anomaly_ml;
GO

SELECT TOP 10 *
FROM gold.order_anomaly_ml;
GO

/* ============================================================
   PASO 11. VALIDAR VALORES NULOS
   ============================================================ */

SELECT
    SUM(CAST(flag_sin_proporcion_freight AS INT))
        AS Faltantes_Proporcion,

    SUM(CAST(flag_sin_tiempo_entrega AS INT))
        AS Faltantes_Tiempo,

    SUM(CAST(flag_sin_retraso_entrega AS INT))
        AS Faltantes_Retraso

FROM gold.order_anomaly_ml;
GO
USE OLIST_DW;
GO

SELECT
    COUNT(*) AS Total_Ordenes
FROM gold.order_anomaly_ml;
GO