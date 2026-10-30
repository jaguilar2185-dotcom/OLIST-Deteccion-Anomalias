

"""Validación, explicación y publicación del proyecto OLIST. Sin ejecución al importar."""
import hashlib
import json
import platform
import uuid
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import sklearn


def conectar(server, readonly=False):
    import pyodbc
    return pyodbc.connect(
        'DRIVER={ODBC Driver 17 for SQL Server};'
        f'SERVER={server};DATABASE=OLIST_DW;Trusted_Connection=yes;'
        'TrustServerCertificate=yes;', readonly=readonly, timeout=15,
        autocommit=False)


def auditar_sql(cn):
    """Controles de Silver y cobertura Gold. Se guardan también los controles con cero casos."""
    controles = {
        'duplicados_ordenes': 'SELECT COUNT_BIG(*) FROM (SELECT order_id FROM silver.orders GROUP BY order_id HAVING COUNT(*)>1) d',
        'duplicados_items': 'SELECT COUNT_BIG(*) FROM (SELECT order_id,order_item_id FROM silver.order_items GROUP BY order_id,order_item_id HAVING COUNT(*)>1) d',
        'duplicados_pagos': 'SELECT COUNT_BIG(*) FROM (SELECT order_id,payment_sequential FROM silver.order_payments GROUP BY order_id,payment_sequential HAVING COUNT(*)>1) d',
        'duplicados_clientes': 'SELECT COUNT_BIG(*) FROM (SELECT customer_id FROM silver.customers GROUP BY customer_id HAVING COUNT(*)>1) d',
        'duplicados_productos': 'SELECT COUNT_BIG(*) FROM (SELECT product_id FROM silver.products GROUP BY product_id HAVING COUNT(*)>1) d',
        'duplicados_vendedores': 'SELECT COUNT_BIG(*) FROM (SELECT seller_id FROM silver.sellers GROUP BY seller_id HAVING COUNT(*)>1) d',
        'items_sin_orden': 'SELECT COUNT_BIG(*) FROM silver.order_items i WHERE NOT EXISTS (SELECT 1 FROM silver.orders o WHERE o.order_id=i.order_id)',
        'pagos_sin_orden': 'SELECT COUNT_BIG(*) FROM silver.order_payments p WHERE NOT EXISTS (SELECT 1 FROM silver.orders o WHERE o.order_id=p.order_id)',
        'ordenes_sin_cliente': 'SELECT COUNT_BIG(*) FROM silver.orders o WHERE NOT EXISTS (SELECT 1 FROM silver.customers c WHERE c.customer_id=o.customer_id)',
        'items_sin_producto': 'SELECT COUNT_BIG(*) FROM silver.order_items i WHERE NOT EXISTS (SELECT 1 FROM silver.products p WHERE p.product_id=i.product_id)',
        'items_sin_vendedor': 'SELECT COUNT_BIG(*) FROM silver.order_items i WHERE NOT EXISTS (SELECT 1 FROM silver.sellers s WHERE s.seller_id=i.seller_id)',
        'items_montos_negativos': 'SELECT COUNT_BIG(*) FROM silver.order_items WHERE price<0 OR freight_value<0',
        'pagos_negativos': 'SELECT COUNT_BIG(*) FROM silver.order_payments WHERE payment_value<0 OR payment_installments<0',
        'fechas_incoherentes': '''SELECT COUNT_BIG(*) FROM silver.orders WHERE
            order_approved_at<order_purchase_timestamp OR order_delivered_carrier_date<order_purchase_timestamp
            OR order_delivered_customer_date<order_purchase_timestamp
            OR order_delivered_customer_date<order_delivered_carrier_date''',
        'ordenes_sin_gold': 'SELECT COUNT_BIG(*) FROM silver.orders o WHERE NOT EXISTS (SELECT 1 FROM gold.order_anomaly_features g WHERE g.order_id=o.order_id)',
        'gold_sin_orden': 'SELECT COUNT_BIG(*) FROM gold.order_anomaly_features g WHERE NOT EXISTS (SELECT 1 FROM silver.orders o WHERE o.order_id=g.order_id)',
    }
    cursor = cn.cursor()
    rows = []
    for nombre, sql in controles.items():
        cantidad = int(cursor.execute(sql).fetchone()[0])
        rows.append({'control': nombre, 'casos': cantidad,
                     'estado': 'REVISAR' if cantidad else 'OK'})
    cursor.close()
    if any(r['casos'] for r in rows if r['control'].startswith('duplicados_')):
        raise ValueError('Hay claves duplicadas en Silver: corregir antes de puntuar.')
    return rows


