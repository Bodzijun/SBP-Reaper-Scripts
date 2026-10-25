import assert from 'node:assert/strict';
import fs from 'node:fs';
import {compileShift} from './shift-fixture.mjs';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8'),create=compileShift(source),old=compileShift(source,{legacy:true});
for(const sr of [44100,48000,96000]){
 const a=create(sr),b=old(sr);
 for(let i=0;i<16000;i++){
  if(i%4000===0)a.p.hz=b.p.hz=[500,-750,0,5000][i/4000];
  const l=.3*Math.sin(i*.037)+.1*Math.cos(i*.011),r=.2*Math.sin(i*.057),aa=a.step(l,r),bb=b.step(l,r);
  assert.deepEqual(aa,bb,'Neutral extra controls must exactly reproduce the previous shifter, including automation');
 }
 const quiet=create(sr,200,30,0,.8);for(let i=0;i<100;i++)assert.deepEqual(quiet.step(0),[0,0],'Oscillators must not generate audio without input');
 console.log(`PASS: actual Shift arithmetic ${sr} Hz, exact legacy-default equivalence and silent input.`);
}
const cases=[
 {hz:500,offset:200,sideband:1,mix:1},
 {hz:500,offset:200,sideband:-1,mix:1},
 {hz:500,offset:200,sideband:0,mix:1},
 {hz:500,offset:200,sideband:.5,mix:.4},
 {hz:500,offset:200,sideband:1,mix:0},
 {hz:0,offset:200,sideband:1,mix:1},
 {hz:200,offset:200,sideband:-1,mix:1},
 {hz:-1500,offset:0,sideband:1,mix:1}
];
for(const settings of cases){
 const d=create(48000,settings.hz,settings.offset,settings.sideband,settings.mix),channels=[[],[]];
 for(let i=0;i<24000;i++){const out=d.step(Math.sin(2*Math.PI*1000*i/48000));if(i>=12000)out.forEach((v,ch)=>channels[ch].push(v));}
 const amplitude=(ch,hz)=>{let re=0,im=0;for(let i=0;i<channels[ch].length;i++){const angle=2*Math.PI*hz*i/48000;re+=channels[ch][i]*Math.cos(angle);im-=channels[ch][i]*Math.sin(angle);}return 2*Math.hypot(re,im)/channels[ch].length;};
 for(let ch=0;ch<2;ch++){
  const shift=settings.hz+(ch?1:-1)*settings.offset;
  if(shift===0){assert(Math.abs(amplitude(ch,1000)-1)<1e-10,'A zero-shift channel must stay in true bypass while its neighbour shifts');continue;}
  const expected=new Map();for(const [hz,gain]of [[1000,1-settings.mix],[Math.abs(1000+shift),settings.mix*(1+settings.sideband)/2],[Math.abs(1000-shift),settings.mix*(1-settings.sideband)/2]])expected.set(hz,(expected.get(hz)||0)+gain);
  for(const [frequency,gain]of expected)assert(Math.abs(amplitude(ch,frequency)-gain)<.015,`Unexpected sideband/blend amplitude: ${JSON.stringify(settings)}, channel ${ch}, ${frequency} Hz`);
 }
}
for(const sr of [8000,44100,48000,96000,192000]){
 const d=create(sr,0);let previousOffset=0,previousSideband=1,previousMix=1;
 for(let i=0;i<16000;i++){
  if(i%400===0){d.p.offset=i%800?10000:-10000;d.p.sideband=i%800?10:-10;d.p.mix=i%800?10:-10;d.p.hz=i%800?5000:-5000;}
  const out=d.step(.3*Math.sin(i*.11),.2*Math.cos(i*.07));assert(out.every(x=>Number.isFinite(x)&&Math.abs(x)<2));
  assert(Math.abs(d.c.current_offset-previousOffset)<=2000*d.c.slew+1e-9);assert(Math.abs(d.c.current_sideband-previousSideband)<=2*d.c.slew+1e-9);assert(Math.abs(d.c.wet_mix-previousMix)<=d.c.slew+1e-9);
  assert(Math.abs(d.c.current_offset)<=1000&&Math.abs(d.c.current_sideband)<=1&&d.c.wet_mix>=0&&d.c.wet_mix<=1);
  assert(d.c.phase>=0&&d.c.phase<1&&d.c.phase_r>=0&&d.c.phase_r<1);
  previousOffset=d.c.current_offset;previousSideband=d.c.current_sideband;previousMix=d.c.wet_mix;
 }
}
console.log('PASS: stereo offsets, main/opposite/ring sidebands, Shift Mix, zero-channel bypass, negative folding and smoothed/clamped automation. Native REAPER compilation/listening remains separate.');
