"""Punto de entrada: configuración única y carpeta independiente por ejecución."""
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path

root = Path(__file__).resolve().parent
config_path = root/'config_proyecto.json'
if not config_path.exists():
    raise SystemExit('Copia config_proyecto.example.json como config_proyecto.json y configura tu servidor.')
config = json.loads(config_path.read_text(encoding='utf-8-sig'))
salida = root/'ejecuciones'/datetime.now().strftime('%Y%m%d_%H%M%S_%f')
args = [sys.executable, str(root/'auditar_y_puntuar.py'), '--server', config['servidor'],
        '--output', str(salida), '--umbral', str(config['umbral']),
        '--justificacion', config['justificacion']]
geo = root/config['geolocalizacion'] if config.get('geolocalizacion') else None
if geo and geo.exists():
    args += ['--geolocalizacion', str(geo)]
else:
    print('Geolocalización no disponible: distancia pendiente en esta ejecución.', flush=True)
if config.get('publicar_sql'):
    args.append('--publicar-sql')
subprocess.run(args, cwd=root, check=True)
from inspeccion_documental import generar
generar(salida)
if config.get('publicar_sql'):
    from verificar_ejecucion import verificar
    verificar(salida, config['servidor'])
(root/'ULTIMA_EJECUCION.txt').write_text(str(salida), encoding='utf-8')
print(f'Proceso terminado. Evidencias: {salida}\nAbre powerbi/Dashboard_OLIST_Claro.pbip y pulsa Actualizar.')
