USE OLIST_DW;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name=N'bronze')
    THROW 51000, 'Falta el esquema bronze en OLIST_DW.', 1;
GO

IF OBJECT_ID(N'bronze.olist_customers_dataset',N'U') IS NULL OR
   OBJECT_ID(N'bronze.olist_order_items_dataset',N'U') IS NULL OR
   OBJECT_ID(N'bronze.olist_order_payments_dataset',N'U') IS NULL OR
   OBJECT_ID(N'bronze.olist_orders_dataset',N'U') IS NULL OR
   OBJECT_ID(N'bronze.olist_products_dataset',N'U') IS NULL OR
   OBJECT_ID(N'bronze.olist_sellers_dataset',N'U') IS NULL
    THROW 51001, 'Falta una o mas tablas Bronze; no continuar.', 1;
GO

-- ETAPA: 00 - Verificación de esquemas

USE OLIST_DW;
GO

SELECT name AS Esquema
FROM sys.schemas
WHERE name IN ('bronze', 'silver', 'gold');
GO

-- ETAPA: 01 - Cantidad de datos en Bronze

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

-- ETAPA: 02 - Silver Customers

USE OLIST_DW;
GO

DROP TABLE IF EXISTS silver.customers;
GO

CREATE TABLE silver.customers
(

    customer_id NVARCHAR(50) NOT NULL,

    customer_unique_id NVARCHAR(50) NOT NULL,

    customer_zip_code_prefix NVARCHAR(10) NULL,

    customer_city NVARCHAR(100) NULL,

    customer_state NVARCHAR(10) NULL
);
GO

INSERT INTO silver.customers
(
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
)

SELECT

    NULLIF(LTRIM(RTRIM(customer_id)), ''),

    NULLIF(LTRIM(RTRIM(customer_unique_id)), ''),

    NULLIF(LTRIM(RTRIM(customer_zip_code_prefix)), ''),

    NULLIF(LTRIM(RTRIM(customer_city)), ''),

    NULLIF(LTRIM(RTRIM(customer_state)), '')

FROM bronze.olist_customers_dataset;
GO

SELECT
    COUNT(*) AS registros_bronze
FROM bronze.olist_customers_dataset;
GO

SELECT
    COUNT(*) AS registros_silver
FROM silver.customers;
GO

SELECT TOP 10 *
FROM silver.customers;
GO

SELECT
    COUNT(*) AS customer_id_nulos
FROM silver.customers
WHERE customer_id IS NULL;
GO

SELECT
    COUNT(*) AS customer_unique_id_nulos
FROM silver.customers
WHERE customer_unique_id IS NULL;
GO

SELECT
    customer_id,
    COUNT(*) AS cantidad
FROM silver.customers
GROUP BY customer_id
HAVING COUNT(*) > 1;
GO

SELECT
    customer_state,
    COUNT(*) AS cantidad
FROM silver.customers
GROUP BY customer_state
ORDER BY customer_state;
GO

SELECT
    COUNT(*) AS codigo_postal_nulo
FROM silver.customers
WHERE customer_zip_code_prefix IS NULL;
GO

ALTER TABLE silver.customers
ADD CONSTRAINT PK_silver_customers
PRIMARY KEY (customer_id);
GO

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

-- ETAPA: 03 - Silver Orders

USE OLIST_DW;
GO

DROP TABLE IF EXISTS silver.orders;
GO

CREATE TABLE silver.orders
(

    order_id NVARCHAR(50) NOT NULL,

    customer_id NVARCHAR(50) NOT NULL,

    order_status NVARCHAR(50) NOT NULL,

    order_purchase_timestamp DATETIME2 NULL,

    order_approved_at DATETIME2 NULL,

    order_delivered_carrier_date DATETIME2 NULL,

    order_delivered_customer_date DATETIME2 NULL,

    order_estimated_delivery_date DATETIME2 NULL
);
GO

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

SELECT
    COUNT(*) AS registros_bronze
FROM bronze.olist_orders_dataset;
GO

SELECT
    COUNT(*) AS registros_silver
FROM silver.orders;
GO

