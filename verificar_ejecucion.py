"""Compara todas las filas publicadas contra los archivos de una ejecución."""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
import pandas as pd
from soporte_proyecto import conectar


def verificar(carpeta, servidor):
    out = Path(carpeta)
    metadata = json.loads((out/'metadata.json').read_text(encoding='utf-8'))
    cols = ['order_id','anomaly_score_if','anomaly_score_lof','anomaly_score_final',
            'anomaly_if','anomaly_lof','anomalia_consenso','nivel_rareza','prioridad_modelo','perfil_anomalia']
    local = pd.read_csv(out/'order_anomaly_scoring.csv')[cols].sort_values('order_id').reset_index(drop=True)
    cn = conectar(servidor, readonly=True)
    try:
        sql = pd.read_sql_query('SELECT '+','.join(cols)+' FROM gold.order_anomaly_scoring ORDER BY order_id',cn)
        pd.testing.assert_frame_equal(sql,local,check_dtype=False,rtol=1e-12,atol=1e-12)
        if metadata.get('distancia_disponible'):
            geo_cols = ['order_id','distancia_aproximada_km','cobertura_distancia','pares_con_distancia','pares_vendedor']
            geo_sql = pd.read_sql_query('SELECT '+','.join(geo_cols)+' FROM gold.order_anomaly_features ORDER BY order_id',cn)
            geo_local = pd.read_csv(out/'order_anomaly_features.csv')[geo_cols].sort_values('order_id').reset_index(drop=True)
            pd.testing.assert_frame_equal(geo_sql,geo_local,check_dtype=False,rtol=1e-12,atol=1e-9)
    finally:
        cn.close()
    evidencia = {'fecha_utc':datetime.now(timezone.utc).isoformat(),'run_id':metadata['run_id'],
                 'filas_scoring':len(local),'campos_scoring':len(cols),
                 'scoring_coincide':True,'distancias_coinciden':bool(metadata.get('distancia_disponible'))}
    (out/'verificacion_sql.json').write_text(json.dumps(evidencia,indent=2),encoding='utf-8')
    print(json.dumps(evidencia,indent=2))


if __name__ == '__main__':
    verificar(sys.argv[1],sys.argv[2] if len(sys.argv)>2 else 'JUAN')
