import fs from 'node:fs/promises';
import path from 'node:path';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';

const input = path.resolve(process.argv[2] || 'resultados');
const output = path.resolve(process.argv[3] || 'outputs/olist');
await fs.mkdir(output, {recursive:true});
const data = JSON.parse(await fs.readFile(path.join(input,'reporte_input.json'),'utf8'));
console.log('Datos leídos. Iniciando libro.');
const wb = Workbook.create();
const summary = wb.worksheets.add('Resumen');
const top = wb.worksheets.add('Top 20');
const evaluation = wb.worksheets.add('Evaluación');
const all = wb.worksheets.add('Órdenes');
const navy='#243B53', blue='#3875B7', orange='#D98935';
function col(n) { let s=''; for(n++;n;n=Math.floor((n-1)/26))s=String.fromCharCode(65+(n-1)%26)+s;return s; }
function title(s,t,cols=12){
  s.showGridLines=false;
  s.getRange(`A1:${col(cols-1)}45`).format.font={name:'Arial',size:10,color:'#243B53'};
  s.getRange(`A1:${col(cols-1)}45`).format.columnWidth=13;
  s.getRange(`A1:${col(cols-1)}45`).format.rowHeight=22;
  s.getRange('A2').values=[[t]];
  s.getRange('A2').format.font={name:'Arial',size:16,bold:true,color:navy};
}
function header(s,r){s.getRange(r).format={fill:navy,font:{name:'Arial',size:10,bold:true,color:'#FFFFFF'},rowHeight:32,wrapText:true};}
function table(s,rows,keys,labels,name){
  const end=col(keys.length-1), last=rows.length+5;
  s.getRange(`A5:${end}5`).values=[labels];
  for(let start=0;start<rows.length;start+=5000){
    const block=rows.slice(start,start+5000).map(r=>keys.map(k=>r[k]??null));
    s.getRange(`A${start+6}:${end}${start+5+block.length}`).values=block;
    if(rows.length>5000)console.log('Filas cargadas:',start+block.length);
  }
  s.tables.add(`A5:${end}${last}`,true,name);
  header(s,`A5:${end}5`);
  s.freezePanes.freezeRows(5);s.freezePanes.freezeColumns(1);
  s.getRange(`A6:${end}${Math.min(last,100)}`).format.rowHeight=24;
  return last;
}
function chart(s,range,name,from,to,colors=[blue,orange]){
  const c=s.charts.add('bar',s.getRange(range));c.title=name;c.hasLegend=false;
  c.setPosition(from,to);c.titleTextStyle.typeface='Arial';c.titleTextStyle.fontSize=13;
  c.xAxis={axisType:'textAxis',textStyle:{typeface:'Arial',fontSize:10}};
  c.yAxis={numberFormatCode:'#,##0',numberFormatSourceLinked:false,textStyle:{typeface:'Arial',fontSize:10}};
  c.series.items.forEach((x,i)=>x.fill=colors[i%colors.length]);return c;
}
title(all,'Resultados por orden',14);
all.getRange('A3').values=[['Fuente: order_anomaly_scoring.csv. Ordenadas por score final descendente. Score de rareza, no probabilidad de fraude.']];
const keys=['order_id','anomaly_score_final','anomaly_score_if','anomaly_score_lof','anomaly_if','anomaly_lof','anomalia_consenso','prioridad_modelo','flag_diferencia_pago','flag_freight_alto','flag_monto_negativo','score_if_raw','score_lof_raw','variables_revision'];
const labels=['Orden','Score final','Score IF','Score LOF','Anomalía IF','Anomalía LOF','Consenso','Prioridad','Diferencia pago','Freight alto','Monto negativo','IF original','LOF original','Variables para revisión'];
const last=table(all,data.scoring,keys,labels,'OrdenesScoring');
all.getRange(`B6:D${last}`).setNumberFormat('0.0000');
all.getRange(`L6:M${last}`).setNumberFormat('0.0000');
all.getRange('A:A').format.columnWidth=37;all.getRange('N:N').format.columnWidth=100;
all.getRange('B:M').format.columnWidth=16;
all.getRange(`B6:B${last}`).conditionalFormats.add('colorScale',{colors:['#EFF4FA','#F5D49B','#C44E40'],thresholds:['min','50%','max']});
all.getRange(`H6:H${last}`).conditionalFormats.add('containsText',{text:'ALTA',format:{fill:'#FBE3DC',font:{bold:true,color:'#9C3326'}}});
console.log('Tabla completa:',data.scoring.length);

title(top,'20 órdenes con mayor score final',14);
top.getRange('A3').values=[['Fuente: top20_explicado.csv. Importes en BRL; descriptores de desviación sujetos a revisión.']];
const tk=['order_id','anomaly_score_final','prioridad_modelo','order_status','monto_total_orden','monto_pagado','freight_total','proporcion_freight_precio','numero_items','numero_pagos','horas_compra_entrega','dias_retraso_entrega','variables_revision'];
const tl=['Orden','Score final','Prioridad','Estado','Monto (BRL)','Pagado (BRL)','Freight (BRL)','Freight / precio','Ítems','Pagos','Entrega (horas)','Retraso (días)','Variables para revisión'];
const tlast=table(top,data.top,tk,tl,'CasosTop20');
top.getRange('A:A').format.columnWidth=37;top.getRange('B:L').format.columnWidth=18;
top.getRange('M:M').format.columnWidth=100;
top.getRange(`B6:B${tlast}`).setNumberFormat('0.0000');
top.getRange(`E6:G${tlast}`).setNumberFormat('"R$ "#,##0.00');
top.getRange(`H6:H${tlast}`).setNumberFormat('0.0%');