SELECT TOP 10 *
FROM silver.orders;
GO

SELECT
    COUNT(*) AS order_id_nulos
FROM silver.orders
WHERE order_id IS NULL;
GO

SELECT
    COUNT(*) AS customer_id_nulos
FROM silver.orders
WHERE customer_id IS NULL;
GO

SELECT
    order_id,
    COUNT(*) AS cantidad
FROM silver.orders
GROUP BY order_id
HAVING COUNT(*) > 1;
GO

SELECT
    order_status,
    COUNT(*) AS cantidad
FROM silver.orders
GROUP BY order_status
ORDER BY order_status;
GO

SELECT
    COUNT(*) AS fecha_compra_nula
FROM silver.orders
WHERE order_purchase_timestamp IS NULL;
GO

SELECT
    COUNT(*) AS fecha_aprobacion_nula
FROM silver.orders
WHERE order_approved_at IS NULL;
GO

SELECT
    COUNT(*) AS fecha_transportista_nula
FROM silver.orders
WHERE order_delivered_carrier_date IS NULL;
GO

SELECT
    COUNT(*) AS fecha_entrega_cliente_nula
FROM silver.orders
WHERE order_delivered_customer_date IS NULL;
GO

SELECT
    COUNT(*) AS entregas_antes_de_compra
FROM silver.orders
WHERE order_delivered_customer_date
      < order_purchase_timestamp;
GO

SELECT
    COUNT(*) AS aprobaciones_antes_de_compra
FROM silver.orders
WHERE order_approved_at < order_purchase_timestamp;
GO

SELECT
    COUNT(*) AS entrega_cliente_antes_transportista
FROM silver.orders
WHERE order_delivered_customer_date
      < order_delivered_carrier_date;
GO

SELECT
    COUNT(*) AS ordenes_sin_cliente
FROM silver.orders o
LEFT JOIN silver.customers c
    ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;
GO

ALTER TABLE silver.orders
ADD CONSTRAINT PK_silver_orders
PRIMARY KEY (order_id);
GO

ALTER TABLE silver.orders
ADD CONSTRAINT FK_silver_orders_customers
FOREIGN KEY (customer_id)
REFERENCES silver.customers(customer_id);
GO

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

-- ETAPA: 04 - Silver Products

USE OLIST_DW;
GO

DROP TABLE IF EXISTS silver.products;
GO

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

SELECT COUNT(*) AS registros_bronze
FROM bronze.olist_products_dataset;

SELECT COUNT(*) AS registros_silver
FROM silver.products;
GO

SELECT TOP 10 *
FROM silver.products;
GO

SELECT COUNT(*) AS product_id_nulos
FROM silver.products
WHERE product_id IS NULL;
GO

SELECT
    product_id,
    COUNT(*) AS cantidad
FROM silver.products
GROUP BY product_id
HAVING COUNT(*) > 1;
GO

SELECT COUNT(*) AS categoria_nula
FROM silver.products
WHERE product_category_name IS NULL;
GO

SELECT
    product_category_name,
    COUNT(*) AS cantidad
FROM silver.products
GROUP BY product_category_name
ORDER BY cantidad DESC;
GO

SELECT COUNT(*) AS peso_nulo
FROM silver.products
WHERE product_weight_g IS NULL;
GO

SELECT COUNT(*) AS peso_negativo
FROM silver.products
WHERE product_weight_g < 0;
GO

SELECT COUNT(*) AS peso_cero
FROM silver.products
WHERE product_weight_g = 0;
GO

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

SELECT COUNT(*) AS dimensiones_negativas
FROM silver.products
WHERE product_length_cm < 0
   OR product_height_cm < 0
   OR product_width_cm < 0;
GO

SELECT COUNT(*) AS dimensiones_cero
FROM silver.products
WHERE product_length_cm = 0
   OR product_height_cm = 0
   OR product_width_cm = 0;
GO

SELECT COUNT(*) AS fotos_negativas
FROM silver.products
WHERE product_photos_qty < 0;
GO

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

