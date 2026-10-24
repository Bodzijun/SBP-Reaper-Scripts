import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8');
function body(name){const at=source.indexOf(`function ${name}(`),tail=source.slice(at),match=/global\(\)\s*\(/.exec(tail);assert(at>=0&&match);const start=at+match.index+match[0].length;return new vm.Script(source.slice(start,source.indexOf('\n);',start)));}
const init=body('uc_sat_init'),process=body('uc_sat_process'),shape=body('uc_sat_transfer');
const math={max:Math.max,min:Math.min,abs:Math.abs,exp:Math.exp,pow:Math.pow,sqrt:Math.sqrt,$pi:Math.PI};
function create(amount=0){const c=vm.createContext({...math,rate:48000,initial_amount:amount});init.runInContext(c);const s=vm.createContext({...math});c.uc_sat_transfer=(input,soft_weight,cubic_weight,rational_weight,hard_weight)=>{Object.assign(s,{input,soft_weight,cubic_weight,rational_weight,hard_weight});return shape.runInContext(s);};Object.assign(c,{input_l:0,input_r:0,target_amount:1,enabled:1,extra_drive:0,mix:1,target_tone:0,target_asymmetry:0,curve:0});return c;}
// Default controls retain the old Soft curve, linked compensation and amount law.
const c=create();let amount=0,ip=0,sp=0;
for(let i=0;i<3000;i++){
 c.input_l=.3*Math.sin(i*.11);c.input_r=.2*Math.cos(i*.17);process.runInContext(c);
 amount+=(1-amount)*c.slew;const drive=10**(amount*30/20),l=Math.tanh(c.input_l*drive),r=Math.tanh(c.input_r*drive);
 ip+=((c.input_l**2+c.input_r**2)*.5-ip)*c.power_slew;sp+=((l*l+r*r)*.5-sp)*c.power_slew;
 const comp=Math.max(1/drive,Math.min(1,Math.sqrt((ip+1e-24)/(sp+1e-24))));
 assert(Math.abs(c.out_l-(c.input_l+(l*comp-c.input_l)*amount))<1e-10);
}
for(let curve=0;curve<4;curve++)for(const asymmetry of [-1,0,1]){
 const s=create();Object.assign(s,{curve,target_asymmetry:asymmetry,target_tone:curve%2?1:-1,extra_drive:24});
 for(let i=0;i<300;i++){process.runInContext(s);assert.equal(s.out_l,0);assert.equal(s.out_r,0);}
 s.enabled=0;s.amount=0;
 for(let i=0;i<100;i++){s.input_l=.25*Math.sin(i);s.input_r=-s.input_l;process.runInContext(s);assert(s.out_l===s.input_l);assert(s.out_r===s.input_r);}
 s.enabled=1;for(let i=0;i<500;i++){s.input_l=.5*Math.sin(i*.1);s.input_r=-s.input_l;process.runInContext(s);assert(Number.isFinite(s.out_l)&&Number.isFinite(s.out_r));assert(Math.abs(s.out_l)<4&&Math.abs(s.out_r)<4);}
}
function render(settings){const c=create(.6);Object.assign(c,{target_amount:.6,...settings});const samples=[];for(let i=0;i<4000;i++){c.input_l=.2*Math.sin(i*.13)+.15*Math.sin(i*1.3);c.input_r=c.input_l;process.runInContext(c);if(i>=3000)samples.push(c.out_l);}return samples;}
const baseline=render({});
for(const settings of [{extra_drive:18},{mix:.25},{target_tone:1},{target_tone:-1},{target_asymmetry:1},{curve:1},{curve:2},{curve:3}]){
 const samples=render(settings),difference=samples.reduce((sum,value,i)=>sum+Math.abs(value-baseline[i]),0);
 assert(difference>.01,`Control must alter output: ${JSON.stringify(settings)}`);
}
console.log('PASS: actual SAT arithmetic, neutral Soft equivalence, four curves, independent audible-control differences, asymmetry extremes, silence, disabled identity and finite output. Native EEL/audio tests still required.');
