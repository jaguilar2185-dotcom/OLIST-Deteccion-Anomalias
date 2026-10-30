# ============================================================
# PROYECTO 2 - DETECCIÓN DE ANOMALÍAS
# PASO 1: PREPARAR PYTHON
# ============================================================

# pandas:
# Permite trabajar con los datos en forma de tabla (DataFrame).
import pandas as pd

# numpy:
# Se utilizará para operaciones numéricas.
import numpy as np

# Librería para conectarnos a SQL Server.
import pyodbc

# Algoritmos que utilizaremos posteriormente.
from sklearn.ensemble import IsolationForest
from sklearn.neighbors import LocalOutlierFactor

# Herramientas para evaluar y comparar los resultados.
from sklearn.preprocessing import MinMaxScaler

print("Librerías cargadas correctamente.")

# ============================================================
# PASO 2: CONEXIÓN CON SQL SERVER
# ============================================================

# Datos de conexión.
server = 'JUAN'
database = 'OLIST_DW'

# Conexión utilizando autenticación de Windows.
conexion = pyodbc.connect(
    'DRIVER={ODBC Driver 17 for SQL Server};'
    f'SERVER={server};'
    f'DATABASE={database};'
    'Trusted_Connection=yes;'
    'TrustServerCertificate=yes;'
)

print("Conexión con SQL Server realizada correctamente.")
# ============================================================
# PASO 3: EXTRAER DATASET PARA MACHINE LEARNING
# ============================================================

# Se consultan las variables que ya fueron preparadas
# y estandarizadas en gold.order_anomaly_ml.
consulta = """
SELECT
    order_id,

    -- Variables numéricas estandarizadas
    z_log_monto_total,
    z_log_freight,
    z_proporcion_freight_precio,
    z_numero_items,
    z_numero_vendedores,
    z_numero_pagos,
    z_max_cuotas,
    z_log_peso,
    z_log_volumen,
    z_horas_compra_entrega,
    z_dias_retraso_entrega,
    z_diferencia_pago,
    z_tipos_pago_distintos,

    -- Flags para validación y explicabilidad
    flag_freight_alto,
    flag_diferencia_pago,
    flag_sin_items,
    flag_sin_pago,
    flag_fecha_incoherente,
    flag_sin_proporcion_freight,
    flag_sin_tiempo_entrega,
    flag_sin_retraso_entrega

FROM gold.order_anomaly_ml;
"""

# Ejecutar la consulta SQL y cargarla en un DataFrame.
df = pd.read_sql(consulta, conexion)

# Mostrar información básica para comprobar la carga.
print("Datos cargados correctamente.")
print("Cantidad de órdenes:", len(df))
print("Cantidad de columnas:", df.shape[1])

# Mostrar las primeras 5 filas.
print(df.head())

# ============================================================
# PASO 4: VALIDACIÓN FINAL DEL DATASET PARA MACHINE LEARNING
# ============================================================
#
# OBJETIVO:
# Comprobar que los datos cargados desde SQL Server están
# preparados correctamente antes de entrenar los algoritmos
# de detección de anomalías.
#
# En este paso NO se modifica ningún dato.
# ============================================================


# ------------------------------------------------------------
# 1. VALIDAR CANTIDAD DE FILAS Y COLUMNAS
# ------------------------------------------------------------

print("\n========================================")
print("1. DIMENSIONES DEL DATASET")
print("========================================")

print("Cantidad de filas:", df.shape[0])
print("Cantidad de columnas:", df.shape[1])


# ------------------------------------------------------------
# 2. VALIDAR QUE CADA ORDER_ID SEA ÚNICO
# ------------------------------------------------------------
# El dataset Gold debe contener exactamente una fila por orden.

print("\n========================================")
print("2. VALIDACIÓN DE ORDER_ID")
print("========================================")

print("Órdenes únicas:", df["order_id"].nunique())

print(
    "Order_id duplicados:",
    df["order_id"].duplicated().sum()
)


# ------------------------------------------------------------
# 3. VALIDAR VALORES NULL
# ------------------------------------------------------------
# Isolation Forest y LOF necesitan trabajar con variables
# numéricas completas.
#
# Por eso verificamos que las variables preparadas para ML
# no tengan valores NULL.

print("\n========================================")
print("3. VALORES NULL POR COLUMNA")
print("========================================")

print(df.isnull().sum())


# ------------------------------------------------------------
# 4. DEFINIR VARIABLES QUE UTILIZARÁ EL MODELO
# ------------------------------------------------------------
#
# IMPORTANTE:
# Los flag_* NO se utilizarán inicialmente para entrenar
# Isolation Forest.
#
# Los conservaremos para explicar posteriormente por qué
# determinadas órdenes pueden ser sospechosas.
#
# De esta manera el modelo descubre patrones inusuales
# utilizando las características de las órdenes y no
# simplemente las reglas que nosotros definimos.
# ------------------------------------------------------------

variables_modelo = [

    "z_log_monto_total",

    "z_log_freight",

    "z_proporcion_freight_precio",

    "z_numero_items",

    "z_numero_vendedores",

    "z_numero_pagos",

    "z_max_cuotas",

    "z_log_peso",

    "z_log_volumen",

    "z_horas_compra_entrega",

    "z_dias_retraso_entrega",

    "z_diferencia_pago",

    "z_tipos_pago_distintos"
]


