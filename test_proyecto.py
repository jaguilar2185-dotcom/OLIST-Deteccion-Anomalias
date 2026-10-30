import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
import pandas as pd

import soporte_proyecto as s


class ProyectoTests(unittest.TestCase):
    def test_reglas_y_prioridad_financiera_sin_consenso(self):
        raw = pd.DataFrame(dict(monto_total_orden=[100., 200., -1.],
            proporcion_freight_precio=[.2, 2., .1], numero_pagos=[1,3,1],
            tipos_pago_distintos=[1,2,1], horas_compra_entrega=[24.,500.,1.],
            diferencia_pago=[0.,0.,2.]))
        result = pd.DataFrame(dict(order_id=['a','b','c'], anomaly_score_if=[0.,1.,.5],
            anomaly_score_lof=[0.,1.,.5], anomaly_score_final=[0.,1.,.5],
            anomaly_if=[0,1,0], anomaly_lof=[0,1,0], anomalia_consenso=[0,1,0],
            flag_monto_negativo=[0,0,1]))
        out = s.completar_resultados(result, pd.DataFrame(index=raw.index), raw)
        self.assertEqual(list(out.prioridad_operativa), ['P4','P2','P1'])
        self.assertIn('freight desproporcionado', out.loc[1,'perfil_anomalia'])
        self.assertEqual(out.loc[2,'flag_diferencia_material'], 1)

    def test_distancia_no_multiplica_ordenes(self):
        geo = pd.DataFrame({'geolocation_zip_code_prefix':['00001','00001','00002'],
            'geolocation_lat':[0.,0.,0.], 'geolocation_lng':[0.,0.,1.]})
        pares = pd.DataFrame({'order_id':['a','a','b'], 'seller_id':['s1','s2','s1'],
            'zip_cliente':['00001','00001','99999'], 'zip_vendedor':['00002','00001','00002']})
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'geo.csv'
            geo.to_csv(path,index=False)
            with patch.object(s.pd, 'read_sql_query', return_value=pares):
                out = s.enriquecer_distancia(pd.DataFrame({'order_id':['a','b']}), None, path)
        self.assertEqual(len(out), 2)
        self.assertAlmostEqual(out.loc[0,'distancia_aproximada_km'],111.195, places=2)
        self.assertTrue(np.isnan(out.loc[1,'distancia_aproximada_km']))
        self.assertEqual(out.loc[1,'cobertura_distancia'], 0)

    def test_publicacion_rollback_si_cohorte_distinta(self):
        class Cursor:
            def execute(self, sql):
                self.sql = sql
                return self
            def __iter__(self):
                return iter([('otra_orden',)])
        class Conexion:
            rollback_ejecutado = False
            commit_ejecutado = False
            def cursor(self): return Cursor()
            def rollback(self): self.rollback_ejecutado = True
            def commit(self): self.commit_ejecutado = True
            def close(self): pass
        cn = Conexion()
        result = pd.DataFrame({'order_id':['a'], 'anomaly_score_if':[.5],
            'anomaly_score_lof':[.5], 'anomaly_score_final':[.5]})
        with patch.object(s, 'conectar', return_value=cn):
            with self.assertRaisesRegex(ValueError, 'cohorte SQL difiere'):
                s.publicar_sql('test', result, pd.DataFrame())
        self.assertTrue(cn.rollback_ejecutado)
        self.assertFalse(cn.commit_ejecutado)


if __name__ == '__main__':
    unittest.main()
