import assert from 'node:assert/strict';
import fs from 'node:fs';
import {compileDoubler} from './doubler-fixture.mjs';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8');
const create=compileDoubler(source);
function silence(d,seconds){for(let i=0;i<Math.ceil(d.c.sample_rate*seconds);i++){const out=d.step(0);assert(out.every(Number.isFinite));}}
function burst(d){const out=[],rate=d.c.sample_rate;for(let i=0;i<Math.ceil(rate*.09);i++){const t=i/rate,envelope=(1-Math.exp(-t/.001))*Math.exp(-t/.025);out.push(d.step(.5*envelope*(Math.sin(2*Math.PI*203*t)+.3*Math.sin(2*Math.PI*571*t))));}for(let i=0;i<Math.ceil(rate*.14);i++)out.push(d.step(0));return out;}
function difference(a,b){return Math.max(...a.map((v,i)=>Math.max(Math.abs(v[0]-b[i][0]),Math.abs(v[1]-b[i][1]))));}
function sideEnergy(out){let m=0,s=0;for(const [l,r]of out){m+=((l+r)/2)**2;s+=((l-r)/2)**2;}return s/m;}
for(const rate of [44100,48000,96000]){
 const d=create(rate,12,9);let resets=0;for(const voice of [d.c.left_voice,d.c.right_voice]){const reset=voice.uc_double_voice_reset;voice.uc_double_voice_reset=function(){resets++;return reset.call(this);};}
 assert(d.c.left_voice.buffer.scopebuffermax<=d.c.right_voice.buffer.scopebuffer,'Pitch histories must be disjoint');
 assert(d.c.right_voice.buffer.scopebuffermax<d.c.width_buffer);
 silence(d,.4);const a=burst(d);silence(d,.31);const b=burst(d);silence(d,.73);const c=burst(d);
 assert(difference(a,b)<1e-9&&difference(a,c)<1e-9,'After a drained gap, the same high-pitch burst must start with the same width/waveform');
 assert.equal(resets,6,'Rearm each voice once per real quiet gap');
 assert(sideEnergy(a)>.01,'High-pitch opposing-detune voices must retain stereo energy on this tonal burst');
 assert(d.c.left_voice.semi<12&&d.c.right_voice.semi>12);
 assert.notEqual(d.c.left_voice.readHead1,d.c.right_voice.readHead1,'Voices must not share the pitch-head trajectory');
 assert(Math.max(...a.flat().map(Math.abs))<1,'Default voice blend must remain bounded');
 // A short pause / zero crossing must not reset and chop an existing tail.
 d.step(.1);const count=resets;silence(d,.02);d.step(.1);assert.equal(resets,count);
 silence(d,.4);assert.equal(d.c.armed,1);assert.equal(d.c.out_l,0);assert.equal(d.c.out_r,0);
 d.params.enabled=0;for(let i=0;i<Math.ceil(rate*.3);i++)d.step(.1,-.2);
 for(let i=0;i<100;i++){const [l,r]=d.step(.1,-.2);assert(Math.abs(l-.1)<1e-12&&Math.abs(r+.2)<1e-12,'Disabled Doubler must preserve stereo input');}
 console.log(`PASS: actual Doubler arithmetic ${rate} Hz, high-pitch repeatability, independent +/- detune, quiet-gap rearm and disabled passthrough.`);
}
for(const semi of [-24,0,24])for(const cents of [-50,0,50]){
 const d=create(48000,semi,cents,1);d.params.mix=1;d.params.delay=100;
 for(let i=0;i<16000;i++){if(i===8000){d.params.semi=-semi;d.params.cents=-cents;d.params.width=0;}const out=d.step(.2*Math.sin(i*.13),.2*Math.cos(i*.07));assert(out.every(x=>Number.isFinite(x)&&Math.abs(x)<2));}
 assert(Math.abs(d.c.left_voice.semi)<=24.8&&Math.abs(d.c.right_voice.semi)<=24.8);
}
// Prove the repeated-burst check detects free-running heads after quiet gaps.
const regression=createRegression();silence(regression,.4);const oldA=burst(regression);silence(regression,.73);const oldB=burst(regression);assert(difference(oldA,oldB)>1e-4,'Fixture must detect missing quiet-gap rearming');
function createRegression(){return compileDoubler(source.replace('quiet_count>=quiet_needed ? armed=1;','quiet_count>=quiet_needed ? armed=0;'))(48000,12,9);}
console.log('PASS: extreme pitches/detunes, delay/width automation and missing-rearm regression. Native REAPER compilation/audio acceptance remains separate.');
