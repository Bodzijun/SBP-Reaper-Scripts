import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8');
// Translate only the bounded EEL syntax used by these two actual configuration
// bodies. This checks memory targets and call counts, not native compilation.
function compile(name){
 const at=source.indexOf(`function ${name}(`),start=source.indexOf('\n(',source.indexOf('global()',at))+2;
 let code=source.slice(start,source.indexOf('\n);',start));
 code=code.replace(/^(\s*)(.+?)\s+\?\s+\(\s*$/gm,'$1if ($2) {')
  .replace(/loop\((128|6),/g,'for(let iteration=0;iteration<$1;iteration++){')
  .replace(/^\s*\);\s*$/gm,'}')
  .replace(/stages<=1 \? position=0;/g,'if(stages<=1) position=0;')
  .replace(/\b(target|current|ptr|ratio_memory)\[([^\]]+)\]/g,'ram[$1+($2)]');
 return new vm.Script(code);
}
const disp=compile('uc_disp_config'),metal=compile('uc_metal_configure');
function context(){
 let trig=0,exponentials=0;
 const c=vm.createContext({ram:new Float64Array(5000),state:0,sample_rate:48000,configured:0,config_ready:0,target_memory:2000,ratio_memory:2200,buffer_size:8192,
  max:Math.max,min:Math.min,pow:Math.pow,sqrt:Math.sqrt,log:Math.log,$pi:Math.PI,
  sin:v=>(trig++,Math.sin(v)),cos:v=>(trig++,Math.cos(v)),exp:v=>(exponentials++,Math.exp(v))});
 [1,1.37,1.91,2.63,3.79,5.17].forEach((v,i)=>c.ram[2200+i]=v);
 return {c,trig:()=>trig,exp:()=>exponentials};
}
for(const rate of [44100,48000,96000]){
 const a=context();Object.assign(a.c,{sample_rate:rate,center:200,spread:100,q:2,stages:48,immediate:1,size:1,decay_seconds:.6,tone:.65});disp.runInContext(a.c);metal.runInContext(a.c);a.c.immediate=0;
 const before=a.c.ram.slice(),trig=a.trig(),exp=a.exp();
 for(let i=0;i<1000;i++){disp.runInContext(a.c);metal.runInContext(a.c);}
 assert.equal(a.trig(),trig,'Unchanged Disperser inputs must perform no trig work');assert.equal(a.exp(),exp,'Unchanged Metal inputs must perform no exponential work');assert.deepEqual(a.c.ram,before);
 for(const [key,value]of [['center',18000],['spread',200],['q',20],['stages',128],['center',40],['stages',0]]){
  a.c[key]=value;disp.runInContext(a.c);
  const fresh=context();Object.assign(fresh.c,{sample_rate:rate,center:a.c.center,spread:a.c.spread,q:a.c.q,stages:a.c.stages,immediate:0});disp.runInContext(fresh.c);
  assert.deepEqual(a.c.ram.slice(1280,1536),fresh.c.ram.slice(1280,1536),'Cached updates must match a fresh configuration');
 }
 for(const [key,value]of [['size',4],['decay_seconds',3],['tone',1],['size',.25],['tone',0]]){
  a.c[key]=value;metal.runInContext(a.c);
  const fresh=context();Object.assign(fresh.c,{sample_rate:rate,size:a.c.size,decay_seconds:a.c.decay_seconds,tone:a.c.tone});metal.runInContext(fresh.c);
  assert.deepEqual(a.c.ram.slice(2000,2030),fresh.c.ram.slice(2000,2030));
 }
 const count=a.trig();a.c.immediate=1;disp.runInContext(a.c);assert(a.trig()>count,'Reinitialization must bypass the cache');
}
console.log('PASS: actual Disperser/Metal config bodies, unchanged calls skip expensive math; every changed input matches uncached targets at 44.1/48/96 kHz. Native EEL compilation still requires REAPER.');