# ------------------------------------------------------------
# 5. CREAR MATRIZ X
# ------------------------------------------------------------
#
# X será la matriz que utilizaremos posteriormente para
# entrenar Isolation Forest y Local Outlier Factor.
# ------------------------------------------------------------

X = df[variables_modelo].copy()


print("\n========================================")
print("4. MATRIZ PARA MACHINE LEARNING")
print("========================================")

print("Filas de X:", X.shape[0])
print("Variables utilizadas:", X.shape[1])


# ------------------------------------------------------------
# 6. VALIDAR NULL EN LAS VARIABLES DEL MODELO
# ------------------------------------------------------------

print("\n========================================")
print("5. NULL EN VARIABLES DEL MODELO")
print("========================================")

print("Total de valores NULL:", X.isnull().sum().sum())


# ------------------------------------------------------------
# 7. VALIDAR VALORES INFINITOS
# ------------------------------------------------------------
#
# Las transformaciones logarítmicas podrían generar valores
# infinitos si no hubieran sido preparadas correctamente.
# Verificamos que esto no haya ocurrido.
# ------------------------------------------------------------

cantidad_infinitos = np.isinf(X.to_numpy()).sum()

print("\n========================================")
print("6. VALORES INFINITOS")
print("========================================")

print("Total de valores infinitos:", cantidad_infinitos)


# ------------------------------------------------------------
# 8. RESUMEN FINAL
# ------------------------------------------------------------

print("\n========================================")
print("RESUMEN DE VALIDACIÓN")
print("========================================")

print("Registros:", len(df))
print("Órdenes únicas:", df["order_id"].nunique())
print("Duplicados:", df["order_id"].duplicated().sum())
print("Variables ML:", len(variables_modelo))
print("NULL en X:", X.isnull().sum().sum())
print("Infinitos en X:", cantidad_infinitos)

# ============================================================
# PASO 5: MODELO 1 - ISOLATION FOREST
# ============================================================

from sklearn.ensemble import IsolationForest

# ------------------------------------------------------------
# 1. DEFINIR PORCENTAJE ESPERADO DE ANOMALÍAS
# ------------------------------------------------------------
# Se utiliza inicialmente una contaminación del 2%.
# Esto NO significa que el 2% sean fraudes.
# Significa que el modelo identificará aproximadamente el 2%
# de las órdenes con comportamiento más inusual.
# ------------------------------------------------------------

contaminacion = 0.05

# ------------------------------------------------------------
# 2. CREAR MODELO ISOLATION FOREST
# ------------------------------------------------------------

modelo_if = IsolationForest(
    n_estimators=200,
    contamination=contaminacion,
    random_state=42,
    n_jobs=-1
)


# ------------------------------------------------------------
# 3. ENTRENAR EL MODELO
# ------------------------------------------------------------

modelo_if.fit(X)


# ------------------------------------------------------------
# 4. OBTENER PREDICCIÓN
# ------------------------------------------------------------
# Isolation Forest devuelve:
#
#  1 = comportamiento normal
# -1 = anomalía
# ------------------------------------------------------------

pred_if = modelo_if.predict(X)


# ------------------------------------------------------------
# 5. OBTENER ANOMALY SCORE
# ------------------------------------------------------------
# score_samples produce valores donde los casos más anómalos
# tienden a tener valores menores.
#
# Multiplicamos por -1 para que:
# mayor score = mayor rareza.
# ------------------------------------------------------------

score_if_raw = -modelo_if.score_samples(X)


# ------------------------------------------------------------
# 6. NORMALIZAR SCORE ENTRE 0 Y 1
# ------------------------------------------------------------

scaler_score = MinMaxScaler()

score_if = scaler_score.fit_transform(
    score_if_raw.reshape(-1, 1)
).ravel()


# ------------------------------------------------------------
# 7. GUARDAR RESULTADOS EN EL DATAFRAME
# ------------------------------------------------------------

df["anomaly_score_if"] = score_if

df["anomaly_if"] = np.where(
    pred_if == -1,
    1,
    0
)


# ------------------------------------------------------------
# 8. RESUMEN DEL MODELO
# ------------------------------------------------------------

cantidad_anomalias_if = df["anomaly_if"].sum()

porcentaje_anomalias_if = (
    cantidad_anomalias_if / len(df)
) * 100


print("\n" + "=" * 55)
print("RESULTADOS - ISOLATION FOREST")
print("=" * 55)

print("Total órdenes:", len(df))
print("Órdenes normales:", len(df) - cantidad_anomalias_if)
print("Órdenes anómalas:", cantidad_anomalias_if)
print(
    "Porcentaje anomalías:",
    round(porcentaje_anomalias_if, 2),
    "%"
)

print(
    "Score mínimo:",
    round(df["anomaly_score_if"].min(), 4)
)

print(
    "Score máximo:",
    round(df["anomaly_score_if"].max(), 4)
)


# ------------------------------------------------------------
# 9. MOSTRAR LAS 20 ÓRDENES MÁS ATÍPICAS
# ------------------------------------------------------------

top20_if = (
    df
    .sort_values(
        "anomaly_score_if",
        ascending=False
    )
    .head(20)
)

print("\nTOP 20 ÓRDENES MÁS ATÍPICAS - ISOLATION FOREST")
print("=" * 55)

print(
    top20_if[
        [
            "order_id",
            "anomaly_score_if",
            "anomaly_if"
        ]
    ].to_string(index=False)
)

# ============================================================
# PASO 6: MODELO 2 - LOCAL OUTLIER FACTOR (LOF)
# ============================================================

