"""Resumen documental reproducible; no sustituye la confirmación operativa humana."""
import sys
from pathlib import Path
import pandas as pd


def generar(carpeta):
    out = Path(carpeta)
    top = pd.read_csv(out/'top20_explicado.csv')
    features = pd.read_csv(out/'order_anomaly_features.csv')
    scores = pd.read_csv(out/'order_anomaly_scoring.csv')
    combinados = scores.merge(features, on='order_id', validate='one_to_one')
    entregadas = combinados.loc[combinados.order_status.eq('delivered')].sort_values(
        ['anomaly_score_final','order_id'], ascending=[False,True]).head(20)
    entregadas.to_csv(out/'top20_entregadas_complementario.csv',index=False,encoding='utf-8-sig')
    sin_items = int(top.numero_items.eq(0).sum())
    filas = ['| Orden | Estado | Ítems | Pagado BRL | Diferencia total−pagado BRL | Lectura documental |',
             '|---|---|---:|---:|---:|---|']
    for r in top.itertuples():
        observacion = ('Sin ítems: no interpretar total cero como compra gratuita. Revisar cobertura y cancelación/devolución.'
                       if r.numero_items == 0 else 'Contrastar valores y perfil con los comprobantes; rareza no confirma error.')
        filas.append(f'| {r.order_id} | {r.order_status} | {r.numero_items} | {r.monto_pagado:.2f} | {r.monto_total_orden-r.monto_pagado:.2f} | {observacion} |')
    casos = '\n'.join(f'- {r.order_id}: total {r.monto_total_orden:.2f} BRL, transporte {r.freight_total:.2f} BRL; {r.perfil_anomalia}.'
                      for r in entregadas.head(5).itertuples())
    texto = f'''# Inspección documental del Top 20

Evidencia: top20_explicado.csv y order_anomaly_features.csv de esta carpeta. Alcance: contraste interno de valores, estado y cobertura. No se consultaron comprobantes, reembolsos ni personas de Operaciones.

## Hallazgo principal
{sin_items} de los veinte casos tienen cero ítems. El estado de la orden y la ausencia de detalle importan: un monto calculado desde ítems puede ser cero aunque exista un pago registrado. Esto permite explicar la selección como una combinación rara o un problema de cobertura; no demuestra pérdida financiera ni fraude.

{chr(10).join(filas)}

## Contraste con órdenes entregadas
top20_entregadas_complementario.csv muestra otros veinte ejemplos entregados usando el ranking global existente. No es un modelo reentrenado ni sustituye el Top 20 principal.

{casos}

## Interpretación de la evaluación
Consultar evaluacion_por_estado.csv para cuantificar la concentración de detecciones en estados distintos. No extrapolar una tasa de la cohorte completa a órdenes entregadas.
Consultar validacion_reglas.csv: una mayor tasa de reglas entre detectadas sugiere utilidad para revisión, sin convertir esas reglas en etiquetas verdaderas.
La coincidencia IF–LOF y la estabilidad son evidencia parcial; desacuerdos requieren inspección, no ocultarlos.

## Decisión y acciones pendientes
La conclusión documental es «requiere contrastar cobertura y contexto». No se confirma error ni fraude. Completar revision_manual_ID.csv con evidencia externa y responsable antes de afirmar validación humana terminada.
Revisar primero diferencias de importes materiales y fechas incoherentes. Separar problemas de datos de operaciones válidas pero inusuales.
El corte del 2% sigue siendo provisional: debe aprobarse según capacidad real de revisión y utilidad observada. Informar la unión de ambos métodos como carga total, además del consenso.
'''
    (out/'Inspeccion_documental_top20.md').write_text(texto, encoding='utf-8')


if __name__ == '__main__':
    generar(sys.argv[1])
