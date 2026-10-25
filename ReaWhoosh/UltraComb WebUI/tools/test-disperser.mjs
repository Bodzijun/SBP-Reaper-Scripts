import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {spreadPosition,sectionFrequencies,allpassCoefficients,sectionGroupDelay,disperserModel} from '../webui/disperser-view.mjs';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8');
const at=source.indexOf('function uc_disp_config('),start=source.indexOf('\n(',source.indexOf('global()',at))+2;
let code=source.slice(start,source.indexOf('\n);',start));
code=code.replace(/^(\s*)(.+?)\s+\?\s+\(\s*$/gm,'$1if ($2) {').replace(/loop\(128,/g,'for(let iteration=0;iteration<128;iteration++){').replace(/^\s*\);\s*$/gm,'}').replace(/stages<=1 \? position=0;/g,'if(stages<=1) position=0;').replace(/\b(target|current)\[([^\]]+)\]/g,'ram[$1+($2)]');
const configure=new vm.Script(code);
const previousConfigure=new vm.Script(code.replace(/position=curve==0[^\n]+\n/,''));
function native(settings,program=configure){const c=vm.createContext({ram:new Float64Array(1600),state:0,configured:0,config_curve:0,immediate:1,sample_rate:settings.sampleRate,max:Math.max,min:Math.min,abs:Math.abs,pow:Math.pow,sin:Math.sin,cos:Math.cos,$pi:Math.PI,...settings});program.runInContext(c);return Array.from({length:settings.stages},(_,i)=>({a2:c.ram[1280+i*2],a1:c.ram[1281+i*2]}));}
function response(omega,{a1,a2}){
 const c1=Math.cos(omega),s1=Math.sin(omega),c2=Math.cos(2*omega),s2=Math.sin(2*omega);
 const nr=a2+a1*c1+c2,ni=-a1*s1-s2,dr=1+a1*c1+a2*c2,di=-a1*s1-a2*s2,d=dr*dr+di*di;
 return {re:(nr*dr+ni*di)/d,im:(ni*dr-nr*di)/d};
}
for(const rate of [44100,48000,96000,192000])for(const stages of [0,1,2,48,128])for(const curve of [-1,0,1]){
 const settings={center:1000,spread:200,q:2,stages,curve,sampleRate:rate},frequencies=sectionFrequencies(settings),coefficients=native(settings);
 assert.equal(frequencies.length,stages);assert(frequencies.every((f,i)=>f>=20&&f<=rate*.49&&(!i||f>=frequencies[i-1])));
 if(curve===0)assert.deepEqual(coefficients,native(settings,previousConfigure),'Neutral Curve must exactly preserve the previous filter coefficients');
 for(let i=0;i<stages;i++){
  const expected=allpassCoefficients(frequencies[i],2,rate);assert(Math.abs(coefficients[i].a1-expected.a1)<1e-12&&Math.abs(coefficients[i].a2-expected.a2)<1e-12,'Visual centres must match actual native coefficient targets');
 }
}
assert(spreadPosition(.5,1)<.5&&spreadPosition(.5,-1)>.5);
for(const q of [.1,2,20])for(const curve of [-1,0,1]){
 const settings={center:1000,spread:100,q,stages:48,curve,sampleRate:48000},coefficients=native(settings);
 for(const frequency of [40,200,777,1000,1500,7000,18000]){
  const omega=2*Math.PI*frequency/48000,epsilon=1e-6;
  for(const c of coefficients){
   const mid=response(omega,c),lo=response(omega-epsilon,c),hi=response(omega+epsilon,c);
   assert(Math.abs(Math.hypot(mid.re,mid.im)-1)<1e-8,'All-pass must retain unity magnitude');
   const delta=Math.atan2(hi.im*lo.re-hi.re*lo.im,hi.re*lo.re+hi.im*lo.im),numeric=-delta/(2*epsilon),analytic=sectionGroupDelay(omega,c);
   assert(Math.abs(numeric-analytic)<Math.max(.002,Math.abs(numeric)*.001),'Q display must match the derivative of native all-pass phase');
  }
 }
}
const base={center:1000,spread:0,q:2,stages:1,curve:0,sampleRate:48000};
const wide=disperserModel(350,{...base,q:.5}),narrow=disperserModel(350,{...base,q:10});assert(narrow.peak>wide.peak*10);
const bandwidth=model=>model.profile.filter(p=>p.delay>=model.peak*.5).map(p=>p.frequency);
const a=bandwidth(wide),b=bandwidth(narrow);assert(b.at(-1)-b[0]<a.at(-1)-a[0]);
assert.equal(disperserModel(350,{...base,stages:0}).peak,0);
// A Center sweep must never shrink the normalized hill at rounded scale steps.
let previousRatio=null,previousLegacyRatio=null,maxLegacyStep=0;
for(let center=40;center<=18000;center*=1.025){
 const model=disperserModel(350,{...base,center,q:7.56,stages:96,curve:.92,spread:200});
 const ratio=model.peak/model.ceiling;
 assert(Math.abs(ratio-1/1.15)<1e-12,'Autoscaling must be continuous with constant headroom');
 if(previousRatio!==null)assert(Math.abs(ratio-previousRatio)<1e-12);
 const decade=10**Math.floor(Math.log10(model.peak)),legacyRatio=model.peak/(Math.ceil(model.peak/decade)*decade);
 if(previousLegacyRatio!==null)maxLegacyStep=Math.max(maxLegacyStep,Math.abs(legacyRatio-previousLegacyRatio));
 previousRatio=ratio;previousLegacyRatio=legacyRatio;
}
assert(maxLegacyStep>.1,'Sweep fixture must expose the previous stepped scaling');
for(const width of [250,350,500]){const model=disperserModel(width,{...base,stages:128,curve:1,spread:200});assert(model.profile.every(p=>Number.isFinite(p.delay)&&p.delay>=0));}
let difference=0;
const ends=[-1,1].map(curve=>native({...base,stages:48,spread:100,curve}));
for(let i=0;i<100;i++){const omega=2*Math.PI*(200*10**(i/99))/48000;const gains=ends.map(list=>{const phase=list.reduce((sum,c)=>{const h=response(omega,c);return sum+Math.atan2(h.im,h.re);},0);return Math.abs(Math.cos(phase/2));});difference+=Math.abs(gains[0]-gains[1]);}
assert(difference>5,'Spread Curve must change the comb dry/all-pass blend response');
console.log('PASS: actual native Spread Curve coefficients, exact neutral equivalence, visual/native centre parity, unity all-pass magnitude, Q/group-delay phase derivatives, bounded plots and audible-response differences. Native listening remains separate.');