from sklearn.neighbors import LocalOutlierFactor

# ------------------------------------------------------------
# 1. CONFIGURACIÓN
# ------------------------------------------------------------
# Utilizamos la misma contaminación (2%) que Isolation Forest
# para que ambos modelos sean comparables.
#
# n_neighbors = 20:
# cada orden se compara con sus 20 vecinos más cercanos.
# ------------------------------------------------------------

modelo_lof = LocalOutlierFactor(
    n_neighbors=20,
    contamination=0.05,
    n_jobs=-1
)


# ------------------------------------------------------------
# 2. EJECUTAR LOF
# ------------------------------------------------------------
# LOF devuelve:
#  1 = comportamiento normal
# -1 = anomalía
# ------------------------------------------------------------

pred_lof = modelo_lof.fit_predict(X)


# ------------------------------------------------------------
# 3. OBTENER ANOMALY SCORE
# ------------------------------------------------------------
# negative_outlier_factor_:
# valores más negativos representan mayor rareza.
#
# Multiplicamos por -1 para que:
# mayor valor = mayor anomalía.
# ------------------------------------------------------------

score_lof_raw = -modelo_lof.negative_outlier_factor_


# ------------------------------------------------------------
# 4. NORMALIZAR SCORE ENTRE 0 Y 1
# ------------------------------------------------------------

scaler_lof = MinMaxScaler()

score_lof = scaler_lof.fit_transform(
    score_lof_raw.reshape(-1, 1)
).ravel()


# ------------------------------------------------------------
# 5. GUARDAR RESULTADOS
# ------------------------------------------------------------

df["anomaly_score_lof"] = score_lof

df["anomaly_lof"] = np.where(
    pred_lof == -1,
    1,
    0
)


# ------------------------------------------------------------
# 6. RESUMEN DEL MODELO LOF
# ------------------------------------------------------------

cantidad_anomalias_lof = df["anomaly_lof"].sum()

porcentaje_anomalias_lof = (
    cantidad_anomalias_lof / len(df)
) * 100


print("\n" + "=" * 55)
print("RESULTADOS - LOCAL OUTLIER FACTOR (LOF)")
print("=" * 55)

print("Total órdenes:", len(df))

print(
    "Órdenes normales:",
    len(df) - cantidad_anomalias_lof
)

print(
    "Órdenes anómalas:",
    cantidad_anomalias_lof
)

print(
    "Porcentaje anomalías:",
    round(porcentaje_anomalias_lof, 2),
    "%"
)

print(
    "Score mínimo:",
    round(df["anomaly_score_lof"].min(), 4)
)

print(
    "Score máximo:",
    round(df["anomaly_score_lof"].max(), 4)
)


# ------------------------------------------------------------
# 7. TOP 20 ÓRDENES MÁS ATÍPICAS SEGÚN LOF
# ------------------------------------------------------------

top20_lof = (
    df
    .sort_values(
        "anomaly_score_lof",
        ascending=False
    )
    .head(20)
)


print("\nTOP 20 ÓRDENES MÁS ATÍPICAS - LOF")
print("=" * 55)

print(
    top20_lof[
        [
            "order_id",
            "anomaly_score_lof",
            "anomaly_lof"
        ]
    ].to_string(index=False)
)

# ============================================================
# PASO 7: COMPARACIÓN DE LOS DOS MODELOS
# ISOLATION FOREST VS LOCAL OUTLIER FACTOR
# ============================================================

# ------------------------------------------------------------
# 1. IDENTIFICAR COINCIDENCIAS
# ------------------------------------------------------------
# consenso_modelos = 1:
# la orden fue considerada anómala por AMBOS modelos.
#
# solo_if = 1:
# únicamente Isolation Forest la considera anómala.
#
# solo_lof = 1:
# únicamente LOF la considera anómala.
# ------------------------------------------------------------

df["consenso_modelos"] = np.where(
    (df["anomaly_if"] == 1) &
    (df["anomaly_lof"] == 1),
    1,
    0
)

df["solo_if"] = np.where(
    (df["anomaly_if"] == 1) &
    (df["anomaly_lof"] == 0),
    1,
    0
)

df["solo_lof"] = np.where(
    (df["anomaly_if"] == 0) &
    (df["anomaly_lof"] == 1),
    1,
    0
)


# ------------------------------------------------------------
# 2. CONTAR RESULTADOS
# ------------------------------------------------------------

total_if = int(df["anomaly_if"].sum())

total_lof = int(df["anomaly_lof"].sum())

total_consenso = int(df["consenso_modelos"].sum())

total_solo_if = int(df["solo_if"].sum())

total_solo_lof = int(df["solo_lof"].sum())


# ------------------------------------------------------------
# 3. CALCULAR PORCENTAJE DE COINCIDENCIA
# ------------------------------------------------------------
# Calculamos qué porcentaje de las anomalías de IF
# también fueron detectadas por LOF.
# ------------------------------------------------------------

porcentaje_coincidencia = (
    total_consenso / total_if * 100
    if total_if > 0
    else 0
)


# ------------------------------------------------------------
# 4. MOSTRAR RESUMEN
# ------------------------------------------------------------

print("\n" + "=" * 60)
print("COMPARACIÓN DE MODELOS")
print("ISOLATION FOREST VS LOCAL OUTLIER FACTOR")
print("=" * 60)