def enriquecer_distancia(df, cn, archivo):
    """Una distancia por par orden-vendedor; nunca promedia ítems ni multiplica filas Gold."""
    geo = pd.read_csv(archivo, dtype={'geolocation_zip_code_prefix': str})
    cols = ['geolocation_zip_code_prefix', 'geolocation_lat', 'geolocation_lng']
    geo = geo[cols].copy()
    geo.columns = ['zip', 'lat', 'lon']
    geo['zip'] = geo['zip'].str.strip().str.zfill(5)
    for col in ['lat', 'lon']:
        geo[col] = pd.to_numeric(geo[col], errors='coerce')
    geo = geo[geo.lat.between(-90, 90) & geo.lon.between(-180, 180)]
    geo = geo.groupby('zip', as_index=False)[['lat', 'lon']].median()
    pares = pd.read_sql_query('''SELECT DISTINCT o.order_id, i.seller_id,
        c.customer_zip_code_prefix AS zip_cliente, s.seller_zip_code_prefix AS zip_vendedor
        FROM silver.orders o JOIN silver.customers c ON c.customer_id=o.customer_id
        JOIN silver.order_items i ON i.order_id=o.order_id
        JOIN silver.sellers s ON s.seller_id=i.seller_id''', cn)
    for col in ['zip_cliente', 'zip_vendedor']:
        pares[col] = pares[col].astype('string').str.strip().str.zfill(5)
    pares = pares.merge(geo.rename(columns={'zip': 'zip_cliente', 'lat': 'lat_c', 'lon': 'lon_c'}),
                        on='zip_cliente', how='left', validate='many_to_one')
    pares = pares.merge(geo.rename(columns={'zip': 'zip_vendedor', 'lat': 'lat_s', 'lon': 'lon_s'}),
                        on='zip_vendedor', how='left', validate='many_to_one')
    lat_c, lat_s = np.radians(pares.lat_c), np.radians(pares.lat_s)
    dlat = lat_s-lat_c
    dlon = np.radians(pares.lon_s-pares.lon_c)
    a = np.sin(dlat/2)**2 + np.cos(lat_c)*np.cos(lat_s)*np.sin(dlon/2)**2
    pares['km'] = 6371.0088 * 2 * np.arcsin(np.sqrt(a.clip(0, 1)))
    agg = pares.groupby('order_id').agg(
        distancia_aproximada_km=('km', 'max'),
        pares_con_distancia=('km', 'count'), pares_vendedor=('seller_id', 'size')).reset_index()
    agg['cobertura_distancia'] = agg.pares_con_distancia / agg.pares_vendedor
    df = df.drop(columns=[c for c in agg if c != 'order_id' and c in df])
    return df.merge(agg, on='order_id', how='left', validate='one_to_one')


def completar_resultados(result, df, raw):
    fechas = pd.Series(False, index=df.index)
    for menor, mayor in [('order_approved_at', 'order_purchase_timestamp'),
                          ('order_delivered_carrier_date', 'order_purchase_timestamp'),
                          ('order_delivered_customer_date', 'order_purchase_timestamp'),
                          ('order_delivered_customer_date', 'order_delivered_carrier_date')]:
        if menor in df and mayor in df:
            fechas |= pd.to_datetime(df[menor], errors='coerce') < pd.to_datetime(df[mayor], errors='coerce')
    result['flag_fecha_incoherente'] = fechas.astype(int)
    # Diferencias pequeñas pueden proceder del redondeo; regla explícita y revisable.
    result['flag_diferencia_material'] = (raw.diferencia_pago.abs() > np.maximum(1., raw.monto_total_orden.abs()*.01)).astype(int)
    reglas = {
        'freight desproporcionado': raw.proporcion_freight_precio > 1,
        'orden de alto valor (P99)': raw.monto_total_orden > raw.monto_total_orden.quantile(.99),
        'combinación de pagos inusual': (raw.numero_pagos > raw.numero_pagos.quantile(.99)) | (raw.tipos_pago_distintos > 1),
        'demora logística extrema (P99)': raw.horas_compra_entrega > raw.horas_compra_entrega.quantile(.99),
        'inconsistencia financiera': result.flag_diferencia_material.eq(1),
        'montos negativos': result.flag_monto_negativo.eq(1),
        'fechas incoherentes': fechas,
    }
    if 'distancia_aproximada_km' in raw:
        reglas['ruta logística extrema (P99)'] = raw.distancia_aproximada_km > raw.distancia_aproximada_km.quantile(.99)
    etiquetas = [[] for _ in range(len(result))]
    for etiqueta, mascara in reglas.items():
        for i in np.flatnonzero(mascara.fillna(False).to_numpy()):
            etiquetas[i].append(etiqueta)
    result['perfil_anomalia'] = [' | '.join(x) if x else 'Sin regla específica; revisar combinación multivariada' for x in etiquetas]
    result['nivel_rareza'] = pd.cut(result.anomaly_score_final, [-.001,.25,.5,.75,1],
                                    labels=['Baja','Media','Alta','Muy alta']).astype(str)
    critico = result[['flag_monto_negativo', 'flag_fecha_incoherente', 'flag_diferencia_material']].any(axis=1)
    result['prioridad_operativa'] = np.select([critico, result.anomalia_consenso.eq(1),
        result.anomaly_if.eq(1) | result.anomaly_lof.eq(1)], ['P1','P2','P3'], default='P4')
    return result


