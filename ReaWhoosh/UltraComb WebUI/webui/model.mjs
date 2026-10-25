export const modules=[
 {key:'freeze',name:'FREEZE / STUTTER',on:48,main:[49,50],extra:[51]},
 {key:'pitch',name:'PITCH SHIFT',on:38,main:[39,44,43],extra:[]},
 {key:'double',name:'DOUBLER',on:52,main:[53,54,55],extra:[56,68,69,70,71,72]},
 {key:'ring',name:'RING MODULATOR',on:24,main:[25,26,27],extra:[]},
 {key:'metal',name:'METAL RESONATOR',on:33,main:[34,35,36,37],extra:[]},
 {key:'sat',name:'SATURATION',on:125,main:[126,23,128,127],extra:[130,129]},
 {key:'filter',name:'FILTER',on:74,main:[76,77,78,79],extra:[75]},
 {key:'chorus',name:'CHORUS',on:119,main:[57,58,121,120],extra:[122]}
];
export const coreGroups={comb:{main:[4,5],extra:[]},disperser:{primary:[7],main:[8,9,10,11,136],extra:[]},shift:{primary:[12],main:[137,138,139],extra:[]}};
export const modulationGroups=[
 {key:'shift',name:'LFO 1',ids:[15,114,115],telemetry:2,on:14,shape:20,depth:114,sync:192,division:195},
 {key:'lfo2',name:'LFO 2',ids:[132,134,135],telemetry:7,on:131,shape:133,depth:134,sync:193,division:196},
 {key:'envelope',name:'Envelope',ids:[117,61,62,63,64],telemetry:6},
 {key:'adr',name:'ADR 1',ids:[140,141,142,191,143,147,144,189,146,190,145],telemetry:8,sync:194,adr:{"mode":140,"source":141,"threshold":142,"attack":143,"decay":144,"level":145,"release":146,"attackCurve":147,"decayCurve":189,"releaseCurve":190,"direction":191,"sync":194,"divisionA":197,"divisionD":198,"divisionR":199,"command":"adrTrigger"}},
 {key:'adr2',name:'ADR 2',ids:[200,201,202,210,203,207,204,208,206,209,205],telemetry:9,sync:211,adr:{"mode":200,"source":201,"threshold":202,"attack":203,"decay":204,"level":205,"release":206,"attackCurve":207,"decayCurve":208,"releaseCurve":209,"direction":210,"sync":211,"divisionA":212,"divisionD":213,"divisionR":214,"command":"adr2Trigger"}}
];
export const matrixTargets=[{"id":0,"label":"None","scale":0,"unit":"","group":"None"},{"id":1,"label":"Core / Dry Delay","scale":25,"unit":"ms","group":"Core"},{"id":2,"label":"Core / FX Feed","scale":200,"unit":"ms","group":"Core"},{"id":3,"label":"Disperser / Center","scale":4,"unit":"oct","group":"Disperser"},{"id":4,"label":"Shift / Frequency","scale":5000,"unit":"Hz","group":"Shift"},{"id":5,"label":"Pitch / Semitones","scale":24,"unit":"st","group":"Pitch"},{"id":6,"label":"Ring / Carrier","scale":10000,"unit":"Hz","group":"Ring"},{"id":7,"label":"Metal / Size","scale":2,"unit":"oct","group":"Metal"},{"id":8,"label":"Double / Pitch","scale":24,"unit":"st","group":"Double"},{"id":9,"label":"Filter / Cutoff","scale":6,"unit":"oct","group":"Filter"},{"id":10,"label":"Core / Feedback","scale":0.5,"unit":"","group":"Core"},{"id":11,"label":"Global / Output","scale":12,"unit":"dB","group":"Global"},{"id":12,"label":"LFO 1 / Rate","scale":4,"unit":"oct","group":"LFO 1"},{"id":13,"label":"LFO 1 / Depth","scale":100,"unit":"%","group":"LFO 1"},{"id":14,"label":"LFO 2 / Rate","scale":4,"unit":"oct","group":"LFO 2"},{"id":15,"label":"LFO 2 / Depth","scale":100,"unit":"%","group":"LFO 2"},{"id":16,"label":"Core / Drive","scale":12,"unit":"dB","group":"Core"},{"id":17,"label":"Core / Dry-FX","scale":1,"unit":"","group":"Core"},{"id":18,"label":"Core / FX Return","scale":1.9,"unit":"","group":"Core"},{"id":19,"label":"Core / Feedback Sat","scale":1,"unit":"","group":"Core"},{"id":20,"label":"Disperser / Q","scale":3,"unit":"oct","group":"Disperser"},{"id":21,"label":"Disperser / Spread","scale":200,"unit":"%","group":"Disperser"},{"id":22,"label":"Disperser / Phase Sub","scale":1,"unit":"","group":"Disperser"},{"id":23,"label":"Ring / Depth","scale":1,"unit":"","group":"Ring"},{"id":24,"label":"Ring / Mix","scale":1,"unit":"","group":"Ring"},{"id":25,"label":"Metal / Decay","scale":3,"unit":"oct","group":"Metal"},{"id":26,"label":"Metal / Tone","scale":1,"unit":"","group":"Metal"},{"id":27,"label":"Metal / Mix","scale":1,"unit":"","group":"Metal"},{"id":28,"label":"Pitch / Mix","scale":1,"unit":"","group":"Pitch"},{"id":29,"label":"Pitch / Recovery","scale":90,"unit":"ms","group":"Pitch"},{"id":30,"label":"Double / Detune","scale":50,"unit":"ct","group":"Double"},{"id":31,"label":"Double / Mix","scale":1,"unit":"","group":"Double"},{"id":32,"label":"Double / Width","scale":1,"unit":"","group":"Double"},{"id":33,"label":"Double / Gain","scale":12,"unit":"dB","group":"Double"},{"id":34,"label":"Double / Delay","scale":100,"unit":"ms","group":"Double"},{"id":35,"label":"Chorus / Rate","scale":4,"unit":"oct","group":"Chorus"},{"id":36,"label":"Chorus / Depth","scale":30,"unit":"ct","group":"Chorus"},{"id":37,"label":"Chorus / Width","scale":1,"unit":"","group":"Chorus"},{"id":38,"label":"Chorus / Mix","scale":1,"unit":"","group":"Chorus"},{"id":39,"label":"Chorus / Delay","scale":49,"unit":"ms","group":"Chorus"},{"id":40,"label":"Filter / Resonance","scale":1,"unit":"","group":"Filter"},{"id":41,"label":"Filter / Drive","scale":24,"unit":"dB","group":"Filter"},{"id":42,"label":"Filter / Mix","scale":1,"unit":"","group":"Filter"},{"id":43,"label":"SAT / Drive","scale":24,"unit":"dB","group":"SAT"},{"id":44,"label":"SAT / Amount","scale":1,"unit":"","group":"SAT"},{"id":45,"label":"SAT / Tone","scale":2,"unit":"","group":"SAT"},{"id":46,"label":"SAT / Asymmetry","scale":2,"unit":"","group":"SAT"},{"id":47,"label":"SAT / Mix","scale":1,"unit":"","group":"SAT"},{"id":48,"label":"Freeze / Mix","scale":1,"unit":"","group":"Freeze"},{"id":49,"label":"Disperser / Spread Curve","scale":1,"unit":"","group":"Disperser"}];
matrixTargets.push({id:50,label:'Shift / Stereo Offset',scale:1000,unit:'Hz',group:'Shift'},
 {id:51,label:'Shift / Sideband',scale:2,unit:'',group:'Shift'},
 {id:52,label:'Shift / Mix',scale:1,unit:'',group:'Shift'});