SELECT COUNT(*) AS items_sin_producto
FROM silver.order_items oi
LEFT JOIN silver.products p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;
GO

ALTER TABLE silver.products
ADD CONSTRAINT PK_silver_products
PRIMARY KEY (product_id);
GO

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

-- ETAPA: 05 - Silver Sellers

USE OLIST_DW;
GO

DROP TABLE IF EXISTS silver.sellers;
GO

CREATE TABLE silver.sellers
(

    seller_id NVARCHAR(50) NOT NULL,

    seller_zip_code_prefix NVARCHAR(10) NULL,

    seller_city NVARCHAR(100) NULL,

    seller_state NVARCHAR(10) NULL
);
GO

INSERT INTO silver.sellers
(
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
)
SELECT

    NULLIF(LTRIM(RTRIM(seller_id)), ''),

    NULLIF(LTRIM(RTRIM(
        CAST(seller_zip_code_prefix AS NVARCHAR(10))
    )), ''),

    NULLIF(LTRIM(RTRIM(seller_city)), ''),

    NULLIF(LTRIM(RTRIM(seller_state)), '')

FROM bronze.olist_sellers_dataset;
GO

SELECT
    COUNT(*) AS registros_bronze
FROM bronze.olist_sellers_dataset;
GO

SELECT
    COUNT(*) AS registros_silver
FROM silver.sellers;
GO

SELECT TOP 10 *
FROM silver.sellers;
GO

SELECT
    COUNT(*) AS seller_id_nulos
FROM silver.sellers
WHERE seller_id IS NULL;
GO

SELECT
    seller_id,
    COUNT(*) AS cantidad
FROM silver.sellers
GROUP BY seller_id
HAVING COUNT(*) > 1;
GO

SELECT
    COUNT(*) AS codigo_postal_nulo
FROM silver.sellers
WHERE seller_zip_code_prefix IS NULL;
GO

SELECT
    COUNT(*) AS ciudad_nula
FROM silver.sellers
WHERE seller_city IS NULL;
GO

SELECT
    COUNT(*) AS estado_nulo
FROM silver.sellers
WHERE seller_state IS NULL;
GO

SELECT
    seller_state,
    COUNT(*) AS cantidad
FROM silver.sellers
GROUP BY seller_state
ORDER BY seller_state;
GO

SELECT TOP 10
    seller_state,
    COUNT(*) AS cantidad_vendedores
FROM silver.sellers
GROUP BY seller_state
ORDER BY COUNT(*) DESC;
GO

ALTER TABLE silver.sellers
ADD CONSTRAINT PK_silver_sellers
PRIMARY KEY (seller_id);
GO

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

WHERE kc.parent_object_id = OBJECT_ID('silver.sellers')

AND kc.type = 'PK';
GO

-- ETAPA: 06 - Silver Order Items

USE OLIST_DW;
GO

DROP TABLE IF EXISTS silver.order_items;
GO

CREATE TABLE silver.order_items
(

    order_id NVARCHAR(50) NOT NULL,

    order_item_id INT NOT NULL,

    product_id NVARCHAR(50) NOT NULL,

    seller_id NVARCHAR(50) NOT NULL,

    shipping_limit_date DATETIME2 NULL,

    price DECIMAL(18,2) NULL,

    freight_value DECIMAL(18,2) NULL
);
GO

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

SELECT
    COUNT(*) AS registros_bronze
FROM bronze.olist_order_items_dataset;
GO

SELECT
    COUNT(*) AS registros_silver
FROM silver.order_items;
GO

SELECT TOP 10 *
FROM silver.order_items;
GO

SELECT
    COUNT(*) AS order_id_nulos
FROM silver.order_items
WHERE order_id IS NULL;
GO

SELECT
    COUNT(*) AS order_item_id_nulos
FROM silver.order_items
WHERE order_item_id IS NULL;
GO

SELECT
    COUNT(*) AS product_id_nulos
FROM silver.order_items
WHERE product_id IS NULL;
GO

SELECT
    COUNT(*) AS seller_id_nulos
FROM silver.order_items
WHERE seller_id IS NULL;
GO