print("Anomalías Isolation Forest:", total_if)
print("Anomalías LOF:", total_lof)
print("Anomalías detectadas por ambos:", total_consenso)
print("Solo Isolation Forest:", total_solo_if)
print("Solo LOF:", total_solo_lof)

print(
    "Porcentaje de coincidencia:",
    round(porcentaje_coincidencia, 2),
    "%"
)


# ------------------------------------------------------------
# 5. CREAR SCORE COMBINADO
# ------------------------------------------------------------
# Promediamos los scores normalizados de ambos modelos.
#
# Esto NO reemplaza los modelos.
# Nos permite priorizar las órdenes que presentan
# mayor rareza considerando ambas metodologías.
# ------------------------------------------------------------

df["anomaly_score_combinado"] = (
    df["anomaly_score_if"] +
    df["anomaly_score_lof"]
) / 2


# ------------------------------------------------------------
# 6. TOP 20 POR SCORE COMBINADO
# ------------------------------------------------------------

top20_combinado = (
    df
    .sort_values(
        "anomaly_score_combinado",
        ascending=False
    )
    .head(20)
)


print("\n" + "=" * 60)
print("TOP 20 - SCORE COMBINADO")
print("=" * 60)

print(
    top20_combinado[
        [
            "order_id",
            "anomaly_score_if",
            "anomaly_score_lof",
            "anomaly_score_combinado",
            "anomaly_if",
            "anomaly_lof",
            "consenso_modelos"
        ]
    ].to_string(index=False)
)

# ============================================================
# PASO 8: EXPLICABILIDAD Y PERFILES DE ANOMALÍA
# ============================================================

# ------------------------------------------------------------
# OBJETIVO
# ------------------------------------------------------------
# Explicar por qué una orden puede considerarse atípica.
#
# Utilizamos las variables estandarizadas (Z-score).
# Como referencia, |Z| >= 3 representa un comportamiento
# extremadamente alejado del comportamiento general.
#
# IMPORTANTE:
# Una anomalía NO significa automáticamente fraude.
# Es un caso que merece revisión.
# ------------------------------------------------------------


# ------------------------------------------------------------
# 1. FUNCIÓN PARA IDENTIFICAR EL PERFIL DE CADA ORDEN
# ------------------------------------------------------------

def obtener_perfil_anomalia(fila):

    perfiles = []

    # --------------------------------------------------------
    # FREIGHT DESPROPORCIONADO
    # --------------------------------------------------------
    if (
        fila["z_proporcion_freight_precio"] >= 3
        or fila["flag_freight_alto"] == 1
    ):
        perfiles.append("Freight desproporcionado")

    # --------------------------------------------------------
    # ORDEN DE ALTO VALOR
    # --------------------------------------------------------
    if fila["z_log_monto_total"] >= 3:
        perfiles.append("Orden de alto valor")

    # --------------------------------------------------------
    # PESO EXTREMO
    # --------------------------------------------------------
    if fila["z_log_peso"] >= 3:
        perfiles.append("Peso agregado extremo")

    # --------------------------------------------------------
    # VOLUMEN EXTREMO
    # --------------------------------------------------------
    if fila["z_log_volumen"] >= 3:
        perfiles.append("Volumen agregado extremo")

    # --------------------------------------------------------
    # CANTIDAD INUSUAL DE ÍTEMS
    # --------------------------------------------------------
    if fila["z_numero_items"] >= 3:
        perfiles.append("Cantidad de ítems inusual")

    # --------------------------------------------------------
    # MÚLTIPLES VENDEDORES
    # --------------------------------------------------------
    if fila["z_numero_vendedores"] >= 3:
        perfiles.append("Número de vendedores inusual")

    # --------------------------------------------------------
    # COMBINACIÓN DE PAGOS INUSUAL
    # --------------------------------------------------------
    if (
        fila["z_numero_pagos"] >= 3
        or fila["z_tipos_pago_distintos"] >= 3
        or fila["z_max_cuotas"] >= 3
    ):
        perfiles.append("Combinación de pagos inusual")

    # --------------------------------------------------------
    # TIEMPO LOGÍSTICO EXTREMO
    # --------------------------------------------------------
    if abs(fila["z_horas_compra_entrega"]) >= 3:
        perfiles.append("Tiempo logístico extremo")

    # --------------------------------------------------------
    # RETRASO DE ENTREGA EXTREMO
    # --------------------------------------------------------
    if abs(fila["z_dias_retraso_entrega"]) >= 3:
        perfiles.append("Desviación extrema en entrega")

    # --------------------------------------------------------
    # DIFERENCIA ENTRE MONTO DE ORDEN Y PAGO
    # --------------------------------------------------------
    if (
        abs(fila["z_diferencia_pago"]) >= 3
        or fila["flag_diferencia_pago"] == 1
    ):
        perfiles.append("Diferencia inusual entre orden y pago")

    # --------------------------------------------------------
    # PROBLEMAS DE CALIDAD / INTEGRIDAD
    # --------------------------------------------------------
    if fila["flag_sin_items"] == 1:
        perfiles.append("Orden sin ítems")

    if fila["flag_sin_pago"] == 1:
        perfiles.append("Orden sin pago")

    if fila["flag_fecha_incoherente"] == 1:
        perfiles.append("Fechas logísticas incoherentes")

    if fila["flag_sin_proporcion_freight"] == 1:
        perfiles.append("Proporción freight no disponible")

    if fila["flag_sin_tiempo_entrega"] == 1:
        perfiles.append("Tiempo de entrega no disponible")

    if fila["flag_sin_retraso_entrega"] == 1:
        perfiles.append("Retraso de entrega no disponible")

    # --------------------------------------------------------
    # SI NINGUNA REGLA INDIVIDUAL SUPERA EL UMBRAL
    # --------------------------------------------------------
    # Esto puede suceder porque los algoritmos multivariados
    # detectan combinaciones raras de variables aunque ninguna
    # variable individual tenga un Z-score >= 3.
    # --------------------------------------------------------

    if len(perfiles) == 0:
        perfiles.append("Combinación multivariada inusual")

    return " | ".join(perfiles)


