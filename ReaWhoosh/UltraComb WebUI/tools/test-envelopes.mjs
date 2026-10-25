import assert from 'node:assert/strict';
import fs from 'node:fs';
import {compileEnvelope,createAdr} from './envelope-fixture.mjs';
import {adrValue,motionValue,envelopeModel,detectorMeter,MOTION_WINDOW_MS} from '../webui/envelope-view.mjs';
import {decodeTelemetry} from '../webui/modulation-view.mjs';
import {decodeDoubler} from '../webui/doubler-view.mjs';
const source=fs.readFileSync(new URL('../sbp_ultraComb_webui.jsfx',import.meta.url),'utf8');
for(const rate of [44100,48000,96000]){
 const quiet=createAdr(source,rate);for(let i=0;i<1000;i++)assert.equal(quiet.step(.5),0,'Off must not create modulation');
 for(const [attackCurve,decayCurve,releaseCurve] of [[-1,-1,-1],[0,0,0],[1,1,1],[-1,0,1],[1,-1,.5],[0,1,-1]]){
  const d=createAdr(source,rate,{mode:2,attack:20,decay:50,level:.4,release:80,attackCurve,decayCurve,releaseCurve});d.step();d.p.trigger++;
  for(let n=0;n<Math.ceil(rate*.18);n++){
   const out=d.step(),time=n*1000/rate,delta=5*1000/rate;
   const nearby=[adrValue(Math.max(0,time-delta),d.p),adrValue(time,d.p),adrValue(time+delta,d.p),time-delta<=20&&time+delta>=20?1:0];
   assert(out>=0&&out<=1&&Number.isFinite(out));
   assert(out>=Math.min(...nearby)-1e-8&&out<=Math.max(...nearby)+1e-8,'Native ADR must follow its target model within sample-boundary rounding');
  }
  assert.equal(d.c.stage,0);assert.equal(d.c.output,0);
 }
 const audio=createAdr(source,rate,{mode:1});for(let i=0;i<rate*.02;i++)audio.step(.01);assert.equal(audio.c.stage,0);
 for(let i=0;i<rate*.01;i++)audio.step(.5);assert(audio.c.stage>0&&audio.c.output>0);assert.equal(audio.c.armed,0);
 for(let i=0;i<rate*.08;i++)audio.step(.5);assert.equal(audio.c.armed,0,'Held audio must not continuously retrigger');
 for(let i=0;i<rate*.2;i++)audio.step(0);assert.equal(audio.c.armed,1,'Falling below the hysteresis threshold rearms audio triggering');
 const loop=createAdr(source,rate,{mode:3,attack:5,decay:5,level:1,release:10});let cycles=0,previousStage=0;
 for(let i=0;i<rate*.12;i++){loop.step();if(loop.c.stage===1&&previousStage===0)cycles++;previousStage=loop.c.stage;}
 assert(cycles>=5);loop.p.mode=2;loop.step();assert.equal(loop.c.output,0,'Switching to Manual must not hold a previous Loop value');
 // A full ping-pong cycle retraces R -> D -> A, including each non-linear curve.
 const ping=createAdr(source,rate,{mode:3,loopDirection:1,attack:40,decay:60,level:.35,release:80,attackCurve:-.5,decayCurve:.5,releaseCurve:-.25});
 const visited=new Set(),total=180;let reversals=0,lastPhase=0;
 for(let n=0;n<rate*.8;n++){
  const out=ping.step(),phase=ping.c.phase;visited.add(ping.c.stage);assert(out>=0&&out<=1&&Number.isFinite(out));
  if(ping.c.stage===4&&phase<lastPhase)reversals++;
  const time=phase*total,delta=8*1000/rate;
  const nearby=[adrValue(Math.max(0,time-delta),ping.p),adrValue(time,ping.p),adrValue(Math.min(total,time+delta),ping.p)];
  for(const knot of [0,40,100,total])if(Math.abs(time-knot)<=delta)nearby.push(adrValue(knot,ping.p));
  assert(out>=Math.min(...nearby)-1e-7&&out<=Math.max(...nearby)+1e-7,`Ping-pong mismatch: rate=${rate}, n=${n}, stage=${ping.c.stage}, age=${ping.c.age}, phase=${phase}, output=${out}, nearby=${nearby}`);
  lastPhase=phase;
 }
 assert.deepEqual([...visited].sort(),[1,2,3,4,5,6]);assert(reversals>0,'Native phase must run backwards during the reverse pass');
 ping.p.loopDirection=0;ping.step();for(let n=0;n<rate*.4;n++){ping.step();assert(ping.c.stage<=3,'Forward mode must not retain reverse stages');}
 ping.p.loopDirection=1;ping.step();ping.p.mode=0;assert.equal(ping.step(),0,'Off must stop ping-pong modulation');
 loop.p.trigger++;loop.step();for(let i=0;i<rate*.003;i++)loop.step();assert(loop.c.output>0);const before=loop.c.output;loop.p.trigger++;assert.equal(loop.step(),before,'Manual retrigger must start at the current level');
 console.log(`PASS: actual ADR ${rate} Hz, Off identity, curve/model parity, audio hysteresis, looping, Manual and continuous retrigger.`);
}
// Independent curve edits must affect only their own segment in the preview.
const shape={attack:100,decay:200,level:.4,release:300,attackCurve:0,decayCurve:0,releaseCurve:0};
// Accelerated 1 kHz control clock exercises the entire 90-second envelope.
const longAdr=createAdr(source,1000,{mode:2,attack:30000,decay:30000,level:.4,release:30000});longAdr.step();longAdr.p.trigger++;
for(let n=0;n<90010;n++){const out=longAdr.step();if([15000,45000,75000].includes(n))assert(Math.abs(out-adrValue(n,longAdr.p))<.001);assert(Number.isFinite(out)&&out>=0&&out<=1);}
assert.equal(longAdr.c.stage,0);assert.equal(longAdr.c.output,0);
const longModel=envelopeModel(350,140,{kind:'adr',mode:4,attack:30000,decay:30000,level:.4,release:30000});assert.equal(longModel.total,90000);assert.equal(longModel.points.at(-1).time,90000);
for(const settings of [shape,{...shape,attack:1,decay:1,release:1},{...shape,attack:2000,decay:4000,release:4000}]){
 const model=envelopeModel(350,140,{kind:'adr',mode:3,...settings});assert.equal(model.points.at(-1).time,model.total);assert(model.points.every(p=>p.time<=model.total),'The curve must end exactly at Release, without a trailing hold');assert.equal(model.points.at(-1).value,0);
}
for(const [key,inside,outside]of [['attackCurve',50,[200,450]],['decayCurve',200,[50,450]],['releaseCurve',450,[50,200]]]){
 const changed={...shape,[key]:1};assert.notEqual(adrValue(inside,changed),adrValue(inside,shape));for(const time of outside)assert.equal(adrValue(time,changed),adrValue(time,shape));
}
// Automated curve changes remain finite and smoothed in the real native processor.
const automated=createAdr(source,48000,{mode:3,attack:100,decay:100,release:100});
let previous=0,maxStep=0;for(let n=0;n<48000;n++){if(n%1200===0){automated.p.attackCurve=n%2400?-1:1;automated.p.decayCurve=-automated.p.attackCurve;automated.p.releaseCurve=automated.p.attackCurve;}const out=automated.step();assert(Number.isFinite(out)&&out>=0&&out<=1);maxStep=Math.max(maxStep,Math.abs(out-previous));previous=out;}
assert(maxStep<.15,'Curve automation must not create abrupt full-depth jumps');
const init=compileEnvelope(source,'uc_pitch_motion_init'),process=compileEnvelope(source,'uc_pitch_motion_process'),c={};for(const key of [...init.instances,...process.instances])c[key]=0;
init.fn.call(c,48000,0,1,.5,0);for(let n=0;n<48000*.5;n++){process.fn.call(c,0,0,1,.5,250,2,-24,1,0);assert(Math.abs(c.visual_motion-motionValue(n/48,250))<1e-9);}
const short=envelopeModel(350,140,{kind:'motion',decay:100,enabled:true}),long=envelopeModel(350,140,{kind:'motion',decay:800,enabled:true});
assert.equal(short.window,MOTION_WINDOW_MS);assert.equal(long.window,MOTION_WINDOW_MS);assert(long.xFor(long.total)>short.xFor(short.total),'Decay must change the visible length/slope on a fixed time axis');
const meter=detectorMeter(140,-24,10**(-18/20),10**(-12/20));assert(Math.abs(meter.levelDb+18)<1e-12&&meter.yFor(meter.levelDb)<meter.thresholdY);
assert.equal(detectorMeter(140,-24).levelDb,null,'No telemetry must not invent an input meter');
const packet=new Float32Array(40);packet[32]=.2;packet[33]=.4;packet[34]=.5;packet[35]=.7;packet[36]=1;packet[37]=.3;packet[38]=.6;packet[39]=.125;
const states=decodeTelemetry({data:packet});assert.equal(states.length,9);assert.equal(states[3].age,.125);assert(states[3].level>.19&&states[8].value>.69&&states[8].enabled);assert(decodeDoubler({data:packet}));
const metadata=JSON.parse(fs.readFileSync(new URL('../sbp_ultraComb_webui.json',import.meta.url),'utf8')).JSFX_WebUI;
assert.equal(metadata.native.streams[2].channels,1);assert(source.includes('reaweb_jsfx_publish(2,WEB_MOD,542,1,web_sample_clock);'),'Control vector must obey the pinned SDK maximum of 32 transport channels');
const live=new Float32Array(42);live[40]=-12;live[41]=-30;const thresholds=decodeTelemetry({data:live});assert.equal(thresholds[3].threshold,-12);assert.equal(thresholds[8].threshold,-30);
assert(metadata.native.commands.some(c=>c.id==='adrTrigger'));assert(source.includes('reaweb_jsfx_id==3 ? atomic_add(ui_adr_fire,1)'));
console.log('PASS: actual Motion decay/model agreement, fixed time axis, real detector meter geometry, ADR telemetry and valid SDK transport dimensions. Native host/listening acceptance remains separate.');
