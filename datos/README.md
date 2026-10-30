# Datos externos

No se incluyen los datos ni resultados locales en este repositorio.
El proyecto utiliza Brazilian E-Commerce Public Dataset by Olist.
Obtén los CSV de su fuente: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
Consulta sus condiciones de uso antes de redistribuirlos.

La carga inicial de Bronze debe realizarse por separado. El script SQL presupone esas tablas cargadas.
Para habilitar la distancia aproximada, coloca aquí `olist_geolocation_dataset.csv`.
Si falta, el análisis continúa sin distancia y registra esta limitación.