# ------------------------------------------------------------
# 2. GENERAR PERFIL PARA TODAS LAS ÓRDENES
# ------------------------------------------------------------

df["perfil_anomalia"] = df.apply(
    obtener_perfil_anomalia,
    axis=1
)


# ------------------------------------------------------------
# 3. CREAR NIVEL DE PRIORIDAD OPERATIVA
# ------------------------------------------------------------
# PRIORIDAD ALTA:
# detectada por ambos modelos.
#
# PRIORIDAD MEDIA:
# detectada únicamente por uno de los modelos.
#
# SIN ALERTA:
# ninguno de los modelos la marcó.
# ------------------------------------------------------------

df["prioridad_revision"] = np.select(
    [
        df["consenso_modelos"] == 1,

        (
            (df["anomaly_if"] == 1) |
            (df["anomaly_lof"] == 1)
        )
    ],
    [
        "ALTA",
        "MEDIA"
    ],
    default="SIN ALERTA"
)


# ------------------------------------------------------------
# 4. CONTAR PERFILES ENTRE LAS ANOMALÍAS
# ------------------------------------------------------------

anomalias = df[
    (df["anomaly_if"] == 1) |
    (df["anomaly_lof"] == 1)
].copy()


print("\n" + "=" * 70)
print("PERFILES DE ANOMALÍA")
print("=" * 70)

print(
    anomalias["perfil_anomalia"]
    .value_counts()
    .head(20)
    .to_string()
)


# ------------------------------------------------------------
# 5. TOP 20 EXPLICABLE
# ------------------------------------------------------------
# Priorizamos primero el score combinado.
# ------------------------------------------------------------

top20_explicable = (
    df[
        (df["anomaly_if"] == 1) |
        (df["anomaly_lof"] == 1)
    ]
    .sort_values(
        "anomaly_score_combinado",
        ascending=False
    )
    .head(20)
)


print("\n" + "=" * 70)
print("TOP 20 ANOMALÍAS EXPLICABLES")
print("=" * 70)

columnas_top20 = [
    "order_id",
    "anomaly_score_if",
    "anomaly_score_lof",
    "anomaly_score_combinado",
    "consenso_modelos",
    "prioridad_revision",
    "perfil_anomalia"
]

print(
    top20_explicable[
        columnas_top20
    ].to_string(index=False)
)

# ============================================================
# PASO 9: ANÁLISIS DE SENSIBILIDAD DE LA CONTAMINACIÓN
# ============================================================

# OBJETIVO:
# Evaluar cómo cambia la cantidad de anomalías detectadas
# cuando modificamos el porcentaje esperado de contaminación.
#
# Se evaluarán:
# 1 %
# 2 %
# 3 %
# 5 %
#
# Esto permite justificar técnicamente el umbral seleccionado
# y comprobar si los resultados son estables.


# ------------------------------------------------------------
# 1. DEFINIR NIVELES DE CONTAMINACIÓN
# ------------------------------------------------------------

niveles_contaminacion = [0.01, 0.02, 0.03, 0.05]

resultados_sensibilidad = []


# ------------------------------------------------------------
# 2. EJECUTAR ISOLATION FOREST PARA CADA NIVEL
# ------------------------------------------------------------

for contaminacion in niveles_contaminacion:

    modelo_sensibilidad = IsolationForest(
        n_estimators=200,
        contamination=contaminacion,
        random_state=42,
        n_jobs=-1
    )

    predicciones = modelo_sensibilidad.fit_predict(X)

    # Isolation Forest devuelve:
    # -1 = anomalía
    #  1 = normal

    cantidad_anomalias = np.sum(predicciones == -1)

    porcentaje_real = (
        cantidad_anomalias / len(X)
    ) * 100

    resultados_sensibilidad.append({
        "contaminacion": contaminacion,
        "porcentaje_configurado": contaminacion * 100,
        "cantidad_anomalias": cantidad_anomalias,
        "porcentaje_detectado": porcentaje_real
    })


# ------------------------------------------------------------
# 3. CONVERTIR RESULTADOS EN DATAFRAME
# ------------------------------------------------------------

df_sensibilidad = pd.DataFrame(resultados_sensibilidad)


print("\n" + "=" * 70)
print("ANÁLISIS DE SENSIBILIDAD - ISOLATION FOREST")
print("=" * 70)

print(
    df_sensibilidad.to_string(
        index=False
    )
)


# ------------------------------------------------------------
# 4. ESTABILIDAD DEL TOP 20
# ------------------------------------------------------------
# Ahora verificamos si las órdenes más extremas continúan
# apareciendo cuando cambiamos la contaminación.
#
# Si una orden aparece repetidamente, tenemos mayor evidencia
# de que realmente posee un comportamiento atípico.
# ------------------------------------------------------------

apariciones_top = {}