SELECT
    COUNT(*) AS shipping_limit_date_nulos
FROM silver.order_items
WHERE shipping_limit_date IS NULL;
GO

SELECT
    COUNT(*) AS price_nulos
FROM silver.order_items
WHERE price IS NULL;
GO

SELECT
    COUNT(*) AS freight_nulos
FROM silver.order_items
WHERE freight_value IS NULL;
GO

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

SELECT
    COUNT(*) AS precios_negativos
FROM silver.order_items
WHERE price < 0;
GO

SELECT
    COUNT(*) AS freight_negativo
FROM silver.order_items
WHERE freight_value < 0;
GO

SELECT
    COUNT(*) AS precios_cero
FROM silver.order_items
WHERE price = 0;
GO

SELECT
    COUNT(*) AS freight_cero
FROM silver.order_items
WHERE freight_value = 0;
GO

SELECT
    COUNT(*) AS items_sin_orden
FROM silver.order_items oi

LEFT JOIN silver.orders o
    ON oi.order_id = o.order_id

WHERE o.order_id IS NULL;
GO

SELECT
    COUNT(DISTINCT order_id) AS ordenes_con_items
FROM silver.order_items;
GO

SELECT TOP 20
    order_id,
    COUNT(*) AS numero_items
FROM silver.order_items
GROUP BY order_id
ORDER BY COUNT(*) DESC;
GO

SELECT TOP 20
    order_id,
    COUNT(DISTINCT seller_id) AS numero_vendedores
FROM silver.order_items
GROUP BY order_id
ORDER BY COUNT(DISTINCT seller_id) DESC;
GO

ALTER TABLE silver.order_items
ADD CONSTRAINT PK_silver_order_items
PRIMARY KEY
(
    order_id,
    order_item_id
);
GO

ALTER TABLE silver.order_items
ADD CONSTRAINT FK_silver_order_items_orders
FOREIGN KEY (order_id)
REFERENCES silver.orders(order_id);
GO

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

-- ETAPA: 07 - Silver Order Payments

USE OLIST_DW;
GO

DROP TABLE IF EXISTS silver.order_payments;
GO

CREATE TABLE silver.order_payments
(

    order_id NVARCHAR(50) NOT NULL,

    payment_sequential INT NOT NULL,

    payment_type NVARCHAR(50) NULL,

    payment_installments INT NULL,

    payment_value DECIMAL(18,2) NULL
);
GO

INSERT INTO silver.order_payments
(
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value
)
SELECT

    NULLIF(LTRIM(RTRIM(order_id)), ''),

    TRY_CONVERT(INT, payment_sequential),

    NULLIF(LTRIM(RTRIM(payment_type)), ''),

    TRY_CONVERT(INT, payment_installments),

    TRY_CONVERT(DECIMAL(18,2), payment_value)

FROM bronze.olist_order_payments_dataset;
GO

SELECT
    COUNT(*) AS registros_bronze
FROM bronze.olist_order_payments_dataset;
GO

SELECT
    COUNT(*) AS registros_silver
FROM silver.order_payments;
GO

SELECT TOP 10 *
FROM silver.order_payments;
GO

SELECT
    COUNT(*) AS order_id_nulos
FROM silver.order_payments
WHERE order_id IS NULL;
GO

SELECT
    COUNT(*) AS payment_sequential_nulos
FROM silver.order_payments
WHERE payment_sequential IS NULL;
GO

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

SELECT
    COUNT(*) AS payment_type_nulos
FROM silver.order_payments
WHERE payment_type IS NULL;
GO

SELECT
    payment_type,
    COUNT(*) AS cantidad
FROM silver.order_payments
GROUP BY payment_type
ORDER BY COUNT(*) DESC;
GO

SELECT
    COUNT(*) AS cuotas_nulas
FROM silver.order_payments
WHERE payment_installments IS NULL;
GO

SELECT
    COUNT(*) AS cuotas_negativas
FROM silver.order_payments
WHERE payment_installments < 0;
GO

SELECT
    COUNT(*) AS cuotas_cero
