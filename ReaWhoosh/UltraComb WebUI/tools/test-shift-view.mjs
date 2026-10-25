import assert from 'node:assert/strict';
import fs from 'node:fs';
import {shiftModel,ShiftMotion} from '../webui/shift-view.mjs';
import {compileShift} from './shift-fixture.mjs';
const comparable=({xFor,...model})=>model;
for(const width of [250,350,475,600])for(const height of [110,140])for(const shift of [-5000,-1000,-.1,0,.1,1000,5000]){
 const model=shiftModel(width,height,{shift,time:1});
 assert(model.partials.every(p=>p.output===Math.abs(p.input+shift)));
 assert(model.partials.every(p=>p.xInput>=model.left&&p.xInput<=model.right&&p.xOutput>=model.left&&p.xOutput<=model.right));
 assert(model.inputY>18&&model.outputY<height-20);
 assert.deepEqual(comparable(shiftModel(width,height,{shift,time:1,motion:false})),comparable(shiftModel(width,height,{shift,time:2,motion:false})),'Reduced motion must freeze the rotor and travel dots');
 if(shift===0)assert.deepEqual(comparable(shiftModel(width,height,{shift,time:1})),comparable(shiftModel(width,height,{shift,time:2})),'Zero Shift must not invent oscillator motion');
 else assert.notEqual(model.phase,shiftModel(width,height,{shift,time:1.1}).phase);
}
const positive=shiftModel(350,140,{shift:100,time:.1}),negative=shiftModel(350,140,{shift:-100,time:.1});
assert(Math.abs(positive.phase+negative.phase-1)<1e-12,'Rotor direction must follow signed frequency');
assert(shiftModel(350,140,{shift:-1000}).partials[0].folded);
// Check that the schematic's direction agrees with the existing native shifter.
// Translate its real arithmetic bodies, including EEL power '^' (not JS XOR).
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8');
const create=compileShift(source);
for(const shift of [-1500,-500,500]){
 const d=create(48000,shift),output=[];
 for(let i=0;i<24000;i++){const out=d.step(Math.sin(2*Math.PI*1000*i/48000),0);if(i>=12000)output.push(out[0]);}
 const amplitude=hz=>{let re=0,im=0;for(let i=0;i<output.length;i++){const angle=2*Math.PI*hz*i/48000;re+=output[i]*Math.cos(angle);im-=output[i]*Math.sin(angle);}return 2*Math.hypot(re,im)/output.length;};
 assert(amplitude(Math.abs(1000+shift))>.8,'Signed/folded reference must match the actual native output frequency');
 assert(amplitude(Math.abs(1000-shift))<.03,'Image sideband must be lower than the shifted reference');
}
for(const sampleRate of [8000,44100,48000,96000])for(const offset of [-1000,0,1000])for(const sideband of [-1,0,1])for(const mix of [0,.5,1]){
 const m=shiftModel(350,140,{shift:5000,offset,sideband,mix,sampleRate});
 for(const ch of m.channels){
  assert(Math.abs(ch.hz)<=sampleRate*.45);
  assert(Math.abs(ch.weights.main+ch.weights.opposite+ch.weights.dry-1)<1e-12);
  assert(ch.partials.every(p=>p.output>=0&&p.output<=sampleRate/2&&p.opposite>=0&&p.opposite<=sampleRate/2));
 }
}
const zeroChannel=shiftModel(350,140,{shift:200,offset:200,sideband:0,mix:1});assert.deepEqual(zeroChannel.channels[0].weights,{main:0,opposite:0,dry:1});
const motion=new ShiftMotion(),first=motion.apply(shiftModel(350,140,{shift:1}),100),before=first.phase;
const after=motion.apply(shiftModel(350,140,{shift:5000}),100.02);assert(Math.abs(after.phase-before)<.03,'Changing Shift must not teleport the preview rotor');
const frozen=motion.apply(shiftModel(350,140,{shift:5000,motion:false}),101,false);assert.equal(frozen.phase,after.phase);
console.log('PASS: signed/folded Frequency Shift geometry, reduced motion, zero-shift idle and agreement with actual native shifter arithmetic. Native host compilation remains separate.');