for contaminacion in niveles_contaminacion:

    modelo_temp = IsolationForest(
        n_estimators=200,
        contamination=contaminacion,
        random_state=42,
        n_jobs=-1
    )

    modelo_temp.fit(X)

    # decision_function:
    # valores menores representan observaciones más anómalas.
    score_temp = -modelo_temp.decision_function(X)

    resultado_temp = pd.DataFrame({
        "order_id": df["order_id"].values,
        "score": score_temp
    })

    top20_temp = (
        resultado_temp
        .sort_values("score", ascending=False)
        .head(20)
    )

    for order_id in top20_temp["order_id"]:

        apariciones_top[order_id] = (
            apariciones_top.get(order_id, 0) + 1
        )


# ------------------------------------------------------------
# 5. MOSTRAR ESTABILIDAD
# ------------------------------------------------------------

df_estabilidad = pd.DataFrame(
    list(apariciones_top.items()),
    columns=[
        "order_id",
        "apariciones_top20"
    ]
)

df_estabilidad = df_estabilidad.sort_values(
    "apariciones_top20",
    ascending=False
)


print("\n" + "=" * 70)
print("ESTABILIDAD DEL TOP 20")
print("=" * 70)

print(
    df_estabilidad
    .head(20)
    .to_string(index=False)
)


# ------------------------------------------------------------
# 6. RESUMEN
# ------------------------------------------------------------

estables_4 = (
    df_estabilidad["apariciones_top20"] == 4
).sum()

estables_3_o_mas = (
    df_estabilidad["apariciones_top20"] >= 3
).sum()


print("\n" + "=" * 70)
print("RESUMEN DE ESTABILIDAD")
print("=" * 70)

print(
    "Órdenes presentes en el Top 20 "
    "en los 4 escenarios:",
    estables_4
)

print(
    "Órdenes presentes en el Top 20 "
    "en al menos 3 escenarios:",
    estables_3_o_mas
)

# ============================================================
# PASO 10: CONSTRUIR SCORING FINAL DE ANOMALÍAS
# ============================================================

# OBJETIVO:
# Crear un score final normalizado entre 0 y 1 por order_id.
#
# El score combinará:
# - Isolation Forest
# - Local Outlier Factor (LOF)
#
# Interpretación:
# 0 = comportamiento más normal
# 1 = comportamiento más atípico
#
# Se mantiene el 2 % como contaminación seleccionada,
# respaldado por el análisis de sensibilidad del Paso 9.


# ------------------------------------------------------------
# 1. VERIFICAR QUE EXISTEN LOS SCORES DE AMBOS MODELOS
# ------------------------------------------------------------

print("\n" + "=" * 70)
print("PASO 10 - SCORING FINAL")
print("=" * 70)

print("Órdenes disponibles:", len(df))

print(
    "Score IF mínimo:",
    round(df["anomaly_score_if"].min(), 6)
)

print(
    "Score IF máximo:",
    round(df["anomaly_score_if"].max(), 6)
)

print(
    "Score LOF mínimo:",
    round(df["anomaly_score_lof"].min(), 6)
)

print(
    "Score LOF máximo:",
    round(df["anomaly_score_lof"].max(), 6)
)


# ------------------------------------------------------------
# 2. CALCULAR SCORE COMBINADO
# ------------------------------------------------------------
# Ambos scores ya están normalizados entre 0 y 1.
#
# Utilizamos el promedio de ambos métodos.
# Esto evita depender exclusivamente de un solo algoritmo.
# ------------------------------------------------------------

df["anomaly_score_final"] = (
    df["anomaly_score_if"] +
    df["anomaly_score_lof"]
) / 2


# ------------------------------------------------------------
# 3. ASEGURAR RANGO ENTRE 0 Y 1
# ------------------------------------------------------------

df["anomaly_score_final"] = (
    df["anomaly_score_final"]
    .clip(0, 1)
)


# ------------------------------------------------------------
# 4. CLASIFICACIÓN FINAL
# ------------------------------------------------------------
# Se considera anomalía de alta confianza cuando
# ambos algoritmos coinciden.
#
# Esto NO significa fraude.
# Significa que la orden merece revisión.
# ------------------------------------------------------------

df["anomalia_consenso"] = (
    (df["anomaly_if"] == 1) &
    (df["anomaly_lof"] == 1)
).astype(int)


# ------------------------------------------------------------
# 5. NIVEL DE RAREZA
# ------------------------------------------------------------
# Clasificación operativa según score final.
#
# Esta clasificación facilita la priorización.
# ------------------------------------------------------------

df["nivel_rareza"] = pd.cut(
    df["anomaly_score_final"],
    bins=[
        -0.001,
        0.25,
        0.50,
        0.75,
        1.00
    ],
    labels=[
        "Baja",
        "Media",
        "Alta",
        "Muy alta"
    ]
)


# ------------------------------------------------------------
# 6. PRIORIDAD DE REVISIÓN
# ------------------------------------------------------------
# ALTA:
# Ambos modelos consideran la orden anómala.
#
# MEDIA:
# Solo uno de los modelos la considera anómala.
#
# BAJA:
# Ningún modelo la considera anómala.
# ------------------------------------------------------------

df["prioridad_modelo"] = np.select(
    [
        (df["anomaly_if"] == 1) &
        (df["anomaly_lof"] == 1),

        (df["anomaly_if"] == 1) |
        (df["anomaly_lof"] == 1)
    ],
    [
        "ALTA",
        "MEDIA"
    ],
    default="BAJA"
)


