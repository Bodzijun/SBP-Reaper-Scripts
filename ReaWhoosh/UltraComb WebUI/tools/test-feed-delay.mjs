import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {arithmeticBody,eelModulo} from './eel-arithmetic.mjs';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8');
// Execute the actual arithmetic bodies with EEL integer modulo semantics.
const body=name=>arithmeticBody(source,name);
const init=body('uc_comb_feed_init'),process=body('uc_comb_feed_process'),read=body('uc_comb_history_read_smooth_channel');
const math={max:Math.max,min:Math.min,exp:Math.exp,floor:Math.floor,eelModulo};
const regressed=source.replace('read_pos=position-max(1,min(size-2,delay));\n  read_pos-=floor(read_pos/size)*size;',
 'read_pos=(position-max(1,min(size-2,delay))+size)%size;');
assert.throws(()=>arithmeticBody(regressed,'uc_comb_history_read_channel'),/Unmodelled EEL modulo/,'Harness must reject the old fractional EEL remainder');
const metalAddress=source.match(/read_pos=write_pos-ptr\[4\];[\s\S]+?next_index=\(index\+1\)%buffer_size;/)?.[0];
assert(metalAddress,'Metal reader must use the checked fractional address calculation');
const metalScript=new vm.Script(metalAddress.replace('(index+1)%buffer_size','eelModulo(index+1,buffer_size)'));
for(const write_pos of [0,1,8191])for(const delay of [2.25,50.123,8190]){
 const c=vm.createContext({...math,write_pos,buffer_size:8192,ptr:[0,0,0,0,delay]});metalScript.runInContext(c);
 assert(c.read_pos>=0&&c.read_pos<8192);assert(Math.abs(c.fraction-((write_pos-delay)-Math.floor(write_pos-delay)))<1e-10);
}
const metrics=[];
for(const rate of [44100,48000,96000]){
 const initial_delay=rate*.003,c=vm.createContext({...math,initial_delay,rate});init.runInContext(c);
 c.target=initial_delay;
 for(let i=0;i<100;i++)assert.equal(process.runInContext(c),initial_delay,'Startup must not sweep from zero');
 let old=initial_delay,oldVelocity=0,previous=c.position,velocity=0,maxOldJerk=0,maxJerk=0;
 const legacySlew=1-Math.exp(-1/(.05*rate));
 for(let i=0;i<Math.ceil(rate*.6);i++){
  c.target=rate*(i<rate*.3?.003+Math.floor(i/(rate*.01))*.0001:.006-Math.floor((i-rate*.3)/(rate*.01))*.0001);
  const next=process.runInContext(c),newVelocity=next-previous;
  old+=(c.target-old)*legacySlew;const nextOldVelocity=(c.target-old)*legacySlew/(1-legacySlew);
  maxOldJerk=Math.max(maxOldJerk,Math.abs(nextOldVelocity-oldVelocity));
  maxJerk=Math.max(maxJerk,Math.abs(newVelocity-velocity));
  assert(Number.isFinite(next)&&next>=rate*.003-1e-8&&next<=rate*.006+1e-8);
  previous=next;velocity=newVelocity;oldVelocity=nextOldVelocity;
 }
 assert(maxJerk<maxOldJerk*.02,'Delay velocity steps should fall by at least 98%');
 c.target=rate*.003;for(let i=0;i<rate;i++)process.runInContext(c);
 assert(Math.abs(c.position-c.target)<1e-8,'Delay must converge after a return movement');
 // Analytic sine reference isolates fractional-read error from the intended pitch bend.
 const size=4096,position=1024,frequency=6000,omega=2*Math.PI*frequency/rate;
 const memory=Float64Array.from({length:size},(_,i)=>.5*Math.sin(i*omega));
 const r=vm.createContext({...math,memory,size,position,delay:100});
 let linearError=0,cubicError=0;
 for(let i=0;i<1000;i++){
  r.delay=100+i/1000;const value=read.runInContext(r),p=position-r.delay,j=Math.floor(p),f=p-j;
  const ideal=.5*Math.sin(p*omega),linear=memory[j]*(1-f)+memory[j+1]*f;
  linearError+=(linear-ideal)**2;cubicError+=(value-ideal)**2;
 }
 assert(cubicError<linearError*.12,'Four-point reading should reduce interpolation error at 6 kHz');
 r.delay=100.25;read.runInContext(r);assert(Math.abs(r.fraction-.75)<1e-10,'Native EEL must retain the fractional read phase');
 r.position=0;read.runInContext(r);assert(Math.abs(r.fraction-.75)<1e-10,'Read phase must survive circular-buffer wrap');r.position=position;
 const epsilon=1e-6;r.delay=100-epsilon;const before=read.runInContext(r);r.delay=100+epsilon;const after=read.runInContext(r);
 assert(Math.abs(after-before)<1e-5,'Crossing an integer delay must not jump a whole sample');
 const oldAddress=delay=>Math.trunc(Math.abs(position-delay+size))%size;
 assert(Math.abs(memory[oldAddress(100-epsilon)]-memory[oldAddress(100+epsilon)])>1e-3,'Regression fixture must reproduce the old EEL whole-sample jump');
 for(const name of ['uc_comb_history_read_channel','uc_double_read','uc_dry_read']){
  const reader=body(name),stereo=name!=='uc_comb_history_read_channel';
  const data=stereo?Float64Array.from({length:size*2},(_,i)=>memory[Math.floor(i/2)]):memory;
  const test=vm.createContext({...math,memory:data,size,position:0,delay:100.25,delay_samples:100.25,channel:0});
  const output=reader.runInContext(test);assert(Math.abs(test.fraction-.75)<1e-10,`${name} must retain fractional phase`);
  assert(Number.isFinite(output));
 }
 // No sample in the current write slot may contribute, including near-zero delays.
 for(const delay of [1,1.1,1.99,2,2.01,2.5,3,3.1,size-2]){
  r.delay=delay;const before=read.runInContext(r);memory[position]=1000000;
  assert(Math.abs(read.runInContext(r)-before)<1e-10,'Read must remain causal');memory[position]=.5*Math.sin(position*omega);
 }
 metrics.push({rate,velocityStepReduction:(100*(1-maxJerk/maxOldJerk)).toFixed(2)+'%',interpolationErrorReduction:(100*(1-Math.sqrt(cubicError/linearError))).toFixed(1)+'%'});
}
// The fully supported interpolation kernel must not boost a stationary sinusoid
// in the feedback path. Check its response through Nyquist at fractional offsets.
for(let step=0;step<=100;step++){
 const f=step/100,coeff=[-.5*f+f*f-.5*f**3,1-2.5*f*f+1.5*f**3,.5*f+2*f*f-1.5*f**3,-.5*f*f+.5*f**3];
 for(let k=0;k<=512;k++){
  const omega=Math.PI*k/512,re=coeff.reduce((s,a,j)=>s+a*Math.cos(j*omega),0),im=coeff.reduce((s,a,j)=>s+a*Math.sin(j*omega),0);
  assert(Math.hypot(re,im)<=1+1e-12,'Interpolation must not introduce stationary feedback gain');
 }
}
console.log('PASS: EEL-aware regression reproduces the old sample jump; all five reader sites preserve fractions, including wrap boundaries. FX Feed startup, glide, return, causal reads and stationary feedback gain pass.');
console.log(JSON.stringify(metrics));
console.log('Native EEL compilation and listening still require REAPER.');
