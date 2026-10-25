import assert from 'node:assert/strict';
import fs from 'node:fs';
import {compileFilter} from './filter-fixture.mjs';
import {filterResponse,filterPlot,filterHeat,combBandBounds} from '../webui/filter-model.mjs';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8'),create=compileFilter(source);
// Compare measured complex impulse responses to the display model, including
// the native normalized bandpass, digital warping, phase and fractional comb read.
for(const sr of [44100,48000,96000]){
 for(let mode=0;mode<8;mode++){
  const f=create(sr,mode,837,.82);f.c.mix_value=1;const samples=[];
  for(let n=0;n<Math.ceil(sr*.15);n++){const [l,r]=f.step(n===0?.1:0,0);samples.push(l*10);assert.equal(r,0,'Independent stereo histories must not leak into each other');assert(Number.isFinite(l));}
  for(const hz of [100,400,837,1600,2008.8,4000,10000]){
   const w=2*Math.PI*hz/sr;let real=0,imag=0;for(let n=0;n<samples.length;n++){real+=samples[n]*Math.cos(w*n);imag-=samples[n]*Math.sin(w*n);}
   const model=filterResponse(hz,{mode,cutoff:837,resonance:.82,mix:1,sampleRate:sr});
   assert(Math.hypot(real-model.real,imag-model.imag)<2e-5,`Native response/graph mismatch: ${sr} Hz, mode ${mode}, probe ${hz}: ${real},${imag} vs ${model.real},${model.imag}`);
  }
  const off=create(sr,mode);off.p.enabled=0;off.p.drive=24;for(let n=0;n<100;n++){const l=Math.sin(n),r=Math.cos(n);assert.deepEqual(off.step(l,r),[l,r]);}
  const silence=create(sr,mode);silence.p.drive=24;for(let n=0;n<200;n++)assert.deepEqual(silence.step(0),[0,0],'New types must not generate signal from silence');
 }
 console.log(`PASS: filter ${sr} Hz, eight native complex responses match the graph, stereo separation, Off identity and silent startup.`);
}
for(const mode of [6,7]){
 const f=create(48000,mode,20,1);f.c.mix_value=1;let feedback=0,peak=0;
 for(let n=0;n<96000;n++){const [out]=f.step((n===0?.2:0)+.95*feedback);feedback=out;peak=Math.max(peak,Math.abs(out));assert(Number.isFinite(out)&&Math.abs(out)<=.20000001,'Normalized feed-forward Comb must not add gain to the feedback loop');}
 assert(peak>0&&Math.abs(feedback)<.02);
}
// Exercise fast changes without stale memories, invalid reads or NaN propagation.
const sweep=create(48000,6,20,1);let difference=0,last=0;
for(let n=0;n<24000;n++){
 if(n%300===0){sweep.p.mode=(n/300)%8;sweep.p.cutoff=n%600?20:20000;sweep.p.resonance=n%900?1:0;sweep.p.drive=n%1200?24:0;}
 const [out]=sweep.step(.1*Math.sin(n*.14));assert(Number.isFinite(out)&&Math.abs(out)<10);difference+=Math.abs(out-last);last=out;
}
assert(difference>1);
for(const sr of [44100,48000,96000])for(let mode=0;mode<8;mode++)for(const cutoff of [20,837,20000]){
 const plot=filterPlot(350,140,{mode,cutoff,resonance:1,mix:1,sampleRate:sr});assert(plot.points.every(([x,y])=>Number.isFinite(x)&&x>=0&&x<=350&&y>=6&&y<=122));
 assert(filterPlot(350,140,{mode,cutoff,resonance:1,mix:0,sampleRate:sr}).points.every(p=>p[1]===70));
}
assert.deepEqual([0,12,24].map(filterHeat),['#65d59d','#ff9d45','#ff4e40']);assert.equal(filterHeat(-1),filterHeat(0));assert.equal(filterHeat(99),filterHeat(24));
for(const width of [100,250,350,600])for(const cutoff of [20,100,400,2000])for(const mode of [6,7]){
 const settings={mode,cutoff,resonance:1,mix:.85,sampleRate:48000},plot=filterPlot(width,140,settings);
 if(plot.dense){assert(plot.dense.limit/cutoff<=12);assert.equal(plot.points.at(-1)[0],plot.dense.from);assert.equal(plot.dense.upper.at(-1)[0],width);assert(plot.points.every(p=>p[0]<=plot.dense.from));}
 for(let i=0;i<200;i++){const hz=20*1000**(i/199),response=filterResponse(hz,settings).magnitude,bounds=combBandBounds(hz,settings);assert(response>=bounds.low-1e-12&&response<=bounds.high+1e-12,'Dense display bounds must contain the real fractional-delay response');}
}
const registry=JSON.parse(fs.readFileSync(new URL('../webui/parameters.json',import.meta.url),'utf8'));assert.equal(registry.parameters.find(p=>p.id===75).options.length,8);assert.equal(registry.random[75].RANDOM_HI,7);assert(registry.random[75].MORPH_ALLOWED&&registry.random[75].RANDOM_ALLOWED);
console.log('PASS: Comb feedback bounds, mode/cutoff/drive automation, bounded plots, Drive heat and all eight native modes in Random/Morph policy. Native REAPER compilation/listening remains separate.');
