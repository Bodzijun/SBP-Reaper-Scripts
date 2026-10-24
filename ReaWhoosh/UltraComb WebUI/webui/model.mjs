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
export const coreGroups={comb:{main:[4,5],extra:[]},disperser:{main:[7,8,9,10,11],extra:[]},shift:{main:[12],extra:[]}};
export const modulationGroups=[
 {key:'shift',name:'LFO 1',ids:[15,114,115],telemetry:2,on:14,shape:20,depth:114},
 {key:'lfo2',name:'LFO 2',ids:[132,134,135],telemetry:7,on:131,shape:133,depth:134},
 {key:'pitch',name:'Motion',ids:[45,116,42,46],telemetry:3},
 {key:'envelope',name:'Envelope',ids:[117,61,62,63,64],telemetry:6}
];
export const matrixTargets=[{"id":0,"label":"None","scale":0,"unit":"","group":"None"},{"id":1,"label":"Core / Dry Delay","scale":25,"unit":"ms","group":"Core"},{"id":2,"label":"Core / FX Feed","scale":25,"unit":"ms","group":"Core"},{"id":3,"label":"Disperser / Center","scale":4,"unit":"oct","group":"Disperser"},{"id":4,"label":"Shift / Frequency","scale":5000,"unit":"Hz","group":"Shift"},{"id":5,"label":"Pitch / Semitones","scale":24,"unit":"st","group":"Pitch"},{"id":6,"label":"Ring / Carrier","scale":10000,"unit":"Hz","group":"Ring"},{"id":7,"label":"Metal / Size","scale":2,"unit":"oct","group":"Metal"},{"id":8,"label":"Double / Pitch","scale":24,"unit":"st","group":"Double"},{"id":9,"label":"Filter / Cutoff","scale":6,"unit":"oct","group":"Filter"},{"id":10,"label":"Core / Feedback","scale":0.5,"unit":"","group":"Core"},{"id":11,"label":"Global / Output","scale":12,"unit":"dB","group":"Global"},{"id":12,"label":"LFO 1 / Rate","scale":4,"unit":"oct","group":"LFO 1"},{"id":13,"label":"LFO 1 / Depth","scale":100,"unit":"%","group":"LFO 1"},{"id":14,"label":"LFO 2 / Rate","scale":4,"unit":"oct","group":"LFO 2"},{"id":15,"label":"LFO 2 / Depth","scale":100,"unit":"%","group":"LFO 2"},{"id":16,"label":"Core / Drive","scale":12,"unit":"dB","group":"Core"},{"id":17,"label":"Core / Dry-FX","scale":1,"unit":"","group":"Core"},{"id":18,"label":"Core / FX Return","scale":1.9,"unit":"","group":"Core"},{"id":19,"label":"Core / Feedback Sat","scale":1,"unit":"","group":"Core"},{"id":20,"label":"Disperser / Q","scale":3,"unit":"oct","group":"Disperser"},{"id":21,"label":"Disperser / Spread","scale":200,"unit":"%","group":"Disperser"},{"id":22,"label":"Disperser / Phase Sub","scale":1,"unit":"","group":"Disperser"},{"id":23,"label":"Ring / Depth","scale":1,"unit":"","group":"Ring"},{"id":24,"label":"Ring / Mix","scale":1,"unit":"","group":"Ring"},{"id":25,"label":"Metal / Decay","scale":3,"unit":"oct","group":"Metal"},{"id":26,"label":"Metal / Tone","scale":1,"unit":"","group":"Metal"},{"id":27,"label":"Metal / Mix","scale":1,"unit":"","group":"Metal"},{"id":28,"label":"Pitch / Mix","scale":1,"unit":"","group":"Pitch"},{"id":29,"label":"Pitch / Recovery","scale":90,"unit":"ms","group":"Pitch"},{"id":30,"label":"Double / Detune","scale":50,"unit":"ct","group":"Double"},{"id":31,"label":"Double / Mix","scale":1,"unit":"","group":"Double"},{"id":32,"label":"Double / Width","scale":1,"unit":"","group":"Double"},{"id":33,"label":"Double / Gain","scale":12,"unit":"dB","group":"Double"},{"id":34,"label":"Double / Delay","scale":100,"unit":"ms","group":"Double"},{"id":35,"label":"Chorus / Rate","scale":4,"unit":"oct","group":"Chorus"},{"id":36,"label":"Chorus / Depth","scale":30,"unit":"ct","group":"Chorus"},{"id":37,"label":"Chorus / Width","scale":1,"unit":"","group":"Chorus"},{"id":38,"label":"Chorus / Mix","scale":1,"unit":"","group":"Chorus"},{"id":39,"label":"Chorus / Delay","scale":49,"unit":"ms","group":"Chorus"},{"id":40,"label":"Filter / Resonance","scale":1,"unit":"","group":"Filter"},{"id":41,"label":"Filter / Drive","scale":24,"unit":"dB","group":"Filter"},{"id":42,"label":"Filter / Mix","scale":1,"unit":"","group":"Filter"},{"id":43,"label":"SAT / Drive","scale":24,"unit":"dB","group":"SAT"},{"id":44,"label":"SAT / Amount","scale":1,"unit":"","group":"SAT"},{"id":45,"label":"SAT / Tone","scale":2,"unit":"","group":"SAT"},{"id":46,"label":"SAT / Asymmetry","scale":2,"unit":"","group":"SAT"},{"id":47,"label":"SAT / Mix","scale":1,"unit":"","group":"SAT"},{"id":48,"label":"Freeze / Mix","scale":1,"unit":"","group":"Freeze"}];
export const matrixScales=matrixTargets.map(t=>t.scale);
export const matrixUnits=matrixTargets.map(t=>t.unit);
export const sharedLfoLabels={114:'Depth',115:'Phase',132:'Rate',134:'Depth',135:'Phase'};
export const labels={1:'Drive',2:'Output',3:'Tap / FX',4:'Tap Delay',5:'FX Feed',6:'Feedback',7:'Center',8:'Q / Pinch',9:'Spread',10:'Stages',11:'Phase Sub',12:'Shift',13:'FX Return',14:'LFO',15:'Rate',16:'Depth',17:'LFO',18:'Rate',19:'Depth',20:'Shape',21:'Shape',23:'Saturation',25:'Carrier',26:'Depth',27:'Mix',28:'Motion',29:'Rate',30:'Depth',31:'Stereo Phase',32:'Shape',34:'Size',35:'Decay',36:'Tone',37:'Mix',39:'Pitch',40:'Motion',41:'Rate',42:'Glide / Decay',43:'Recovery',44:'Mix',45:'Mode',46:'Attack Gate',49:'Loop',50:'Mix',51:'Direction',53:'Voice Pitch',54:'Detune',55:'Voice Mix',56:'Width',57:'Chorus Rate',58:'Chorus Depth',60:'Target',61:'Depth',62:'Sensitivity',63:'Attack',64:'Release',65:'Morph A / B',66:'Amount',67:'Scope',68:'Voice Gain',69:'Voice Delay',70:'Low Cut',71:'High Cut',72:'Polarity',75:'Type',76:'Cutoff',77:'Resonance',78:'Drive',79:'Mix',80:'Rate',81:'Depth',82:'Shape',85:'Clip',86:'Ceiling',87:'Mode'};
export const units={1:'dB',2:'dB',4:'ms',5:'ms',7:'Hz',9:'%',12:'Hz',15:'Hz',16:'Hz',18:'Hz',19:'%',25:'Hz',29:'Hz',30:'ms',31:'°',35:'s',39:'st',40:'st',41:'Hz',42:'ms',43:'ms',46:'dB',49:'ms',53:'st',54:'ct',57:'Hz',58:'ct',62:'dB',63:'ms',64:'ms',68:'dB',69:'ms',70:'Hz',71:'Hz',76:'Hz',78:'dB',80:'Hz',81:'oct',86:'dB'};
Object.assign(labels,{132:'Rate',134:'Depth',135:'Phase'});
Object.assign(units,{114:'%',115:'°',132:'Hz',134:'%',135:'°'});
const logIds=new Set([7,71,76]);
Object.assign(labels,{3:'Dry / FX',4:'Dry Delay'});
export function toPosition(p,value){
 if(p.id===25)return Math.sqrt(Math.max(0,(value-p.min)/(p.max-p.min)));
 if(p.id===12)return .5+.5*Math.sign(value)*Math.cbrt(Math.abs(value)/p.max);
 if(logIds.has(p.id))return Math.log(Math.max(p.min,value)/p.min)/Math.log(p.max/p.min);
 return (value-p.min)/(p.max-p.min);
}
export function fromPosition(p,position){
 const t=Math.max(0,Math.min(1,position));let value;
 if(p.id===25)value=p.min+(p.max-p.min)*t*t;
 else if(p.id===12)value=p.max*(2*t-1)**3;
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
