"""OLIST: lectura de Gold y salidas locales; publicación SQL opcional y transaccional.
Uso: python auditar_y_puntuar.py --umbral .02 --justificacion "Presupuesto exploratorio"
Requiere pandas, numpy, pyodbc y scikit-learn.
El 2% es presupuesto exploratorio de revisión, no prevalencia de fraude.
"""
import argparse
import json
from pathlib import Path
import numpy as np
import pandas as pd
from sklearn.ensemble import IsolationForest
from sklearn.neighbors import LocalOutlierFactor
from sklearn.preprocessing import StandardScaler
from soporte_proyecto import (conectar, enriquecer_distancia, auditar_sql, completar_resultados,
                              evaluar, publicar_sql)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server', default='TU_SERVIDOR')
    parser.add_argument('--output', default='resultados')
    parser.add_argument('--umbral', type=float, default=.02, help='Fracción por modelo: .01, .02, .05')
    parser.add_argument('--justificacion', required=True, help='Razón operativa del corte elegido')
    parser.add_argument('--geolocalizacion', help='CSV OLIST geolocation, con latitud/longitud por prefijo')
    parser.add_argument('--entrada', help='CSV de features para ejecución local sin SQL')
    parser.add_argument('--publicar-sql', action='store_true', help='Actualizar scoring SQL en una transacción')
    args = parser.parse_args()
    if not 0 < args.umbral <= .5:
        parser.error('--umbral debe estar entre 0 (excluido) y 0.5')
    if not args.justificacion.strip():
        parser.error('--justificacion no puede estar vacía')
    if args.entrada and args.publicar_sql:
        parser.error('La publicación requiere una lectura actual de SQL, no --entrada')
    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    # Utilizar además un usuario con permiso SELECT exclusivamente.
    if args.entrada:
        df = pd.read_csv(args.entrada).sort_values('order_id').reset_index(drop=True)
        source_df = df.copy()
        calidad_sql = [{'control': 'SQL', 'estado': 'NO EVALUADO: entrada local'}]
    else:
        print('Consultando controles de calidad y Gold...', flush=True)
        cn = conectar(args.server, readonly=True)
        try:
            calidad_sql = auditar_sql(cn)
            df = pd.read_sql_query('SELECT * FROM gold.order_anomaly_features ORDER BY order_id', cn)
            source_df = df.copy()
            if args.geolocalizacion:
                df = enriquecer_distancia(df, cn, args.geolocalizacion)
        finally:
            cn.close()
    pd.DataFrame(calidad_sql).to_csv(out / 'calidad_sql.csv', index=False, encoding='utf-8-sig')
    print(f'Gold leída: {len(df)} órdenes. Preparando variables...', flush=True)
    if len(df) < 22 or df.order_id.isna().any() or df.order_id.duplicated().any():
        raise ValueError('Se requieren al menos 22 órdenes con identificadores únicos y no nulos.')
    columns = ['monto_total_orden', 'freight_total', 'proporcion_freight_precio',
               'numero_items', 'numero_vendedores', 'numero_pagos', 'max_cuotas',
               'peso_total_g', 'volumen_total_cm3', 'horas_compra_entrega',
               'dias_retraso_entrega', 'tipos_pago_distintos', 'monto_pagado']
    raw = df[columns].apply(pd.to_numeric, errors='raise')
    if 'distancia_aproximada_km' in df and df.distancia_aproximada_km.notna().any():
        raw['distancia_aproximada_km'] = pd.to_numeric(df.distancia_aproximada_km, errors='raise')
    if np.isinf(raw.to_numpy(dtype=float)).any():
        raise ValueError('Hay infinitos en las variables originales.')
    raw['diferencia_pago'] = raw.monto_total_orden - raw.monto_pagado
    raw = raw.drop(columns='monto_pagado')
    # Conservar valores negativos para diagnóstico; no aplicar log1p a negativos.
    logcols = ['monto_total_orden', 'freight_total', 'peso_total_g', 'volumen_total_cm3']
    if 'distancia_aproximada_km' in raw:
        logcols.append('distancia_aproximada_km')
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
    iforest = IsolationForest(n_estimators=200, contamination=args.umbral, random_state=42, n_jobs=-1)
    lof = LocalOutlierFactor(n_neighbors=20, contamination=args.umbral, n_jobs=-1)
    print('Entrenando Isolation Forest y LOF...', flush=True)
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
    medianas_originales = raw.median()
    def explain(i):
        top = z.iloc[i].abs().nlargest(3).index
        return ' | '.join(f'{c}: valor={raw.loc[i, c]:.4g}, mediana={medianas_originales[c]:.4g}, z_transformado={z.loc[i, c]:.2f}' for c in top)
    print('Generando explicaciones y perfiles...', flush=True)
    result['variables_revision'] = [explain(i) for i in range(len(df))]
    result['flag_diferencia_pago'] = (raw.diferencia_pago.abs() > .01).astype(int)
    result['flag_freight_alto'] = (raw.proporcion_freight_precio > 1).astype(int)
    result['flag_monto_negativo'] = (raw[['monto_total_orden', 'freight_total']].lt(0).any(axis=1)).astype(int)
    result = completar_resultados(result, df, raw)
    df.to_csv(out / 'order_anomaly_features.csv', index=False, encoding='utf-8-sig')
    ranked = result.sort_values(['anomaly_score_final', 'order_id'], ascending=[False, True])
    ranked.to_csv(out / 'order_anomaly_scoring.csv', index=False, encoding='utf-8-sig')
    details = ranked.head(20).merge(df, on='order_id', validate='one_to_one')
    details.to_csv(out / 'top20_explicado.csv', index=False, encoding='utf-8-sig')
    def jaccard(a, b):
        return len(a & b) / len(a | b) if a | b else 1.0
    baseline = set(np.flatnonzero(flags_if))
    sensitivity = []
    print('Evaluando estabilidad y sensibilidad...', flush=True)
    for seed in [7, 21, 84]:
        model = IsolationForest(n_estimators=200, contamination=args.umbral, random_state=seed, n_jobs=-1)
        selected = set(np.flatnonzero(model.fit_predict(X) == -1))
        sensitivity.append({'method': 'IF', 'parameter': 'seed', 'value': seed,
                            'jaccard_base': jaccard(baseline, selected)})
    baseline_lof = set(np.flatnonzero(flags_lof))
    for k in [10, 40]:
        model = LocalOutlierFactor(n_neighbors=min(k, len(df)-1), contamination=args.umbral, n_jobs=-1)
        selected = set(np.flatnonzero(model.fit_predict(X) == -1))
        sensitivity.append({'method': 'LOF', 'parameter': 'neighbors', 'value': k,
                            'jaccard_base': jaccard(baseline_lof, selected)})
    pd.DataFrame(sensitivity).to_csv(out / 'estabilidad.csv', index=False)
    # Sensibilidad del umbral: no requiere reentrenar los modelos.
    cuts = []
    for c in sorted(set([.01, .02, .03, .05, args.umbral])):
        a = set(np.flatnonzero(scores_if > np.quantile(scores_if, 1-c)))
        b = set(np.flatnonzero(scores_lof > np.quantile(scores_lof, 1-c)))
        cuts.append({'contamination': c, 'if_count': len(a), 'lof_count': len(b),
                     'consensus_count': len(a & b), 'union_count': len(a | b),
                     'jaccard_methods': jaccard(a, b)})
    pd.DataFrame(cuts).to_csv(out / 'sensibilidad_umbral.csv', index=False)
    metadata = {'rows': len(df),
                'contamination': args.umbral, 'justificacion': args.justificacion,
                'source': args.entrada or 'gold.order_anomaly_features',
                'seed': 42, 'log_signed_columns': logcols,
                'medians_transformed': medians.to_dict(), 'columns_scaled': list(z.columns),
                'mean': scaler.mean_.tolist(), 'scale': scaler.scale_.tolist(),
                'missing_indicators': list(missing.columns),
                'jaccard_methods': jaccard(baseline, baseline_lof),
                'limitations': ['Distancia por centroides postales; no recorrido vial. Revisar cobertura.', 'Gold confunde algunos faltantes con cero',
                               'Evaluación retrospectiva: incluye información posterior a la compra',
                               'Percentiles relativos a la cohorte; no probabilidad de fraude']}
    evaluar(result, df, raw, out, metadata, calidad_sql)
    if args.publicar_sql:
        print('Validando y publicando scoring SQL en una transacción...', flush=True)
        publicar_sql(args.server, result, source_df, df if args.geolocalizacion else None)
        metadata['publicacion_sql'] = 'Completada en transacción única'
    else:
        metadata['publicacion_sql'] = 'No solicitada'
    (out / 'metadata.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Resultados en {out.resolve()}. SQL: {metadata["publicacion_sql"]}.')



if __name__ == '__main__':
    main()