matrixTargets.push({id:53,label:'ADR / Attack',scale:4,unit:'oct',group:'ADR'},
 {id:54,label:'ADR / Decay',scale:4,unit:'oct',group:'ADR'},
 {id:55,label:'ADR / Bend Level',scale:1,unit:'',group:'ADR'},
 {id:56,label:'ADR / Release',scale:4,unit:'oct',group:'ADR'},
 {id:57,label:'ADR / Attack Curve',scale:2,unit:'',group:'ADR'});
matrixTargets.push({id:58,label:'LFO 1 / Phase',scale:360,unit:'°',group:'LFO 1'},
 {id:59,label:'LFO 2 / Phase',scale:360,unit:'°',group:'LFO 2'},
 {id:60,label:'Motion / Decay',scale:4,unit:'oct',group:'Legacy',deprecated:true},
 {id:61,label:'Motion / Threshold',scale:60,unit:'dB',group:'Legacy',deprecated:true},
 {id:62,label:'Envelope / Depth',scale:2,unit:'',group:'Envelope'},
 {id:63,label:'Envelope / Sensitivity',scale:48,unit:'dB',group:'Envelope'},
 {id:64,label:'Envelope / Attack',scale:4,unit:'oct',group:'Envelope'},
 {id:65,label:'Envelope / Release',scale:4,unit:'oct',group:'Envelope'},
 {id:66,label:'ADR / Threshold',scale:60,unit:'dB',group:'ADR'},
 {id:67,label:'Double / Low Cut',scale:2000,unit:'Hz',group:'Double'},
 {id:68,label:'Double / High Cut',scale:4,unit:'oct',group:'Double'});
