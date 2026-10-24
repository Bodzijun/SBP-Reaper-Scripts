import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {arithmeticBody,eelModulo} from './eel-arithmetic.mjs';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8');
const body=name=>arithmeticBody(source,name);
const init=body('uc_chorus_init'),process=body('uc_chorus_process'),read=body('uc_double_read');
function create(rate){
 const size=Math.ceil(rate*.1)+4;
 const c=vm.createContext({memory:new Float64Array(size*2),size,rate,max:Math.max,min:Math.min,exp:Math.exp,sin:Math.sin,floor:Math.floor,eelModulo,$pi:Math.PI,memset:(data,value,count)=>data.fill(value,0,count)});
 c.uc_double_read=(data,length,position,delay,channel)=>{assert(delay>=0&&delay<length-2,'Read delay must fit the independent Chorus buffer');Object.assign(c,{memory:data,size:length,position,delay_samples:delay,channel});return read.runInContext(c);};
 init.runInContext(c);Object.assign(c,{input_l:0,input_r:0,enabled:0,mix:1,target_rate:.3,depth_cents:30,target_width:1,delay_ms:50});return c;
}
for(const rate of [44100,48000,96000]){
 const c=create(rate);let changed=0;
 for(let i=0;i<12000;i++){
  c.input_l=.5*Math.sin(i*.07);c.input_r=.5*Math.cos(i*.11);
  process.runInContext(c);assert.equal(c.out_l,c.input_l);assert.equal(c.out_r,c.input_r);
 }
 c.enabled=1;
 for(let i=0;i<12000;i++){
  c.input_l=.5*Math.sin(i*.07);c.input_r=.5*Math.cos(i*.11);
  process.runInContext(c);assert(Number.isFinite(c.out_l)&&Number.isFinite(c.out_r));assert(Math.abs(c.out_l)<=.500001&&Math.abs(c.out_r)<=.500001,'Chorus must not amplify bounded input');changed+=Math.abs(c.out_l-c.input_l);
 }
 assert(changed>10,'Enabled Chorus must audibly alter a periodic signal');
 const silent=create(rate);silent.enabled=1;for(let i=0;i<100;i++){process.runInContext(silent);assert.equal(silent.out_l,0);assert.equal(silent.out_r,0);}
}
console.log('PASS: actual Chorus arithmetic bodies, 44.1/48/96 kHz, exact disabled output, silence, bounded active output and audible change. Native EEL compilation still requires REAPER.');