# ------------------------------------------------------------
# 7. CREAR DATASET FINAL DE SCORING
# ------------------------------------------------------------

columnas_scoring = [
    "order_id",
    "anomaly_score_if",
    "anomaly_score_lof",
    "anomaly_score_final",
    "anomaly_if",
    "anomaly_lof",
    "anomalia_consenso",
    "nivel_rareza",
    "prioridad_modelo",
    "perfil_anomalia"
]

df_scoring = df[columnas_scoring].copy()


# ------------------------------------------------------------
# 8. ORDENAR DE MAYOR A MENOR RAREZA
# ------------------------------------------------------------

df_scoring = df_scoring.sort_values(
    by="anomaly_score_final",
    ascending=False
)


# ------------------------------------------------------------
# 9. VALIDACIONES
# ------------------------------------------------------------

print("\n" + "=" * 70)
print("VALIDACIÓN DEL SCORING")
print("=" * 70)

print("Registros:", len(df_scoring))

print(
    "Órdenes únicas:",
    df_scoring["order_id"].nunique()
)

print(
    "Duplicados:",
    df_scoring["order_id"].duplicated().sum()
)

print(
    "NULL score final:",
    df_scoring["anomaly_score_final"].isna().sum()
)

print(
    "Score mínimo:",
    round(df_scoring["anomaly_score_final"].min(), 6)
)

print(
    "Score máximo:",
    round(df_scoring["anomaly_score_final"].max(), 6)
)

print(
    "Anomalías por consenso:",
    df_scoring["anomalia_consenso"].sum()
)


# ------------------------------------------------------------
# 10. DISTRIBUCIÓN POR PRIORIDAD
# ------------------------------------------------------------

print("\n" + "=" * 70)
print("DISTRIBUCIÓN POR PRIORIDAD")
print("=" * 70)

print(
    df_scoring["prioridad_modelo"]
    .value_counts()
)


# ------------------------------------------------------------
# 11. DISTRIBUCIÓN POR NIVEL DE RAREZA
# ------------------------------------------------------------

print("\n" + "=" * 70)
print("DISTRIBUCIÓN POR NIVEL DE RAREZA")
print("=" * 70)

print(    df_scoring["nivel_rareza"]
    .value_counts()
    .sort_index()
)
# ------------------------------------------------------------
# 12. TOP 20 FINAL
# ------------------------------------------------------------

print("\n" + "=" * 70)
print("TOP 20 - SCORING FINAL DE ANOMALÍAS")
print("=" * 70)

print(
    df_scoring[
        [
            "order_id",
            "anomaly_score_final",
            "anomaly_score_if",
            "anomaly_score_lof",
            "anomalia_consenso",
            "prioridad_modelo",
            "perfil_anomalia"
        ]
    ]
    .head(20)
    .to_string(index=False)
)

# ============================================================
# PASO 11: PREPARAR RESULTADO FINAL PARA SQL SERVER
# ============================================================

print("\n" + "=" * 70)
print("PASO 11 - PREPARAR SCORING PARA GOLD")
print("=" * 70)


# ------------------------------------------------------------
# 1. CREAR DATAFRAME PARA EXPORTACIÓN
# ------------------------------------------------------------

df_gold_scoring = df_scoring.copy()


# ------------------------------------------------------------
# 2. CONVERTIR nivel_rareza A TEXTO
# ------------------------------------------------------------
# pd.cut genera una variable categórica.
# Para SQL Server es más conveniente enviarla como texto.

df_gold_scoring["nivel_rareza"] = (
    df_gold_scoring["nivel_rareza"]
    .astype(str)
)


# ------------------------------------------------------------
# 3. VALIDAR ORDER_ID
# ------------------------------------------------------------

print("Registros:", len(df_gold_scoring))

print(
    "Órdenes únicas:",
    df_gold_scoring["order_id"].nunique()
)

print(
    "Duplicados:",
    df_gold_scoring["order_id"].duplicated().sum()
)


# ------------------------------------------------------------
# 4. VALIDAR SCORES
# ------------------------------------------------------------

print(
    "NULL score IF:",
    df_gold_scoring["anomaly_score_if"].isna().sum()
)

print(
    "NULL score LOF:",
    df_gold_scoring["anomaly_score_lof"].isna().sum()
)

print(
    "NULL score final:",
    df_gold_scoring["anomaly_score_final"].isna().sum()
)


# ------------------------------------------------------------
# 5. VALIDAR RANGO DEL SCORE FINAL
# ------------------------------------------------------------

scores_fuera_rango = (
    (df_gold_scoring["anomaly_score_final"] < 0) |
    (df_gold_scoring["anomaly_score_final"] > 1)
).sum()

print(
    "Scores fuera del rango 0-1:",
    scores_fuera_rango
)


# ------------------------------------------------------------
# 6. MOSTRAR RESUMEN
# ------------------------------------------------------------

print("\n" + "=" * 70)
print("RESUMEN DATASET PARA GOLD")
print("=" * 70)

print(
    df_gold_scoring[
        [
            "order_id",
            "anomaly_score_final",
            "anomalia_consenso",
            "nivel_rareza",
            "prioridad_modelo",
            "perfil_anomalia"
        ]
    ]
    .head(10)
    .to_string(index=False)
)