matrixTargets.push({id:69,label:'ADR / Decay Curve',scale:2,unit:'',group:'ADR'},
 {id:70,label:'ADR / Release Curve',scale:2,unit:'',group:'ADR'});
for(const target of matrixTargets)if(target.group==='ADR'){target.group='ADR 1';target.label=target.label.replace('ADR /','ADR 1 /');}
for(const [i,name,scale,unit]of [[71,'Attack',4,'oct'],[72,'Decay',4,'oct'],[73,'Bend Level',1,''],[74,'Release',4,'oct'],[75,'Attack Curve',2,''],[76,'Threshold',60,'dB'],[77,'Decay Curve',2,''],[78,'Release Curve',2,'']])matrixTargets.push({id:i,label:'ADR 2 / '+name,scale,unit,group:'ADR 2'});
export const matrixScales=matrixTargets.map(t=>t.scale);
export const matrixUnits=matrixTargets.map(t=>t.unit);
export const sharedLfoLabels={114:'Depth',115:'Phase',132:'Rate',134:'Depth',135:'Phase'};
export const labels={1:'Drive',2:'Output',3:'Tap / FX',4:'Tap Delay',5:'FX Feed',6:'Feedback',7:'Center',8:'Q / Pinch',9:'Spread',10:'Stages',11:'Phase Sub',12:'Shift',13:'FX Return',14:'LFO',15:'Rate',16:'Depth',17:'LFO',18:'Rate',19:'Depth',20:'Shape',21:'Shape',23:'Saturation',25:'Carrier',26:'Depth',27:'Mix',28:'Motion',29:'Rate',30:'Depth',31:'Stereo Phase',32:'Shape',34:'Size',35:'Decay',36:'Tone',37:'Mix',39:'Pitch',40:'Motion',41:'Rate',42:'Glide / Decay',43:'Recovery',44:'Mix',45:'Mode',46:'Attack Gate',49:'Loop',50:'Mix',51:'Direction',53:'Voice Pitch',54:'Detune',55:'Voice Mix',56:'Width',57:'Chorus Rate',58:'Chorus Depth',60:'Target',61:'Depth',62:'Sensitivity',63:'Attack',64:'Release',65:'Morph A / B',66:'Amount',67:'Scope',68:'Voice Gain',69:'Voice Delay',70:'Low Cut',71:'High Cut',72:'Polarity',75:'Type',76:'Cutoff',77:'Resonance',78:'Drive',79:'Mix',80:'Rate',81:'Depth',82:'Shape',85:'Clip',86:'Ceiling',87:'Mode'};
export const units={1:'dB',2:'dB',4:'ms',5:'ms',7:'Hz',9:'%',12:'Hz',15:'Hz',16:'Hz',18:'Hz',19:'%',25:'Hz',29:'Hz',30:'ms',31:'°',35:'s',39:'st',40:'st',41:'Hz',42:'ms',43:'ms',46:'dB',49:'ms',53:'st',54:'ct',57:'Hz',58:'ct',62:'dB',63:'ms',64:'ms',68:'dB',69:'ms',70:'Hz',71:'Hz',76:'Hz',78:'dB',80:'Hz',81:'oct',86:'dB'};
Object.assign(labels,{132:'Rate',134:'Depth',135:'Phase',136:'Curve',137:'Stereo Offset',138:'Sideband',139:'Shift Mix'});
Object.assign(units,{114:'%',115:'°',132:'Hz',134:'%',135:'°',137:'Hz'});
Object.assign(labels,{140:'Mode',141:'Source',142:'Threshold',143:'Attack',144:'Decay',145:'Bend Level',146:'Release',147:'A Curve',189:'D Curve',190:'R Curve'});
Object.assign(labels,{192:'Timing',193:'Timing',194:'Timing',195:'Rate',196:'Rate',197:'Attack',198:'Decay',199:'Release'});
Object.assign(labels,{188:'Scope',191:'Loop Direction'});
Object.assign(units,{142:'dB',143:'ms',144:'ms',146:'ms'});
const logIds=new Set([7,71,76,143,144,146]);
Object.assign(labels,{3:'Dry / FX',4:'Dry Delay'});
for(const [old,id]of [[140,200],[141,201],[142,202],[143,203],[144,204],[145,205],[146,206],[147,207],[189,208],[190,209],[191,210],[194,211],[197,212],[198,213],[199,214]]){labels[id]=labels[old];if(units[old])units[id]=units[old];}
export function formatControlLabel(parameter){
 const unit=units[parameter.id]||'',name=labels[parameter.id]||parameter.name;
 return unit?`${name.replace(/\s*\([^)]*\)\s*$/,'')}, ${unit}`:name;
}
export function toPosition(p,value,sensitivity='linear'){
 if(p.id===25)return Math.sqrt(Math.max(0,(value-p.min)/(p.max-p.min)));
 if(p.id===137||p.id===12&&sensitivity==='fine')return .5+.5*Math.sign(value)*Math.cbrt(Math.abs(value)/p.max);
 if(logIds.has(p.id))return Math.log(Math.max(p.min,value)/p.min)/Math.log(p.max/p.min);
 return (value-p.min)/(p.max-p.min);
}
export function fromPosition(p,position,sensitivity='linear'){
 const t=Math.max(0,Math.min(1,position));let value;
 if(p.id===25)value=p.min+(p.max-p.min)*t*t;
 else if(p.id===137||p.id===12&&sensitivity==='fine')value=p.max*(2*t-1)**3;
 else if(logIds.has(p.id))value=p.min*(p.max/p.min)**t;
 else value=p.min+(p.max-p.min)*t;
 return Math.max(p.min,Math.min(p.max,p.min+Math.round((value-p.min)/p.step)*p.step));
}
export function decodeOrder(rank,position,chorusPosition=7){
 const available=[0,1,2,3,4,5],result=[];let factor=120;
 for(let n=0;n<6;n++){const digit=Math.floor(rank/factor);rank-=digit*factor;result.push(available.splice(digit,1)[0]);factor=Math.max(1,factor/Math.max(1,5-n));}
 result.splice(position,0,6);result.splice(chorusPosition,0,7);return result;
}
export function encodeOrder(order){
 const chorusPosition=order.indexOf(7),seven=order.filter(x=>x!==7),position=seven.indexOf(6),six=seven.filter(x=>x!==6),available=[0,1,2,3,4,5];let rank=0,factor=120;
 six.forEach((value,i)=>{const digit=available.indexOf(value);rank+=digit*factor;available.splice(digit,1);factor=Math.max(1,factor/Math.max(1,5-i));});
 return {rank,position,chorusPosition};
}