FROM silver.order_payments
WHERE payment_installments = 0;
GO

SELECT
    COUNT(*) AS valor_pago_nulo
FROM silver.order_payments
WHERE payment_value IS NULL;
GO

SELECT
    COUNT(*) AS pagos_negativos
FROM silver.order_payments
WHERE payment_value < 0;
GO

SELECT
    COUNT(*) AS pagos_cero
FROM silver.order_payments
WHERE payment_value = 0;
GO

SELECT
    COUNT(*) AS pagos_sin_orden
FROM silver.order_payments p

LEFT JOIN silver.orders o
    ON p.order_id = o.order_id

WHERE o.order_id IS NULL;
GO

SELECT TOP 20
    order_id,
    COUNT(*) AS numero_pagos
FROM silver.order_payments
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC;
GO

ALTER TABLE silver.order_payments
ADD CONSTRAINT PK_silver_order_payments
PRIMARY KEY
(
    order_id,
    payment_sequential
);
GO

ALTER TABLE silver.order_payments
ADD CONSTRAINT FK_silver_order_payments_orders
FOREIGN KEY (order_id)
REFERENCES silver.orders(order_id);
GO

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

-- ETAPA: 08 - Validación integral Silver

USE OLIST_DW;
GO

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

SELECT
    COUNT(*) AS ordenes_sin_cliente
FROM silver.orders o

LEFT JOIN silver.customers c
    ON o.customer_id = c.customer_id

WHERE c.customer_id IS NULL;
GO

SELECT
    COUNT(*) AS items_sin_orden
FROM silver.order_items oi

LEFT JOIN silver.orders o
    ON oi.order_id = o.order_id

WHERE o.order_id IS NULL;
GO

SELECT
    COUNT(*) AS items_sin_producto
FROM silver.order_items oi

LEFT JOIN silver.products p
    ON oi.product_id = p.product_id

WHERE p.product_id IS NULL;
GO

SELECT
    COUNT(*) AS items_sin_vendedor
FROM silver.order_items oi

LEFT JOIN silver.sellers s
    ON oi.seller_id = s.seller_id

WHERE s.seller_id IS NULL;
GO

SELECT
    COUNT(*) AS pagos_sin_orden
FROM silver.order_payments op

LEFT JOIN silver.orders o
    ON op.order_id = o.order_id

WHERE o.order_id IS NULL;
GO

SELECT
    customer_id,
    COUNT(*) AS cantidad
FROM silver.customers

GROUP BY
    customer_id

HAVING COUNT(*) > 1;
GO

SELECT
    order_id,
    COUNT(*) AS cantidad
FROM silver.orders

GROUP BY
    order_id

HAVING COUNT(*) > 1;
GO

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

SELECT
    product_id,
    COUNT(*) AS cantidad
FROM silver.products

GROUP BY
    product_id

HAVING COUNT(*) > 1;
GO

SELECT
    seller_id,
    COUNT(*) AS cantidad
FROM silver.sellers

GROUP BY
    seller_id

HAVING COUNT(*) > 1;
GO

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

-- ETAPA: 09 - Revisión de tipos de datos

USE OLIST_DW;
GO

SELECT
    COLUMN_NAME AS columna,
    DATA_TYPE AS tipo_dato
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'silver'
  AND TABLE_NAME = 'customers'
ORDER BY ORDINAL_POSITION;
GO

SELECT
    COLUMN_NAME AS columna,
    DATA_TYPE AS tipo_dato
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'silver'
  AND TABLE_NAME = 'orders'
ORDER BY ORDINAL_POSITION;
GO

SELECT
    COLUMN_NAME AS columna,
    DATA_TYPE AS tipo_dato
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'silver'
  AND TABLE_NAME = 'order_items'
ORDER BY ORDINAL_POSITION;
GO

SELECT
    COLUMN_NAME AS columna,
    DATA_TYPE AS tipo_dato
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'silver'
  AND TABLE_NAME = 'products'
ORDER BY ORDINAL_POSITION;
GO

SELECT
    COLUMN_NAME AS columna,
    DATA_TYPE AS tipo_dato
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'silver'
  AND TABLE_NAME = 'sellers'