def evaluar(result, df, raw, out, metadata, calidad_sql):
    metadata.update(run_id=str(uuid.uuid4()), fecha_utc=datetime.now(timezone.utc).isoformat(),
        python=platform.python_version(), sklearn=sklearn.__version__, pandas=pd.__version__,
        input_sha256=hashlib.sha256(pd.util.hash_pandas_object(df, index=False).values.tobytes()).hexdigest())
    seleccionado = result.anomaly_if.eq(1) | result.anomaly_lof.eq(1)
    registros = []
    for col in [c for c in result if c.startswith('flag_')]:
        for grupo, mask in [('detectadas', seleccionado), ('no_detectadas', ~seleccionado)]:
            registros.append({'regla': col, 'grupo': grupo, 'ordenes': int(mask.sum()),
                'casos': int(result.loc[mask, col].sum()),
                'tasa': float(result.loc[mask, col].mean()) if mask.any() else None})
    pd.DataFrame(registros).to_csv(out/'validacion_reglas.csv', index=False, encoding='utf-8-sig')
    if 'order_status' in df:
        por_estado = result[['order_id','anomaly_if','anomaly_lof','anomalia_consenso']].merge(
            df[['order_id','order_status']], on='order_id', validate='one_to_one')
        por_estado.groupby('order_status', dropna=False).agg(
            ordenes=('order_id','size'), detectadas_IF=('anomaly_if','sum'),
            detectadas_LOF=('anomaly_lof','sum'), consenso=('anomalia_consenso','sum'),
            tasa_IF=('anomaly_if','mean'), tasa_LOF=('anomaly_lof','mean')).to_csv(out/'evaluacion_por_estado.csv', encoding='utf-8-sig')
    calidad = pd.DataFrame({'variable': raw.columns,
        'faltantes': raw.isna().sum().values, 'ceros': raw.eq(0).sum().values,
        'negativos': raw.lt(0).sum().values,
        'mediana': raw.median().values, 'p99': raw.quantile(.99).values})
    calidad.to_csv(out/'calidad_features.csv', index=False, encoding='utf-8-sig')
    ranked = result.sort_values(['anomaly_score_final','order_id'], ascending=[False,True])
    grupos = [('top20', ranked.head(20)),
              ('cerca_corte_IF', result.assign(dist=(result.anomaly_score_if-(1-metadata['contamination'])).abs()).sort_values(['dist','order_id']).head(10)),
              ('control_no_detectado', result.loc[~seleccionado].sample(min(10,int((~seleccionado).sum())), random_state=42))]
    muestras = pd.concat([x.assign(grupo_revision=g) for g,x in grupos], ignore_index=True).drop(columns='dist', errors='ignore')
    muestras = muestras.merge(df, on='order_id', validate='many_to_one')
    for col in ['responsable', 'evidencia_consultada', 'decision_humana', 'justificacion_revision', 'fecha_revision']:
        muestras[col] = ''
    # Cada ejecución conserva su plantilla; nunca sobrescribe decisiones previas.
    revision = f'revision_manual_{metadata["run_id"]}.csv'
    muestras.to_csv(out/revision, index=False, encoding='utf-8-sig')
    metadata['revision_manual'] = revision
    metadata['revision_estado'] = 'PENDIENTE: la selección automática no es validación humana'
    distancia = 'distancia_aproximada_km' in raw
    metadata['distancia_disponible'] = distancia
    metadata['cobertura_distancia_ordenes'] = float(raw.distancia_aproximada_km.notna().mean()) if distancia else 0.
    metadata['reglas'] = {'freight': 'freight/precio > 1', 'alto_valor': 'monto > P99',
        'pagos': 'numero_pagos > P99 o tipos_pago_distintos > 1', 'logistica': 'horas > P99',
        'diferencia_material': '|total-pagado| > max(1 BRL, 1% de |total|)',
        'rareza': 'Cuartiles fijos del promedio de percentiles; descriptivos, no confianza'}
    texto = f'''# Evaluación OLIST — ejecución {metadata['run_id']}

Órdenes: {len(df):,}. IF: {int(result.anomaly_if.sum()):,}; LOF: {int(result.anomaly_lof.sum()):,}; consenso: {int(result.anomalia_consenso.sum()):,}.
Jaccard IF–LOF: {metadata['jaccard_methods']:.4f}. No equivale a exactitud.

## Criterio de corte
Fracción seleccionada por modelo: {metadata['contamination']:.1%}. Justificación declarada: {metadata['justificacion']}.
Es una hipótesis operativa que debe contrastarse con la revisión; no una tasa de fraude.
Los empates pueden reducir la cantidad seleccionada. sensibilidad_umbral.csv compara 1%, 2%, 3%, 5% y el corte elegido sin reentrenar.
estabilidad.csv cambia semillas IF y vecinos LOF; no confundir estabilidad con corrección.

## Preparación y explicabilidad
Log con signo en {', '.join(metadata['log_signed_columns'])}; imputación por mediana, StandardScaler y banderas de faltantes.
Scores normalizados por percentil empírico dentro de la cohorte y promedio de ambos percentiles.
Las tres desviaciones z de variables transformadas y las reglas describen el caso; no son atribuciones causales.
Las unidades son BRL, gramos, cm³, horas, días y kilómetros; conteos y proporciones según el nombre.
Los perfiles pueden solaparse. Los cuartiles de nivel_rareza son descriptivos y no determinan la detección.

## Validación cuantitativa
Consultar calidad_sql.csv, calidad_features.csv, validacion_reglas.csv, sensibilidad_umbral.csv y estabilidad.csv.
validacion_reglas.csv compara tasas en detectadas y no detectadas; las reglas no son etiquetas verdaderas.
Los controles Silver no prueban que Bronze carezca de rechazos o conversiones fallidas.
La población incluye todos los estados: canceladas/no disponibles pueden concentrar problemas de cobertura.
Distancia disponible: {distancia}. Cobertura de órdenes: {metadata['cobertura_distancia_ordenes']:.1%}.
La distancia es el máximo vendedor–cliente por centroides postales, no trayecto vial; revisar cobertura de pares.

## Validación cualitativa pendiente
Completar {revision}: top 20, diez casos cerca del corte IF y hasta diez controles no detectados.
Registrar evidencia, responsable y decisión: válida inusual / error confirmado / requiere investigación / insuficiente evidencia.
No inventar conclusiones ni declarar revisión completada sin evidencia. Sin etiquetas no se informa precisión ni recall.

## Protocolo de revisión
P1 Finanzas/Calidad: negativos, fechas imposibles o diferencias materiales; comprobar comprobantes y cobertura de datos.
P2 Operaciones: consenso IF–LOF, priorizando impacto monetario y logístico.
P3 Analista: un solo modelo, contrastar contexto y reglas.
P4 Muestreo de controles: buscar omisiones y evaluar casos normales.
Cerrar cada caso con order_id, ejecución, evidencia, responsable, resolución y fecha.

## Limitaciones
Datos retrospectivos: entrega y retraso no estaban disponibles en la compra. No es un detector en tiempo real.
Los ceros heredados de Gold pueden esconder faltantes; no se convierten automáticamente en valores conocidos.
No comparar automáticamente scores percentiles de cohortes distintas. Una anomalía no implica fraude.
'''
    (out/'Evaluacion_proyecto.md').write_text(texto, encoding='utf-8')