# ============================================================
# PASO 12: GUARDAR SCORING FINAL EN SQL SERVER
# ============================================================
#
# OBJETIVO:
# Crear la tabla Gold con el resultado final del modelo.
#
# Una fila = una orden.
#
# Esta tabla contiene:
# - Score Isolation Forest
# - Score LOF
# - Score final combinado
# - Indicadores de anomalía
# - Consenso entre modelos
# - Nivel de rareza
# - Prioridad de revisión
# - Explicación / perfil de anomalía
#
# IMPORTANTE:
# Una anomalía NO significa fraude.
# Indica una orden que merece revisión.
# ============================================================

print("\n" + "=" * 70)
print("PASO 12 - GUARDAR SCORING EN SQL SERVER")
print("=" * 70)


# ------------------------------------------------------------
# 1. CREAR CURSOR
# ------------------------------------------------------------

cursor = conexion.cursor()


# ------------------------------------------------------------
# 2. ELIMINAR TABLA SI YA EXISTE
# ------------------------------------------------------------
# Esto permite volver a ejecutar el proceso completo
# sin generar duplicados.
# ------------------------------------------------------------

cursor.execute("""
IF OBJECT_ID('gold.order_anomaly_scoring', 'U') IS NOT NULL
    DROP TABLE gold.order_anomaly_scoring;
""")

conexion.commit()


# ------------------------------------------------------------
# 3. CREAR TABLA GOLD
# ------------------------------------------------------------

cursor.execute("""
CREATE TABLE gold.order_anomaly_scoring
(
    order_id NVARCHAR(50) NOT NULL,

    anomaly_score_if FLOAT NOT NULL,
    anomaly_score_lof FLOAT NOT NULL,
    anomaly_score_final FLOAT NOT NULL,

    anomaly_if TINYINT NOT NULL,
    anomaly_lof TINYINT NOT NULL,
    anomalia_consenso TINYINT NOT NULL,

    nivel_rareza NVARCHAR(20) NOT NULL,
    prioridad_modelo NVARCHAR(20) NOT NULL,

    perfil_anomalia NVARCHAR(2000) NULL,

    CONSTRAINT PK_gold_order_anomaly_scoring
        PRIMARY KEY (order_id)
);
""")

conexion.commit()

print("Tabla gold.order_anomaly_scoring creada correctamente.")


# ------------------------------------------------------------
# 4. PREPARAR INSERT
# ------------------------------------------------------------

sql_insert = """
INSERT INTO gold.order_anomaly_scoring
(
    order_id,
    anomaly_score_if,
    anomaly_score_lof,
    anomaly_score_final,
    anomaly_if,
    anomaly_lof,
    anomalia_consenso,
    nivel_rareza,
    prioridad_modelo,
    perfil_anomalia
)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
"""


# ------------------------------------------------------------
# 5. PREPARAR LOS DATOS
# ------------------------------------------------------------

datos_insertar = []

for fila in df_gold_scoring.itertuples(index=False):

    datos_insertar.append(
        (
            str(fila.order_id),

            float(fila.anomaly_score_if),
            float(fila.anomaly_score_lof),
            float(fila.anomaly_score_final),

            int(fila.anomaly_if),
            int(fila.anomaly_lof),
            int(fila.anomalia_consenso),

            str(fila.nivel_rareza),
            str(fila.prioridad_modelo),

            None
            if pd.isna(fila.perfil_anomalia)
            else str(fila.perfil_anomalia)
        )
    )


# ------------------------------------------------------------
# 6. ACTIVAR INSERCIÓN RÁPIDA
# ------------------------------------------------------------
cursor.fast_executemany = True


# ------------------------------------------------------------
# 7. INSERTAR LOS 99.441 REGISTROS POR LOTES
# ------------------------------------------------------------
# Se insertan grupos pequeños de registros para evitar
# saturar la memoria disponible de SQL Server.

tamano_lote = 500
total_registros = len(datos_insertar)

print("Iniciando inserción por lotes...")
print("Total de registros a insertar:", total_registros)

for inicio in range(0, total_registros, tamano_lote):

    fin = min(inicio + tamano_lote, total_registros)

    lote = datos_insertar[inicio:fin]

    cursor.executemany(
        sql_insert,
        lote
    )

    # Confirmamos cada lote para liberar recursos
    conexion.commit()

    print(
        f"Insertados {fin} de {total_registros} registros"
    )


print("=" * 70)
print("Datos insertados correctamente.")
print("Registros enviados:", total_registros)
print("=" * 70)

# 8. VALIDAR DESDE SQL SERVER
# ------------------------------------------------------------

cursor.execute("""
SELECT
    COUNT(*) AS total_registros,
    COUNT(DISTINCT order_id) AS ordenes_unicas,
    SUM(CASE WHEN anomalia_consenso = 1 THEN 1 ELSE 0 END)
        AS anomalias_consenso,
    MIN(anomaly_score_final) AS score_minimo,
    MAX(anomaly_score_final) AS score_maximo
FROM gold.order_anomaly_scoring;
""")

resultado = cursor.fetchone()


print("\n" + "=" * 70)
print("VALIDACIÓN DE TABLA GOLD")
print("=" * 70)

print("Registros:", resultado[0])
print("Órdenes únicas:", resultado[1])
print("Anomalías por consenso:", resultado[2])
print("Score mínimo:", resultado[3])
print("Score máximo:", resultado[4])


# ------------------------------------------------------------
# 9. CERRAR CURSOR
# ------------------------------------------------------------

cursor.close()


print("\n" + "=" * 70)
print("TABLA GOLD CREADA CORRECTAMENTE")
print("=" * 70)

print("Tabla: gold.order_anomaly_scoring")