ORDER BY ORDINAL_POSITION;
GO

SELECT
    COLUMN_NAME AS columna,
    DATA_TYPE AS tipo_dato
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'silver'
  AND TABLE_NAME = 'order_payments'
ORDER BY ORDINAL_POSITION;
GO

-- ETAPA: 10 - Construcción tabla Gold de características

USE OLIST_DW;
GO

DROP TABLE IF EXISTS gold.order_anomaly_features;
GO

WITH items_agregados AS
(
    SELECT
        oi.order_id,

        COUNT(*) AS numero_items,

        COUNT(DISTINCT oi.product_id) AS numero_productos_distintos,

        COUNT(DISTINCT oi.seller_id) AS numero_vendedores,

        SUM(oi.price) AS precio_productos,

        SUM(oi.freight_value) AS freight_total,

        SUM(
            COALESCE(p.product_weight_g, 0)
        ) AS peso_total_g,

        SUM(
            COALESCE(p.product_length_cm, 0) *
            COALESCE(p.product_height_cm, 0) *
            COALESCE(p.product_width_cm, 0)
        ) AS volumen_total_cm3

    FROM silver.order_items oi

    LEFT JOIN silver.products p
        ON oi.product_id = p.product_id

    GROUP BY oi.order_id
),

pagos_agregados AS
(
    SELECT
        op.order_id,

        COUNT(*) AS numero_pagos,

        COUNT(DISTINCT op.payment_type) AS tipos_pago_distintos,

        MAX(op.payment_installments) AS max_cuotas,

        SUM(op.payment_value) AS monto_pagado

    FROM silver.order_payments op

    GROUP BY op.order_id
),

vendedor_orden AS
(
    SELECT
        oi.order_id,

        MIN(s.seller_state) AS seller_state_referencia,

        MIN(s.seller_zip_code_prefix) AS seller_zip_referencia

    FROM silver.order_items oi

    LEFT JOIN silver.sellers s
        ON oi.seller_id = s.seller_id

    GROUP BY oi.order_id
)

SELECT

    o.order_id,

    o.customer_id,

    o.order_status,

    o.order_purchase_timestamp,

    o.order_approved_at,

    o.order_delivered_carrier_date,

    o.order_delivered_customer_date,

    o.order_estimated_delivery_date,

    c.customer_state,

    c.customer_zip_code_prefix,

    vo.seller_state_referencia,

    vo.seller_zip_referencia,

    COALESCE(ia.precio_productos, 0)
        AS precio_productos,

    COALESCE(ia.freight_total, 0)
        AS freight_total,

    COALESCE(ia.precio_productos, 0)
    +
    COALESCE(ia.freight_total, 0)
        AS monto_total_orden,

    COALESCE(pa.monto_pagado, 0)
        AS monto_pagado,

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

    COALESCE(ia.peso_total_g, 0)
        AS peso_total_g,

    COALESCE(ia.volumen_total_cm3, 0)
        AS volumen_total_cm3,

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

    CASE
        WHEN o.order_approved_at IS NOT NULL
        THEN DATEDIFF(
            HOUR,
            o.order_purchase_timestamp,
            o.order_approved_at
        )
        ELSE NULL
    END AS horas_compra_aprobacion,

    CASE
        WHEN o.order_delivered_carrier_date IS NOT NULL
        THEN DATEDIFF(
            HOUR,
            o.order_purchase_timestamp,
            o.order_delivered_carrier_date
        )
        ELSE NULL
    END AS horas_compra_transportista,

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

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
        THEN DATEDIFF(
            HOUR,
            o.order_purchase_timestamp,
            o.order_delivered_customer_date
        )
        ELSE NULL
    END AS horas_compra_entrega,

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

    CASE
        WHEN c.customer_state IS NULL
          OR vo.seller_state_referencia IS NULL
            THEN NULL

        WHEN c.customer_state = vo.seller_state_referencia
            THEN 0

        ELSE 1

    END AS vendedor_otro_estado

INTO gold.order_anomaly_features

