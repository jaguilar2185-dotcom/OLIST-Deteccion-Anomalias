"""OLIST: lectura de Gold y salidas locales. Nunca escribe en SQL Server.
Uso: python auditar_y_puntuar.py --server JUAN --output resultados
Requiere pandas, numpy, pyodbc y scikit-learn.
El 2% es presupuesto exploratorio de revisión, no prevalencia de fraude.
"""
import argparse
import json
from pathlib import Path
import numpy as np
import pandas as pd
import pyodbc
from sklearn.ensemble import IsolationForest
from sklearn.neighbors import LocalOutlierFactor
from sklearn.preprocessing import StandardScaler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', default='JUAN')
    parser.add_argument('--output', default='resultados')
    parser.add_argument('--excel', action='store_true', help='Generar además el reporte de Excel con gráficos')
    args = parser.parse_args()
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    # Utilizar además un usuario con permiso SELECT exclusivamente.
    cn = pyodbc.connect(
        'DRIVER={ODBC Driver 17 for SQL Server};'
        f'SERVER={args.server};DATABASE=OLIST_DW;Trusted_Connection=yes;'
        'TrustServerCertificate=yes;', readonly=True)
    try:
        df = pd.read_sql_query('SELECT * FROM gold.order_anomaly_features ORDER BY order_id', cn)
    finally:
        cn.close()
    if len(df) < 22 or df.order_id.isna().any() or df.order_id.duplicated().any():
        raise ValueError('Se requieren al menos 22 órdenes con identificadores únicos y no nulos.')
    columns = ['monto_total_orden', 'freight_total', 'proporcion_freight_precio',
               'numero_items', 'numero_vendedores', 'numero_pagos', 'max_cuotas',
               'peso_total_g', 'volumen_total_cm3', 'horas_compra_entrega',
               'dias_retraso_entrega', 'tipos_pago_distintos', 'monto_pagado']
    raw = df[columns].apply(pd.to_numeric, errors='raise')
    if np.isinf(raw.to_numpy(dtype=float)).any():
        raise ValueError('Hay infinitos en las variables originales.')
    raw['diferencia_pago'] = raw.monto_total_orden - raw.monto_pagado
    raw = raw.drop(columns='monto_pagado')
    # Conservar valores negativos para diagnóstico; no aplicar log1p a negativos.
    logcols = ['monto_total_orden', 'freight_total', 'peso_total_g', 'volumen_total_cm3']
    transformed = raw.copy()
    for col in logcols:
        transformed[col] = np.sign(raw[col]) * np.log1p(raw[col].abs())
    medians = transformed.median()
    if medians.isna().any():
        raise ValueError('Una variable está completamente vacía; revisar Gold.')
    missing = transformed.isna().astype(int)
    missing = missing.loc[:, missing.any()]
    scaler = StandardScaler()
    z = pd.DataFrame(scaler.fit_transform(transformed.fillna(medians)), columns=raw.columns)
    X = pd.concat([z, missing.add_prefix('sin_')], axis=1)
    if not np.isfinite(X.to_numpy()).all():
        raise ValueError('Matriz no finita.')
    iforest = IsolationForest(n_estimators=200, contamination=.02, random_state=42, n_jobs=-1)
    lof = LocalOutlierFactor(n_neighbors=20, contamination=.02, n_jobs=-1)
    flags_if = iforest.fit_predict(X) == -1
    flags_lof = lof.fit_predict(X) == -1
    scores_if = -iforest.score_samples(X)
    scores_lof = -lof.negative_outlier_factor_
    # Percentiles empíricos comparables dentro de esta cohorte; no probabilidades.
    def percentile(values):
        ranks = pd.Series(values).rank(method='average')
        return (ranks - 1) / (len(ranks) - 1)
    result = pd.DataFrame({'order_id': df.order_id,
                           'score_if_raw': scores_if, 'score_lof_raw': scores_lof,
                           'anomaly_score_if': percentile(scores_if),
                           'anomaly_score_lof': percentile(scores_lof),
                           'anomaly_if': flags_if.astype(int),
                           'anomaly_lof': flags_lof.astype(int)})
    result['anomaly_score_final'] = result[['anomaly_score_if', 'anomaly_score_lof']].mean(axis=1)
    result['anomalia_consenso'] = (flags_if & flags_lof).astype(int)
    result['prioridad_modelo'] = np.select([flags_if & flags_lof, flags_if | flags_lof],
                                          ['ALTA', 'MEDIA'], default='BAJA')
    # Descriptores de desviación, no atribuciones causales del modelo.
    def explain(i):
        top = z.iloc[i].abs().nlargest(3).index
        return ' | '.join(f'{c}: valor={raw.loc[i, c]:.4g}, z={z.loc[i, c]:.2f}' for c in top)
    result['variables_revision'] = [explain(i) for i in range(len(df))]
    result['flag_diferencia_pago'] = (raw.diferencia_pago.abs() > .01).astype(int)
    result['flag_freight_alto'] = (raw.proporcion_freight_precio > 1).astype(int)
    result['flag_monto_negativo'] = (raw[['monto_total_orden', 'freight_total']].lt(0).any(axis=1)).astype(int)
    ranked = result.sort_values(['anomaly_score_final', 'order_id'], ascending=[False, True])
    ranked.to_csv(out / 'order_anomaly_scoring.csv', index=False, encoding='utf-8-sig')
    details = ranked.head(20).merge(df, on='order_id', validate='one_to_one')
    details.to_csv(out / 'top20_explicado.csv', index=False, encoding='utf-8-sig')
    def jaccard(a, b):
        return len(a & b) / len(a | b) if a | b else 1.0
    baseline = set(np.flatnonzero(flags_if))
    sensitivity = []
    for seed in [7, 21, 84]:
        model = IsolationForest(n_estimators=200, contamination=.02, random_state=seed, n_jobs=-1)
        selected = set(np.flatnonzero(model.fit_predict(X) == -1))
        sensitivity.append({'method': 'IF', 'parameter': 'seed', 'value': seed,
                            'jaccard_base': jaccard(baseline, selected)})
    baseline_lof = set(np.flatnonzero(flags_lof))
    for k in [10, 40]:
        model = LocalOutlierFactor(n_neighbors=min(k, len(df)-1), contamination=.02, n_jobs=-1)
        selected = set(np.flatnonzero(model.fit_predict(X) == -1))
        sensitivity.append({'method': 'LOF', 'parameter': 'neighbors', 'value': k,
                            'jaccard_base': jaccard(baseline_lof, selected)})
    pd.DataFrame(sensitivity).to_csv(out / 'estabilidad.csv', index=False)
    # Sensibilidad del umbral: no requiere reentrenar los modelos.
    cuts = []
    for c in [.01, .02, .03, .05]:
        a = set(np.flatnonzero(scores_if > np.quantile(scores_if, 1-c)))
        b = set(np.flatnonzero(scores_lof > np.quantile(scores_lof, 1-c)))
        cuts.append({'contamination': c, 'if_count': len(a), 'lof_count': len(b),
                     'jaccard_methods': jaccard(a, b)})
    pd.DataFrame(cuts).to_csv(out / 'sensibilidad_umbral.csv', index=False)
    metadata = {'rows': len(df), 'source': 'gold.order_anomaly_features',
                'contamination': .02, 'seed': 42, 'log_signed_columns': logcols,
                'medians_transformed': medians.to_dict(), 'columns_scaled': list(z.columns),
                'mean': scaler.mean_.tolist(), 'scale': scaler.scale_.tolist(),
                'missing_indicators': list(missing.columns),
                'jaccard_methods': jaccard(baseline, baseline_lof),
                'limitations': ['Sin distancia geográfica', 'Gold confunde algunos faltantes con cero',
                               'Evaluación retrospectiva: incluye información posterior a la compra',
                               'Percentiles relativos a la cohorte; no probabilidad de fraude']}
    (out / 'metadata.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Resultados locales en {out.resolve()}. No se modificó SQL Server.')
    if args.excel:
        import subprocess
        root = Path(__file__).resolve().parent
        subprocess.run(['cmd.exe', '/c', str(root / 'Actualizar_reporte.cmd'), str(out.resolve())],
                       cwd=root, check=True)


if __name__ == '__main__':
    main()