title(summary,'OLIST · Detección de anomalías');summary.tabColor=navy;
summary.getRange('A4').values=[['Scores relativos a esta cohorte. Una anomalía requiere revisión; no implica fraude.']];
summary.getRange('A6:B6').values=[['Indicador','Resultado']];header(summary,'A6:B6');
summary.getRange('A7:A12').values=[['Órdenes analizadas'],['Anomalías IF'],['Anomalías LOF'],['Consenso IF y LOF'],['Marcadas por algún modelo'],['Coincidencia Jaccard']];
summary.getRange('B7:B12').formulas=[
  [`=COUNTA('Órdenes'!A6:A${last})`], [`=SUM('Órdenes'!E6:E${last})`],
  [`=SUM('Órdenes'!F6:F${last})`],[`=SUM('Órdenes'!G6:G${last})`],
  ['=B8+B9-B10'],['=IF(B11=0,0,B10/B11)']];
summary.getRange('A:A').format.columnWidth=32;summary.getRange('B:B').format.columnWidth=17;
summary.getRange('B7:B11').setNumberFormat('#,##0');summary.getRange('B12').setNumberFormat('0.0%');
summary.getRange('A16:B19').values=[['Prioridad','Órdenes'],['ALTA',null],['MEDIA',null],['BAJA',null]];
header(summary,'A16:B16');
for(let r=17;r<=19;r++)summary.getRange(`B${r}`).formulas=[[`=COUNTIF('Órdenes'!H6:H${last},A${r})`]];
summary.getRange('A22:B26').values=[['Detección','Órdenes'],['Ambos',null],['Solo IF',null],['Solo LOF',null],['Ninguno',null]];
header(summary,'A22:B22');
summary.getRange('B23:B26').formulas=[['=B10'],['=B8-B10'],['=B9-B10'],['=B7-B11']];
chart(summary,'A16:B19','Órdenes por prioridad','D6','L19');
chart(summary,'A22:B26','Coincidencia entre modelos','D21','L35');
summary.getRange('A30:B33').values=[['Regla de revisión','Órdenes'],['Diferencia pago > R$ 0,01',null],['Freight mayor al precio',null],['Monto o freight negativo',null]];
header(summary,'A30:B30');
summary.getRange('B31:B33').formulas=[...['I','J','K'].map(c=>[`=SUM('Órdenes'!${c}6:${c}${last})`])];

title(evaluation,'Sensibilidad y estabilidad');
evaluation.getRange('A4').values=[['Fuente: sensibilidad_umbral.csv y estabilidad.csv. Jaccard: intersección / unión de las órdenes marcadas.']];
evaluation.getRange('A6:D10').values=[['Contaminación','IF (órdenes)','LOF (órdenes)','Jaccard entre modelos'],...data.cuts.map(r=>[r.contamination,r.if_count,r.lof_count,r.jaccard_methods])];
header(evaluation,'A6:D6');evaluation.getRange('A7:A10').setNumberFormat('0%');evaluation.getRange('D7:D10').setNumberFormat('0.0%');
evaluation.getRange('A14:D19').values=[['Método','Parámetro','Valor','Jaccard con base'],...data.stability.map(r=>[r.method,r.parameter,r.value,r.jaccard_base])];
header(evaluation,'A14:D14');evaluation.getRange('D15:D19').setNumberFormat('0.0%');
evaluation.getRange('A:D').format.columnWidth=24;
evaluation.getRange('A23').values=[['Contaminación base: 2%. IF: semilla 42. LOF: 20 vecinos.']];
evaluation.getRange('A25').values=[['Limitaciones de la ejecución']];evaluation.getRange('A25').format.font.bold=true;
data.metadata.limitations.forEach((x,i)=>evaluation.getRange(`A${27+i}`).values=[[x]]);
evaluation.getRange('F6:G11').values=[['Prueba','Jaccard'],...data.stability.map(r=>[`${r.method} ${r.parameter} ${r.value}`,r.jaccard_base])];
evaluation.getRange('G7:G11').setNumberFormat('0.0%');header(evaluation,'F6:G6');
const ev=chart(evaluation,'F6:G11','Estabilidad de las órdenes marcadas','F14','N29');
ev.yAxis={numberFormatCode:'0%',numberFormatSourceLinked:false,textStyle:{typeface:'Arial',fontSize:10}};

wb.recalculate();
console.log((await wb.inspect({kind:'region',sheetId:'Resumen',range:'A6:B12',maxChars:1800})).ndjson);
const count=data.scoring.length;
if(summary.getRange('B7').values[0][0]!==count)throw Error('Recuento de resumen incorrecto');
// Comprobar reacción de la fórmula a una edición y restaurar antes de exportar.
const before=summary.getRange('B8').values[0][0], original=all.getRange('E6').values[0][0];
all.getRange('E6').values=[[1-original]];wb.recalculate();
if(summary.getRange('B8').values[0][0]!==before+1-2*original)throw Error('No recalcula resumen');
all.getRange('E6').values=[[original]];wb.recalculate();
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!|#SPILL!',options:{useRegex:true,maxResults:10},maxChars:1500})).ndjson);
for(const [sheet,range] of [['Resumen','A1:L36'],['Top 20','A1:F12'],['Evaluación','A1:N31'],['Órdenes','A1:H12']]){
 const preview=await wb.render({sheetName:sheet,range,scale:1,format:'png'});
 await fs.writeFile(path.join(output,`${sheet}.png`),new Uint8Array(await preview.arrayBuffer()));
}
const file=await SpreadsheetFile.exportXlsx(wb);
await file.save(path.join(output,'Reporte_OLIST.xlsx'));
console.log('Reporte guardado:',path.join(output,'Reporte_OLIST.xlsx'));