def publicar_sql(server, result, features, enriquecidas=None):
    """Actualiza todas las filas existentes con rollback; nunca DROP ni publicación parcial."""
    columnas = ['order_id', 'anomaly_score_if', 'anomaly_score_lof', 'anomaly_score_final',
                'anomaly_if', 'anomaly_lof', 'anomalia_consenso', 'nivel_rareza',
                'prioridad_modelo', 'perfil_anomalia']
    if result.order_id.isna().any() or result.order_id.duplicated().any():
        raise ValueError('Scoring con claves inválidas')
    if not np.isfinite(result[['anomaly_score_if','anomaly_score_lof','anomaly_score_final']]).all().all():
        raise ValueError('Scores no finitos')
    cn = conectar(server)
    try:
        cur = cn.cursor()
        cur.execute('SET XACT_ABORT ON; SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;')
        # Verifica la misma cohorte. Bloquea escrituras concurrentes durante la publicación.
        existentes = {str(r[0]) for r in cur.execute('SELECT order_id FROM gold.order_anomaly_scoring WITH (UPDLOCK,HOLDLOCK)')}
        if existentes != set(result.order_id.astype(str)):
            raise ValueError('La cohorte SQL difiere. Se detiene sin borrar ni agregar órdenes.')
        # Si la fuente cambió desde la lectura, no publica resultados obsoletos.
        actual = pd.read_sql_query('SELECT * FROM gold.order_anomaly_features ORDER BY order_id', cn)
        base_cols = list(actual.columns)
        previo = features[base_cols].sort_values('order_id').reset_index(drop=True)
        if not actual.equals(previo):
            raise ValueError('Gold cambió durante el análisis; ejecutar nuevamente.')
        cur.execute('''CREATE TABLE #scoring (order_id NVARCHAR(50) NOT NULL PRIMARY KEY,
            anomaly_score_if FLOAT NOT NULL, anomaly_score_lof FLOAT NOT NULL, anomaly_score_final FLOAT NOT NULL,
            anomaly_if TINYINT NOT NULL, anomaly_lof TINYINT NOT NULL, anomalia_consenso TINYINT NOT NULL,
            nivel_rareza NVARCHAR(20) NOT NULL, prioridad_modelo NVARCHAR(20) NOT NULL,
            perfil_anomalia NVARCHAR(2000) NULL)''')
        datos = list(result[columnas].itertuples(index=False, name=None))
        for inicio in range(0,len(datos),500):
            cur.executemany('INSERT INTO #scoring VALUES (?,?,?,?,?,?,?,?,?,?)', datos[inicio:inicio+500])
        asignaciones = ', '.join(f't.[{c}]=s.[{c}]' for c in columnas[1:])
        cur.execute(f'UPDATE t SET {asignaciones} FROM gold.order_anomaly_scoring t JOIN #scoring s ON t.order_id=s.order_id')
        if enriquecidas is not None:
            # Agrega solo las variables geográficas; conserva el resto de Gold y sus relaciones.
            for col in ['distancia_aproximada_km', 'cobertura_distancia', 'pares_con_distancia', 'pares_vendedor']:
                cur.execute(f"IF COL_LENGTH('gold.order_anomaly_features','{col}') IS NULL ALTER TABLE gold.order_anomaly_features ADD [{col}] FLOAT NULL")
            dist_cols = ['order_id','distancia_aproximada_km','cobertura_distancia','pares_con_distancia','pares_vendedor']
            dist = enriquecidas[dist_cols].astype(object).where(enriquecidas[dist_cols].notna(), None)
            filas = list(dist.itertuples(index=False, name=None))
            # Parámetros explícitos y tabla persistente: soporta coordenadas NULL con ODBC 17.
            import pyodbc
            dist_cursor = cn.cursor()
            staging = '##olist_dist_' + uuid.uuid4().hex
            dist_cursor.execute(f'CREATE TABLE {staging} (order_id NVARCHAR(50) PRIMARY KEY, km FLOAT NULL, cobertura FLOAT NULL, conocidos FLOAT NULL, pares FLOAT NULL)')
            dist_cursor.fast_executemany = True
            dist_cursor.setinputsizes([(pyodbc.SQL_WVARCHAR, 50, 0)] + [(pyodbc.SQL_DOUBLE, 0, 0)] * 4)
            for inicio in range(0,len(filas),500):
                dist_cursor.executemany(f'INSERT INTO {staging} VALUES (?,?,?,?,?)', filas[inicio:inicio+500])
            dist_cursor.execute(f'''UPDATE g SET distancia_aproximada_km=d.km, cobertura_distancia=d.cobertura,
                pares_con_distancia=d.conocidos, pares_vendedor=d.pares
                FROM gold.order_anomaly_features g JOIN {staging} d ON g.order_id=d.order_id''')
            dist_cursor.execute(f'DROP TABLE {staging}')
            dist_cursor.close()
        cur.execute('''SELECT COUNT_BIG(*) FROM gold.order_anomaly_scoring t JOIN #scoring s ON t.order_id=s.order_id
            WHERE t.anomaly_if<>s.anomaly_if OR t.anomaly_lof<>s.anomaly_lof
            OR t.anomalia_consenso<>s.anomalia_consenso OR t.anomaly_score_final<>s.anomaly_score_final''')
        if cur.fetchone()[0]:
            raise ValueError('La comprobación posterior a la carga falló')
        cn.commit()
    except Exception:
        cn.rollback()
        raise
    finally:
        cn.close()