FROM silver.orders o

LEFT JOIN silver.customers c
    ON o.customer_id = c.customer_id

LEFT JOIN items_agregados ia
    ON o.order_id = ia.order_id

LEFT JOIN pagos_agregados pa
    ON o.order_id = pa.order_id

LEFT JOIN vendedor_orden vo
    ON o.order_id = vo.order_id;

GO

USE OLIST_DW;
GO

SELECT COUNT(*) AS registros_gold
FROM gold.order_anomaly_features;
GO

SELECT
    order_id,
    COUNT(*) AS cantidad
FROM gold.order_anomaly_features
GROUP BY order_id
HAVING COUNT(*) > 1;
GO

SELECT COUNT(*) AS ordenes_silver_sin_gold
FROM silver.orders o
LEFT JOIN gold.order_anomaly_features g
    ON o.order_id = g.order_id
WHERE g.order_id IS NULL;
GO

SELECT COUNT(*) AS order_id_nulos
FROM gold.order_anomaly_features
WHERE order_id IS NULL;
GO

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

-- ETAPA: 11 - Validaciones de calidad Gold

USE OLIST_DW;
GO

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

SELECT COUNT(*) AS ordenes_monto_cero
FROM gold.order_anomaly_features
WHERE monto_total_orden = 0;
GO

SELECT
    order_status,
    COUNT(*) AS cantidad
FROM gold.order_anomaly_features
WHERE monto_total_orden = 0
GROUP BY order_status
ORDER BY cantidad DESC;
GO

SELECT
    order_status,
    COUNT(*) AS cantidad
FROM gold.order_anomaly_features
WHERE numero_items = 0
GROUP BY order_status
ORDER BY cantidad DESC;
GO

SELECT
    order_status,
    COUNT(*) AS cantidad
FROM gold.order_anomaly_features
WHERE numero_pagos = 0
GROUP BY order_status
ORDER BY cantidad DESC;
GO

SELECT COUNT(*) AS aprobaciones_antes_compra
FROM gold.order_anomaly_features
WHERE order_approved_at < order_purchase_timestamp;
GO

SELECT COUNT(*) AS transportista_antes_compra
FROM gold.order_anomaly_features
WHERE order_delivered_carrier_date < order_purchase_timestamp;
GO

SELECT COUNT(*) AS entrega_cliente_antes_compra
FROM gold.order_anomaly_features
WHERE order_delivered_customer_date < order_purchase_timestamp;
GO

SELECT COUNT(*) AS cliente_antes_transportista
FROM gold.order_anomaly_features
WHERE order_delivered_customer_date <
      order_delivered_carrier_date;
GO

SELECT COUNT(*) AS aprobacion_despues_entrega
FROM gold.order_anomaly_features
WHERE order_approved_at >
      order_delivered_customer_date;
GO

SELECT COUNT(*) AS freight_mayor_precio
FROM gold.order_anomaly_features
WHERE freight_total > precio_productos
  AND precio_productos > 0;
GO

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

SELECT COUNT(*) AS ordenes_diferencia_pago
FROM gold.order_anomaly_features
WHERE ABS(monto_total_orden - monto_pagado) > 0.01;
GO

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

-- ETAPA: 12 - Preparación del dataset para Machine Learning

SET NOCOUNT ON;
GO

IF OBJECT_ID('gold.order_anomaly_features', 'U') IS NULL
BEGIN
    THROW 51000,
        'No existe gold.order_anomaly_features.',
        1;
END;
GO

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

IF OBJECT_ID('gold.order_anomaly_ml', 'U') IS NOT NULL
BEGIN
    THROW 51002,
        'gold.order_anomaly_ml ya existe. No se modificó.',
        1;
END;
GO

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

        monto_pagado - monto_total_orden
            AS diferencia_pago,

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

SELECT
    COUNT(*) AS Total_Ordenes,
    COUNT(DISTINCT order_id) AS Ordenes_Unicas
FROM gold.order_anomaly_ml;
GO

SELECT TOP 10 *
FROM gold.order_anomaly_ml;
GO

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
