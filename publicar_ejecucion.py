"""Publica una ejecución terminada sin volver a entrenar; verifica primero su snapshot."""
import argparse
import json
from pathlib import Path

import pandas as pd
from soporte_proyecto import conectar, publicar_sql


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('carpeta')
    parser.add_argument('--server', default='TU_SERVIDOR')
    args = parser.parse_args()
    out = Path(args.carpeta)
    metadata = json.loads((out/'metadata.json').read_text(encoding='utf-8'))
    features = pd.read_csv(out/'order_anomaly_features.csv', dtype={
        'order_id': 'str', 'customer_id': 'str', 'customer_zip_code_prefix': 'str',
        'seller_zip_referencia': 'str'})
    result = pd.read_csv(out/'order_anomaly_scoring.csv')
    cn = conectar(args.server, readonly=True)
    try:
        actual = pd.read_sql_query('SELECT * FROM gold.order_anomaly_features ORDER BY order_id', cn)
    finally:
        cn.close()
    # El CSV conserva el snapshot completo; verifica todas las columnas de la fuente.
    previo = features[list(actual.columns)].sort_values('order_id').reset_index(drop=True)
    for col in actual:
        if pd.api.types.is_datetime64_any_dtype(actual[col]):
            previo[col] = pd.to_datetime(previo[col], errors='raise')
    pd.testing.assert_frame_equal(actual, previo, check_dtype=False, rtol=1e-12, atol=1e-9)
    enriquecidas = features if metadata.get('distancia_disponible') else None
    publicar_sql(args.server, result, actual, enriquecidas)
    metadata['publicacion_sql'] = 'Completada en transacción única; scoring y distancia Gold'
    (out/'metadata.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Publicación comprobada: scoring y distancia Gold. Actualiza Power BI.')


if __name__ == '__main__':
    main()
